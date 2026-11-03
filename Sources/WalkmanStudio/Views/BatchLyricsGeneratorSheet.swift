import SwiftUI
import AppKit

// MARK: - Batch Lyrics Generator Sheet
public struct BatchLyricsGeneratorSheet: View {
    public enum TabContext: Equatable {
        case allSongs
        case recentlyAdded
        case hiRes
        case albums(selectedAlbumName: String?, albumTrackCount: Int)
        case artists(selectedArtistName: String?, artistTrackCount: Int)
    }

    public enum LyricsScope: String, CaseIterable, Identifiable {
        case allInTab = "All Tracks in View"
        case selectedOnly = "Selected Track(s)"
        case contextOnly = "Selected Item"

        public var id: String { rawValue }
    }

    private enum SheetState {
        case configure
        case running
        case completed
    }

    // Input parameters
    let allTracks: [Track]
    let selectedTracks: [Track]
    let tabContext: TabContext
    let onDismiss: () -> Void

    // Configuration State
    @State private var selectedScope: LyricsScope = .allInTab
    @State private var onlyMissingLyrics: Bool = true
    @State private var sheetState: SheetState = .configure

    // Progress State
    @State private var totalTracksToProcess: Int = 0
    @State private var processedCount: Int = 0
    @State private var syncedCount: Int = 0
    @State private var plainCount: Int = 0
    @State private var skippedCount: Int = 0
    @State private var notFoundCount: Int = 0
    @State private var currentTrackTitle: String = ""
    @State private var currentTrackArtist: String = ""
    @State private var currentTrackStage: String = ""
    @State private var etaString: String = "Estimating..."
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var startTime: Date? = nil

    // Hover states for buttons
    @State private var isPrimaryHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    public init(
        allTracks: [Track],
        selectedTracks: [Track],
        tabContext: TabContext = .allSongs,
        onDismiss: @escaping () -> Void
    ) {
        self.allTracks = allTracks
        self.selectedTracks = selectedTracks
        self.tabContext = tabContext
        self.onDismiss = onDismiss

        // Initial default scope
        if !selectedTracks.isEmpty {
            _selectedScope = State(initialValue: .selectedOnly)
        } else {
            switch tabContext {
            case .albums(let name, _):
                _selectedScope = State(initialValue: name != nil ? .contextOnly : .allInTab)
            case .artists(let name, _):
                _selectedScope = State(initialValue: name != nil ? .contextOnly : .allInTab)
            default:
                _selectedScope = State(initialValue: .allInTab)
            }
        }
    }

    // MARK: - Computed Target Tracks
    private var candidateTracks: [Track] {
        switch selectedScope {
        case .allInTab:
            return allTracks
        case .selectedOnly:
            return selectedTracks.isEmpty ? allTracks : selectedTracks
        case .contextOnly:
            switch tabContext {
            case .albums(let name, _):
                if let albumName = name {
                    return allTracks.filter { $0.album.localizedCaseInsensitiveCompare(albumName) == .orderedSame }
                }
                return allTracks
            case .artists(let name, _):
                if let artistName = name {
                    return allTracks.filter { $0.artist.localizedCaseInsensitiveCompare(artistName) == .orderedSame }
                }
                return allTracks
            default:
                return allTracks
            }
        }
    }

    private var targetTracks: [Track] {
        if onlyMissingLyrics {
            return candidateTracks.filter { track in
                let url = URL(fileURLWithPath: track.fullPath)
                let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
                let upperLrcURL = url.deletingPathExtension().appendingPathExtension("LRC")
                let hasLrcFile = FileManager.default.fileExists(atPath: lrcURL.path) || FileManager.default.fileExists(atPath: upperLrcURL.path)
                if hasLrcFile { return false }
                return AudioTagger.shared.extractLyrics(fileURL: url) == nil
            }
        } else {
            return candidateTracks
        }
    }

    private var tracksWithLyricsCount: Int {
        candidateTracks.count - targetTracks.count
    }

    private var isOver100Tracks: Bool {
        candidateTracks.count > 100
    }

