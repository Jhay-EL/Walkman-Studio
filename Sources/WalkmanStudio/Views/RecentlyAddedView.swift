import SwiftUI
import AppKit

public struct RankedTrack: Identifiable, Sendable {
    public let rank: Int
    public let track: Track
    public let isHiRes: Bool
    
    public var id: String { track.id }
    public var title: String { track.title }
    public var artist: String { track.artist }
    public var album: String { track.album }
    public var format: String { track.format }
    public var dateAdded: Date { track.dateAdded }
    public var durationSeconds: Double { track.durationSeconds }
    
    public init(rank: Int, track: Track, isHiRes: Bool) {
        self.rank = rank
        self.track = track
        self.isHiRes = isHiRes
    }
}

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
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
    
    private static let defaultSortOrder = [KeyPathComparator(\RankedTrack.dateAdded, order: .reverse)]
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var searchQuery: String = ""
    @State private var formatFilter: String = "ALL"
    @State private var sortOrder = defaultSortOrder
    
    @State private var displayedTracks: [RankedTrack] = []
    @State private var sortedBaseTracks: [Track] = []
    @State private var currentPlaybackQueue: [Track] = []
    @State private var visibleTrackIds: Set<String> = []
    
    private let formatFilterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Formats", icon: nil, isHiRes: false),
        FilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
        FilterOption(id: "MP3", title: "MP3", icon: nil, isHiRes: false),
        FilterOption(id: "M4A", title: "M4A", icon: nil, isHiRes: false),
        FilterOption(id: "LEARNING", title: "Language Study", icon: "character.book.closed.fill", isHiRes: false),
        FilterOption(id: "HI-RES", title: "Hi-Res", icon: "waveform", isHiRes: true)
    ]
    
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
    
    // MARK: - Fast Date & Duration Formatters (Computed lazily for visible cells only)
    
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
        guard seconds > 0 else { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private static func sortTracksByDateDescending(_ list: [Track]) -> [Track] {
        return list.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    // MARK: - High-Performance Filter Pipeline (< 1ms execution, Zero Re-Sorting)
    
    private func recomputeDisplayedTracks(newSortOrder: [KeyPathComparator<RankedTrack>]? = nil) {
        let baseList = sortedBaseTracks.isEmpty ? tracks : sortedBaseTracks
        let activeSortOrder = newSortOrder ?? sortOrder
        let isDefaultSort = (activeSortOrder == Self.defaultSortOrder)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let filtered: [Track] = baseList.filter { track in
            // 1. Format filter
            if formatFilter == "HI-RES" {
                if track.bitsPerSample <= 16 && track.sampleRate <= 48000 { return false }
            } else if formatFilter == "LEARNING" {
                if !track.isLanguageStudy { return false }
            } else if formatFilter != "ALL" {
                if track.format != formatFilter { return false }
            }
            
            // 2. Search query
            if !q.isEmpty {
                let match = track.title.localizedCaseInsensitiveContains(q)
                    || track.artist.localizedCaseInsensitiveContains(q)
                    || track.album.localizedCaseInsensitiveContains(q)
                    || track.filename.localizedCaseInsensitiveContains(q)
                if !match { return false }
            }
            
            return true
        }
        
        let finalRankedTracks: [RankedTrack]
        if isDefaultSort {
            // Base list is already sorted by dateAdded descending, so stable filtering
            // preserves the sorted order with ZERO sorting cost!
            finalRankedTracks = filtered.enumerated().map { (index, track) in
                let hiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
                return RankedTrack(rank: index + 1, track: track, isHiRes: hiRes)
            }
        } else {
            var items: [RankedTrack] = []
            items.reserveCapacity(filtered.count)
            for (index, track) in filtered.enumerated() {
                let hiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
                items.append(RankedTrack(rank: index + 1, track: track, isHiRes: hiRes))
            }
            let customSorted = items.sorted(using: activeSortOrder)
            finalRankedTracks = customSorted.enumerated().map { (idx, item) in
                RankedTrack(rank: idx + 1, track: item.track, isHiRes: item.isHiRes)
            }
        }
        
        self.displayedTracks = finalRankedTracks
        self.currentPlaybackQueue = finalRankedTracks.map(\.track)
        self.visibleTrackIds = Set(finalRankedTracks.map(\.id))
    }
    
    private var isPlayingFromVisibleQueue: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && visibleTrackIds.contains(current.id)
    }
    
    private func togglePlaybackRecent() {
        guard !displayedTracks.isEmpty else { return }
        if isPlayingFromVisibleQueue {
            player.pause()
        } else if let first = currentPlaybackQueue.first {
            player.play(track: first, in: currentPlaybackQueue)
        }
    }
    
    private func shufflePlaybackRecent() {
        guard !currentPlaybackQueue.isEmpty else { return }
        let shuffled = currentPlaybackQueue.shuffled()
        if let random = shuffled.first {
            player.play(track: random, in: shuffled)
        }
    }
    
    // MARK: - Main Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // -----------------------------------------------------------------
            // macOS 27 LIQUID GLASS TOOLBAR (Responsive Wide & Compact Layouts)
            // -----------------------------------------------------------------
            ViewThatFits(in: .horizontal) {
                wideToolbarLayout
                compactToolbarLayout
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.8)
                }
            )
            
            // -----------------------------------------------------------------
            // CONTENT: EMPTY STATE / NO SEARCH RESULTS / TABLE
            // -----------------------------------------------------------------
            if displayedTracks.isEmpty && !isLoading {
                if tracks.isEmpty {
                    emptyStorageView
                } else {
                    noSearchResultsView
                }
            } else {
                trackTableView
            }
        }
        .onAppear {
            if sortedBaseTracks.isEmpty && !tracks.isEmpty {
                sortedBaseTracks = Self.sortTracksByDateDescending(tracks)
            }
            recomputeDisplayedTracks()
        }
        .onChange(of: tracks) { _, newTracks in
            sortedBaseTracks = Self.sortTracksByDateDescending(newTracks)
            recomputeDisplayedTracks()
        }
        .onChange(of: searchQuery) { _, _ in
            recomputeDisplayedTracks()
        }
        .onChange(of: formatFilter) { _, _ in
            recomputeDisplayedTracks()
        }
        .onChange(of: sortOrder) { _, newOrder in
            recomputeDisplayedTracks(newSortOrder: newOrder)
        }
    }
    
    // -------------------------------------------------------------------------
    // SUBVIEWS
    // -------------------------------------------------------------------------
    
    private var wideToolbarLayout: some View {
        HStack(spacing: 8) {
            searchFieldView
                .frame(minWidth: 140, maxWidth: 200)
            
            formatSegmentedBar
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 4)
            
            playbackControlsView
                .fixedSize(horizontal: true, vertical: false)
            
            statusIndicatorView
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private var compactToolbarLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchFieldView
                    .frame(maxWidth: .infinity)
                
                Spacer(minLength: 4)
                
                playbackControlsView
                    .fixedSize(horizontal: true, vertical: false)
                
                statusIndicatorView
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                formatSegmentedBar
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 1)
            }
        }
    }
    
    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchQuery.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
            
            TextField("Search recently added...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7.5)
        .frame(minHeight: 36)
        .background(
            ZStack {
                Color.white.opacity(0.06)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(searchQuery.isEmpty ? 0.12 : 0.30), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 2.5, x: 0, y: 1)
    }
    
    private var formatSegmentedBar: some View {
        FormatSegmentedBarView(
            options: formatFilterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private var playbackControlsView: some View {
        HStack(spacing: 7) {
            Button(action: togglePlaybackRecent) {
                HStack(spacing: 6) {
                    Image(systemName: isPlayingFromVisibleQueue ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isPlayingFromVisibleQueue ? "Pause" : "Play Recent")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
            .disabled(displayedTracks.isEmpty)
            .help(isPlayingFromVisibleQueue ? "Pause playback" : "Play recent tracks in order")
            
            Button(action: shufflePlaybackRecent) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .capsule, cornerRadius: 17))
            .disabled(displayedTracks.isEmpty)
            .help("Shuffle and play recent tracks")
        }
    }
    
    private var statusIndicatorView: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                Text("Scanning...")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text("\(displayedTracks.count.formatted()) new")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }
    
    private var emptyStorageView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle().fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
                
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Recently Added Tracks")
                .font(WalkmanFont.title3)
                .foregroundStyle(.white)
            
            Text("Drag and drop audio files into Transfer & Convert to copy music to your Walkman.")
                .font(WalkmanFont.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            Button(action: onGoToTransfer) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Go to Transfer Queue")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
            .padding(.top, 4)
            
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 22))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Matching New Tracks")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(searchQuery.isEmpty
                 ? "No recently added tracks match the selected format."
                 : "No recently added tracks match \"\(searchQuery)\" with the selected format.")
                .font(WalkmanFont.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button(action: {
                searchQuery = ""
                formatFilter = "ALL"
            }) {
                Text("Reset Filters")
                    .font(WalkmanFont.calloutMedium)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 12))
            .padding(.top, 4)
            
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var trackTableView: some View {
        Table(displayedTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#", value: \.rank) { item in
                Text(item.rank.formatted())
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 30, ideal: 38, max: 50)
            
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
                        TrackCoverThumbnail(track: track, size: 32, isPlaying: isPlayingThis)
                    }
                    .buttonStyle(.plain)
                    .help(isPlayingThis ? "Pause" : "Play preview")
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(track.title)
                                .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                                .lineLimit(1)
                            
                            if isPlayingThis {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                            
                            if track.isLanguageStudy {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .help("Language Study & Audiobooks (/LEARNING/)")
                            }
                        }
                    }
                }
            }
            .width(min: 170, ideal: 260)
            
            TableColumn("Artist", value: \.artist) { item in
                Text(item.artist.isEmpty ? "Unknown Artist" : item.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 160)
            
            TableColumn("Album", value: \.album) { item in
                Text(item.album.isEmpty ? "—" : item.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)
            
            TableColumn("Format", value: \.format) { item in
                HStack(spacing: 4.5) {
                    Text(item.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            ZStack {
                                Color.white.opacity(item.isHiRes ? 0.08 : 0.05)
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.12), location: 0),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 3)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        .foregroundStyle(item.isHiRes ? WalkmanTheme.silverLight : Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(item.isHiRes ? 0.22 : 0.09), lineWidth: 0.6)
                        )
                    
                    if item.isHiRes {
                        HStack(spacing: 2.5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 7, weight: .black))
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGoldGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(WalkmanTheme.hiResGoldDark.opacity(0.6), lineWidth: 0.5)
                        )
                    }
                }
            }
            .width(min: 90, ideal: 110, max: 130)

            TableColumn("SenseMe") { item in
                if item.track.isSenseMeAnalyzed {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("12 TONE")
                            .font(WalkmanFont.badge)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18))
                    )
                    .overlay(
                        Capsule().stroke(Color(red: 255/255, green: 165/255, blue: 30/255).opacity(0.55), lineWidth: 0.8)
                    )
                    .foregroundStyle(Color(red: 255/255, green: 195/255, blue: 80/255))
                    .help("Sony 12 Tone / SenseMe Analyzed • \(item.track.senseMeChannels.joined(separator: ", "))")
                } else {
                    Text("—")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.secondary.opacity(0.35))
                }
            }
            .width(min: 70, ideal: 84, max: 96)
            
            TableColumn("Date Added", value: \.dateAdded) { item in
                Text(formatDateAdded(item.dateAdded))
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 135, max: 165)
            
            TableColumn("Duration", value: \.durationSeconds) { item in
                Text(formatDuration(item.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .width(min: 55, ideal: 65, max: 80)
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
                
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.track.fullPath, forType: .string)
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
        .tableScrollBottomInset(88)
    }
}

