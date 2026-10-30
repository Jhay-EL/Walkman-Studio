import SwiftUI
import AppKit

public struct FullScreenNowPlayingView: View {
    @Binding var isPresented: Bool
    var libraryTracks: [Track] = []

    @ObservedObject private var player = AudioPlayerService.shared
    @ObservedObject private var progress = AudioPlayerService.shared.progress

    @State private var activeTab: RightPaneTab = .lyrics
    @State private var lyrics: String? = nil
    @State private var parsedLines: [MetadataStudioView.ParsedLyricLine] = []
    @State private var isLoadingLyrics: Bool = false
    @State private var lyricsError: String? = nil
    @State private var activeLyricId: Int? = nil
    @State private var hasInitialScrolled: Bool = false
    @State private var hoveredLyricId: Int? = nil
    @State private var isArtworkHovered: Bool = false
    @State private var lastNonZeroVolume: Float = 0.8
    @State private var isWindowFullScreen: Bool = false
    @State private var coverColors: (primary: Color, secondary: Color) = (.clear, .clear)
    @State private var isVolumeExpanded: Bool = false
    @State private var isVolumeHovered: Bool = false
    @State private var isVolumeSpeakerHovered: Bool = false
    @State private var isLyricsTabHovered: Bool = false
    @State private var isQueueTabHovered: Bool = false

    private enum RightPaneTab {
        case lyrics
        case queue
    }

    public init(isPresented: Binding<Bool>, libraryTracks: [Track] = []) {
        self._isPresented = isPresented
        self.libraryTracks = libraryTracks
    }

    public static func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    public static func formatRemaining(_ current: Double, duration: Double) -> String {
        if duration <= 0 || duration.isNaN || duration.isInfinite { return "--:--" }
        let rem = max(0.0, duration - current)
        return "-\(formatTime(rem))"
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

    public static func setWindowToolbarVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.canBecomeMain || window.isKeyWindow {
                    window.toolbar?.isVisible = visible
                    if let items = window.toolbar?.items {
                        for item in items {
                            if item.itemIdentifier.rawValue.lowercased().contains("sidebar") ||
                               item.label.lowercased().contains("sidebar") {
                                item.isEnabled = visible
                            }
                        }
                    }
                }
            }
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            let windowSize = geometry.size
            let topBarHeight: CGFloat = 92
            let contentHeight = max(200, windowSize.height - topBarHeight - 16)
            let horizontalMargin: CGFloat = windowSize.width < 900 ? 24 : 36
            let columnGap: CGFloat = windowSize.width < 900 ? 24 : 36
            let availableColumnWidth = max(200, (windowSize.width - (horizontalMargin * 2) - columnGap) / 2)

            ZStack {
                // Background: Strictly locked to window bounds so it CANNOT shift or distort layout
                playerBackground(size: windowSize)
                    .frame(width: windowSize.width, height: windowSize.height)
                    .clipped()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Navigation Strip: Close/Window controls on left, Volume control on right (positioned below macOS traffic lights)
                    topNavigationBar
                        .padding(.horizontal, horizontalMargin)
                        .padding(.top, 44)
                        .padding(.bottom, 6)
                        .frame(width: windowSize.width, height: topBarHeight, alignment: .top)

                    // Main 2-Column Split: Unified Music Controls on left, Centered Lyrics on right
                    HStack(spacing: columnGap) {
                        // Left Column: Unified Artwork, Metadata, Custom Scrubber & Transport (Centered)
                        leftTrackSection(availableWidth: availableColumnWidth, availableHeight: contentHeight)
                            .frame(width: availableColumnWidth, height: contentHeight, alignment: .center)

                        // Right Column: Apple-style Centered Synchronized Live Lyrics or Centered Queue
                        rightContentSection(availableWidth: availableColumnWidth, availableHeight: contentHeight)
                            .frame(width: availableColumnWidth, height: contentHeight, alignment: .center)
                    }
                    .padding(.horizontal, horizontalMargin)
                    .frame(width: windowSize.width, height: contentHeight)
                }
                .frame(width: windowSize.width, height: windowSize.height, alignment: .top)

