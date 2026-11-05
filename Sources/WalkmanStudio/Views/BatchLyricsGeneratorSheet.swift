import SwiftUI
import AppKit

// MARK: - Batch Lyrics Generator Sheet
public struct BatchLyricsGeneratorSheet: View {
    public enum TabContext: Equatable {
        case allSongs
        case recentlyAdded
        case hiRes
        case languageStudy
        case albums(selectedAlbumName: String?, albumTrackCount: Int)
        case artists(selectedArtistName: String?, artistTrackCount: Int)
        case playlist(playlistName: String, playlistTrackCount: Int)
    }

    public enum LyricsScope: String, CaseIterable, Identifiable {
        case allInTab = "All Tracks in View"
        case selectedOnly = "Selected Track(s)"
        case contextOnly = "Active Item"
        case customSelection = "Choose Specific..."

        public var id: String { rawValue }
    }

    private enum SheetState {
        case configure
        case running
        case completed
    }

    public enum LyricsFetchCategory: String, CaseIterable, Identifiable, Sendable {
        case synced = "Synced .LRC"
        case plain = "Plain Text"
        case skipped = "Skipped"
        case notFound = "Not Found"

        public var id: String { rawValue }

        public var color: Color {
            switch self {
            case .synced: return .green
            case .plain: return .blue
            case .skipped: return WalkmanTheme.silverMuted
            case .notFound: return .orange
            }
        }

        public var icon: String {
            switch self {
            case .synced: return "quote.bubble.fill"
            case .plain: return "doc.text.fill"
            case .skipped: return "forward.fill"
            case .notFound: return "exclamationmark.triangle.fill"
            }
        }
    }

    public struct TrackFetchResultItem: Identifiable, Sendable {
        public let id: String
        public let track: Track
        public let category: LyricsFetchCategory
        public let detail: String
        public let timestamp: Date
    }

    // Input parameters
    let allTracks: [Track]
    let selectedTracks: [Track]
    let tabContext: TabContext
    let precomputedAlbums: [AlbumItem]?
    let precomputedArtists: [ArtistItem]?
    let onDismiss: () -> Void

    // Configuration State
    @State private var selectedScope: LyricsScope = .allInTab
    @State private var onlyMissingLyrics: Bool = true
    @State private var sheetState: SheetState = .configure

    // Custom Scope Selection State
    @State private var customSearchText: String = ""
    @State private var selectedCustomTrackIds: Set<String> = []
    @State private var selectedCustomAlbumIds: Set<String> = []
    @State private var selectedCustomArtistIds: Set<String> = []

    // Background Lyrics Scan State
    @State private var isScanningLyrics: Bool = true
    @State private var tracksWithLyricsIds: Set<String> = []
    @State private var lyricsScanTask: Task<Void, Never>? = nil

    // Progress State
    @State private var totalTracksToProcess: Int = 0
    @State private var processedCount: Int = 0
    @State private var syncedCount: Int = 0
    @State private var plainCount: Int = 0
    @State private var skippedCount: Int = 0
    @State private var notFoundCount: Int = 0
    @State private var fetchedResultItems: [TrackFetchResultItem] = []
    @State private var selectedMetricCategory: LyricsFetchCategory? = nil
    @State private var breakdownSearchQuery: String = ""
    @State private var currentTrackTitle: String = ""
    @State private var currentTrackArtist: String = ""
    @State private var currentTrackStage: String = ""
    @State private var etaString: String = "Estimating..."
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var startTime: Date? = nil

    // Hover states for buttons
    @State private var isPrimaryHovered: Bool = false
    @State private var isCancelHovered: Bool = false
    @State private var showWarningPopover: Bool = false
    @State private var showInfoPopover: Bool = false

    public init(
        allTracks: [Track],
        selectedTracks: [Track],
        tabContext: TabContext = .allSongs,
        precomputedAlbums: [AlbumItem]? = nil,
        precomputedArtists: [ArtistItem]? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.allTracks = allTracks
        self.selectedTracks = selectedTracks
        self.tabContext = tabContext
        self.precomputedAlbums = precomputedAlbums
        self.precomputedArtists = precomputedArtists
        self.onDismiss = onDismiss

        // Initial default scope
        if !selectedTracks.isEmpty {
            _selectedScope = State(initialValue: .selectedOnly)
        } else {
            switch tabContext {
            case .albums(let name, _):
                _selectedScope = State(initialValue: name != nil ? .contextOnly : .allInTab)
            case .artists(let name, _):
                _selectedScope = State(initialValue: name != nil ? .contextOnly : .allInTab)
            default:
                _selectedScope = State(initialValue: .allInTab)
            }
        }
    }

    // MARK: - Precomputed Collections
    private var availableAlbums: [AlbumItem] {
        if let albums = precomputedAlbums, !albums.isEmpty {
            return albums
        }
        return AlbumsView.buildAlbums(from: allTracks)
    }

    private var availableArtists: [ArtistItem] {
        if let artists = precomputedArtists, !artists.isEmpty {
            return artists
        }
        return ArtistsView.buildArtists(from: allTracks)
    }

