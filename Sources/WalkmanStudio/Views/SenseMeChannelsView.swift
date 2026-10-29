import SwiftUI
import AppKit
import ImageIO

// =============================================================================
// SONY SENSME™ CHANNELS ARCHITECTURE
// Authentic recreation of Sony Walkman 12 Tone Acoustic Mood & Time Channels
// With 3D Stacked Card Carousel Slider & Integrated Bottom Tracks List
// =============================================================================

public enum SenseMeChannelCategory: String, CaseIterable, Identifiable, Sendable {
    case timeOfDay = "Time of Day"
    case moodAndStyle = "Mood & Style"
    case special = "Global Playback"

    public var id: String { rawValue }
}

public struct SenseMeChannel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: SenseMeChannelCategory
    public let subtitle: String
    public let description: String
    public let icon: String
    public let gradientColors: [Color]
    public let artworkFilename: String
    public let hourRange: Range<Int>?

    public var isTimeOfDay: Bool {
        category == .timeOfDay
    }

    public func isCurrentlyActive(at hour: Int = Calendar.current.component(.hour, from: Date())) -> Bool {
        guard let range = hourRange else { return false }
        return range.contains(hour)
    }

    // Official Sony Walkman Channels Definition
    public static let allChannels: [SenseMeChannel] = [
        // ---------------------------------------------------------------------
        // 1. Time of Day Channels (5 Channels)
        // ---------------------------------------------------------------------
        SenseMeChannel(
            id: "morning",
            name: "Morning",
            category: .timeOfDay,
            subtitle: "05:00 – 10:00 • Fresh & Upbeat",
            description: "Gentle, uplifting morning melodies and crisp acoustic rhythms to ease into the day.",
            icon: "sun.horizon.fill",
            gradientColors: [Color(red: 0.96, green: 0.65, blue: 0.35), Color(red: 0.88, green: 0.38, blue: 0.22)],
            artworkFilename: "senseme_morning.png",
            hourRange: 5..<10
        ),
        SenseMeChannel(
            id: "daytime",
            name: "Daytime",
            category: .timeOfDay,
            subtitle: "10:00 – 17:00 • Active & Vibrant",
            description: "Bright, dynamic tracks and driving beats that keep you energized throughout the afternoon.",
            icon: "sun.max.fill",
            gradientColors: [Color(red: 0.98, green: 0.76, blue: 0.20), Color(red: 0.88, green: 0.44, blue: 0.12)],
            artworkFilename: "senseme_daytime.png",
            hourRange: 10..<17
        ),
        SenseMeChannel(
            id: "evening",
            name: "Evening",
            category: .timeOfDay,
            subtitle: "17:00 – 21:00 • Relax & Unwind",
            description: "Smooth, mellow tunes with warm textures perfect for winding down after work.",
            icon: "sunset.fill",
            gradientColors: [Color(red: 0.88, green: 0.34, blue: 0.44), Color(red: 0.48, green: 0.18, blue: 0.58)],
            artworkFilename: "senseme_evening.png",
            hourRange: 17..<21
        ),
        SenseMeChannel(
            id: "night",
            name: "Night",
            category: .timeOfDay,
            subtitle: "21:00 – 00:00 • Lounge & Chill",
            description: "Atmospheric, late-night grooves and emotive soundscapes for relaxed listening.",
            icon: "moon.stars.fill",
            gradientColors: [Color(red: 0.36, green: 0.24, blue: 0.68), Color(red: 0.14, green: 0.12, blue: 0.38)],
            artworkFilename: "senseme_night.png",
            hourRange: 21..<24
        ),
        SenseMeChannel(
            id: "midnight",
            name: "Midnight",
            category: .timeOfDay,
            subtitle: "00:00 – 05:00 • Deep & Ambient",
            description: "Deep, calming soundscapes, gentle pianos, and slow tempos for late night contemplation.",
            icon: "sparkles",
            gradientColors: [Color(red: 0.20, green: 0.20, blue: 0.46), Color(red: 0.08, green: 0.08, blue: 0.20)],
            artworkFilename: "senseme_midnight.png",
            hourRange: 0..<5
        ),

        // ---------------------------------------------------------------------
        // 2. Mood & Style Channels (10 Channels)
        // ---------------------------------------------------------------------
        SenseMeChannel(
            id: "energetic",
            name: "Energetic",
            category: .moodAndStyle,
            subtitle: "High Energy • Fast Tempo",
            description: "High arousal and driving rhythms (115+ BPM) engineered for workouts and peak motivation.",
            icon: "bolt.fill",
            gradientColors: [Color(red: 0.95, green: 0.24, blue: 0.24), Color(red: 0.82, green: 0.10, blue: 0.36)],
            artworkFilename: "senseme_energetic.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "relax",
            name: "Relax",
            category: .moodAndStyle,
            subtitle: "Soothing • Low Arousal",
            description: "Gentle, calming acoustics and ambient melodies (sub-105 BPM) to reduce stress and center your mind.",
            icon: "leaf.fill",
            gradientColors: [Color(red: 0.24, green: 0.72, blue: 0.56), Color(red: 0.12, green: 0.46, blue: 0.40)],
            artworkFilename: "senseme_relax.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "upbeat",
            name: "Upbeat",
            category: .moodAndStyle,
            subtitle: "Cheerful • Positive Valence",
            description: "Happy, sunny, and joyful tracks guaranteed to brighten your mood with positive valence.",
            icon: "sparkle",
            gradientColors: [Color(red: 0.96, green: 0.58, blue: 0.18), Color(red: 0.90, green: 0.38, blue: 0.28)],
            artworkFilename: "senseme_upbeat.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "mellow",
            name: "Mellow",
            category: .moodAndStyle,
            subtitle: "Warm • Introspective",
            description: "Warm mid-tempo songs with low emotional tension, comforting timbres, and reflective tones.",
            icon: "cup.and.saucer.fill",
            gradientColors: [Color(red: 0.62, green: 0.46, blue: 0.36), Color(red: 0.38, green: 0.26, blue: 0.20)],
            artworkFilename: "senseme_mellow.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "emotional",
            name: "Emotional",
            category: .moodAndStyle,
            subtitle: "Soulful • Expressive Ballads",
            description: "Deeply expressive vocal melodies, passionate ballads, and moving harmonies.",
            icon: "heart.fill",
            gradientColors: [Color(red: 0.86, green: 0.24, blue: 0.56), Color(red: 0.54, green: 0.14, blue: 0.46)],
            artworkFilename: "senseme_emotional.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "lounge",
            name: "Lounge",
            category: .moodAndStyle,
            subtitle: "Sophisticated • Mid-Tempo",
            description: "Subtle jazz, downtempo, and chillout grooves (80–118 BPM) for relaxed social atmospheres.",
            icon: "wineglass.fill",
            gradientColors: [Color(red: 0.46, green: 0.40, blue: 0.62), Color(red: 0.24, green: 0.20, blue: 0.42)],
            artworkFilename: "senseme_lounge.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "dance",
            name: "Dance",
            category: .moodAndStyle,
            subtitle: "Rhythm-Driven • 108–138 BPM",
            description: "Punchy basslines, infectious four-on-the-floor beats, and club-ready electronic tracks.",
            icon: "music.note",
            gradientColors: [Color(red: 0.86, green: 0.18, blue: 0.76), Color(red: 0.46, green: 0.08, blue: 0.66)],
            artworkFilename: "senseme_dance.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "extreme",
            name: "Extreme",
            category: .moodAndStyle,
            subtitle: "Intense • Hard & Heavy",
            description: "Max arousal, relentless overdrive, heavy distortion, and aggressive beats.",
            icon: "flame.fill",
            gradientColors: [Color(red: 0.82, green: 0.14, blue: 0.14), Color(red: 0.42, green: 0.04, blue: 0.10)],
            artworkFilename: "senseme_extreme.png",
            hourRange: nil
        ),
        // ---------------------------------------------------------------------
        // 3. Special / Global Channel (1 Channel)
        // ---------------------------------------------------------------------
        SenseMeChannel(
            id: "shuffle_all",
            name: "Shuffle All Songs",
            category: .special,
            subtitle: "All Analyzed 12-Tone Tracks",
            description: "Continuously shuffles every 12 Tone / SensMe analyzed track in your library.",
            icon: "shuffle",
            gradientColors: [WalkmanTheme.hiResGold, Color(red: 0.76, green: 0.54, blue: 0.14)],
            artworkFilename: "senseme_shuffle_all.png",
            hourRange: nil
        )
    ]
}