                // Background dismiss tap area active ONLY when volume pod is expanded (prevents gesture interference with buttons)
                if isVolumeExpanded {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                isVolumeExpanded = false
                            }
                        }
                }

                // Bottom Right Floating Switcher (Lyrics vs Queue)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        bottomRightSwitcher
                            .padding(.trailing, horizontalMargin)
                            .padding(.bottom, 20)
                    }
                }
                .frame(width: windowSize.width, height: windowSize.height)
            }
            .frame(width: windowSize.width, height: windowSize.height)
            .clipped()
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WalkmanTheme.obsidian.ignoresSafeArea())
        .onAppear {
            Self.setWindowToolbarVisible(false)
            loadLyrics(for: player.currentTrack)
            updateCoverColors(from: player.currentCoverArt)
            checkWindowFullScreenState()
        }
        .onDisappear {
            Self.setWindowToolbarVisible(true)
        }
        .onChange(of: player.currentTrack?.id) {
            activeLyricId = nil
            loadLyrics(for: player.currentTrack)
            updateCoverColors(from: player.currentCoverArt)
        }
        .onChange(of: player.currentCoverArt) {
            updateCoverColors(from: player.currentCoverArt)
        }
        .onExitCommand {
            if isVolumeExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isVolumeExpanded = false
                }
            } else {
                dismiss()
            }
        }
    }

    private func dismiss() {
        Self.setWindowToolbarVisible(true)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
            isPresented = false
        }
    }

    private func checkWindowFullScreenState() {
        if let win = NSApp.keyWindow {
            self.isWindowFullScreen = win.styleMask.contains(.fullScreen)
        }
    }

    // MARK: - Dynamic Blurred Album Art Background (Strictly Bounded to Window Bounds)
    @ViewBuilder
    private func playerBackground(size: CGSize) -> some View {
        ZStack {
            // Base obsidian chassis
            WalkmanTheme.obsidian

            if let cover = player.currentCoverArt {
                // High-blur scaled cover artwork filling the view
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .scaleEffect(1.2)
                    .blur(radius: 90)
                    .opacity(0.85)

                // Ambient gradient wash derived from artwork palette
                LinearGradient(
                    colors: [
                        coverColors.primary.opacity(0.35),
                        coverColors.secondary.opacity(0.22),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Translucent obsidian contrast layer ensuring razor-sharp typography
                WalkmanTheme.obsidian
                    .opacity(0.60)

                // Top & bottom gentle vignettes
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.38), location: 0.0),
                        .init(color: Color.clear, location: 0.22),
                        .init(color: Color.clear, location: 0.78),
                        .init(color: Color.black.opacity(0.42), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.5), value: player.currentCoverArt)
    }

    private func updateCoverColors(from image: NSImage?) {
        guard let image = image else {
            self.coverColors = (.clear, .clear)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return }
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            guard w > 0, h > 0 else { return }

            let c1 = rep.colorAt(x: min(w - 1, w / 4), y: min(h - 1, h / 4)) ?? NSColor.black
            let c2 = rep.colorAt(x: min(w - 1, (3 * w) / 4), y: min(h - 1, (3 * h) / 4)) ?? NSColor.black

            let prim = Color(nsColor: c1)
            let sec = Color(nsColor: c2)

            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.coverColors = (prim, sec)
                }
            }
        }
    }

    // MARK: - Top Navigation Bar (Enlarged Buttons & Tactile Hits)
    private var topNavigationBar: some View {
        HStack {
            // Top-left: Separate Close & Window Fullscreen Liquid Glass Buttons
            HStack(spacing: 10) {
                // Close button (Esc)
                LiquidGlassTopBarButton(
                    systemName: "xmark",
                    iconSize: 13,
                    buttonSize: 36,
                    helpText: "Exit Full Screen (Esc)",
                    action: dismiss
                )
                .keyboardShortcut(.escape, modifiers: [])

                // Native window full screen toggle button
                LiquidGlassTopBarButton(
                    systemName: isWindowFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    iconSize: 13,
                    buttonSize: 36,
                    helpText: isWindowFullScreen ? "Exit Window Full Screen" : "Enter Window Full Screen",
                    action: {
                        if let win = NSApp.keyWindow {
                            win.toggleFullScreen(nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                checkWindowFullScreenState()
                            }
                        }
                    }
                )
            }

            Spacer()

            // Top-right: Responsive Liquid Glass Volume Capsule
            volumeControlPod
        }
    }

    @ViewBuilder
    private var volumeControlPod: some View {
        HStack(spacing: isVolumeExpanded ? 10 : 0) {
            if isVolumeExpanded {
                FullScreenVolumeSlider(volume: $player.volume)
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
                    .font(.system(size: 13, weight: isVolumeExpanded ? .bold : .semibold))
                    .foregroundStyle(
                        player.volume <= 0.001
                            ? Color.white.opacity(0.45)
                            : (isVolumeSpeakerHovered || isVolumeHovered ? .white : WalkmanTheme.silverLight)
                    )
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FullScreenTactileButtonStyle())
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
        .padding(.leading, isVolumeExpanded ? 12 : 7)
        .padding(.trailing, isVolumeExpanded ? 8 : 7)
        .padding(.vertical, 6)
        .frame(height: 38)
        .background(
            ZStack {
                if isVolumeExpanded {
                    Capsule()
                        .fill(Color.white.opacity(0.12))

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.28), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 6)
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                } else {
                    Capsule()
                        .fill(Color.white.opacity(isVolumeHovered ? 0.12 : 0.08))

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.24), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 6)
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    Color.white.opacity(isVolumeExpanded ? 0.24 : (isVolumeHovered ? 0.20 : 0.16)),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
        .clipShape(Capsule())
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.16)) {
                isVolumeHovered = h
            }
        }
    }

    // MARK: - Left: Track Info & Playback Controls (Unified Apple Music Layout)
    @ViewBuilder
    private func leftTrackSection(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        // Responsively scale artwork to ensure artwork + control pod fit inside availableHeight without vertical clipping
        let controlsHeight: CGFloat = 138
        let maxArtHeight = max(160, availableHeight - controlsHeight - 20)
        let maxArtWidth = max(160, availableWidth * 0.88)
        let artworkDimension: CGFloat = min(380, min(maxArtHeight, maxArtWidth))
        let track = player.currentTrack
        let isHiRes = (track?.bitsPerSample ?? 16) > 16 || (track?.sampleRate ?? 44100) > 48000

        let podSpacing: CGFloat = artworkDimension < 240 ? 10 : (artworkDimension < 300 ? 14 : 18)
        let innerSpacing: CGFloat = artworkDimension < 240 ? 10 : 14

        VStack(spacing: podSpacing) {
            // 1. Album Artwork
            ZStack {
                if let cover = player.currentCoverArt {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artworkDimension, height: artworkDimension)
                        .clipShape(RoundedRectangle(cornerRadius: max(12, artworkDimension * 0.055 + 4), style: .continuous))
                } else {
                    // Dark card with musical note placeholder (matching Image 1)
                    RoundedRectangle(cornerRadius: max(12, artworkDimension * 0.055 + 4), style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: artworkDimension, height: artworkDimension)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: artworkDimension * 0.28, weight: .light))
                                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.38))
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: max(12, artworkDimension * 0.055 + 4), style: .continuous)
                    .stroke(
                        isArtworkHovered ? Color.white.opacity(0.35) : Color.white.opacity(0.12),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
            .scaleEffect(isArtworkHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isArtworkHovered)
            .onHover { h in
                isArtworkHovered = h
            }

            // 2. Tightly Unified Music Control Pod (Title + Scrubber + Transport Controls)
            VStack(spacing: innerSpacing) {
                // Track Title & Artist Metadata (Left-aligned to Artwork)
                VStack(alignment: .leading, spacing: 4) {
                    if let track = track {
                        Text(track.title)
                            .font(.system(size: artworkDimension < 260 ? 18 : 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 8) {
                            Text(track.artist)
                                .font(.system(size: artworkDimension < 260 ? 13 : 15, weight: .medium))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)

                            if !track.album.isEmpty {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))

                                Text(track.album)
                                    .font(.system(size: artworkDimension < 260 ? 12 : 14, weight: .regular))
                                    .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.85))
                                    .lineLimit(1)
                            }

                            if isHiRes {
                                HStack(spacing: 3) {
                                    Text("HR")
                                        .font(.system(size: 8.5, weight: .black))
                                    Text("\(track.bitsPerSample)bit")
                                        .font(.system(size: 8.5, weight: .semibold))
                                }
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(WalkmanTheme.hiResGold.opacity(0.20))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(WalkmanTheme.hiResGold.opacity(0.50), lineWidth: 0.8)
                                )
                            }
                        }
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Select a song to start listening")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.7))
                    }
                }
                .frame(width: artworkDimension, alignment: .leading)

                // Sleek Custom Timeline Scrubber (Directly beneath metadata)
                FullScreenScrubberBar(
                    currentTime: Binding(
                        get: { progress.currentTime },
                        set: { progress.currentTime = $0 }
                    ),
                    duration: progress.duration,
                    isHiRes: isHiRes,
                    isEnabled: player.currentTrack != nil,
                    onSeek: { target in
                        player.seek(to: target)
                    }
                )
                .frame(width: artworkDimension)

                // Clean Apple-style Icon Transport Controls Row (Directly beneath scrubber)
                HStack(spacing: artworkDimension < 260 ? 20 : (artworkDimension < 320 ? 26 : 34)) {
                    // Shuffle
                    FullScreenTransportButton(
                        systemName: "shuffle",
                        size: artworkDimension < 260 ? 15 : 18,
                        isActive: player.isShuffle,
                        isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                        helpText: player.isShuffle ? "Shuffle: On" : "Shuffle: Off",
                        action: { player.isShuffle.toggle() }
                    )

                    // Previous
                    FullScreenTransportButton(
                        systemName: "backward.fill",
                        size: artworkDimension < 260 ? 20 : 24,
                        isActive: false,
                        isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                        helpText: "Previous Track",
                        action: { player.playPrevious() }
                    )

                    // Play / Pause prominent icon button (matching Apple Music Image 1)
                    Button(action: {
                        if player.currentTrack != nil {
                            player.togglePlayPause()
                        } else if let first = player.effectiveQueue.first ?? libraryTracks.first {
                            player.play(track: first, in: player.effectiveQueue)
                        }
                    }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: artworkDimension < 260 ? 28 : 34, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: artworkDimension < 260 ? 40 : 48, height: artworkDimension < 260 ? 40 : 48)
                            .scaleEffect(player.isPlaying ? 1.0 : 1.06)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FullScreenTactileButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
                    .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .onHover { h in
                        if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    // Next
                    FullScreenTransportButton(
                        systemName: "forward.fill",
                        size: artworkDimension < 260 ? 20 : 24,
                        isActive: false,
                        isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                        helpText: "Next Track",
                        action: { player.playNext() }
                    )

                    // Repeat
                    FullScreenTransportButton(
                        systemName: "repeat",
                        size: artworkDimension < 260 ? 15 : 18,
                        isActive: player.isRepeat,
                        isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                        helpText: player.isRepeat ? "Repeat: On" : "Repeat: Off",
                        action: { player.isRepeat.toggle() }
                    )
                }
                .frame(width: artworkDimension, alignment: .center)
            }
        }
        .frame(width: availableWidth, height: availableHeight, alignment: .center)
    }

    // MARK: - Right: Centered Apple-style Synchronized Live Lyrics & Queue Section
    @ViewBuilder
    private func rightContentSection(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        ZStack {
            if player.currentTrack == nil {
                // Exact text and centered layout from Image 1: "Play a song to see lyrics here."
                VStack(spacing: 8) {
                    Text("Play a song to see lyrics here.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                switch activeTab {
                case .lyrics:
                    centeredLyricsView(availableWidth: availableWidth, availableHeight: availableHeight)
                case .queue:
                    centeredQueueView
                }
            }
        }
        .frame(width: availableWidth, height: availableHeight, alignment: .center)
    }

    // MARK: - Centered Synchronized Lyrics View
    private func centeredLyricsView(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ZStack {
                if isLoadingLyrics {
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(WalkmanTheme.silverLight)
                            .scaleEffect(1.2)

                        Text("Fetching lyrics...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if parsedLines.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.4))

                        Text("No lyrics found for this song.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(WalkmanTheme.silverMuted)

                        if let tr = player.currentTrack {
                            Button(action: {
                                loadLyrics(for: tr, forceOnline: true)
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Search Online")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.85))
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    // Apple Music Style Horizontally & Vertically Centered Synchronized Lyrics Scroll
                    let topPadding = max(24, availableHeight * 0.16)
                    let bottomPadding = max(80, availableHeight * 0.50)
                    let activeSize: CGFloat = availableHeight < 550 ? 25 : 29
                    let inactiveSize: CGFloat = availableHeight < 550 ? 21 : 24
                    let lineSpacing: CGFloat = availableHeight < 550 ? 20 : 26

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .center, spacing: lineSpacing) {
                            // Top breathing room positioning initial lyrics higher (aligned with artwork)
                            Spacer()
                                .frame(height: topPadding)

                            ForEach(parsedLines, id: \.id) { line in
                                let isActive = (activeLyricId == line.id)
                                let isHovered = (hoveredLyricId == line.id)

                                Button(action: {
                                    if let t = line.timeInSeconds {
                                        player.seekTo(time: t, in: player.currentTrack)
                                    }
                                }) {
                                    Text(line.text.isEmpty ? "• • •" : line.text)
                                        .font(.system(size: isActive ? activeSize : inactiveSize, weight: isActive ? .bold : .semibold))
                                        .foregroundStyle(
                                            isActive ? Color.white :
                                            (isHovered ? Color.white.opacity(0.88) : Color.white.opacity(0.35))
                                        )
                                        .scaleEffect(isActive ? 1.03 : 1.0, anchor: .center)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .animation(.easeInOut(duration: 0.18), value: isActive)
                                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                                .onHover { h in
                                    if h {
                                        hoveredLyricId = line.id
                                        NSCursor.pointingHand.push()
                                    } else {
                                        if hoveredLyricId == line.id {
                                            hoveredLyricId = nil
                                        }
                                        NSCursor.pop()
                                    }
                                }
                            }

                            // Bottom breathing room so late lines can scroll up
                            Spacer()
                                .frame(height: bottomPadding)
                        }
                        .padding(.horizontal, 36)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.88),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            updateActiveLyric(proxy: proxy, forceScroll: true)
                        }
                    }
                    .onChange(of: progress.currentTime) {
                        updateActiveLyric(proxy: proxy)
                    }
                    .onChange(of: player.isPlaying) {
                        updateActiveLyric(proxy: proxy)
                    }
                    .onChange(of: parsedLines) {
                        activeLyricId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            updateActiveLyric(proxy: proxy, forceScroll: true)
                        }
                    }
                    .onChange(of: player.currentTrack?.id) {
                        activeLyricId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            updateActiveLyric(proxy: proxy, forceScroll: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// Lead time (0.3s / 300ms) to ensure lyric highlighting anticipates vocal onset with zero lag, matching Track Details pane.
    private let lyricLeadTimeSeconds: Double = 0.3

    private func updateActiveLyric(proxy: ScrollViewProxy, forceScroll: Bool = false) {
        guard !parsedLines.isEmpty else { return }
        let now = progress.currentTime + lyricLeadTimeSeconds
        var targetId: Int? = nil

        for line in parsedLines {
            guard let t = line.timeInSeconds else { continue }
            if now >= t {
                targetId = line.id
            } else {
                break
            }
        }

        if forceScroll || targetId != activeLyricId {
            activeLyricId = targetId
            hasInitialScrolled = true
            if let id = targetId {
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }
    }

    // MARK: - Centered Queue (Playing Next) View
    private var centeredQueueView: some View {
        let queueTracks = player.currentQueue.isEmpty ? libraryTracks : player.currentQueue

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Playing Next")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("(\(queueTracks.count) songs)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer()
            }
            .padding(.horizontal, 24)

            if queueTracks.isEmpty {
                VStack(spacing: 8) {
                    Text("Queue is empty")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(queueTracks.enumerated()), id: \.element.id) { index, item in
                            let isCurrent = (player.currentTrack?.id == item.id)
                            QueueRowView(
                                index: index,
                                item: item,
                                isCurrent: isCurrent,
                                isPlaying: player.isPlaying,
                                onPlay: {
                                    player.play(track: item, in: queueTracks)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
        }
        .frame(maxWidth: 580, alignment: .center)
    }

    // MARK: - Bottom Right Switcher (Enlarged Lyrics vs Queue)
    private var bottomRightSwitcher: some View {
        HStack(spacing: 4) {
            // Lyrics Button
            Button(action: {
                if activeTab != .lyrics {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                        activeTab = .lyrics
                    }
                }
            }) {
                ZStack {
                    if activeTab == .lyrics {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(isLyricsTabHovered ? 0.10 : 0.001))
                    }

                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(activeTab == .lyrics ? .white : (isLyricsTabHovered ? .white : WalkmanTheme.silverMuted))
                }
                .frame(width: 42, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .scaleEffect(isLyricsTabHovered && activeTab != .lyrics ? 1.05 : 1.0)
                .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isLyricsTabHovered)
            }
            .buttonStyle(FullScreenTactileButtonStyle())
            .help("Synchronized Live Lyrics")
            .onHover { h in
                isLyricsTabHovered = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Queue Button (Track List)
            Button(action: {
                if activeTab != .queue {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                        activeTab = .queue
                    }
                }
            }) {
                ZStack {
                    if activeTab == .queue {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Color.white.opacity(isQueueTabHovered ? 0.10 : 0.001))
                    }

                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(activeTab == .queue ? .white : (isQueueTabHovered ? .white : WalkmanTheme.silverMuted))
                }
                .frame(width: 42, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .scaleEffect(isQueueTabHovered && activeTab != .queue ? 1.05 : 1.0)
                .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isQueueTabHovered)
            }
            .buttonStyle(FullScreenTactileButtonStyle())
            .help("Playing Next Queue")
            .onHover { h in
                isQueueTabHovered = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(4)
        .background(
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.09))
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
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.85))
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
    }

    // MARK: - Lyrics Loading Logic
    private func loadLyrics(for track: Track?, forceOnline: Bool = false) {
        guard let track = track else {
            self.lyrics = nil
            self.parsedLines = []
            self.lyricsError = nil
            self.isLoadingLyrics = false
            self.activeLyricId = nil
            self.hasInitialScrolled = false
            return
        }

        self.isLoadingLyrics = true
        self.lyricsError = nil
        self.activeLyricId = nil
        self.hasInitialScrolled = false

        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = URL(fileURLWithPath: track.fullPath)
            let local = !forceOnline ? AudioTagger.shared.extractLyrics(fileURL: fileURL) : nil
            let localParsed = (local != nil && !local!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?
                MetadataStudioView.parseLyrics(local, durationSeconds: track.durationSeconds) : []
            let isLocalSynced = local != nil && local!.contains("[") && localParsed.contains(where: { $0.timeInSeconds != nil })

            if isLocalSynced {
                DispatchQueue.main.async {
                    guard self.player.currentTrack?.id == track.id else { return }
                    self.lyrics = local
                    self.parsedLines = localParsed
                    self.isLoadingLyrics = false
                }
                return
            }

            // If local lyrics are missing or plain text (unsynced), fetch synchronized lyrics online via LyricsService
            Task {
                do {
                    let res = try await LyricsService.shared.fetchLyrics(
                        title: track.title,
                        artist: track.artist,
                        album: track.album,
                        durationSeconds: track.durationSeconds
                    )
                    await MainActor.run {
                        guard self.player.currentTrack?.id == track.id else { return }
                        self.lyrics = res.lyrics
                        self.parsedLines = MetadataStudioView.parseLyrics(res.lyrics, durationSeconds: track.durationSeconds)
                        self.isLoadingLyrics = false
                    }
                } catch {
                    await MainActor.run {
                        guard self.player.currentTrack?.id == track.id else { return }
                        if let local = local, !localParsed.isEmpty {
                            // Fallback to local plain lyrics with synthesized progressive timestamps
                            self.lyrics = local
                            self.parsedLines = localParsed
                            self.lyricsError = nil
                        } else {
                            self.lyrics = nil
                            self.parsedLines = []
                            self.lyricsError = "No lyrics found online"
                        }
                        self.isLoadingLyrics = false
                    }
                }
            }
        }
    }
}

// MARK: - Subviews & Styles

struct FullScreenTactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct LiquidGlassTopBarButton: View {
    let systemName: String
    var iconSize: CGFloat = 13
    var iconWeight: Font.Weight = .bold
    var buttonSize: CGFloat = 36
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Liquid glass background fill
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.08))

                // Specular top reflection sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.34 : 0.22), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.6),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())

                // Hairline specular border
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHovered ? 0.32 : 0.20), location: 0.0),
                                .init(color: .white.opacity(isHovered ? 0.16 : 0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )

                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: iconWeight))
                    .foregroundStyle(isHovered ? .white : WalkmanTheme.silverLight)
            }
            .frame(width: buttonSize, height: buttonSize)
            .shadow(color: Color.black.opacity(isHovered ? 0.38 : 0.24), radius: isHovered ? 8 : 5, x: 0, y: isHovered ? 3 : 2)
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Circle())
        }
        .buttonStyle(FullScreenTactileButtonStyle())
        .help(helpText)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct FullScreenScrubberBar: View {
    @Binding var currentTime: Double
    let duration: Double
    let isHiRes: Bool
    let isEnabled: Bool
    let onSeek: (Double) -> Void

    @State private var dragValue: Double? = nil
    @State private var isHovering: Bool = false

    private var activeTime: Double {
        dragValue ?? currentTime
    }

    private var progressRatio: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, activeTime / duration)))
    }

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

    private func formatRemaining(_ current: Double, duration: Double) -> String {
        if duration <= 0 || duration.isNaN || duration.isInfinite { return "--:--" }
        let rem = max(0.0, duration - current)
        return "-\(formatTime(rem))"
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                let thumbX = w * progressRatio
                let trackHeight: CGFloat = isHovering ? 5.5 : 4.0

                ZStack(alignment: .leading) {
                    // Base background track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: trackHeight)

                    // Active progress fill
                    Capsule()
                        .fill(isHiRes ? WalkmanTheme.hiResGold : Color.white)
                        .frame(width: max(0, min(w, thumbX)), height: trackHeight)

                    // Smooth tracking thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isHovering ? 13 : 10, height: isHovering ? 13 : 10)
                        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, min(w - (isHovering ? 13 : 10), thumbX - (isHovering ? 6.5 : 5.0))))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard isEnabled, duration > 0 else { return }
                            let ratio = max(0, min(1, gesture.location.x / w))
                            dragValue = Double(ratio) * duration
                        }
                        .onEnded { gesture in
                            guard isEnabled, duration > 0 else { return }
                            let ratio = max(0, min(1, gesture.location.x / w))
                            let target = Double(ratio) * duration
                            onSeek(target)
                            dragValue = nil
                        }
                )
            }
            .frame(height: 14)
            .onHover { h in
                guard isEnabled else { return }
                isHovering = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Timeline elapsed and remaining counters
            HStack {
                Text(isEnabled ? formatTime(activeTime) : "--:--")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer()

                Text(isEnabled ? formatRemaining(activeTime, duration: duration) : "--:--")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
    }
}

