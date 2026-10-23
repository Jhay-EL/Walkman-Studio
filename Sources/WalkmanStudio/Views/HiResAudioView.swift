import SwiftUI
import AppKit

public struct HiResAudioView: View {
    let tracks: [Track]
    let onSelectTrack: (Track) -> Void
    var onEditTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery: String = ""
    @State private var minBitsFilter: Int = 24
    
    public init(
        tracks: [Track],
        onSelectTrack: @escaping (Track) -> Void,
        onEditTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.onSelectTrack = onSelectTrack
        self.onEditTrack = onEditTrack
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
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Banner
            HStack(spacing: 14) {
                // Official Japan Audio Society / Sony Hi-Res Audio Logo
                if let logo = Self.cachedLogoImage {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 232/255, green: 185/255, blue: 68/255))
                            .frame(width: 44, height: 44)
                        
                        VStack(spacing: 1) {
                            Text("Hi-Res")
                                .font(.system(size: 11, weight: .black, design: .serif))
                                .foregroundStyle(Color.black)
                            Text("AUDIO")
                                .font(.system(size: 7.5, weight: .bold, design: .default))
                                .tracking(0.5)
                                .foregroundStyle(Color.black)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hi-Res Studio Master Library")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)
                    
                    Text("Audiophile 24-bit / 96kHz+ lossless streams calibrated for Sony S-Master HX DAC.")
                        .font(WalkmanFont.callout)
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
                                .font(.system(size: 11))
                            Text("Play Hi-Res Queue")
                                .font(WalkmanFont.calloutBold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: WalkmanTheme.hiResGold.opacity(0.3), radius: 4, x: 0, y: 1)
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
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search Hi-Res titles...", text: $searchQuery)
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
                .frame(maxWidth: 290)
                
                Picker("", selection: $minBitsFilter) {
                    Text("24-bit Studio Masters").tag(24)
                    Text("All Hi-Res (>16-bit)").tag(16)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Spacer()
                
                Text("\(filteredTracks.count) Studio Master Tracks")
                    .font(WalkmanFont.mono)
                    .foregroundStyle(WalkmanTheme.hiResGoldLight)
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
                                TrackCoverThumbnail(track: track, size: 38, isPlaying: isPlayingThis)
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2.5) {
                                HStack(spacing: 6) {
                                    Text(track.title)
                                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                        .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGoldLight : .white)
                                        .lineLimit(1)
                                    
                                    Text("\(track.bitsPerSample)-bit / \(track.sampleRate / 1000)kHz")
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(WalkmanTheme.hiResGold.opacity(0.18))
                                        .foregroundStyle(WalkmanTheme.hiResGoldLight)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(WalkmanTheme.hiResGold.opacity(0.4), lineWidth: 0.6)
                                        )
                                        .clipShape(Capsule())
                                }
                                
                                Text("\(track.artist) — \(track.album)")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text("\(track.bitrateKbps) kbps")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                            
                            Text(track.format)
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.10))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            
                            Text(formatDuration(track.durationSeconds))
                                .font(WalkmanFont.mono)
                                .foregroundStyle(.secondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
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
                        .contextMenu {
                            Button("Play Track") {
                                player.play(track: track, in: filteredTracks)
                            }
                            Divider()
                            Button {
                                onEditTrack?(track)
                            } label: {
                                Label("Edit Song Metadata...", systemImage: "square.and.pencil")
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
                .padding(14)
            }
        }
    }
}
