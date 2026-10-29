import SwiftUI
import AppKit

// =============================================================================
// SONY SENSME™ CHANNELS ARCHITECTURE
// Authentic recreation of Sony Walkman 12 Tone Acoustic Mood & Time Channels
// Horizontal Stack Carousel with 3D Depth Transitions & Bottom Channel Tracks
// =============================================================================

public enum SenseMeChannelCategory: String, CaseIterable, Identifiable, Sendable {
    case timeOfDay = "Time of Day"
    case moodAndStyle = "Mood & Style"
    case special = "Global Playback"

    public var id: String { rawValue }
}

public enum SenseMeViewMode: String, CaseIterable, Identifiable, Sendable {
    case carousel = "Channels Carousel"
    case moodGalaxy = "12-Tone Mood Galaxy"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .carousel: return "rectangle.stack.fill"
        case .moodGalaxy: return "sparkles"
        }
    }
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
        SenseMeChannel(
            id: "acoustic",
            name: "Acoustic",
            category: .moodAndStyle,
            subtitle: "Natural Instruments & Vocals",
            description: "Unplugged guitars, pianos, folk instrumentation, and intimate, organic performances.",
            icon: "guitars.fill",
            gradientColors: [Color(red: 0.76, green: 0.54, blue: 0.34), Color(red: 0.48, green: 0.32, blue: 0.18)],
            artworkFilename: "senseme_acoustic.png",
            hourRange: nil
        ),
        SenseMeChannel(
            id: "electronic",
            name: "Electronic",
            category: .moodAndStyle,
            subtitle: "Synthesizers & Digital Beats",
            description: "Analog synths, modular soundscapes, ambient electronica, and futuristic grooves.",
            icon: "pianokeys.inverse",
            gradientColors: [Color(red: 0.18, green: 0.60, blue: 0.92), Color(red: 0.08, green: 0.28, blue: 0.72)],
            artworkFilename: "senseme_electronic.png",
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
// =============================================================================

public final class SenseMeArtworkResolver: @unchecked Sendable {
    public static let shared = SenseMeArtworkResolver()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    private init() {}

    public func image(for channelId: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[channelId] {
            return cached
        }

        let filenames = [
            "senseme_\(channelId).png",
            "senseme_\(channelId).jpg",
            "\(channelId).png",
            "\(channelId).jpg"
        ]

        for fn in filenames {
            if let img = NSImage(named: fn) {
                cache[channelId] = img
                return img
            }
            if let path = Bundle.main.path(forResource: fn, ofType: nil),
               let img = NSImage(contentsOfFile: path) {
                cache[channelId] = img
                return img
            }
        }

        let candidateDirs = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".walkman_studio/senseme"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/WalkmanStudio/SenseMe")
        ]

        for dir in candidateDirs {
            for fn in filenames {
                let fileUrl = dir.appendingPathComponent(fn)
                if FileManager.default.fileExists(atPath: fileUrl.path),
                   let img = NSImage(contentsOf: fileUrl) {
                    cache[channelId] = img
                    return img
                }
            }
        }

        return nil
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
// MAIN SENSEME CHANNELS VIEW (REDESIGNED: CAROUSEL TOP + TRACKS BOTTOM)
// =============================================================================

public struct SenseMeChannelsView: View {
    @ObservedObject private var localLibrary = LocalMusicLibraryService.shared
    @ObservedObject private var player = AudioPlayerService.shared

    var onInspectTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onGoToTransfer: (() -> Void)? = nil
    var onNavigateToLocalLibrary: (() -> Void)? = nil

    @State private var selectedChannel: SenseMeChannel = SenseMeChannel.allChannels[0]
    @State private var viewMode: SenseMeViewMode = .carousel
    @State private var selectedCategoryFilter: String = "ALL"
    @State private var trackFilterQuery: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var analysisCurrent: Int = 0
    @State private var analysisTotal: Int = 0
    @State private var analysisTrackName: String = ""
    @State private var showAnalysisSheet: Bool = false
    @State private var analysisTask: Task<Void, Never>? = nil

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
        switch selectedCategoryFilter {
        case "TIME":
            return SenseMeChannel.allChannels.filter { $0.category == .timeOfDay }
        case "MOOD":
            return SenseMeChannel.allChannels.filter { $0.category == .moodAndStyle }
        case "SPECIAL":
            return SenseMeChannel.allChannels.filter { $0.category == .special }
        default:
            return SenseMeChannel.allChannels
        }
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
        ZStack {
            WalkmanTheme.background
                .ignoresSafeArea()

            // Dynamic Ambient Backing Glow derived from the active selected channel
            RadialGradient(
                colors: [selectedChannel.gradientColors[0].opacity(0.15), Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 650
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: selectedChannel.id)

            VStack(spacing: 0) {
                // Top Header (Title, 12-Tone badge, Mode Toggle, Analysis status)
                topHeaderBar
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .background(
                        WalkmanTheme.background
                            .overlay(
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 0.8),
                                alignment: .bottom
                            )
                    )

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
                    switch viewMode {
                    case .carousel:
                        // REDESIGNED DUAL PANE:
                        // Top = Horizontal Stack Carousel
                        // Bottom = Tracks List for Selected Channel
                        carouselAndTracksSplitView
                    case .moodGalaxy:
                        SenseMeMoodGalaxyView(
                            tracks: analyzedTracks,
                            onInspectTrack: onInspectTrack
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAnalysisSheet) {
            batchAnalysisProgressSheet
        }
        .onAppear {
            // Default select the channel matching the current time of day
            let hour = Calendar.current.component(.hour, from: Date())
            if let activeTimeCh = SenseMeChannel.allChannels.first(where: { $0.isCurrentlyActive(at: hour) }) {
                self.selectedChannel = activeTimeCh
            }
        }
    }

    // -------------------------------------------------------------------------
    // TOP HEADER BAR
    // -------------------------------------------------------------------------
    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("SenseMe™ Channels")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("12 TONE")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(WalkmanTheme.hiResGold.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.8)
                        )
                }

                Text("Acoustic mood and time-of-day channels based on Sony 12 Tone Analysis")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer(minLength: 12)

            // Mode Selector Toggle (Channels Carousel vs 12-Tone Mood Galaxy)
            HStack(spacing: 2) {
                ForEach(SenseMeViewMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                            viewMode = mode
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 11.5, weight: viewMode == mode ? .bold : .medium))
                        }
                        .foregroundStyle(viewMode == mode ? Color.black : WalkmanTheme.silverLight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                if viewMode == mode {
                                    Capsule().fill(WalkmanTheme.hiResGoldGradient)
                                }
                            }
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8))

            // Stats Badges
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                    Text("\(analyzedTracks.count) / \(localLibrary.tracks.count)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8))

                // Analyze 12-Tone Acoustics Button
                if !unanalyzedTracks.isEmpty {
                    Button(action: startBatchAnalysis) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Analyze (\(unanalyzedTracks.count))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Batch analyze remaining local tracks for Sony 12 Tone Acoustics")
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
    private var carouselAndTracksSplitView: some View {
        VStack(spacing: 0) {
            // TOP SECTION: Horizontal Stack Carousel
            topCarouselStage
                .frame(height: 228)
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
    // TOP CAROUSEL STAGE
    // -------------------------------------------------------------------------
    private var topCarouselStage: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 10) {
                // Category Filter Pills & Left/Right Step Controls
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        categoryFilterButton(id: "ALL", title: "All Channels (\(SenseMeChannel.allChannels.count))")
                        categoryFilterButton(id: "TIME", title: "🌅 Time of Day (5)")
                        categoryFilterButton(id: "MOOD", title: "⚡ Mood & Style (10)")
                        categoryFilterButton(id: "SPECIAL", title: "🔀 Global (1)")
                    }

                    Spacer()

                    // Previous / Next Step Buttons
                    HStack(spacing: 6) {
                        Button(action: { stepChannel(offset: -1, proxy: proxy) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Previous Channel")

                        Button(action: { stepChannel(offset: 1, proxy: proxy) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Next Channel")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)

                // Horizontal Carousel ScrollView with 3D Depth Transitions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Left breathing margin
                        Spacer().frame(width: 14)

                        ForEach(displayedChannels) { ch in
                            let isSelected = selectedChannel.id == ch.id
                            let chTracks = tracks(for: ch)
                            let isActiveTime = ch.isCurrentlyActive(at: currentHour)

                            SenseMeCarouselCard(
                                channel: ch,
                                tracks: chTracks,
                                isSelected: isSelected,
                                isActiveTime: isActiveTime,
                                onSelect: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                                        self.selectedChannel = ch
                                        proxy.scrollTo(ch.id, anchor: .center)
                                    }
                                },
                                onQuickPlay: {
                                    quickPlay(channel: ch)
                                }
                            )
                            .id(ch.id)
                            .carouselScrollTransition()
                        }

                        // Right breathing margin
                        Spacer().frame(width: 14)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func categoryFilterButton(id: String, title: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                selectedCategoryFilter = id
                if let first = displayedChannels.first {
                    selectedChannel = first
                }
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: selectedCategoryFilter == id ? .bold : .medium))
                .foregroundStyle(selectedCategoryFilter == id ? Color.black : WalkmanTheme.silverLight)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    selectedCategoryFilter == id ?
                        WalkmanTheme.hiResGoldGradient :
                        LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(selectedCategoryFilter == id ? WalkmanTheme.hiResGold.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func stepChannel(offset: Int, proxy: ScrollViewProxy) {
        let channels = displayedChannels
        guard !channels.isEmpty else { return }
        guard let currentIndex = channels.firstIndex(where: { $0.id == selectedChannel.id }) else {
            selectedChannel = channels[0]
            proxy.scrollTo(channels[0].id, anchor: .center)
            return
        }

        let newIndex = max(0, min(channels.count - 1, currentIndex + offset))
        let target = channels[newIndex]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            self.selectedChannel = target
            proxy.scrollTo(target.id, anchor: .center)
        }
    }

    // -------------------------------------------------------------------------
    // BOTTOM SECTION: CHANNEL TRACKLIST & PLAY CONTROLS
    // -------------------------------------------------------------------------
    private var bottomTracklistSection: some View {
        let currentTracks = tracks(for: selectedChannel)

        return VStack(spacing: 0) {
            // Channel Action Toolbar (Title, Count, Play All, Shuffle, Search)
            HStack(spacing: 14) {
                // Channel Identity Pill
                HStack(spacing: 8) {
                    Image(systemName: selectedChannel.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selectedChannel.gradientColors[0])

                    Text(selectedChannel.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text(selectedChannel.category.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }

                Text("•")
                    .foregroundStyle(WalkmanTheme.silverDark)

                Text(selectedChannel.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)

                Spacer()

                // Filter search inside channel
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    TextField("Filter channel...", text: $trackFilterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 170)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))

                // Play All Button
                Button(action: { playAll(in: currentTracks) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Play All")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(currentTracks.isEmpty)

                // Shuffle Button
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
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(currentTracks.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(WalkmanTheme.background.opacity(0.75))

            Divider().overlay(Color.white.opacity(0.06))

            // Channel Tracks Table
            if currentTracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 34))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Text("No Tracks in \"\(selectedChannel.name)\"")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Tracks are automatically assigned to this channel when their 12-Tone speed, mood, and valence parameters match.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
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
    private func tracks(for channel: SenseMeChannel) -> [Track] {
        let analyzed = analyzedTracks
        if channel.id == "shuffle_all" {
            return analyzed
        }

        return analyzed.filter { tr in
            if tr.senseMeChannels.contains(channel.name) {
                return true
            }

            // Fallback heuristics using 12-Tone acoustic metrics if channels array not populated
            if let bpm = tr.senseMeBpm, let val = tr.senseMeValence, let aro = tr.senseMeArousal {
                switch channel.id {
                case "energetic":
                    return aro >= 0.35 && val >= 0.15 && bpm >= 115
                case "relax":
                    return aro <= -0.15 && val >= -0.30 && bpm <= 105
                case "upbeat":
                    return val >= 0.20 && aro >= -0.10 && aro <= 0.65
                case "mellow":
                    return aro >= -0.75 && aro <= 0.0 && val >= -0.35 && val <= 0.45
                case "emotional":
                    return val <= -0.10 && aro >= -0.55 && aro <= 0.40
                case "extreme":
                    return aro >= 0.65
                case "dance":
                    return bpm >= 108 && bpm <= 138 && aro >= 0.25
                case "lounge":
                    return bpm >= 80 && bpm <= 118 && aro >= -0.40 && aro <= 0.30
                case "acoustic":
                    return tr.genre.localizedCaseInsensitiveContains("acoustic") || val >= 0.10
                case "electronic":
                    return tr.genre.localizedCaseInsensitiveContains("electronic") || aro >= 0.40
                case "morning":
                    return val >= 0.15 || (aro >= -0.20 && bpm >= 90 && bpm <= 125)
                case "daytime":
                    return val >= 0.10 || (aro >= 0.15 && bpm >= 105)
                case "evening":
                    return (aro >= -0.30 && aro <= 0.20 && val >= -0.20) || bpm <= 115
                case "night":
                    return (aro <= 0.10 && val <= 0.25) || bpm <= 110
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
        guard !channelTracks.isEmpty else { return }

        if channel.id == "shuffle_all" {
            let shuffled = channelTracks.shuffled()
            if let first = shuffled.first {
                player.isShuffle = true
                player.play(track: first, in: shuffled)
            }
        } else {
            player.play(track: channelTracks[0], in: channelTracks)
        }
    }

    private func playAll(in channelTracks: [Track]) {
        guard let first = channelTracks.first else { return }
        player.play(track: first, in: channelTracks)
    }

    private func shuffleAll(in channelTracks: [Track]) {
        guard !channelTracks.isEmpty else { return }
        let shuffled = channelTracks.shuffled()
        if let first = shuffled.first {
            player.isShuffle = true
            player.play(track: first, in: shuffled)
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
                self.isAnalyzing = false
            }
        }
    }
}

// =============================================================================
// SENSEME CAROUSEL CARD COMPONENT (HORIZONTAL STACK WITH PEAKING VINYL)
// =============================================================================

private struct SenseMeCarouselCard: View {
    let channel: SenseMeChannel
    let tracks: [Track]
    let isSelected: Bool
    let isActiveTime: Bool
    let onSelect: () -> Void
    let onQuickPlay: () -> Void

    @State private var isHovered = false
    @ObservedObject private var player = AudioPlayerService.shared

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

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                // Tactile Peeking Vinyl Record (Slides out when active or hovered)
                peekingVinylRecord
                    .offset(x: (isSelected || isHovered) ? 24 : 0, y: (isSelected || isHovered) ? -14 : 0)
                    .opacity((isSelected || isHovered) ? 0.95 : 0.0)
                    .scaleEffect((isSelected || isHovered) ? 1.0 : 0.8)
                    .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isSelected || isHovered)

                // Foreground Card Body
                VStack(alignment: .leading, spacing: 0) {
                    // Artwork / Mood Tile
                    ZStack(alignment: .topTrailing) {
                        artworkOrPlaceholderTile
                            .frame(height: 108)
                            .clipped()

                        // "CURRENT TIME" Badge
                        if isActiveTime {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(WalkmanTheme.hiResGold)
                                    .frame(width: 5, height: 5)
                                Text("CURRENT TIME")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(Color.black)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .padding(6)
                        }

                        // Hover / Playing Quick Play Button
                        if (isHovered || isPlayingThisChannel || isSelected) && !tracks.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Button(action: onQuickPlay) {
                                        ZStack {
                                            Circle()
                                                .fill(WalkmanTheme.hiResGoldGradient)
                                                .frame(width: 28, height: 28)
                                                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 2)

                                            Image(systemName: isPlayingThisChannel ? "pause.fill" : "play.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color.black)
                                                .offset(x: isPlayingThisChannel ? 0 : 0.8)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                        }
                    }

                    // Card Footer Info
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(channel.name)
                                .font(.system(size: 13, weight: isSelected ? .heavy : .bold))
                                .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : (isHovered ? Color.white : WalkmanTheme.silverLight))
                                .lineLimit(1)

                            if isPlayingThisChannel {
                                EqualizerLiveBars(color: WalkmanTheme.hiResGold, barCount: 3)
                            }

                            Spacer()

                            Text("\(tracks.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }

                        HStack(spacing: 4) {
                            Text(durationLabel)
                                .font(.system(size: 9.5))
                                .foregroundStyle(WalkmanTheme.silverDark)

                            Spacer()

                            if tracks.isEmpty {
                                Text("No tracks")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(isSelected ? 0.04 : 0.02))
                }
                .frame(width: 195)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.06 : (isHovered ? 0.04 : 0.02)))
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isSelected ?
                                WalkmanTheme.hiResGold.opacity(0.85) :
                                (isActiveTime ?
                                    WalkmanTheme.hiResGold.opacity(0.40) :
                                    Color.white.opacity(isHovered ? 0.22 : 0.08)),
                            lineWidth: isSelected ? 1.5 : (isActiveTime ? 1.0 : 0.8)
                        )
                )
            }
            .shadow(
                color: Color.black.opacity(isSelected ? 0.35 : (isHovered ? 0.22 : 0.12)),
                radius: isSelected ? 7 : (isHovered ? 5 : 2),
                x: 0,
                y: isSelected ? 3 : 1
            )
            .scaleEffect(isSelected ? 1.04 : (isHovered ? 1.01 : 0.93))
            .opacity(isSelected ? 1.0 : (isHovered ? 0.92 : 0.72))
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: isSelected || isHovered)
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

    private var peekingVinylRecord: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.16),
                            Color(red: 0.04, green: 0.04, blue: 0.05)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 45
                    )
                )
                .frame(width: 80, height: 80)
                .shadow(color: Color.black.opacity(0.45), radius: 4, x: 2, y: 1)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                .frame(width: 68, height: 68)
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                .frame(width: 56, height: 56)

            Circle()
                .fill(channel.gradientColors[0].opacity(0.85))
                .frame(width: 26, height: 26)

            Circle()
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .frame(width: 6, height: 6)
        }
        .rotationEffect(.degrees((isSelected || isHovered) ? 30 : 0))
    }

    @ViewBuilder
    private var artworkOrPlaceholderTile: some View {
        if let customImage = SenseMeArtworkResolver.shared.image(for: channel.id) {
            Image(nsImage: customImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
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
                    .frame(height: 22)
                    Spacer()
                }

                VStack(spacing: 4) {
                    Image(systemName: channel.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)

                    Text(channel.name.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
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
    @State private var sortOrder = [
        KeyPathComparator(\Track.artist),
        KeyPathComparator(\Track.album),
        KeyPathComparator(\Track.trackNum)
    ]

    private var sortedTracks: [Track] {
        tracks.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trackNum) { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying

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
                            Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                    .frame(width: 24, alignment: .center)
                }
                .buttonStyle(.plain)
            }
            .width(min: 24, ideal: 30, max: 36)

            TableColumn("Title", value: \.title) { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying

                HStack(spacing: 8) {
                    TrackCoverThumbnail(track: track, size: 28, isPlaying: isPlayingThis)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                            .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGold : Color.white)
                            .lineLimit(1)

                        if let highlight = track.senseMeHighlightSec, highlight > 0 {
                            Button(action: {
                                player.play(track: track, in: allChannelTracks, startTime: highlight)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8))
                                    Text("Preview Chorus @ \(formatTime(highlight))")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(WalkmanTheme.hiResGold)
                            }
                            .buttonStyle(.plain)
                            .help("Jump to Sony Sabi Chorus Highlight")
                        }
                    }
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Album", value: \.album) { track in
                Text(track.album.isEmpty ? "Unknown Album" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Speed", value: \.senseMeBpmString) { track in
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

            TableColumn("Mood", value: \.senseMeMoodString) { track in
                if let val = track.senseMeValence, let aro = track.senseMeArousal {
                    HStack(spacing: 4) {
                        Text("V: \(val >= 0 ? "+" : "")\(String(format: "%.2f", val))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(val >= 0 ? Color(red: 0.95, green: 0.70, blue: 0.25) : WalkmanTheme.silverMuted)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(WalkmanTheme.silverDark)

                        Text("A: \(aro >= 0 ? "+" : "")\(String(format: "%.2f", aro))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(aro >= 0 ? Color(red: 0.95, green: 0.40, blue: 0.40) : WalkmanTheme.silverMuted)
                    }
                } else {
                    Text("—")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverDark)
                }
            }
            .width(min: 110, ideal: 130, max: 150)

            TableColumn("Time", value: \.durationSeconds) { track in
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
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tr.fullPath)])
                }
            }
        }
    }

    private func formatTime(_ sec: Double) -> String {
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// =============================================================================
// SENSEME 12-TONE MOOD GALAXY (ACOUSTIC UNIVERSE MAP)
// =============================================================================

public struct SenseMeMoodGalaxyView: View {
    let tracks: [Track]
    var onInspectTrack: ((Track) -> Void)? = nil

    @ObservedObject private var player = AudioPlayerService.shared
    @State private var hoveredTrack: Track? = nil
    @State private var selectedFilterChannel: String = "ALL"

    private let filterOptions = [
        ("ALL", "All Moods"),
        ("Energetic", "⚡ Energetic"),
        ("Relax", "🍃 Relax"),
        ("Upbeat", "✨ Upbeat"),
        ("Mellow", "☕ Mellow"),
        ("Emotional", "💖 Emotional"),
        ("Dance", "🪩 Dance"),
        ("Lounge", "🍸 Lounge"),
        ("Morning", "🌅 Morning"),
        ("Night", "🌙 Night")
    ]

    private var filteredTracks: [Track] {
        if selectedFilterChannel == "ALL" {
            return tracks
        }
        return tracks.filter { $0.senseMeChannels.contains(selectedFilterChannel) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar & Shuffle Button
            galaxyToolbar
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.02))

            // 2D Acoustic Mood Canvas
            GeometryReader { geo in
                ZStack {
                    quadrantBackgrounds(size: geo.size)
                    coordinateCrosshairs(size: geo.size)

                    ForEach(tracks) { tr in
                        let isHighlighted = selectedFilterChannel == "ALL" || tr.senseMeChannels.contains(selectedFilterChannel)
                        let isPlaying = player.currentTrack?.id == tr.id && player.isPlaying

                        trackGalaxyNode(track: tr, in: geo.size, isHighlighted: isHighlighted, isPlaying: isPlaying)
                    }

                    if let target = hoveredTrack {
                        hoverPopover(for: target, in: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.05, green: 0.055, blue: 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
                .padding(20)
            }
        }
    }

    private var galaxyToolbar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filterOptions, id: \.0) { opt in
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                selectedFilterChannel = opt.0
                            }
                        }) {
                            Text(opt.1)
                                .font(.system(size: 11, weight: selectedFilterChannel == opt.0 ? .bold : .medium))
                                .foregroundStyle(selectedFilterChannel == opt.0 ? Color.black : WalkmanTheme.silverLight)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(
                                    selectedFilterChannel == opt.0 ?
                                        WalkmanTheme.hiResGoldGradient :
                                        LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(selectedFilterChannel == opt.0 ? WalkmanTheme.hiResGold.opacity(0.4) : Color.white.opacity(0.10), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            Button(action: shuffleActiveZone) {
                HStack(spacing: 5) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 11, weight: .bold))
                    Text("Shuffle Mood Zone (\(filteredTracks.count))")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(WalkmanTheme.hiResGoldGradient)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(filteredTracks.isEmpty)
        }
    }

    private func quadrantBackgrounds(size: CGSize) -> some View {
        let halfW = size.width / 2
        let halfH = size.height / 2

        return ZStack {
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.65, blue: 0.20).opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: min(halfW, halfH) * 1.2
            )
            .frame(width: halfW, height: halfH)
            .offset(x: halfW / 2, y: -halfH / 2)

            RadialGradient(
                colors: [Color(red: 0.85, green: 0.20, blue: 0.35).opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: min(halfW, halfH) * 1.2
            )
            .frame(width: halfW, height: halfH)
            .offset(x: -halfW / 2, y: -halfH / 2)

            RadialGradient(
                colors: [Color(red: 0.20, green: 0.35, blue: 0.75).opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: min(halfW, halfH) * 1.2
            )
            .frame(width: halfW, height: halfH)
            .offset(x: -halfW / 2, y: -halfH / 2)

            RadialGradient(
                colors: [Color(red: 0.18, green: 0.70, blue: 0.55).opacity(0.14), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: min(halfW, halfH) * 1.2
            )
            .frame(width: halfW, height: halfH)
            .offset(x: halfW / 2, y: halfH / 2)
        }
    }

    private func coordinateCrosshairs(size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: size.width - 40, height: 1)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: size.height - 40)

            Circle()
                .stroke(WalkmanTheme.hiResGold.opacity(0.25), lineWidth: 0.8)
                .frame(width: 28, height: 28)

            VStack {
                HStack {
                    Text("INTENSE / FAST")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))
                        .padding(14)
                    Spacer()
                    Text("UPBEAT / ENERGETIC")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.hiResGold.opacity(0.75))
                        .padding(14)
                }
                Spacer()
                HStack {
                    Text("MELLOW / EMOTIONAL")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))
                        .padding(14)
                    Spacer()
                    Text("RELAXED / PEACEFUL")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 0.55).opacity(0.75))
                        .padding(14)
                }
            }

            VStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text("High Arousal (Energy / Speed)")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverDark)
                .padding(.top, 8)

                Spacer()

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text("Sad / Melancholic")
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Joyful / Upbeat")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverDark)
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    Text("Low Arousal (Calm / Ambient)")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverDark)
                .padding(.bottom, 8)
            }
        }
    }

    private func trackGalaxyNode(track: Track, in size: CGSize, isHighlighted: Bool, isPlaying: Bool) -> some View {
        let val = track.senseMeValence ?? 0.0
        let aro = track.senseMeArousal ?? 0.0

        let posX = (size.width / 2) + CGFloat(val) * ((size.width - 100) / 2)
        let posY = (size.height / 2) - CGFloat(aro) * ((size.height - 100) / 2)

        let isHovered = hoveredTrack?.id == track.id

        return ZStack {
            if isPlaying {
                Circle()
                    .stroke(WalkmanTheme.hiResGold.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                    .scaleEffect(1.2)
            }

            Circle()
                .fill(
                    isPlaying ?
                        WalkmanTheme.hiResGoldGradient :
                        (isHighlighted ?
                            LinearGradient(colors: [Color.white, WalkmanTheme.hiResGoldLight], startPoint: .top, endPoint: .bottom) :
                            LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                )
                .frame(width: isPlaying ? 11 : (isHovered ? 12 : 7.5), height: isPlaying ? 11 : (isHovered ? 12 : 7.5))
                .shadow(
                    color: isHighlighted ? WalkmanTheme.hiResGold.opacity(0.6) : Color.clear,
                    radius: isHovered || isPlaying ? 6 : 2
                )
        }
        .position(x: posX, y: posY)
        .opacity(isHighlighted ? 1.0 : 0.25)
        .onHover { hovering in
            if hovering {
                self.hoveredTrack = track
            } else if self.hoveredTrack?.id == track.id {
                self.hoveredTrack = nil
            }
        }
        .onTapGesture {
            player.play(track: track, in: filteredTracks)
        }
    }

    private func hoverPopover(for track: Track, in size: CGSize) -> some View {
        let val = track.senseMeValence ?? 0.0
        let aro = track.senseMeArousal ?? 0.0

        let posX = (size.width / 2) + CGFloat(val) * ((size.width - 100) / 2)
        let posY = (size.height / 2) - CGFloat(aro) * ((size.height - 100) / 2)

        let clampX = min(max(posX, 120), size.width - 120)
        let clampY = max(posY - 60, 50)

        return HStack(spacing: 8) {
            TrackCoverThumbnail(track: track, size: 36, isPlaying: player.currentTrack?.id == track.id && player.isPlaying)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let bpm = track.senseMeBpm, bpm > 0 {
                        Text("\(Int(bpm.rounded())) BPM")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(WalkmanTheme.hiResGold)
                    }
                    Text("V: \(String(format: "%.2f", val)) • A: \(String(format: "%.2f", aro))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
        }
        .padding(8)
        .background(WalkmanTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WalkmanTheme.hiResGold.opacity(0.4), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
        .position(x: clampX, y: clampY)
        .allowsHitTesting(false)
    }

    private func shuffleActiveZone() {
        let targets = filteredTracks
        guard !targets.isEmpty else { return }
        let shuffled = targets.shuffled()
        if let first = shuffled.first {
            player.isShuffle = true
            player.play(track: first, in: shuffled)
        }
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

extension View {
    @ViewBuilder
    func carouselScrollTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1.03 : 0.88)
                    .opacity(phase.isIdentity ? 1.0 : 0.65)
                    .rotation3DEffect(
                        .degrees(Double(phase.value) * -12),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .offset(y: phase.isIdentity ? 0 : 5)
            }
        } else {
            self
        }
    }
}
