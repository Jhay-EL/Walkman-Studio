import SwiftUI
import AppKit

public enum HiResViewMode: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case albums = "Albums"
    case artists = "Artists"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .tracks: return "music.note.list"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        }
    }
}

public enum HiResTrackSortOption: String, CaseIterable, Identifiable {
    case defaultOrder = "Default"
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case highestQuality = "Highest Quality"
    case recentlyAdded = "Recently Added"
    
    public var id: String { rawValue }
}

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

public struct HiResAudioView: View {
    let tracks: [Track]
    let precomputedAlbums: [AlbumItem]?
    let precomputedArtists: [ArtistItem]?
    let onSelectTrack: (Track) -> Void
    var onEditAlbum: ((AlbumItem) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    var onDeleteAlbum: ((AlbumItem) -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var viewMode: HiResViewMode = .tracks
    @State private var trackSortOption: HiResTrackSortOption = .defaultOrder
    @State private var albumSortOption: AlbumSortOption = .recentlyAdded
    @State private var searchQuery: String = ""
    @State private var formatFilter: String = "ALL"
    @State private var baseHiResTracks: [Track] = []
    @State private var displayedTracks: [Track] = []
    @State private var displayedTrackIds: Set<String> = []
    @State private var displayedAlbums: [AlbumItem] = []
    @State private var displayedArtists: [ArtistItem] = []
    @State private var albumCount: Int = 0
    @State private var artistCount: Int = 0
    
    private let formatFilterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Hi-Res", icon: "waveform", isHiRes: true),
        FilterOption(id: "STUDIO24", title: "24-Bit Masters", icon: "sparkles", isHiRes: true),
        FilterOption(id: "KHZ96", title: "96kHz+ Ultra", icon: "dial.high.fill", isHiRes: true),
        FilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
        FilterOption(id: "DSD", title: "DSD / SACD", icon: nil, isHiRes: false)
    ]
    
    public init(
        tracks: [Track],
        precomputedAlbums: [AlbumItem]? = nil,
        precomputedArtists: [ArtistItem]? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditAlbum: ((AlbumItem) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil,
        onDeleteAlbum: ((AlbumItem) -> Void)? = nil,
        onDeleteTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedAlbums = precomputedAlbums
        self.precomputedArtists = precomputedArtists
        self.onSelectTrack = onSelectTrack
        self.onEditAlbum = onEditAlbum
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
        self.onDeleteAlbum = onDeleteAlbum
        self.onDeleteTrack = onDeleteTrack
        
        let hiRes = tracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
        self._baseHiResTracks = State(initialValue: hiRes)
        self._displayedTracks = State(initialValue: hiRes)
        self._displayedTrackIds = State(initialValue: Set(hiRes.map(\.id)))
        
        let hrAlbums = (precomputedAlbums ?? []).filter { $0.isHiRes }
        self._displayedAlbums = State(initialValue: hrAlbums)
        self._albumCount = State(initialValue: hrAlbums.count)
        
        let hrArtists = (precomputedArtists ?? []).filter { $0.isHiRes }
        self._displayedArtists = State(initialValue: hrArtists)
        self._artistCount = State(initialValue: hrArtists.count)
    }
    
    private static let cachedLogoImage: NSImage? = {
        if let bundleURL = Bundle.main.url(forResource: "hires_audio_logo", withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        if let bundleSvgURL = Bundle.main.url(forResource: "hires_audio_logo", withExtension: "svg"),
           let img = NSImage(contentsOf: bundleSvgURL) {
            return img
        }
        if let localImg = NSImage(contentsOfFile: "assets/hires_audio_logo.png") {
            return localImg
        }
        if let localSvg = NSImage(contentsOfFile: "assets/hires_audio_logo.svg") {
            return localSvg
        }
        return nil
    }()

    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - High-Performance Filter Pipeline (< 1ms execution, Isolated from Hover State)
    
    private func recomputePipeline() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasQuery = !q.isEmpty
        let isAll = formatFilter == "ALL"
        
        // 1. Filter and sort base tracks
        var filteredTracks = baseHiResTracks.filter { track in
            if hasQuery {
                let match = track.title.localizedCaseInsensitiveContains(q)
                    || track.artist.localizedCaseInsensitiveContains(q)
                    || track.album.localizedCaseInsensitiveContains(q)
                if !match { return false }
            }
            if !isAll {
                switch formatFilter {
                case "STUDIO24":
                    if track.bitsPerSample < 24 { return false }
                case "KHZ96":
                    if track.sampleRate < 96000 { return false }
                case "FLAC":
                    if track.format != "FLAC" { return false }
                case "DSD":
                    let fmt = track.format.uppercased()
                    if fmt != "DSD" && fmt != "DSF" && fmt != "DFF" { return false }
                default:
                    break
                }
            }
            return true
        }
        
        switch trackSortOption {
        case .defaultOrder:
            break
        case .title:
            filteredTracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            filteredTracks.sort {
                let r = $0.artist.localizedStandardCompare($1.artist)
                if r == .orderedSame {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return r == .orderedAscending
            }
        case .album:
            filteredTracks.sort {
                let r = $0.album.localizedStandardCompare($1.album)
                if r == .orderedSame {
                    let n0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    let n1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    if n0 != n1 && n0 > 0 && n1 > 0 { return n0 < n1 }
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return r == .orderedAscending
            }
        case .highestQuality:
            filteredTracks.sort {
                if $0.sampleRate != $1.sampleRate {
                    return $0.sampleRate > $1.sampleRate
                }
                if $0.bitsPerSample != $1.bitsPerSample {
                    return $0.bitsPerSample > $1.bitsPerSample
                }
                return $0.bitrateKbps > $1.bitrateKbps
            }
        case .recentlyAdded:
            filteredTracks.sort { $0.dateAdded > $1.dateAdded }
        }
        
        displayedTracks = filteredTracks
        displayedTrackIds = Set(filteredTracks.map(\.id))
        
        // 2. Compute Albums (Filter from precomputedAlbums if available, else build from filteredTracks)
        if let preAlbums = precomputedAlbums {
            let hrAlbums = preAlbums.filter { alb in
                guard alb.isHiRes else { return false }
                if hasQuery {
                    let match = alb.name.localizedCaseInsensitiveContains(q) || alb.artist.localizedCaseInsensitiveContains(q)
                    if !match { return false }
                }
                if !isAll {
                    let hasMatchingFormat = alb.tracks.contains { tr in
                        switch formatFilter {
                        case "STUDIO24": return tr.bitsPerSample >= 24
                        case "KHZ96": return tr.sampleRate >= 96000
                        case "FLAC": return tr.format == "FLAC"
                        case "DSD":
                            let fmt = tr.format.uppercased()
                            return fmt == "DSD" || fmt == "DSF" || fmt == "DFF"
                        default: return true
                        }
                    }
                    if !hasMatchingFormat { return false }
                }
                return true
            }
            
            var sortedAlbums = hrAlbums
            switch albumSortOption {
            case .recentlyAdded:
                sortedAlbums.sort {
                    if $0.latestDateAdded != $1.latestDateAdded { return $0.latestDateAdded > $1.latestDateAdded }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .nameAsc:
                sortedAlbums.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            case .nameDesc:
                sortedAlbums.sort { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
            case .artistAsc:
                sortedAlbums.sort {
                    let cmp = $0.artist.localizedStandardCompare($1.artist)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .yearDesc:
                sortedAlbums.sort {
                    let y0 = Int($0.year) ?? 0
                    let y1 = Int($1.year) ?? 0
                    if y0 != y1 { return y0 > y1 }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .yearAsc:
                sortedAlbums.sort {
                    let y0 = Int($0.year) ?? 0
                    let y1 = Int($1.year) ?? 0
                    if y0 != y1 { return y0 < y1 }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .trackCountDesc:
                sortedAlbums.sort {
                    if $0.trackCount != $1.trackCount { return $0.trackCount > $1.trackCount }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            displayedAlbums = sortedAlbums
            albumCount = sortedAlbums.count
        } else {
            let built = AlbumsView.buildAlbums(from: filteredTracks)
            displayedAlbums = built
            albumCount = built.count
        }
        
        // 3. Compute Artists (Filter from precomputedArtists if available, else build from filteredTracks)
        if let preArtists = precomputedArtists {
            let hrArtists = preArtists.filter { art in
                guard art.isHiRes else { return false }
                if hasQuery {
                    let match = art.name.localizedCaseInsensitiveContains(q)
                        || art.albums.contains(where: { $0.name.localizedCaseInsensitiveContains(q) })
                        || art.tracks.contains(where: { $0.title.localizedCaseInsensitiveContains(q) })
                    if !match { return false }
                }
                if !isAll {
                    let hasMatchingFormat = art.tracks.contains { tr in
                        switch formatFilter {
                        case "STUDIO24": return tr.bitsPerSample >= 24
                        case "KHZ96": return tr.sampleRate >= 96000
                        case "FLAC": return tr.format == "FLAC"
                        case "DSD":
                            let fmt = tr.format.uppercased()
                            return fmt == "DSD" || fmt == "DSF" || fmt == "DFF"
                        default: return true
                        }
                    }
                    if !hasMatchingFormat { return false }
                }
                return true
            }
            displayedArtists = hrArtists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            artistCount = hrArtists.count
        } else {
            let built = ArtistsView.buildArtists(from: filteredTracks)
            displayedArtists = built
            artistCount = built.count
        }
    }
    
    private var isPlayingFromHiResQueue: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && displayedTrackIds.contains(current.id)
    }
    
    private func togglePlaybackHiRes() {
        if isPlayingFromHiResQueue {
            player.pause()
        } else if let first = displayedTracks.first {
            player.play(track: first, in: displayedTracks)
        }
    }
    
    private func shufflePlaybackHiRes() {
        guard let randomTrack = displayedTracks.randomElement() else { return }
        let shuffled = displayedTracks.shuffled()
        player.play(track: randomTrack, in: shuffled)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Responsive Floating Toolbar
            toolbarContainer
            
            if displayedTracks.isEmpty {
                emptyStateView
            } else {
                ZStack {
                    tracksContentView
                        .opacity(viewMode == .tracks ? 1 : 0)
                        .allowsHitTesting(viewMode == .tracks)
                    
                    albumsContentView
                        .opacity(viewMode == .albums ? 1 : 0)
                        .allowsHitTesting(viewMode == .albums)
                    
                    artistsContentView
                        .opacity(viewMode == .artists ? 1 : 0)
                        .allowsHitTesting(viewMode == .artists)
                }
                .animation(.easeInOut(duration: 0.15), value: viewMode)
            }
        }
        .onAppear {
            if baseHiResTracks.isEmpty && !tracks.isEmpty {
                baseHiResTracks = tracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
            }
            recomputePipeline()
        }
        .onChange(of: tracks) { _, newTracks in
            baseHiResTracks = newTracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
            recomputePipeline()
        }
        .onChange(of: precomputedAlbums) { _, _ in
            recomputePipeline()
        }
        .onChange(of: precomputedArtists) { _, _ in
            recomputePipeline()
        }
        .onChange(of: searchQuery) { _, _ in
            recomputePipeline()
        }
        .onChange(of: formatFilter) { _, _ in
            recomputePipeline()
        }
        .onChange(of: trackSortOption) { _, _ in
            recomputePipeline()
        }
        .onChange(of: albumSortOption) { _, _ in
            recomputePipeline()
        }
    }
    
    private var tracksContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Studio Master Console Header Banner
                studioConsoleBanner
                
                // Hi-Res Tracks List
                let currentId = player.currentTrack?.id
                let isPlaying = player.isPlaying
                
                LazyVStack(spacing: 3) {
                    ForEach(displayedTracks) { track in
                        HiResTrackRowView(
                            track: track,
                            isPlayingThis: isPlaying && (currentId == track.id),
                            onSelect: {
                                onSelectTrack(track)
                            },
                            onPlayToggle: {
                                let isCurrent = currentId == track.id
                                if isCurrent && isPlaying {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: displayedTracks)
                                }
                            },
                            onEdit: {
                                onEditTrack?(track)
                            },
                            onTrimCut: {
                                onTrimCutTrack?(track)
                            },
                            onDelete: {
                                onDeleteTrack?(track)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
    }
    
    private var albumsContentView: some View {
        AlbumsView(
            tracks: displayedTracks,
            precomputedAlbums: displayedAlbums,
            showToolbar: false,
            externalSortOption: albumSortOption,
            onSelectTrack: onSelectTrack,
            onEditAlbum: onEditAlbum,
            onEditTrack: onEditTrack,
            onTrimCutTrack: onTrimCutTrack,
            onDeleteAlbum: onDeleteAlbum,
            onDeleteTrack: onDeleteTrack
        )
    }
    
    private var artistsContentView: some View {
        ArtistsView(
            tracks: displayedTracks,
            precomputedArtists: displayedArtists,
            showToolbar: false,
            onSelectTrack: onSelectTrack,
            onEditTrack: onEditTrack,
            onTrimCutTrack: onTrimCutTrack
        )
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
                .frame(minWidth: 110, maxWidth: 210)
            
            formatSegmentedBar
                .fixedSize(horizontal: true, vertical: false)
            
            filterMenuButton
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            playbackControlsView
                .fixedSize(horizontal: true, vertical: false)
            
            trackCountPill
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private var compactToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 80, maxWidth: .infinity)
                
                Spacer(minLength: 4)
                
                playbackControlsView
                    .fixedSize(horizontal: true, vertical: false)
                
                trackCountPill
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
                
                Spacer(minLength: 4)
                
                trackCountPill
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            HStack(spacing: 8) {
                playbackControlsView
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
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
    
    private var filterMenuButton: some View {
        HiResFilterMenuButton(
            viewMode: $viewMode,
            trackSortOption: $trackSortOption,
            albumSortOption: $albumSortOption
        )
    }
    
    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
            
            TextField("Search Hi-Res titles, artists, albums...", text: $searchQuery)
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
    
    private var formatSegmentedBar: some View {
        HiResSegmentedBarView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private var playbackControlsView: some View {
        HStack(spacing: 7) {
            Button(action: togglePlaybackHiRes) {
                HStack(spacing: 6) {
                    Image(systemName: isPlayingFromHiResQueue ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isPlayingFromHiResQueue ? "Pause" : "Play Hi-Res")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
            .disabled(displayedTracks.isEmpty)
            .help(isPlayingFromHiResQueue ? "Pause playback" : "Play Hi-Res tracks in order")
            
            Button(action: shufflePlaybackHiRes) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
            .disabled(displayedTracks.isEmpty)
            .help("Shuffle Hi-Res tracks")
        }
    }
    
    private var trackCountPill: some View {
        HStack(spacing: 5) {
            Image(systemName: countPillIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WalkmanTheme.hiResGold)
            Text(countPillText)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.hiResGoldLight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WalkmanTheme.hiResGold.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(WalkmanTheme.hiResGold.opacity(0.24), lineWidth: 0.8)
        )
    }
    
    private var countPillIcon: String {
        switch viewMode {
        case .tracks: return "waveform"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        }
    }
    
    private var countPillText: String {
        switch viewMode {
        case .tracks:
            return displayedTracks.count == 1 ? "1 Master" : "\(displayedTracks.count.formatted()) Masters"
        case .albums:
            let count = uniqueAlbumCount
            return count == 1 ? "1 Album" : "\(count.formatted()) Albums"
        case .artists:
            let count = uniqueArtistCount
            return count == 1 ? "1 Artist" : "\(count.formatted()) Artists"
        }
    }
    
    private var uniqueAlbumCount: Int {
        Set(displayedTracks.map { "\($0.album.lowercased())__\($0.artist.lowercased())" }).count
    }
    
    private var uniqueArtistCount: Int {
        Set(displayedTracks.map { $0.primaryArtist.lowercased() }).count
    }
    
    // -------------------------------------------------------------------------
    // STUDIO MASTER CONSOLE BANNER
    // -------------------------------------------------------------------------
    
    private var studioConsoleBanner: some View {
        HStack(spacing: 16) {
            // Official Japan Audio Society / Sony Hi-Res Audio Logo
            if let logo = Self.cachedLogoImage {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WalkmanTheme.hiResGold)
                        .frame(width: 48, height: 48)
                    
                    VStack(spacing: 1) {
                        Text("Hi-Res")
                            .font(.system(size: 12, weight: .black, design: .serif))
                            .foregroundStyle(Color.black)
                        Text("AUDIO")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.black)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 8) {
                    Text("Hi-Res Studio Master Library")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    
                    Text("S-Master HX")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGold.opacity(0.18))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.6)
                        )
                }
                
                Text("Audiophile 24-bit / 96kHz+ lossless streams calibrated for Sony S-Master HX DAC & DSEE Ultimate.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Spacer()
            
            // Audio specs capsule
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(baseHiResTracks.count) Total Masters")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(WalkmanTheme.silverLight)
                    Text("Lossless PCM / DSD")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .padding(14)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 2)
    }
    
    // -------------------------------------------------------------------------
    // EMPTY STATE VIEW
    // -------------------------------------------------------------------------
    
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
                Image(systemName: "waveform.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Matching Hi-Res Tracks")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(searchQuery.isEmpty
                 ? "No audio tracks match the selected Hi-Res filter."
                 : "No Hi-Res tracks match \"\(searchQuery)\" with the selected filter.")
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
// HI-RES FILTER & VIEW MODE MENU BUTTON (APPLE-STYLE CIRCULAR LIQUID GLASS)
// -----------------------------------------------------------------------------
private struct HiResFilterMenuButton: View {
    @Binding var viewMode: HiResViewMode
    @Binding var trackSortOption: HiResTrackSortOption
    @Binding var albumSortOption: AlbumSortOption
    
    @State private var isHovered = false
    
    private var isFilterActive: Bool {
        viewMode != .tracks || trackSortOption != .defaultOrder || albumSortOption != .recentlyAdded
    }
    
    var body: some View {
        Menu {
            Picker("View As", selection: $viewMode) {
                ForEach(HiResViewMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.inline)
            
            if viewMode == .tracks {
                Divider()
                Picker("Sort Tracks", selection: $trackSortOption) {
                    ForEach(HiResTrackSortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.inline)
            } else if viewMode == .albums {
                Divider()
                Picker("Sort Albums", selection: $albumSortOption) {
                    ForEach(AlbumSortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            ZStack {
                // Circular glass body
                Circle()
                    .fill(
                        isFilterActive ?
                            Color.white.opacity(isHovered ? 0.16 : 0.12) :
                            Color.white.opacity(isHovered ? 0.10 : 0.05)
                    )
                
                // Top specular refraction sheen (Liquid Glass)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.32 : (isFilterActive ? 0.24 : 0.12)), location: 0.0),
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
                        isFilterActive ?
                            Color.white :
                            (isHovered ? Color.white : WalkmanTheme.silverLight)
                    )
                
                // Active beacon indicator (subtle 5pt dot at top right when non-default view or sort is active)
                if isFilterActive {
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
                        isFilterActive ?
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
        .help("View and sort options (Currently \(viewMode.rawValue))")
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
// HI-RES SEGMENTED BAR (MATCHED GEOMETRY SLIDING LIQUID GLASS LENS)
// -----------------------------------------------------------------------------
private struct HiResSegmentedBarView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    let onSelectFilter: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                HiResTabPillView(
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
// HI-RES TAB PILL VIEW (ROUND LIQUID GLASS CLICK BOX WITH HOVER)
// -----------------------------------------------------------------------------
private struct HiResTabPillView: View {
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
            .frame(minHeight: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    WalkmanTheme.hiResGoldLight :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        // Liquid Glass Active Pill Highlight — smoothly transfers via matched geometry
                        ActiveHiResPillBackground(isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeHiResHighlight", in: namespace)
                    } else if isHovered {
                        // Liquid Glass Hover Pill (Round frosted glass box)
                        HoverHiResPillBackground()
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

private struct ActiveHiResPillBackground: View {
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            // Liquid Glass Translucent Gold-Tinted Body Fill
            WalkmanTheme.hiResGold.opacity(isHovered ? 0.18 : 0.13)
            
            // Top specular refraction sheen
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.45 : 0.35), location: 0.0),
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
                    WalkmanTheme.hiResGold.opacity(isHovered ? 0.70 : 0.55),
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

private struct HoverHiResPillBackground: View {
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
// HI-RES TRACK ROW VIEW (TACTILE HOVER & AUDIO STATE)
// -----------------------------------------------------------------------------
private struct HiResRowBackground: View {
    let isPlaying: Bool
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            // Base Card Fill
            if isPlaying {
                WalkmanTheme.cardHover
                // Authentic Sony Hi-Res Gold subtle tint
                WalkmanTheme.hiResGold.opacity(0.08)
            } else if isHovered {
                Color.white.opacity(0.065)
            } else {
                WalkmanTheme.card.opacity(0.40)
            }
            
            // Specular Top Refraction Sheen (Liquid Glass Optics)
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(
                            color: isPlaying ?
                                WalkmanTheme.hiResGold.opacity(0.25) :
                                (isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.05)),
                            location: 0.0
                        ),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isHovered ? 5.5 : 4)
                
                Spacer(minLength: 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isPlaying ?
                        WalkmanTheme.hiResGold.opacity(0.40) :
                        (isHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.04)),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.22 : 0.08),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: isHovered ? 1.5 : 1
        )
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isPlaying)
    }
}

private struct HiResTrackRowView: View {
    let track: Track
    let isPlayingThis: Bool
    let onSelect: () -> Void
    let onPlayToggle: () -> Void
    var onEdit: (() -> Void)? = nil
    var onTrimCut: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Cover Art Thumbnail with Tactile Play/Pause Hover Overlay
            ZStack {
                TrackCoverThumbnail(track: track, size: 38, isPlaying: isPlayingThis)
                
                if isHovered {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.40))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGoldLight : Color.white)
                }
            }
            .frame(width: 38, height: 38)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(track.title)
                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(
                            isPlayingThis ?
                                WalkmanTheme.hiResGoldLight :
                                (isHovered ? Color.white : WalkmanTheme.silverLight)
                        )
                        .lineLimit(1)
                        .animation(.easeOut(duration: 0.15), value: isHovered)
                    
                    Text("\(track.bitsPerSample)-bit / \(track.sampleRate / 1000)kHz")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGold.opacity(isPlayingThis ? 0.28 : (isHovered ? 0.22 : 0.16)))
                        .foregroundStyle(isPlayingThis ? Color.white : WalkmanTheme.hiResGoldLight)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                WalkmanTheme.hiResGold.opacity(isPlayingThis ? 0.60 : (isHovered ? 0.45 : 0.35)),
                                lineWidth: 0.6
                            )
                        )
                }
                
                Text("\(track.artist) — \(track.album)")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(isHovered ? WalkmanTheme.silverLight.opacity(0.85) : WalkmanTheme.silverMuted)
                    .lineLimit(1)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            }
            
            Spacer()
            
            Text("\(track.bitrateKbps) kbps")
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(isHovered ? WalkmanTheme.silverLight.opacity(0.90) : WalkmanTheme.silverMuted.opacity(0.85))
                .animation(.easeOut(duration: 0.15), value: isHovered)
            
            Text(track.format)
                .font(WalkmanFont.badge)
                .padding(.horizontal, 5.5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(isHovered ? 0.12 : 0.08))
                .foregroundStyle(isHovered ? Color.white : WalkmanTheme.silverLight)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.22 : 0.12), lineWidth: 0.6)
                )
            
            Text(formatDuration(track.durationSeconds))
                .font(WalkmanFont.mono)
                .foregroundStyle(isHovered ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                .frame(width: 46, alignment: .trailing)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7.5)
        .background(
            HiResRowBackground(isPlaying: isPlayingThis, isHovered: isHovered)
        )
        .scaleEffect(isHovered && !isPlayingThis ? 1.004 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .onTapGesture {
            onSelect()
            onPlayToggle()
        }
        .contextMenu {
            Button(isPlayingThis ? "Pause" : "Play Track") {
                onPlayToggle()
            }
            Divider()
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
