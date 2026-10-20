import SwiftUI
import AppKit

public struct ArtistsView: View {
    let tracks: [Track]
    let onSelectTrack: (Track) -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var selectedArtistName: String? = nil
    @State private var searchQuery: String = ""
    
    public init(tracks: [Track], onSelectTrack: @escaping (Track) -> Void) {
        self.tracks = tracks
        self.onSelectTrack = onSelectTrack
    }
    
    private var artists: [ArtistItem] {
        var grouped: [String: [Track]] = [:]
        for track in tracks {
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = artist.isEmpty ? "Unknown Artist" : artist
            grouped[key, default: []].append(track)
        }
        
        var list: [ArtistItem] = []
        for (artistName, artistTracks) in grouped {
            var albumGrouped: [String: [Track]] = [:]
            for track in artistTracks {
                albumGrouped[track.album, default: []].append(track)
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
        return artists.filter { $0.name.lowercased().contains(q) }
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    TextField("Filter artists...", text: $searchQuery)
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
                                    // Circular Artist Badge
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? WalkmanTheme.gold : Color.white.opacity(0.1))
                                            .frame(width: 32, height: 32)
                                        
                                        Text(String(art.name.prefix(1)).uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(isSelected ? .black : .white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(art.name)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .foregroundStyle(isSelected ? .white : .primary)
                                            .lineLimit(1)
                                        
                                        Text("\(art.albumCount) albums • \(art.trackCount) tracks")
                                            .font(.system(size: 9))
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
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 250)
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Right Detail Column: Artist Discography
            if let artist = activeArtist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Artist Hero Banner
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(WalkmanTheme.goldGradient)
                                    .frame(width: 60, height: 60)
                                
                                Text(String(artist.name.prefix(1)).uppercased())
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundStyle(.black)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artist.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("\(artist.albumCount) Albums • \(artist.trackCount) Tracks on Walkman")
                                    .font(.system(size: 11))
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
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(WalkmanTheme.goldGradient)
                                .foregroundStyle(.black)
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
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(alb.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                            
                                            if alb.isHiRes {
                                                Text("Hi-Res")
                                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(WalkmanTheme.gold)
                                                    .foregroundStyle(.black)
                                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                            }
                                        }
                                        
                                        HStack(spacing: 6) {
                                            if !alb.year.isEmpty {
                                                Text(alb.year)
                                                Text("•")
                                            }
                                            Text("\(alb.trackCount) tracks")
                                        }
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
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
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(WalkmanTheme.gold)
                                                    .frame(width: 16)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Text(track.trackNum.isEmpty ? "\(index + 1)" : track.trackNum)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 22, alignment: .trailing)
                                            
                                            Text(track.title)
                                                .font(.system(size: 11, weight: isPlayingThis ? .bold : .medium))
                                                .foregroundStyle(isPlayingThis ? WalkmanTheme.gold : .white)
                                                .lineLimit(1)
                                            
                                            Spacer()
                                            
                                            Text(track.format)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                            
                                            let mins = Int(track.durationSeconds) / 60
                                            let secs = Int(track.durationSeconds) % 60
                                            Text(String(format: "%d:%02d", mins, secs))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 38, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
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
    }
}