// =============================================================================
// SENSEME ARTWORK RESOLVER
// High-Performance Artwork Resolver with Downsampling Cache & Multi-Path Fallback
// =============================================================================

public final class SenseMeArtworkResolver: @unchecked Sendable {
    public static let shared = SenseMeArtworkResolver()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    private init() {}

    public func image(for channel: SenseMeChannel) -> NSImage? {
        image(for: channel.id, channelName: channel.name)
    }

    public func image(for channelId: String, channelName: String? = nil) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[channelId] {
            return cached
        }

        // Build exhaustive candidate filename variations
        var candidates: [String] = []
        if let name = channelName {
            candidates.append("\(name).jpg")
            candidates.append("\(name).jpeg")
            candidates.append("\(name).png")
            candidates.append("\(name.lowercased()).jpg")
            candidates.append("\(name.lowercased()).jpeg")
            candidates.append("\(name.lowercased()).png")
        }
        if channelId == "shuffle_all" {
            candidates.append("Shuffle all songs.jpg")
            candidates.append("Shuffle all songs.jpeg")
            candidates.append("Shuffle all songs.png")
            candidates.append("Shuffle All Songs.jpg")
            candidates.append("Shuffle All Songs.jpeg")
            candidates.append("Shuffle All Songs.png")
            candidates.append("shuffle_all.jpg")
            candidates.append("shuffle_all.png")
        }
        candidates.append("\(channelId).jpg")
        candidates.append("\(channelId).jpeg")
        candidates.append("\(channelId).png")
        candidates.append("\(channelId.capitalized).jpg")
        candidates.append("\(channelId.capitalized).png")
        candidates.append("senseme_\(channelId).jpg")
        candidates.append("senseme_\(channelId).png")

        // 1. Check App Bundle Resources
        for fn in candidates {
            if let img = NSImage(named: fn) {
                cache[channelId] = img
                return img
            }
            if let path = Bundle.main.path(forResource: fn, ofType: nil),
               let img = loadThumbnail(from: URL(fileURLWithPath: path)) {
                cache[channelId] = img
                return img
            }
        }

        // 2. Candidate Directories
        var candidateDirs: [URL] = []

        // In-App Resources directory and subfolders
        if let resURL = Bundle.main.resourceURL {
            candidateDirs.append(resURL.appendingPathComponent("senseme"))
            candidateDirs.append(resURL.appendingPathComponent("SensMe Channel cover"))
            candidateDirs.append(resURL)
        }

        // Project / Development Directory
        candidateDirs.append(URL(fileURLWithPath: "/Users/workstation/Documents/Projects/walkman-studio/assets/SensMe Channel cover"))
        candidateDirs.append(URL(fileURLWithPath: "assets/SensMe Channel cover"))

        // User Custom Directories
        candidateDirs.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".walkman_studio/senseme"))
        candidateDirs.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/WalkmanStudio/SenseMe"))

        for dir in candidateDirs {
            for fn in candidates {
                let fileUrl = dir.appendingPathComponent(fn)
                if FileManager.default.fileExists(atPath: fileUrl.path),
                   let img = loadThumbnail(from: fileUrl) {
                    cache[channelId] = img
                    return img
                }
            }
        }

        return nil
    }

    private func loadThumbnail(from url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width / 2, height: cgThumb.height / 2))
        }
        return NSImage(contentsOf: url)
    }
}

// =============================================================================
// ANIMATED LIVE EQUALIZER BARS
// =============================================================================

public struct EqualizerLiveBars: View {
    var color: Color = WalkmanTheme.hiResGold
    var barCount: Int = 4
    @State private var heights: [CGFloat] = [0.35, 0.75, 0.50, 0.85]

