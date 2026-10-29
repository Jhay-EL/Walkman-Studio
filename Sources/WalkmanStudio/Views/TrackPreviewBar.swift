import SwiftUI
import AppKit

public struct TrackPreviewBar: View {
    @ObservedObject var player = AudioPlayerService.shared
    @ObservedObject var progress = AudioPlayerService.shared.progress
    var libraryTracks: [Track] = []
    var isInspectorPresented: Bool = false
    let onOpenInspector: () -> Void
    var onOpenFullScreen: () -> Void = {}

    @State private var dragTime: Double? = nil
    @State private var isArtworkHovered: Bool = false
    @State private var lastNonZeroVolume: Float = 0.8
    @State private var isVolumeExpanded: Bool = false
    @State private var isVolumeHovered: Bool = false
    @State private var isVolumeSpeakerHovered: Bool = false
    @State private var isEnlargeHovered: Bool = false

    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return "0:00" }
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            // LEFT: Transport controls (Shuffle, Prev, Play/Pause, Next, Repeat)
            transportControlsZone

            // CENTER: Now Playing Display Pod
            centerDisplayPod

            // RIGHT: Volume & Details Inspector Toggle
            trailingControlsZone
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(height: 56)
        .background(
            ZStack {
                // Native Apple macOS ultra-thin frosted glass material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Translucent obsidian veil (reveals UI elements underneath while keeping controls sharp)
                Color(red: 16 / 255, green: 17 / 255, blue: 21 / 255)
                    .opacity(0.24)

                // Subtle white ambient reflection
                Color.white
                    .opacity(0.04)

                // Top specular refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.28), location: 0.0),
                            .init(color: .white.opacity(0.06), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.24), location: 0.0),
                            .init(color: .white.opacity(0.10), location: 0.5),
                            .init(color: .white.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 1.5)
        .onExitCommand {
            if isVolumeExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isVolumeExpanded = false
                }
            }
        }
    }

    // MARK: - Left: Transport Controls
    private var transportControlsZone: some View {
        HStack(spacing: 10) {
            // Shuffle
            LiquidGlassPlayerButton(
                systemName: "shuffle",
                size: 13,
                isActive: player.isShuffle,
                helpText: player.isShuffle ? "Shuffle: On" : "Shuffle: Off",
                action: { player.isShuffle.toggle() }
            )

            // Previous
            LiquidGlassPlayerButton(
                systemName: "backward.fill",
                size: 14.5,
                isActive: false,
                isDisabled: player.currentTrack == nil && libraryTracks.isEmpty && player.effectiveQueue.isEmpty,
                helpText: "Previous track (F7 or Cmd+Left)",
                action: { player.playPrevious() }
            )

            // Play / Pause prominent circular button
            PlayPauseCircleButton(
                isPlaying: player.isPlaying,
                isEnabled: player.currentTrack != nil || !libraryTracks.isEmpty || !player.effectiveQueue.isEmpty,
                action: {
                    if player.currentTrack != nil {
                        player.togglePlayPause()
                    } else if let first = libraryTracks.first ?? player.effectiveQueue.first {
                        player.play(track: first, in: !libraryTracks.isEmpty ? libraryTracks : player.effectiveQueue)
                    }
                }
            )

            // Next
            LiquidGlassPlayerButton(
                systemName: "forward.fill",
                size: 14.5,
                isActive: false,
                isDisabled: player.currentTrack == nil && libraryTracks.isEmpty && player.effectiveQueue.isEmpty,
                helpText: "Next track (F9 or Cmd+Right)",
                action: { player.playNext() }
            )

            // Repeat
            LiquidGlassPlayerButton(
                systemName: "repeat",
                size: 13,
                isActive: player.isRepeat,
                helpText: player.isRepeat ? "Repeat: On" : "Repeat: Off",
                action: { player.isRepeat.toggle() }
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Center: Display Pod
    private var centerDisplayPod: some View {
        ZStack {
            // Display pod inner glass styling (translucent)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.16), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )

            if let track = player.currentTrack {
                activeTrackDisplay(for: track)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
            } else {
                idleDisplay
                    .padding(.horizontal, 14)
            }
        }
        .frame(minWidth: 160, maxWidth: .infinity)
        .frame(height: 42)
        .contentShape(Rectangle())
        .onTapGesture {
            if isVolumeExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isVolumeExpanded = false
                }
            }
        }
    }

    @ViewBuilder
    private func activeTrackDisplay(for track: Track) -> some View {
        let isHiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
        let curTime = dragTime ?? progress.currentTime
        let durTime = progress.duration
        let timeWidth: CGFloat = durTime >= 3600 ? 54 : (durTime >= 600 ? 40 : 34)

        HStack(spacing: 8) {
            // Artwork thumbnail (clickable to open inspector)
            Button(action: onOpenInspector) {
                ZStack {
                    if let img = player.currentCoverArt {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        TrackCoverThumbnail(track: track, size: 34, isPlaying: player.isPlaying)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            isArtworkHovered ? Color.white.opacity(0.40) : (player.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.12)),
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(isArtworkHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isArtworkHovered)
            }
            .buttonStyle(.plain)
            .help("Click to view full metadata details & artwork")
            .onHover { h in
                isArtworkHovered = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Metadata & Scrubber
            VStack(alignment: .leading, spacing: 2) {
                // Top row: Title, Artist, Hi-Res Badge
                HStack(spacing: 5) {
                    Text(track.title.isEmpty ? "Unknown Title" : track.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(player.isPlaying ? .white : Color(white: 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if !track.artist.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .fixedSize()

                        Text(track.artist)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(0.5)
                    }

                    if isHiRes {
                        Text("HR")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundStyle(WalkmanTheme.hiResGoldLight)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(WalkmanTheme.hiResGold.opacity(0.20))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.6))
                            .fixedSize()
                    }
                }

                // Bottom row: Timeline scrubber with unclipped responsive monospaced counters
                HStack(spacing: 6) {
                    Text(formatTime(curTime))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: timeWidth, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)

                    Slider(
                        value: Binding(
                            get: { dragTime ?? progress.currentTime },
                            set: { newTime in dragTime = newTime }
                        ),
                        in: 0...max(1.0, progress.duration),
                        onEditingChanged: { editing in
                            if editing {
                                player.isSeeking = true
                            } else {
                                if let target = dragTime {
                                    player.seek(to: target)
                                }
                                dragTime = nil
                            }
                        }
                    )
                    .controlSize(.mini)
                    .tint(isHiRes ? WalkmanTheme.hiResGold : WalkmanTheme.silver)

                    Text(formatTime(durTime))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: timeWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var idleDisplay: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))

            Text("Walkman Studio")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right: Responsive Apple-Style Volume & Enlarge Controls
    private var trailingControlsZone: some View {
        HStack(spacing: 6) {
            // Fluid responsive volume adjustment capsule
            volumeControlPod

            // Enlarge Button (Full Screen Now Playing with Artwork & Live Lyrics)
            enlargeButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var enlargeButton: some View {
        Button(action: onOpenFullScreen) {
            ZStack {
                // Liquid glass background capsule
                Capsule()
                    .fill(Color.white.opacity(isEnlargeHovered ? 0.12 : 0.05))

                // Specular top highlight sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isEnlargeHovered ? 0.28 : 0.10), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())

                // Hairline border
                Capsule()
                    .strokeBorder(
                        Color.white.opacity(isEnlargeHovered ? 0.24 : 0.10),
                        lineWidth: 0.85
                    )

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnlargeHovered ? .white : WalkmanTheme.silverLight)
            }
            .frame(width: 30, height: 30)
            .shadow(color: Color.black.opacity(isEnlargeHovered ? 0.28 : 0.0), radius: 4, x: 0, y: 1.5)
            .scaleEffect(isEnlargeHovered ? 1.07 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isEnlargeHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePlayerButtonStyle())
        .help("Full Screen Player (Artwork & Live Lyrics)")
        .onHover { h in
            isEnlargeHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var speakerIconName: String {
        if player.volume <= 0.001 {
            return "speaker.slash.fill"
        } else if player.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    private func toggleMute() {
        if player.volume > 0.001 {
            lastNonZeroVolume = player.volume
            player.volume = 0.0
        } else {
            player.volume = lastNonZeroVolume > 0.05 ? lastNonZeroVolume : 0.8
        }
    }

    @ViewBuilder
    private var volumeControlPod: some View {
        HStack(spacing: isVolumeExpanded ? 8 : 0) {
            if isVolumeExpanded {
                VolumeCapsuleSlider(volume: $player.volume)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .trailing))
                        )
                    )
            }

            // Speaker Icon Button
            Button(action: {
                if NSEvent.modifierFlags.contains(.option) {
                    toggleMute()
                } else if !isVolumeExpanded {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        isVolumeExpanded = true
                    }
                } else {
                    if player.volume <= 0.001 {
                        toggleMute()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            isVolumeExpanded = false
                        }
                    }
                }
            }) {
                Image(systemName: speakerIconName)
                    .font(.system(size: 13, weight: isVolumeExpanded ? .semibold : .medium))
                    .foregroundStyle(
                        player.volume <= 0.001
                            ? Color.white.opacity(0.45)
                            : (isVolumeSpeakerHovered || isVolumeHovered ? .white : WalkmanTheme.silverLight)
                    )
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TactilePlayerButtonStyle())
            .help(
                isVolumeExpanded
                    ? (player.volume <= 0.001 ? "Unmute" : "Close Volume Slider (⌥+Click to Mute)")
                    : "Adjust Volume (Click to expand, ⌥+Click to Mute)"
            )
            .onHover { h in
                isVolumeSpeakerHovered = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.leading, isVolumeExpanded ? 10 : 3)
        .padding(.trailing, isVolumeExpanded ? 8 : 3)
        .padding(.vertical, 3)
        .frame(height: 30)
        .background(
            ZStack {
                if isVolumeExpanded {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(Capsule())
                } else {
                    Capsule()
                        .fill(Color.white.opacity(isVolumeHovered ? 0.09 : 0.05))

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isVolumeHovered ? 0.22 : 0.08), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 7)
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    Color.white.opacity(isVolumeExpanded ? 0.24 : (isVolumeHovered ? 0.20 : 0.10)),
                    lineWidth: 0.85
                )
        )
        .clipShape(Capsule())
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.16)) {
                isVolumeHovered = h
            }
        }
    }
}

