import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum LocalDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    case recentlyAdded = "Recently Added"
    case folders = "Folders"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .songs: return "music.note.list"
        case .albums: return "square.stack.fill"
        case .artists: return "music.mic"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .folders: return "folder.fill"
        }
    }
}

public enum LocalSortOption: String, CaseIterable, Identifiable, Sendable {
    case titleAZ = "Title (A–Z)"
    case titleZA = "Title (Z–A)"
    case artistAZ = "Artist (A–Z)"
    case albumAZ = "Album (A–Z)"
    case dateNewest = "Date Added (Newest)"
    case dateOldest = "Date Added (Oldest)"
    case duration = "Duration (Longest)"
    case bitrate = "Audio Quality / Bitrate"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .titleAZ: return "Title (A–Z)"
        case .titleZA: return "Title (Z–A)"
        case .artistAZ: return "Artist"
        case .albumAZ: return "Album"
        case .dateNewest: return "Newest"
        case .dateOldest: return "Oldest"
        case .duration: return "Duration"
        case .bitrate: return "Quality"
        }
    }

    public var iconName: String {
        switch self {
        case .titleAZ:
            return "arrow.up.and.down.text.horizontal"
        case .titleZA:
            return "arrow.down.and.line.horizontal.and.arrow.up"
        case .artistAZ:
            return "person.fill"
        case .albumAZ:
            return "square.stack.fill"
        case .dateNewest:
            return "clock.fill"
        case .dateOldest:
            return "calendar"
        case .duration:
            return "timer"
        case .bitrate:
            return "waveform"
        }
    }
}

public struct LocalLibraryView: View {
    let tracks: [Track]
    let folders: [LocalMusicFolder]
    let isLoading: Bool
    var drives: [WalkmanDrive] = []
    var activeDrive: WalkmanDrive? = nil
    @Binding var selectedTrackId: String?
    let onInspectTrack: (Track) -> Void
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onGoToTransfer: (() -> Void)? = nil
    var onEditAlbum: ((AlbumItem) -> Void)? = nil
    var onTransferComplete: (() -> Void)? = nil

    private static let defaultSortOrder = [
        KeyPathComparator(\Track.artist),
        KeyPathComparator(\Track.album),
        KeyPathComparator(\Track.trackNum)
    ]

    @ObservedObject private var player = AudioPlayerService.shared
    @ObservedObject private var localService = LocalMusicLibraryService.shared

    @State private var displayMode: LocalDisplayMode = .songs
    @State private var sortOption: LocalSortOption = .artistAZ
    @State private var sortOrder = defaultSortOrder
    @State private var formatFilter: String = "ALL"
    @State private var searchQuery: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var isImportHovered: Bool = false
    @State private var folderToRemove: LocalMusicFolder? = nil
    @State private var showRemoveConfirmation: Bool = false
    @Namespace private var modeAnimationNamespace

    // Direct Transfer to Walkman State
    @State private var isDirectTransferring: Bool = false
    @State private var directTransferProgress: Double = 0.0
    @State private var directTransferCurrentIndex: Int = 0
    @State private var directTransferTotalCount: Int = 0
    @State private var directTransferCurrentTitle: String = ""
    @State private var showDirectTransferSheet: Bool = false
    @State private var directTransferComplete: Bool = false
    @State private var directTransferTargetName: String = "Sony Walkman"

    // Unsupported Format & Device Warning Alert State
    @State private var showTransferWarningAlert: Bool = false
    @State private var transferWarningTitle: String = ""
    @State private var transferWarningMessage: String = ""
    @State private var pendingWarningTracks: [Track] = []
    @State private var supportedTracksForMixedChoice: [Track] = []
    @State private var hasMixedFormats: Bool = false

    public init(
        tracks: [Track],
        folders: [LocalMusicFolder],
        isLoading: Bool,
        drives: [WalkmanDrive] = [],
        activeDrive: WalkmanDrive? = nil,
        selectedTrackId: Binding<String?>,
        onInspectTrack: @escaping (Track) -> Void,
        onDeleteTrack: ((Track) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onGoToTransfer: (() -> Void)? = nil,
        onEditAlbum: ((AlbumItem) -> Void)? = nil,
        onTransferComplete: (() -> Void)? = nil
    ) {
        self.tracks = tracks
        self.folders = folders
        self.isLoading = isLoading
        self.drives = drives
        self.activeDrive = activeDrive
        self._selectedTrackId = selectedTrackId
        self.onInspectTrack = onInspectTrack
        self.onDeleteTrack = onDeleteTrack
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
        self.onGoToTransfer = onGoToTransfer
        self.onEditAlbum = onEditAlbum
        self.onTransferComplete = onTransferComplete
    }

    private var mappedAlbumSortOption: AlbumSortOption {
        switch sortOption {
        case .dateNewest: return .recentlyAdded
        case .titleAZ, .albumAZ: return .nameAsc
        case .titleZA: return .nameDesc
        case .artistAZ: return .artistAsc
        case .dateOldest: return .yearAsc
        case .duration, .bitrate: return .trackCountDesc
        }
    }

    private func isHiRes(_ track: Track) -> Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }

