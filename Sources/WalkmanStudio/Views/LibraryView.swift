import SwiftUI
import AppKit

fileprivate struct FilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

public struct LibraryView: View {
    let tracks: [Track]
    let isLoading: Bool
    @Binding var selectedTrackId: String?
    let onInspectTrack: (Track) -> Void
    let onGoToTransfer: () -> Void
    var onDeleteTrack: ((Track) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var onTrimCutTrack: ((Track) -> Void)? = nil
    
    private static let defaultSortOrder = [
        KeyPathComparator(\Track.artist),
        KeyPathComparator(\Track.album),
        KeyPathComparator(\Track.trackNum)
    ]
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var formatFilter: String = "ALL"
    @State private var searchQuery: String = ""
    @State private var sortOrder = defaultSortOrder
    @State private var displayedTracks: [Track] = []
    @State private var sortedBaseTracks: [Track] = []
    @State private var visibleTrackIds: Set<String> = []
    
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
    
    private var visibleTracks: [Track] {
        if displayedTracks.isEmpty && !tracks.isEmpty && searchQuery.isEmpty && formatFilter == "ALL" {
            return sortedBaseTracks.isEmpty ? tracks : sortedBaseTracks
        }
        return displayedTracks
    }
    
    private static func sortTracksDefault(_ list: [Track]) -> [Track] {
        return list.sorted { a, b in
            if a.artist != b.artist { return a.artist < b.artist }
            if a.album != b.album { return a.album < b.album }
            return a.trackNum < b.trackNum
        }
    }
    
    private func recomputeDisplayedTracks(newSortOrder: [KeyPathComparator<Track>]? = nil) {
        let baseList = sortedBaseTracks.isEmpty ? tracks : sortedBaseTracks
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeSort = newSortOrder ?? sortOrder
        let isDefaultSort = (activeSort == Self.defaultSortOrder)
        
        let filtered: [Track]
        if q.isEmpty {
            switch formatFilter {
            case "ALL":
                filtered = baseList
            case "HI-RES":
                filtered = baseList.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
            case "LEARNING":
                filtered = baseList.filter { $0.isLanguageStudy }
            default:
                filtered = baseList.filter { $0.format == formatFilter }
            }
        } else {
            filtered = baseList.filter { track in
                let matchesSearch = track.title.localizedCaseInsensitiveContains(q)
                    || track.artist.localizedCaseInsensitiveContains(q)
                    || track.album.localizedCaseInsensitiveContains(q)
                    || track.filename.localizedCaseInsensitiveContains(q)
                guard matchesSearch else { return false }
                switch formatFilter {
                case "ALL": return true
                case "HI-RES": return track.bitsPerSample > 16 || track.sampleRate > 48000
                case "LEARNING": return track.isLanguageStudy
                default: return track.format == formatFilter
                }
            }
        }
        
        let finalTracks: [Track]
        if isDefaultSort {
            // Because baseList is already sorted by (artist, album, trackNum),
            // stable filtering preserves the sorted order with ZERO sorting cost!
            finalTracks = filtered
        } else {
            finalTracks = filtered.sorted(using: activeSort)
        }
        
        self.displayedTracks = finalTracks
        self.visibleTrackIds = Set(finalTracks.map(\.id))
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
    
    private var isPlayingFromVisibleList: Bool {
        guard let current = player.currentTrack else { return false }
        return player.isPlaying && visibleTrackIds.contains(current.id)
    }
    
    private func togglePlaybackAll() {
        if isPlayingFromVisibleList {
            player.pause()
        } else if let first = visibleTracks.first {
            player.play(track: first, in: visibleTracks)
        }
    }
    
    private func shufflePlaybackAll() {
        guard !visibleTracks.isEmpty else { return }
        let shuffled = visibleTracks.shuffled()
        if let randomTrack = shuffled.first {
            player.play(track: randomTrack, in: shuffled)
        }
    }
    
    private let filterOptions: [FilterOption] = [
        FilterOption(id: "ALL", title: "All Formats", icon: nil, isHiRes: false),
        FilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
        FilterOption(id: "MP3", title: "MP3", icon: nil, isHiRes: false),
        FilterOption(id: "M4A", title: "M4A", icon: nil, isHiRes: false),
        FilterOption(id: "LEARNING", title: "Language Study", icon: "character.book.closed.fill", isHiRes: false),
        FilterOption(id: "HI-RES", title: "Hi-Res", icon: "waveform", isHiRes: true)
    ]
    
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
            if tracks.isEmpty && !isLoading {
                emptyStorageView
            } else if visibleTracks.isEmpty && !isLoading {
                noSearchResultsView
            } else {
                trackTableView
            }
        }
        .onAppear {
            if sortedBaseTracks.isEmpty && !tracks.isEmpty {
                sortedBaseTracks = Self.sortTracksDefault(tracks)
            }
            recomputeDisplayedTracks()
        }
        .onChange(of: tracks) {
            sortedBaseTracks = Self.sortTracksDefault(tracks)
            recomputeDisplayedTracks()
        }
        .onChange(of: searchQuery) {
            recomputeDisplayedTracks()
        }
        .onChange(of: formatFilter) {
            recomputeDisplayedTracks()
        }
        .onChange(of: sortOrder) {
            recomputeDisplayedTracks()
        }
    }
    
