import SwiftUI
import AppKit

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

fileprivate enum ArtistDetailWidthTier: Equatable {
    case extraWide // >= 520pt
    case wide      // 430..<520pt
    case compact   // 340..<430pt
    case minimal   // < 340pt

    init(width: CGFloat) {
        if width >= 520 {
            self = .extraWide
        } else if width >= 430 {
            self = .wide
        } else if width >= 340 {
            self = .compact
        } else {
            self = .minimal
        }
    }
}

public struct ArtistsView: View, Equatable {
    let tracks: [Track]
    let precomputedArtists: [ArtistItem]?
    let showToolbar: Bool
    var initialSelectedArtistName: String? = nil
    let onSelectTrack: (Track) -> Void
    var onEditTrack: ((Track) -> Void)? = nil
    var onEditTrackWithList: ((Track, [Track]) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onTransferArtist: ((ArtistItem) -> Void)? = nil
    var onTransferTracks: (([Track]) -> Void)? = nil
    var onTransferTrack: ((Track) -> Void)? = nil

    public static func == (lhs: ArtistsView, rhs: ArtistsView) -> Bool {
        lhs.tracks == rhs.tracks &&
        lhs.precomputedArtists == rhs.precomputedArtists &&
        lhs.showToolbar == rhs.showToolbar &&
        lhs.initialSelectedArtistName == rhs.initialSelectedArtistName
    }
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedArtistName: String? = nil
    @State private var searchQuery: String = ""
    @State private var isSearchExpanded: Bool = false
    @State private var formatFilter: String = "ALL"
    @State private var cachedArtists: [ArtistItem] = []
    @State private var displayedArtists: [ArtistItem] = []
    @State private var cachedActiveArtist: ArtistItem? = nil
    @State private var cachedFilteredAlbums: [AlbumItem] = []
    @State private var cachedHeroMetadata: String = ""
    @State private var cachedHeroQuality: String = ""
    @State private var cachedHeroAvgBitrate: String? = nil
    @State private var detailWidthTier: ArtistDetailWidthTier = .extraWide
    @State private var isCompactMasterColumn: Bool = false
    @State private var showBatchLyricsSheet: Bool = false
    @State private var isPreparingLyricsSheet: Bool = false
    
    private let formatFilterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Formats", icon: nil, isHiRes: false),
        FilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
        FilterOption(id: "MP3", title: "MP3", icon: nil, isHiRes: false),
        FilterOption(id: "M4A", title: "M4A", icon: nil, isHiRes: false),
        FilterOption(id: "HI-RES", title: "Hi-Res", icon: "waveform", isHiRes: true)
    ]
    