    private var formatOptions: [(id: String, label: String)] {
        [
            ("ALL", "All Formats"),
            ("FLAC", "FLAC"),
            ("MP3", "MP3"),
            ("M4A", "M4A"),
            ("HI-RES", "Hi-Res Audio")
        ]
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 GB" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let absoluteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func formatDateAdded(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 7 * 86400 && interval >= 0 {
            return Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
        }
        return Self.absoluteDateFormatter.string(from: date)
    }

    var effectiveTracks: [Track] {
        localService.tracks.isEmpty ? tracks : localService.tracks
    }

    var effectiveFolders: [LocalMusicFolder] {
        localService.folders.isEmpty ? folders : localService.folders
    }

    var effectiveIsLoading: Bool {
        isLoading || localService.isScanning
    }

    var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = effectiveTracks

        // 1. Format Filter
        if formatFilter != "ALL" {
            switch formatFilter {
            case "HI-RES":
                list = list.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
            default:
                list = list.filter { $0.format.uppercased() == formatFilter }
            }
        }

        // 2. Search Query
        if !q.isEmpty {
            list = list.filter { tr in
                tr.title.localizedCaseInsensitiveContains(q) ||
                tr.artist.localizedCaseInsensitiveContains(q) ||
                tr.album.localizedCaseInsensitiveContains(q) ||
                tr.genre.localizedCaseInsensitiveContains(q) ||
                tr.filename.localizedCaseInsensitiveContains(q) ||
                tr.fullPath.localizedCaseInsensitiveContains(q)
            }
        }

        // 3. Sorting
        if sortOrder != Self.defaultSortOrder {
            list = list.sorted(using: sortOrder)
        } else {
            switch sortOption {
            case .titleAZ:
                list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .titleZA:
                list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
            case .artistAZ:
                list.sort {
                    if $0.artist != $1.artist {
                        return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                    }
                    if $0.album != $1.album {
                        return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                    }
                    return $0.trackNum < $1.trackNum
                }
            case .albumAZ:
                list.sort {
                    if $0.album != $1.album {
                        return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                    }
                    return $0.trackNum < $1.trackNum
                }
            case .dateNewest:
                list.sort { $0.dateAdded > $1.dateAdded }
            case .dateOldest:
                list.sort { $0.dateAdded < $1.dateAdded }
            case .duration:
                list.sort { $0.durationSeconds > $1.durationSeconds }
            case .bitrate:
                list.sort {
                    let qualityA = $0.sampleRate * $0.bitsPerSample
                    let qualityB = $1.sampleRate * $1.bitsPerSample
                    if qualityA != qualityB { return qualityA > qualityB }
                    return $0.bitrateKbps > $1.bitrateKbps
                }
            }
        }

        return list
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Import Folders"
        panel.message = "Choose one or more music folders to add to your Local Music Library"
        panel.canCreateDirectories = false

        if panel.runModal() == .OK {
            let urls = panel.urls
            localService.addFolders(urls: urls)
        }
    }

    private func togglePlaybackAll() {
        guard let first = filteredTracks.first else { return }
        if player.isPlaying && filteredTracks.contains(where: { $0.id == player.currentTrack?.id }) {
            player.pause()
        } else {
            selectedTrackId = first.id
            player.play(track: first, in: filteredTracks)
        }
    }

    private func shufflePlaybackAll() {
        guard !filteredTracks.isEmpty else { return }
        let shuffled = filteredTracks.shuffled()
        if let first = shuffled.first {
            selectedTrackId = first.id
            player.play(track: first, in: shuffled)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // -----------------------------------------------------------------
            // macOS 27 LIQUID GLASS TOP MENU / NAVIGATION TOOLBAR
            // -----------------------------------------------------------------
            ViewThatFits(in: .horizontal) {
                wideTopBar
                compactTopBar
                narrowTopBar
            }
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

            // -----------------------------------------------------------------
            // MAIN VIEWPORT
            // -----------------------------------------------------------------
            if effectiveFolders.isEmpty && !effectiveIsLoading {
                emptyLibraryView
            } else if effectiveIsLoading && effectiveTracks.isEmpty {
                scanningLoadingView
            } else if filteredTracks.isEmpty && !effectiveIsLoading && displayMode != .folders {
                if effectiveTracks.isEmpty {
                    noAudioFilesView
                } else {
                    noSearchResultsView
                }
            } else {
                switch displayMode {
                case .songs:
                    songsTableView
                case .albums:
                    albumsGridView
                case .artists:
                    artistsGridView
                case .recentlyAdded:
                    recentlyAddedTableView
                case .folders:
                    foldersManagerView
                }
            }
        }
        .background(WalkmanTheme.background.ignoresSafeArea())
        .onChange(of: sortOption) { _, _ in
            sortOrder = Self.defaultSortOrder
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .confirmationDialog(
            "Remove Folder from Local Library?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible,
            presenting: folderToRemove
        ) { folder in
            Button("Remove Folder", role: .destructive) {
                localService.removeFolder(id: folder.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("This will remove \"\(folder.displayName)\" and its indexed tracks from your Walkman Studio database. Files on disk will NOT be deleted.")
        }
        .sheet(isPresented: $showDirectTransferSheet) {
            DirectTransferSheet(
                targetName: directTransferTargetName,
                current: directTransferCurrentIndex,
                total: directTransferTotalCount,
                currentTitle: directTransferCurrentTitle,
                progress: directTransferProgress,
                isComplete: directTransferComplete,
                onDone: {
                    showDirectTransferSheet = false
                }
            )
        }
        .alert(transferWarningTitle, isPresented: $showTransferWarningAlert) {
            if hasMixedFormats {
                Button("Transfer & Convert (All)") {
                    TransferQueueService.shared.enqueue(tracks: pendingWarningTracks)
                    onGoToTransfer?()
                }
                if let targetDrive = ((activeDrive != nil && activeDrive?.type != .local) ? activeDrive : drives.first(where: { $0.type == .internal || $0.type == .microsd })) {
                    Button("Transfer \(supportedTracksForMixedChoice.count) Supported Tracks") {
                        startDirectTransfer(tracks: supportedTracksForMixedChoice, targetDrive: targetDrive)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } else {
                Button("Open Transfer & Convert") {
                    TransferQueueService.shared.enqueue(tracks: pendingWarningTracks)
                    onGoToTransfer?()
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            Text(transferWarningMessage)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var folderURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        folderURLs.append(url)
                    }
                } else if let url = item as? URL {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        folderURLs.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !folderURLs.isEmpty {
                self.localService.addFolders(urls: folderURLs)
            }
        }
    }

    // -------------------------------------------------------------------------
    // TOP NAVIGATION TOOLBAR LAYOUTS (WIDE / COMPACT / NARROW)
    // -------------------------------------------------------------------------
    private var wideTopBar: some View {
        HStack(spacing: 10) {
            searchFieldView
                .frame(minWidth: 160, maxWidth: 240)

            displayBySegmentedControl
                .fixedSize(horizontal: true, vertical: false)

            combinedFilterSortMenu
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            toolbarActionButtons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 120, maxWidth: .infinity)

                combinedFilterSortMenu
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 4)

                toolbarActionButtons
                    .fixedSize(horizontal: true, vertical: false)
            }

            displayBySegmentedControl
        }
    }

    private var narrowTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 100, maxWidth: .infinity)
                combinedFilterSortMenu
                    .fixedSize(horizontal: true, vertical: false)
                toolbarActionButtons
            }

            displayBySegmentedControl
        }
    }

    // -------------------------------------------------------------------------
    // TOOLBAR COMPONENTS
    // -------------------------------------------------------------------------
    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)

            TextField("Search local tracks, artists, albums, folders...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search query")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7.5)
        .frame(minHeight: 36)
        .background(
            ZStack {
                Color.white.opacity(0.06)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0.0),
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(searchQuery.isEmpty ? 0.12 : 0.30), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 2.5, x: 0, y: 1)
    }

    private var displayBySegmentedControl: some View {
        LocalDisplayModeSegmentedControl(displayMode: $displayMode)
    }

    private var combinedFilterSortMenu: some View {
        LocalFilterSortDropdown(
            formatFilter: $formatFilter,
            sortOption: $sortOption,
            formatOptions: formatOptions
        )
    }

    private var toolbarActionButtons: some View {
        importFolderButton
    }

    private var importFolderButton: some View {
        Button(action: openFolderPicker) {
            HStack(spacing: 7) {
                if effectiveIsLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(WalkmanTheme.hiResGold)
                        .frame(width: 13, height: 13)
                    Text("Scanning...")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                } else {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isImportHovered ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
                    Text("Import Folder")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isImportHovered ? Color.white : Color.white.opacity(0.88))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(height: 36)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(isImportHovered ? 0.12 : 0.055))

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isImportHovered ? 0.28 : 0.16), location: 0.0),
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
                    .stroke(
                        effectiveIsLoading ?
                            WalkmanTheme.hiResGold.opacity(0.40) :
                            Color.white.opacity(isImportHovered ? 0.32 : 0.12),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isImportHovered ? 0.22 : 0.12), radius: isImportHovered ? 4 : 2, x: 0, y: 1)
            .scaleEffect(isImportHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help("Import music folders into Local Music Library • \(effectiveTracks.count) songs indexed")
        .onHover { hovering in
            guard isImportHovered != hovering else { return }
            isImportHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isImportHovered {
                isImportHovered = false
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isImportHovered)
    }

    // -------------------------------------------------------------------------
    // SONGS TABLE VIEW (Native macOS Table with multi-column sorting & context menu)
    // -------------------------------------------------------------------------
    private var songsTableView: some View {
        Table(filteredTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trackNum) { track in
                Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 26, ideal: 34, max: 44)

            TableColumn("Title", value: \.title) { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying

                HStack(spacing: 8) {
                    Button(action: {
                        self.selectedTrackId = track.id
                        if isPlayingThis {
                            player.pause()
                        } else {
                            player.play(track: track, in: filteredTracks)
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
                                .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                .lineLimit(1)

                            if isPlayingThis {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }

                            if track.isLanguageStudy {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .help("Language Study & Audiobooks")
                            }
                        }
                    }
                }
            }
            .width(min: 130, ideal: 220)

            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 140)

            TableColumn("Album", value: \.album) { track in
                Text(track.album.isEmpty ? "—" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 150)

            TableColumn("Format", value: \.format) { track in
                let hiRes = isHiRes(track)
                HStack(spacing: 4.5) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            ZStack {
                                Color.white.opacity(hiRes ? 0.08 : 0.05)
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.12), location: 0),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 3)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        .foregroundStyle(hiRes ? WalkmanTheme.silverLight : Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(hiRes ? 0.22 : 0.09), lineWidth: 0.6)
                        )

                    if hiRes {
                        HStack(spacing: 2.5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 7, weight: .black))
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(WalkmanTheme.hiResGoldLight.opacity(0.6), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
                    }
                }
            }
            .width(min: 65, ideal: 85, max: 110)

            TableColumn("SenseMe") { track in
                if track.isSenseMeAnalyzed {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("12 TONE")
                            .font(WalkmanFont.badge)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18))
                    )
                    .overlay(
                        Capsule().stroke(Color(red: 255/255, green: 165/255, blue: 30/255).opacity(0.55), lineWidth: 0.8)
                    )
                    .foregroundStyle(Color(red: 255/255, green: 195/255, blue: 80/255))
                    .help("Sony 12 Tone / SenseMe Analyzed • \(track.senseMeChannels.joined(separator: ", "))")
                } else {
                    Text("—")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.secondary.opacity(0.35))
                }
            }
            .width(min: 60, ideal: 76, max: 90)

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
            .width(min: 50, ideal: 64, max: 80)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            trackContextMenu(for: selection, in: filteredTracks)
        } primaryAction: { selection in
            if let firstId = selection.first, let track = filteredTracks.first(where: { $0.id == firstId }) {
                self.selectedTrackId = track.id
                if player.currentTrack?.id == track.id && player.isPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: filteredTracks)
                }
            }
        }
        .tableScrollBottomInset(88)
    }

    // -------------------------------------------------------------------------
    // RECENTLY ADDED TRACKS TABLE VIEW
    // -------------------------------------------------------------------------
    private var recentlyAddedTracks: [Track] {
        var list = filteredTracks
        if sortOrder == Self.defaultSortOrder && sortOption == .artistAZ {
            list.sort { $0.dateAdded > $1.dateAdded }
        }
        return list
    }

    private var recentlyAddedTableView: some View {
        Table(recentlyAddedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#") { track in
                let idx = (recentlyAddedTracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
                Text("\(idx)")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 28, ideal: 36, max: 46)

            TableColumn("Title", value: \.title) { track in
                let isCurrent = player.currentTrack?.id == track.id
                let isPlayingThis = isCurrent && player.isPlaying

                HStack(spacing: 8) {
                    Button(action: {
                        self.selectedTrackId = track.id
                        if isPlayingThis {
                            player.pause()
                        } else {
                            player.play(track: track, in: recentlyAddedTracks)
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
                                .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                .lineLimit(1)

                            if isPlayingThis {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }

                            if track.isLanguageStudy {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .help("Language Study & Audiobooks")
                            }
                        }
                    }
                }
            }
            .width(min: 130, ideal: 220)

            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 140)

            TableColumn("Album", value: \.album) { track in
                Text(track.album.isEmpty ? "—" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 150)

            TableColumn("Format", value: \.format) { track in
                let hiRes = isHiRes(track)
                HStack(spacing: 4.5) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            ZStack {
                                Color.white.opacity(hiRes ? 0.08 : 0.05)
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.12), location: 0),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 3)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        .foregroundStyle(hiRes ? WalkmanTheme.silverLight : Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(hiRes ? 0.22 : 0.09), lineWidth: 0.6)
                        )

                    if hiRes {
                        HStack(spacing: 2.5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 7, weight: .black))
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(WalkmanTheme.hiResGoldLight.opacity(0.6), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
                    }
                }
            }
            .width(min: 65, ideal: 85, max: 110)

            TableColumn("SenseMe") { track in
                if track.isSenseMeAnalyzed {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("12 TONE")
                            .font(WalkmanFont.badge)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18))
                    )
                    .overlay(
                        Capsule().stroke(Color(red: 255/255, green: 165/255, blue: 30/255).opacity(0.55), lineWidth: 0.8)
                    )
                    .foregroundStyle(Color(red: 255/255, green: 195/255, blue: 80/255))
                    .help("Sony 12 Tone / SenseMe Analyzed • \(track.senseMeChannels.joined(separator: ", "))")
                } else {
                    Text("—")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.secondary.opacity(0.35))
                }
            }
            .width(min: 60, ideal: 76, max: 90)

            TableColumn("Date Added", value: \.dateAdded) { track in
                Text(formatDateAdded(track.dateAdded))
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120, max: 160)

            TableColumn("Duration", value: \.durationSeconds) { track in
                Text(formatDuration(track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .width(min: 50, ideal: 64, max: 80)
        }
        .contextMenu(forSelectionType: Track.ID.self) { selection in
            trackContextMenu(for: selection, in: recentlyAddedTracks)
        } primaryAction: { selection in
            if let firstId = selection.first, let track = recentlyAddedTracks.first(where: { $0.id == firstId }) {
                self.selectedTrackId = track.id
                if player.currentTrack?.id == track.id && player.isPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: recentlyAddedTracks)
                }
            }
        }
        .tableScrollBottomInset(88)
    }

    @ViewBuilder
    private func trackContextMenu(for selection: Set<Track.ID>, in sourceTracks: [Track]) -> some View {
        if let firstId = selection.first, let track = sourceTracks.first(where: { $0.id == firstId }) {
            let isThisPlaying = player.currentTrack?.id == track.id && player.isPlaying

            Button(isThisPlaying ? "Pause Playback" : "Play Preview") {
                self.selectedTrackId = track.id
                if isThisPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: sourceTracks)
                }
            }

            Divider()

            Button {
                onEditTrack?(track)
            } label: {
                Label("Edit Song Metadata...", systemImage: "square.and.pencil")
            }

            Button {
                onTrimCutTrack?(track)
            } label: {
                Label("Trim & Cut Audio...", systemImage: "scissors")
            }

            Button {
                ArtworkExportService.exportArtwork(for: track)
            } label: {
                Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button {
                let targets = sourceTracks.filter { selection.contains($0.id) }
                let toTransfer = targets.isEmpty ? [track] : targets
                handleTransferToWalkman(tracks: toTransfer)
            } label: {
                Label(selection.count > 1 ? "Transfer \(selection.count) Tracks to Walkman" : "Transfer to Walkman", systemImage: "arrow.right.circle.fill")
            }

            if let onTransfer = onGoToTransfer {
                Button {
                    let targets = sourceTracks.filter { selection.contains($0.id) }
                    let toQueue = targets.isEmpty ? [track] : targets
                    TransferQueueService.shared.enqueue(tracks: toQueue)
                    onTransfer()
                } label: {
                    Label("Send to Transfer & Convert...", systemImage: "arrow.up.arrow.down.circle")
                }
            }

            Button("Inspect Metadata & Artwork (Cmd+I)") {
                onInspectTrack(track)
            }

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.fullPath)])
            }

            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.fullPath, forType: .string)
            }

            Divider()

            Button(role: .destructive) {
                let targets = sourceTracks.filter { selection.contains($0.id) }
                let toDelete = targets.isEmpty ? [track] : targets
                for tr in toDelete {
                    onDeleteTrack?(tr)
                }
            } label: {
                Label(selection.count > 1 ? "Remove \(selection.count) Songs from Local Library" : "Remove from Local Library", systemImage: "trash")
            }
        }
    }

    // -------------------------------------------------------------------------
    // ALBUMS GRID VIEW (Uses Full AlbumsView with AlbumDetailView integration)
    // -------------------------------------------------------------------------
    private var albumsGridView: some View {
        let isFiltered = !searchQuery.isEmpty || formatFilter != "ALL"
        let precomputed = isFiltered ? nil : (localService.precomputedAlbums.isEmpty ? nil : localService.precomputedAlbums)
        return AlbumsView(
            tracks: filteredTracks,
            precomputedAlbums: precomputed,
            showToolbar: false,
            externalSortOption: mappedAlbumSortOption,
            onSelectTrack: { track in
                selectedTrackId = track.id
                onInspectTrack(track)
            },
            onEditAlbum: { album in
                onEditAlbum?(album)
            },
            onEditTrack: { track in
                onEditTrack?(track)
            },
            onTrimCutTrack: { track in
                onTrimCutTrack?(track)
            },
            onDeleteAlbum: { album in
                for tr in album.tracks {
                    onDeleteTrack?(tr)
                }
            },
            onDeleteTrack: { track in
                onDeleteTrack?(track)
            },
            onTransferAlbum: { album in
                handleTransferToWalkman(tracks: album.tracks)
            },
            onTransferTrack: { track in
                handleTransferToWalkman(tracks: [track])
            }
        )
        .id("local-albums-\(formatFilter)-\(searchQuery)-\(filteredTracks.count)")
    }

    // -------------------------------------------------------------------------
    // ARTISTS SPLIT VIEW (Uses Full ArtistsView with Master-Detail & Releases)
    // -------------------------------------------------------------------------
    private var artistsGridView: some View {
        let isFiltered = !searchQuery.isEmpty || formatFilter != "ALL"
        let precomputed = isFiltered ? nil : (localService.precomputedArtists.isEmpty ? nil : localService.precomputedArtists)
        return ArtistsView(
            tracks: filteredTracks,
            precomputedArtists: precomputed,
            showToolbar: false,
            onSelectTrack: { track in
                selectedTrackId = track.id
                onInspectTrack(track)
            },
            onEditTrack: { track in
                onEditTrack?(track)
            },
            onTrimCutTrack: { track in
                onTrimCutTrack?(track)
            },
            onTransferArtist: { artist in
                handleTransferToWalkman(tracks: artist.tracks)
            },
            onTransferTracks: { tracks in
                handleTransferToWalkman(tracks: tracks)
            },
            onTransferTrack: { track in
                handleTransferToWalkman(tracks: [track])
            }
        )
        .id("local-artists-\(formatFilter)-\(searchQuery)-\(filteredTracks.count)")
    }

    // -------------------------------------------------------------------------
    // FOLDERS MANAGER VIEW
    // -------------------------------------------------------------------------
    private var foldersManagerView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 14) {
                // Folder Manager Header Banner
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
                        Text("Monitored Music Folders")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(effectiveFolders.count) directories indexed • \(formatBytes(localService.totalSizeBytes)) storage • \(effectiveTracks.count) total songs")
                            .font(.system(size: 12))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    Button(action: openFolderPicker) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Folder...")
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
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))

                // Folder Cards
                ForEach(effectiveFolders) { folder in
                    LocalFolderRowCard(
                        folder: folder,
                        onSelect: {
                            searchQuery = folder.displayName
                            displayMode = .songs
                        },
                        onReveal: {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        },
                        onRemove: {
                            self.folderToRemove = folder
                            self.showRemoveConfirmation = true
                        },
                        onTransfer: {
                            let folderTracks = effectiveTracks.filter { $0.fullPath.hasPrefix(folder.path) }
                            handleTransferToWalkman(tracks: folderTracks)
                        }
                    )
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
    }

    // -------------------------------------------------------------------------
    // EMPTY STATE VIEW
    // -------------------------------------------------------------------------
    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 38))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            VStack(spacing: 8) {
                Text("Your Local Music Library")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text("Import music folders to organize, play, and transfer tracks to your Sony Walkman.")
                    .font(.system(size: 13))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 12) {
                Button(action: openFolderPicker) {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle.fill")
                        Text("Import Music Folders...")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(WalkmanTheme.silverGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 1.5)
                }
                .buttonStyle(.plain)

                Text("or drag & drop folders here from Finder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var scanningLoadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(WalkmanTheme.hiResGold)
            VStack(spacing: 6) {
                Text(localService.scanStatusText ?? "Scanning Local Folders...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Indexing tracks, audio formats, and cover artwork")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAudioFilesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.slash")
                .font(.system(size: 40))
                .foregroundStyle(WalkmanTheme.silverMuted)
            VStack(spacing: 6) {
                Text("No Audio Files Found")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text("The monitored local folders do not contain supported audio files (FLAC, MP3, M4A, AAC, WAV, AIFF, DSD).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 10) {
                Button("Add Another Folder...") {
                    openFolderPicker()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(WalkmanTheme.silverGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .buttonStyle(.plain)

                Button("Rescan Monitored Folders") {
                    localService.rescanAllFolders()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("No Matching Local Tracks")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            if !searchQuery.isEmpty && formatFilter != "ALL" {
                Text("No tracks matched your query \"\(searchQuery)\" with format filter \"\(formatFilter)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if !searchQuery.isEmpty {
                Text("No tracks matched your search query \"\(searchQuery)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if formatFilter != "ALL" {
                Text("No tracks matched active format filter \"\(formatFilter)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("No local tracks match current filter criteria.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("Clear Filters") {
                searchQuery = ""
                formatFilter = "ALL"
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------------------
    // TRANSFER TO WALKMAN ORCHESTRATION
    // -------------------------------------------------------------------------
    private func handleTransferToWalkman(tracks: [Track]) {
        guard !tracks.isEmpty else { return }

        // 1. Check if a physical Sony Walkman DAP is mounted
        let walkmanDrive = (activeDrive != nil && activeDrive?.type != .local) ? activeDrive : drives.first(where: { $0.type == .internal || $0.type == .microsd })
        guard let targetDrive = walkmanDrive else {
            // No Walkman device connected -> Show Warning Alert offering redirect to Transfer & Convert tab
            transferWarningTitle = "No Walkman Connected"
            transferWarningMessage = "Please connect your Sony Walkman DAP via USB Mass Storage to transfer songs directly.\n\nWould you like to redirect to the Transfer & Convert tab to prepare your queue?"
            pendingWarningTracks = tracks
            hasMixedFormats = false
            showTransferWarningAlert = true
            return
        }

        // 2. Format Support Check
        let unsupported = tracks.filter { track in
            let ext = URL(fileURLWithPath: track.fullPath).pathExtension.lowercased()
            return !TransferQueueService.isFormatSupported(ext: ext)
        }

        if !unsupported.isEmpty {
            let uniqueExts = Array(Set(unsupported.map { ".\(URL(fileURLWithPath: $0.fullPath).pathExtension.lowercased())" })).sorted().joined(separator: ", ")
            pendingWarningTracks = tracks

            if unsupported.count == tracks.count {
                // ALL selected tracks are unsupported
                hasMixedFormats = false
                transferWarningTitle = "Unsupported Audio Format"
                transferWarningMessage = "The selected track\(tracks.count == 1 ? " is" : "s are") in an audio format (\(uniqueExts)) not natively supported by Sony Walkman non-Android firmware.\n\nRedirect to the Transfer & Convert tab to optimize and convert \(tracks.count == 1 ? "this track" : "these tracks") before transferring to your Walkman?"
                showTransferWarningAlert = true
            } else {
                // MIXED: some supported, some unsupported
                hasMixedFormats = true
                let supported = tracks.filter { track in
                    let ext = URL(fileURLWithPath: track.fullPath).pathExtension.lowercased()
                    return TransferQueueService.isFormatSupported(ext: ext)
                }
                supportedTracksForMixedChoice = supported
                transferWarningTitle = "Unsupported Formats Detected"
                transferWarningMessage = "\(unsupported.count) of \(tracks.count) selected tracks are in formats (\(uniqueExts)) not natively playable on Sony Walkman.\n\nWould you like to redirect to the Transfer & Convert tab to optimize all tracks, or transfer only the \(supported.count) supported track\(supported.count == 1 ? "" : "s") directly?"
                showTransferWarningAlert = true
            }
            return
        }

        // 3. ALL tracks are supported -> Execute Direct Transfer to Walkman
        startDirectTransfer(tracks: tracks, targetDrive: targetDrive)
    }

    private func startDirectTransfer(tracks: [Track], targetDrive: WalkmanDrive) {
        directTransferTotalCount = tracks.count
        directTransferCurrentIndex = 0
        directTransferProgress = 0.0
        directTransferCurrentTitle = tracks.first?.title ?? ""
        directTransferTargetName = targetDrive.name
        directTransferComplete = false
        showDirectTransferSheet = true
        isDirectTransferring = true

        Task {
            do {
                _ = try await TransferQueueService.shared.transferDirectly(
                    tracks: tracks,
                    to: targetDrive
                ) { current, total, trackTitle in
                    Task { @MainActor in
                        self.directTransferCurrentIndex = current
                        self.directTransferCurrentTitle = trackTitle
                        self.directTransferProgress = total > 0 ? Double(current) / Double(total) : 1.0
                    }
                }
                await MainActor.run {
                    self.directTransferProgress = 1.0
                    self.directTransferComplete = true
                    self.isDirectTransferring = false
                    self.onTransferComplete?()
                }
            } catch {
                await MainActor.run {
                    self.isDirectTransferring = false
                    self.showDirectTransferSheet = false
                    self.transferWarningTitle = "Transfer Failed"
                    self.transferWarningMessage = error.localizedDescription
                    self.showTransferWarningAlert = true
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------
// LOCAL FOLDER ROW CARD
// -----------------------------------------------------------------------------
private struct LocalFolderRowCard: View {
    let folder: LocalMusicFolder
    var onSelect: (() -> Void)? = nil
    var onRescan: (() -> Void)? = nil
    let onReveal: () -> Void
    let onRemove: () -> Void
    var onTransfer: (() -> Void)? = nil

    @State private var isHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 GB" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { onSelect?() }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 40, height: 40)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(folder.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)

                            Text("\(folder.trackCount) tracks")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.10))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(Capsule())

                            Text(formatBytes(folder.totalBytes))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }

                        Text(folder.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                if let onRescan = onRescan {
                    Button(action: onRescan) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan this folder")
                }

                Button(action: onReveal) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Remove folder from Local Music Library")
            }
        }
        .padding(12)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.16 : 0.06), lineWidth: 0.8)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            if let onTransfer = onTransfer {
                Button {
                    onTransfer()
                } label: {
                    Label("Transfer Folder to Walkman", systemImage: "arrow.right.circle.fill")
                }
                Divider()
            }
            Button("Open Folder in Songs View") {
                onSelect?()
            }
            Button("Reveal in Finder", action: onReveal)
            Divider()
            Button("Remove from Local Library", role: .destructive, action: onRemove)
        }
    }
}

// MARK: - Liquid Glass Combined Filter & Sort Dropdown
private struct LocalFilterSortDropdown: View {
    @Binding var formatFilter: String
    @Binding var sortOption: LocalSortOption
    let formatOptions: [(id: String, label: String)]

    @State private var isHovered = false

    private var isFormatActive: Bool {
        formatFilter != "ALL"
    }

    private var isSortActive: Bool {
        sortOption != .artistAZ
    }

    private var isFilterOrSortActive: Bool {
        isFormatActive || isSortActive
    }

    private var activeFormatLabel: String {
        formatOptions.first(where: { $0.id == formatFilter })?.label ?? formatFilter
    }

    var body: some View {
        Menu {
            // -------------------------------------------------------------
            // SECTION 1: Audio Formats
            // -------------------------------------------------------------
            Section("Audio Format") {
                ForEach(formatOptions, id: \.id) { opt in
                    Button {
                        formatFilter = opt.id
                    } label: {
                        HStack {
                            if formatFilter == opt.id {
                                Image(systemName: "checkmark")
                            }
                            if opt.id == "HI-RES" {
                                Label(opt.label, systemImage: "waveform")
                            } else {
                                Text(opt.label)
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // SECTION 2: Sort Criteria
            // -------------------------------------------------------------
            Section("Sort By") {
                ForEach(LocalSortOption.allCases) { opt in
                    Button {
                        sortOption = opt
                    } label: {
                        HStack {
                            if sortOption == opt {
                                Image(systemName: "checkmark")
                            }
                            Label(opt.rawValue, systemImage: opt.iconName)
                        }
                    }
                }
            }

            // -------------------------------------------------------------
            // SECTION 3: Reset
            // -------------------------------------------------------------
            if isFilterOrSortActive {
                Divider()
                Button(role: .destructive) {
                    formatFilter = "ALL"
                    sortOption = .artistAZ
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

                // Filter icon (3 horizontal decreasing lines), enlarged
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16.5, weight: .semibold))
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
            .frame(width: 36, height: 36)
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
        .help("Filter & Sort: \(activeFormatLabel) • \(sortOption.rawValue)")
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .fixedSize()
    }
}

// MARK: - Liquid Glass Display Mode Segmented Control
private struct LocalDisplayModeSegmentedControl: View {
    @Binding var displayMode: LocalDisplayMode
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: LocalDisplayMode = .songs

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LocalDisplayMode.allCases) { mode in
                LocalDisplayModePillView(
                    mode: mode,
                    isSelected: activeHighlightId == mode,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard displayMode != mode else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeHighlightId = mode
                        }
                        displayMode = mode
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

private struct LocalDisplayModePillView: View {
    let mode: LocalDisplayMode
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
                            .matchedGeometryEffect(id: "activeDisplayModeHighlight", in: namespace)
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
        .contentShape(Capsule())
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
    }
}

// -----------------------------------------------------------------------------
// DIRECT TRANSFER PROGRESS SHEET
// -----------------------------------------------------------------------------
private struct DirectTransferSheet: View {
    let targetName: String
    let current: Int
    let total: Int
    let currentTitle: String
    let progress: Double
    let isComplete: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // Header with Icon
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalkmanTheme.hiResGoldGradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: WalkmanTheme.hiResGold.opacity(0.3), radius: 6, x: 0, y: 2)

                    Image(systemName: isComplete ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isComplete ? "Transfer Complete" : "Transferring to Walkman...")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text(targetName)
                        .font(.system(size: 12))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }

            // Progress Details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isComplete ? "\(total) track\(total == 1 ? "" : "s") transferred" : "Track \(current) of \(total)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Spacer()

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 7)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(WalkmanTheme.hiResGoldGradient)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(progress))), height: 7)
                            .animation(.linear(duration: 0.15), value: progress)
                    }
                }
                .frame(height: 7)

                if !isComplete && !currentTitle.isEmpty {
                    Text(currentTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
            )

            // Hardware compliance caption
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                Text("Baseline RGB 800x800 JPEG • Strict ID3v2.3 UTF-16 • AppleDouble Cleaned")
                    .font(.system(size: 10))
                    .foregroundStyle(WalkmanTheme.silverDark)
            }

            if isComplete {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(WalkmanTheme.background)
    }
}

