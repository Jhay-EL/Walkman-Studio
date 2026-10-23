import SwiftUI
import AppKit
import AVFoundation
import MediaToolbox

// MARK: - Real-Time Preview Audio DSP Controller
final class PreviewDSPController: @unchecked Sendable {
    var channelMode: AudioChannelMode = .original
    var gainDb: Double = 0.0
    var fadeInDuration: Double = 0.0
    var fadeOutDuration: Double = 0.0
    var startTime: Double = 0.0
    var endTime: Double = 0.0
    var totalDuration: Double = 0.0
    var mode: AudioTrimMode = .trim
    var isAuditioning: Bool = false
    var sampleRate: Double = 44100.0

    // Plain primitive timestamp updated on main thread — NEVER query AVPlayer inside CoreAudio thread!
    var currentTime: Double = 0.0
    var isPlaying: Bool = false
}

private func createPreviewAudioTap(controller: PreviewDSPController) -> MTAudioProcessingTap? {
    let unmanaged = Unmanaged.passRetained(controller)
    let clientInfo = unmanaged.toOpaque()

    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: clientInfo,
        init: { tap, clientInfo, tapStorageOut in
            tapStorageOut.pointee = clientInfo
        },
        finalize: { tap in
            let storage = MTAudioProcessingTapGetStorage(tap)
            Unmanaged<PreviewDSPController>.fromOpaque(storage).release()
        },
        prepare: { tap, maxFrames, processingFormat in
            let storage = MTAudioProcessingTapGetStorage(tap)
            let dsp = Unmanaged<PreviewDSPController>.fromOpaque(storage).takeUnretainedValue()
            dsp.sampleRate = processingFormat.pointee.mSampleRate
        },
        unprepare: { _ in },
        process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
            let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
            guard status == noErr else { return }

            let storage = MTAudioProcessingTapGetStorage(tap)
            let dsp = Unmanaged<PreviewDSPController>.fromOpaque(storage).takeUnretainedValue()

            let frames = Int(numberFramesOut.pointee)
            guard frames > 0 else { return }

            let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
            guard abl.count > 0, let leftPtr = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let rightPtr: UnsafeMutablePointer<Float>? = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil

            // 1. Channel Configuration Routing
            switch dsp.channelMode {
            case .original, .stereo:
                break
            case .swapLR:
                if let right = rightPtr {
                    for i in 0..<frames {
                        let tmp = leftPtr[i]
                        leftPtr[i] = right[i]
                        right[i] = tmp
                    }
                }
            case .mono:
                if let right = rightPtr {
                    for i in 0..<frames {
                        let mono = 0.5 * (leftPtr[i] + right[i])
                        leftPtr[i] = mono
                        right[i] = mono
                    }
                }
            case .leftOnly:
                if let right = rightPtr {
                    for i in 0..<frames {
                        right[i] = leftPtr[i]
                    }
                }
            case .rightOnly:
                if let right = rightPtr {
                    for i in 0..<frames {
                        leftPtr[i] = right[i]
                    }
                }
            case .muteLeft:
                for i in 0..<frames {
                    leftPtr[i] = 0.0
                }
            case .muteRight:
                if let right = rightPtr {
                    for i in 0..<frames {
                        right[i] = 0.0
                    }
                }
            case .invertPhase:
                for i in 0..<frames {
                    leftPtr[i] = -leftPtr[i]
                }
                if let right = rightPtr {
                    for i in 0..<frames {
                        right[i] = -right[i]
                    }
                }
            }

            // 2. Gain / Boost Scaling
            let gainLinear = Float(pow(10.0, dsp.gainDb / 20.0))

            // 3. Smooth Transitions (Fade In & Fade Out)
            let baseTime = dsp.currentTime

            let sr = max(1.0, dsp.sampleRate)
            let fadeIn = dsp.fadeInDuration
            let fadeOut = dsp.fadeOutDuration
            let hasFadeIn = fadeIn > 0.01
            let hasFadeOut = fadeOut > 0.01
            let startT = dsp.startTime
            let endT = dsp.endTime

            if !hasFadeIn && !hasFadeOut && !dsp.isAuditioning {
                // Fast path: Apply gain only
                if abs(gainLinear - 1.0) > 0.001 {
                    for i in 0..<frames {
                        leftPtr[i] = max(-1.0, min(1.0, leftPtr[i] * gainLinear))
                    }
                    if let right = rightPtr {
                        for i in 0..<frames {
                            right[i] = max(-1.0, min(1.0, right[i] * gainLinear))
                        }
                    }
                }
            } else {
                // Envelope path: compute per-sample envelope
                for i in 0..<frames {
                    let sampleTime = baseTime + (Double(i) / sr)
                    var envelope: Float = 1.0

                    if dsp.mode == .trim {
                        if dsp.isAuditioning {
                            if sampleTime < startT || sampleTime > endT {
                                envelope = 0.0
                            } else {
                                if hasFadeIn && sampleTime < startT + fadeIn {
                                    let frac = Float((sampleTime - startT) / fadeIn)
                                    envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                                }
                                if hasFadeOut && sampleTime > endT - fadeOut {
                                    let frac = Float((endT - sampleTime) / fadeOut)
                                    envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                                }
                            }
                        } else {
                            if hasFadeIn && sampleTime >= startT && sampleTime < startT + fadeIn {
                                let frac = Float((sampleTime - startT) / fadeIn)
                                envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                            }
                            if hasFadeOut && sampleTime > endT - fadeOut && sampleTime <= endT {
                                let frac = Float((endT - sampleTime) / fadeOut)
                                envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                            }
                        }
                    } else {
                        // Cut mode
                        if sampleTime > startT && sampleTime < endT {
                            if dsp.isAuditioning {
                                envelope = 0.0
                            }
                        } else if hasFadeOut && sampleTime > startT - fadeOut && sampleTime <= startT {
                            let frac = Float((startT - sampleTime) / fadeOut)
                            envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                        } else if hasFadeIn && sampleTime >= endT && sampleTime < endT + fadeIn {
                            let frac = Float((sampleTime - endT) / fadeIn)
                            envelope *= sin(max(0.0, min(1.0, frac)) * .pi / 2.0)
                        }
                    }

                    let multiplier = gainLinear * envelope
                    leftPtr[i] = max(-1.0, min(1.0, leftPtr[i] * multiplier))
                    if let right = rightPtr {
                        right[i] = max(-1.0, min(1.0, right[i] * multiplier))
                    }
                }
            }
        }
    )

    var tap: MTAudioProcessingTap?
    let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
    guard err == noErr else { return nil }
    return tap
}

public struct TrimAndCutSheet: View {
    let track: Track
    let onSaved: () -> Void
    let onDismiss: () -> Void

    // Audio file specs
    @State private var sourceChannels: Int = 2
    @State private var sourceSampleRate: Double = 44100.0
    @State private var totalDuration: Double = 0.0