    // -------------------------------------------------------------------------
    // SUBVIEWS
    // -------------------------------------------------------------------------
    
    private var wideToolbarLayout: some View {
        HStack(spacing: 10) {
            searchFieldView
                .frame(minWidth: 150, maxWidth: 240)
            
            formatSegmentedBar
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 6)
            
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
            
            TextField("Search title, artist, or album...", text: $searchQuery)
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
                // Top specular sheen
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
            options: filterOptions,
            selectedFilter: $formatFilter,
            onSelectFilter: { newFilter in
                formatFilter = newFilter
            }
        )
    }
    
    private var playbackControlsView: some View {
        HStack(spacing: 7) {
            Button(action: togglePlaybackAll) {
                HStack(spacing: 6) {
                    Image(systemName: isPlayingFromVisibleList ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isPlayingFromVisibleList ? "Pause" : "Play All")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
            .disabled(visibleTracks.isEmpty)
            .help(isPlayingFromVisibleList ? "Pause playback" : "Play all visible tracks in order")
            
            Button(action: shufflePlaybackAll) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .capsule, cornerRadius: 17))
            .disabled(visibleTracks.isEmpty)
            .help("Shuffle and play visible tracks")
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
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text("\(visibleTracks.count.formatted()) tracks")
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
                
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Tracks on Selected Storage")
                .font(WalkmanFont.title3)
                .foregroundStyle(.white)
            
            Text("Drag and drop audio files into Transfer & Convert to sync music onto your Walkman.")
                .font(WalkmanFont.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            Button(action: onGoToTransfer) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Go to Transfer & Convert")
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
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            
            Text("No Matching Songs")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            
            Text("No songs match \"\(searchQuery)\" with the selected filter.")
                .font(WalkmanFont.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                searchQuery = ""
                formatFilter = "ALL"
            }) {
                Text("Clear Search & Filters")
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
        Table(visibleTracks, selection: $selectedTrackId, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trackNum) { track in
                Text(track.trackNum.isEmpty ? "—" : track.trackNum)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
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
                            player.play(track: track, in: visibleTracks)
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
            
            TableColumn("Artist", value: \.artist) { track in
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 160)
            
            TableColumn("Album", value: \.album) { track in
                Text(track.album.isEmpty ? "—" : track.album)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)
            
            TableColumn("Format", value: \.format) { track in
                let hiRes = isHiRes(track)
                HStack(spacing: 4.5) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            ZStack {
                                Color.white.opacity(hiRes ? 0.08 : 0.05)
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
                        .foregroundStyle(hiRes ? WalkmanTheme.silverLight : Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(hiRes ? 0.22 : 0.09), lineWidth: 0.6)
                        )
                    
                    if hiRes {
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
                                .stroke(WalkmanTheme.hiResGoldLight.opacity(0.6), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
                    }
                }
            }
            .width(min: 75, ideal: 100, max: 120)
            
            TableColumn("Duration", value: \.durationSeconds) { track in
                Text(formatDuration(track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .width(min: 60, ideal: 72, max: 90)
            
            TableColumn("Bitrate", value: \.bitrateKbps) { track in
                Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "—")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.secondary)
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
                        player.play(track: track, in: visibleTracks)
                    }
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
                    onInspectTrack(track)
                }
                
                Divider()
                
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(track.fullPath, forType: .string)
                }
                
                Divider()
                
                Button(role: .destructive) {
                    let targets = tracks.filter { selection.contains($0.id) }
                    let toDelete = targets.isEmpty ? [track] : targets
                    let idsToDelete = Set(toDelete.map { $0.id })
                    displayedTracks.removeAll(where: { idsToDelete.contains($0.id) })
                    if let sel = selectedTrackId, idsToDelete.contains(sel) {
                        selectedTrackId = nil
                    }
                    for tr in toDelete {
                        onDeleteTrack?(tr)
                    }
                } label: {
                    Label(selection.count > 1 ? "Delete \(selection.count) Songs from Device" : "Delete from Device", systemImage: "trash")
                }
            }
        } primaryAction: { selection in
            if let firstId = selection.first, let track = tracks.first(where: { $0.id == firstId }) {
                if player.currentTrack?.id == track.id && player.isPlaying {
                    player.pause()
                } else {
                    player.play(track: track, in: visibleTracks)
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
                            .matchedGeometryEffect(id: "activeTabHighlight", in: namespace)
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
