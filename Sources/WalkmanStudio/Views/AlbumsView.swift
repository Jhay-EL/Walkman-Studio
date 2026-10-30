import SwiftUI
import AppKit

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

public enum AlbumSortOption: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case nameAsc = "Album Name (A–Z)"
    case nameDesc = "Album Name (Z–A)"
    case artistAsc = "Artist (A–Z)"
    case yearDesc = "Release Year (Newest)"
    case yearAsc = "Release Year (Oldest)"
    case trackCountDesc = "Track Count (Most)"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .nameAsc: return "arrow.up.circle"
        case .nameDesc: return "arrow.down.circle"
        case .artistAsc: return "music.mic"
        case .yearDesc, .yearAsc: return "calendar"
        case .trackCountDesc: return "list.number"
        }
    }
}

public struct AlbumsView: View {
    let tracks: [Track]
    let precomputedAlbums: [AlbumItem]?
    let showToolbar: Bool
    let externalSortOption: AlbumSortOption?
    let onSelectTrack: (Track) -> Void
    var onEditAlbum: ((AlbumItem) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onEditTrackWithList: ((Track, [Track]) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onDeleteAlbum: ((AlbumItem) -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onTransferAlbum: ((AlbumItem) -> Void)? = nil
    var onTransferTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedAlbum: AlbumItem? = nil
    @State private var searchQuery: String = ""
    @State private var sortOption: AlbumSortOption = .recentlyAdded
    @State private var formatFilter: String = "ALL"
    @State private var cachedAlbums: [AlbumItem] = []
    @State private var displayedAlbums: [AlbumItem] = []
    
    private let formatFilterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Formats", icon: nil, isHiRes: false),
        FilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
        FilterOption(id: "MP3", title: "MP3", icon: nil, isHiRes: false),
        FilterOption(id: "M4A", title: "M4A", icon: nil, isHiRes: false),
        FilterOption(id: "LEARNING", title: "Language Study", icon: "character.book.closed.fill", isHiRes: false),
        FilterOption(id: "HI-RES", title: "Hi-Res", icon: "waveform", isHiRes: true)
    ]
    
    public init(
        tracks: [Track],
        precomputedAlbums: [AlbumItem]? = nil,
        showToolbar: Bool = true,
        externalSortOption: AlbumSortOption? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditAlbum: ((AlbumItem) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onEditTrackWithList: ((Track, [Track]) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onDeleteAlbum: ((AlbumItem) -> Void)? = nil,
        onDeleteTrack: ((Track) -> Void)? = nil,
        onTransferAlbum: ((AlbumItem) -> Void)? = nil,
        onTransferTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedAlbums = precomputedAlbums
        self.showToolbar = showToolbar
        self.externalSortOption = externalSortOption
        self.onSelectTrack = onSelectTrack
        self.onEditAlbum = onEditAlbum
        self.onEditTrack = onEditTrack
        self.onEditTrackWithList = onEditTrackWithList
        self.onTrimCutTrack = onTrimCutTrack
        self.onDeleteAlbum = onDeleteAlbum
        self.onDeleteTrack = onDeleteTrack
        self.onTransferAlbum = onTransferAlbum
        self.onTransferTrack = onTransferTrack
        
        let initial = precomputedAlbums ?? []
        self._cachedAlbums = State(initialValue: initial)
        self._displayedAlbums = State(initialValue: initial)
    }
    
    private var effectiveSortOption: AlbumSortOption {
        externalSortOption ?? sortOption
    }
    
    private var baseAlbums: [AlbumItem] {
        if let pre = precomputedAlbums { return pre }
        if !cachedAlbums.isEmpty { return cachedAlbums }
        return []
    }
    
    nonisolated public static func buildAlbums(from tracks: [Track]) -> [AlbumItem] {
        var grouped: [String: [Track]] = [:]
        var displayNames: [String: String] = [:]
        
        for track in tracks {
            let trimmed = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let albName = trimmed.isEmpty ? "Unknown Album" : trimmed
            let key = albName.lowercased()
            
            if displayNames[key] == nil || (!trimmed.isEmpty && displayNames[key] == "Unknown Album") {
                displayNames[key] = albName
            }
            grouped[key, default: []].append(track)
        }
        
        var list: [AlbumItem] = []
        for (key, albumTracks) in grouped {
            let albumName = displayNames[key] ?? key
            
            // Sort tracks by track number, then title
            let sortedTracks = albumTracks.sorted {
                let num0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                let num1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                if num0 != num1 && num0 > 0 && num1 > 0 {
                    return num0 < num1
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            
            // Determine primary album artist
            var artistCounts: [String: Int] = [:]
            for track in sortedTracks {
                let art = track.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                if !art.isEmpty && art != "Unknown Artist" {
                    artistCounts[art, default: 0] += 1
                }
            }
            
            let albumArtist: String
            if artistCounts.isEmpty {
                albumArtist = "Unknown Artist"
            } else if artistCounts.count == 1 {
                albumArtist = artistCounts.keys.first!
            } else {
                let sortedArtists = artistCounts.sorted { $0.value > $1.value }
                let topArtist = sortedArtists[0]
                // If the top artist accounts for more than half of the tracks, treat as primary album artist
                if Double(topArtist.value) / Double(sortedTracks.count) > 0.50 {
                    albumArtist = topArtist.key
                } else {
                    let lowerAlb = albumName.lowercased()
                    let isSoundtrack = lowerAlb.contains("soundtrack") || lowerAlb.contains("ost") || sortedTracks.contains(where: { $0.genre.lowercased().contains("soundtrack") })
                    albumArtist = isSoundtrack ? "Soundtrack / Various Artists" : "Various Artists"
                }
            }
            
            let year = sortedTracks.first(where: { !$0.year.isEmpty })?.year ?? ""
            list.append(AlbumItem(
                name: albumName,
                artist: albumArtist,
                year: year,
                trackCount: sortedTracks.count,
                tracks: sortedTracks
            ))
        }
        
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - High-Performance Filter Pipeline (< 1ms execution, Isolated from Hover State)
    
    private func recomputeDisplayedAlbums() {
        if !showToolbar, let pre = precomputedAlbums {
            displayedAlbums = pre
            return
        }
        let list = baseAlbums
        if list.isEmpty {
            displayedAlbums = []
            return
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasQuery = !q.isEmpty
        let isAllFormat = formatFilter == "ALL"
        
        let filtered = list.filter { alb in
            if hasQuery {
                let match = alb.name.localizedCaseInsensitiveContains(q) || alb.artist.localizedCaseInsensitiveContains(q)
                if !match { return false }
            }
            if !isAllFormat {
                switch formatFilter {
                case "HI-RES":
                    if !alb.isHiRes { return false }
                case "LEARNING":
                    if !alb.isLanguageStudy { return false }
                case "FLAC":
                    if !alb.tracks.contains(where: { $0.format == "FLAC" }) { return false }
                case "MP3":
                    if !alb.tracks.contains(where: { $0.format == "MP3" }) { return false }
                case "M4A":
                    if !alb.tracks.contains(where: { $0.format == "M4A" || $0.format == "AAC" || $0.format == "ALAC" }) { return false }
                default:
                    break
                }
            }
            return true
        }
        
        switch effectiveSortOption {
        case .recentlyAdded:
            displayedAlbums = filtered.sorted {
                if $0.latestDateAdded != $1.latestDateAdded {
                    return $0.latestDateAdded > $1.latestDateAdded
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .nameAsc:
            displayedAlbums = filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            displayedAlbums = filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .artistAsc:
            displayedAlbums = filtered.sorted {
                let cmp = $0.artist.localizedStandardCompare($1.artist)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .yearDesc:
            displayedAlbums = filtered.sorted {
                let yA = Int($0.year) ?? 0
                let yB = Int($1.year) ?? 0
                if yA != yB { return yA > yB }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .yearAsc:
            displayedAlbums = filtered.sorted {
                let yA = Int($0.year) ?? 9999
                let yB = Int($1.year) ?? 9999
                if yA != yB { return yA < yB }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .trackCountDesc:
            displayedAlbums = filtered.sorted {
                if $0.trackCount != $1.trackCount {
                    return $0.trackCount > $1.trackCount
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let album = selectedAlbum {
                // Album Detail View (Tactile Liquid Glass Console)
                AlbumDetailView(
                    album: album,
                    onBack: { selectedAlbum = nil },
                    onSelectTrack: onSelectTrack,
                    onEditAlbum: {
                        onEditAlbum?(album)
                    },
                    onEditTrack: { tr in
                        if let onEditTrackWithList = onEditTrackWithList {
                            onEditTrackWithList(tr, album.tracks)
                        } else {
                            onEditTrack?(tr)
                        }
                    },
                    onEditTrackWithList: onEditTrackWithList,
                    onTrimCutTrack: { tr in
                        onTrimCutTrack?(tr)
                    },
                    onDeleteAlbum: {
                        selectedAlbum = nil
                        onDeleteAlbum?(album)
                    },
                    onDeleteTrack: { tr in
                        onDeleteTrack?(tr)
                    },
                    onTransferAlbum: onTransferAlbum != nil ? { onTransferAlbum?(album) } : nil,
                    onTransferTrack: onTransferTrack
                )
            } else {
                // Albums Grid View
                VStack(spacing: 0) {
                    if showToolbar {
                        toolbarContainer
                    }
                    
                    if displayedAlbums.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 18)], spacing: 22) {
                                ForEach(displayedAlbums, id: \.self) { alb in
                                    AlbumGridCard(
                                        album: alb,
                                        onOpen: { selectedAlbum = alb },
                                        onInspectAlbum: {
                                            if let rep = alb.representativeTrack {
                                                onSelectTrack(rep)
                                            }
                                        },
                                        onEditAlbum: {
                                            onEditAlbum?(alb)
                                        },
                                        onDeleteAlbum: {
                                            onDeleteAlbum?(alb)
                                        },
                                        onTransferAlbum: onTransferAlbum != nil ? { onTransferAlbum?(alb) } : nil
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 88)
                        }
                    }
                }
            }
        }
        .onAppear {
            player.activeQueueProvider = nil
            if cachedAlbums.isEmpty && precomputedAlbums == nil && !tracks.isEmpty {
                cachedAlbums = Self.buildAlbums(from: tracks)
                recomputeDisplayedAlbums()
            } else if precomputedAlbums != nil {
                recomputeDisplayedAlbums()
            }
        }
        .onChange(of: precomputedAlbums) { _, newPrecomputed in
            if let newPrecomputed = newPrecomputed {
                cachedAlbums = newPrecomputed
                recomputeDisplayedAlbums()
                
                // If user was viewing an album detail, refresh selectedAlbum to the new instance
                if let currentSel = selectedAlbum {
                    if let updated = newPrecomputed.first(where: { $0.id == currentSel.id }) {
                        selectedAlbum = updated
                    } else {
                        let trackPaths = Set(currentSel.tracks.map(\.fullPath))
                        if let updated = newPrecomputed.first(where: { alb in
                            alb.tracks.contains(where: { trackPaths.contains($0.fullPath) })
                        }) {
                            selectedAlbum = updated
                        }
                    }
                }
            } else {
                recomputeDisplayedAlbums()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackMetadataDidUpdate)) { _ in
            if precomputedAlbums == nil && !tracks.isEmpty {
                cachedAlbums = Self.buildAlbums(from: tracks)
            }
            recomputeDisplayedAlbums()
        }
        .onChange(of: tracks) { _, newTracks in
            if let sel = selectedAlbum, !newTracks.contains(where: { $0.album.lowercased() == sel.name.lowercased() }) {
                selectedAlbum = nil
            }
            if precomputedAlbums != nil {
                recomputeDisplayedAlbums()
                return
            }
            Task.detached(priority: .userInitiated) {
                let built = Self.buildAlbums(from: newTracks)
                await MainActor.run {
                    self.cachedAlbums = built
                    self.recomputeDisplayedAlbums()
                }
            }
        }
        .onChange(of: searchQuery) { _, _ in
            recomputeDisplayedAlbums()
        }
        .onChange(of: formatFilter) { _, _ in
            recomputeDisplayedAlbums()
        }
        .onChange(of: sortOption) { _, _ in
            recomputeDisplayedAlbums()
        }
        .onChange(of: externalSortOption) { _, _ in
            recomputeDisplayedAlbums()
        }
        .onChange(of: cachedAlbums) { _, _ in
            recomputeDisplayedAlbums()
        }
    }
    
    // -------------------------------------------------------------------------
    // RESPONSIVE TOOLBAR (LIQUID GLASS + VIEWTHATFITS FOR SMALL WINDOWS)
    // -------------------------------------------------------------------------
    
    private var toolbarContainer: some View {
        ViewThatFits(in: .horizontal) {
            wideToolbarLayout
            compactToolbarLayout
            narrowToolbarLayout
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
    }
    
    private var wideToolbarLayout: some View {
        HStack(spacing: 8) {
            searchFieldView
                .frame(minWidth: 110, maxWidth: 220)
            
            formatSegmentedBar
                .fixedSize(horizontal: true, vertical: false)
            
            filterMenuButton
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            albumCountPill
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private var compactToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 80, maxWidth: .infinity)
                
                albumCountPill
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    formatSegmentedBar
                        .fixedSize(horizontal: true, vertical: false)
                    
                    filterMenuButton
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 1)
            }
        }
    }
    
    private var narrowToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 80, maxWidth: .infinity)
                
                albumCountPill
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    formatSegmentedBar
                        .fixedSize(horizontal: true, vertical: false)
                    
                    filterMenuButton
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 1)
            }
        }
    }
    
    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
            
            TextField("Search albums or artists...", text: $searchQuery)
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
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7.5)
        .frame(height: 38)
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
    
    private var filterMenuButton: some View {
        AlbumFilterSortMenuButton(
            sortOption: $sortOption
        )
    }
    
    private var formatSegmentedBar: some View {
        AlbumFormatSegmentedBarView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private var albumCountPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text(displayedAlbums.count == 1 ? "1 Album" : "\(displayedAlbums.count.formatted()) Albums")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            ZStack {
                Color.white.opacity(0.04)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
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
                            .init(color: Color.white.opacity(0.20), location: 0.0),
                            .init(color: Color.white.opacity(0.08), location: 0.5),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 2, x: 0, y: 1)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Matching Albums")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(searchQuery.isEmpty
                 ? "No albums match the selected format filter."
                 : "No albums match \"\(searchQuery)\" with the selected filter.")
                .font(WalkmanFont.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button(action: {
                searchQuery = ""
                formatFilter = "ALL"
            }) {
                Text("Reset Filters")
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
}

// -----------------------------------------------------------------------------
// FILTER & SORT MENU BUTTON (APPLE-STYLE CIRCULAR FILTER ICON & DROPDOWN)
// -----------------------------------------------------------------------------
private struct AlbumFilterSortMenuButton: View {
    @Binding var sortOption: AlbumSortOption
    
    @State private var isHovered = false
    
    private var isSortActive: Bool {
        sortOption != .recentlyAdded
    }
    
    var body: some View {
        Menu {
            Picker("Sort Options", selection: $sortOption) {
                ForEach(AlbumSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ZStack {
                // Circular glass body
                Circle()
                    .fill(
                        isSortActive ?
                            Color.white.opacity(isHovered ? 0.16 : 0.12) :
                            Color.white.opacity(isHovered ? 0.10 : 0.05)
                    )
                
                // Top specular refraction sheen (Liquid Glass)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.32 : (isSortActive ? 0.24 : 0.12)), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())
                
                // Apple filter icon (3 horizontal decreasing lines)
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isSortActive ?
                            Color.white :
                            (isHovered ? Color.white : WalkmanTheme.silverLight)
                    )
                
                // Active beacon indicator (subtle 5pt dot at top right when non-default sort is active)
                if isSortActive {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(5)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        isSortActive ?
                            Color.white.opacity(0.32) :
                            Color.white.opacity(isHovered ? 0.22 : 0.10),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.20 : 0.10), radius: isHovered ? 3.5 : 2, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help("Sort albums (\(sortOption.rawValue))")
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
// ALBUM FORMAT SEGMENTED BAR (MATCHED GEOMETRY SLIDING LIQUID GLASS LENS)
// -----------------------------------------------------------------------------
private struct AlbumFormatSegmentedBarView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    let onSelectFilter: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                AlbumFormatTabPillView(
                    option: opt,
                    isSelected: activeHighlightId == opt.id,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard selectedFilter != opt.id else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeHighlightId = opt.id
                        }
                        onSelectFilter(opt.id)
                    }
                )
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeHighlightId = selectedFilter
        }
        .onChange(of: selectedFilter) { _, newFilter in
            if activeHighlightId != newFilter {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeHighlightId = newFilter
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------
// ALBUM FORMAT TAB PILL VIEW (ROUND LIQUID GLASS CLICK BOX WITH HOVER)
// -----------------------------------------------------------------------------
private struct AlbumFormatTabPillView: View {
    let option: FilterOption
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5.5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                }
                Text(option.title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    (option.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        // Liquid Glass Active Pill Highlight — smoothly transfers via matched geometry
                        ActiveAlbumPillBackground(isHiRes: option.isHiRes, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeAlbumFormatHighlight", in: namespace)
                    } else if isHovered {
                        // Liquid Glass Hover Pill (Round frosted glass box)
                        HoverAlbumPillBackground()
                    } else {
                        // Transparent hit-testable canvas
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

private struct ActiveAlbumPillBackground: View {
    let isHiRes: Bool
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            // Liquid Glass Translucent Body Fill
            Color.white.opacity(isHiRes ? 0.13 : 0.16)
            
            // Top specular refraction sheen
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isHiRes ?
                        WalkmanTheme.hiResGold.opacity(isHovered ? 0.65 : 0.55) :
                        Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.30 : 0.22),
            radius: isHovered ? 4 : 2.5,
            x: 0,
            y: 1
        )
    }
}

private struct HoverAlbumPillBackground: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.09)
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.20), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5.5)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// -----------------------------------------------------------------------------
// ALBUM GRID CARD (TACTILE HOVER, SMOOTH CURSOR, FLOATING QUICK PLAY)
// -----------------------------------------------------------------------------
private struct AlbumGridCard: View {
    let album: AlbumItem
    let onOpen: () -> Void
    var onInspectAlbum: (() -> Void)? = nil
    var onEditAlbum: (() -> Void)? = nil
    var onDeleteAlbum: (() -> Void)? = nil
    var onTransferAlbum: (() -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var isHovered = false
    
    private var isAlbumPlaying: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && album.tracks.contains(where: { $0.id == current.id })
    }
    
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                // Artwork Tile
                ZStack(alignment: .bottomTrailing) {
                    if let rep = album.representativeTrack {
                        TrackCoverThumbnail(track: rep, size: 160)
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(isHovered ? 0.22 : 0.08), lineWidth: 0.85)
                            )
                            .shadow(color: Color.black.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 10 : 6, x: 0, y: isHovered ? 5 : 3)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WalkmanTheme.card)
                            .frame(width: 160, height: 160)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(isHovered ? 0.22 : 0.08), lineWidth: 0.85)
                            )
                            .shadow(color: Color.black.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 10 : 6, x: 0, y: isHovered ? 5 : 3)
                    }
                    
                    // Quick Play floating action button on hover
                    if isHovered {
                        Button {
                            if isAlbumPlaying {
                                player.pause()
                            } else if let current = player.currentTrack, album.tracks.contains(where: { $0.id == current.id }) {
                                player.play()
                            } else if let first = album.tracks.first {
                                player.play(track: first, in: album.tracks)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 245/255, green: 247/255, blue: 252/255))
                                    .frame(width: 36, height: 36)
                                    .shadow(color: Color.black.opacity(0.40), radius: 5, x: 0, y: 2)
                                Image(systemName: isAlbumPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .offset(x: isAlbumPlaying ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        if album.isHiRes {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(WalkmanTheme.hiResGold.opacity(0.92))
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .shadow(color: Color.black.opacity(0.30), radius: 2, y: 1)
                                .padding(8)
                        } else if album.isLanguageStudy {
                            HStack(spacing: 3.5) {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.system(size: 8))
                                Text("Learning")
                            }
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.85))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .shadow(color: Color.black.opacity(0.30), radius: 2, y: 1)
                            .padding(8)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(isHovered ? Color.white : WalkmanTheme.silverLight)
                        .lineLimit(1)
                    
                    Text(album.artist)
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if !album.year.isEmpty {
                            Text(album.year)
                            Text("•")
                        }
                        Text("\(album.trackCount) tracks")
                    }
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.80))
                }
                .frame(width: 160, alignment: .leading)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
            )
            .scaleEffect(isHovered ? 1.025 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contextMenu {
            if let onTransfer = onTransferAlbum {
                Button {
                    onTransfer()
                } label: {
                    Label("Transfer Album to Walkman", systemImage: "arrow.right.circle.fill")
                }
                Divider()
            }

            Button(action: onOpen) {
                Label("View Album Details", systemImage: "music.note.list")
            }
            
            Button {
                if isAlbumPlaying {
                    player.pause()
                } else if let current = player.currentTrack, album.tracks.contains(where: { $0.id == current.id }) {
                    player.play()
                } else if let first = album.tracks.first {
                    player.play(track: first, in: album.tracks)
                }
            } label: {
                Label(isAlbumPlaying ? "Pause Album" : "Play Album", systemImage: isAlbumPlaying ? "pause.fill" : "play.fill")
            }
            
            Divider()
            
            Button {
                onEditAlbum?()
            } label: {
                Label("Edit Album Metadata...", systemImage: "square.and.pencil")
            }
            
            Button {
                ArtworkExportService.exportArtwork(for: album)
            } label: {
                Label("Export Album Artwork to Mac...", systemImage: "square.and.arrow.down")
            }
            
            Button {
                onInspectAlbum?()
            } label: {
                Label("Inspect in Sidebar", systemImage: "sidebar.trailing")
            }
            
            if let rep = album.representativeTrack {
                Button {
                    let dir = URL(fileURLWithPath: rep.fullPath).deletingLastPathComponent().path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dir, forType: .string)
                } label: {
                    Label("Copy Album Folder Path", systemImage: "doc.on.doc")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDeleteAlbum?()
            } label: {
                Label("Delete Album from Device", systemImage: "trash")
            }
        }
    }
}