    public init(color: Color = WalkmanTheme.hiResGold, barCount: Int = 4) {
        self.color = color
        self.barCount = barCount
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2.2, height: max(3.5, 13 * heights[idx % heights.count]))
            }
        }
        .frame(height: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.38).repeatForever(autoreverses: true)) {
                heights = [0.90, 0.25, 0.80, 0.40]
            }
        }
    }
}

// =============================================================================
// MAIN SENSEME CHANNELS VIEW
// Stacked Card Carousel Slider on Top + Full Tracklist Table on Bottom
// =============================================================================

public struct SenseMeChannelsView: View {
    @ObservedObject private var localLibrary = LocalMusicLibraryService.shared
    @ObservedObject private var player = AudioPlayerService.shared

    var onInspectTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onGoToTransfer: (() -> Void)? = nil
    var onNavigateToLocalLibrary: (() -> Void)? = nil

    @State private var activeIndex: Int = 0
    @State private var trackFilterQuery: String = ""
    @State private var dragOffset: CGFloat = 0.0
    @State private var lastStepTimestamp: TimeInterval = 0
    @State private var isStepping: Bool = false
    @State private var channelAutoPlayTask: Task<Void, Never>? = nil
    @State private var randomizedPlaylists: [String: [Track]] = [:]
    @State private var isAnalyzing: Bool = false
    @State private var analysisCurrent: Int = 0
    @State private var analysisTotal: Int = 0
    @State private var analysisTrackName: String = ""
    @State private var showAnalysisSheet: Bool = false
    @State private var analysisTask: Task<Void, Never>? = nil
    @State private var emptyChannelNotice: String? = nil
    @State private var emptyNoticeDismissTask: Task<Void, Never>? = nil

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var analyzedTracks: [Track] {
        localLibrary.tracks.filter { $0.isSenseMeAnalyzed }
    }

    private var unanalyzedTracks: [Track] {
        localLibrary.tracks.filter { !$0.isSenseMeAnalyzed }
    }

    private var displayedChannels: [SenseMeChannel] {
        SenseMeChannel.allChannels
    }

    private var selectedChannel: SenseMeChannel {
        let channels = displayedChannels
        guard !channels.isEmpty else { return SenseMeChannel.allChannels[0] }
        let safeIndex = max(0, min(channels.count - 1, activeIndex))
        return channels[safeIndex]
    }

