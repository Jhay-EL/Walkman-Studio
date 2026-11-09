import SwiftUI
import AppKit

// MARK: - Display & Filter Enums

public enum LanguageStudyDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case tracks = "Tracks"
    case albums = "Albums"
    case artists = "Artists"
    case recentlyAdded = "Recently Added"
    case folders = "Folders"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .tracks: return "waveform"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .folders: return "folder"
        }
    }
}

fileprivate enum LanguageStudySortOption: String, CaseIterable, Identifiable {
    case titleAZ = "title_az"
    case titleZA = "title_za"
    case artistAZ = "artist_az"
    case albumAZ = "album_az"
    case durationDesc = "duration_desc"
    case dateAddedDesc = "date_desc"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .titleAZ: return "Title (A–Z)"
        case .titleZA: return "Title (Z–A)"
        case .artistAZ: return "Speaker / Artist (A–Z)"
        case .albumAZ: return "Course / Album (A–Z)"
        case .durationDesc: return "Duration (Longest First)"
        case .dateAddedDesc: return "Recently Added First"
        }
    }
    
    var iconName: String {
        switch self {
        case .titleAZ, .titleZA: return "textformat.abc"
        case .artistAZ: return "person"
        case .albumAZ: return "square.stack"
        case .durationDesc: return "timer"
        case .dateAddedDesc: return "calendar"
        }
    }
    
    var comparator: (Track, Track) -> Bool {
        switch self {
        case .titleAZ:
            return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .artistAZ:
            return { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .albumAZ:
            return { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .durationDesc:
            return { $0.durationSeconds > $1.durationSeconds }
        case .dateAddedDesc:
            return { $0.dateAdded > $1.dateAdded }
        }
    }
}

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
}