// -----------------------------------------------------------------------------
// ALBUM DETAIL VIEW (TACTILE AUDIO CONSOLE)
// -----------------------------------------------------------------------------
private struct AlbumDetailView: View {
    let album: AlbumItem
    let onBack: () -> Void
    let onSelectTrack: (Track) -> Void
    var onEditAlbum: (() -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onEditTrackWithList: ((Track, [Track]) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onDeleteAlbum: (() -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onTransferAlbum: (() -> Void)? = nil
    var onTransferTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    private var isAlbumPlaying: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && album.tracks.contains(where: { $0.id == current.id })
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private var totalDurationSeconds: Double {
        album.tracks.reduce(0) { $0 + $1.durationSeconds }
    }
    
    private var albumTypeString: String {
        if album.trackCount == 1 {
            return "SINGLE"
        } else if album.trackCount <= 5 {
            return "EP"
        } else if album.artist.localizedCaseInsensitiveContains("various") {
            return "COMPILATION"
        } else {
            return "ALBUM"
        }
    }
    
    private var genreString: String? {
        album.tracks.compactMap { tr in
            let g = tr.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            return g.isEmpty ? nil : g
        }.first
    }
    
    private var totalDurationFormatted: String {
        let total = totalDurationSeconds
        if total <= 0 { return "\(album.trackCount) Songs" }
        let hours = Int(total) / 3600
        let mins = (Int(total) % 3600) / 60
        let secs = Int(total) % 60
        if hours > 0 {
            return "\(album.trackCount) Songs, \(hours) hr \(mins) min"
        } else if mins > 0 {
            return "\(album.trackCount) Songs, \(mins) min \(secs) sec"
        } else {
            return "\(album.trackCount) Songs, \(secs) sec"
        }
    }
    
    private var totalFileSizeFormatted: String {
        let bytes = album.tracks.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if bytes <= 0 { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private var maxAudioQualityString: String {
        let maxBits = album.tracks.map(\.bitsPerSample).max() ?? 0
        let maxSampleRate = album.tracks.map(\.sampleRate).max() ?? 0
        let format = album.primaryFormat
        
        if maxBits > 0 && maxSampleRate > 0 {
            let khz = Double(maxSampleRate) / 1000.0
            let khzStr = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            return "\(format) • \(maxBits)-bit / \(khzStr) kHz"
        } else if maxSampleRate > 0 {
            let khz = Double(maxSampleRate) / 1000.0
            let khzStr = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            return "\(format) • \(khzStr) kHz"
        }
        return format
    }
    
    private var avgBitrateString: String? {
        let bitrates = album.tracks.map(\.bitrateKbps).filter { $0 > 0 }
        guard !bitrates.isEmpty else { return nil }
        let avg = bitrates.reduce(0, +) / bitrates.count
        return "\(avg) kbps"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Back Navigation Header
            HStack(spacing: 8) {
                AlbumDetailBackButton(onBack: onBack)
                Spacer()
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Album Hero Header (Apple Music macOS Redesign)
                    albumHeroHeader
                    
                    // Tracklist Column Header
                    HStack(spacing: 12) {
                        Text("#")
                            .font(.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .frame(width: 26, alignment: .trailing)
                        
                        Text("Title")
                            .font(.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                        
                        Spacer()
                        
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.8)
                        .padding(.horizontal, 24)
                    
                    // Tracklist Rows
                    VStack(spacing: 2) {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                            AlbumTrackRowView(
                                index: index + 1,
                                track: track,
                                album: album,
                                onSelect: {
                                    onSelectTrack(track)
                                },
                                onPlayToggle: {
                                    player.playOrToggle(track: track, in: album.tracks)
                                },
                                onEdit: {
                                    if let onEditTrackWithList = onEditTrackWithList {
                                        onEditTrackWithList(track, album.tracks)
                                    } else {
                                        onEditTrack?(track)
                                    }
                                },
                                onTrimCut: {
                                    onTrimCutTrack?(track)
                                },
                                onDelete: {
                                    onDeleteTrack?(track)
                                },
                                onTransfer: onTransferTrack != nil ? { onTransferTrack?(track) } : nil
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Apple Music Style Album Copyright & Summary Footer
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(totalDurationFormatted)
                            if !totalFileSizeFormatted.isEmpty {
                                Text("•")
                                Text(totalFileSizeFormatted)
                            }
                        }
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        
                        if !album.year.isEmpty {
                            Text("℗ \(album.year) \(album.artist)")
                                .font(.caption)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
                    .padding(.bottom, 88)
                }
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // ALBUM HERO HEADER & ACTION BUTTONS
    // -------------------------------------------------------------------------
    
    private var albumHeroHeader: some View {
        HStack(alignment: .top, spacing: 26) {
            // Large Album Cover Art (220x220 pt)
            albumCoverArtView
            
            // Prominent Metadata Details & Action Controls
            VStack(alignment: .leading, spacing: 6) {
                // 1. Album Type Kicker
                Text(albumTypeString)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .tracking(1.4)
                
                // 2. Big Prominent Album Title (28pt Bold)
                Text(album.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 3. Artist Name (18pt Semibold)
                Text(album.artist)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)
                
                // 4. Primary Metadata line (Genre • Year • Total Duration • Total Size)
                HStack(spacing: 6) {
                    if let genre = genreString {
                        Text(genre)
                        Text("•")
                    }
                    if !album.year.isEmpty {
                        Text(album.year)
                        Text("•")
                    }
                    Text(totalDurationFormatted)
                    if !totalFileSizeFormatted.isEmpty {
                        Text("•")
                        Text(totalFileSizeFormatted)
                    }
                }
                .font(WalkmanFont.callout)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .padding(.top, 2)
                
                // 5. Important Specification Badges (Hi-Res Audio, Format & Resolution, Bitrate)
                HStack(spacing: 7) {
                    if album.isHiRes {
                        HStack(spacing: 4.5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Hi-Res Audio")
                                .font(WalkmanFont.badge)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(WalkmanTheme.hiResGold.opacity(0.92))
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                    } else if album.isLanguageStudy {
                        HStack(spacing: 4) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.system(size: 9))
                            Text("Language Study")
                        }
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.85))
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                    }
                    
                    // Audio Quality Specs Pill
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(album.isHiRes ? WalkmanTheme.hiResGoldLight : WalkmanTheme.silverLight)
                        Text(maxAudioQualityString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    
                    // Bitrate Pill
                    if let avgBitrate = avgBitrateString {
                        Text("~\(avgBitrate)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                    }
                }
                .padding(.top, 4)
                
                Spacer(minLength: 8)
                
                // 6. Action Buttons Bar
                albumActionButtonsView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
    
    private var albumCoverArtView: some View {
        Group {
            if let rep = album.representativeTrack {
                TrackCoverThumbnail(track: rep, size: 220)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(0.50), radius: 14, x: 0, y: 7)
            } else {
                ZStack {
                    Color.white.opacity(0.04)
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
            }
        }
        .contextMenu {
            if let onTransfer = onTransferAlbum {
                Button {
                    onTransfer()
                } label: {
                    Label("Transfer Album to Walkman", systemImage: "arrow.right.circle.fill")
                }
                Divider()
            }
            Button {
                onEditAlbum?()
            } label: {
                Label("Edit Album Metadata...", systemImage: "square.and.pencil")
            }
            Button {
                ArtworkExportService.exportArtwork(for: album)
            } label: {
                Label("Export Album Artwork to Mac...", systemImage: "square.and.arrow.down")
            }
            if let rep = album.representativeTrack {
                Button {
                    let dir = URL(fileURLWithPath: rep.fullPath).deletingLastPathComponent().path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dir, forType: .string)
                } label: {
                    Label("Copy Album Folder Path", systemImage: "doc.on.doc")
                }
            }
        }
    }
    
    private var albumActionButtonsView: some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout (single row with labels)
            HStack(spacing: 8) {
                playButton
                shuffleButton
                editLabeledButton
                getInfoLabeledButton
                moreMenuButton
            }
            
            // Compact layout (Apple Music style circular liquid glass buttons)
            HStack(spacing: 8) {
                playButton
                shuffleButton
                editCircularButton
                getInfoCircularButton
                moreMenuButton
            }
            
            // Ultra-compact layout (two rows)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    playButton
                    shuffleButton
                }
                HStack(spacing: 8) {
                    editCircularButton
                    getInfoCircularButton
                    exportCircularButton
                    moreMenuButton
                }
            }
        }
        .padding(.top, 4)
    }
    
    private var playButton: some View {
        Button(action: {
            if isAlbumPlaying {
                player.pause()
            } else if let current = player.currentTrack, album.tracks.contains(where: { $0.id == current.id }) {
                player.play()
            } else if let first = album.tracks.first {
                player.play(track: first, in: album.tracks)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isAlbumPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isAlbumPlaying ? "Pause" : "Play")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help(isAlbumPlaying ? "Pause album playback" : "Play album from the beginning")
    }
    
    private var shuffleButton: some View {
        Button(action: {
            if let randomTrack = album.tracks.randomElement() {
                let shuffled = album.tracks.shuffled()
                player.play(track: randomTrack, in: shuffled)
            }
        }) {
            HStack(spacing: 5.5) {
                Image(systemName: "shuffle")
                    .font(.system(size: 11, weight: .semibold))
                Text("Shuffle")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Shuffle tracks in this album")
    }
    
    private var editLabeledButton: some View {
        Button(action: { onEditAlbum?() }) {
            HStack(spacing: 5.5) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                Text("Edit Album")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Edit album artwork, tags, and track numbers in a popup window")
    }
    
    @ViewBuilder
    private var getInfoLabeledButton: some View {
        if let rep = album.representativeTrack {
            Button(action: { onSelectTrack(rep) }) {
                HStack(spacing: 5.5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Get Info")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
            .fixedSize(horizontal: true, vertical: false)
            .help("Inspect album metadata and cover artwork in sidebar")
        }
    }
    
    private var editCircularButton: some View {
        Button(action: { onEditAlbum?() }) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Edit album artwork, tags, and track numbers")
    }
    
    @ViewBuilder
    private var getInfoCircularButton: some View {
        if let rep = album.representativeTrack {
            Button(action: { onSelectTrack(rep) }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
            .fixedSize(horizontal: true, vertical: false)
            .help("Inspect album in sidebar")
        }
    }
    
    private var exportCircularButton: some View {
        Button(action: { ArtworkExportService.exportArtwork(for: album) }) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Export cover art to Mac")
    }
    
    private var moreMenuButton: some View {
        Menu {
            Button {
                onEditAlbum?()
            } label: {
                Label("Edit Album Metadata...", systemImage: "square.and.pencil")
            }
            
            if let rep = album.representativeTrack {
                Button {
                    onSelectTrack(rep)
                } label: {
                    Label("Inspect in Sidebar", systemImage: "sidebar.trailing")
                }
            }
            
            Button {
                ArtworkExportService.exportArtwork(for: album)
            } label: {
                Label("Export Album Artwork to Mac...", systemImage: "square.and.arrow.down")
            }
            
            if let rep = album.representativeTrack {
                Button {
                    let dir = URL(fileURLWithPath: rep.fullPath).deletingLastPathComponent().path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dir, forType: .string)
                } label: {
                    Label("Copy Album Folder Path", systemImage: "doc.on.doc")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDeleteAlbum?()
            } label: {
                Label("Delete Album from Device", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12.5, weight: .bold))
                .frame(width: 34, height: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .menuIndicator(.hidden)
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("More album options")
    }
}

// -----------------------------------------------------------------------------
// ALBUM DETAIL BACK BUTTON (ROUND PILL WITH HOVER SPRING KINETICS)
// -----------------------------------------------------------------------------
private struct AlbumDetailBackButton: View {
    let onBack: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text("Albums")
                    .font(WalkmanFont.calloutMedium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .frame(minHeight: 32)
            .background(
                ZStack {
                    Color.white.opacity(isHovered ? 0.09 : 0.04)
                    if isHovered {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.18), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5)
                            Spacer(minLength: 0)
                        }
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isHovered ? 0.22 : 0.10), lineWidth: 0.8)
            )
            .foregroundStyle(isHovered ? Color.white : WalkmanTheme.silverLight)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// -----------------------------------------------------------------------------
// ALBUM TRACK ROW VIEW (TACTILE HOVER & AUDIO STATE)
// -----------------------------------------------------------------------------
private struct AlbumTrackRowView: View {
    let index: Int
    let track: Track
    let album: AlbumItem
    let onSelect: () -> Void
    let onPlayToggle: () -> Void
    var onEdit: (() -> Void)? = nil
    var onTrimCut: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onTransfer: (() -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var isHovered = false
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        let isPlayingThis = player.currentTrack?.id == track.id && player.isPlaying
        
        HStack(spacing: 12) {
            // Track Number or Play/Pause Indicator
            ZStack {
                if isHovered {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isPlayingThis ? (album.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) : WalkmanTheme.silverLight)
                } else if isPlayingThis {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(album.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white)
                } else {
                    Text("\(index)")
                        .font(WalkmanFont.mono)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
            .frame(width: 26, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                    .foregroundStyle(isPlayingThis ? (album.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) : (isHovered ? Color.white : WalkmanTheme.silverLight))
                    .lineLimit(1)
                
                if album.artist.contains("Various Artists") || track.primaryArtist.lowercased() != album.artist.lowercased() {
                    Text(track.artist)
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                } else if let feat = track.featuredDisplayString(primaryArtist: album.artist) {
                    HStack(spacing: 4) {
                        Text("feat.")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                        Text(feat)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if track.bitsPerSample > 16 || track.sampleRate > 48000 {
                Text("Hi-Res")
                    .font(WalkmanFont.badge)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(WalkmanTheme.hiResGold.opacity(0.18))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(WalkmanTheme.hiResGold.opacity(0.4), lineWidth: 0.6)
                    )
            }
            
            Text(track.format)
                .font(WalkmanFont.badge)
                .padding(.horizontal, 5.5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )
            
            Text(formatDuration(track.durationSeconds))
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isPlayingThis ?
                        WalkmanTheme.cardHover :
                        (isHovered ? Color.white.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isPlayingThis ?
                        Color.white.opacity(0.12) :
                        (isHovered ? Color.white.opacity(0.06) : Color.clear),
                    lineWidth: 0.8
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            onPlayToggle()
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button(isPlayingThis ? "Pause" : "Play Track") {
                onPlayToggle()
            }
            Divider()
            if let onTransfer = onTransfer {
                Button {
                    onTransfer()
                } label: {
                    Label("Transfer to Walkman", systemImage: "arrow.right.circle.fill")
                }
                Divider()
            }
            Button {
                onEdit?()
            } label: {
                Label("Edit Song Metadata...", systemImage: "square.and.pencil")
            }
            Button {
                onTrimCut?()
            } label: {
                Label("Trim & Cut...", systemImage: "scissors")
            }
            Button {
                ArtworkExportService.exportArtwork(for: track)
            } label: {
                Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
            }
            Button("Inspect in Sidebar") {
                onSelect()
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.fullPath, forType: .string)
            }
            Divider()
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete from Device", systemImage: "trash")
            }
        }
    }
}
