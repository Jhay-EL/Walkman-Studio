import SwiftUI
import AppKit

public struct ArtistsView: View {
    let tracks: [Track]
    let precomputedArtists: [ArtistItem]?
    let onSelectTrack: (Track) -> Void
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedArtistName: String? = nil
    @State private var searchQuery: String = ""
    
    public init(
        tracks: [Track],
        precomputedArtists: [ArtistItem]? = nil,
        onSelectTrack: @escaping (Track) -> Void,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.precomputedArtists = precomputedArtists
        self.onSelectTrack = onSelectTrack
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
    }
    
    @State private var cachedArtists: [ArtistItem] = []
    
    private var artists: [ArtistItem] {
        if let pre = precomputedArtists, !pre.isEmpty { return pre }
        if !cachedArtists.isEmpty { return cachedArtists }
        return Self.buildArtists(from: tracks)
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
                    return n0 < n1
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
    
    private var filteredArtists: [ArtistItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return artists }
        return artists.filter { art in
            art.name.lowercased().contains(q) || art.tracks.contains(where: { $0.artist.lowercased().contains(q) || $0.title.lowercased().contains(q) })
        }
    }
    
    private var activeArtist: ArtistItem? {
        if let name = selectedArtistName {
            return artists.first(where: { $0.name == name }) ?? artists.first
        }
        return artists.first
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Column: Artist List (Master)
            VStack(spacing: 0) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Filter artists...", text: $searchQuery)
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
                .padding(12)
                
                Divider()
                    .overlay(Color.white.opacity(0.06))
                
                // Artists Scroll List
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredArtists) { art in
                            let isSelected = activeArtist?.name == art.name
                            
                            Button(action: { selectedArtistName = art.name }) {
                                HStack(spacing: 10) {
                                    // Circular Artist Photo Avatar
                                    ArtistAvatarView(
                                        artistName: art.name,
                                        representativeTrack: art.representativeTrack,
                                        size: 34,
                                        isSelected: isSelected
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(art.name)
                                            .font(isSelected ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .lineLimit(1)
                                        
                                        Text("\(art.albumCount) albums • \(art.trackCount) tracks")
                                            .font(WalkmanFont.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? WalkmanTheme.cardHover : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Play All (\(art.trackCount) tracks)") {
                                    if let first = art.tracks.first {
                                        player.play(track: first, in: art.tracks)
                                    }
                                }
                                Divider()
                                Button("Refresh Artist Photo") {
                                    ArtistArtCache.shared.refresh(artistName: art.name, representativeTrack: art.representativeTrack)
                                }
                                Button("Choose Custom Photo...") {
                                    promptCustomPhoto(for: art.name)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(minWidth: 180, idealWidth: 215, maxWidth: 245)
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Right Detail Column: Artist Discography
            if let artist = activeArtist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Artist Hero Banner
                        HStack(spacing: 16) {
                            Button(action: {
                                promptCustomPhoto(for: artist.name)
                            }) {
                                ArtistAvatarView(
                                    artistName: artist.name,
                                    representativeTrack: artist.representativeTrack,
                                    size: 64,
                                    isSelected: false
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                            .help("Click to change artist photo, or right-click to refresh")
                            .contextMenu {
                                Button("Refresh Artist Photo") {
                                    ArtistArtCache.shared.refresh(artistName: artist.name, representativeTrack: artist.representativeTrack)
                                }
                                Button("Choose Custom Photo...") {
                                    promptCustomPhoto(for: artist.name)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artist.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("\(artist.albumCount) Albums • \(artist.trackCount) Tracks on Walkman")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Play All Button
                            Button(action: {
                                if let first = artist.tracks.first {
                                    player.play(track: first, in: artist.tracks)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11))
                                    Text("Play All")
                                        .font(WalkmanFont.calloutBold)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(WalkmanTheme.silverGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Albums Discography Sections
                        ForEach(artist.albums) { alb in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 14) {
                                    if let rep = alb.representativeTrack {
                                        TrackCoverThumbnail(track: rep, size: 54)
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(alb.name)
                                                .font(WalkmanFont.headline)
                                                .foregroundStyle(.white)
                                            
                                            if alb.isHiRes {
                                                Text("Hi-Res")
                                                    .font(WalkmanFont.badge)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(WalkmanTheme.hiResGoldGradient)
                                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                                    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                                            }
                                        }
                                        
                                        HStack(spacing: 6) {
                                            if !alb.year.isEmpty {
                                                Text(alb.year)
                                                Text("•")
                                            }
                                            Text("\(alb.trackCount) tracks")
                                        }
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button {
                                        ArtworkExportService.exportArtwork(for: alb)
                                    } label: {
                                        Label("Export Album Artwork to Mac...", systemImage: "square.and.arrow.down")
                                    }
                                }
                                
                                // Album Track Rows
                                VStack(spacing: 2) {
                                    ForEach(Array(alb.tracks.enumerated()), id: \.element.id) { index, track in
                                        let isPlayingThis = player.currentTrack?.id == track.id && player.isPlaying
                                        
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                if isPlayingThis {
                                                    player.pause()
                                                } else {
                                                    player.play(track: track, in: alb.tracks)
                                                }
                                            }) {
                                                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(WalkmanTheme.silverLight)
                                                    .frame(width: 16)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Text(track.trackNum.isEmpty ? "\(index + 1)" : track.trackNum)
                                                .font(WalkmanFont.mono)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, alignment: .trailing)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title)
                                                    .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                                    .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                                    .lineLimit(1)
                                                
                                                if let feat = track.featuredDisplayString(primaryArtist: artist.name) {
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
                                                .foregroundStyle(.tertiary)
                                            
                                            let mins = Int(track.durationSeconds) / 60
                                            let secs = Int(track.durationSeconds) % 60
                                            Text(String(format: "%d:%02d", mins, secs))
                                                .font(WalkmanFont.mono)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 44, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
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
                                                player.play(track: track, in: alb.tracks)
                                            }
                                        }
                                        .contextMenu {
                                            Button("Play Track") {
                                                player.play(track: track, in: alb.tracks)
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
                                                Label("Trim & Cut...", systemImage: "scissors")
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
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.mic")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Select an artist from the list")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task(id: tracks.count) {
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildArtists(from: tracks)
            }.value
            await MainActor.run {
                self.cachedArtists = built
            }
        }
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