private struct FullScreenTransportButton: View {
    let systemName: String
    let size: CGFloat
    let isActive: Bool
    var isDisabled: Bool = false
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: isActive ? .bold : .semibold))
                .foregroundStyle(
                    isDisabled ? Color.white.opacity(0.20) :
                    (isActive ? WalkmanTheme.hiResGold : (isHovered ? .white : Color.white.opacity(0.70)))
                )
                .frame(width: 44, height: 44)
                .scaleEffect(isHovered && !isDisabled ? 1.12 : 1.0)
        }
        .buttonStyle(FullScreenTactileButtonStyle())
        .disabled(isDisabled)
        .help(helpText)
        .onHover { h in
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct QueueRowView: View {
    let index: Int
    let item: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                if isCurrent && isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .frame(width: 24)
                } else {
                    Text("\(index + 1)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(isCurrent ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted.opacity(0.6))
                        .frame(width: 24, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? WalkmanTheme.hiResGoldLight : .white)
                        .lineLimit(1)

                    Text(item.artist)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(FullScreenNowPlayingView.formatTime(item.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isCurrent ?
                Color.white.opacity(0.09) :
                (isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct FullScreenVolumeSlider: View {
    @Binding var volume: Float
    let totalWidth: CGFloat = 96
    let trackHeight: CGFloat = 6.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clampedVol = CGFloat(max(0.0, min(1.0, volume)))
            let fillWidth = max(0, w * clampedVol)

            ZStack(alignment: .leading) {
                // Background Track
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
        .frame(width: totalWidth, height: 26)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