    // MARK: - Computed Target Tracks
    private var candidateTracks: [Track] {
        switch selectedScope {
        case .allInTab:
            return allTracks
        case .selectedOnly:
            return selectedTracks.isEmpty ? allTracks : selectedTracks
        case .contextOnly:
            switch tabContext {
            case .albums(let name, _):
                if let albumName = name {
                    return allTracks.filter { $0.album.localizedCaseInsensitiveCompare(albumName) == .orderedSame }
                }
                return allTracks
            case .artists(let name, _):
                if let artistName = name {
                    return allTracks.filter { $0.artist.localizedCaseInsensitiveCompare(artistName) == .orderedSame }
                }
                return allTracks
            default:
                return allTracks
            }
        case .customSelection:
            switch tabContext {
            case .albums:
                let matched = availableAlbums.filter { selectedCustomAlbumIds.contains($0.id) }
                return matched.flatMap(\.tracks)
            case .artists:
                let matched = availableArtists.filter { selectedCustomArtistIds.contains($0.id) }
                return matched.flatMap(\.tracks)
            default:
                return allTracks.filter { selectedCustomTrackIds.contains($0.id) }
            }
        }
    }

    private var targetTracks: [Track] {
        if onlyMissingLyrics {
            return candidateTracks.filter { !tracksWithLyricsIds.contains($0.id) }
        } else {
            return candidateTracks
        }
    }

    private func scanExistingLyricsAsync() {
        guard onlyMissingLyrics else {
            isScanningLyrics = false
            return
        }
        lyricsScanTask?.cancel()
        isScanningLyrics = true
        let snapshotTracks = candidateTracks
        lyricsScanTask = Task.detached(priority: .userInitiated) {
            var foundIds = Set<String>()
            for track in snapshotTracks {
                if Task.isCancelled { return }
                let url = URL(fileURLWithPath: track.fullPath)
                let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
                let upperLrcURL = url.deletingPathExtension().appendingPathExtension("LRC")
                if FileManager.default.fileExists(atPath: lrcURL.path) || FileManager.default.fileExists(atPath: upperLrcURL.path) {
                    foundIds.insert(track.id)
                } else if AudioTagger.shared.extractLyrics(fileURL: url) != nil {
                    foundIds.insert(track.id)
                }
            }
            let completedFoundIds = foundIds
            if Task.isCancelled { return }
            await MainActor.run {
                self.tracksWithLyricsIds = completedFoundIds
                self.isScanningLyrics = false
            }
        }
    }

    private var tracksWithLyricsCount: Int {
        candidateTracks.count - targetTracks.count
    }

    private var isOver100Tracks: Bool {
        candidateTracks.count > 100
    }