    // Waveform state
    @State private var waveformPeaks: [Float] = []
    @State private var isLoadingWaveform: Bool = true

    // DAW-grade Timeline Zoom & Viewport Window State
    @State private var zoomScale: CGFloat = 1.0 // 1.0x (Fit) to 8.0x
    @State private var windowStartTime: Double = 0.0 // Active viewport start time in seconds

    // Marker & Mode state
    @State private var mode: AudioTrimMode = .trim
    @State private var startTime: Double = 0.0
    @State private var endTime: Double = 0.0

    // Drag tracking for marker handles
    @State private var dragInitialStartTime: Double? = nil
    @State private var dragInitialEndTime: Double? = nil

    // Channel routing & tools state
    @State private var channelMode: AudioChannelMode = .original
    @State private var fadeInDuration: Double = 0.0
    @State private var fadeOutDuration: Double = 0.0
    @State private var gainDb: Double = 0.0
    @State private var destination: AudioSaveDestination = .overwrite
    @State private var preserveTags: Bool = true

    // In-sheet Preview Audio Player & Real-time DSP
    @State private var dspController = PreviewDSPController()
    @State private var previewPlayer: AVPlayer? = nil
    @State private var timeObserverToken: Any? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var isLoopingSelection: Bool = false
    @State private var isPlayingFromStart: Bool = false
    @State private var isAuditioningResult: Bool = false
    @State private var volume: Float = 0.8

    // Processing & feedback state
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showSuccessBanner: Bool = false

    public init(track: Track, onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.track = track
        self.onSaved = onSaved
        self.onDismiss = onDismiss
    }