    public init(
        onInspectTrack: ((Track) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onGoToTransfer: (() -> Void)? = nil,
        onNavigateToLocalLibrary: (() -> Void)? = nil
    ) {
        self.onInspectTrack = onInspectTrack
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
        self.onGoToTransfer = onGoToTransfer
        self.onNavigateToLocalLibrary = onNavigateToLocalLibrary
    }

    public var body: some View {
        ZStack(alignment: .top) {
            WalkmanTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Optional Analysis Alert Banner
                if !unanalyzedTracks.isEmpty && !localLibrary.tracks.isEmpty {
                    analysisNotificationBanner
                }

                // Main Viewport Content
                if localLibrary.tracks.isEmpty {
                    emptyLibraryView
                } else if analyzedTracks.isEmpty && !isAnalyzing {
                    noAnalyzedTracksView
                } else {
                    // DUAL PANE:
                    // Upper Pane = Stacked Card Carousel Slider (Bigger cards & 3D stack physics)
                    // Lower Pane = Selected Channel Tracklist & Controls
                    stackedDeckAndTracksSplitView
                }
            }

            // Floating Toast Notice Pill (when channel has no tracks or playback stopped)
            if let notice = emptyChannelNotice {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.hiResGold)

                    Text(notice)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white)

                    Button(action: {
                        withAnimation { emptyChannelNotice = nil }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.96))
                )
                .overlay(
                    Capsule()
                        .stroke(WalkmanTheme.hiResGold.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.50), radius: 8, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 14)
                .zIndex(999)
            }
        }
        .sheet(isPresented: $showAnalysisSheet) {
            batchAnalysisProgressSheet
        }
        .onChange(of: activeIndex) { newIndex in
            handleChannelSwitched(to: newIndex)
        }
        .onAppear {
            // Default select the channel matching the current time of day
            let hour = Calendar.current.component(.hour, from: Date())
            if let idx = displayedChannels.firstIndex(where: { $0.isCurrentlyActive(at: hour) }) {
                self.activeIndex = idx
            }
            _ = generateRandomizedPlaylist(for: selectedChannel)

            // Auto on-board check: if any unanalyzed tracks or legacy multi-channel tracks exist, re-analyze on-board in background
            let needsReanalysis = localLibrary.tracks.contains { tr in
                !tr.isSenseMeAnalyzed || (tr.senseMeChannels.contains("Morning") && tr.senseMeChannels.contains("Midnight") && tr.senseMeChannels.contains("Daytime"))
            }
            if needsReanalysis {
                Task {
                    await localLibrary.analyzeLocalTracksWithSenseMe(forceReanalyzeAll: true) { _, _, _ in }
                    await MainActor.run {
                        randomizedPlaylists.removeAll()
                        _ = generateRandomizedPlaylist(for: selectedChannel)
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // NOTIFICATION BANNER
    // -------------------------------------------------------------------------
    private var analysisNotificationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(WalkmanTheme.hiResGold)

            Text("\(unanalyzedTracks.count) track\(unanalyzedTracks.count == 1 ? "" : "s") in your Local Music Library have not been analyzed for 12 Tone Acoustics yet.")
                .font(.system(size: 12))
                .foregroundStyle(WalkmanTheme.silverLight)

            Spacer()

            Button(action: startBatchAnalysis) {
                Text("Analyze Now")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WalkmanTheme.hiResGold.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.025))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.8),
            alignment: .bottom
        )
    }

    // -------------------------------------------------------------------------
    // DUAL PANE: TOP STACK CAROUSEL + BOTTOM CHANNEL TRACKLIST
    // -------------------------------------------------------------------------
    // DUAL PANE: 3D STACKED CARD CAROUSEL SLIDER + BOTTOM TRACKS LIST
    // -------------------------------------------------------------------------
    private var stackedDeckAndTracksSplitView: some View {
        VStack(spacing: 0) {
            // TOP SECTION: 3D Stacked Card Carousel Slider (Taller 4:3 Aspect Ratio Cards)
            stackedCarouselStage
                .frame(height: 440)
                .background(
                    WalkmanTheme.background
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 0.8),
                            alignment: .bottom
                        )
                )

            // BOTTOM SECTION: Channel Header & Tracklist
            bottomTracklistSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // -------------------------------------------------------------------------
    // 3D STACKED CARD CAROUSEL SLIDER STAGE
    // -------------------------------------------------------------------------
    private var stackedCarouselStage: some View {
        ZStack {
            // Interactive Stack Container
            GeometryReader { geo in
                    let centerX = geo.size.width / 2
                    let centerY = geo.size.height / 2

                    ZStack {
                        // Render all cards layered in 3D Stack order (no mid-transition popup or clipping)
                        ForEach(Array(displayedChannels.enumerated()), id: \.element.id) { index, ch in
                            let relativeIndex = CGFloat(index - activeIndex) + (dragOffset / 235.0)
                            let chTracks = tracks(for: ch)

                            SenseMeStackedCard(
                                channel: ch,
                                tracks: chTracks,
                                relativeIndex: relativeIndex,
                                onSelect: {
                                    guard !isStepping else { return }
                                    let now = ProcessInfo.processInfo.systemUptime
                                    guard now - lastStepTimestamp > 0.42 else { return }
                                    lastStepTimestamp = now
                                    isStepping = true
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                                        self.activeIndex = index
                                        self.dragOffset = 0
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                                        self.isStepping = false
                                    }
                                },
                                onQuickPlay: {
                                    quickPlay(channel: ch)
                                }
                            )
                            .scaleEffect(cardScale(for: relativeIndex))
                            .rotation3DEffect(
                                .degrees(cardRotationY(for: relativeIndex)),
                                axis: (x: 0, y: 1, z: 0)
                            )
                            .offset(
                                x: cardXOffset(for: relativeIndex),
                                y: cardYOffset(for: relativeIndex)
                            )
                            .opacity(cardOpacity(for: relativeIndex))
                            .zIndex(cardZIndex(for: relativeIndex))
                            .position(x: centerX, y: centerY)
                            .allowsHitTesting(abs(relativeIndex) < 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isStepping else { return }
                                self.dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                guard !isStepping else { return }
                                let threshold: CGFloat = 60.0
                                var targetIndex = activeIndex
                                if value.translation.width < -threshold && activeIndex < displayedChannels.count - 1 {
                                    targetIndex += 1
                                } else if value.translation.width > threshold && activeIndex > 0 {
                                    targetIndex -= 1
                                }
                                guard targetIndex != activeIndex else {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.92)) {
                                        dragOffset = 0
                                    }
                                    return
                                }
                                let now = ProcessInfo.processInfo.systemUptime
                                guard now - lastStepTimestamp > 0.35 else {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.92)) {
                                        dragOffset = 0
                                    }
                                    return
                                }
                                lastStepTimestamp = now
                                isStepping = true
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                                    activeIndex = targetIndex
                                    dragOffset = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                                    self.isStepping = false
                                }
                            }
                    )
                }

                // Left Slider Floating Arrow Button
                HStack {
                    Button(action: { stepChannel(offset: -1) }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.white.opacity(activeIndex > 0 && !isStepping ? 0.20 : 0.06), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(activeIndex > 0 && !isStepping ? Color.white : WalkmanTheme.silverMuted.opacity(0.3))
                        }
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStepping || activeIndex == 0)
                    .padding(.leading, 18)

                    Spacer()

                    // Right Slider Floating Arrow Button
                    Button(action: { stepChannel(offset: 1) }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.white.opacity(activeIndex < displayedChannels.count - 1 && !isStepping ? 0.20 : 0.06), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(activeIndex < displayedChannels.count - 1 && !isStepping ? Color.white : WalkmanTheme.silverMuted.opacity(0.3))
                        }
                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStepping || activeIndex >= displayedChannels.count - 1)
                    .padding(.trailing, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

    // -------------------------------------------------------------------------
    // 3D STACK CALCULATIONS: CENTER BIGGER, BEHIND CARDS SMALLER
    // -------------------------------------------------------------------------
    private func cardXOffset(for relativeIndex: CGFloat) -> CGFloat {
        let sign: CGFloat = relativeIndex >= 0 ? 1.0 : -1.0
        let absDist = abs(relativeIndex)
        if absDist <= 1.0 {
            return relativeIndex * 235.0
        } else if absDist <= 2.0 {
            return sign * (235.0 + (absDist - 1.0) * 150.0)
        } else {
            return sign * (385.0 + (absDist - 2.0) * 125.0)
        }
    }

    private func cardYOffset(for relativeIndex: CGFloat) -> CGFloat {
        let absDist = abs(relativeIndex)
        // Center card is slightly lifted; receding behind cards sit gently lower in perspective
        return min(16.0, absDist * 7.0)
    }

    private func cardScale(for relativeIndex: CGFloat) -> CGFloat {
        let absDist = abs(relativeIndex)
        if absDist <= 1.0 {
            // Center is 1.10, smoothly dropping to 0.78 at distance 1
            return 1.10 - (absDist * 0.32)
        } else if absDist <= 2.0 {
            // Distance 1 to 2: 0.78 down to 0.60
            return 0.78 - ((absDist - 1.0) * 0.18)
        } else {
            // Distance 2+: 0.60 down to minimum 0.46
            return max(0.46, 0.60 - ((absDist - 2.0) * 0.14))
        }
    }

    private func cardOpacity(for relativeIndex: CGFloat) -> Double {
        let absDist = abs(relativeIndex)
        if absDist <= 1.2 { return 1.0 }
        if absDist >= 3.2 { return 0.0 }
        return max(0.0, 1.0 - Double(absDist - 1.2) * 0.50)
    }

    private func cardRotationY(for relativeIndex: CGFloat) -> Double {
        let clamped = max(-1.8, min(1.8, relativeIndex))
        return Double(clamped) * -16.0
    }

    private func cardZIndex(for relativeIndex: CGFloat) -> Double {
        let absDist = abs(relativeIndex)
        let tieBreaker = relativeIndex > 0 ? 0.01 : 0.0
        return 100.0 - (Double(absDist) * 15.0) + tieBreaker
    }

    private func stepChannel(offset: Int) {
        let channels = displayedChannels
        guard !channels.isEmpty else { return }

        // Spam prevention throttle: ensure animations settle cleanly without compounding
        guard !isStepping else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastStepTimestamp > 0.42 else { return }
        lastStepTimestamp = now
        isStepping = true

        let newIndex = max(0, min(channels.count - 1, activeIndex + offset))
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            self.activeIndex = newIndex
            self.dragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            self.isStepping = false
        }
    }

    // -------------------------------------------------------------------------
    // BOTTOM SECTION: CHANNEL TRACKLIST & PLAY CONTROLS
    // -------------------------------------------------------------------------
    private var bottomTracklistSection: some View {
        let currentTracks = tracks(for: selectedChannel)

        return VStack(spacing: 0) {
            // Action Toolbar (Filter, Play All, Shuffle) OR Empty Channel Banner
            if currentTracks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.hiResGold)

                    Text("No tracks available in \"\(selectedChannel.name)\" channel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text("• Playback stopped")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.025))
            } else {
                HStack {
                    Spacer()

                    // LIQUID GLASS WRAPPED CONTROLS CLUSTER
                    HStack(spacing: 8) {
                        // Filter search inside channel
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(WalkmanTheme.silverMuted)

                            TextField("Filter channel...", text: $trackFilterQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))

                            if !trackFilterQuery.isEmpty {
                                Button(action: { trackFilterQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(width: 165)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.12), location: 0.0),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 5)
                                    Spacer(minLength: 0)
                                }
                                .clipShape(Capsule())
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

                        // Play All Button (Liquid Glass Hi-Res Gold)
                        Button(action: { playAll(in: currentTracks) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Play All")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    WalkmanTheme.hiResGoldGradient

                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.42), location: 0.0),
                                                .init(color: Color.clear, location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 6)
                                        Spacer(minLength: 0)
                                    }
                                    .clipShape(Capsule())
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.50), location: 0.0),
                                                .init(color: Color.white.opacity(0.15), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(color: WalkmanTheme.hiResGold.opacity(0.28), radius: 4, x: 0, y: 1.5)
                        }
                        .buttonStyle(.plain)

                        // Shuffle Button (Liquid Glass Translucent Frosted)
                        Button(action: { shuffleAll(in: currentTracks) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Shuffle")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))

                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.24), location: 0.0),
                                                .init(color: Color.clear, location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 6)
                                        Spacer(minLength: 0)
                                    }
                                    .clipShape(Capsule())
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.24), location: 0.0),
                                                .init(color: Color.white.opacity(0.08), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(.ultraThinMaterial)

                            Capsule()
                                .fill(Color(red: 18 / 255, green: 19 / 255, blue: 24 / 255).opacity(0.68))

                            Capsule()
                                .fill(Color.white.opacity(0.04))

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
                            .clipShape(Capsule())
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.26), location: 0.0),
                                        .init(color: .white.opacity(0.10), location: 0.5),
                                        .init(color: .white.opacity(0.04), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(WalkmanTheme.background.opacity(0.75))
            }

            Divider().overlay(Color.white.opacity(0.06))

            // Channel Tracks Table
            if currentTracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "speaker.slash.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Text("No Tracks in \"\(selectedChannel.name)\"")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Music playback was stopped. There are no tracks in your library matching this channel's 12-Tone acoustic mood, speed, or energy parameters.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
                .padding(.bottom, 88)
            } else {
                SenseMeChannelTableView(
                    tracks: filteredTracks(from: currentTracks),
                    allChannelTracks: currentTracks,
                    onInspectTrack: onInspectTrack,
                    onEditTrack: onEditTrack,
                    onTrimCutTrack: onTrimCutTrack,
                    onGoToTransfer: onGoToTransfer
                )
            }
        }
    }

    private func filteredTracks(from source: [Track]) -> [Track] {
        let q = trackFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return source }
        return source.filter { tr in
            tr.title.localizedCaseInsensitiveContains(q) ||
            tr.artist.localizedCaseInsensitiveContains(q) ||
            tr.album.localizedCaseInsensitiveContains(q) ||
            tr.genre.localizedCaseInsensitiveContains(q)
        }
    }

    // -------------------------------------------------------------------------
    // EMPTY STATES
    // -------------------------------------------------------------------------
    private var emptyLibraryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 42))
                .foregroundStyle(WalkmanTheme.silverMuted)

            Text("No Local Music Indexed")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)

            Text("Import folders into your Local Music Library to organize your tracks into Sony SensMe™ Channels.")
                .font(.system(size: 13))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(action: { onNavigateToLocalLibrary?() }) {
                Text("Go to Local Library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private var noAnalyzedTracksView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(WalkmanTheme.hiResGold)

            Text("12 Tone Acoustic Analysis Required")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)

            Text("Sony SensMe™ Channels analyzes speed (BPM), mood (valence), and energy (arousal) to automatically group your tracks into tailored listening channels.")
                .font(.system(size: 13))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button(action: startBatchAnalysis) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                    Text("Analyze Local Tracks (\(localLibrary.tracks.count) Songs)")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(WalkmanTheme.hiResGoldGradient)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // -------------------------------------------------------------------------
    // BATCH ANALYSIS SHEET
    // -------------------------------------------------------------------------
    private var batchAnalysisProgressSheet: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 32))
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Text("12 Tone Acoustic Analysis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)

                Text("Extracting speed, valence, and arousal for Sony SensMe™ Channels...")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Spacer()
                    Text("\(analysisCurrent) of \(analysisTotal)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }

                let fraction = analysisTotal > 0 ? Double(analysisCurrent) / Double(analysisTotal) : 0.0
                ProgressView(value: fraction)
                    .tint(WalkmanTheme.hiResGold)

                Text(analysisTrackName.isEmpty ? "Preparing..." : analysisTrackName)
                    .font(.system(size: 11))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button("Stop Analysis") {
                    analysisTask?.cancel()
                    showAnalysisSheet = false
                    isAnalyzing = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer()

                if !isAnalyzing {
                    Button("Done") {
                        showAnalysisSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(WalkmanTheme.card)
    }

    // -------------------------------------------------------------------------
    // LOGIC & ACTIONS
    // -------------------------------------------------------------------------
    private func handleChannelSwitched(to newIndex: Int) {
        channelAutoPlayTask?.cancel()

        // 1. Immediately pause playing audio so audio from the previous channel does not leak
        player.pause()

        let channels = displayedChannels
        guard !channels.isEmpty else { return }
        let safeIndex = max(0, min(channels.count - 1, newIndex))
        let targetChannel = channels[safeIndex]
        let channelTracks = tracks(for: targetChannel)

        // 2. If the destination channel has NO tracks:
        // Immediately stop playback, clear the audio queue, and tell the user that there are no tracks
        if channelTracks.isEmpty {
            player.stopAndClear()
            showEmptyChannelNotice(for: targetChannel)
            return
        }

        // 3. Clear empty channel notice since destination channel has tracks
        withAnimation {
            emptyChannelNotice = nil
        }

        // 4. Channel has tracks -> Auto-play tracks from the selected channel after 380ms debounce
        channelAutoPlayTask = Task {
            // Debounce pause: wait 380ms for card animation to land and settle gracefully
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                autoPlayCurrentChannel()
            }
        }
    }

    private func autoPlayCurrentChannel() {
        let channel = selectedChannel
        // Generate fresh randomized playlist weighted by mood/vibe and time of day
        let currentTracks = generateRandomizedPlaylist(for: channel)
        if currentTracks.isEmpty {
            player.stopAndClear()
            showEmptyChannelNotice(for: channel)
            return
        }

        let firstTrack = currentTracks[0]
        player.isShuffle = true
        let startTime = firstTrack.senseMeHighlightSec ?? 0.0
        player.play(
            track: firstTrack,
            coverArt: nil,
            in: currentTracks,
            startTime: startTime > 5.0 ? startTime : nil
        )
    }

    private func tracks(for channel: SenseMeChannel) -> [Track] {
        if let cached = randomizedPlaylists[channel.id], !cached.isEmpty {
            return cached
        }
        return generateRandomizedPlaylist(for: channel)
    }

    private func generateRandomizedPlaylist(for channel: SenseMeChannel) -> [Track] {
        let candidates = candidateTracks(for: channel)
        guard !candidates.isEmpty else {
            randomizedPlaylists[channel.id] = []
            return []
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let scored = candidates.map { tr -> (track: Track, score: Double) in
            var score = 50.0
            if let aro = tr.senseMeArousal, let val = tr.senseMeValence, let bpm = tr.senseMeBpm {
                switch channel.id {
                case "energetic":
                    score += aro * 30.0 + ((bpm - 110.0) / 40.0) * 15.0
                case "relax":
                    score -= aro * 30.0 + ((110.0 - bpm) / 40.0) * 15.0 + val * 10.0
                case "upbeat":
                    score += val * 35.0 + aro * 15.0
                case "mellow":
                    score += (1.0 - abs(aro + 0.25)) * 30.0 + (1.0 - abs(val)) * 15.0
                case "emotional":
                    score -= val * 35.0 + (aro > 0 ? 10.0 : -10.0)
                case "lounge":
                    score += (1.0 - abs(bpm - 100.0) / 35.0) * 25.0 + (0.5 - abs(aro)) * 20.0
                case "dance":
                    score += (1.0 - abs(bpm - 124.0) / 30.0) * 35.0 + aro * 20.0
                case "extreme":
                    score += aro * 45.0 + ((bpm - 120.0) / 30.0) * 15.0
                case "morning":
                    let hourFit = (hour >= 5 && hour < 10) ? 30.0 : 0.0
                    score += val * 30.0 + ((120.0 - abs(bpm - 105.0)) / 40.0) * 10.0 + hourFit
                case "daytime":
                    let hourFit = (hour >= 10 && hour < 17) ? 30.0 : 0.0
                    score += aro * 25.0 + ((bpm - 100.0) / 30.0) * 15.0 + hourFit
                case "evening":
                    let hourFit = (hour >= 17 && hour < 21) ? 30.0 : 0.0
                    score += (1.0 - abs(aro)) * 25.0 + val * 15.0 + hourFit
                case "night":
                    let hourFit = (hour >= 21 || hour < 0) ? 30.0 : 0.0
                    score -= aro * 30.0 + (1.0 - val) * 15.0 + hourFit
                case "midnight":
                    let hourFit = (hour >= 0 && hour < 5) ? 35.0 : 0.0
                    score -= aro * 40.0 + ((95.0 - bpm) / 30.0) * 15.0 + hourFit
                default:
                    break
                }
            }
            // Controlled entropy jitter to create fresh variations each selection
            let jitter = Double.random(in: -28.0...28.0)
            return (tr, score + jitter)
        }

        let shuffled = scored.sorted { $0.score > $1.score }.map { $0.track }
        randomizedPlaylists[channel.id] = shuffled
        return shuffled
    }

    private func candidateTracks(for channel: SenseMeChannel) -> [Track] {
        let analyzed = analyzedTracks
        if channel.id == "shuffle_all" {
            return analyzed
        }

        return analyzed.filter { tr in
            if tr.senseMeChannels.contains(channel.name) {
                return true
            }

            if let bpm = tr.senseMeBpm, let val = tr.senseMeValence, let aro = tr.senseMeArousal {
                switch channel.id {
                case "energetic":
                    return aro >= 0.30 && val >= 0.10 && bpm >= 112
                case "relax":
                    return aro <= -0.10 && val >= -0.30 && bpm <= 108
                case "upbeat":
                    return val >= 0.15 && aro >= -0.15 && aro <= 0.70
                case "mellow":
                    return aro >= -0.75 && aro <= 0.05 && val >= -0.35 && val <= 0.45
                case "emotional":
                    return val <= -0.05 && aro >= -0.55 && aro <= 0.40
                case "extreme":
                    return aro >= 0.60 || bpm >= 145
                case "dance":
                    return bpm >= 105 && bpm <= 140 && aro >= 0.20
                case "lounge":
                    return bpm >= 75 && bpm <= 120 && aro >= -0.40 && aro <= 0.25
                case "morning":
                    return (val >= 0.10 || (aro >= -0.20 && aro <= 0.35)) && bpm >= 85 && bpm <= 130
                case "daytime":
                    return (aro >= 0.05 || bpm >= 100) && aro >= -0.15
                case "evening":
                    return bpm <= 118 && aro >= -0.45 && aro <= 0.20
                case "night":
                    return aro <= 0.15 && val <= 0.30 && bpm <= 115
                case "midnight":
                    return aro <= -0.10 || bpm <= 88
                default:
                    return false
                }
            }
            return false
        }
    }

    private func quickPlay(channel: SenseMeChannel) {
        let channelTracks = tracks(for: channel)
        if channelTracks.isEmpty {
            player.stopAndClear()
            showEmptyChannelNotice(for: channel)
            return
        }

        // If this channel is already playing, toggle pause / resume
        if let current = player.currentTrack, channelTracks.contains(where: { $0.id == current.id }) {
            player.togglePlayPause()
            return
        }

        let first = channelTracks[0]
        player.isShuffle = true
        let startTime = first.senseMeHighlightSec ?? 0.0
        player.play(track: first, coverArt: nil, in: channelTracks, startTime: startTime > 5.0 ? startTime : nil)
    }

    private func playAll(in channelTracks: [Track]) {
        guard let first = channelTracks.first else {
            player.stopAndClear()
            showEmptyChannelNotice(for: selectedChannel)
            return
        }
        player.play(track: first, in: channelTracks)
    }

    private func shuffleAll(in channelTracks: [Track]) {
        let fresh = generateRandomizedPlaylist(for: selectedChannel)
        guard let first = fresh.first else {
            player.stopAndClear()
            showEmptyChannelNotice(for: selectedChannel)
            return
        }
        player.isShuffle = true
        let startTime = first.senseMeHighlightSec ?? 0.0
        player.play(track: first, in: fresh, startTime: startTime > 5.0 ? startTime : nil)
    }

    private func showEmptyChannelNotice(for channel: SenseMeChannel) {
        emptyNoticeDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.emptyChannelNotice = "No tracks in \"\(channel.name)\" channel • Playback stopped"
        }
        emptyNoticeDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.emptyChannelNotice = nil
                }
            }
        }
    }

    private func startBatchAnalysis() {
        guard !unanalyzedTracks.isEmpty else { return }
        isAnalyzing = true
        analysisCurrent = 0
        analysisTotal = unanalyzedTracks.count
        analysisTrackName = ""
        showAnalysisSheet = true

        analysisTask = Task {
            await localLibrary.analyzeLocalTracksWithSenseMe { current, total, trackName in
                Task { @MainActor in
                    self.analysisCurrent = current
                    self.analysisTotal = total
                    self.analysisTrackName = trackName
                }
            }
            await MainActor.run {
                self.randomizedPlaylists.removeAll()
                _ = self.generateRandomizedPlaylist(for: self.selectedChannel)
                self.isAnalyzing = false
            }
        }
    }
}