    private var currentProgress: Double {
        guard totalTracksToProcess > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedCount) / Double(totalTracksToProcess)))
    }

    // MARK: - Body View
    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar with Close Button
            HStack {
                Spacer()
                SheetCloseButton(action: {
                    cancelAndDismiss()
                })
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)
            .frame(height: 36)

            // Header Section
            headerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Body Content based on State
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    switch sheetState {
                    case .configure:
                        configurationContent
                    case .running:
                        runningProgressContent
                    case .completed:
                        completedSummaryContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Section
            footerActionsSection
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 650, height: 580)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.92)
                    .background(.ultraThinMaterial)

                // Top specular refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 235/255, green: 240/255, blue: 255/255), location: 0.0),
                                .init(color: Color(red: 175/255, green: 195/255, blue: 235/255), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.40), lineWidth: 0.85)
                    )

                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
            }
            .shadow(color: Color.black.opacity(0.30), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(sheetTitle)
                        .font(WalkmanFont.title1)
                        .foregroundStyle(.primary)

                    if sheetState == .configure {
                        Text("\(candidateTracks.count) Tracks in Scope")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                Text(sheetSubtitle)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var sheetTitle: String {
        switch sheetState {
        case .configure:
            return "Generate Walkman Lyrics"
        case .running:
            return "Fetching Online Lyrics"
        case .completed:
            return "Lyrics Generation Complete"
        }
    }

    private var sheetSubtitle: String {
        switch sheetState {
        case .configure:
            return "Batch search public music databases for synchronized .LRC lyrics and sync them directly to your Sony Walkman storage."
        case .running:
            return "Parallel multi-track fetching active. Searching LRCLIB and Lyrics.ovh for timestamped .LRC lyrics..."
        case .completed:
            return "Finished scanning and saving lyrics companion files to your Walkman library."
        }
    }

    // MARK: - Configure View
    private var configurationContent: some View {
        VStack(spacing: 16) {
            // Explanation card
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.85))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("How Walkman Studio Lyrics Work")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text("This tool queries online databases (preferring timestamped synchronized .LRC from LRCLIB, with Lyrics.ovh as fallback) and creates companion .lrc files alongside your music files. The Sony Walkman OS and Android Walkman Music Player automatically read companion .lrc files during playback.")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 0.85)
            )

            // Over 100 Tracks Advisory Notice
            if isOver100Tracks {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Large Library Notice")
                                .font(WalkmanFont.calloutBold)
                                .foregroundStyle(Color.orange)

                            Text("(\(candidateTracks.count) Tracks)")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverLight)
                        }

                        Text("Fetching lyrics for over 100 tracks involves individual API searches and may take several minutes. Walkman Studio uses parallel multi-worker concurrent requests (5 simultaneous threads) to maximize performance while adhering to public API limits.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverLight.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 0.85)
                )
            }

            // Scope Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("GENERATION SCOPE")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    scopeOptionRow(
                        title: "All Tracks in View",
                        subtitle: "\(allTracks.count) tracks in the current library tab",
                        scope: .allInTab
                    )

                    if !selectedTracks.isEmpty {
                        scopeOptionRow(
                            title: "Selected Track\(selectedTracks.count > 1 ? "s" : "") Only",
                            subtitle: "\(selectedTracks.count) currently selected audio track\(selectedTracks.count > 1 ? "s" : "")",
                            scope: .selectedOnly
                        )
                    }

                    switch tabContext {
                    case .albums(let name, let count):
                        if let albumName = name {
                            scopeOptionRow(
                                title: "Selected Album: \(albumName)",
                                subtitle: "\(count) tracks in this album",
                                scope: .contextOnly
                            )
                        }
                    case .artists(let name, let count):
                        if let artistName = name {
                            scopeOptionRow(
                                title: "Selected Artist: \(artistName)",
                                subtitle: "\(count) tracks by this artist",
                                scope: .contextOnly
                            )
                        }
                    default:
                        EmptyView()
                    }
                }
            }

            // Filter Toggles
            VStack(alignment: .leading, spacing: 8) {
                Text("OPTIMIZATION & CACHE")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 8) {
                    Toggle(isOn: $onlyMissingLyrics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Only fetch for tracks missing lyrics (Recommended)")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(WalkmanTheme.silverLight)
                            Text(onlyMissingLyrics
                                 ? "Skips \(tracksWithLyricsCount) tracks that already have .LRC files; generates for \(targetTracks.count) tracks."
                                 : "Will re-fetch and overwrite lyrics for all \(candidateTracks.count) tracks.")
                                .font(WalkmanFont.caption)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                }
            }
        }
    }

    private func scopeOptionRow(title: String, subtitle: String, scope: LyricsScope) -> some View {
        Button(action: {
            selectedScope = scope
        }) {
            HStack(spacing: 12) {
                Image(systemName: selectedScope == scope ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedScope == scope ? Color.white : WalkmanTheme.silverMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                    Text(subtitle)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(12)
            .background(
                ZStack {
                    if selectedScope == scope {
                        Color.white.opacity(0.08)
                    } else {
                        Color.white.opacity(0.03)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selectedScope == scope ? Color.white.opacity(0.25) : Color.white.opacity(0.06), lineWidth: 0.85)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Running View
    private var runningProgressContent: some View {
        VStack(spacing: 20) {
            // Live Progress Bar & Percent
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.85))

                        let fillWidth = max(8, geo.size.width * CGFloat(currentProgress))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(red: 235/255, green: 240/255, blue: 255/255), location: 0.0),
                                        .init(color: Color(red: 175/255, green: 205/255, blue: 255/255), location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                            .shadow(color: Color.blue.opacity(0.35), radius: 4, x: 0, y: 1)
                    }
                }
                .frame(height: 10)
                .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.80), value: currentProgress)

                HStack {
                    Text("\(processedCount) of \(totalTracksToProcess) tracks")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(etaString)
                    }
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                    Spacer()

                    Text("\(Int(currentProgress * 100))%")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }
            .padding(.top, 10)

            // Current Track Ticker Card
            if !currentTrackTitle.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)

                        Text(currentTrackTitle + (currentTrackArtist.isEmpty ? "" : " • \(currentTrackArtist)"))
                            .font(WalkmanFont.calloutMedium)
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )

                    if !currentTrackStage.isEmpty {
                        Text(currentTrackStage)
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                }
            }

            // Real-Time Stats Chips
            HStack(spacing: 10) {
                metricPill(title: "Synced .LRC", count: syncedCount, color: .green)
                metricPill(title: "Plain Text", count: plainCount, color: .blue)
                metricPill(title: "Skipped", count: skippedCount, color: WalkmanTheme.silverMuted)
                metricPill(title: "Not Found", count: notFoundCount, color: .orange)
            }
            .padding(.top, 8)
        }
    }

    private func metricPill(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.20), lineWidth: 0.85)
        )
    }

    // MARK: - Completed View
    private var completedSummaryContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Color.green.opacity(0.35), lineWidth: 0.85))

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.green)
            }
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Lyrics Batch Complete")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(WalkmanTheme.silverLight)

                Text("Successfully checked \(totalTracksToProcess) tracks in your Walkman Library.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
            }

            // Results Matrix
            HStack(spacing: 10) {
                metricPill(title: "Synced .LRC", count: syncedCount, color: .green)
                metricPill(title: "Plain Text", count: plainCount, color: .blue)
                metricPill(title: "Skipped", count: skippedCount, color: WalkmanTheme.silverMuted)
                metricPill(title: "Not Found", count: notFoundCount, color: .orange)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green.opacity(0.85))
                Text("Hardware companion .LRC files saved with timestamp metadata preserved.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Footer Actions
    private var footerActionsSection: some View {
        HStack(spacing: 12) {
            if sheetState == .configure {
                // Cancel
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 17))
                .keyboardShortcut(.cancelAction)

                Spacer()

                // Generate Button
                Button(action: startGeneration) {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(targetTracks.isEmpty ? "No Tracks to Fetch" : "Generate Lyrics (\(targetTracks.count))")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
                    .padding(.horizontal, 22)
                    .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
                .disabled(targetTracks.isEmpty)
                .keyboardShortcut(.defaultAction)
            } else if sheetState == .running {
                Spacer()

                // Stop Button
                Button(action: cancelGeneration) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Stop Generation")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(Color.red.opacity(0.90))
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .destructive, cornerRadius: 17))

                Spacer()
            } else if sheetState == .completed {
                Spacer()

                // Done Button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(Color(red: 20/255, green: 24/255, blue: 36/255))
                        .padding(.horizontal, 28)
                        .frame(height: 34)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 17))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Generation Execution Logic
    private func startGeneration() {
        let tracksToProcess = targetTracks
        guard !tracksToProcess.isEmpty else { return }

        sheetState = .running
        totalTracksToProcess = tracksToProcess.count
        processedCount = 0
        syncedCount = 0
        plainCount = 0
        skippedCount = 0
        notFoundCount = 0
        currentTrackTitle = ""
        currentTrackArtist = ""
        currentTrackStage = "Starting multi-threaded concurrent engine..."
        etaString = "Estimating..."
        startTime = Date()

        generationTask = Task {
            let concurrencyLimit = 5
            var trackIndex = 0
            let total = tracksToProcess.count

            await withTaskGroup(of: (Track, Result<LyricsResult, Error>?).self) { group in
                var activeWorkers = 0
                // Spawn initial batch of workers
                while trackIndex < total && activeWorkers < concurrencyLimit && !Task.isCancelled {
                    let track = tracksToProcess[trackIndex]
                    trackIndex += 1
                    activeWorkers += 1
                    group.addTask {
                        await fetchSingleTrack(track: track)
                    }
                }

                // Consume completed results and spawn subsequent tracks
                for await (track, result) in group {
                    activeWorkers -= 1
                    if Task.isCancelled { break }

                    await MainActor.run {
                        self.handleTrackResult(track: track, result: result)
                    }

                    if trackIndex < total && !Task.isCancelled {
                        let nextTrack = tracksToProcess[trackIndex]
                        trackIndex += 1
                        activeWorkers += 1
                        group.addTask {
                            await fetchSingleTrack(track: nextTrack)
                        }
                    }
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.sheetState = .completed
                    NotificationCenter.default.post(name: .trackMetadataDidUpdate, object: nil)
                }
            }
        }
    }

    private func fetchSingleTrack(track: Track) async -> (Track, Result<LyricsResult, Error>?) {
        let trackURL = URL(fileURLWithPath: track.fullPath)

        // Check if track already has lyrics and we are skipping
        if onlyMissingLyrics {
            let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
            let upperLrcURL = trackURL.deletingPathExtension().appendingPathExtension("LRC")
            if FileManager.default.fileExists(atPath: lrcURL.path) || FileManager.default.fileExists(atPath: upperLrcURL.path) || AudioTagger.shared.extractLyrics(fileURL: trackURL) != nil {
                return (track, nil)
            }
        }

        do {
            let res = try await LyricsService.shared.fetchLyrics(
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationSeconds: track.durationSeconds
            )
            return (track, .success(res))
        } catch {
            return (track, .failure(error))
        }
    }

    @MainActor
    private func handleTrackResult(track: Track, result: Result<LyricsResult, Error>?) {
        processedCount += 1
        currentTrackTitle = track.title
        currentTrackArtist = track.artist

        if let resWrap = result {
            switch resWrap {
            case .success(let lyricsResult):
                let trackURL = URL(fileURLWithPath: track.fullPath)
                do {
                    try AudioTagger.shared.saveLyrics(fileURL: trackURL, lyrics: lyricsResult.lyrics)
                    if lyricsResult.synced {
                        syncedCount += 1
                        currentTrackStage = "Saved synchronized .LRC file"
                    } else {
                        plainCount += 1
                        currentTrackStage = "Saved plain lyrics file"
                    }
                } catch {
                    notFoundCount += 1
                    currentTrackStage = "Failed to write .LRC: \(error.localizedDescription)"
                }
            case .failure:
                notFoundCount += 1
                currentTrackStage = "No lyrics found online"
            }
        } else {
            // Skipped (already has lyrics)
            skippedCount += 1
            currentTrackStage = "Skipped (already has .LRC)"
        }

        // Update ETA
        if let start = startTime, processedCount > 1 {
            let elapsed = Date().timeIntervalSince(start)
            let speed = Double(processedCount) / max(elapsed, 0.1) // tracks/second
            let remaining = Double(totalTracksToProcess - processedCount)
            let etaSec = remaining / max(speed, 0.05)
            etaString = formatETA(etaSec)
        }
    }

    private func formatETA(_ seconds: Double) -> String {
        if seconds <= 2 {
            return "Finishing..."
        }
        let totalSec = Int(seconds)
        let mins = totalSec / 60
        let secs = totalSec % 60
        if mins > 0 {
            return "\(mins)m \(secs)s remaining"
        } else {
            return "\(secs)s remaining"
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        sheetState = .completed
        NotificationCenter.default.post(name: .trackMetadataDidUpdate, object: nil)
    }

    private func cancelAndDismiss() {
        generationTask?.cancel()
        generationTask = nil
        onDismiss()
    }
}

// MARK: - Sheet Close Button
private struct SheetCloseButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.07))
                    .frame(width: 28, height: 28)
                
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.25 : 0.12), lineWidth: 0.8)
                    .frame(width: 28, height: 28)
                
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.65))
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