    public init(
        tracks: [Track],
        precomputedArtists: [ArtistItem]? = nil,
        showToolbar: Bool = true,
        initialSelectedArtistName: String? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditTrack: ((Track) -> Void)? = nil,
        onEditTrackWithList: ((Track, [Track]) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onTransferArtist: ((ArtistItem) -> Void)? = nil,
        onTransferTracks: (([Track]) -> Void)? = nil,
        onTransferTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedArtists = precomputedArtists
        self.showToolbar = showToolbar
        self.initialSelectedArtistName = initialSelectedArtistName
        self.onSelectTrack = onSelectTrack
        self.onEditTrack = onEditTrack
        self.onEditTrackWithList = onEditTrackWithList
        self.onTrimCutTrack = onTrimCutTrack
        self.onTransferArtist = onTransferArtist
        self.onTransferTracks = onTransferTracks
        self.onTransferTrack = onTransferTrack
        
        let initial = precomputedArtists ?? []
        let targetName = initialSelectedArtistName ?? initial.first?.name
        let initialActive = initial.first(where: { $0.name == targetName }) ?? initial.first
        self._cachedArtists = State(initialValue: initial)
        self._displayedArtists = State(initialValue: initial)
        self._selectedArtistName = State(initialValue: initialActive?.name ?? targetName)
        self._cachedActiveArtist = State(initialValue: initialActive)
        self._cachedFilteredAlbums = State(initialValue: initialActive?.albums ?? [])
        self._cachedHeroMetadata = State(initialValue: initialActive.map(Self.computeHeroMetadata) ?? "")
        self._cachedHeroQuality = State(initialValue: initialActive.map(Self.computeHeroQuality) ?? "")
        self._cachedHeroAvgBitrate = State(initialValue: initialActive.flatMap(Self.computeHeroAvgBitrate))
    }
    
    private var baseArtists: [ArtistItem] {
        if let pre = precomputedArtists { return pre }
        if !cachedArtists.isEmpty { return cachedArtists }
        return []
    }
    
    nonisolated public static func buildArtists(from tracks: [Track]) -> [ArtistItem] {
        var grouped: [String: [Track]] = [:]
        for track in tracks {
            let primary = track.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = primary.isEmpty ? "Unknown Artist" : primary
            grouped[key, default: []].append(track)
        }
        
        var list: [ArtistItem] = []
        for (artistName, artistTracks) in grouped {
            var albumGrouped: [String: [Track]] = [:]
            for track in artistTracks {
                let alb = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
                let albumKey = alb.isEmpty ? "Unknown Album" : alb
                albumGrouped[albumKey, default: []].append(track)
            }
            
            var albumItems: [AlbumItem] = []
            for (albumName, albTracks) in albumGrouped {
                let sortedTracks = albTracks.sorted {
                    let n0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    let n1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    if n0 != n1 && n0 > 0 && n1 > 0 {
                        return n0 < n1
                    }
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                let year = sortedTracks.first(where: { !$0.year.isEmpty })?.year ?? ""
                albumItems.append(AlbumItem(
                    name: albumName,
                    artist: artistName,
                    year: year,
                    trackCount: sortedTracks.count,
                    tracks: sortedTracks
                ))
            }
            
            list.append(ArtistItem(
                name: artistName,
                albumCount: albumItems.count,
                trackCount: artistTracks.count,
                albums: albumItems.sorted { $0.year > $1.year },
                tracks: artistTracks
            ))
        }
        
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - High-Performance Filter Pipeline (< 1ms execution, Isolated from Hover State)
    
    private func recomputeDisplayedArtists() {
        if !showToolbar, let pre = precomputedArtists {
            displayedArtists = pre
            if let sel = selectedArtistName {
                if !displayedArtists.contains(where: { $0.name == sel }) {
                    selectedArtistName = displayedArtists.first?.name
                }
            } else {
                selectedArtistName = displayedArtists.first?.name
            }
            recomputeActiveArtistConsole()
            return
        }
        let list = baseArtists
        if list.isEmpty {
            displayedArtists = []
            selectedArtistName = nil
            recomputeActiveArtistConsole()
            return
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if q.isEmpty {
            displayedArtists = list
        } else {
            displayedArtists = list.filter { art in
                // Fast path: match artist name first
                if art.name.localizedCaseInsensitiveContains(q) {
                    return true
                }
                // Secondary path: match album names or track titles
                return art.albums.contains(where: { $0.name.localizedCaseInsensitiveContains(q) })
                    || art.tracks.contains(where: { $0.title.localizedCaseInsensitiveContains(q) })
            }
        }
        
        // Ensure active selection remains valid
        if let sel = selectedArtistName {
            if !displayedArtists.contains(where: { $0.name == sel }) {
                selectedArtistName = displayedArtists.first?.name
            }
        } else {
            selectedArtistName = displayedArtists.first?.name
        }
        recomputeActiveArtistConsole()
    }
    
    private var activeArtist: ArtistItem? {
        cachedActiveArtist ?? displayedArtists.first
    }

    private func recomputeActiveArtistConsole() {
        let resolved: ArtistItem?
        if let name = selectedArtistName {
            resolved = displayedArtists.first(where: { $0.name == name }) ?? displayedArtists.first
        } else {
            resolved = displayedArtists.first
        }
        cachedActiveArtist = resolved
        if let art = resolved {
            cachedFilteredAlbums = Self.computeFilteredAlbums(for: art, filter: formatFilter)
            cachedHeroMetadata = Self.computeHeroMetadata(for: art)
            cachedHeroQuality = Self.computeHeroQuality(for: art)
            cachedHeroAvgBitrate = Self.computeHeroAvgBitrate(for: art)
        } else {
            cachedFilteredAlbums = []
            cachedHeroMetadata = ""
            cachedHeroQuality = ""
            cachedHeroAvgBitrate = nil
        }
    }

    private func selectTargetArtistIfNeeded(proxy: ScrollViewProxy? = nil) {
        guard let target = initialSelectedArtistName, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let list = baseArtists.isEmpty ? cachedArtists : baseArtists
        if let match = list.first(where: {
            $0.name.localizedCaseInsensitiveCompare(target) == .orderedSame
        }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.selectedArtistName = match.name
            }
            if let proxy = proxy {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(match.name, anchor: .center)
                    }
                }
            }
        }
    }
    
    private static func computeFilteredAlbums(for artist: ArtistItem, filter: String) -> [AlbumItem] {
        if filter == "ALL" {
            return artist.albums
        }
        return artist.albums.compactMap { alb in
            let matchingTracks = alb.tracks.filter { track in
                switch filter {
                case "HI-RES":
                    return track.bitsPerSample > 16 || track.sampleRate > 48000
                case "FLAC":
                    return track.format == "FLAC"
                case "MP3":
                    return track.format == "MP3"
                case "M4A":
                    return track.format == "M4A" || track.format == "AAC" || track.format == "ALAC"
                default:
                    return true
                }
            }
            if matchingTracks.isEmpty { return nil }
            return AlbumItem(
                name: alb.name,
                artist: alb.artist,
                year: alb.year,
                trackCount: matchingTracks.count,
                tracks: matchingTracks
            )
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if showToolbar {
                // Full-Width Top Navigation & Action Toolbar
                topToolbarContainer
                
                // Single Straight Line Divider under Segmented Tabs (uninterrupted across full window)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.8)
            }
            
            // Split Content Area: Left Master List & Right Discography Console
            HStack(spacing: 0) {
                // Left Column: Artist Master List
                let currentActiveName = activeArtist?.name
                VStack(spacing: 0) {
                    if displayedArtists.isEmpty {
                        leftEmptyStateView
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    ForEach(displayedArtists) { art in
                                        let isSelected = currentActiveName == art.name
                                        ArtistListRowView(
                                            artist: art,
                                            isSelected: isSelected,
                                            onSelect: {
                                                selectedArtistName = art.name
                                            },
                                            onPlayAll: {
                                                if let first = art.tracks.first {
                                                    player.play(track: first, in: art.tracks)
                                                }
                                            },
                                            onRefreshPhoto: {
                                                ArtistArtCache.shared.refresh(artistName: art.name, representativeTrack: art.representativeTrack)
                                            },
                                            onCustomPhoto: {
                                                promptCustomPhoto(for: art.name)
                                            },
                                            onTransferArtist: onTransferArtist != nil ? { onTransferArtist?(art) } : nil,
                                            onFetchLyrics: {
                                                selectedArtistName = art.name
                                                showBatchLyricsSheet = true
                                            }
                                        )
                                        .equatable()
                                        .id(art.name)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                                .padding(.bottom, 88)
                            }
                            .onAppear {
                                selectTargetArtistIfNeeded(proxy: proxy)
                            }
                            .onChange(of: initialSelectedArtistName) { _, _ in
                                selectTargetArtistIfNeeded(proxy: proxy)
                            }
                        }
                    }
                }
                .frame(width: isCompactMasterColumn ? 160 : 185)
                .background(Color.clear)
                
                // Vertical Hairline Divider between Master List & Detail Console
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 0.8)
                
                // Right Detail Column: Artist Discography Console
                if let artist = activeArtist {
                    let currentPlayingId = player.currentTrack?.id
                    let isPlayingNow = player.isPlaying
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            // Hero Banner
                            artistHeroBanner(for: artist)
                            
                            // Releases Section Header
                            HStack(spacing: 8) {
                                Text("Releases")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("(\(cachedFilteredAlbums.count))")
                                    .font(WalkmanFont.calloutMedium)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Spacer()
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                            
                            // Discography Albums
                            if cachedFilteredAlbums.isEmpty {
                                discographyEmptyStateView
                            } else {
                                ForEach(cachedFilteredAlbums) { alb in
                                    artistAlbumSection(
                                        album: alb,
                                        artist: artist,
                                        currentPlayingId: currentPlayingId,
                                        isPlayingNow: isPlayingNow
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .padding(.bottom, 88)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        GeometryReader { geo in
                            let tier = ArtistDetailWidthTier(width: geo.size.width)
                            Color.clear
                                .onAppear {
                                    if detailWidthTier != tier { detailWidthTier = tier }
                                }
                                .onChange(of: tier) { _, newTier in
                                    detailWidthTier = newTier
                                }
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.mic")
                            .font(.system(size: 36))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                        Text("Select an artist from the list")
                            .font(WalkmanFont.title3)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(
                GeometryReader { geo in
                    let compact = geo.size.width < 740
                    Color.clear
                        .onAppear {
                            if isCompactMasterColumn != compact { isCompactMasterColumn = compact }
                        }
                        .onChange(of: compact) { _, newCompact in
                            isCompactMasterColumn = newCompact
                        }
                }
            )
        }
        .onAppear {
            if cachedArtists.isEmpty && precomputedArtists == nil && !tracks.isEmpty {
                cachedArtists = Self.buildArtists(from: tracks)
                recomputeDisplayedArtists()
            } else if precomputedArtists != nil {
                recomputeDisplayedArtists()
            } else {
                recomputeActiveArtistConsole()
            }
        }
        .onChange(of: precomputedArtists) { _, newPrecomputed in
            if let newPrecomputed = newPrecomputed {
                cachedArtists = newPrecomputed
                recomputeDisplayedArtists()
                if let sel = selectedArtistName, !newPrecomputed.contains(where: { $0.name == sel }) {
                    selectedArtistName = newPrecomputed.first?.name
                } else if selectedArtistName == nil {
                    selectedArtistName = newPrecomputed.first?.name
                }
            } else {
                recomputeDisplayedArtists()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackMetadataDidUpdate)) { _ in
            if precomputedArtists == nil && !tracks.isEmpty {
                cachedArtists = Self.buildArtists(from: tracks)
            }
            recomputeDisplayedArtists()
        }
        .onChange(of: tracks) { _, newTracks in
            if precomputedArtists != nil {
                recomputeDisplayedArtists()
                return
            }
            Task.detached(priority: .userInitiated) {
                let built = Self.buildArtists(from: newTracks)
                await MainActor.run {
                    self.cachedArtists = built
                    self.recomputeDisplayedArtists()
                }
            }
        }
        .onChange(of: searchQuery) { _, _ in
            recomputeDisplayedArtists()
        }
        .onChange(of: selectedArtistName) { _, _ in
            recomputeActiveArtistConsole()
        }
        .onChange(of: formatFilter) { _, _ in
            recomputeActiveArtistConsole()
        }
        .onChange(of: cachedArtists) { _, _ in
            recomputeDisplayedArtists()
        }
        .sheet(isPresented: $showBatchLyricsSheet) {
            BatchLyricsGeneratorSheet(
                allTracks: tracks,
                selectedTracks: activeArtist?.tracks ?? [],
                tabContext: .artists(
                    selectedArtistName: activeArtist?.name,
                    artistTrackCount: activeArtist?.tracks.count ?? 0
                ),
                precomputedArtists: cachedArtists.isEmpty ? nil : cachedArtists,
                onDismiss: {
                    showBatchLyricsSheet = false
                }
            )
        }
    }
    
    // -------------------------------------------------------------------------
    // LEFT COLUMN SUBVIEWS (SEARCH CAPSULE & LIST)
    // -------------------------------------------------------------------------
    
    private var searchFieldView: some View {
        ExpandableLiquidGlassSearchBar(
            text: $searchQuery,
            isExpanded: $isSearchExpanded,
            placeholder: "Filter artists...",
            expandedWidth: 260,
            helpText: "Filter artists"
        )
    }
    
    private var leftEmptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.slash")
                .font(.system(size: 26))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("No Artists Found")
                .font(WalkmanFont.calloutMedium)
                .foregroundStyle(WalkmanTheme.silverMuted)
            if !searchQuery.isEmpty {
                Button("Clear Search") {
                    searchQuery = ""
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 10))
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // -------------------------------------------------------------------------
    // TOP NAVIGATION TOOLBAR (LIQUID GLASS + VIEWTHATFITS FOR SMALL WINDOWS)
    // -------------------------------------------------------------------------
    
    private var topToolbarContainer: some View {
        ViewThatFits(in: .horizontal) {
            wideTopToolbarLayout(isCompactSegmented: false, minWidth: 740)
            wideTopToolbarLayout(isCompactSegmented: true, minWidth: 680)
            dropdownTopToolbarLayout
            compactTopToolbarLayout
            narrowTopToolbarLayout
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: isSearchExpanded)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.clear)
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
        .disabled((displayedArtists.isEmpty && activeArtist == nil) || isPreparingLyricsSheet)
        .help("LRC Fetcher: Fetch and sync .LRC lyrics for artists")
    }
    
    private func wideTopToolbarLayout(isCompactSegmented: Bool, minWidth: CGFloat) -> some View {
        HStack(spacing: isCompactSegmented ? 6 : 8) {
            searchFieldView
                .fixedSize(horizontal: true, vertical: false)
            
            artistFormatSegmentedBar(isCompact: isCompactSegmented)
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            if !isSearchExpanded {
                HStack(spacing: isCompactSegmented ? 6 : 8) {
                    if let artist = activeArtist {
                        artistActionButtons(for: artist)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    batchLyricsButton
                        .fixedSize(horizontal: true, vertical: false)
                    
                    artistCountPill
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
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
        .frame(minWidth: minWidth)
    }
    
    private var dropdownTopToolbarLayout: some View {
        HStack(spacing: 6) {
            searchFieldView
                .fixedSize(horizontal: true, vertical: false)
            
            artistFormatDropdownMenu
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            if !isSearchExpanded {
                HStack(spacing: 6) {
                    if let artist = activeArtist {
                        artistActionButtons(for: artist)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    batchLyricsButton
                        .fixedSize(horizontal: true, vertical: false)
                    
                    artistCountPill
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
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
    
    private var compactTopToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                
                Spacer(minLength: 4)
                
                if !isSearchExpanded {
                    HStack(spacing: 8) {
                        if let artist = activeArtist {
                            artistActionButtons(for: artist)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        
                        batchLyricsButton
                        
                        artistCountPill
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
                artistFormatSegmentedBar(isCompact: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private var narrowTopToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                
                Spacer(minLength: 4)
                
                if !isSearchExpanded {
                    HStack(spacing: 8) {
                        batchLyricsButton
                        
                        artistCountPill
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
                if let artist = activeArtist {
                    HStack(spacing: 8) {
                        artistActionButtons(for: artist)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        )
                    )
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                artistFormatSegmentedBar(isCompact: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private func artistFormatSegmentedBar(isCompact: Bool = false) -> some View {
        ArtistFormatSegmentedBarView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            isCompact: isCompact,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private var artistFormatDropdownMenu: some View {
        ArtistFormatDropdownMenuView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private func artistActionButtons(for artist: ArtistItem) -> some View {
        let isPlayingArtist = player.isPlaying && artist.tracks.contains(where: { $0.id == player.currentTrack?.id })
        
        return HStack(spacing: 7) {
            Button(action: {
                if let first = artist.tracks.first {
                    if isPlayingArtist {
                        player.pause()
                    } else {
                        player.play(track: first, in: artist.tracks)
                    }
                }
            }) {
                Image(systemName: isPlayingArtist ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .disabled(artist.tracks.isEmpty)
            .help(isPlayingArtist ? "Pause playback" : "Play all tracks by \(artist.name)")
            
            Button(action: {
                if let randomTrack = artist.tracks.randomElement() {
                    let shuffled = artist.tracks.shuffled()
                    player.play(track: randomTrack, in: shuffled)
                }
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .disabled(artist.tracks.isEmpty)
            .help("Shuffle tracks by \(artist.name)")
        }
    }
    
    private var artistCountPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("\(displayedArtists.count.formatted())")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .help(displayedArtists.count == 1 ? "1 Artist" : "\(displayedArtists.count.formatted()) Artists")
        .padding(.horizontal, 11)
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
    
    // -------------------------------------------------------------------------
    // ARTIST METADATA COMPUTATION HELPERS
    // -------------------------------------------------------------------------
    
    private static func computeArtistGenre(for artist: ArtistItem) -> String? {
        let genres = artist.tracks.compactMap { tr -> String? in
            let g = tr.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            return g.isEmpty ? nil : g
        }
        guard !genres.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for g in genres { counts[g, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? genres.first
    }
    
    private static func computeArtistYearsRange(for artist: ArtistItem) -> String? {
        let years = artist.tracks.compactMap { tr -> Int? in
            let clean = tr.year.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(clean)
        }.filter { $0 > 1900 && $0 < 2100 }
        
        guard let minYear = years.min(), let maxYear = years.max() else { return nil }
        if minYear == maxYear {
            return "\(minYear)"
        } else {
            return "\(minYear) – \(maxYear)"
        }
    }
    
    private static func computeArtistDuration(for artist: ArtistItem) -> String {
        let total = artist.tracks.reduce(0.0) { $0 + $1.durationSeconds }
        let count = artist.trackCount
        let songsLabel = "\(count) \(count == 1 ? "Song" : "Songs")"
        if total <= 0 { return songsLabel }
        let hours = Int(total) / 3600
        let mins = (Int(total) % 3600) / 60
        let secs = Int(total) % 60
        if hours > 0 {
            return "\(songsLabel), \(hours) hr \(mins) min"
        } else if mins > 0 {
            return "\(songsLabel), \(mins) min \(secs) sec"
        } else {
            return "\(songsLabel), \(secs) sec"
        }
    }
    
    private static func computeArtistTotalSize(for artist: ArtistItem) -> String {
        let bytes = artist.tracks.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if bytes <= 0 { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private static func computeHeroQuality(for artist: ArtistItem) -> String {
        let maxBits = artist.tracks.map(\.bitsPerSample).max() ?? 0
        let maxSampleRate = artist.tracks.map(\.sampleRate).max() ?? 0
        let formats = artist.tracks.map(\.format)
        let primaryFormat = formats.first(where: { $0 == "FLAC" || $0 == "DSD" || $0 == "ALAC" }) ?? (formats.first ?? "AUDIO")
        
        if maxBits > 0 && maxSampleRate > 0 {
            let khz = Double(maxSampleRate) / 1000.0
            let khzStr = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            return "\(primaryFormat) • \(maxBits)-bit / \(khzStr) kHz"
        } else if maxSampleRate > 0 {
            let khz = Double(maxSampleRate) / 1000.0
            let khzStr = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            return "\(primaryFormat) • \(khzStr) kHz"
        }
        return primaryFormat
    }
    
    private static func computeHeroAvgBitrate(for artist: ArtistItem) -> String? {
        let bitrates = artist.tracks.map(\.bitrateKbps).filter { $0 > 0 }
        guard !bitrates.isEmpty else { return nil }
        let avg = bitrates.reduce(0, +) / bitrates.count
        return "\(avg) kbps"
    }
    
    // -------------------------------------------------------------------------
    // ARTIST HERO BANNER & ALBUM SECTIONS
    // -------------------------------------------------------------------------
    
    private static func computeHeroMetadata(for artist: ArtistItem) -> String {
        var components: [String] = []
        if let genre = computeArtistGenre(for: artist) {
            components.append(genre)
        }
        if let years = computeArtistYearsRange(for: artist) {
            components.append(years)
        }
        components.append("\(artist.albumCount) \(artist.albumCount == 1 ? "Album" : "Albums")")
        components.append(computeArtistDuration(for: artist))
        let sizeStr = computeArtistTotalSize(for: artist)
        if !sizeStr.isEmpty {
            components.append(sizeStr)
        }
        return components.joined(separator: " • ")
    }
    
    private var artistHiResBadge: some View {
        HStack(spacing: 4.5) {
            Image(systemName: "waveform")
                .font(.system(size: 9.5, weight: .bold))
            Text("Hi-Res Audio")
                .font(WalkmanFont.badge)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(WalkmanTheme.hiResGold.opacity(0.92))
        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func artistQualityBadge(for artist: ArtistItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(artist.isHiRes ? WalkmanTheme.hiResGoldLight : WalkmanTheme.silverLight)
            Text(cachedHeroQuality)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var artistBitrateBadge: some View {
        Group {
            if let avgBitrate = cachedHeroAvgBitrate {
                Text("~\(avgBitrate)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    
    @ViewBuilder
    private func artistSpecificationBadges(for artist: ArtistItem) -> some View {
        Group {
            if detailWidthTier == .extraWide {
                HStack(spacing: 7) {
                    if artist.isHiRes {
                        artistHiResBadge
                    }
                    artistQualityBadge(for: artist)
                    artistBitrateBadge
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        if artist.isHiRes {
                            artistHiResBadge
                        }
                        artistQualityBadge(for: artist)
                    }
                    artistBitrateBadge
                }
            }
        }
        .padding(.top, 4)
    }
    
    private func artistHeroBanner(for artist: ArtistItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Prominent Circular Artist Avatar (96x96 pt)
            artistCoverArtView(for: artist)
            
            // Prominent Metadata Details & Action Controls
            VStack(alignment: .leading, spacing: 6) {
                // 1. Kicker
                Text("ARTIST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .tracking(1.4)
                
                // 2. Big Prominent Artist Name (28pt Bold)
                Text(artist.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 3. Primary Metadata Line (Genre • Years Active • Albums Count • Duration • Size)
                Text(cachedHeroMetadata)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                
                // 4. Specification Badges (Hi-Res Audio Gold Badge, Audio Specs, Bitrate)
                artistSpecificationBadges(for: artist)
                
                Spacer(minLength: 8)
                
                // 5. Action Buttons Bar
                artistActionButtonsView(for: artist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
    
    private func artistCoverArtView(for artist: ArtistItem) -> some View {
        ArtistCoverAvatarButton(
            artist: artist,
            onChooseCustom: { promptCustomPhoto(for: artist.name) },
            onRefresh: { ArtistArtCache.shared.refresh(artistName: artist.name, representativeTrack: artist.representativeTrack) },
            onExportArtwork: { track in ArtworkExportService.exportArtwork(for: track) }
        )
    }
    
    @ViewBuilder
    private func artistActionButtonsView(for artist: ArtistItem) -> some View {
        Group {
            switch detailWidthTier {
            case .extraWide:
                HStack(spacing: 8) {
                    artistPlayButton(for: artist)
                    artistShuffleButton(for: artist)
                    artistChangePhotoButton(for: artist)
                    artistMoreMenuButton(for: artist)
                }
            case .wide, .compact:
                HStack(spacing: 8) {
                    artistPlayButton(for: artist)
                    artistShuffleButton(for: artist)
                    artistChangePhotoCircularButton(for: artist)
                    artistMoreMenuButton(for: artist)
                }
            case .minimal:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        artistPlayButton(for: artist)
                        artistShuffleButton(for: artist)
                    }
                    HStack(spacing: 8) {
                        artistChangePhotoCircularButton(for: artist)
                        artistRefreshPhotoCircularButton(for: artist)
                        artistMoreMenuButton(for: artist)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
    
    private func artistPlayButton(for artist: ArtistItem) -> some View {
        Button(action: {
            if let first = artist.tracks.first {
                player.play(track: first, in: artist.tracks)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Play All")
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
        .help("Play all songs by this artist from the beginning")
    }
    
    private func artistShuffleButton(for artist: ArtistItem) -> some View {
        Button(action: {
            if let randomTrack = artist.tracks.randomElement() {
                let shuffled = artist.tracks.shuffled()
                player.play(track: randomTrack, in: shuffled)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "shuffle")
                    .font(.system(size: 11, weight: .bold))
                Text("Shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Shuffle all tracks by this artist")
    }
    
    private func artistChangePhotoButton(for artist: ArtistItem) -> some View {
        Button(action: {
            promptCustomPhoto(for: artist.name)
        }) {
            HStack(spacing: 5.5) {
                Image(systemName: "camera")
                    .font(.system(size: 11, weight: .semibold))
                Text("Change Photo")
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
        .help("Select a custom photo for this artist")
    }
    
    private func artistRefreshPhotoButton(for artist: ArtistItem) -> some View {
        Button(action: {
            ArtistArtCache.shared.refresh(artistName: artist.name, representativeTrack: artist.representativeTrack)
        }) {
            HStack(spacing: 5.5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("Refresh")
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
        .help("Refresh artist photo from track artwork")
    }
    
    private func artistExportArtworkButton(for track: Track) -> some View {
        Button(action: {
            ArtworkExportService.exportArtwork(for: track)
        }) {
            HStack(spacing: 5.5) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("Export Artwork")
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
        .help("Export cover artwork to Mac")
    }
    
    private func artistChangePhotoCircularButton(for artist: ArtistItem) -> some View {
        Button(action: {
            promptCustomPhoto(for: artist.name)
        }) {
            Image(systemName: "camera")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Select a custom photo for this artist")
    }
    
    private func artistRefreshPhotoCircularButton(for artist: ArtistItem) -> some View {
        Button(action: {
            ArtistArtCache.shared.refresh(artistName: artist.name, representativeTrack: artist.representativeTrack)
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
        .fixedSize(horizontal: true, vertical: false)
        .help("Refresh artist photo from track artwork")
    }
    
    private func artistMoreMenuButton(for artist: ArtistItem) -> some View {
        Menu {
            Button {
                promptCustomPhoto(for: artist.name)
            } label: {
                Label("Choose Custom Photo...", systemImage: "camera")
            }
            
            Button {
                ArtistArtCache.shared.refresh(artistName: artist.name, representativeTrack: artist.representativeTrack)
            } label: {
                Label("Refresh Artist Photo", systemImage: "arrow.clockwise")
            }

            Button {
                selectedArtistName = artist.name
                showBatchLyricsSheet = true
            } label: {
                Label("Fetch .LRC Lyrics for Artist...", systemImage: "quote.bubble")
            }
            
            if let rep = artist.representativeTrack, rep.hasArtwork {
                Button {
                    ArtworkExportService.exportArtwork(for: rep)
                } label: {
                    Label("Export Artist Artwork to Mac...", systemImage: "square.and.arrow.down")
                }
            }
            
            Divider()
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(artist.name, forType: .string)
            } label: {
                Label("Copy Artist Name", systemImage: "doc.on.doc")
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
        .help("More artist options")
    }
    
    private var discographyEmptyStateView: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 30)
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("No releases match the selected format filter.")
                .font(WalkmanFont.callout)
                .foregroundStyle(WalkmanTheme.silverMuted)
            Button("Show All Formats") {
                formatFilter = "ALL"
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 10))
            .padding(.top, 2)
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func albumSummaryString(for album: AlbumItem) -> String {
        var parts: [String] = []
        if !album.year.isEmpty {
            parts.append(album.year)
        }
        parts.append("\(album.trackCount) \(album.trackCount == 1 ? "track" : "tracks")")
        let albDuration = album.tracks.reduce(0.0) { $0 + $1.durationSeconds }
        if albDuration > 0 {
            let mins = Int(albDuration) / 60
            parts.append("\(mins) min")
        }
        parts.append(album.primaryFormat)
        return parts.joined(separator: " • ")
    }
    
    private func artistAlbumSection(
        album: AlbumItem,
        artist: ArtistItem,
        currentPlayingId: String?,
        isPlayingNow: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Album Header Row
            HStack(spacing: 12) {
                if let rep = album.representativeTrack {
                    TrackCoverThumbnail(track: rep, size: 52)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(album.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if album.isHiRes {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(WalkmanTheme.hiResGold.opacity(0.92))
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                                .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    Text(albumSummaryString(for: album))
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 8)
                
                if detailWidthTier == .extraWide || detailWidthTier == .wide {
                    Button(action: {
                        if let first = album.tracks.first {
                            player.play(track: first, in: album.tracks)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Play Album")
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5.5)
                        .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .subtle, cornerRadius: 12))
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Button(action: {
                        if let first = album.tracks.first {
                            player.play(track: first, in: album.tracks)
                        }
                    }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .subtle, cornerRadius: 14))
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Play Album")
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let onTransfer = onTransferTracks {
                    Button {
                        onTransfer(album.tracks)
                    } label: {
                        Label("Transfer Album to Walkman", systemImage: "arrow.right.circle.fill")
                    }
                    Divider()
                }
                Button("Play Album") {
                    if let first = album.tracks.first {
                        player.play(track: first, in: album.tracks)
                    }
                }
                Divider()
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
            
            // Album Tracks Card Container
            LazyVStack(spacing: 1.5) {
                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                    ArtistTrackRowView(
                        index: index + 1,
                        track: track,
                        artistName: artist.name,
                        albumTracks: album.tracks,
                        isPlayingThis: isPlayingNow && (currentPlayingId == track.id),
                        widthTier: detailWidthTier,
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
                        onTransferTrack: onTransferTrack != nil ? { onTransferTrack?(track) } : nil
                    )
                    .equatable()
                }
            }
            .padding(6)
            .background(WalkmanTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
            )
        }
        .padding(.vertical, 4)
    }
    
    private func promptCustomPhoto(for artistName: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.prompt = "Choose Photo"
        panel.message = "Select an artist photo for \(artistName)"
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            ArtistArtCache.shared.setCustomImage(img, for: artistName)
        }
    }
}

// -----------------------------------------------------------------------------
// ARTIST COVER AVATAR BUTTON (PROMINENT CIRCULAR WITH TACTILE SPRING KINETICS)
// -----------------------------------------------------------------------------
private struct ArtistCoverAvatarButton: View {
    let artist: ArtistItem
    let onChooseCustom: () -> Void
    let onRefresh: () -> Void
    let onExportArtwork: ((Track) -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onChooseCustom) {
            ArtistAvatarView(
                artistName: artist.name,
                representativeTrack: artist.representativeTrack,
                size: 96,
                isSelected: false
            )
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.28 : 0.14), lineWidth: 0.85)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.60 : 0.45), radius: isHovered ? 14 : 10, x: 0, y: isHovered ? 7 : 5)
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .fixedSize()
        .onHover { hovering in
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
        .help("Click to change artist photo, or right-click for options")
        .contextMenu {
            Button("Refresh Artist Photo", action: onRefresh)
            Button("Choose Custom Photo...", action: onChooseCustom)
            if let rep = artist.representativeTrack, rep.hasArtwork, let export = onExportArtwork {
                Divider()
                Button {
                    export(rep)
                } label: {
                    Label("Export Artwork to Mac...", systemImage: "square.and.arrow.down")
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------
// ARTIST LIST ROW VIEW (TACTILE HOVER & SELECTION)
// -----------------------------------------------------------------------------
private struct ArtistListRowView: View, Equatable {
    let artist: ArtistItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlayAll: () -> Void
    let onRefreshPhoto: () -> Void
    let onCustomPhoto: () -> Void
    var onTransferArtist: (() -> Void)? = nil
    var onFetchLyrics: (() -> Void)? = nil
    
    @State private var isHovered = false

    static func == (lhs: ArtistListRowView, rhs: ArtistListRowView) -> Bool {
        lhs.artist.name == rhs.artist.name &&
        lhs.artist.albumCount == rhs.artist.albumCount &&
        lhs.artist.trackCount == rhs.artist.trackCount &&
        lhs.isSelected == rhs.isSelected
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Circular Artist Photo Avatar
                ArtistAvatarView(
                    artistName: artist.name,
                    representativeTrack: artist.representativeTrack,
                    size: 32,
                    isSelected: isSelected
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(isSelected ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : WalkmanTheme.silverLight))
                        .lineLimit(1)
                    
                    Text("\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums") • \(artist.trackCount) tracks")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(isSelected ? WalkmanTheme.silverLight.opacity(0.85) : WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        Color.white.opacity(0.12)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.22), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5)
                            Spacer(minLength: 0)
                        }
                    } else if isHovered {
                        Color.white.opacity(0.05)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ?
                            Color.white.opacity(0.24) :
                            (isHovered ? Color.white.opacity(0.08) : Color.clear),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(isHovered && !isSelected ? 1.015 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            if let onTransfer = onTransferArtist {
                Button {
                    onTransfer()
                } label: {
                    Label("Transfer Artist to Walkman", systemImage: "arrow.right.circle.fill")
                }
                Divider()
            }
            Button("Play All (\(artist.trackCount) tracks)") {
                onPlayAll()
            }
            if let onFetchLyrics = onFetchLyrics {
                Button {
                    onFetchLyrics()
                } label: {
                    Label("Fetch .LRC Lyrics for Artist...", systemImage: "quote.bubble")
                }
            }
            Divider()
            Button("Refresh Artist Photo") {
                onRefreshPhoto()
            }
            Button("Choose Custom Photo...") {
                onCustomPhoto()
            }
        }
    }
}

// -----------------------------------------------------------------------------
// ARTIST FORMAT DROPDOWN MENU VIEW (COMPACT LIQUID GLASS DROPDOWN)
// -----------------------------------------------------------------------------
private struct ArtistFormatDropdownMenuView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    let onSelectFilter: (String) -> Void
    
    @State private var isHovered = false
    
    private var activeOption: FilterOption? {
        options.first(where: { $0.id == selectedFilter })
    }
    
    var body: some View {
        Menu {
            ForEach(options) { opt in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedFilter = opt.id
                    }
                    onSelectFilter(opt.id)
                } label: {
                    HStack {
                        if selectedFilter == opt.id {
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
        } label: {
            LiquidGlassDropdownLabel(height: 38, isHovered: isHovered, isHiRes: activeOption?.isHiRes == true) {
                HStack(spacing: 7) {
                    if let icon = activeOption?.icon {
                        Image(systemName: icon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(activeOption?.isHiRes == true ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
                    }
                    
                    Text(activeOption?.title ?? selectedFilter)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeOption?.isHiRes == true ? WalkmanTheme.hiResGold : Color.white)
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

// -----------------------------------------------------------------------------
// ARTIST FORMAT SEGMENTED BAR (MATCHED GEOMETRY SLIDING LIQUID GLASS LENS)
// -----------------------------------------------------------------------------
private struct ArtistFormatSegmentedBarView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    var isCompact: Bool = false
    let onSelectFilter: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(options) { opt in
                ArtistFormatTabPillView(
                    option: opt,
                    isSelected: activeHighlightId == opt.id,
                    isCompact: isCompact,
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
// ARTIST FORMAT TAB PILL VIEW (ROUND LIQUID GLASS CLICK BOX WITH HOVER)
// -----------------------------------------------------------------------------
private struct ArtistFormatTabPillView: View {
    let option: FilterOption
    let isSelected: Bool
    var isCompact: Bool = false
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: isCompact ? 4.5 : 5.5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                }
                Text(option.title)
                    .font(.system(size: isCompact ? 12 : 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, isCompact ? 10 : 14)
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
                        ActiveArtistPillBackground(isHiRes: option.isHiRes, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeArtistFormatHighlight", in: namespace)
                    } else if isHovered {
                        // Liquid Glass Hover Pill (Round frosted glass box)
                        HoverArtistPillBackground()
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

private struct ActiveArtistPillBackground: View {
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

private struct HoverArtistPillBackground: View {
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
// ARTIST TRACK ROW VIEW (TACTILE HOVER & AUDIO STATE)
// -----------------------------------------------------------------------------
private struct ArtistTrackRowView: View, Equatable {
    let index: Int
    let track: Track
    let artistName: String
    let albumTracks: [Track]
    let isPlayingThis: Bool
    let widthTier: ArtistDetailWidthTier
    let onSelect: () -> Void
    let onPlayToggle: () -> Void
    var onEdit: (() -> Void)? = nil
    var onTrimCut: (() -> Void)? = nil
    var onTransferTrack: (() -> Void)? = nil
    
    @State private var isHovered = false

    static func == (lhs: ArtistTrackRowView, rhs: ArtistTrackRowView) -> Bool {
        lhs.index == rhs.index &&
        lhs.track == rhs.track &&
        lhs.artistName == rhs.artistName &&
        lhs.isPlayingThis == rhs.isPlayingThis &&
        lhs.widthTier == rhs.widthTier
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private var hiResBadgeView: some View {
        Text("Hi-Res")
            .font(WalkmanFont.badge)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(WalkmanTheme.hiResGold.opacity(0.18))
            .foregroundStyle(WalkmanTheme.hiResGold)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.6)
            )
            .fixedSize()
    }
    
    private var durationView: some View {
        Text(formatDuration(track.durationSeconds))
            .font(WalkmanFont.mono)
            .foregroundStyle(WalkmanTheme.silverMuted)
            .frame(width: 44, alignment: .trailing)
            .fixedSize()
    }
    
    var body: some View {
        let isTrackHiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
        
        HStack(spacing: 8) {
            // Track Number or Play/Pause Indicator
            ZStack {
                if isHovered || isPlayingThis {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                } else {
                    Text(track.trackNum.isEmpty ? "\(index)" : track.trackNum)
                        .font(WalkmanFont.mono)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
            .frame(width: 20, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : (isHovered ? Color.white : WalkmanTheme.silverLight))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if let feat = track.featuredDisplayString(primaryArtist: artistName) {
                    HStack(spacing: 4) {
                        Text("feat.")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                        Text(feat)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 6)
            
            switch widthTier {
            case .extraWide, .wide:
                HStack(spacing: 6) {
                    if isTrackHiRes {
                        hiResBadgeView
                    }
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    durationView
                }
            case .compact:
                HStack(spacing: 6) {
                    if isTrackHiRes {
                        hiResBadgeView
                    } else {
                        Text(track.format)
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    durationView
                }
            case .minimal:
                durationView
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isPlayingThis ?
                        WalkmanTheme.cardHover :
                        (isHovered ? Color.white.opacity(0.04) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button(isPlayingThis ? "Pause" : "Play Track") {
                onPlayToggle()
            }
            Divider()
            if let onTransfer = onTransferTrack {
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
        }
    }
}
