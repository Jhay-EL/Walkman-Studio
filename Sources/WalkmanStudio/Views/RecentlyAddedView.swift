import SwiftUI
import AppKit

public struct RecentlyAddedView: View {
    let tracks: [Track]
    let isLoading: Bool
    @Binding var selectedTrackId: String?
    let onInspectTrack: (Track) -> Void
    let onGoToTransfer: () -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery: String = ""
    @State private var timeframeFilter: TimeframeFilter = .all
    @State private var formatFilter: String = "ALL"
    @State private var sortOrder = [KeyPathComparator(\Track.dateAdded, order: .reverse)]
    
    public enum TimeframeFilter: String, CaseIterable, Identifiable {
        case all = "All Newest"
        case days30 = "Last 30 Days"
        case days7 = "Last 7 Days"
        
        public var id: String { rawValue }
    }
    
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
        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        
        let filtered = tracks.filter { track in
            // Timeframe filter
            switch timeframeFilter {
            case .all:
                break
            case .days30:
                if track.dateAdded < thirtyDaysAgo { return false }
            case .days7:
                if track.dateAdded < sevenDaysAgo { return false }
            }
            
            // Format filter
            if formatFilter == "HI-RES" {
                if track.bitsPerSample <= 16 && track.sampleRate <= 48000 { return false }
            } else if formatFilter != "ALL" {
                if track.format != formatFilter { return false }
            }
            
            // Search query
            if !q.isEmpty {
                let match = track.title.lowercased().contains(q)
                    || track.artist.lowercased().contains(q)
                    || track.album.lowercased().contains(q)
                    || track.filename.lowercased().contains(q)
                if !match { return false }
            }
            
            return true
        }
        
        return filtered.sorted(using: sortOrder)
    }
    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    
    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    
    private func formatDateAdded(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 7 * 86400 && interval >= 0 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        return Self.absoluteFormatter.string(from: date)
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
            // Header Hero Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalkmanTheme.card)
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recently Added")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)
                    
                    Text("Freshly synchronized audio files on your Walkman, ordered by transfer date.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !filteredTracks.isEmpty {
                    Button(action: {
                        if let first = filteredTracks.first {
                            player.play(track: first, in: filteredTracks)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Play Recent Queue")
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
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)
            .padding(14)
            
            // Search & Filter Bar
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search recently added...", text: $searchQuery)
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
                
                // Timeframe Picker
                Picker("", selection: $timeframeFilter) {
                    ForEach(TimeframeFilter.allCases) { tf in
                        Text(tf.rawValue).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                // Format Picker
                Picker("", selection: $formatFilter) {
                    Text("All Formats").tag("ALL")
                    Text("FLAC").tag("FLAC")
                    Text("MP3").tag("MP3")
                    Text("Hi-Res").tag("HI-RES")
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                
                Spacer()
                
                Text("\(filteredTracks.count.formatted()) tracks")
                    .font(WalkmanFont.mono)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            // Content Table
            if filteredTracks.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 38))
                        .foregroundStyle(.tertiary)
                    Text("No Recently Added Tracks")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.secondary)
                    Text(timeframeFilter == .all
                         ? "Drag and drop music into Transfer & Convert to copy songs to your Walkman."
                         : "No songs match the '\(timeframeFilter.rawValue)' filter. Try switching to 'All Newest'.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    
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
                    TableColumn("#") { track in
                        let idx = (filteredTracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
                        Text("\(idx)")
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 30, ideal: 36, max: 48)
                    
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
                    .width(min: 170, ideal: 240)
                    
                    TableColumn("Artist", value: \.artist) { track in
                        Text(track.artist)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 150)
                    
                    TableColumn("Album", value: \.album) { track in
                        Text(track.album)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 170)
                    
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
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1.5)
                                    .background(WalkmanTheme.hiResGoldGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 2.5))
                            }
                        }
                    }
                    .width(min: 90, ideal: 110, max: 125)
                    
                    TableColumn("Date Added", value: \.dateAdded) { track in
                        Text(formatDateAdded(track.dateAdded))
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    
                    TableColumn("Duration", value: \.durationSeconds) { track in
                        Text(formatDuration(track.durationSeconds))
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 70, max: 80)
                }
                .contextMenu(forSelectionType: Track.ID.self) { items in
                    if let id = items.first, let track = tracks.first(where: { $0.id == id }) {
                        Button("Inspect Metadata & Specs") {
                            onInspectTrack(track)
                        }
                        Button("Play") {
                            player.play(track: track, in: filteredTracks)
                        }
                        Divider()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(track.fullPath, inFileViewerRootedAtPath: "")
                        }
                    }
                } primaryAction: { items in
                    if let id = items.first, let track = tracks.first(where: { $0.id == id }) {
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
