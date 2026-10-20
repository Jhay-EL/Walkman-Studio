import SwiftUI
import AppKit

public struct HiResAudioView: View {
    let tracks: [Track]
    let onSelectTrack: (Track) -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery: String = ""
    @State private var minBitsFilter: Int = 24
    
    public init(tracks: [Track], onSelectTrack: @escaping (Track) -> Void) {
        self.tracks = tracks
        self.onSelectTrack = onSelectTrack
    }
    
    private var hiResTracks: [Track] {
        tracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
    }
    
    private var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hiResTracks.filter { track in
            let matchSearch = q.isEmpty
                || track.title.lowercased().contains(q)
                || track.artist.lowercased().contains(q)
                || track.album.lowercased().contains(q)
            
            if !matchSearch { return false }
            if minBitsFilter == 24 && track.bitsPerSample < 24 { return false }
            return true
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Banner
            HStack(spacing: 14) {
                // Hi-Res Gold Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalkmanTheme.goldGradient)
                        .frame(width: 48, height: 48)
                        .shadow(color: WalkmanTheme.gold.opacity(0.3), radius: 6)
                    
                    VStack(spacing: 1) {
                        Text("Hi-Res")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                        Text("AUDIO")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hi-Res Studio Master Library")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Audiophile 24-bit / 96kHz+ lossless streams calibrated for Sony S-Master HX DAC.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Play All Hi-Res Button
                if !filteredTracks.isEmpty {
                    Button(action: {
                        if let first = filteredTracks.first {
                            player.play(track: first, in: filteredTracks)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Play Hi-Res Queue")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(WalkmanTheme.goldGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)
            .padding(14)
            
            // Search & Filter Row
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search Hi-Res titles...", text: $searchQuery)
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
                
                Picker("", selection: $minBitsFilter) {
                    Text("24-bit Studio Masters").tag(24)
                    Text("All Hi-Res (>16-bit)").tag(16)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                
                Spacer()
                
                Text("\(filteredTracks.count) Studio Master Tracks")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.gold)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            // Hi-Res Tracks List
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                        let isPlayingThis = player.currentTrack?.id == track.id && player.isPlaying
                        
                        HStack(spacing: 14) {
                            Button(action: {
                                if isPlayingThis {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: filteredTracks)
                                }
                            }) {
                                TrackCoverThumbnail(track: track, size: 36, isPlaying: isPlayingThis)
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(track.title)
                                        .font(.system(size: 12, weight: isPlayingThis ? .bold : .medium))
                                        .foregroundStyle(isPlayingThis ? WalkmanTheme.gold : .white)
                                        .lineLimit(1)
                                    
                                    Text("\(track.bitsPerSample)-bit / \(track.sampleRate / 1000)kHz")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(WalkmanTheme.gold.opacity(0.18))
                                        .foregroundStyle(WalkmanTheme.gold)
                                        .clipShape(Capsule())
                                }
                                
                                Text("\(track.artist) — \(track.album)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text("\(track.bitrateKbps) kbps")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            
                            Text(track.format)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(WalkmanTheme.gold.opacity(0.12))
                                .foregroundStyle(WalkmanTheme.gold)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            
                            Text(formatDuration(track.durationSeconds))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isPlayingThis ? WalkmanTheme.cardHover : Color.white.opacity(0.02))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectTrack(track)
                            if player.currentTrack?.id == track.id && player.isPlaying {
                                player.pause()
                            } else {
                                player.play(track: track, in: filteredTracks)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}
