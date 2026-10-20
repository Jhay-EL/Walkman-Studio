import SwiftUI
import AppKit

public struct AlbumsView: View {
    let tracks: [Track]
    let onSelectTrack: (Track) -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedAlbum: AlbumItem? = nil
    @State private var searchQuery: String = ""
    
    public init(tracks: [Track], onSelectTrack: @escaping (Track) -> Void) {
        self.tracks = tracks
        self.onSelectTrack = onSelectTrack
    }
    
    private var albums: [AlbumItem] {
        var grouped: [String: [Track]] = [:]
        for track in tracks {
            let key = "\(track.primaryArtist)|\(track.album)"
            grouped[key, default: []].append(track)
        }
        
        var list: [AlbumItem] = []
        for (key, albumTracks) in grouped {
            let parts = key.components(separatedBy: "|")
            let artist = parts.first ?? "Unknown Artist"
            let name = parts.count > 1 ? parts[1] : "Unknown Album"
            let sortedTracks = albumTracks.sorted {
                let num0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                let num1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                return num0 < num1
            }
            let year = sortedTracks.first(where: { !$0.year.isEmpty })?.year ?? ""
            list.append(AlbumItem(
                name: name,
                artist: artist,
                year: year,
                trackCount: sortedTracks.count,
                tracks: sortedTracks
            ))
        }
        
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private var filteredAlbums: [AlbumItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return albums }
        return albums.filter {
            $0.name.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let album = selectedAlbum {
                // Album Detail View (Apple Music Style)
                AlbumDetailView(
                    album: album,
                    onBack: { selectedAlbum = nil },
                    onSelectTrack: onSelectTrack
                )
            } else {
                // Albums Grid View
                VStack(spacing: 0) {
                    // Header Bar
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            
                            TextField("Search albums or artists...", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                            
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: 280)
                        
                        Spacer()
                        
                        Text("\(filteredAlbums.count.formatted()) Albums")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)], spacing: 22) {
                            ForEach(filteredAlbums) { alb in
                                AlbumGridCard(album: alb) {
                                    selectedAlbum = alb
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }
}

private struct AlbumGridCard: View {
    let album: AlbumItem
    let onOpen: () -> Void
    
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
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.silverGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(album.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if !album.year.isEmpty {
                            Text(album.year)
                            Text("•")
                        }
                        Text("\(album.trackCount) tracks")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumDetailView: View {
    let album: AlbumItem
    let onBack: () -> Void
    let onSelectTrack: (Track) -> Void
    
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
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Albums")
                            .font(.system(size: 12))
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
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(album.name)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                if album.isHiRes {
                                    Text("Hi-Res Audio")
                                        .font(.system(size: 9, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(WalkmanTheme.silverGradient)
                                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Text(album.artist)
                                .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            
                            // Play Album Button
                            Button(action: {
                                if let first = album.tracks.first {
                                    player.play(track: first, in: album.tracks)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text("Play Album")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(WalkmanTheme.silverGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
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
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .secondary)
                                            .opacity(isPlayingThis ? 0 : 1)
                                        
                                        Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                            .opacity(isPlayingThis ? 1 : 0)
                                    }
                                    .frame(width: 24, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.system(size: 12, weight: isPlayingThis ? .bold : .regular))
                                        .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                        .lineLimit(1)
                                    
                                    if let feat = track.featuredDisplayString(primaryArtist: album.artist) {
                                        HStack(spacing: 4) {
                                            Text("feat.")
                                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                            Text(feat)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if track.bitsPerSample > 16 || track.sampleRate > 48000 {
                                    Text("Hi-Res")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                                
                                Text(track.format)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                Text(formatDuration(track.durationSeconds))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
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
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
        }
    }
}
