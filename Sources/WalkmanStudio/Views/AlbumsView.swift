import SwiftUI
import AppKit

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
    let onSelectTrack: (Track) -> Void
    var onEditAlbum: ((AlbumItem) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onDeleteAlbum: ((AlbumItem) -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedAlbum: AlbumItem? = nil
    @State private var searchQuery: String = ""
    @State private var sortOption: AlbumSortOption = .recentlyAdded
    @State private var formatFilter: String = "ALL"
    @State private var cachedAlbums: [AlbumItem] = []
    
    public init(
        tracks: [Track],
        precomputedAlbums: [AlbumItem]? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditAlbum: ((AlbumItem) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onDeleteAlbum: ((AlbumItem) -> Void)? = nil,
        onDeleteTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedAlbums = precomputedAlbums
        self.onSelectTrack = onSelectTrack
        self.onEditAlbum = onEditAlbum
        self.onEditTrack = onEditTrack
        self.onDeleteAlbum = onDeleteAlbum
        self.onDeleteTrack = onDeleteTrack
    }
    
    private var albums: [AlbumItem] {
        if let pre = precomputedAlbums, !pre.isEmpty { return pre }
        if !cachedAlbums.isEmpty { return cachedAlbums }
        return Self.buildAlbums(from: tracks)
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
    
    private var filteredAndSortedAlbums: [AlbumItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = albums.filter { alb in
            if !q.isEmpty {
                let matchesQuery = alb.name.lowercased().contains(q) || alb.artist.lowercased().contains(q)
                if !matchesQuery { return false }
            }
            if formatFilter == "HI-RES" {
                return alb.isHiRes
            } else if formatFilter == "LEARNING" {
                return alb.isLanguageStudy
            } else if formatFilter == "FLAC" {
                return alb.tracks.contains { $0.format == "FLAC" }
            } else if formatFilter == "MP3" {
                return alb.tracks.contains { $0.format == "MP3" }
            }
            return true
        }
        
        return filtered.sorted { a, b in
            switch sortOption {
            case .nameAsc:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc:
                return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .recentlyAdded:
                if a.latestDateAdded != b.latestDateAdded {
                    return a.latestDateAdded > b.latestDateAdded
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .artistAsc:
                let cmp = a.artist.localizedStandardCompare(b.artist)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .yearDesc:
                let yA = Int(a.year) ?? 0
                let yB = Int(b.year) ?? 0
                if yA != yB { return yA > yB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .yearAsc:
                let yA = Int(a.year) ?? 9999
                let yB = Int(b.year) ?? 9999
                if yA != yB { return yA < yB }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .trackCountDesc:
                if a.trackCount != b.trackCount {
                    return a.trackCount > b.trackCount
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let album = selectedAlbum {
                // Album Detail View (Apple Music Style)
                AlbumDetailView(
                    album: album,
                    onBack: { selectedAlbum = nil },
                    onSelectTrack: onSelectTrack,
                    onEditAlbum: {
                        onEditAlbum?(album)
                    },
                    onEditTrack: { tr in
                        onEditTrack?(tr)
                    },
                    onDeleteAlbum: {
                        selectedAlbum = nil
                        onDeleteAlbum?(album)
                    },
                    onDeleteTrack: { tr in
                        onDeleteTrack?(tr)
                    }
                )
            } else {
                // Albums Grid View
                VStack(spacing: 0) {
                    // Header Bar
                    HStack(spacing: 10) {
                        // Search Field
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            
                            TextField("Search albums or artists...", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                            
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: 240)
                        
                        // Sort Menu Dropdown
                        Menu {
                            Picker("Sort By", selection: $sortOption) {
                                ForEach(AlbumSortOption.allCases) { opt in
                                    Label(opt.rawValue, systemImage: opt.icon).tag(opt)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sortOption.icon)
                                    .font(.system(size: 11))
                                Text(sortOption.rawValue)
                                    .font(WalkmanFont.calloutMedium)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(WalkmanTheme.silverLight)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        
                        // Format Filter Chips
                        Picker("", selection: $formatFilter) {
                            Text("All").tag("ALL")
                            Text("Learning").tag("LEARNING")
                            Text("Hi-Res").tag("HI-RES")
                            Text("FLAC").tag("FLAC")
                            Text("MP3").tag("MP3")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                        
                        Spacer()
                        
                        Text("\(filteredAndSortedAlbums.count.formatted()) Albums")
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                    
                    if filteredAndSortedAlbums.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "square.stack")
                                .font(.system(size: 38))
                                .foregroundStyle(.tertiary)
                            Text(searchQuery.isEmpty ? "No Albums Found" : "No Albums Matching \"\(searchQuery)\"")
                                .font(WalkmanFont.title3)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)], spacing: 22) {
                                ForEach(filteredAndSortedAlbums) { alb in
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
                                        }
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
        }
        .onChange(of: tracks) {
            if let sel = selectedAlbum, !tracks.contains(where: { $0.album.lowercased() == sel.name.lowercased() }) {
                selectedAlbum = nil
            }
        }
        .task(id: tracks.count) {
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildAlbums(from: tracks)
            }.value
            await MainActor.run {
                self.cachedAlbums = built
            }
        }
    }
}

private struct AlbumGridCard: View {
    let album: AlbumItem
    let onOpen: () -> Void
    var onInspectAlbum: (() -> Void)? = nil
    var onEditAlbum: (() -> Void)? = nil
    var onDeleteAlbum: (() -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                // Artwork Tile
                ZStack(alignment: .bottomTrailing) {
                    if let rep = album.representativeTrack {
                        TrackCoverThumbnail(track: rep, size: 160)
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(WalkmanTheme.card)
                            .frame(width: 160, height: 160)
                            .overlay(
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                            )
                    }
                    
                    if album.isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .shadow(color: Color.black.opacity(0.4), radius: 2)
                            .padding(6)
                    } else if album.isLanguageStudy {
                        HStack(spacing: 3) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.system(size: 8))
                            Text("Learning")
                        }
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: Color.black.opacity(0.4), radius: 2)
                        .padding(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(album.name)
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(album.artist)
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if !album.year.isEmpty {
                            Text(album.year)
                            Text("•")
                        }
                        Text("\(album.trackCount) tracks")
                    }
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.tertiary)
                }
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpen) {
                Label("View Album Details", systemImage: "music.note.list")
            }
            
            Button {
                if let first = album.tracks.first {
                    player.play(track: first, in: album.tracks)
                }
            } label: {
                Label("Play Album", systemImage: "play.fill")
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

private struct AlbumDetailView: View {
    let album: AlbumItem
    let onBack: () -> Void
    let onSelectTrack: (Track) -> Void
    var onEditAlbum: (() -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onDeleteAlbum: (() -> Void)? = nil
    var onDeleteTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private var totalDurationSeconds: Double {
        album.tracks.reduce(0) { $0 + $1.durationSeconds }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Back Navigation Header
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Albums")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Album Hero Header
                    HStack(spacing: 20) {
                        if let rep = album.representativeTrack {
                            TrackCoverThumbnail(track: rep, size: 140)
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Text(album.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                if album.isHiRes {
                                    Text("Hi-Res Audio")
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2.5)
                                        .background(WalkmanTheme.hiResGoldGradient)
                                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                        .clipShape(Capsule())
                                } else if album.isLanguageStudy {
                                    HStack(spacing: 4) {
                                        Image(systemName: "character.book.closed.fill")
                                            .font(.system(size: 9))
                                        Text("Language Study")
                                    }
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(Capsule())
                                }
                            }
                            
                            Text(album.artist)
                                .font(WalkmanFont.title3)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            
                            HStack(spacing: 6) {
                                if !album.year.isEmpty {
                                    Text(album.year)
                                    Text("•")
                                }
                                Text("\(album.trackCount) tracks")
                                Text("•")
                                Text(formatDuration(totalDurationSeconds))
                            }
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            
                            // Action Buttons
                            HStack(spacing: 8) {
                                Button(action: {
                                    if let first = album.tracks.first {
                                        player.play(track: first, in: album.tracks)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 11))
                                        Text("Play Album")
                                            .font(WalkmanFont.calloutBold)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { onEditAlbum?() }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 11))
                                        Text("Edit Album")
                                            .font(WalkmanFont.calloutMedium)
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Edit album artwork, tags, and track numbers in a popup window")
                                
                                Button(action: { ArtworkExportService.exportArtwork(for: album) }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 11))
                                        Text("Export Artwork")
                                            .font(WalkmanFont.calloutMedium)
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Extract and save album cover art onto your Mac")
                                
                                if let rep = album.representativeTrack {
                                    Button(action: { onSelectTrack(rep) }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 11))
                                            Text("Get Info")
                                                .font(WalkmanFont.calloutMedium)
                                        }
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundStyle(WalkmanTheme.silverLight)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Inspect album metadata and cover artwork in sidebar")
                                }
                                
                                Button(action: { onDeleteAlbum?() }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                        Text("Delete Album")
                                            .font(WalkmanFont.calloutMedium)
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Color.red.opacity(0.16))
                                    .foregroundStyle(Color(red: 255/255, green: 110/255, blue: 100/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Delete album and all its tracks from Walkman without confirmation")
                            }
                            .padding(.top, 6)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .contextMenu {
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
                    
                    // Album Tracks List
                    VStack(spacing: 2) {
                        ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                            let isPlayingThis = player.currentTrack?.id == track.id && player.isPlaying
                            
                            HStack(spacing: 12) {
                                // Track Number or Play button
                                Button(action: {
                                    if isPlayingThis {
                                        player.pause()
                                    } else {
                                        player.play(track: track, in: album.tracks)
                                    }
                                }) {
                                    ZStack {
                                        Text("\(index + 1)")
                                            .font(WalkmanFont.mono)
                                            .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .secondary)
                                            .opacity(isPlayingThis ? 0 : 1)
                                        
                                        Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                            .opacity(isPlayingThis ? 1 : 0)
                                    }
                                    .frame(width: 26, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                        .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                        .lineLimit(1)
                                    
                                    if album.artist.contains("Various Artists") || track.primaryArtist.lowercased() != album.artist.lowercased() {
                                        Text(track.artist)
                                            .font(WalkmanFont.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else if let feat = track.featuredDisplayString(primaryArtist: album.artist) {
                                        HStack(spacing: 4) {
                                            Text("feat.")
                                                .font(WalkmanFont.badge)
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                            Text(feat)
                                                .font(WalkmanFont.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if track.bitsPerSample > 16 || track.sampleRate > 48000 {
                                    Text("Hi-Res")
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 4.5)
                                        .padding(.vertical, 1.5)
                                        .background(WalkmanTheme.hiResGold.opacity(0.18))
                                        .foregroundStyle(WalkmanTheme.hiResGold)
                                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                                }
                                
                                Text(track.format)
                                    .font(WalkmanFont.badge)
                                    .foregroundStyle(.secondary)
                                
                                Text(formatDuration(track.durationSeconds))
                                    .font(WalkmanFont.mono)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isPlayingThis ? WalkmanTheme.cardHover : Color.clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectTrack(track)
                                if player.currentTrack?.id == track.id && player.isPlaying {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: album.tracks)
                                }
                            }
                            .contextMenu {
                                Button("Play Track") {
                                    player.play(track: track, in: album.tracks)
                                }
                                Divider()
                                Button {
                                    onEditTrack?(track)
                                } label: {
                                    Label("Edit Song Metadata...", systemImage: "square.and.pencil")
                                }
                                Button {
                                    ArtworkExportService.exportArtwork(for: track)
                                } label: {
                                    Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                                }
                                Button("Inspect in Sidebar") {
                                    onSelectTrack(track)
                                }
                                Divider()
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(track.fullPath, forType: .string)
                                }
                                Divider()
                                Button(role: .destructive) {
                                    onDeleteTrack?(track)
                                } label: {
                                    Label("Delete from Device", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
        }
    }
}