    private var currentProgress: Double {
        guard totalTracksToProcess > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedCount) / Double(totalTracksToProcess)))
    }

    // MARK: - Body View
    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar with Close Button
            HStack {
                Spacer()
                SheetCloseButton(action: {
                    cancelAndDismiss()
                })
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)
            .frame(height: 36)

            // Header Section
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Body Content based on State
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    switch sheetState {
                    case .configure:
                        configurationContent
                    case .running:
                        runningProgressContent
                    case .completed:
                        completedSummaryContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Section
            footerActionsSection
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(
            minWidth: 620,
            idealWidth: 680,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 640,
            maxHeight: .infinity
        )
        .background(
            SheetWindowResizer(
                minSize: NSSize(width: 620, height: 520)
            )
        )
        .onAppear {
            initializeCustomSelectionDefaults()
            scanExistingLyricsAsync()
        }
        .onChange(of: selectedScope) { _, _ in
            scanExistingLyricsAsync()
        }
        .onChange(of: onlyMissingLyrics) { _, _ in
            scanExistingLyricsAsync()
        }
        .onChange(of: selectedCustomTrackIds) { _, _ in
            if selectedScope == .customSelection {
                scanExistingLyricsAsync()
            }
        }
        .onChange(of: selectedCustomAlbumIds) { _, _ in
            if selectedScope == .customSelection {
                scanExistingLyricsAsync()
            }
        }
        .onChange(of: selectedCustomArtistIds) { _, _ in
            if selectedScope == .customSelection {
                scanExistingLyricsAsync()
            }
        }
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.92)
                    .background(.ultraThinMaterial)

                // Top specular refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 235/255, green: 240/255, blue: 255/255), location: 0.0),
                                .init(color: Color(red: 175/255, green: 195/255, blue: 235/255), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.40), lineWidth: 0.85)
                    )

                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
            }
            .shadow(color: Color.black.opacity(0.30), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(sheetTitle)
                        .font(WalkmanFont.title1)
                        .foregroundStyle(.primary)

                    if sheetState == .configure {
                        if isOver100Tracks {
                            warningBadgeButton
                        }

                        infoIconButton
                    }
                }

                Text(sheetSubtitle)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var warningBadgeButton: some View {
        Button(action: { showWarningPopover.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)
                Text("Large Library")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.orange.opacity(0.16))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.40), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            showWarningPopover = isHovered
        }
        .popover(isPresented: $showWarningPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.orange)

                    Text("Large Library Notice (\(candidateTracks.count) Tracks)")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(Color.orange)
                }

                Text("Fetching lyrics for over 100 tracks involves individual API searches and may take several minutes. Walkman Studio uses parallel multi-worker concurrent requests (5 simultaneous threads) to maximize performance while adhering to public API limits.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverLight.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 360)
            .background(
                WalkmanTheme.card.opacity(0.96)
                    .background(.ultraThinMaterial)
            )
        }
        .help("Large Library Notice: Fetching lyrics for over 100 tracks involves individual API searches and may take several minutes.")
    }

    private var infoIconButton: some View {
        Button(action: { showInfoPopover.toggle() }) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .padding(4)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            showInfoPopover = isHovered
        }
        .popover(isPresented: $showInfoPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.blue)

                    Text("How Walkman Studio Lyrics Work")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }

                Text("This tool queries online databases (preferring timestamped synchronized .LRC from LRCLIB, with Lyrics.ovh as fallback) and creates companion .lrc files alongside your music files. The Sony Walkman OS and Android Walkman Music Player automatically read companion .lrc files during playback.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverLight.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 360)
            .background(
                WalkmanTheme.card.opacity(0.96)
                    .background(.ultraThinMaterial)
            )
        }
        .help("How Walkman Studio Lyrics Work: Queries online databases and creates companion .lrc files alongside music files.")
    }

    private var sheetTitle: String {
        switch sheetState {
        case .configure:
            return "LRC Fetcher"
        case .running:
            return "Fetching .LRC Lyrics..."
        case .completed:
            return "LRC Fetch Complete"
        }
    }

    private var sheetSubtitle: String {
        switch sheetState {
        case .configure:
            switch tabContext {
            case .playlist(let name, _):
                return "Batch search online databases for synchronized .lrc lyrics for playlist '\(name)' and sync them to your Sony Walkman storage."
            default:
                return "Batch search online databases for synchronized .lrc lyrics and sync them directly to your Sony Walkman storage."
            }
        case .running:
            return "Parallel multi-track fetching active. Searching LRCLIB and Lyrics.ovh for timestamped .LRC lyrics..."
        case .completed:
            return "Finished scanning and saving .lrc companion files to your Walkman library."
        }
    }

    // MARK: - Configure View
    private var configurationContent: some View {
        VStack(spacing: 16) {
            // Scope Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("FETCH SCOPE")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    // Option 1: All in Tab
                    scopeOptionRow(
                        title: allInTabTitle,
                        subtitle: allInTabSubtitle,
                        scope: .allInTab
                    )

                    // Option 2: Pre-selected tracks (if user had selected items)
                    if !selectedTracks.isEmpty {
                        scopeOptionRow(
                            title: "Selected Track\(selectedTracks.count > 1 ? "s" : "") Only",
                            subtitle: "\(selectedTracks.count) currently selected audio track\(selectedTracks.count > 1 ? "s" : "")",
                            scope: .selectedOnly
                        )
                    }

                    // Option 3: Context-specific active item (Current Album or Current Artist)
                    switch tabContext {
                    case .albums(let name, let count):
                        if let albumName = name {
                            scopeOptionRow(
                                title: "Current Album: \(albumName)",
                                subtitle: "\(count) tracks in this album",
                                scope: .contextOnly
                            )
                        }
                    case .artists(let name, let count):
                        if let artistName = name {
                            scopeOptionRow(
                                title: "Current Artist: \(artistName)",
                                subtitle: "\(count) tracks by this artist",
                                scope: .contextOnly
                            )
                        }
                    default:
                        EmptyView()
                    }

                    // Option 4: Custom selection
                    scopeOptionRow(
                        title: customSelectionTitle,
                        subtitle: customSelectionSubtitle,
                        scope: .customSelection
                    )
                }

                // If Custom Selection is selected, show the interactive item picker card
                if selectedScope == .customSelection {
                    customPickerCard
                        .padding(.top, 4)
                }
            }

            // Filter Toggles
            VStack(alignment: .leading, spacing: 8) {
                Text("OPTIMIZATION & CACHE")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                Button(action: {
                    onlyMissingLyrics.toggle()
                }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: onlyMissingLyrics ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(onlyMissingLyrics ? Color.white : WalkmanTheme.silverMuted)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Only fetch for tracks missing lyrics (Recommended)")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(WalkmanTheme.silverLight)
                            if isScanningLyrics {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                    Text("Analyzing library for existing lyrics...")
                                        .font(WalkmanFont.caption)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                            } else {
                                Text(onlyMissingLyrics
                                     ? "Skips \(tracksWithLyricsCount) tracks that already have .LRC files; fetches for \(targetTracks.count) tracks."
                                     : "Will re-fetch and overwrite .lrc files for all \(candidateTracks.count) tracks.")
                                    .font(WalkmanFont.caption)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                        }

                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Dynamic Scope Labels
    private var allInTabTitle: String {
        switch tabContext {
        case .allSongs:
            return "All Songs in Library"
        case .recentlyAdded:
            return "All Recently Added"
        case .hiRes:
            return "All Hi-Res Audio Tracks"
        case .languageStudy:
            return "All Language Study Tracks"
        case .albums:
            return "All Albums"
        case .artists:
            return "All Artists"
        case .playlist(let name, _):
            return "All Tracks in '\(name)'"
        }
    }

    private var allInTabSubtitle: String {
        switch tabContext {
        case .albums:
            return "\(availableAlbums.count) albums (\(allTracks.count) total tracks)"
        case .artists:
            return "\(availableArtists.count) artists (\(allTracks.count) total tracks)"
        case .playlist(let name, let count):
            return "\(count) tracks in playlist '\(name)'"
        default:
            return "\(allTracks.count) tracks in the current library tab"
        }
    }

    private var customSelectionTitle: String {
        switch tabContext {
        case .albums:
            return "Select Specific Albums..."
        case .artists:
            return "Select Specific Artists..."
        default:
            return "Select Specific Tracks..."
        }
    }

    private var customSelectionSubtitle: String {
        switch tabContext {
        case .albums:
            let selectedCount = selectedCustomAlbumIds.count
            return "\(selectedCount) of \(availableAlbums.count) albums selected (\(candidateTracks.count) tracks)"
        case .artists:
            let selectedCount = selectedCustomArtistIds.count
            return "\(selectedCount) of \(availableArtists.count) artists selected (\(candidateTracks.count) tracks)"
        default:
            let selectedCount = selectedCustomTrackIds.count
            return "\(selectedCount) of \(allTracks.count) tracks selected"
        }
    }

    // MARK: - Custom Item Picker Card
    private var customPickerCard: some View {
        VStack(spacing: 8) {
            // Search Box and Quick Actions
            HStack(spacing: 8) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    TextField(customSearchPlaceholder, text: $customSearchText)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.white)

                    if !customSearchText.isEmpty {
                        Button(action: { customSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )

                // Select All Button
                Button(action: selectAllCustomItems) {
                    Text("Select All")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                // Deselect All Button
                Button(action: deselectAllCustomItems) {
                    Text("Deselect All")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Scrollable List of Items
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 3) {
                    switch tabContext {
                    case .albums:
                        ForEach(filteredAlbums) { album in
                            albumRow(album)
                        }
                    case .artists:
                        ForEach(filteredArtists) { artist in
                            artistRow(artist)
                        }
                    default:
                        ForEach(filteredTracks) { track in
                            trackRow(track)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140, idealHeight: 180, maxHeight: 380)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
        )
    }

    private var customSearchPlaceholder: String {
        switch tabContext {
        case .albums: return "Search albums or artists..."
        case .artists: return "Search artists..."
        default: return "Search tracks by title, artist, or album..."
        }
    }

    private var filteredTracks: [Track] {
        let query = customSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return allTracks }
        return allTracks.filter { track in
            track.title.localizedCaseInsensitiveContains(query) ||
            track.artist.localizedCaseInsensitiveContains(query) ||
            track.album.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredAlbums: [AlbumItem] {
        let query = customSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return availableAlbums }
        return availableAlbums.filter { album in
            album.name.localizedCaseInsensitiveContains(query) ||
            album.artist.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredArtists: [ArtistItem] {
        let query = customSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return availableArtists }
        return availableArtists.filter { artist in
            artist.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func selectAllCustomItems() {
        switch tabContext {
        case .albums:
            for album in filteredAlbums {
                selectedCustomAlbumIds.insert(album.id)
            }
        case .artists:
            for artist in filteredArtists {
                selectedCustomArtistIds.insert(artist.id)
            }
        default:
            for track in filteredTracks {
                selectedCustomTrackIds.insert(track.id)
            }
        }
    }

    private func deselectAllCustomItems() {
        switch tabContext {
        case .albums:
            if customSearchText.isEmpty {
                selectedCustomAlbumIds.removeAll()
            } else {
                for album in filteredAlbums {
                    selectedCustomAlbumIds.remove(album.id)
                }
            }
        case .artists:
            if customSearchText.isEmpty {
                selectedCustomArtistIds.removeAll()
            } else {
                for artist in filteredArtists {
                    selectedCustomArtistIds.remove(artist.id)
                }
            }
        default:
            if customSearchText.isEmpty {
                selectedCustomTrackIds.removeAll()
            } else {
                for track in filteredTracks {
                    selectedCustomTrackIds.remove(track.id)
                }
            }
        }
    }

    private func trackRow(_ track: Track) -> some View {
        let isSelected = selectedCustomTrackIds.contains(track.id)
        return Button(action: {
            if isSelected {
                selectedCustomTrackIds.remove(track.id)
            } else {
                selectedCustomTrackIds.insert(track.id)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : WalkmanTheme.silverMuted)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title.isEmpty ? track.filename : track.title)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)
                    Text("\(track.artist.isEmpty ? "Unknown Artist" : track.artist) • \(track.album.isEmpty ? "Unknown Album" : track.album)")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.format.uppercased())
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func albumRow(_ album: AlbumItem) -> some View {
        let isSelected = selectedCustomAlbumIds.contains(album.id)
        return Button(action: {
            if isSelected {
                selectedCustomAlbumIds.remove(album.id)
            } else {
                selectedCustomAlbumIds.insert(album.id)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : WalkmanTheme.silverMuted)

                // Album Thumbnail Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 12))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(album.trackCount) tracks")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func artistRow(_ artist: ArtistItem) -> some View {
        let isSelected = selectedCustomArtistIds.contains(artist.id)
        return Button(action: {
            if isSelected {
                selectedCustomArtistIds.remove(artist.id)
            } else {
                selectedCustomArtistIds.insert(artist.id)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : WalkmanTheme.silverMuted)

                // Artist Avatar Icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: "music.mic")
                        .font(.system(size: 11))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(artist.name)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)
                    Text("\(artist.albumCount) albums • \(artist.trackCount) tracks")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(artist.trackCount) tracks")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func initializeCustomSelectionDefaults() {
        if selectedCustomTrackIds.isEmpty {
            selectedCustomTrackIds = !selectedTracks.isEmpty ? Set(selectedTracks.map(\.id)) : Set(allTracks.map(\.id))
        }
        if selectedCustomAlbumIds.isEmpty {
            switch tabContext {
            case .albums(let name, _):
                if let albumName = name {
                    let matches = availableAlbums.filter { $0.name.localizedCaseInsensitiveCompare(albumName) == .orderedSame }
                    selectedCustomAlbumIds = Set(matches.map(\.id))
                } else {
                    selectedCustomAlbumIds = Set(availableAlbums.map(\.id))
                }
            default:
                selectedCustomAlbumIds = Set(availableAlbums.map(\.id))
            }
        }
        if selectedCustomArtistIds.isEmpty {
            switch tabContext {
            case .artists(let name, _):
                if let artistName = name {
                    let matches = availableArtists.filter { $0.name.localizedCaseInsensitiveCompare(artistName) == .orderedSame }
                    selectedCustomArtistIds = Set(matches.map(\.id))
                } else {
                    selectedCustomArtistIds = Set(availableArtists.map(\.id))
                }
            default:
                selectedCustomArtistIds = Set(availableArtists.map(\.id))
            }
        }
    }

    private func scopeOptionRow(title: String, subtitle: String, scope: LyricsScope) -> some View {
        Button(action: {
            selectedScope = scope
        }) {
            HStack(spacing: 12) {
                Image(systemName: selectedScope == scope ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedScope == scope ? Color.white : WalkmanTheme.silverMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                    Text(subtitle)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(12)
            .background(
                ZStack {
                    if selectedScope == scope {
                        Color.white.opacity(0.08)
                    } else {
                        Color.white.opacity(0.03)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selectedScope == scope ? Color.white.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 0.85)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Running View
    private var runningProgressContent: some View {
        VStack(spacing: 20) {
            // Live Progress Bar & Percent
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.85))

                        let fillWidth = max(8, geo.size.width * CGFloat(currentProgress))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(red: 235/255, green: 240/255, blue: 255/255), location: 0.0),
                                        .init(color: Color(red: 175/255, green: 205/255, blue: 255/255), location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                            .shadow(color: Color.blue.opacity(0.35), radius: 4, x: 0, y: 1)
                    }
                }
                .frame(height: 10)
                .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.80), value: currentProgress)

                HStack {
                    Text("\(processedCount) of \(totalTracksToProcess) tracks")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(etaString)
                    }
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                    Spacer()

                    Text("\(Int(currentProgress * 100))%")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }
            .padding(.top, 10)

            // Current Track Ticker Card
            if !currentTrackTitle.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)

                        Text(currentTrackTitle + (currentTrackArtist.isEmpty ? "" : " • \(currentTrackArtist)"))
                            .font(WalkmanFont.calloutMedium)
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )

                    if !currentTrackStage.isEmpty {
                        Text(currentTrackStage)
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                }
            }

            // Real-Time Stats Chips (Liquid Glass)
            HStack(spacing: 10) {
                ForEach(LyricsFetchCategory.allCases) { cat in
                    LiquidGlassMetricButton(
                        category: cat,
                        count: count(for: cat),
                        isSelected: selectedMetricCategory == cat,
                        action: { toggleCategory(cat) }
                    )
                }
            }
            .padding(.top, 4)

            // Expandable Track Breakdown List
            trackBreakdownCard
        }
    }

    // MARK: - Completed View
    private var completedSummaryContent: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Color.green.opacity(0.35), lineWidth: 0.85))

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.green)
            }
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("LRC Batch Fetch Complete")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(WalkmanTheme.silverLight)

                Text("Successfully checked \(totalTracksToProcess) tracks in your Walkman Library.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
            }

            // Results Matrix (Liquid Glass)
            HStack(spacing: 10) {
                ForEach(LyricsFetchCategory.allCases) { cat in
                    LiquidGlassMetricButton(
                        category: cat,
                        count: count(for: cat),
                        isSelected: selectedMetricCategory == cat,
                        action: { toggleCategory(cat) }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green.opacity(0.85))
                Text("Hardware companion .LRC files saved with timestamp metadata preserved.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .padding(.top, 2)

            // Expandable Track Breakdown List
            trackBreakdownCard
                .padding(.horizontal, 4)
        }
    }

    private func count(for category: LyricsFetchCategory) -> Int {
        switch category {
        case .synced: return syncedCount
        case .plain: return plainCount
        case .skipped: return skippedCount
        case .notFound: return notFoundCount
        }
    }

    private func toggleCategory(_ category: LyricsFetchCategory) {
        withAnimation(.easeInOut(duration: 0.20)) {
            if selectedMetricCategory == category {
                selectedMetricCategory = nil
            } else {
                selectedMetricCategory = category
                breakdownSearchQuery = ""
            }
        }
    }

    private var currentCategoryItems: [TrackFetchResultItem] {
        guard let cat = selectedMetricCategory else { return [] }
        return fetchedResultItems.filter { $0.category == cat }
    }

    private var filteredCategoryItems: [TrackFetchResultItem] {
        let q = breakdownSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return currentCategoryItems
        }
        return currentCategoryItems.filter { item in
            item.track.title.lowercased().contains(q) ||
            item.track.artist.lowercased().contains(q) ||
            item.track.album.lowercased().contains(q)
        }
    }

    private func breakdownHeaderTitle(for category: LyricsFetchCategory) -> String {
        switch category {
        case .notFound:
            return "Tracks with No Lyrics Found"
        case .synced:
            return "Tracks with Synced .LRC Saved"
        case .plain:
            return "Tracks with Plain Lyrics Saved"
        case .skipped:
            return "Skipped Tracks (Already Had .LRC)"
        }
    }

    @ViewBuilder
    private var trackBreakdownCard: some View {
        if let category = selectedMetricCategory {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(category.color)

                    Text(breakdownHeaderTitle(for: category))
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text("\(currentCategoryItems.count)")
                        .font(WalkmanFont.monoSmall)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(category.color.opacity(0.18))
                        .foregroundStyle(category.color)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(category.color.opacity(0.35), lineWidth: 0.8))

                    Spacer()

                    if currentCategoryItems.count > 3 {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            TextField("Filter tracks...", text: $breakdownSearchQuery)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.caption)
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .frame(width: 120)
                            if !breakdownSearchQuery.isEmpty {
                                Button(action: { breakdownSearchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            selectedMetricCategory = nil
                            breakdownSearchQuery = ""
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .padding(5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close breakdown")
                }

                Divider()
                    .overlay(Color.white.opacity(0.06))

                if filteredCategoryItems.isEmpty {
                    HStack {
                        Spacer()
                        Text(currentCategoryItems.isEmpty ? "No tracks in this category yet." : "No matching tracks found.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredCategoryItems.enumerated()), id: \.element.id) { index, item in
                                breakdownTrackRow(item: item, index: index + 1, category: category)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 120, idealHeight: 220, maxHeight: 360)
                }

                if category == .notFound && !currentCategoryItems.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange.opacity(0.85))
                        Text("Tip: Verify song title and artist tags in the Metadata Editor to help online lyric matching.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(
                ZStack {
                    WalkmanTheme.card.opacity(0.85)
                        .background(.ultraThinMaterial)

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.18), location: 0.0),
                                .init(color: Color.white.opacity(0.02), location: 0.5),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 7)
                        Spacer(minLength: 0)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: category.color.opacity(0.50), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.5),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
        }
    }

    private func breakdownTrackRow(item: TrackFetchResultItem, index: Int, category: LyricsFetchCategory) -> some View {
        HStack(spacing: 12) {
            // Index number
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.70))
                .frame(width: 22, alignment: .trailing)

            // Audio note icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(category.color.opacity(0.85))
                .frame(width: 14)

            // Title & Artist / Album
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title)
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.track.artist.isEmpty {
                        Text(item.track.artist)
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    if !item.track.album.isEmpty {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))
                        Text(item.track.album)
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 16)

            // Format Badge (FLAC, MP3, etc.)
            Text(item.track.format.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .layoutPriority(1)

            // Detail badge / status reason (Fully responsive across window widths)
            Text(item.detail)
                .font(WalkmanFont.caption)
                .foregroundStyle(category == .notFound ? Color.orange.opacity(0.90) : WalkmanTheme.silverMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(item.detail)
                .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Footer Actions
    private var footerActionsSection: some View {
        HStack(spacing: 12) {
            if sheetState == .configure {
                // Cancel
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
                .keyboardShortcut(.cancelAction)

                Spacer()

                // Generate Button
                Button(action: startGeneration) {
                    HStack(spacing: 6) {
                        if isScanningLyrics {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.75)
                            Text("Checking Lyrics...")
                                .font(WalkmanFont.calloutBold)
                        } else {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(targetTracks.isEmpty ? "No Tracks to Fetch" : "Fetch LRC Lyrics (\(targetTracks.count))")
                                .font(WalkmanFont.calloutBold)
                        }
                    }
                    .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
                    .padding(.horizontal, 22)
                    .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
                .disabled(targetTracks.isEmpty || isScanningLyrics)
                .keyboardShortcut(.defaultAction)
            } else if sheetState == .running {
                Spacer()

                // Stop Button
                Button(action: cancelGeneration) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Stop Generation")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(Color.red.opacity(0.90))
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .destructive, cornerRadius: 17))

                Spacer()
            } else if sheetState == .completed {
                Spacer()

                // Done Button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
                        .padding(.horizontal, 28)
                        .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Generation Execution Logic
    private func startGeneration() {
        let tracksToProcess = targetTracks
        guard !tracksToProcess.isEmpty else { return }

        sheetState = .running
        totalTracksToProcess = tracksToProcess.count
        processedCount = 0
        syncedCount = 0
        plainCount = 0
        skippedCount = 0
        notFoundCount = 0
        fetchedResultItems = []
        selectedMetricCategory = nil
        breakdownSearchQuery = ""
        currentTrackTitle = ""
        currentTrackArtist = ""
        currentTrackStage = "Starting multi-threaded concurrent engine..."
        etaString = "Estimating..."
        startTime = Date()

        generationTask = Task {
            let concurrencyLimit = 5
            var trackIndex = 0
            let total = tracksToProcess.count

            await withTaskGroup(of: (Track, Result<LyricsResult, Error>?).self) { group in
                var activeWorkers = 0
                // Spawn initial batch of workers
                while trackIndex < total && activeWorkers < concurrencyLimit && !Task.isCancelled {
                    let track = tracksToProcess[trackIndex]
                    trackIndex += 1
                    activeWorkers += 1
                    group.addTask {
                        await fetchSingleTrack(track: track)
                    }
                }

                // Consume completed results and spawn subsequent tracks
                for await (track, result) in group {
                    activeWorkers -= 1
                    if Task.isCancelled { break }

                    await MainActor.run {
                        self.handleTrackResult(track: track, result: result)
                    }

                    if trackIndex < total && !Task.isCancelled {
                        let nextTrack = tracksToProcess[trackIndex]
                        trackIndex += 1
                        activeWorkers += 1
                        group.addTask {
                            await fetchSingleTrack(track: nextTrack)
                        }
                    }
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.sheetState = .completed
                    NotificationCenter.default.post(name: .trackMetadataDidUpdate, object: nil)
                }
            }
        }
    }

    private func fetchSingleTrack(track: Track) async -> (Track, Result<LyricsResult, Error>?) {
        let trackURL = URL(fileURLWithPath: track.fullPath)

        // Check if track already has lyrics and we are skipping
        if onlyMissingLyrics {
            let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
            let upperLrcURL = trackURL.deletingPathExtension().appendingPathExtension("LRC")
            if FileManager.default.fileExists(atPath: lrcURL.path) || FileManager.default.fileExists(atPath: upperLrcURL.path) || AudioTagger.shared.extractLyrics(fileURL: trackURL) != nil {
                return (track, nil)
            }
        }

        do {
            let res = try await LyricsService.shared.fetchLyrics(
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationSeconds: track.durationSeconds
            )
            return (track, .success(res))
        } catch {
            return (track, .failure(error))
        }
    }

    @MainActor
    private func handleTrackResult(track: Track, result: Result<LyricsResult, Error>?) {
        processedCount += 1
        currentTrackTitle = track.title
        currentTrackArtist = track.artist

        if let resWrap = result {
            switch resWrap {
            case .success(let lyricsResult):
                let trackURL = URL(fileURLWithPath: track.fullPath)
                do {
                    try AudioTagger.shared.saveLyrics(fileURL: trackURL, lyrics: lyricsResult.lyrics)
                    if lyricsResult.synced {
                        syncedCount += 1
                        currentTrackStage = "Saved synchronized .LRC file"
                        fetchedResultItems.append(TrackFetchResultItem(
                            id: "\(track.id)-synced-\(processedCount)",
                            track: track,
                            category: .synced,
                            detail: "Synced .LRC companion saved",
                            timestamp: Date()
                        ))
                    } else {
                        plainCount += 1
                        currentTrackStage = "Saved plain lyrics file"
                        fetchedResultItems.append(TrackFetchResultItem(
                            id: "\(track.id)-plain-\(processedCount)",
                            track: track,
                            category: .plain,
                            detail: "Plain text lyrics saved",
                            timestamp: Date()
                        ))
                    }
                } catch {
                    notFoundCount += 1
                    currentTrackStage = "Failed to write .LRC: \(error.localizedDescription)"
                    fetchedResultItems.append(TrackFetchResultItem(
                        id: "\(track.id)-diskerror-\(processedCount)",
                        track: track,
                        category: .notFound,
                        detail: "Disk error: \(error.localizedDescription)",
                        timestamp: Date()
                    ))
                }
            case .failure(let error):
                notFoundCount += 1
                currentTrackStage = "No lyrics found online"
                let detailMsg: String
                if let lyricsErr = error as? LyricsError {
                    detailMsg = lyricsErr.errorDescription ?? "No lyrics found online"
                } else {
                    detailMsg = "No lyrics found online"
                }
                fetchedResultItems.append(TrackFetchResultItem(
                    id: "\(track.id)-notfound-\(processedCount)",
                    track: track,
                    category: .notFound,
                    detail: detailMsg,
                    timestamp: Date()
                ))
            }
        } else {
            // Skipped (already has lyrics)
            skippedCount += 1
            currentTrackStage = "Skipped (already has .LRC)"
            fetchedResultItems.append(TrackFetchResultItem(
                id: "\(track.id)-skipped-\(processedCount)",
                track: track,
                category: .skipped,
                detail: "Existing companion .LRC preserved",
                timestamp: Date()
            ))
        }

        // Update ETA
        if let start = startTime, processedCount > 1 {
            let elapsed = Date().timeIntervalSince(start)
            let speed = Double(processedCount) / max(elapsed, 0.1) // tracks/second
            let remaining = Double(totalTracksToProcess - processedCount)
            let etaSec = remaining / max(speed, 0.05)
            etaString = formatETA(etaSec)
        }
    }

    private func formatETA(_ seconds: Double) -> String {
        if seconds <= 2 {
            return "Finishing..."
        }
        let totalSec = Int(seconds)
        let mins = totalSec / 60
        let secs = totalSec % 60
        if mins > 0 {
            return "\(mins)m \(secs)s remaining"
        } else {
            return "\(secs)s remaining"
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        sheetState = .completed
        NotificationCenter.default.post(name: .trackMetadataDidUpdate, object: nil)
    }

    private func cancelAndDismiss() {
        generationTask?.cancel()
        generationTask = nil
        onDismiss()
    }
}

// MARK: - Sheet Close Button
private struct SheetCloseButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.07))
                    .frame(width: 28, height: 28)
                
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.25 : 0.12), lineWidth: 0.8)
                    .frame(width: 28, height: 28)
                
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.65))
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Sheet Window Resizer
private struct SheetWindowResizer: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> SheetWindowResizerNSView {
        let view = SheetWindowResizerNSView()
        view.minSize = minSize
        return view
    }

    func updateNSView(_ nsView: SheetWindowResizerNSView, context: Context) {
        nsView.minSize = minSize
        nsView.applyConfiguration()
    }
}