fileprivate struct LanguageStudyFolder: Identifiable, Hashable {
    let path: String
    let displayName: String
    let isLearningDir: Bool
    let tracks: [Track]
    
    var id: String { path }
    var trackCount: Int { tracks.count }
    var totalDuration: Double { tracks.reduce(0) { $0 + $1.durationSeconds } }
    var totalBytes: Int64 { tracks.reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - LanguageStudyView

public struct LanguageStudyView: View {
    let tracks: [Track]
    let activeDrive: WalkmanDrive?
    let onSelectTrack: (Track) -> Void
    var onEditTrack: ((Track) -> Void)? = nil
    var onEditTrackWithList: ((Track, [Track]) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onNavigateToTransfer: (() -> Void)? = nil
    
    private static let defaultSortOrder = [KeyPathComparator(\Track.title, order: .forward)]
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var displayMode: LanguageStudyDisplayMode = .tracks
    @State private var searchQuery: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var formatFilter: String = "ALL"
    @State private var sortOption: LanguageStudySortOption = .titleAZ
    @State private var sortOrder = defaultSortOrder
    @State private var selectedTrackId: Track.ID? = nil
    @State private var showBatchLyricsSheet: Bool = false
    @State private var isPreparingLyricsSheet: Bool = false
    
    // High-Performance Pipeline State (< 0.1ms execution, fully isolated from hover & layout measurement)
    @State private var baseLanguageTracks: [Track] = []
    @State private var displayedTracks: [Track] = []
    @State private var recentlyAddedTracks: [Track] = []
    @State private var languageFolders: [LanguageStudyFolder] = []
    @State private var albumCount: Int = 0
    @State private var artistCount: Int = 0
    
    private let filterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Lessons", icon: "character.book.closed.fill"),
        FilterOption(id: "MP3", title: "MP3", icon: "waveform"),
        FilterOption(id: "M4A", title: "M4A / AAC", icon: "waveform"),
        FilterOption(id: "FLAC", title: "FLAC", icon: "waveform"),
        FilterOption(id: "LEARNING_DIR", title: "/LEARNING Folder Only", icon: "folder.fill")
    ]
    
    public init(
        tracks: [Track],
        activeDrive: WalkmanDrive? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditTrack: ((Track) -> Void)? = nil,
        onEditTrackWithList: ((Track, [Track]) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onDeleteTrack: ((Track) -> Void)? = nil,
        onNavigateToTransfer: (() -> Void)? = nil
    ) {
        self.tracks = tracks
        self.activeDrive = activeDrive
        self.onSelectTrack = onSelectTrack
        self.onEditTrack = onEditTrack
        self.onEditTrackWithList = onEditTrackWithList
        self.onTrimCutTrack = onTrimCutTrack
        self.onDeleteTrack = onDeleteTrack
        self.onNavigateToTransfer = onNavigateToTransfer
        
        let lang = tracks.allSatisfy(\.isLanguageStudy) ? tracks : tracks.filter(\.isLanguageStudy)
        self._baseLanguageTracks = State(initialValue: lang)
        self._displayedTracks = State(initialValue: lang)
        self._recentlyAddedTracks = State(initialValue: lang.sorted { $0.dateAdded > $1.dateAdded })
        let initialFolders = Self.buildFolders(from: lang)
        self._languageFolders = State(initialValue: initialFolders)
        self._albumCount = State(initialValue: Set(lang.map(\.album).filter { !$0.isEmpty }).count)
        self._artistCount = State(initialValue: Set(lang.map(\.artist).filter { !$0.isEmpty }).count)
    }
    
    private static func buildFolders(from source: [Track]) -> [LanguageStudyFolder] {
        var dict: [String: [Track]] = [:]
        for track in source {
            let parentDir = (track.fullPath as NSString).deletingLastPathComponent
            dict[parentDir, default: []].append(track)
        }
        
        return dict.map { path, folderTracks in
            let folderName = (path as NSString).lastPathComponent
            let isLearning = path.contains("/LEARNING")
            return LanguageStudyFolder(
                path: path,
                displayName: folderName.isEmpty ? "Root" : folderName,
                isLearningDir: isLearning,
                tracks: folderTracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }.sorted { f1, f2 in
            if f1.isLearningDir != f2.isLearningDir {
                return f1.isLearningDir && !f2.isLearningDir
            }
            return f1.displayName.localizedCaseInsensitiveCompare(f2.displayName) == .orderedAscending
        }
    }
    
    private func recomputePipeline() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        var filtered = baseLanguageTracks
        
        // 1. Format / category filter
        if formatFilter != "ALL" {
            switch formatFilter {
            case "LEARNING_DIR":
                filtered = filtered.filter { $0.fullPath.contains("/LEARNING/") }
            case "M4A":
                filtered = filtered.filter { $0.format == "M4A" || $0.format == "AAC" || $0.format == "ALAC" }
            default:
                filtered = filtered.filter { $0.format == formatFilter }
            }
        }
        
        // 2. Search query filter
        if !q.isEmpty {
            filtered = filtered.filter { track in
                track.title.localizedCaseInsensitiveContains(q) ||
                track.artist.localizedCaseInsensitiveContains(q) ||
                track.album.localizedCaseInsensitiveContains(q) ||
                track.filename.localizedCaseInsensitiveContains(q) ||
                track.relativePath.localizedCaseInsensitiveContains(q)
            }
        }
        
        // 3. Sorting
        let sortedByDropdown = filtered.sorted(by: sortOption.comparator)
        let finalDisplayed = sortedByDropdown.sorted(using: sortOrder)
        
        self.displayedTracks = finalDisplayed
        self.recentlyAddedTracks = finalDisplayed.sorted { $0.dateAdded > $1.dateAdded }
        self.languageFolders = Self.buildFolders(from: finalDisplayed)
        self.albumCount = Set(finalDisplayed.map(\.album).filter { !$0.isEmpty }).count
        self.artistCount = Set(finalDisplayed.map(\.artist).filter { !$0.isEmpty }).count
    }
    
    // MARK: - Main Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Liquid Glass Toolbar
            ViewThatFits(in: .horizontal) {
                wideToolbarLayout
                dropdownToolbarLayout
                compactToolbarLayout
                narrowToolbarLayout
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.84), value: isSearchExpanded)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.8)
                }
            )
            
            // Content
            if baseLanguageTracks.isEmpty && displayMode != .folders {
                emptyLanguageStudyView
            } else if displayedTracks.isEmpty && displayMode != .folders {
                noSearchResultsView
            } else {
                switch displayMode {
                case .tracks:
                    tracksTableView
                case .albums:
                    albumsView
                case .artists:
                    artistsView
                case .recentlyAdded:
                    recentlyAddedTableView
                case .folders:
                    foldersView
                }
            }
        }
        .sheet(isPresented: $showBatchLyricsSheet) {
            BatchLyricsGeneratorSheet(
                allTracks: displayedTracks,
                selectedTracks: displayedTracks.filter { selectedTrackId == $0.id },
                tabContext: .languageStudy,
                onDismiss: {
                    showBatchLyricsSheet = false
                }
            )
        }
        .onChange(of: searchQuery) { _, _ in recomputePipeline() }
        .onChange(of: formatFilter) { _, _ in recomputePipeline() }
        .onChange(of: sortOption) { _, _ in recomputePipeline() }
        .onChange(of: sortOrder) { _, _ in recomputePipeline() }
        .onChange(of: tracks) { _, newTracks in
            let lang = newTracks.allSatisfy(\.isLanguageStudy) ? newTracks : newTracks.filter(\.isLanguageStudy)
            self.baseLanguageTracks = lang
            recomputePipeline()
        }
    }
    
    // -------------------------------------------------------------------------
    // EMBEDDED ALBUMS & ARTISTS VIEWS
    // -------------------------------------------------------------------------
    
    private var albumsView: some View {
        AlbumsView(
            tracks: displayedTracks,
            showToolbar: false,
            onSelectTrack: onSelectTrack,
            onEditTrack: onEditTrack,
            onEditTrackWithList: onEditTrackWithList,
            onTrimCutTrack: onTrimCutTrack,
            onDeleteTrack: onDeleteTrack
        )
        .id("lang-albums-\(formatFilter)-\(searchQuery)-\(displayedTracks.count)")
    }
    
    private var artistsView: some View {
        ArtistsView(
            tracks: displayedTracks,
            showToolbar: false,
            onSelectTrack: onSelectTrack,
            onEditTrack: onEditTrack,
            onEditTrackWithList: onEditTrackWithList,
            onTrimCutTrack: onTrimCutTrack
        )
        .id("lang-artists-\(formatFilter)-\(searchQuery)-\(displayedTracks.count)")
    }
    
    // -------------------------------------------------------------------------
    // TOOLBAR SUBVIEWS
    // -------------------------------------------------------------------------
    
    private var wideToolbarLayout: some View {
        HStack(spacing: 8) {
            searchFieldView
            
            displayModeSegmentedControl
                .fixedSize(horizontal: true, vertical: false)
            
            filterDropdownMenu
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            if !isSearchExpanded {
                HStack(spacing: 8) {
                    batchLyricsButton
                    
                    playbackControlsView
                        .fixedSize(horizontal: true, vertical: false)
                    
                    statusIndicatorView
                        .fixedSize(horizontal: true, vertical: false)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .trailing))
                            .combined(with: .scale(scale: 0.92, anchor: .trailing)),
                        removal: .opacity
                            .combined(with: .move(edge: .trailing))
                            .combined(with: .scale(scale: 0.92, anchor: .trailing))
                    )
                )
            }
        }
    }
    
    private var dropdownToolbarLayout: some View {
        HStack(spacing: 8) {
            searchFieldView
            
            displayModeDropdownMenu
                .fixedSize(horizontal: true, vertical: false)
            
            filterDropdownMenu
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            if !isSearchExpanded {
                HStack(spacing: 8) {
                    batchLyricsButton
                    
                    playbackControlsView
                        .fixedSize(horizontal: true, vertical: false)
                    
                    statusIndicatorView
                        .fixedSize(horizontal: true, vertical: false)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .trailing))
                            .combined(with: .scale(scale: 0.92, anchor: .trailing)),
                        removal: .opacity
                            .combined(with: .move(edge: .trailing))
                            .combined(with: .scale(scale: 0.92, anchor: .trailing))
                    )
                )
            }
        }
    }
    
    private var compactToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                
                filterDropdownMenu
                    .fixedSize(horizontal: true, vertical: false)
                
                Spacer(minLength: 4)
                
                if !isSearchExpanded {
                    HStack(spacing: 8) {
                        batchLyricsButton
                        
                        playbackControlsView
                            .fixedSize(horizontal: true, vertical: false)
                        
                        statusIndicatorView
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .trailing))
                                .combined(with: .scale(scale: 0.92, anchor: .trailing)),
                            removal: .opacity
                                .combined(with: .move(edge: .trailing))
                                .combined(with: .scale(scale: 0.92, anchor: .trailing))
                        )
                    )
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                displayModeSegmentedControl
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private var narrowToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                
                filterDropdownMenu
                    .fixedSize(horizontal: true, vertical: false)
                
                Spacer(minLength: 4)
                
                if !isSearchExpanded {
                    HStack(spacing: 8) {
                        batchLyricsButton
                        
                        statusIndicatorView
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .trailing))
                                .combined(with: .scale(scale: 0.92, anchor: .trailing)),
                            removal: .opacity
                                .combined(with: .move(edge: .trailing))
                                .combined(with: .scale(scale: 0.92, anchor: .trailing))
                        )
                    )
                }
            }
            
            if !isSearchExpanded {
                HStack(spacing: 8) {
                    playbackControlsView
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    )
                )
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                displayModeSegmentedControl
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private var searchFieldView: some View {
        ExpandableLiquidGlassSearchBar(
            text: $searchQuery,
            isExpanded: $isSearchExpanded,
            placeholder: "Search lessons, audiobooks, topics...",
            expandedWidth: 260,
            helpText: "Search Language Study"
        )
    }
    
    private var displayModeSegmentedControl: some View {
        LanguageStudyDisplayModeSegmentedControl(displayMode: $displayMode)
    }
    
    private var displayModeDropdownMenu: some View {
        LanguageStudyDisplayModeDropdown(displayMode: $displayMode)
    }
    
    private var filterDropdownMenu: some View {
        LanguageStudyFilterDropdown(
            formatFilter: $formatFilter,
            sortOption: $sortOption,
            filterOptions: filterOptions
        )
    }
    
    private var batchLyricsButton: some View {
        Button(action: {
            isPreparingLyricsSheet = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showBatchLyricsSheet = true
                isPreparingLyricsSheet = false
            }
        }) {
            if isPreparingLyricsSheet {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                    .frame(width: 38, height: 38)
            } else {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
        .disabled(displayedTracks.isEmpty || isPreparingLyricsSheet)
        .help("LRC Fetcher: Fetch transcripts and synchronized lyrics for lessons")
    }
    
    private var isPlayingFromLanguageList: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && displayedTracks.contains(where: { $0.id == current.id })
    }
    
    private func togglePlaybackLanguage() {
        if isPlayingFromLanguageList {
            player.pause()
        } else if let first = displayedTracks.first {
            self.selectedTrackId = first.id
            player.play(track: first, in: displayedTracks)
        }
    }
    
    private func shufflePlaybackLanguage() {
        guard !displayedTracks.isEmpty else { return }
        let shuffled = displayedTracks.shuffled()
        if let randomTrack = shuffled.first {
            self.selectedTrackId = randomTrack.id
            player.play(track: randomTrack, in: shuffled)
        }
    }
    
    private var playbackControlsView: some View {
        HStack(spacing: 7) {
            Button(action: togglePlaybackLanguage) {
                HStack(spacing: 6) {
                    Image(systemName: isPlayingFromLanguageList ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isPlayingFromLanguageList ? "Pause" : "Play All")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(height: 38)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
            .disabled(displayedTracks.isEmpty)
            .help(isPlayingFromLanguageList ? "Pause playback" : "Play all visible lessons in order")
            
            Button(action: shufflePlaybackLanguage) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .disabled(displayedTracks.isEmpty)
            .help("Shuffle play visible lessons")
        }
    }
    
    private var statusIndicatorIcon: String {
        switch displayMode {
        case .tracks: return "character.book.closed.fill"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .folders: return "folder"
        }
    }
    
    private var statusIndicatorCount: Int {
        switch displayMode {
        case .tracks, .recentlyAdded:
            return displayedTracks.count
        case .albums:
            return albumCount
        case .artists:
            return artistCount
        case .folders:
            return languageFolders.count
        }
    }
    
    private var statusIndicatorHelp: String {
        let count = statusIndicatorCount
        switch displayMode {
        case .tracks:
            return count == 1 ? "1 Lesson" : "\(count.formatted()) Lessons"
        case .albums:
            return count == 1 ? "1 Course / Album" : "\(count.formatted()) Courses / Albums"
        case .artists:
            return count == 1 ? "1 Speaker / Instructor" : "\(count.formatted()) Speakers / Instructors"
        case .recentlyAdded:
            return count == 1 ? "1 Recent Lesson" : "\(count.formatted()) Recent Lessons"
        case .folders:
            return count == 1 ? "1 Folder" : "\(count.formatted()) Folders"
        }
    }
    
    private var statusIndicatorView: some View {
        HStack(spacing: 5) {
            Image(systemName: statusIndicatorIcon)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
            
            Text("\(statusIndicatorCount.formatted())")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .help(statusIndicatorHelp)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            ZStack {
                Color.white.opacity(0.08)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.10), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.45), location: 0.0),
                            .init(color: Color.white.opacity(0.20), location: 0.5),
                            .init(color: Color.white.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // -------------------------------------------------------------------------
    // TABLE SUBVIEWS (TRACKS & RECENTLY ADDED)
    // -------------------------------------------------------------------------
    
    private var tracksTableView: some View {
        Table(displayedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trackNum) { track in
                Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 26, ideal: 34, max: 44)
            
            TableColumn("Lesson / Title", value: \.title) { track in
                trackTitleCell(track: track, in: displayedTracks)
            }
            .width(min: 160, ideal: 240)
            
            TableColumn("Speaker / Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Speaker" : track.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 150)
            
            TableColumn("Course / Album", value: \.album) { track in
                Text(track.album.isEmpty ? "—" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 150)
            
            TableColumn("Location") { track in
                locationBadge(for: track)
            }
            .width(min: 80, ideal: 95, max: 110)
            
            TableColumn("Format", value: \.format) { track in
                formatBadge(for: track)
            }
            .width(min: 50, ideal: 60, max: 70)
            
            TableColumn("Duration", value: \.durationSeconds) { track in
                Text(formatDuration(track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .width(min: 50, ideal: 64, max: 80)
            
            TableColumn("Bitrate", value: \.bitrateKbps) { track in
                Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "—")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.secondary)
            }
            .width(min: 50, ideal: 60, max: 75)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            tableContextMenu(selection: selection, in: displayedTracks)
        } primaryAction: { selection in
            if let firstId = selection.first, let track = displayedTracks.first(where: { $0.id == firstId }) {
                self.selectedTrackId = track.id
                player.play(track: track, in: displayedTracks)
            }
        }
        .tableScrollBottomInset(88)
    }
    
    private var recentlyAddedTableView: some View {
        Table(recentlyAddedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#") { track in
                let idx = (recentlyAddedTracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
                Text("\(idx)")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 26, ideal: 34, max: 44)
            
            TableColumn("Lesson / Title", value: \.title) { track in
                trackTitleCell(track: track, in: recentlyAddedTracks)
            }
            .width(min: 160, ideal: 240)
            
            TableColumn("Speaker / Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Speaker" : track.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 150)
            
            TableColumn("Course / Album", value: \.album) { track in
                Text(track.album.isEmpty ? "—" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 150)
            
            TableColumn("Added") { track in
                Text(formatRelativeDate(track.dateAdded))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .width(min: 75, ideal: 95, max: 120)
            
            TableColumn("Location") { track in
                locationBadge(for: track)
            }
            .width(min: 80, ideal: 95, max: 110)
            
            TableColumn("Format", value: \.format) { track in
                formatBadge(for: track)
            }
            .width(min: 50, ideal: 60, max: 70)
            
            TableColumn("Duration", value: \.durationSeconds) { track in
                Text(formatDuration(track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .width(min: 50, ideal: 64, max: 80)
            
            TableColumn("Bitrate", value: \.bitrateKbps) { track in
                Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "—")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.secondary)
            }
            .width(min: 50, ideal: 60, max: 75)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            tableContextMenu(selection: selection, in: recentlyAddedTracks)
        } primaryAction: { selection in
            if let firstId = selection.first, let track = recentlyAddedTracks.first(where: { $0.id == firstId }) {
                self.selectedTrackId = track.id
                player.play(track: track, in: recentlyAddedTracks)
            }
        }
        .tableScrollBottomInset(88)
    }
    
    private func trackTitleCell(track: Track, in list: [Track]) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let isPlayingThis = isCurrent && player.isPlaying
        
        return HStack(spacing: 8) {
            Button(action: {
                self.selectedTrackId = track.id
                if isPlayingThis {
                    player.pause()
                } else {
                    player.play(track: track, in: list)
                }
            }) {
                TrackCoverThumbnail(track: track, size: 30, isPlaying: isPlayingThis)
            }
            .buttonStyle(.plain)
            .help(isPlayingThis ? "Pause" : "Play preview")
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(track.title)
                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(isPlayingThis ? Color.white : WalkmanTheme.silverLight)
                        .lineLimit(1)
                    
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .help("Language Study Track")
                }
                
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private func locationBadge(for track: Track) -> some View {
        let isLearningDir = track.fullPath.contains("/LEARNING/")
        return HStack(spacing: 4) {
            Image(systemName: isLearningDir ? "folder.fill" : "music.note")
                .font(.system(size: 8))
            Text(isLearningDir ? "/LEARNING/" : "/MUSIC/")
                .font(WalkmanFont.badge)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule().fill(Color.white.opacity(isLearningDir ? 0.12 : 0.05))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(isLearningDir ? 0.28 : 0.12), lineWidth: 0.7)
        )
        .foregroundStyle(isLearningDir ? Color.white : WalkmanTheme.silverMuted)
        .help(isLearningDir ? "Stored in Walkman native /LEARNING/ folder" : "Stored in /MUSIC/ with Language/Audiobook genre")
    }
    
    private func formatBadge(for track: Track) -> some View {
        Text(track.format)
            .font(WalkmanFont.badge)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75)
            )
            .foregroundStyle(WalkmanTheme.silverLight)
    }
    
    @ViewBuilder
    private func tableContextMenu(selection: Set<Track.ID>, in sourceList: [Track]) -> some View {
        if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId }) {
            let isThisPlaying = player.currentTrack?.id == track.id && player.isPlaying
            
            Button(isThisPlaying ? "Pause Playback" : "Play Preview") {
                self.selectedTrackId = track.id
                if isThisPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: sourceList)
                }
            }
            
            Divider()
            
            Button {
                let targets = sourceList.filter { selection.contains($0.id) }
                if let first = targets.first {
                    if targets.count > 1, let onEditTrackWithList = onEditTrackWithList {
                        onEditTrackWithList(first, targets)
                    } else if let onEditTrack = onEditTrack {
                        onEditTrack(first)
                    }
                }
            } label: {
                Label(selection.count > 1 ? "Edit Metadata for \(selection.count) Lessons..." : "Edit Metadata...", systemImage: "pencil")
            }
            
            Button {
                let targets = sourceList.filter { selection.contains($0.id) }
                if let first = targets.first, let onTrimCutTrack = onTrimCutTrack {
                    onTrimCutTrack(first)
                }
            } label: {
                Label("Trim / Cut Audio...", systemImage: "scissors")
            }
            
            Divider()
            
            Button {
                let fileURLs = sourceList.filter { selection.contains($0.id) }.map { URL(fileURLWithPath: $0.fullPath) }
                NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            
            Button {
                let paths = sourceList.filter { selection.contains($0.id) }.map(\.fullPath).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                let targets = sourceList.filter { selection.contains($0.id) }
                for tr in targets {
                    onDeleteTrack?(tr)
                }
            } label: {
                Label(selection.count > 1 ? "Delete \(selection.count) Lessons from Walkman" : "Delete from Walkman", systemImage: "trash")
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // FOLDERS VIEW
    // -------------------------------------------------------------------------
    
    private var foldersView: some View {
        let folders = languageFolders
        let totalFolderBytes: Int64 = folders.reduce(0) { $0 + $1.totalBytes }
        let folderCount = folders.count
        let trackCount = displayedTracks.count
        let suffix = folderCount == 1 ? "" : "s"
        let subtitleText = "\(folderCount) folder\(suffix) indexed • \(trackCount) total lessons • \(formatBytes(totalFolderBytes)) storage"

        return ScrollView {
            VStack(spacing: 12) {
                // Header Banner
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Language Study Folders on Walkman")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(.white)
                        Text(subtitleText)
                            .font(.system(size: 12))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    
                    Spacer()
                    
                    if let activeDrive = activeDrive {
                        Button(action: {
                            let url = URL(fileURLWithPath: activeDrive.learningDir)
                            if FileManager.default.fileExists(atPath: url.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: activeDrive.mountPoint)])
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text("Open in Finder")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                
                // Folder Cards
                ForEach(languageFolders) { folder in
                    LanguageStudyFolderCard(
                        folder: folder,
                        onPlay: {
                            if let first = folder.tracks.first {
                                self.selectedTrackId = first.id
                                player.play(track: first, in: folder.tracks)
                            }
                        },
                        onViewLessons: {
                            searchQuery = folder.displayName
                            displayMode = .tracks
                        },
                        onReveal: {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
                        }
                    )
                }
            }
            .padding(16)
        }
    }
    
    // -------------------------------------------------------------------------
    // EMPTY & ZERO SEARCH STATES
    // -------------------------------------------------------------------------
    
    private var emptyLanguageStudyView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(WalkmanTheme.silverLight.opacity(0.8))
            }
            
            VStack(spacing: 6) {
                Text("No Language Study Tracks Found")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(Color.white)
                
                Text("Sony Walkman devices feature a dedicated Language Study player mode with quick replay (-3s, +10s), A-B repeat, and speed control.\n\nTracks transferred to the Walkman's root /LEARNING folder or tagged with Language, Audiobook, or Podcast genres will appear here.")
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            
            HStack(spacing: 12) {
                if let onNavigateToTransfer = onNavigateToTransfer {
                    Button(action: onNavigateToTransfer) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Transfer Audiobooks & Lessons...")
                        }
                        .font(WalkmanFont.calloutMedium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 20))
                }
                
                if let activeDrive = activeDrive {
                    Button(action: {
                        let learningURL = URL(fileURLWithPath: activeDrive.learningDir)
                        if !FileManager.default.fileExists(atPath: learningURL.path) {
                            try? FileManager.default.createDirectory(at: learningURL, withIntermediateDirectories: true)
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([learningURL])
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text("Open /LEARNING in Finder")
                        }
                        .font(WalkmanFont.calloutMedium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 20))
                }
            }
            .padding(.top, 8)
            
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(WalkmanTheme.silverMuted)
            
            Text("No Lessons Match Filters")
                .font(WalkmanFont.title3)
                .foregroundStyle(Color.white)
            
            Text("Try clearing the search query or selecting \"All Lessons\" in the filter menu.")
                .font(WalkmanFont.subheadline)
                .foregroundStyle(WalkmanTheme.silverMuted)
            
            Button(action: {
                searchQuery = ""
                formatFilter = "ALL"
            }) {
                Text("Clear Search & Filters")
                    .font(WalkmanFont.calloutMedium)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 12))
            .padding(.top, 4)
            
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Liquid Glass Display Mode Dropdown Menu

private struct LanguageStudyDisplayModeDropdown: View {
    @Binding var displayMode: LanguageStudyDisplayMode
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(LanguageStudyDisplayMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        displayMode = mode
                    }
                } label: {
                    HStack {
                        if displayMode == mode {
                            Image(systemName: "checkmark")
                        }
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            }
        } label: {
            LiquidGlassDropdownLabel(height: 36, isHovered: isHovered) {
                HStack(spacing: 7) {
                    Image(systemName: displayMode.icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text(displayMode.rawValue)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .fixedSize()
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - Liquid Glass Display Mode Segmented Control

private struct LanguageStudyDisplayModeSegmentedControl: View {
    @Binding var displayMode: LanguageStudyDisplayMode
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: LanguageStudyDisplayMode = .tracks
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(LanguageStudyDisplayMode.allCases) { mode in
                LanguageStudyDisplayModePillView(
                    mode: mode,
                    isSelected: activeHighlightId == mode,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard displayMode != mode else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            activeHighlightId = mode
                            displayMode = mode
                        }
                    }
                )
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeHighlightId = displayMode
        }
        .onChange(of: displayMode) { _, newMode in
            if activeHighlightId != newMode {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeHighlightId = newMode
                }
            }
        }
    }
}

private struct LanguageStudyDisplayModePillView: View {
    let mode: LanguageStudyDisplayMode
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                Text(mode.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.70)))
            .background(
                ZStack {
                    if isSelected {
                        LiquidGlassActivePill(isHiRes: false, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeLangDisplayHighlight", in: namespace)
                    } else if isHovered {
                        LiquidGlassHoverPill()
                    } else {
                        Color.white.opacity(0.001)
                    }
                }
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.arrow.set()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .fixedSize()
    }
}

// MARK: - Liquid Glass Filter & Sort Dropdown

private struct LanguageStudyFilterDropdown: View {
    @Binding var formatFilter: String
    @Binding var sortOption: LanguageStudySortOption
    let filterOptions: [FilterOption]
    
    @State private var isHovered = false
    
    private var isFilterActive: Bool {
        formatFilter != "ALL"
    }
    
    private var isSortActive: Bool {
        sortOption != .titleAZ
    }
    
    private var isFilterOrSortActive: Bool {
        isFilterActive || isSortActive
    }
    
    private var activeFilterTitle: String {
        filterOptions.first(where: { $0.id == formatFilter })?.title ?? formatFilter
    }
    
    var body: some View {
        Menu {
            Section("Format & Category") {
                ForEach(filterOptions) { opt in
                    Button {
                        formatFilter = opt.id
                    } label: {
                        HStack {
                            if formatFilter == opt.id {
                                Image(systemName: "checkmark")
                            }
                            if let icon = opt.icon {
                                Label(opt.title, systemImage: icon)
                            } else {
                                Text(opt.title)
                            }
                        }
                    }
                }
            }
            
            Section("Sort By") {
                ForEach(LanguageStudySortOption.allCases) { opt in
                    Button {
                        sortOption = opt
                    } label: {
                        HStack {
                            if sortOption == opt {
                                Image(systemName: "checkmark")
                            }
                            Label(opt.title, systemImage: opt.iconName)
                        }
                    }
                }
            }
            
            if isFilterOrSortActive {
                Divider()
                Button(role: .destructive) {
                    formatFilter = "ALL"
                    sortOption = .titleAZ
                } label: {
                    Label("Reset Filter & Sort", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            ZStack {
                // Circular Liquid Glass foundation fill
                Circle()
                    .fill(
                        isFilterOrSortActive ?
                            Color.white.opacity(isHovered ? 0.16 : 0.10) :
                            Color.white.opacity(isHovered ? 0.09 : 0.045)
                    )
                
                // Top specular refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.32 : (isFilterOrSortActive ? 0.24 : 0.14)), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())
                
                // Filter icon (line.3.horizontal.decrease)
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isFilterOrSortActive ?
                            WalkmanTheme.hiResGold :
                            (isHovered ? Color.white : WalkmanTheme.silverLight)
                    )
                
                // Active beacon indicator (gold dot at top right when filter or sort is active)
                if isFilterOrSortActive {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(WalkmanTheme.hiResGold)
                                .frame(width: 5.5, height: 5.5)
                                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(5.5)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        isFilterOrSortActive ?
                            WalkmanTheme.hiResGold.opacity(isHovered ? 0.60 : 0.38) :
                            Color.white.opacity(isHovered ? 0.26 : 0.11),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 3.5 : 2, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help("Filter & Sort: \(activeFilterTitle) • \(sortOption.title)")
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.arrow.set()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .fixedSize()
    }
}

// MARK: - Folder Row Card Subview

fileprivate struct LanguageStudyFolderCard: View {
    let folder: LanguageStudyFolder
    let onPlay: () -> Void
    let onViewLessons: () -> Void
    let onReveal: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(folder.isLearningDir ? 0.12 : 0.06))
                    .frame(width: 42, height: 42)
                Image(systemName: folder.isLearningDir ? "folder.fill" : "folder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(folder.isLearningDir ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(folder.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    if folder.isLearningDir {
                        Text("/LEARNING/")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.hiResGold.opacity(0.18))
                            .foregroundStyle(WalkmanTheme.hiResGoldLight)
                            .clipShape(Capsule())
                    }
                }
                
                Text("\(folder.trackCount) lesson\(folder.trackCount == 1 ? "" : "s") • \(formatDuration(folder.totalDuration)) • \(formatBytes(folder.totalBytes))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                
                Text(folder.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Play Folder")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: onViewLessons) {
                    Text("View Lessons")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(isHovered ? 0.05 : 0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.16 : 0.07), lineWidth: 0.8)
        )
        .onHover { isHovered = $0 }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