    private var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }

    private var outputDuration: Double {
        if mode == .trim {
            return max(0.01, endTime - startTime)
        } else {
            return max(0.01, totalDuration - (endTime - startTime))
        }
    }

    private var durationDelta: Double {
        outputDuration - totalDuration
    }

    // Active viewport duration in seconds
    private var windowDuration: Double {
        totalDuration / Double(max(1.0, zoomScale))
    }

    private var maxWindowStartTime: Double {
        max(0.0, totalDuration - windowDuration)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    // Hero Track Summary
                    heroTrackSummary

                    // Mode Selector (Trim vs Cut)
                    modeSelectorDeck

                    // Optimized Audio Waveform & Range Selection Studio
                    waveformDeck

                    // In-sheet Playback & Preview Transport Deck
                    transportDeck

                    // Marker Stepper Fine-Tuning Deck (2 Columns)
                    markerControlsDeck

                    // Output Duration Metrics Strip
                    durationMetricsStrip

                    // Channel Routing & Enhancements (L/R Invert, Mono/Stereo, Fades, Gain)
                    channelAndEffectsDeck

                    // Output Destination & Tag Preservation Deck
                    destinationDeck
                }
                .padding(14)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Action Footer
            footerBar
        }
        // 35% Smaller Window Dimensions (Compact & Ergonomic: ~860 × 650 pt)
        .frame(minWidth: 820, idealWidth: 860, maxWidth: 920, minHeight: 610, idealHeight: 650, maxHeight: 720)
        .background(WalkmanTheme.background.ignoresSafeArea())
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: channelMode) { _, newMode in
            dspController.channelMode = newMode
        }
        .onChange(of: gainDb) { _, newGain in
            dspController.gainDb = newGain
        }
        .onChange(of: fadeInDuration) { _, newIn in
            dspController.fadeInDuration = newIn
        }
        .onChange(of: fadeOutDuration) { _, newOut in
            dspController.fadeOutDuration = newOut
        }
        .onChange(of: startTime) { _, newStart in
            dspController.startTime = newStart
        }
        .onChange(of: endTime) { _, newEnd in
            dspController.endTime = newEnd
        }
        .onChange(of: mode) { _, newMode in
            dspController.mode = newMode
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(WalkmanTheme.silverGradient)
                    .frame(width: 28, height: 28)

                Image(systemName: "scissors")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Trim & Cut Audio Studio")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Text(track.filename)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Hero Track Summary
    private var heroTrackSummary: some View {
        HStack(spacing: 12) {
            TrackCoverThumbnail(track: track, size: 52)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(track.title.isEmpty ? track.filename : track.title)
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    }
                }

                let dispArtist = track.artist.isEmpty ? "Unknown Artist" : track.artist
                let dispAlbum = track.album.isEmpty ? "Unknown Album" : track.album
                Text("\(dispArtist) — \(dispAlbum)")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(sourceChannels == 1 ? "Mono (1 ch)" : "Stereo (2 ch)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text("\(Int(sourceSampleRate / 1000.0)) kHz")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)

                    if track.bitsPerSample > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(track.bitsPerSample)-bit")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                    }

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(formatTime(totalDuration))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }

            Spacer()

            // Quick Play/Pause Hero Button
            Button(action: togglePlayPause) {
                HStack(spacing: 5) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isPlaying ? "Pause Preview" : "Play Full Track")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isPlaying ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .foregroundStyle(isPlaying ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .liquidGlass(cornerRadius: 9)
    }

    // MARK: - Mode Selector Deck
    private var modeSelectorDeck: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Trim Mode Option
                Button(action: { mode = .trim }) {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.system(size: 13, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Trim Mode")
                                .font(WalkmanFont.bodyBold)
                            Text("Keep Selection [Start → End]")
                                .font(WalkmanFont.monoSmall)
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(mode == .trim ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .foregroundStyle(mode == .trim ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(mode == .trim ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Cut Mode Option
                Button(action: { mode = .cut }) {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors.badge.ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cut Mode")
                                .font(WalkmanFont.bodyBold)
                            Text("Remove Selection & Splice")
                                .font(WalkmanFont.monoSmall)
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(mode == .cut ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .foregroundStyle(mode == .cut ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(mode == .cut ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Description Helper
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(mode.description)
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 3)
        }
    }

    // MARK: - Waveform Deck with DAW-Grade Timeline & Exact Fit
    private var waveformDeck: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Title and Zoom / Navigation Controls
            HStack(spacing: 8) {
                Text("AUDIO WAVEFORM & RANGE SELECTION")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer()

                if isLoadingWaveform {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Rendering Waveform...")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }

                // Smooth Zoom Toolbar
                HStack(spacing: 4) {
                    ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { z in
                        Button(action: { setZoom(CGFloat(z)) }) {
                            Text(z == 1.0 ? "Fit" : "\(Int(z))x")
                                .font(WalkmanFont.pillCounter)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(abs(zoomScale - CGFloat(z)) < 0.1 ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                                .foregroundStyle(abs(zoomScale - CGFloat(z)) < 0.1 ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help(z == 1.0 ? "Fit waveform exactly into window (100% full view)" : "Zoom into waveform at \(Int(z))x magnification")
                    }

                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.12))

                    // Zoom Out
                    Button(action: { setZoom(max(1.0, zoomScale - 1.0)) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomScale <= 1.01 ? Color.white.opacity(0.2) : WalkmanTheme.silverLight)
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale <= 1.01)
                    .help("Zoom Out (-)")

                    // Zoom Slider
                    Slider(
                        value: Binding(
                            get: { zoomScale },
                            set: { setZoom($0) }
                        ),
                        in: 1.0...8.0
                    )
                    .frame(width: 70)
                    .help(String(format: "Zoom: %.1fx", zoomScale))

                    // Zoom In
                    Button(action: { setZoom(min(8.0, zoomScale + 1.0)) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomScale >= 7.99 ? Color.white.opacity(0.2) : WalkmanTheme.silverLight)
                    }
                    .buttonStyle(.plain)
                    .disabled(zoomScale >= 7.99)
                    .help("Zoom In (+)")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Overview Minimap Strip (Full-track navigation)
            overviewMinimapStrip

            // Main Waveform Canvas & Range Markers (DAW-grade viewport)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .topLeading) {
                    // Background Canvas Box
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    // High-Performance Audio Waveform Canvas (100% boundary exact)
                    if !waveformPeaks.isEmpty {
                        Canvas { context, size in
                            let canvasW = size.width
                            let canvasH = size.height
                            let midY = canvasH / 2.0
                            guard canvasW > 10, canvasH > 10, totalDuration > 0 else { return }

                            let peaksCount = waveformPeaks.count
                            let step: CGFloat = 3.0
                            let numBars = max(20, Int(canvasW / step))

                            for b in 0..<numBars {
                                let barFrac = Double(b) / Double(numBars)
                                let barTime = windowStartTime + barFrac * windowDuration
                                let songFrac = barTime / totalDuration
                                let sampleIdx = min(peaksCount - 1, max(0, Int(songFrac * Double(peaksCount))))
                                let peak = CGFloat(waveformPeaks[sampleIdx])
                                let barH = max(3.0, peak * (canvasH - 16))

                                let x = CGFloat(b) * (canvasW / CGFloat(numBars))
                                let actualBarW = max(1.2, (canvasW / CGFloat(numBars)) - 0.8)

                                let isInSelection = barTime >= startTime && barTime <= endTime
                                let color = barColor(forSelection: isInSelection)

                                let rect = CGRect(
                                    x: x,
                                    y: midY - barH / 2.0,
                                    width: actualBarW,
                                    height: barH
                                )
                                context.fill(Path(roundedRect: rect, cornerRadius: 1.0), with: .color(color))
                            }
                        }
                    }

                    // Selection Range Overlay Box & Inactive Regions
                    let selStartX = timeToX(startTime, width: w)
                    let selEndX = timeToX(endTime, width: w)
                    let clampedStartX = max(0.0, min(w, selStartX))
                    let clampedEndX = max(0.0, min(w, selEndX))
                    let selWidth = max(0.0, clampedEndX - clampedStartX)

                    if mode == .trim {
                        // Inactive unselected region before Start Marker (trimmed out)
                        if clampedStartX > 0 {
                            Rectangle()
                                .fill(Color.black.opacity(0.35))
                                .frame(width: clampedStartX, height: h)
                                .offset(x: 0, y: 0)
                        }

                        // Inactive unselected region after End Marker (trimmed out)
                        if clampedEndX < w {
                            Rectangle()
                                .fill(Color.black.opacity(0.35))
                                .frame(width: w - clampedEndX, height: h)
                                .offset(x: clampedEndX, y: 0)
                        }

                        // Active Selection Highlight
                        if selWidth > 0 {
                            Rectangle()
                                .fill(WalkmanTheme.hiResGold.opacity(0.07))
                                .frame(width: selWidth, height: h)
                                .offset(x: clampedStartX, y: 0)
                        }
                    } else {
                        // Cut mode: highlighted excised region
                        if selWidth > 0 {
                            Rectangle()
                                .fill(Color.red.opacity(0.22))
                                .frame(width: selWidth, height: h)
                                .offset(x: clampedStartX, y: 0)
                                .overlay(
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(Color.red.opacity(0.85))
                                        Text("CUT REGION")
                                            .font(WalkmanFont.badge)
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.red.opacity(0.95))
                                    }
                                )
                        }
                    }

                    // Start Marker Line & Handle (Aligned to exact sub-pixel coordinate)
                    if startTime >= windowStartTime - 0.5 && startTime <= windowStartTime + windowDuration + 0.5 {
                        let mX = timeToX(startTime, width: w)
                        let lineX = max(0.0, min(w - 2.0, mX - 1.0))
                        let badgeW: CGFloat = 54.0
                        let badgeH: CGFloat = 18.0
                        let badgeX = max(0.0, min(w - badgeW, mX - badgeW / 2.0))

                        // 1. Exact Vertical Gold Line
                        Rectangle()
                            .fill(WalkmanTheme.hiResGoldLight)
                            .frame(width: 2.0, height: h)
                            .shadow(color: WalkmanTheme.hiResGold.opacity(0.75), radius: 2.5, x: 0, y: 0)
                            .offset(x: lineX, y: 0)

                        // 2. Start Badge Handle (Center is anchored directly to gold line)
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.right.square.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                            Text("START")
                                .font(WalkmanFont.badge)
                                .fontWeight(.bold)
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                        }
                        .frame(width: badgeW, height: badgeH)
                        .background(Color.black.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5)
                                .stroke(WalkmanTheme.hiResGoldLight.opacity(0.85), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                        .offset(x: badgeX, y: 1)

                        // 3. Start Marker Badge Drag Target (Top 24pt handle)
                        let hitW: CGFloat = max(badgeW, 36.0)
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: hitW, height: 24.0)
                            .offset(x: max(0.0, min(w - hitW, mX - hitW / 2.0)), y: 0)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { val in
                                        if dragInitialStartTime == nil {
                                            dragInitialStartTime = startTime
                                        }
                                        let initial = dragInitialStartTime ?? startTime
                                        let dt = (val.translation.width / w) * windowDuration
                                        self.startTime = max(0.0, min(endTime - 0.05, initial + dt))
                                    }
                                    .onEnded { _ in
                                        dragInitialStartTime = nil
                                    }
                            )
                    }

                    // End Marker Line & Handle (Aligned to exact sub-pixel coordinate)
                    if endTime >= windowStartTime - 0.5 && endTime <= windowStartTime + windowDuration + 0.5 {
                        let mX = timeToX(endTime, width: w)
                        let lineX = max(0.0, min(w - 2.0, mX - 1.0))
                        let badgeW: CGFloat = 50.0
                        let badgeH: CGFloat = 18.0
                        let badgeX = max(0.0, min(w - badgeW, mX - badgeW / 2.0))

                        // 1. Exact Vertical Gold Line
                        Rectangle()
                            .fill(WalkmanTheme.hiResGoldLight)
                            .frame(width: 2.0, height: h)
                            .shadow(color: WalkmanTheme.hiResGold.opacity(0.75), radius: 2.5, x: 0, y: 0)
                            .offset(x: lineX, y: 0)

                        // 2. End Badge Handle (Center is anchored directly to gold line)
                        HStack(spacing: 3) {
                            Text("END")
                                .font(WalkmanFont.badge)
                                .fontWeight(.bold)
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                            Image(systemName: "chevron.left.square.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                        }
                        .frame(width: badgeW, height: badgeH)
                        .background(Color.black.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5)
                                .stroke(WalkmanTheme.hiResGoldLight.opacity(0.85), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                        .offset(x: badgeX, y: 1)

                        // 3. End Marker Badge Drag Target (Top 24pt handle)
                        let hitW: CGFloat = max(badgeW, 36.0)
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: hitW, height: 24.0)
                            .offset(x: max(0.0, min(w - hitW, mX - hitW / 2.0)), y: 0)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { val in
                                        if dragInitialEndTime == nil {
                                            dragInitialEndTime = endTime
                                        }
                                        let initial = dragInitialEndTime ?? endTime
                                        let dt = (val.translation.width / w) * windowDuration
                                        self.endTime = max(startTime + 0.05, min(totalDuration, initial + dt))
                                    }
                                    .onEnded { _ in
                                        dragInitialEndTime = nil
                                    }
                            )
                    }

                    // Playhead Cursor Needle (Mathematically aligned to currentTime)
                    if currentTime >= windowStartTime && currentTime <= windowStartTime + windowDuration {
                        let pX = timeToX(currentTime, width: w)
                        let pLineX = max(0.0, min(w - 1.5, pX - 0.75))

                        // Vertical Playhead Line
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1.5, height: h)
                            .shadow(color: Color.white.opacity(0.95), radius: 3, x: 0, y: 0)
                            .offset(x: pLineX, y: 0)

                        // Downward White Triangle Cap
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.7), radius: 1, x: 0, y: 1)
                            .frame(width: 9.0, height: 7.0)
                            .offset(x: max(0.0, min(w - 9.0, pX - 4.5)), y: 0)
                    }
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let seekTime = xToTime(val.location.x, width: w)
                            seekTo(time: seekTime)
                        }
                )
            }
            .frame(height: 95)

            // Mathematically Precise Dynamic Timeline Ruler Canvas
            accurateTimelineRuler

            // Zoom Pan Controls Bar (Visible when zoomed in)
            if zoomScale > 1.01 {
                timelinePanControlsBar
            }
        }
        .padding(10)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Overview Minimap Strip
    private var overviewMinimapStrip: some View {
        GeometryReader { miniGeo in
            let mW = miniGeo.size.width
            let mH = miniGeo.size.height

            ZStack(alignment: .leading) {
                // Background Box
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                // Minimap full-song waveform preview
                if !waveformPeaks.isEmpty {
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        let midY = h / 2.0
                        let count = waveformPeaks.count
                        let numBars = max(20, Int(w / 2.5))

                        for b in 0..<numBars {
                            let frac = Double(b) / Double(numBars)
                            let idx = min(count - 1, Int(frac * Double(count)))
                            let peak = CGFloat(waveformPeaks[idx])
                            let barH = max(2.0, peak * (h - 4))
                            let x = CGFloat(b) * (w / CGFloat(numBars))
                            let rect = CGRect(x: x, y: midY - barH / 2.0, width: max(1.0, w / CGFloat(numBars) - 0.5), height: barH)
                            context.fill(Path(rect), with: .color(Color.white.opacity(0.20)))
                        }
                    }
                }

                // Selection Highlight on Minimap
                let mStartX = max(0, min(mW, (startTime / max(0.01, totalDuration)) * mW))
                let mEndX = max(0, min(mW, (endTime / max(0.01, totalDuration)) * mW))
                let mSelW = max(0, mEndX - mStartX)
                Rectangle()
                    .fill(mode == .trim ? WalkmanTheme.hiResGold.opacity(0.35) : Color.red.opacity(0.35))
                    .frame(width: mSelW, height: mH)
                    .offset(x: mStartX)

                // Minimap Gold Boundary Lines for Start & End
                Rectangle()
                    .fill(WalkmanTheme.hiResGoldLight)
                    .frame(width: 1, height: mH)
                    .offset(x: max(0, min(mW - 1, mStartX)))

                Rectangle()
                    .fill(WalkmanTheme.hiResGoldLight)
                    .frame(width: 1, height: mH)
                    .offset(x: max(0, min(mW - 1, mEndX - 0.5)))

                // Highlighted Viewport Window (When zoomed in)
                if zoomScale > 1.01 {
                    let vStartX = (windowStartTime / max(0.01, totalDuration)) * mW
                    let vWidth = (windowDuration / max(0.01, totalDuration)) * mW
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white, lineWidth: 1.5)
                        .background(Color.white.opacity(0.12))
                        .frame(width: max(14, vWidth), height: mH)
                        .offset(x: min(mW - max(14, vWidth), max(0, vStartX)))
                }

                // Playhead on Minimap (Centered on mPlayheadX)
                let mPlayheadX = (currentTime / max(0.01, totalDuration)) * mW
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5, height: mH)
                    .offset(x: max(0, min(mW - 1.5, mPlayheadX - 0.75)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let frac = max(0.0, min(1.0, val.location.x / mW))
                        let clickedTime = frac * totalDuration
                        let maxStart = max(0.0, totalDuration - windowDuration)
                        windowStartTime = max(0.0, min(maxStart, clickedTime - windowDuration / 2.0))
                    }
            )
        }
        .frame(height: 16)
    }

    // MARK: - Mathematically Precise Timeline Ruler Canvas
    private var accurateTimelineRuler: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let canvasW = size.width
                guard canvasW > 10, totalDuration > 0 else { return }

                let pxPerSec = canvasW / windowDuration
                // Target ~80-110 points between major time marks
                let rawInterval = 85.0 / pxPerSec
                let possibleIntervals: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]
                let majorInterval = possibleIntervals.first(where: { $0 >= rawInterval }) ?? 60.0

                let firstTick = ceil(windowStartTime / majorInterval) * majorInterval
                var t = firstTick

                while t <= windowStartTime + windowDuration + 0.001 && t <= totalDuration {
                    let x = timeToX(t, width: canvasW)

                    // Draw tick line
                    let tickRect = CGRect(x: x - 0.5, y: 0, width: 1.0, height: 4.0)
                    context.fill(Path(tickRect), with: .color(Color.white.opacity(0.35)))

                    // Format label: MM:SS or MM:SS.s
                    let totalSec = Int(t)
                    let ms = Int((t - Double(totalSec)) * 1000)
                    let s = totalSec % 60
                    let m = (totalSec / 60) % 60
                    let hrs = totalSec / 3600

                    let timeStr: String
                    if majorInterval < 1.0 {
                        timeStr = String(format: "%02d:%02d.%01d", m, s, ms / 100)
                    } else if hrs > 0 {
                        timeStr = String(format: "%d:%02d:%02d", hrs, m, s)
                    } else {
                        timeStr = String(format: "%02d:%02d", m, s)
                    }

                    let label = context.resolve(
                        Text(timeStr)
                            .font(WalkmanFont.monoSmall)
                            .foregroundColor(Color.white.opacity(0.55))
                    )
                    let textWidth: CGFloat = 40.0
                    let labelX = max(0.0, min(canvasW - textWidth, x - textWidth / 2.0))
                    context.draw(label, at: CGPoint(x: labelX + textWidth / 2.0, y: 11.0))

                    t += majorInterval
                }

                // Ruler indicator for Start Marker (Gold pip)
                if startTime >= windowStartTime && startTime <= windowStartTime + windowDuration {
                    let sX = timeToX(startTime, width: canvasW)
                    let startRect = CGRect(x: sX - 1.0, y: 0, width: 2.0, height: 5.0)
                    context.fill(Path(startRect), with: .color(WalkmanTheme.hiResGoldLight))
                }

                // Ruler indicator for End Marker (Gold pip)
                if endTime >= windowStartTime && endTime <= windowStartTime + windowDuration {
                    let eX = timeToX(endTime, width: canvasW)
                    let endRect = CGRect(x: eX - 1.0, y: 0, width: 2.0, height: 5.0)
                    context.fill(Path(endRect), with: .color(WalkmanTheme.hiResGoldLight))
                }

                // Ruler indicator for Playhead (White pip)
                if currentTime >= windowStartTime && currentTime <= windowStartTime + windowDuration {
                    let cX = timeToX(currentTime, width: canvasW)
                    let curRect = CGRect(x: cX - 0.75, y: 0, width: 1.5, height: 6.0)
                    context.fill(Path(curRect), with: .color(Color.white))
                }
            }
        }
        .frame(height: 18)
    }

    // MARK: - Zoom Pan Controls Bar
    private var timelinePanControlsBar: some View {
        HStack(spacing: 8) {
            // Jump to Playhead
            Button(action: centerOnPlayhead) {
                HStack(spacing: 3) {
                    Image(systemName: "scope")
                        .font(.system(size: 9.5))
                    Text("Playhead")
                        .font(WalkmanFont.badge)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Center viewport on playhead position")

            // Jump to Start Marker
            Button(action: centerOnStartMarker) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.to.line")
                        .font(.system(size: 9.5))
                    Text("Start")
                        .font(WalkmanFont.badge)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Center viewport on Start Marker")

            // Jump to End Marker
            Button(action: centerOnEndMarker) {
                HStack(spacing: 3) {
                    Text("End")
                        .font(WalkmanFont.badge)
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 9.5))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Center viewport on End Marker")

            Spacer()

            // Pan Left Button
            Button(action: panLeft) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(.plain)
            .help("Scroll Viewport Left")

            // Timeline Pan Slider
            Slider(value: $windowStartTime, in: 0...max(0.001, maxWindowStartTime))
                .frame(width: 140)
                .help("Timeline Pan Slider")

            // Pan Right Button
            Button(action: panRight) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(.plain)
            .help("Scroll Viewport Right")
        }
        .padding(.top, 2)
    }

    private func barColor(forSelection: Bool) -> Color {
        if mode == .trim {
            return forSelection ? WalkmanTheme.silverLight : Color.white.opacity(0.18)
        } else {
            return forSelection ? Color.red.opacity(0.60) : WalkmanTheme.silverLight
        }
    }

    // Helper math to map time to screen X
    private func timeToX(_ time: Double, width: CGFloat) -> CGFloat {
        guard windowDuration > 0 else { return 0 }
        let fraction = (time - windowStartTime) / windowDuration
        return CGFloat(fraction) * width
    }

    // Helper math to map screen X to time
    private func xToTime(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return windowStartTime }
        let fraction = Double(x / width)
        return windowStartTime + fraction * windowDuration
    }

    // MARK: - Transport Deck with "Play from Start Marker"
    private var transportDeck: some View {
        HStack(spacing: 12) {
            // Playhead Time Readout
            VStack(alignment: .leading, spacing: 1) {
                Text("PLAYHEAD")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(formatTime(currentTime))
                    .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 85, alignment: .leading)

            Spacer()

            // Main Transport Buttons
            HStack(spacing: 7) {
                // Seek to 0:00
                Button(action: { seekTo(time: 0) }) {
                    Image(systemName: "backward.to.line.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Jump to beginning (0:00)")

                // Jump Playhead to Start Marker
                Button(action: { seekTo(time: startTime) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.left.to.line.compact")
                            .font(.system(size: 11, weight: .bold))
                        Text("Start")
                            .font(WalkmanFont.badge)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Jump playhead to Start Marker")

                // Step -5s
                Button(action: { seekTo(time: max(0, currentTime - 5.0)) }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Rewind 5 seconds")

                // Main Play / Pause
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(WalkmanTheme.silverGradient)
                }
                .buttonStyle(.plain)
                .help("Play / Pause from current playhead (Space)")

                // Step +5s
                Button(action: { seekTo(time: min(totalDuration, currentTime + 5.0)) }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Forward 5 seconds")

                // Jump Playhead to End Marker
                Button(action: { seekTo(time: endTime) }) {
                    HStack(spacing: 2) {
                        Text("End")
                            .font(WalkmanFont.badge)
                        Image(systemName: "arrow.right.to.line.compact")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Jump playhead to End Marker")
            }
            .foregroundStyle(WalkmanTheme.silverLight)

            Spacer()

            // Play from Start Marker, Audition, and Loop Controls
            HStack(spacing: 8) {
                // Play from Start Marker Button
                Button(action: playFromStartMarker) {
                    HStack(spacing: 5) {
                        Image(systemName: isPlayingFromStart ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isPlayingFromStart ? "Playing Range" : "Play from Start Marker")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isPlayingFromStart ? WalkmanTheme.hiResGoldGradient : WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Starts playback at the Start Marker and plays strictly between Start and End markers")

                // Audition Result Button
                Button(action: toggleAuditionResult) {
                    HStack(spacing: 4) {
                        Image(systemName: isAuditioningResult ? "stop.fill" : (mode == .trim ? "waveform.badge.magnifyingglass" : "scissors"))
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isAuditioningResult ? "Stop" : (mode == .trim ? "Audition" : "Cut Audition"))
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isAuditioningResult ? WalkmanTheme.hiResGoldGradient : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .foregroundStyle(isAuditioningResult ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(mode == .trim ? "Play strictly the selected region [Start → End]" : "Play track preview with the cut section skipped!")

                // Loop Toggle
                Button(action: { isLoopingSelection.toggle() }) {
                    Image(systemName: isLoopingSelection ? "repeat.1" : "repeat")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isLoopingSelection ? WalkmanTheme.hiResGoldLight : .secondary)
                }
                .buttonStyle(.plain)
                .help("Loop playback continuously between Start and End markers")

                // Volume Slider
                HStack(spacing: 4) {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                    Slider(value: $volume, in: 0...1) { _ in
                        previewPlayer?.volume = volume
                    }
                    .frame(width: 55)
                }
            }
        }
        .padding(10)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Marker Stepper Controls (2 Columns)
    private var markerControlsDeck: some View {
        HStack(spacing: 12) {
            // Start Marker Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "chevron.right.square.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WalkmanTheme.hiResGoldLight)
                    Text("START MARKER")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Spacer()

                    Button("Set to 0:00") {
                        startTime = 0.0
                    }
                    .font(WalkmanFont.monoSmall)
                    .buttonStyle(.plain)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }

                HStack(alignment: .center) {
                    Text(formatTime(startTime))
                        .font(Font.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    Spacer()

                    // Play from Start Marker shortcut
                    Button(action: playFromStartMarker) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("Play Here")
                        }
                        .font(WalkmanFont.calloutBold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Seek playhead to Start Marker and play")

                    Button(action: { startTime = max(0, min(currentTime, endTime - 0.01)) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9.5))
                            Text("Playhead")
                        }
                        .font(WalkmanFont.calloutMedium)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Set Start Marker to current playback cursor")
                }

                // Fine-tuning buttons
                HStack(spacing: 4) {
                    stepperBtn(title: "-5s") { startTime = max(0, startTime - 5.0) }
                    stepperBtn(title: "-1s") { startTime = max(0, startTime - 1.0) }
                    stepperBtn(title: "-0.1s") { startTime = max(0, startTime - 0.1) }
                    stepperBtn(title: "+0.1s") { startTime = min(endTime - 0.05, startTime + 0.1) }
                    stepperBtn(title: "+1s") { startTime = min(endTime - 0.05, startTime + 1.0) }
                    stepperBtn(title: "+5s") { startTime = min(endTime - 0.05, startTime + 5.0) }
                }
            }
            .padding(10)
            .liquidGlass(cornerRadius: 10)

            // End Marker Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "chevron.left.square.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WalkmanTheme.hiResGoldLight)
                    Text("END MARKER")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Spacer()

                    Button("Set to End") {
                        endTime = totalDuration
                    }
                    .font(WalkmanFont.monoSmall)
                    .buttonStyle(.plain)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }

                HStack(alignment: .center) {
                    Text(formatTime(endTime))
                        .font(Font.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    Spacer()

                    // Play Pre-roll shortcut
                    Button(action: playPreRollToEnd) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("Last 3s")
                        }
                        .font(WalkmanFont.calloutBold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Play the last 3 seconds leading up to End Marker to check cut boundary")

                    Button(action: { endTime = min(totalDuration, max(currentTime, startTime + 0.01)) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9.5))
                            Text("Playhead")
                        }
                        .font(WalkmanFont.calloutMedium)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Set End Marker to current playback cursor")
                }

                // Fine-tuning buttons
                HStack(spacing: 4) {
                    stepperBtn(title: "-5s") { endTime = max(startTime + 0.05, endTime - 5.0) }
                    stepperBtn(title: "-1s") { endTime = max(startTime + 0.05, endTime - 1.0) }
                    stepperBtn(title: "-0.1s") { endTime = max(startTime + 0.05, endTime - 0.1) }
                    stepperBtn(title: "+0.1s") { endTime = min(totalDuration, endTime + 0.1) }
                    stepperBtn(title: "+1s") { endTime = min(totalDuration, endTime + 1.0) }
                    stepperBtn(title: "+5s") { endTime = min(totalDuration, endTime + 5.0) }
                }
            }
            .padding(10)
            .liquidGlass(cornerRadius: 10)
        }
    }

    private func stepperBtn(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WalkmanFont.monoSmall)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration Metrics Strip
    private var durationMetricsStrip: some View {
        HStack(spacing: 16) {
            metricItem(label: "ORIGINAL DURATION", value: formatTime(totalDuration), color: .secondary)

            Divider()
                .frame(height: 20)
                .overlay(Color.white.opacity(0.1))

            metricItem(label: "SELECTED SPAN", value: formatTime(endTime - startTime), color: WalkmanTheme.silverLight)

            Divider()
                .frame(height: 20)
                .overlay(Color.white.opacity(0.1))

            metricItem(label: "RESULT OUTPUT DURATION", value: formatTime(outputDuration), color: WalkmanTheme.hiResGoldLight)

            Spacer()

            // Net change badge
            let pct = totalDuration > 0 ? (durationDelta / totalDuration) * 100.0 : 0
            HStack(spacing: 4) {
                Image(systemName: durationDelta <= 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 9.5))
                Text(String(format: "%@ (%.1f%%)", formatTime(abs(durationDelta)), pct))
                    .font(WalkmanFont.monoSmall)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(durationDelta <= 0 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(durationDelta <= 0 ? Color.green : Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 8)
    }

    private func metricItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(WalkmanFont.badge)
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text(value)
                .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // MARK: - Channel Routing & Effects Deck
    private var channelAndEffectsDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUDIO CHANNEL ROUTING & ENHANCEMENTS")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(WalkmanTheme.silverMuted)

            HStack(spacing: 12) {
                // Channel Routing Selector
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: channelMode.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(WalkmanTheme.silverLight)
                        Text("Channel Configuration")
                            .font(WalkmanFont.subheadlineMedium)
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $channelMode) {
                        ForEach(AudioChannelMode.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    // Visual routing indicator
                    HStack(spacing: 6) {
                        switch channelMode {
                        case .original:
                            Text("Source layout preserved (\(sourceChannels == 1 ? "Mono" : "Stereo"))")
                        case .swapLR:
                            Text("Swaps channels: [ Left ] ⇄ [ Right ]")
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                        case .mono:
                            Text("Downmixes to 1-channel Mono: [ (L + R) / 2 ]")
                                .foregroundStyle(WalkmanTheme.silverLight)
                        case .stereo:
                            Text("Forces 2-channel Stereo output")
                        case .leftOnly:
                            Text("Duplicates Left channel: [ L ] → Both Ears")
                        case .rightOnly:
                            Text("Duplicates Right channel: [ R ] → Both Ears")
                        case .muteLeft:
                            Text("Mutes Left channel: [ Muted ] | [ Right ]")
                                .foregroundStyle(Color.red.opacity(0.85))
                        case .muteRight:
                            Text("Mutes Right channel: [ Left ] | [ Muted ]")
                                .foregroundStyle(Color.red.opacity(0.85))
                        case .invertPhase:
                            Text("Inverts electrical phase: -180° Polarity Flip")
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Fades & Transitions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smooth Transitions (Fades)")
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        // Fade In
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fade In")
                                .font(WalkmanFont.badge)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Picker("", selection: $fadeInDuration) {
                                Text("None (0s)").tag(0.0)
                                Text("0.10s").tag(0.10)
                                Text("0.25s").tag(0.25)
                                Text("0.50s").tag(0.50)
                                Text("1.00s").tag(1.00)
                                Text("2.00s").tag(2.00)
                                Text("3.00s").tag(3.00)
                                Text("5.00s").tag(5.00)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        // Fade Out
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fade Out")
                                .font(WalkmanFont.badge)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Picker("", selection: $fadeOutDuration) {
                                Text("None (0s)").tag(0.0)
                                Text("0.10s").tag(0.10)
                                Text("0.25s").tag(0.25)
                                Text("0.50s").tag(0.50)
                                Text("1.00s").tag(1.00)
                                Text("2.00s").tag(2.00)
                                Text("3.00s").tag(3.00)
                                Text("5.00s").tag(5.00)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        // Gain / Boost
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gain / Boost")
                                .font(WalkmanFont.badge)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Picker("", selection: $gainDb) {
                                Text("-12 dB").tag(-12.0)
                                Text("-6 dB").tag(-6.0)
                                Text("-3 dB").tag(-3.0)
                                Text("0 dB (Normal)").tag(0.0)
                                Text("+2 dB").tag(2.0)
                                Text("+3 dB").tag(3.0)
                                Text("+4 dB").tag(4.0)
                                Text("+6 dB (2x Boost)").tag(6.0)
                                Text("+9 dB").tag(9.0)
                                Text("+12 dB (4x Boost)").tag(12.0)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Destination Deck
    private var destinationDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAVE & EXPORT DESTINATION")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(WalkmanTheme.silverMuted)

            HStack(spacing: 10) {
                ForEach(AudioSaveDestination.allCases) { opt in
                    Button(action: { destination = opt }) {
                        HStack(spacing: 6) {
                            Image(systemName: opt.icon)
                                .font(.system(size: 11.5))
                            Text(opt.title)
                                .font(WalkmanFont.bodyMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 8)
                        .background(destination == opt ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .foregroundStyle(destination == opt ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(destination == opt ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Warning note if overwrite
            if destination == .overwrite {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 10.5))
                    Text("Overwriting will safely replace the track file on disk and preserve all ID3v2.3 / Vorbis tags and embedded album art.")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            } else if destination == .newFile {
                HStack(spacing: 5) {
                    Image(systemName: "doc.badge.plus")
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .font(.system(size: 10.5))
                    Text("Creates a new copy alongside the original file with '[Trimmed]' appended to the filename.")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }

            // Tag preservation checkbox
            Toggle(isOn: $preserveTags) {
                HStack(spacing: 5) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10))
                    Text("Preserve Track Metadata (Title, Artist, Album, Year) and Baseline RGB JPEG Cover Art")
                        .font(WalkmanFont.calloutMedium)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
        .padding(10)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 10) {
            // Status / Error message
            if let err = errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
                Text(err)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
            } else if let status = statusMessage {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(status)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)
            } else if showSuccessBanner {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                Text("Track processed successfully!")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(Color.green)
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .font(WalkmanFont.calloutMedium)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .buttonStyle(.plain)
            .disabled(isProcessing)

            Button(action: executeProcess) {
                HStack(spacing: 6) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Processing...")
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(mode == .trim ? "Apply & Trim Track" : "Apply & Cut Track")
                    }
                }
                .font(WalkmanFont.calloutBold)
                .padding(.horizontal, 16)
                .padding(.vertical, 6.5)
                .background(WalkmanTheme.silverGradient)
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WalkmanTheme.background)
    }

    // MARK: - Zoom & Navigation Logic
    private func setZoom(_ newZoom: CGFloat) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            let clamped = max(1.0, min(8.0, newZoom))
            let oldWindowDur = windowDuration
            let oldCenter = windowStartTime + oldWindowDur / 2.0

            zoomScale = clamped

            if clamped <= 1.01 {
                windowStartTime = 0.0
            } else {
                let newWindowDur = totalDuration / Double(clamped)
                let maxStart = max(0.0, totalDuration - newWindowDur)
                windowStartTime = max(0.0, min(maxStart, oldCenter - newWindowDur / 2.0))
            }
        }
    }

    private func centerOnPlayhead() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let maxStart = max(0.0, totalDuration - windowDuration)
            windowStartTime = max(0.0, min(maxStart, currentTime - windowDuration / 2.0))
        }
    }

    private func centerOnStartMarker() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let maxStart = max(0.0, totalDuration - windowDuration)
            windowStartTime = max(0.0, min(maxStart, startTime - windowDuration / 2.0))
        }
    }

    private func centerOnEndMarker() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let maxStart = max(0.0, totalDuration - windowDuration)
            windowStartTime = max(0.0, min(maxStart, endTime - windowDuration / 2.0))
        }
    }

    private func panLeft() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            windowStartTime = max(0.0, windowStartTime - windowDuration * 0.25)
        }
    }

    private func panRight() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            windowStartTime = min(maxWindowStartTime, windowStartTime + windowDuration * 0.25)
        }
    }

    // MARK: - Playback Logic
    private func setupInitialState() {
        totalDuration = max(0.1, track.durationSeconds)
        startTime = 0.0
        endTime = totalDuration
        windowStartTime = 0.0
        zoomScale = 1.0

        // Pause main app player so audio device isn't contended
        if AudioPlayerService.shared.isPlaying {
            AudioPlayerService.shared.pause()
        }

        let fileURL = URL(fileURLWithPath: track.fullPath)

        // Inspect hardware properties
        if let info = TrimCutService.shared.inspectAudio(fileURL: fileURL) {
            sourceChannels = info.channelCount
            sourceSampleRate = info.sampleRate
            if info.duration > 0 {
                totalDuration = info.duration
                endTime = info.duration
            }
        }

        // Setup local AVPlayer for preview with Real-Time DSP Audio Tap
        dspController.channelMode = channelMode
        dspController.gainDb = gainDb
        dspController.fadeInDuration = fadeInDuration
        dspController.fadeOutDuration = fadeOutDuration
        dspController.startTime = startTime
        dspController.endTime = endTime
        dspController.totalDuration = totalDuration
        dspController.mode = mode
        dspController.isAuditioning = false

        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)

        if let tap = createPreviewAudioTap(controller: dspController) {
            let inputParams = AVMutableAudioMixInputParameters()
            inputParams.audioTapProcessor = tap
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParams]
            item.audioMix = audioMix
        }

        previewPlayer = AVPlayer(playerItem: item)
        previewPlayer?.volume = volume
        dspController.currentTime = startTime

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = previewPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            let cur = CMTimeGetSeconds(time)
            self.currentTime = cur
            self.dspController.currentTime = cur

            // Smoothly auto-pan viewport window to follow playhead when zoomed in
            if self.isPlaying && self.zoomScale > 1.05 {
                let winDur = self.windowDuration
                let maxStart = self.maxWindowStartTime
                if cur > self.windowStartTime + winDur * 0.95 {
                    self.windowStartTime = min(maxStart, cur - winDur * 0.1)
                } else if cur < self.windowStartTime {
                    self.windowStartTime = max(0.0, cur - winDur * 0.1)
                }
            }

            // Check boundary limits during playback
            if self.isPlayingFromStart || self.isAuditioningResult {
                if self.mode == .trim {
                    if cur >= self.endTime {
                        if self.isLoopingSelection {
                            self.seekTo(time: self.startTime)
                        } else {
                            self.previewPlayer?.pause()
                            self.isPlaying = false
                            self.isPlayingFromStart = false
                            self.isAuditioningResult = false
                            self.dspController.isAuditioning = false
                            self.dspController.isPlaying = false
                            self.seekTo(time: self.startTime)
                        }
                    }
                } else {
                    // Cut mode auditioning: skip from start to end
                    if cur >= self.startTime && cur < self.endTime {
                        self.seekTo(time: self.endTime)
                    } else if cur >= self.totalDuration {
                        if self.isLoopingSelection {
                            self.seekTo(time: 0.0)
                        } else {
                            self.previewPlayer?.pause()
                            self.isPlaying = false
                            self.isPlayingFromStart = false
                            self.isAuditioningResult = false
                            self.dspController.isAuditioning = false
                            self.dspController.isPlaying = false
                            self.seekTo(time: 0.0)
                        }
                    }
                }
            } else if self.isLoopingSelection {
                if cur >= self.endTime {
                    self.seekTo(time: self.startTime)
                }
            }
        }

        // Load high-resolution waveform (600 peaks)
        Task {
            let peaks = await TrimCutService.shared.generateWaveform(fileURL: fileURL, barCount: 600)
            await MainActor.run {
                self.waveformPeaks = peaks
                self.isLoadingWaveform = false
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            previewPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        previewPlayer?.pause()
        previewPlayer = nil
        isPlaying = false
        isPlayingFromStart = false
        isAuditioningResult = false
        dspController.isAuditioning = false
        dspController.isPlaying = false
    }

    private func togglePlayPause() {
        guard let p = previewPlayer else { return }
        isPlayingFromStart = false
        isAuditioningResult = false
        dspController.isAuditioning = false
        if isPlaying {
            p.pause()
            isPlaying = false
            dspController.isPlaying = false
        } else {
            // If near end, loop back to start marker
            if currentTime >= endTime - 0.05 {
                seekTo(time: startTime)
            }
            dspController.isPlaying = true
            p.play()
            isPlaying = true
        }
    }

    /// Plays audio starting exactly at the Start Marker and tracks to the End Marker
    private func playFromStartMarker() {
        guard let p = previewPlayer else { return }
        if isPlayingFromStart && isPlaying {
            p.pause()
            isPlaying = false
            isPlayingFromStart = false
            dspController.isAuditioning = false
            dspController.isPlaying = false
        } else {
            isPlayingFromStart = true
            isAuditioningResult = true
            dspController.isAuditioning = true
            dspController.isPlaying = true
            seekTo(time: startTime)
            centerOnStartMarker()
            p.play()
            isPlaying = true
        }
    }

    /// Plays pre-roll (last 3 seconds) before the End Marker to audition boundary
    private func playPreRollToEnd() {
        guard let p = previewPlayer else { return }
        isPlayingFromStart = true
        isAuditioningResult = true
        dspController.isAuditioning = true
        dspController.isPlaying = true
        let preRollTime = max(startTime, endTime - 3.0)
        seekTo(time: preRollTime)
        centerOnEndMarker()
        p.play()
        isPlaying = true
    }

    private func toggleAuditionResult() {
        guard let p = previewPlayer else { return }
        if isAuditioningResult && isPlaying {
            p.pause()
            isPlaying = false
            isAuditioningResult = false
            isPlayingFromStart = false
            dspController.isAuditioning = false
            dspController.isPlaying = false
        } else {
            isAuditioningResult = true
            isPlayingFromStart = true
            dspController.isAuditioning = true
            dspController.isPlaying = true
            if mode == .trim {
                seekTo(time: startTime)
                centerOnStartMarker()
            } else {
                seekTo(time: 0.0)
            }
            p.play()
            isPlaying = true
        }
    }

    private func seekTo(time: Double) {
        let clamped = max(0.0, min(totalDuration, time))
        currentTime = clamped
        dspController.currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        previewPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Execution & Processing
    private func executeProcess() {
        guard !isProcessing else { return }

        // Pause preview player before processing
        previewPlayer?.pause()
        isPlaying = false
        isPlayingFromStart = false
        isAuditioningResult = false

        errorMessage = nil
        statusMessage = "Preparing audio processor..."
        isProcessing = true

        let selectedDest = destination

        // Handle export to Mac via NSSavePanel
        if selectedDest == .exportMac {
            let savePanel = NSSavePanel()
            savePanel.title = "Export Trimmed Audio"
            savePanel.prompt = "Export"
            savePanel.canCreateDirectories = true

            let ext = URL(fileURLWithPath: track.fullPath).pathExtension
            savePanel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .audio]

            let cleanTitle = track.title.isEmpty ? track.filename : track.title
            savePanel.nameFieldStringValue = "\(cleanTitle) [Trimmed].\(ext)"

            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    self.runProcessingTask(targetURL: targetURL)
                } else {
                    self.isProcessing = false
                    self.statusMessage = nil
                }
            }
        } else {
            runProcessingTask(targetURL: nil)
        }
    }

    private func runProcessingTask(targetURL: URL?) {
        let opts = TrimCutOptions(
            mode: mode,
            startTime: startTime,
            endTime: endTime,
            totalDuration: totalDuration,
            channelMode: channelMode,
            fadeInDuration: fadeInDuration,
            fadeOutDuration: fadeOutDuration,
            gainDb: gainDb,
            destination: destination,
            customOutputURL: targetURL,
            preserveTags: preserveTags
        )

        Task {
            do {
                _ = try await TrimCutService.shared.processAudio(
                    track: track,
                    options: opts,
                    progressHandler: { msg in
                        Task { @MainActor in
                            self.statusMessage = msg
                        }
                    }
                )

                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = nil
                    self.showSuccessBanner = true

                    // Trigger parent refresh
                    self.onSaved()

                    // Auto-dismiss after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.onDismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Time Formatter
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00.000" }
        let totalMs = Int(seconds * 1000)
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let s = totalSec % 60
        let m = (totalSec / 60) % 60
        let h = totalSec / 3600

        if h > 0 {
            return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
        } else {
            return String(format: "%02d:%02d.%03d", m, s, ms)
        }
    }
}