private final class SheetWindowResizerNSView: NSView {
    var minSize: NSSize = .zero
    private let sheetDelegate = SheetWindowDelegate()
    private var parentResizeObserver: Any?
    private weak var observedParent: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        sheetDelegate.ownerView = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        sheetDelegate.ownerView = self
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            teardown()
        } else {
            setup()
            DispatchQueue.main.async { [weak self] in
                self?.setup()
            }
        }
    }

    private func setup() {
        guard let window = self.window else { return }
        if window.delegate == nil || window.delegate === sheetDelegate {
            window.delegate = sheetDelegate
        }
        applyConfiguration()
        setupParentObserver()
    }

    private func teardown() {
        removeParentObserver()
        if let window = self.window, window.delegate === sheetDelegate {
            window.delegate = nil
        }
    }

    func setupParentObserver() {
        guard let window = self.window else { return }
        let parent = window.sheetParent ?? window.parent ?? NSApp.mainWindow ?? NSApp.keyWindow
        guard let parent = parent, parent !== observedParent else { return }
        removeParentObserver()
        observedParent = parent
        parentResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.applyConfiguration()
        }
    }

    func removeParentObserver() {
        if let observer = parentResizeObserver {
            NotificationCenter.default.removeObserver(observer)
            parentResizeObserver = nil
        }
        observedParent = nil
    }

    func applyConfiguration() {
        guard let window = self.window else { return }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }

        let parent = window.sheetParent ?? window.parent ?? NSApp.mainWindow ?? NSApp.keyWindow
        let maxW: CGFloat
        let maxH: CGFloat

        if let parent = parent {
            // Keep at least 24pt margin on each side (48pt total horizontal inset)
            // Keep at least 80pt vertically (56pt sheet top titlebar offset + 24pt bottom clearance)
            maxW = max(minSize.width, parent.frame.width - 48)
            maxH = max(minSize.height, parent.frame.height - 80)
        } else {
            maxW = 1200
            maxH = 750
        }

        let effectiveMinW = min(minSize.width, maxW)
        let effectiveMinH = min(minSize.height, maxH)

        window.minSize = NSSize(width: effectiveMinW, height: effectiveMinH)
        window.contentMinSize = NSSize(width: effectiveMinW, height: effectiveMinH)
        window.maxSize = NSSize(width: maxW, height: maxH)
        window.contentMaxSize = NSSize(width: maxW, height: maxH)

        // Ensure current window frame stays inside maximum boundaries without overlapping the main window
        var currentFrame = window.frame
        var needsResize = false
        if currentFrame.width > maxW {
            currentFrame.size.width = maxW
            needsResize = true
        }
        if currentFrame.height > maxH {
            currentFrame.size.height = maxH
            needsResize = true
        }
        if needsResize {
            window.setFrame(currentFrame, display: true, animate: true)
        }
    }

    func clampProposedSize(_ frameSize: NSSize, for window: NSWindow) -> NSSize {
        let parent = window.sheetParent ?? window.parent ?? NSApp.mainWindow ?? NSApp.keyWindow
        let maxW: CGFloat
        let maxH: CGFloat

        if let parent = parent {
            maxW = max(minSize.width, parent.frame.width - 48)
            maxH = max(minSize.height, parent.frame.height - 80)
        } else {
            maxW = window.maxSize.width > 0 ? window.maxSize.width : 1200
            maxH = window.maxSize.height > 0 ? window.maxSize.height : 750
        }

        var clamped = frameSize
        let minW = min(minSize.width, maxW)
        let minH = min(minSize.height, maxH)

        clamped.width = min(max(clamped.width, minW), maxW)
        clamped.height = min(max(clamped.height, minH), maxH)
        return clamped
    }

    deinit {
        removeParentObserver()
    }
}

