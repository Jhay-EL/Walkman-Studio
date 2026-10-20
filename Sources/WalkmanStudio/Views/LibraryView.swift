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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search title, artist, or album...", text: $searchQuery)
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
                
                // Format Filters
                Picker("", selection: $formatFilter) {
                    Text("All Formats").tag("ALL")
                    Text("FLAC").tag("FLAC")
                    Text("MP3").tag("MP3")
                    Text("Hi-Res (>16bit)").tag("HI-RES")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading library...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(filteredTracks.count.formatted()) tracks")
                        .font(.system(size: 11, design: .monospaced))
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
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Tracks on Selected Volume")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Drag and drop audio files into Transfer & Convert to sync to your Walkman.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    
                    Button("Go to Transfer Queue") {
                        onGoToTransfer()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(WalkmanTheme.goldGradient)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
                    TableColumn("#", value: \.trackNum) { track in
                        Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 28, ideal: 36, max: 46)
                    
                    TableColumn("Title", value: \.title) { track in
                        let isCurrent = player.currentTrack?.id == track.id
                        let isPlayingThis = isCurrent && player.isPlaying
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                if isPlayingThis {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: filteredTracks)
                                }
                            }) {
                                TrackCoverThumbnail(track: track, size: 24, isPlaying: isPlayingThis)
                            }
                            .buttonStyle(.plain)
                            .help(isPlayingThis ? "Pause" : "Play preview")
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 11, weight: isPlayingThis ? .bold : .medium))
                                    .foregroundStyle(isPlayingThis ? WalkmanTheme.gold : .primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 160, ideal: 240)
                    
                    TableColumn("Artist", value: \.artist) { track in
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 150)
                    
                    TableColumn("Album", value: \.album) { track in
                        Text(track.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 170)
                    
                    TableColumn("Format", value: \.format) { track in
                        HStack(spacing: 4) {
                            Text(track.format)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isHiRes(track) ? WalkmanTheme.gold.opacity(0.18) : (track.format == "FLAC" ? WalkmanTheme.gold.opacity(0.12) : Color.white.opacity(0.06)))
                                .foregroundStyle(isHiRes(track) ? WalkmanTheme.gold : (track.format == "FLAC" ? WalkmanTheme.gold : .secondary))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            
                            if isHiRes(track) {
                                Text("Hi-Res")
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(WalkmanTheme.gold)
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                    .width(min: 65, ideal: 85, max: 100)
                    
                    TableColumn("Duration", value: \.durationSeconds) { track in
                        Text(formatDuration(track.durationSeconds))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 55, ideal: 65, max: 80)
                    
                    TableColumn("Bitrate", value: \.bitrateKbps) { track in
                        Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .width(min: 55, ideal: 65, max: 80)
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
                }
            }
        }
    }
}