// MARK: - Subviews & Styles

struct TactilePlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct VolumeCapsuleSlider: View {
    @Binding var volume: Float
    let totalWidth: CGFloat = 82
    let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clampedVol = CGFloat(max(0.0, min(1.0, volume)))
            let fillWidth = max(0, w * clampedVol)

            ZStack(alignment: .leading) {
                // Background Track (unfilled)
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(height: trackHeight)

                // Filled Active Level Track
                Rectangle()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: trackHeight)
            }
            .frame(height: trackHeight)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newPct = Float(max(0.0, min(1.0, value.location.x / w)))
                        volume = newPct
                    }
            )
        }
        .frame(width: totalWidth, height: 22)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct LiquidGlassPlayerButton: View {
    let systemName: String
    let size: CGFloat
    let isActive: Bool
    var isDisabled: Bool = false
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Liquid glass background capsule on hover
                Capsule()
                    .fill(Color.white.opacity(isHovered && !isDisabled ? 0.11 : 0.0))

                if isHovered && !isDisabled {
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.22), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 6)
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())

                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }

                Image(systemName: systemName)
                    .font(.system(size: size, weight: isActive ? .bold : .medium))
                    .foregroundStyle(
                        isDisabled ? Color.white.opacity(0.20) :
                        (isActive ? WalkmanTheme.hiResGold : (isHovered ? .white : Color.white.opacity(0.70)))
                    )
            }
            .frame(width: 30, height: 30)
            .scaleEffect(isHovered && !isDisabled ? 1.08 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePlayerButtonStyle())
        .disabled(isDisabled)
        .help(helpText)
        .onHover { h in
            guard !isDisabled else { return }
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct PlayPauseCircleButton: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isEnabled ?
                                (isHovered ? [Color.white, Color(white: 0.94)] : [Color(white: 0.96), Color(white: 0.84)]) :
                                [Color.white.opacity(0.3), Color.white.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 36, height: 36)

                // Specular top highlight
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.50 : 0.30), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
                    .offset(x: isPlaying ? 0 : 1)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.50 : 0.30), lineWidth: 0.85)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.20), radius: isHovered ? 4 : 2, x: 0, y: 1.5)
            .scaleEffect(isHovered && isEnabled ? 1.07 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.70), value: isHovered)
        }
        .buttonStyle(TactilePlayerButtonStyle())
        .disabled(!isEnabled)
        .keyboardShortcut(.space, modifiers: [])
        .help(isPlaying ? "Pause (Space)" : "Play (Space)")
        .onHover { h in
            guard isEnabled else { return }
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
