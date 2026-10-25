import SwiftUI
import AppKit

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

public struct ArtistsView: View {
    let tracks: [Track]
    let precomputedArtists: [ArtistItem]?
    let showToolbar: Bool
    let onSelectTrack: (Track) -> Void
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedArtistName: String? = nil
    @State private var searchQuery: String = ""
    @State private var formatFilter: String = "ALL"
    @State private var cachedArtists: [ArtistItem] = []
    @State private var displayedArtists: [ArtistItem] = []
    
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
        precomputedArtists: [ArtistItem]? = nil,
        showToolbar: Bool = true,
        onSelectTrack: @escaping (Track) -> Void,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedArtists = precomputedArtists
        self.showToolbar = showToolbar
        self.onSelectTrack = onSelectTrack
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
        
        let initial = precomputedArtists ?? []
        self._cachedArtists = State(initialValue: initial)
        self._displayedArtists = State(initialValue: initial)
        self._selectedArtistName = State(initialValue: initial.first?.name)
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
            return
        }
        let list = baseArtists
        if list.isEmpty {
            displayedArtists = []
            selectedArtistName = nil
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
    }
    
    private var activeArtist: ArtistItem? {
        if let name = selectedArtistName {
            return displayedArtists.first(where: { $0.name == name }) ?? displayedArtists.first
        }
        return displayedArtists.first
    }
    
    private func filteredAlbums(for artist: ArtistItem) -> [AlbumItem] {
        if formatFilter == "ALL" {
            return artist.albums
        }
        return artist.albums.compactMap { alb in
            let matchingTracks = alb.tracks.filter { track in
                switch formatFilter {
                case "HI-RES":
                    return track.bitsPerSample > 16 || track.sampleRate > 48000
                case "LEARNING":
                    return track.isLanguageStudy
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
                VStack(spacing: 0) {
                    if displayedArtists.isEmpty {
                        leftEmptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(displayedArtists) { art in
                                    let isSelected = activeArtist?.name == art.name
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
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 260)
                .background(Color.clear)
                
                // Vertical Hairline Divider between Master List & Detail Console
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 0.8)
                
                // Right Detail Column: Artist Discography Console
                if let artist = activeArtist {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            // Hero Banner
                            artistHeroBanner(for: artist)
                            
                            // Releases Section Header
                            let albums = filteredAlbums(for: artist)
                            HStack(spacing: 8) {
                                Text("Releases")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("(\(albums.count))")
                                    .font(WalkmanFont.calloutMedium)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Spacer()
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                            
                            // Discography Albums
                            if albums.isEmpty {
                                discographyEmptyStateView
                            } else {
                                ForEach(albums) { alb in
                                    artistAlbumSection(album: alb, artist: artist)
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 88)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .onAppear {
            if cachedArtists.isEmpty && precomputedArtists == nil && !tracks.isEmpty {
                cachedArtists = Self.buildArtists(from: tracks)
                recomputeDisplayedArtists()
            } else if precomputedArtists != nil {
                recomputeDisplayedArtists()
            }
        }
        .onChange(of: precomputedArtists) { _, newPrecomputed in
            if let newPrecomputed = newPrecomputed {
                cachedArtists = newPrecomputed
                displayedArtists = newPrecomputed
                if let sel = selectedArtistName, !newPrecomputed.contains(where: { $0.name == sel }) {
                    selectedArtistName = newPrecomputed.first?.name
                } else if selectedArtistName == nil {
                    selectedArtistName = newPrecomputed.first?.name
                }
            } else {
                recomputeDisplayedArtists()
            }
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
        .onChange(of: cachedArtists) { _, _ in
            recomputeDisplayedArtists()
        }
    }
    
    // -------------------------------------------------------------------------
    // LEFT COLUMN SUBVIEWS (SEARCH CAPSULE & LIST)
    // -------------------------------------------------------------------------
    
    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
            
            TextField("Filter artists...", text: $searchQuery)
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
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
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
                    .frame(height: 6)
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
            wideTopToolbarLayout
            compactTopToolbarLayout
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.clear)
    }
    
    private var wideTopToolbarLayout: some View {
        HStack(spacing: 8) {
            searchFieldView
                .frame(minWidth: 160, idealWidth: 214, maxWidth: 240)
            
            artistFormatSegmentedBar
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            if let artist = activeArtist {
                artistActionButtons(for: artist)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            HStack(spacing: 6) {
                artistCountPill
                    .fixedSize(horizontal: true, vertical: false)
                
                if let artist = activeArtist {
                    trackCountPill(for: artist)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }
    
    private var compactTopToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(minWidth: 140, maxWidth: 220)
                
                Spacer(minLength: 4)
                
                if let artist = activeArtist {
                    artistActionButtons(for: artist)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                HStack(spacing: 6) {
                    artistCountPill
                        .fixedSize(horizontal: true, vertical: false)
                    
                    if let artist = activeArtist {
                        trackCountPill(for: artist)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                artistFormatSegmentedBar
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private var artistFormatSegmentedBar: some View {
        ArtistFormatSegmentedBarView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private func artistActionButtons(for artist: ArtistItem) -> some View {
        HStack(spacing: 7) {
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
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(minHeight: 33)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 16.5))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(artist.tracks.isEmpty)
            .help("Play all tracks by \(artist.name)")
            
            Button(action: {
                if let randomTrack = artist.tracks.randomElement() {
                    let shuffled = artist.tracks.shuffled()
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
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 33)
                .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 16.5))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(artist.tracks.isEmpty)
            .help("Shuffle tracks by \(artist.name)")
        }
    }
    
    private var artistCountPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.2")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text(displayedArtists.count == 1 ? "1 Artist" : "\(displayedArtists.count.formatted()) Artists")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func trackCountPill(for artist: ArtistItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("\(artist.trackCount) Tracks")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // -------------------------------------------------------------------------
    // ARTIST METADATA COMPUTATION HELPERS
    // -------------------------------------------------------------------------
    
    private func artistGenreString(for artist: ArtistItem) -> String? {
        let genres = artist.tracks.compactMap { tr -> String? in
            let g = tr.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            return g.isEmpty ? nil : g
        }
        guard !genres.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for g in genres { counts[g, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? genres.first
    }
    
    private func artistYearsRangeString(for artist: ArtistItem) -> String? {
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
    
    private func artistDurationFormatted(for artist: ArtistItem) -> String {
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
    
    private func artistTotalSizeFormatted(for artist: ArtistItem) -> String {
        let bytes = artist.tracks.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if bytes <= 0 { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func artistQualitySpecsString(for artist: ArtistItem) -> String {
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
    
    private func artistAvgBitrateString(for artist: ArtistItem) -> String? {
        let bitrates = artist.tracks.map(\.bitrateKbps).filter { $0 > 0 }
        guard !bitrates.isEmpty else { return nil }
        let avg = bitrates.reduce(0, +) / bitrates.count
        return "\(avg) kbps"
    }
    
    // -------------------------------------------------------------------------
    // ARTIST HERO BANNER & ALBUM SECTIONS
    // -------------------------------------------------------------------------
    
    private func artistMetadataSummary(for artist: ArtistItem) -> String {
        var components: [String] = []
        if let genre = artistGenreString(for: artist) {
            components.append(genre)
        }
        if let years = artistYearsRangeString(for: artist) {
            components.append(years)
        }
        components.append("\(artist.albumCount) \(artist.albumCount == 1 ? "Album" : "Albums")")
        components.append(artistDurationFormatted(for: artist))
        let sizeStr = artistTotalSizeFormatted(for: artist)
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
            Text(artistQualitySpecsString(for: artist))
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
    
    private func artistBitrateBadge(for artist: ArtistItem) -> some View {
        Group {
            if let avgBitrate = artistAvgBitrateString(for: artist) {
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
    
    private func artistSpecificationBadges(for artist: ArtistItem) -> some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout (single horizontal row)
            HStack(spacing: 7) {
                if artist.isHiRes {
                    artistHiResBadge
                }
                artistQualityBadge(for: artist)
                artistBitrateBadge(for: artist)
            }
            
            // Compact layout (two rows)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if artist.isHiRes {
                        artistHiResBadge
                    }
                    artistQualityBadge(for: artist)
                }
                artistBitrateBadge(for: artist)
            }
        }
        .padding(.top, 4)
    }
    
    private func artistHeroBanner(for artist: ArtistItem) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Prominent Circular Artist Avatar (120x120 pt)
            artistCoverArtView(for: artist)
            
            // Prominent Metadata Details & Action Controls
            VStack(alignment: .leading, spacing: 6) {
                // 1. Kicker
                Text("ARTIST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .tracking(1.4)
                
                // 2. Big Prominent Artist Name (32pt Bold)
                Text(artist.name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 3. Primary Metadata Line (Genre • Years Active • Albums Count • Duration • Size)
                Text(artistMetadataSummary(for: artist))
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
    
    private func artistActionButtonsView(for artist: ArtistItem) -> some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout (single row with labels)
            HStack(spacing: 8) {
                artistPlayButton(for: artist)
                artistShuffleButton(for: artist)
                artistChangePhotoButton(for: artist)
                artistMoreMenuButton(for: artist)
            }
            
            // Compact layout (Apple Music style circular icons)
            HStack(spacing: 8) {
                artistPlayButton(for: artist)
                artistShuffleButton(for: artist)
                artistChangePhotoCircularButton(for: artist)
                artistMoreMenuButton(for: artist)
            }
            
            // Two rows
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
    
    private func artistAlbumSection(album: AlbumItem, artist: ArtistItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Album Header Row
            HStack(spacing: 14) {
                if let rep = album.representativeTrack {
                    TrackCoverThumbnail(track: rep, size: 60)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(album.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if album.isHiRes {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 2)
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
                
                Spacer(minLength: 12)
                
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
            }
            .contentShape(Rectangle())
            .contextMenu {
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
            VStack(spacing: 1.5) {
                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                    ArtistTrackRowView(
                        index: index + 1,
                        track: track,
                        artistName: artist.name,
                        albumTracks: album.tracks,
                        onSelect: {
                            onSelectTrack(track)
                            if player.currentTrack?.id == track.id && player.isPlaying {
                                player.pause()
                            } else {
                                player.play(track: track, in: album.tracks)
                            }
                        },
                        onPlay: {
                            player.play(track: track, in: album.tracks)
                        },
                        onEdit: {
                            onEditTrack?(track)
                        },
                        onTrimCut: {
                            onTrimCutTrack?(track)
                        }
                    )
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
                size: 120,
                isSelected: false
            )
            .frame(width: 120, height: 120)
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
private struct ArtistListRowView: View {
    let artist: ArtistItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlayAll: () -> Void
    let onRefreshPhoto: () -> Void
    let onCustomPhoto: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Circular Artist Photo Avatar
                ArtistAvatarView(
                    artistName: artist.name,
                    representativeTrack: artist.representativeTrack,
                    size: 36,
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
            .padding(.horizontal, 10)
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
            Button("Play All (\(artist.trackCount) tracks)") {
                onPlayAll()
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
// ARTIST FORMAT SEGMENTED BAR (MATCHED GEOMETRY SLIDING LIQUID GLASS LENS)
// -----------------------------------------------------------------------------
private struct ArtistFormatSegmentedBarView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    let onSelectFilter: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                ArtistFormatTabPillView(
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
// ARTIST FORMAT TAB PILL VIEW (ROUND LIQUID GLASS CLICK BOX WITH HOVER)
// -----------------------------------------------------------------------------
private struct ArtistFormatTabPillView: View {
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
private struct ArtistTrackRowView: View {
    let index: Int
    let track: Track
    let artistName: String
    let albumTracks: [Track]
    let onSelect: () -> Void
    let onPlay: () -> Void
    var onEdit: (() -> Void)? = nil
    var onTrimCut: (() -> Void)? = nil
    
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
            // Track Number or Play button
            Button(action: onPlay) {
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
                .frame(width: 22, alignment: .trailing)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : (isHovered ? Color.white : WalkmanTheme.silverLight))
                    .lineLimit(1)
                
                if let feat = track.featuredDisplayString(primaryArtist: artistName) {
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
                            .stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.6)
                    )
            }
            
            Text(track.format)
                .font(WalkmanFont.badge)
                .foregroundStyle(WalkmanTheme.silverMuted)
            
            Text(formatDuration(track.durationSeconds))
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .frame(width: 44, alignment: .trailing)
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
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Play Track") {
                onPlay()
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
        }
    }
}
