import SwiftUI
import AppKit

public struct LibraryView: View {
    let tracks: [Track]
    let isLoading: Bool
    @Binding var selectedTrackId: String?
    let onInspectTrack: (Track) -> Void
    let onGoToTransfer: () -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var formatFilter: String = "ALL"
    @State private var searchQuery: String = ""
    @State private var sortOrder = [KeyPathComparator(\Track.artist), KeyPathComparator(\Track.album), KeyPathComparator(\Track.trackNum)]
    
    public init(
        tracks: [Track],
        isLoading: Bool,
        selectedTrackId: Binding<String?>,
        onInspectTrack: @escaping (Track) -> Void,
        onGoToTransfer: @escaping () -> Void
    ) {
        self.tracks = tracks
        self.isLoading = isLoading
        self._selectedTrackId = selectedTrackId
        self.onInspectTrack = onInspectTrack
        self.onGoToTransfer = onGoToTransfer
    }
    
    private var filteredTracks: [Track] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = tracks.filter { track in
            let matchesSearch = q.isEmpty
                || track.title.lowercased().contains(q)
                || track.artist.lowercased().contains(q)
                || track.album.lowercased().contains(q)
                || track.filename.lowercased().contains(q)
            
            if !matchesSearch { return false }
            
            if formatFilter == "ALL" { return true }
            if formatFilter == "HI-RES" { return track.bitsPerSample > 16 || track.sampleRate > 48000 }
            return track.format == formatFilter
        }
        return filtered.sorted(using: sortOrder)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func isHiRes(_ track: Track) -> Bool {
        return track.bitsPerSample > 16 || track.sampleRate > 48000
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search title, artist, or album...", text: $searchQuery)
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
                
                // Format Filters
                Picker("", selection: $formatFilter) {
                    Text("All Formats").tag("ALL")
                    Text("FLAC").tag("FLAC")
                    Text("MP3").tag("MP3")
                    Text("Hi-Res (>16bit)").tag("HI-RES")
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading library...")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(filteredTracks.count.formatted()) tracks")
                        .font(WalkmanFont.mono)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            // Native macOS Table
            if tracks.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.house")
                        .font(.system(size: 38))
                        .foregroundStyle(.tertiary)
                    Text("No Tracks on Selected Volume")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.secondary)
                    Text("Drag and drop audio files into Transfer & Convert to sync to your Walkman.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.tertiary)
                    
                    Button("Go to Transfer Queue") {
                        onGoToTransfer()
                    }
                    .font(WalkmanFont.calloutMedium)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
                    TableColumn("#", value: \.trackNum) { track in
                        Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 30, ideal: 38, max: 50)
                    
                    TableColumn("Title", value: \.title) { track in
                        let isCurrent = player.currentTrack?.id == track.id
                        let isPlayingThis = isCurrent && player.isPlaying
                        
                        HStack(spacing: 9) {
                            Button(action: {
                                if isPlayingThis {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: filteredTracks)
                                }
                            }) {
                                TrackCoverThumbnail(track: track, size: 28, isPlaying: isPlayingThis)
                            }
                            .buttonStyle(.plain)
                            .help(isPlayingThis ? "Pause" : "Play preview")
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                    .foregroundStyle(isPlayingThis ? .white : .primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 170, ideal: 260)
                    
                    TableColumn("Artist", value: \.artist) { track in
                        Text(track.artist)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 160)
                    
                    TableColumn("Album", value: \.album) { track in
                        Text(track.album)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)
                    
                    TableColumn("Format", value: \.format) { track in
                        HStack(spacing: 4) {
                            Text(track.format)
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(isHiRes(track) ? WalkmanTheme.hiResGold.opacity(0.14) : Color.white.opacity(0.06))
                                .foregroundStyle(isHiRes(track) ? WalkmanTheme.hiResGold : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            
                            if isHiRes(track) {
                                Text("Hi-Res")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(WalkmanTheme.hiResGoldGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                            }
                        }
                    }
                    .width(min: 75, ideal: 95, max: 115)
                    
                    TableColumn("Duration", value: \.durationSeconds) { track in
                        Text(formatDuration(track.durationSeconds))
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 72, max: 90)
                    
                    TableColumn("Bitrate", value: \.bitrateKbps) { track in
                        Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "—")
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.tertiary)
                    }
                    .width(min: 60, ideal: 72, max: 90)
                }
                .contextMenu(forSelectionType: Track.ID.self) { selection in
                    if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId }) {
                        let isThisPlaying = player.currentTrack?.id == track.id && player.isPlaying
                        
                        Button(isThisPlaying ? "Pause Playback" : "Play Preview") {
                            if isThisPlaying {
                                player.pause()
                            } else {
                                player.play(track: track, in: filteredTracks)
                            }
                        }
                        
                        Divider()
                        
                        Button("Inspect & Edit Metadata (Get Info)") {
                            onInspectTrack(track)
                        }
                        
                        Divider()
                        
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.fullPath)])
                        }
                        
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(track.fullPath, forType: .string)
                        }
                    }
                } primaryAction: { selection in
                    if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId }) {
                        if player.currentTrack?.id == track.id && player.isPlaying {
                            player.pause()
                        } else {
                            player.play(track: track, in: filteredTracks)
                        }
                    }
                }
            }
        }
    }
}