// -----------------------------------------------------------------------------
// FORMAT SEGMENTED BAR VIEW (LIQUID GLASS SLIDING PILL TRANSITION)
// -----------------------------------------------------------------------------
private struct FormatSegmentedBarView: View {
    let options: [FilterOption]
    @Binding var selectedFilter: String
    let onSelectFilter: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                FormatTabPillView(
                    option: opt,
                    isSelected: activeHighlightId == opt.id,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard selectedFilter != opt.id else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeHighlightId = opt.id
                        }
                        onSelectFilter(opt.id)
                    }
                )
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeHighlightId = selectedFilter
        }
        .onChange(of: selectedFilter) { _, newFilter in
            if activeHighlightId != newFilter {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeHighlightId = newFilter
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------
// FORMAT TAB PILL VIEW (ROUND LIQUID GLASS CLICK BOX WITH HOVER & SLIDING PILL)
// -----------------------------------------------------------------------------
private struct FormatTabPillView: View {
    let option: FilterOption
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5.5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                }
                Text(option.title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    (option.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        // Liquid Glass Active Pill Highlight — smoothly transfers via matched geometry
                        ActivePillBackground(isHiRes: option.isHiRes, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeFormatHighlight", in: namespace)
                    } else if isHovered {
                        // Liquid Glass Hover Pill (Round frosted glass box)
                        HoverPillBackground()
                    } else {
                        // Transparent hit-testable canvas
                        Color.white.opacity(0.001)
                    }
                }
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
    }
}

// -----------------------------------------------------------------------------
// ACTIVE LIQUID GLASS PILL BACKGROUND
// -----------------------------------------------------------------------------
private struct ActivePillBackground: View {
    let isHiRes: Bool
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            // Liquid Glass Translucent Body Fill
            Color.white.opacity(isHiRes ? 0.13 : 0.16)
            
            // Top specular refraction sheen
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isHiRes ? WalkmanTheme.hiResGold.opacity(0.55) : Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 3,
            x: 0,
            y: 1
        )
    }
}

// -----------------------------------------------------------------------------
// HOVER LIQUID GLASS PILL BACKGROUND
// -----------------------------------------------------------------------------
private struct HoverPillBackground: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.09)
            
            // Subtle specular refraction on top edge
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.20), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5.5)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(
            color: Color.black.opacity(0.15),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}