private final class SheetWindowDelegate: NSObject, NSWindowDelegate {
    weak var ownerView: SheetWindowResizerNSView?

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let owner = ownerView else { return frameSize }
        return owner.clampProposedSize(frameSize, for: sender)
    }
}

// MARK: - Liquid Glass Metric Button
private struct LiquidGlassMetricButton: View {
    let category: BatchLyricsGeneratorSheet.LyricsFetchCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(count > 0 ? category.color : category.color.opacity(0.50))

                    if isSelected {
                        Circle()
                            .fill(category.color)
                            .frame(width: 5, height: 5)
                            .shadow(color: category.color.opacity(0.85), radius: 2)
                    }
                }

                HStack(spacing: 4) {
                    Text(category.rawValue)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                        .lineLimit(1)

                    if count > 0 {
                        Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(isSelected ? category.color : WalkmanTheme.silverMuted.opacity(0.60))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 6)
            .background(
                ZStack {
                    // Liquid Glass Translucent Chassis
                    if isSelected {
                        category.color.opacity(isHovered ? 0.16 : 0.12)
                            .background(Color.white.opacity(isHovered ? 0.10 : 0.06))
                    } else {
                        Color.white.opacity(isHovered ? 0.08 : 0.035)
                    }

                    // Top specular optical reflection sheen (Liquid Glass)
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isSelected ? 0.40 : (isHovered ? 0.28 : 0.15)), location: 0.0),
                                .init(color: Color.white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 8)
                        Spacer(minLength: 0)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ?
                            LinearGradient(
                                stops: [
                                    .init(color: category.color.opacity(0.90), location: 0.0),
                                    .init(color: category.color.opacity(0.45), location: 0.6),
                                    .init(color: Color.white.opacity(0.25), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isHovered ? 0.35 : 0.16), location: 0.0),
                                    .init(color: category.color.opacity(isHovered ? 0.35 : 0.14), location: 0.5),
                                    .init(color: Color.white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isSelected ? 1.2 : 0.85
                    )
            )
            .shadow(
                color: isSelected ? category.color.opacity(0.28) : (isHovered ? Color.black.opacity(0.25) : Color.clear),
                radius: isSelected ? 7 : 4,
                x: 0,
                y: isSelected ? 2 : 1
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(count == 0 ? "No tracks in \(category.rawValue)" : "Click to view \(count) \(category.rawValue) tracks")
    }
}