// =============================================================================
// SENSEME STACKED CARD COMPONENT
// Center Prominent (1.08x) & Behind Receding (0.76x -> 0.46x) with Depth Scrim
// =============================================================================

private struct SenseMeStackedCard: View {
    let channel: SenseMeChannel
    let tracks: [Track]
    let relativeIndex: CGFloat
    let onSelect: () -> Void
    let onQuickPlay: () -> Void

    @State private var isHovered = false
    @ObservedObject private var player = AudioPlayerService.shared

    private var isFront: Bool {
        abs(relativeIndex) < 0.45
    }

    private var isPlayingThisChannel: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && tracks.contains(where: { $0.id == current.id })
    }

    private var totalDurationSec: Double {
        tracks.reduce(0.0) { $0 + $1.durationSeconds }
    }

    private var durationLabel: String {
        if totalDurationSec <= 0 { return "0 min" }
        let mins = Int(totalDurationSec) / 60
        if mins >= 60 {
            let hours = mins / 60
            let remMins = mins % 60
            return "\(hours) hr \(remMins) min"
        }
        return "\(mins) min"
    }

    private var cleanSubtitle: String {
        if let range = channel.subtitle.range(of: "• ") {
            return String(channel.subtitle[range.upperBound...])
        }
        return channel.subtitle
    }

    var body: some View {
        Button(action: {
            if isFront {
                onQuickPlay()
            } else {
                onSelect()
            }
        }) {
            // Card Body (336pt width x 304pt height - 4:3 Aspect Ratio Artwork)
            VStack(alignment: .leading, spacing: 0) {
                // Artwork / Mood Tile (exact 4:3 ratio: 336pt x 252pt)
                ZStack(alignment: .topTrailing) {
                    artworkOrPlaceholderTile
                        .frame(width: 336, height: 252)
                        .clipped()

                    // Dimming Scrim for receding behind cards
                    if abs(relativeIndex) > 0.3 {
                        Color.black
                            .opacity(min(0.48, Double(abs(relativeIndex) - 0.25) * 0.36))
                            .allowsHitTesting(false)
                    }
                }

                // Card Footer Info (52pt)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 15, weight: isFront ? .heavy : .bold))
                            .foregroundStyle(isFront ? Color.white : (isHovered ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted))
                            .lineLimit(1)

                        if isPlayingThisChannel {
                            EqualizerLiveBars(color: WalkmanTheme.hiResGold, barCount: 3)
                        }

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "music.note")
                                .font(.system(size: 9.5))
                            Text("\(tracks.count) Songs")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    HStack(spacing: 4) {
                        Text(cleanSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)

                        Spacer()

                        Text(durationLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(WalkmanTheme.silverDark)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(width: 336, height: 52)
                .background(
                    ZStack {
                        Color(red: 16 / 255, green: 17 / 255, blue: 21 / 255).opacity(isFront ? 0.90 : 0.82)
                        Color.white.opacity(isFront ? 0.04 : 0.02)
                    }
                )
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(isFront ? 0.12 : 0.05))
                        .frame(height: 0.8),
                    alignment: .top
                )
            }
            .frame(width: 336, height: 304)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 14 / 255, green: 15 / 255, blue: 19 / 255).opacity(isFront ? 0.88 : 0.80))

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(isFront ? 0.04 : 0.015))

                    // Optical top specular sheen reflection
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isFront ? 0.32 : 0.14), location: 0.0),
                                .init(color: Color.white.opacity(0.04), location: 0.45),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: isFront ? [
                                .init(color: Color.white.opacity(0.70), location: 0.0),
                                .init(color: Color.white.opacity(0.35), location: 0.35),
                                .init(color: Color.white.opacity(0.12), location: 0.70),
                                .init(color: Color.white.opacity(0.06), location: 1.0)
                            ] : [
                                .init(color: Color.white.opacity(isHovered ? 0.38 : 0.18), location: 0.0),
                                .init(color: Color.white.opacity(isHovered ? 0.18 : 0.08), location: 0.5),
                                .init(color: Color.white.opacity(0.03), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isFront ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isFront ? 0.56 : 0.32),
                radius: isFront ? 20 : 7,
                x: 0,
                y: isFront ? 10 : 3
            )
            .shadow(
                color: Color.black.opacity(isFront ? 0.24 : 0.12),
                radius: isFront ? 5 : 2,
                x: 0,
                y: isFront ? 2 : 1
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var artworkOrPlaceholderTile: some View {
        if let customImage = SenseMeArtworkResolver.shared.image(for: channel) {
            ZStack {
                Image(nsImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                // Top specular gradient sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 25)
                    Spacer()
                }

                // Bottom vignette gradient to blend into footer
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.black.opacity(0.40), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 35)
                }
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: channel.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Color.black.opacity(0.35)

                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.30), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 25)
                    Spacer()
                }

                VStack(spacing: 5) {
                    Image(systemName: channel.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)

                    Text(channel.name.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
        }
    }
}

