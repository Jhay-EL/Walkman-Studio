import SwiftUI
import AppKit

public struct RankedTrack: Identifiable, Sendable {
    public let rank: Int
    public let track: Track
    public let formattedDate: String
    public let formattedDuration: String
    public let isHiRes: Bool
    
    public var id: String { track.id }
    public var title: String { track.title }
    public var artist: String { track.artist }
    public var album: String { track.album }
    public var format: String { track.format }
    public var dateAdded: Date { track.dateAdded }
    public var durationSeconds: Double { track.durationSeconds }
}

public struct RecentlyAddedView: View {
    let tracks: [Track]
    let isLoading: Bool
    @Binding var selectedTrackId: String?
    let onInspectTrack: (Track) -> Void
    let onGoToTransfer: () -> Void
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery: String = ""
    @State private var timeframeFilter: TimeframeFilter = .all
    @State private var formatFilter: String = "ALL"
    @State private var sortOrder = [KeyPathComparator(\RankedTrack.dateAdded, order: .reverse)]
    
    @State private var displayedTracks: [RankedTrack] = []
    @State private var currentPlaybackQueue: [Track] = []
    
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
        onGoToTransfer: @escaping () -> Void,
        onDeleteTrack: ((Track) -> Void)? = nil,
        onEditTrack: ((Track) -> Void)? = nil,
        onTrimCutTrack: ((Track) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.isLoading = isLoading
        self._selectedTrackId = selectedTrackId
        self.onInspectTrack = onInspectTrack
        self.onGoToTransfer = onGoToTransfer
        self.onDeleteTrack = onDeleteTrack
        self.onEditTrack = onEditTrack
        self.onTrimCutTrack = onTrimCutTrack
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
    
    private func formatDateAdded(_ date: Date, now: Date) -> String {
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
    
    private func recomputeDisplayedTracks(newSortOrder: [KeyPathComparator<RankedTrack>]? = nil) {
        let activeSortOrder = newSortOrder ?? sortOrder
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
            } else if formatFilter == "LEARNING" {
                if !track.isLanguageStudy { return false }
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
        
        var items: [RankedTrack] = []
        items.reserveCapacity(filtered.count)
        
        for (index, track) in filtered.enumerated() {
            let fDate = formatDateAdded(track.dateAdded, now: now)
            let fDuration = formatDuration(track.durationSeconds)
            let hiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
            items.append(RankedTrack(
                rank: index + 1,
                track: track,
                formattedDate: fDate,
                formattedDuration: fDuration,
                isHiRes: hiRes
            ))
        }
        
        let sorted = items.sorted(using: activeSortOrder)
        let reindexed: [RankedTrack] = sorted.enumerated().map { (idx, item) in
            RankedTrack(
                rank: idx + 1,
                track: item.track,
                formattedDate: item.formattedDate,
                formattedDuration: item.formattedDuration,
                isHiRes: item.isHiRes
            )
        }
        
        self.displayedTracks = reindexed
        self.currentPlaybackQueue = reindexed.map(\.track)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
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
                    Text("M4A").tag("M4A")
                    Text("Language Study").tag("LEARNING")
                    Text("Hi-Res").tag("HI-RES")
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
                
                Spacer()
                
                Text("\(displayedTracks.count.formatted()) tracks")
                    .font(WalkmanFont.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if !displayedTracks.isEmpty {
                    Button(action: {
                        if let first = currentPlaybackQueue.first {
                            player.play(track: first, in: currentPlaybackQueue)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text("Play Recent Queue")
                                .font(WalkmanFont.calloutBold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            // Content Table
            if displayedTracks.isEmpty && !isLoading {
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
                Table(displayedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
                    TableColumn("#", value: \.rank) { item in
                        Text("\(item.rank)")
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 30, ideal: 36, max: 48)
                    
                    TableColumn("Title", value: \.title) { item in
                        let track = item.track
                        let isCurrent = player.currentTrack?.id == track.id
                        let isPlayingThis = isCurrent && player.isPlaying
                        
                        HStack(spacing: 9) {
                            Button(action: {
                                if isPlayingThis {
                                    player.pause()
                                } else {
                                    player.play(track: track, in: currentPlaybackQueue)
                                }
                            }) {
                                TrackCoverThumbnail(track: track, size: 28, isPlaying: isPlayingThis)
                            }
                            .buttonStyle(.plain)
                            .help(isPlayingThis ? "Pause" : "Play preview")
                            
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(track.title)
                                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                        .foregroundStyle(isPlayingThis ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    if track.isLanguageStudy {
                                        Image(systemName: "character.book.closed.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                            .help("Language Study & Audiobooks (/LEARNING/)")
                                    }
                                }
                            }
                        }
                    }
                    .width(min: 170, ideal: 240)
                    
                    TableColumn("Artist", value: \.artist) { item in
                        Text(item.artist)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 150)
                    
                    TableColumn("Album", value: \.album) { item in
                        Text(item.album)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 170)
                    
                    TableColumn("Format", value: \.format) { item in
                        HStack(spacing: 4) {
                            Text(item.format)
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(item.isHiRes ? WalkmanTheme.hiResGold.opacity(0.14) : Color.white.opacity(0.06))
                                .foregroundStyle(item.isHiRes ? WalkmanTheme.hiResGold : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            
                            if item.isHiRes {
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
                    
                    TableColumn("Date Added", value: \.dateAdded) { item in
                        Text(item.formattedDate)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 110, ideal: 130, max: 160)
                    
                    TableColumn("Duration", value: \.durationSeconds) { item in
                        Text(item.formattedDuration)
                            .font(WalkmanFont.mono)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 70, max: 80)
                }
                .contextMenu(forSelectionType: RankedTrack.ID.self) { items in
                    if let id = items.first, let item = displayedTracks.first(where: { $0.id == id }) {
                        Button("Play") {
                            player.play(track: item.track, in: currentPlaybackQueue)
                        }
                        Divider()
                        Button {
                            onEditTrack?(item.track)
                        } label: {
                            Label("Edit Song Metadata...", systemImage: "square.and.pencil")
                        }
                        Button {
                            onTrimCutTrack?(item.track)
                        } label: {
                            Label("Trim & Cut...", systemImage: "scissors")
                        }
                        Button {
                            ArtworkExportService.exportArtwork(for: item.track)
                        } label: {
                            Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                        }
                        Button("Inspect in Sidebar") {
                            onInspectTrack(item.track)
                        }
                        Divider()
                        Button(role: .destructive) {
                            let targets = displayedTracks.filter { items.contains($0.id) }
                            let toDelete = targets.isEmpty ? [item] : targets
                            let idsToDelete = Set(toDelete.map { $0.id })
                            displayedTracks.removeAll(where: { idsToDelete.contains($0.id) })
                            if let sel = selectedTrackId, idsToDelete.contains(sel) {
                                selectedTrackId = nil
                            }
                            for r in toDelete {
                                onDeleteTrack?(r.track)
                            }
                        } label: {
                            Label(items.count > 1 ? "Delete \(items.count) Songs from Device" : "Delete from Device", systemImage: "trash")
                        }
                    }
                } primaryAction: { items in
                    if let id = items.first, let item = displayedTracks.first(where: { $0.id == id }) {
                        if player.currentTrack?.id == item.track.id && player.isPlaying {
                            player.pause()
                        } else {
                            player.play(track: item.track, in: currentPlaybackQueue)
                        }
                    }
                }
            }
        }
        .onAppear {
            recomputeDisplayedTracks()
        }
        .onChange(of: tracks) {
            recomputeDisplayedTracks()
        }
        .onChange(of: searchQuery) {
            recomputeDisplayedTracks()
        }
        .onChange(of: timeframeFilter) {
            recomputeDisplayedTracks()
        }
        .onChange(of: formatFilter) {
            recomputeDisplayedTracks()
        }
        .onChange(of: sortOrder) {
            recomputeDisplayedTracks()
        }
    }
}