// =============================================================================
// CHANNEL TABLE VIEW (NATIVE MACOS TABLE WITH HOVER & CONTEXT MENU)
// =============================================================================

private struct SenseMeChannelTableView: View {
    let tracks: [Track]
    let allChannelTracks: [Track]
    var onInspectTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onGoToTransfer: (() -> Void)? = nil

    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedTrackId: String? = nil

    var body: some View {
        Table(tracks, selection: $selectedTrackId) {
            TableColumn("#") { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying
                let pos = (tracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1

                Button(action: {
                    self.selectedTrackId = track.id
                    if isPlayingThis {
                        player.pause()
                    } else {
                        player.play(track: track, in: allChannelTracks)
                    }
                }) {
                    ZStack {
                        if isPlayingThis {
                            EqualizerLiveBars(color: WalkmanTheme.hiResGold, barCount: 3)
                        } else {
                            Text("\(pos)")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                    .frame(width: 24, alignment: .center)
                }
                .buttonStyle(.plain)
            }
            .width(min: 24, ideal: 30, max: 36)

            TableColumn("Title") { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying

                HStack(spacing: 8) {
                    TrackCoverThumbnail(track: track, size: 28, isPlaying: isPlayingThis)

                    Text(track.title)
                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGold : Color.white)
                        .lineLimit(1)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Artist") { track in
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Album") { track in
                Text(track.album.isEmpty ? "Unknown Album" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Speed") { track in
                if let bpm = track.senseMeBpm, bpm > 0 {
                    Text("\(Int(bpm.rounded())) BPM")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                } else {
                    Text("—")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverDark)
                }
            }
            .width(min: 60, ideal: 75, max: 90)

            TableColumn("Time") { track in
                Text(track.durationFormatted)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 44, ideal: 56, max: 70)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            if let id = selection.first, let tr = tracks.first(where: { $0.id == id }) {
                Button("Play Now") {
                    player.play(track: tr, in: allChannelTracks)
                }
                if let highlight = tr.senseMeHighlightSec, highlight > 0 {
                    Button("Play Chorus Highlight (\(formatTime(highlight)))") {
                        player.play(track: tr, in: allChannelTracks, startTime: highlight)
                    }
                }
                Divider()
                Button("Inspect Track Metadata") {
                    onInspectTrack?(tr)
                }
                Button("Edit Song Metadata...") {
                    onEditTrack?(tr)
                }
                Button("Trim & Cut...") {
                    onTrimCutTrack?(tr)
                }
                if let onTransfer = onGoToTransfer {
                    Divider()
                    Button {
                        let targets = tracks.filter { selection.contains($0.id) }
                        let toQueue = targets.isEmpty ? [tr] : targets
                        TransferQueueService.shared.enqueue(tracks: toQueue)
                        onTransfer()
                    } label: {
                        Label("Send to Transfer & Convert...", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tr.fullPath)])
                }
            }
        } primaryAction: { selection in
            if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId }) {
                self.selectedTrackId = track.id
                if player.currentTrack?.id == track.id && player.isPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: allChannelTracks)
                }
            }
        }
        .tableScrollBottomInset(88)
    }

    private func formatTime(_ sec: Double) -> String {
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// =============================================================================
// TRACK CONVENIENCE EXTENSIONS FOR SENSEME SORTING
// =============================================================================

extension Track {
    var durationFormatted: String {
        let s = Int(durationSeconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var senseMeBpmString: String {
        guard let bpm = senseMeBpm, bpm > 0 else { return "000" }
        return String(format: "%03d", Int(bpm.rounded()))
    }

    var senseMeMoodString: String {
        guard let val = senseMeValence else { return "0.00" }
        return String(format: "%.2f", val)
    }
}
