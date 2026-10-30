import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TransferQueueView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let onTransferComplete: () -> Void

    @ObservedObject private var queueService = TransferQueueService.shared

    @State private var targetDriveId: String = ""
    @State private var targetMode: TransferTargetMode = .music
    @State private var selectedPreset: String = "copy_optimize"

    private var queue: [TransferItem] {
        get { queueService.queue }
        nonmutating set { queueService.queue = newValue }
    }
    @State private var isProcessing: Bool = false
    @State private var isTargeted: Bool = false
    @State private var queueSearchText: String = ""

    // Liquid Glass Sheets
    @State private var itemToEdit: TransferItem? = nil
    @State private var showTransferConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var showDuplicateImportSheet: Bool = false

    // Duplicate Prevention Guardrail State
    private let libraryTracks: [Track]
    @State private var duplicateImportCandidates: [DuplicateImportCandidate] = []
    @State private var pendingNonDuplicateURLs: [URL] = []
    @State private var pendingAllImportURLs: [URL] = []

    // Audio Import / Folder Scanning State
    @State private var isImporting: Bool = false
    @State private var importStatusMessage: String = "Scanning folder for music..."
    @State private var importCurrent: Int = 0
    @State private var importTotal: Int = 0
    @State private var importCurrentTitle: String = ""
    @State private var importProgress: Double = 0.0
    @State private var importTask: Task<Void, Never>? = nil

    // Hardware Optimization & Sync Toggles
    @State private var optimizeArtwork: Bool = true
    @State private var fetchLyrics: Bool = true
    @State private var autoFetchMetadata: Bool = true
    @State private var saveFolderJpg: Bool = true
    @State private var normalizeVolume: Bool = false
    @State private var autoSenseMe: Bool = true

    // Batch & In-Flight Status
    @State private var isBatchOptimizing: Bool = false
    @State private var isBatchFetchingLyrics: Bool = false
    @State private var batchStatusText: String? = nil

    // Audio Player Observation
    @ObservedObject private var player = AudioPlayerService.shared

    public init(
        drives: [WalkmanDrive],
        activeDrive: WalkmanDrive?,
        libraryTracks: [Track] = [],
        onTransferComplete: @escaping () -> Void
    ) {
        self.drives = drives
        self.activeDrive = activeDrive
        self.libraryTracks = libraryTracks
        self.onTransferComplete = onTransferComplete
        let initialId: String
        if let active = activeDrive {
            initialId = active.mountPoint
        } else if let first = drives.first {
            initialId = first.mountPoint
        } else {
            initialId = "local_library"
        }
        _targetDriveId = State(initialValue: initialId)
    }

    private var defaultLocalURL: URL {
        if let first = LocalMusicLibraryService.shared.folders.first {
            return first.url
        }
        let musicURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Walkman Studio Library")
        try? FileManager.default.createDirectory(at: musicURL, withIntermediateDirectories: true)
        return musicURL
    }

    private var isLocalDestination: Bool {
        targetDriveId == "local_library" || targetDriveId.hasPrefix("local_folder_") || (drives.isEmpty && !targetDriveId.hasPrefix("/Volumes"))
    }

    private var selectedTarget: WalkmanDrive? {
        if isLocalDestination {
            if targetDriveId.hasPrefix("local_folder_") {
                let folderId = String(targetDriveId.dropFirst("local_folder_".count))
                if let folder = LocalMusicLibraryService.shared.folders.first(where: { $0.id == folderId }) {
                    return WalkmanDrive.localLibrary(at: folder.url, name: "Local: \(folder.displayName)")
                }
            }
            return WalkmanDrive.localLibrary(at: defaultLocalURL, name: "Local Music Library")
        }
        return drives.first(where: { $0.mountPoint == targetDriveId }) ?? activeDrive ?? (drives.isEmpty ? WalkmanDrive.localLibrary(at: defaultLocalURL) : nil)
    }

    private var queueTotalBytes: Int64 {
        queue.reduce(0) { $0 + $1.sizeBytes }
    }

    private var queueTotalDuration: Double {
        queue.reduce(0) { $0 + $1.durationSeconds }
    }

    private var filteredQueueIndices: [Int] {
        if queueSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(0..<queue.count)
        }
        let q = queueSearchText.lowercased()
        return queue.indices.filter { idx in
            let item = queue[idx]
            return item.title.lowercased().contains(q) ||
                   item.artist.lowercased().contains(q) ||
                   item.album.lowercased().contains(q) ||
                   item.filename.lowercased().contains(q)
        }
    }

    private var duplicatesInQueue: [TransferItem] {
        queue.filter { $0.isDuplicateOnWalkman }
    }

    private var modeButtonsView: some View {
        TransferModeSegmentedBarView(
            targetMode: $targetMode,
            onSelectMode: { newMode in
                targetMode = newMode
                if newMode == .learning && (selectedPreset == "flac_16" || selectedPreset == "flac_24_96") {
                    selectedPreset = "copy_optimize"
                }
            }
        )
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // -------------------------------------------------------------
                // PANEL 0: DESTINATION MODE SELECTOR (Music vs Language Study)
                // -------------------------------------------------------------
                HStack {
                    modeButtonsView
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // -------------------------------------------------------------
                // PANEL 1: CONFIGURATION CONTROL DECK (EQUAL-WIDTH CARDS)
                // -------------------------------------------------------------
                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let cardWidth = max(0, (geo.size.width - spacing * 2) / 3.0)
                    let cardHeight: CGFloat = 114

                    HStack(spacing: spacing) {
                        // Card 1: Target Destination Drive
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: isLocalDestination ? "internaldrive.fill" : (targetMode == .learning ? "character.book.closed.fill" : "hifispeaker.fill"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(isLocalDestination ? WalkmanTheme.silverLight : (targetMode == .learning ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted))
                                Text(isLocalDestination ? "TARGET: LOCAL STORAGE" : (targetMode == .learning ? "TARGET: /LEARNING" : "DESTINATION DRIVE"))
                                    .font(WalkmanFont.sectionHeader)
                                    .foregroundStyle(isLocalDestination ? WalkmanTheme.silverLight.opacity(0.85) : (targetMode == .learning ? WalkmanTheme.hiResGold.opacity(0.9) : Color.white.opacity(0.4)))
                            }

                            LiquidGlassDropdownMenu(title: currentTargetDriveLabel) {
                                Picker("", selection: $targetDriveId) {
                                    if !drives.isEmpty {
                                        Section("Walkman Storage") {
                                            ForEach(drives) { d in
                                                let dev = WalkmanDeviceDetector.shared.detectDevices(drives: drives).first(where: { $0.drives.contains(where: { $0.mountPoint == d.mountPoint }) })
                                                let label = (drives.count > 2 && dev != nil) ? "\(dev!.specificModel) • \(d.name)" : d.name
                                                Text(label).tag(d.mountPoint)
                                            }
                                        }
                                    }
                                    Section("Local Storage") {
                                        Text("Local Music Library").tag("local_library")
                                        ForEach(LocalMusicLibraryService.shared.folders) { f in
                                            Text("Folder: \(f.displayName)").tag("local_folder_\(f.id)")
                                        }
                                    }
                                }
                                .pickerStyle(.inline)
                            }

                            Spacer(minLength: 0)

                            if let target = selectedTarget {
                                let freeGB = Double(target.freeBytes) / 1_073_741_824.0
                                let totalGB = Double(target.totalBytes) / 1_073_741_824.0
                                VStack(alignment: .leading, spacing: 3) {
                                    ProgressView(value: min(1.0, max(0.0, target.percentUsed / 100.0)))
                                        .progressViewStyle(.linear)
                                        .tint(WalkmanTheme.silver)
                                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                                    HStack(spacing: 4) {
                                        Text(String(format: "%.1f GB free", freeGB))
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(.white.opacity(0.88))
                                        Text(String(format: "/ %.1f GB", totalGB))
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Text("No Destination Selected")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                        .liquidGlass(cornerRadius: 12)

                        // Card 2: Conversion Preset
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 10))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Text("CONVERSION PRESET")
                                    .font(WalkmanFont.sectionHeader)
                                    .foregroundStyle(.tertiary)
                            }

                            LiquidGlassDropdownMenu(title: presetDisplayName(selectedPreset)) {
                                Picker("", selection: $selectedPreset) {
                                    Section("Pass-Through & Optimization") {
                                        Text("Optimize Metadata Only (Direct Copy)").tag("copy_optimize")
                                        Text("Direct Copy (Raw Passthrough)").tag("copy_raw")
                                    }

                                    Section("Podcasts, Audiobooks & Voice (Speech Optimized)") {
                                        Text("MP3 128 kbps Spoken Word (Compact Size)").tag("mp3_128")
                                        Text("MP3 192 kbps Voice Master (High Clarity)").tag("mp3_192")
                                        Text("AAC 128 kbps Spoken Audio (M4A)").tag("aac_128")
                                    }

                                    Section("Lossless FLAC (Sony S-Master HX)") {
                                        Text("FLAC 16-bit / 44.1kHz (CD Quality)").tag("flac_16")
                                        Text("FLAC 24-bit / 48kHz (Studio Lossless)").tag("flac_24_48")
                                        Text("FLAC 24-bit / 96kHz (Hi-Res Master)").tag("flac_24_96")
                                        Text("FLAC 24-bit / 192kHz (Ultra Hi-Res)").tag("flac_24_192")
                                    }

                                    Section("MP3 (Strict ID3v2.3 UTF-16)") {
                                        Text("MP3 320 kbps CBR (Maximum Quality)").tag("mp3_320")
                                        Text("MP3 256 kbps CBR (High Quality)").tag("mp3_256")
                                        Text("MP3 VBR V0 (~245 kbps Variable)").tag("mp3_v0")
                                    }

                                    Section("Apple & PCM Audio") {
                                        Text("AAC 320 kbps (High Fidelity M4A)").tag("aac_320")
                                        Text("AAC 256 kbps (iTunes Standard M4A)").tag("aac_256")
                                        Text("ALAC Apple Lossless (16-bit)").tag("alac_16")
                                        Text("WAV 16-bit / 44.1kHz PCM").tag("wav_16")
                                    }
                                }
                                .pickerStyle(.inline)
                            }

                            Spacer(minLength: 0)

                            Text(presetDescription(selectedPreset))
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(selectedPreset == "copy_optimize" ? WalkmanTheme.silverLight : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                        .liquidGlass(cornerRadius: 12)

                        // Card 3: Batch Queue & Transfer CTA
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Text("SYNC TO WALKMAN")
                                    .font(WalkmanFont.sectionHeader)
                                    .foregroundStyle(.tertiary)
                            }

                            Button(action: {
                                showTransferConfirmation = true
                            }) {
                                HStack(spacing: 8) {
                                    Spacer(minLength: 0)
                                    if isProcessing {
                                        ProgressView()
                                            .scaleEffect(0.70)
                                        let doneCount = queue.filter { $0.status == .success }.count
                                        Text("Transferring (\(doneCount)/\(queue.count))...")
                                            .font(WalkmanFont.calloutBold)
                                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    } else if queue.isEmpty {
                                        Image(systemName: "arrow.right.circle")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Queue Empty")
                                            .font(WalkmanFont.calloutMedium)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Start Transfer (\(queue.count))")
                                            .font(WalkmanFont.calloutBold)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .foregroundStyle(
                                    queue.isEmpty ?
                                        Color.white.opacity(0.35) :
                                        Color(red: 20/255, green: 20/255, blue: 24/255)
                                )
                            }
                            .buttonStyle(
                                LiquidGlassButtonStyle(
                                    variant: queue.isEmpty ? .glass : .prominent,
                                    cornerRadius: 19
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .disabled(queue.isEmpty || isProcessing || isBatchOptimizing || isBatchFetchingLyrics)

                            Spacer(minLength: 0)

                            let doneCount = queue.filter { $0.status == .success }.count
                            if doneCount == queue.count && !queue.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text("All \(queue.count) tracks transferred")
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(.green)
                                }
                            } else {
                                Text("\(doneCount) of \(queue.count) transferred")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                        .liquidGlass(cornerRadius: 12)
                    }
                }
                .frame(height: 114)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // -------------------------------------------------------------
                // PANEL 2: HARDWARE OPTIMIZATION CAPSULES & BATCH ACTIONS
                // -------------------------------------------------------------
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            toggleChip(
                                title: "Baseline RGB Art",
                                icon: "photo.badge.checkmark",
                                isOn: $optimizeArtwork,
                                help: "Converts artwork to strict Baseline RGB JPEG (max 800x800) for Sony Walkman display engine"
                            )
                            toggleChip(
                                title: ".LRC Lyrics",
                                icon: "quote.bubble",
                                isOn: $fetchLyrics,
                                help: targetMode == .learning ? "Disabled in Language Study mode (lyrics are not needed for audiobooks or podcasts)" : "Auto-downloads synchronized .lrc lyrics alongside music on Walkman",
                                disabled: targetMode == .learning
                            )
                            toggleChip(
                                title: "Auto-Tags",
                                icon: "sparkles",
                                isOn: $autoFetchMetadata,
                                help: targetMode == .learning ? "Disabled in Language Study mode (preserves original chapter titles & author info)" : "Auto-queries iTunes & Deezer for missing tags & high-res artwork",
                                disabled: targetMode == .learning
                            )
                            toggleChip(
                                title: "folder.jpg",
                                icon: "folder",
                                isOn: $saveFolderJpg,
                                help: "Writes folder.jpg and cover.jpg into destination album directory"
                            )
                            toggleChip(
                                title: "EBU R128 Leveling",
                                icon: "speaker.wave.2",
                                isOn: $normalizeVolume,
                                help: "Normalizes track loudness using EBU R128 standard during transcoding",
                                disabled: selectedPreset == "copy_optimize" || selectedPreset == "copy_raw"
                            )
                            toggleChip(
                                title: "12 Tone / SenseMe",
                                icon: "waveform.path.badge.plus",
                                isOn: $autoSenseMe,
                                help: "Injects Sony 12 Tone Analysis (SenseMe) metadata so the Walkman illuminates the SenseMe channel indicator"
                            )
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .disableScrollClipIfAvailable()

                    Spacer(minLength: 8)

                    if !queue.isEmpty {
                        batchToolbarButtons
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.8)
                    .padding(.horizontal, 16)

                // -------------------------------------------------------------
                // PANEL 3: EMPTY DROPZONE vs POPULATED QUEUE CONTAINER
                // -------------------------------------------------------------
                if queue.isEmpty {
                    if isImporting {
                        importingProgressView
                            .padding(.horizontal, 16)
                            .padding(.bottom, 88)
                    } else {
                        // EMPTY STATE: Large, inviting drop zone
                        emptyDropZone
                            .padding(.horizontal, 16)
                            .padding(.bottom, 88)
                    }
                } else {
                    // POPULATED STATE: High-end Queue View (No huge redundant drop box!)
                    VStack(spacing: 0) {
                        if isImporting {
                            importingBannerView
                        }

                        // Queue Header Bar
                        HStack(spacing: 10) {
                            // Left summary
                            HStack(spacing: 6) {
                                Text("Queue")
                                    .font(WalkmanFont.headline)
                                    .foregroundStyle(.white)

                                Text("\(queue.count)")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())

                                Text("•")
                                    .foregroundStyle(.tertiary)

                                Text(WalkmanEngine.formatBytes(queueTotalBytes))
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(.secondary)

                                if queueTotalDuration > 0 {
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                    Text(WalkmanEngine.formatDuration(queueTotalDuration))
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            let missingCount = queue.filter { $0.isMissingMetadata }.count
                            if missingCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                    Text("\(missingCount) missing tags / art")
                                        .font(WalkmanFont.monoSmall)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                            }

                            Spacer()

                            // Queue Search Filter (for large queues)
                            if queue.count > 4 {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.white.opacity(0.55))

                                    TextField("Filter queue...", text: $queueSearchText)
                                        .textFieldStyle(.plain)
                                        .font(WalkmanFont.callout)

                                    if !queueSearchText.isEmpty {
                                        Button(action: { queueSearchText = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 32)
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
                                            .frame(height: 5.5)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(queueSearchText.isEmpty ? 0.10 : 0.28), lineWidth: 0.85)
                                )
                                .frame(maxWidth: 180)
                            }

                            // Sort Queue Menu
                            Menu {
                                Button {
                                    sortQueueByTrackNumber()
                                } label: {
                                    Label("Sort by Track Number", systemImage: "number")
                                }
                                Button {
                                    sortQueueByFilename()
                                } label: {
                                    Label("Sort by Filename (A-Z)", systemImage: "doc.plaintext")
                                }
                                Button {
                                    sortQueueByArtistAlbum()
                                } label: {
                                    Label("Sort by Artist & Album", systemImage: "music.note.list")
                                }
                            } label: {
                                HStack(spacing: 4.5) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text("Sort")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.85))
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(.plain)
                            .help("Sort queue items by track number, filename, or album")

                            // Add More Files Button
                            Button(action: openFilePicker) {
                                HStack(spacing: 4.5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text("Add Files...")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.85))
                            }
                            .buttonStyle(.plain)
                            .help("Add more audio files or folders to the transfer queue")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(WalkmanTheme.card.opacity(0.9))
                        .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)

                        // Duplicate Guardrail Banner (If duplicates exist in the queue)
                        if !duplicatesInQueue.isEmpty && !isProcessing {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)

                                Text("\(duplicatesInQueue.count) track(s) in queue already exist on your Walkman library.")
                                    .font(WalkmanFont.calloutMedium)
                                    .foregroundStyle(.white)

                                Spacer()

                                Button(action: removeDuplicatesFromQueue) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                        Text("Remove Duplicates")
                                            .font(WalkmanFont.captionBold)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.orange.opacity(0.4), lineWidth: 0.8))
                                }
                                .buttonStyle(.plain)
                                .help("Remove all duplicate tracks from the queue to avoid redundant copies")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.12))
                            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.25)), alignment: .bottom)
                        }

                        // Scrollable Queue Cards List
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredQueueIndices.filter { $0 < queue.count }, id: \.self) { idx in
                                    QueueItemRow(
                                        item: $queueService.queue[idx],
                                        isThisPlaying: player.isPlaying && player.currentTrack?.id == queue[idx].sourceURL.path,
                                        destinationExtension: destinationExtension(for: queue[idx].sourceURL),
                                        rootFolderName: targetMode.rootFolderName,
                                        isLearningMode: targetMode == .learning,
                                        onTogglePlay: { togglePreviewPlayback(for: queue[idx]) },
                                        onPickArtwork: { pickCustomArtwork(for: queue[idx].id) },
                                        onOptimize: { optimizeSingleTrack(queue[idx]) },
                                        onFetchLyrics: { fetchLyricsForTrack(queue[idx]) },
                                        onEdit: { itemToEdit = queue[idx] },
                                        onRemove: {
                                            let targetId = queue[idx].id
                                            queue.removeAll(where: { $0.id == targetId })
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 88)
                        }
                    }
                    .liquidGlass(cornerRadius: 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88)
                }
            }

            // Drag & Drop Hover Overlay (illuminates over the entire view when files are dragged)
            if isTargeted {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(WalkmanTheme.silver)

                        Text("Drop to Add to Transfer Queue")
                            .font(WalkmanFont.title2)
                            .foregroundStyle(.white)

                        Text("Supports FLAC, MP3, M4A, M4B, WAV, ALAC, AAC, DSD • Auto-indexes tags & art")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(WalkmanTheme.silver, lineWidth: 2))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .sheet(item: $itemToEdit) { item in
            QueueItemEditorSheet(
                item: item,
                destinationExtension: destinationExtension(for: item.sourceURL),
                rootFolderName: targetMode.rootFolderName,
                onSave: { updated in
                    if let idx = queue.firstIndex(where: { $0.id == updated.id }) {
                        queue[idx] = updated
                    }
                    itemToEdit = nil
                },
                onDismiss: {
                    itemToEdit = nil
                }
            )
        }
        .sheet(isPresented: $showTransferConfirmation) {
            TransferSyncSheet(
                queue: queue,
                targetDrive: selectedTarget,
                targetMode: targetMode,
                preset: selectedPreset,
                presetDescription: presetDescription(selectedPreset),
                onConfirm: { skipDuplicates in
                    showTransferConfirmation = false
                    startBatchTransfer(skipExistingDuplicates: skipDuplicates)
                },
                onCancel: {
                    showTransferConfirmation = false
                }
            )
        }
        .sheet(isPresented: $showDuplicateImportSheet) {
            DuplicateImportGuardSheet(
                candidates: duplicateImportCandidates,
                nonDuplicateCount: pendingNonDuplicateURLs.count,
                totalCount: pendingAllImportURLs.count,
                targetDriveName: selectedTarget?.name ?? "Walkman",
                onSkipDuplicates: {
                    showDuplicateImportSheet = false
                    for url in pendingNonDuplicateURLs {
                        enqueueSingleFile(url)
                    }
                },
                onAddAll: {
                    showDuplicateImportSheet = false
                    for url in pendingAllImportURLs {
                        let isDup = duplicateImportCandidates.contains(where: { $0.url == url })
                        let info = duplicateImportCandidates.first(where: { $0.url == url })?.matchReason
                        enqueueSingleFile(url, isDuplicate: isDup, duplicateInfo: info)
                    }
                },
                onCancel: {
                    showDuplicateImportSheet = false
                }
            )
        }
        .sheet(isPresented: $showClearConfirmation) {
            ClearQueueConfirmSheet(
                queueCount: queue.count,
                onConfirm: {
                    queue.removeAll()
                    showClearConfirmation = false
                },
                onCancel: {
                    showClearConfirmation = false
                }
            )
        }
    }

    // -------------------------------------------------------------------------
    // IMPORTING PROGRESS VIEW (Liquid Glass)
    // -------------------------------------------------------------------------
    private var importingProgressView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WalkmanTheme.card.opacity(0.85))
                .background(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.18), location: 0.0),
                                .init(color: .white.opacity(0.04), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 10)
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.30), location: 0.0),
                                    .init(color: Color.white.opacity(0.10), location: 0.5),
                                    .init(color: Color.white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                )
                .shadow(color: Color.black.opacity(0.30), radius: 20, x: 0, y: 8)

            VStack(spacing: 16) {
                // Top Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 58, height: 58)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.85)
                        )

                    ProgressView()
                        .controlSize(.regular)
                        .scaleEffect(1.1)
                }
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)

                VStack(spacing: 5) {
                    Text("Importing Music to Walkman Studio")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text(importTotal > 0
                         ? "Analyzing audio metadata, tags, and inspecting duplicates..."
                         : "Scanning folders for audio tracks and albums...")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .multilineTextAlignment(.center)
                }

                // Progress Bar
                VStack(spacing: 7) {
                    ImportProgressBar(progress: importProgress, isIndeterminate: importTotal == 0)
                        .frame(maxWidth: 420)

                    HStack {
                        if importTotal > 0 {
                            Text("\(importCurrent) of \(importTotal) tracks")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverLight)

                            Spacer()

                            Text("\(Int(importProgress * 100))%")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverLight)
                        } else {
                            Text("Discovering tracks...")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: 420)
                }

                // Current Track File Name Pill
                if !importCurrentTitle.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WalkmanTheme.silver)

                        Text(importCurrentTitle)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                    .frame(maxWidth: 460)
                }

                // Cancel Button
                Button(action: {
                    importTask?.cancel()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        isImporting = false
                    }
                }) {
                    Text("Cancel Import")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 16))
                .padding(.top, 4)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------------------
    // IMPORTING BANNER VIEW (When Queue Already Has Tracks)
    // -------------------------------------------------------------------------
    private var importingBannerView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(importTotal > 0 ? "Importing music to Walkman Studio (\(importCurrent)/\(importTotal))..." : "Scanning folder for music...")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(WalkmanTheme.silverLight)

                if !importCurrentTitle.isEmpty {
                    Text(importCurrentTitle)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if importTotal > 0 {
                ImportProgressBar(progress: importProgress, isIndeterminate: false)
                    .frame(width: 140)

                Text("\(Int(importProgress * 100))%")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            Button("Cancel") {
                importTask?.cancel()
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    isImporting = false
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
            .font(WalkmanFont.captionBold)
            .frame(height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.92)
                    .background(.ultraThinMaterial)
                VStack {
                    LinearGradient(stops: [.init(color: .white.opacity(0.15), location: 0), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 4)
                    Spacer()
                }
            }
        )
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.10)), alignment: .bottom)
    }

    // -------------------------------------------------------------------------
    // EMPTY STATE VIEW
    // -------------------------------------------------------------------------
    private var emptyDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 5])
                )
                .background(isTargeted ? Color.white.opacity(0.08) : WalkmanTheme.card.opacity(0.35))

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 68, height: 68)

                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }

                VStack(spacing: 5) {
                    Text(targetMode == .learning ? "Drag & Drop Podcasts, Audiobooks, or Audio Files" : "Drag & Drop Audio Files or Folders")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)

                    Text(targetMode == .learning
                         ? "Drop podcast episodes or audiobooks (.m4b, .mp3, .m4a) to transfer directly to Walkman Language Study mode with DPC speed control, A-B Repeat, and Quick Replay."
                         : "Drop songs or entire albums from Finder to convert, optimize Baseline RGB artwork, sync lyrics, and copy to Walkman.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                HStack(spacing: 6) {
                    ForEach(["FLAC", "MP3", "M4A", "M4B (Audiobook)", "WAV", "ALAC", "AAC", "DSD"], id: \.self) { fmt in
                        Text(fmt)
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                    }
                }
                .padding(.vertical, 2)

                Button(action: openFilePicker) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Browse Audio Files or Folders...")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------------------
    // HARDWARE TOGGLE CAPSULE CHIP
    // -------------------------------------------------------------------------
    private func toggleChip(title: String, icon: String, isOn: Binding<Bool>, help: String, disabled: Bool = false) -> some View {
        HardwareOptimizationToggleChipView(
            title: title,
            icon: icon,
            isOn: isOn,
            help: help,
            disabled: disabled
        )
    }

    // -------------------------------------------------------------------------
    // BATCH TOOLBAR BUTTONS
    // -------------------------------------------------------------------------
    private var batchToolbarButtons: some View {
        HStack(spacing: 6) {
            if targetMode != .learning {
                TransferBatchActionButton(
                    title: isBatchOptimizing ? "Optimizing..." : "Optimize All",
                    icon: "sparkles",
                    isLoading: isBatchOptimizing,
                    isDisabled: isBatchOptimizing || isProcessing,
                    help: "Fetches missing metadata and optimizes cover artwork to Baseline RGB JPEG for all tracks",
                    action: batchOptimizeAll
                )

                TransferBatchActionButton(
                    title: isBatchFetchingLyrics ? "Fetching..." : "Fetch Lyrics",
                    icon: "quote.bubble.fill",
                    isLoading: isBatchFetchingLyrics,
                    isDisabled: isBatchFetchingLyrics || isProcessing,
                    help: "Fetches synchronized .LRC lyrics for all tracks in the queue",
                    action: batchFetchAllLyrics
                )
            }

            TransferBatchActionButton(
                title: "Clear",
                icon: "trash",
                isDestructive: true,
                isDisabled: isProcessing,
                help: "Clear all tracks from the queue",
                action: {
                    if !queue.isEmpty {
                        showClearConfirmation = true
                    }
                }
            )
        }
    }

    // -------------------------------------------------------------------------
    // HELPERS & INGESTION
    // -------------------------------------------------------------------------
    private var currentTargetDriveLabel: String {
        if targetDriveId == "local_library" {
            return "Local Music Library"
        } else if targetDriveId.hasPrefix("local_folder_") {
            let folderId = String(targetDriveId.dropFirst("local_folder_".count))
            if let folder = LocalMusicLibraryService.shared.folders.first(where: { $0.id == folderId }) {
                return "Folder: \(folder.displayName)"
            }
            return "Local Folder"
        } else if let drive = drives.first(where: { $0.mountPoint == targetDriveId }) {
            let dev = WalkmanDeviceDetector.shared.detectDevices(drives: drives).first(where: { $0.drives.contains(where: { $0.mountPoint == drive.mountPoint }) })
            return (drives.count > 2 && dev != nil) ? "\(dev!.specificModel) • \(drive.name)" : drive.name
        } else if let first = drives.first {
            return first.name
        } else {
            return "Local Music Library"
        }
    }

    private func presetDisplayName(_ preset: String) -> String {
        switch preset {
        case "copy_optimize":
            return "Optimize Metadata Only (Direct Copy)"
        case "copy_raw":
            return "Direct Copy (Raw Passthrough)"
        case "mp3_128":
            return "MP3 128 kbps Spoken Word"
        case "mp3_192":
            return "MP3 192 kbps Voice Master"
        case "aac_128":
            return "AAC 128 kbps Spoken Audio"
        case "flac_16":
            return "FLAC 16-bit / 44.1kHz (CD Quality)"
        case "flac_24_48":
            return "FLAC 24-bit / 48kHz (Studio Lossless)"
        case "flac_24_96", "flac_24":
            return "FLAC 24-bit / 96kHz (Hi-Res Master)"
        case "flac_24_192":
            return "Ultra Hi-Res FLAC 24-bit / 192kHz"
        case "mp3_320":
            return "MP3 320 kbps CBR (Maximum Quality)"
        case "mp3_256":
            return "MP3 256 kbps CBR (High Quality)"
        case "mp3_v0":
            return "MP3 VBR V0 (~245 kbps Variable)"
        case "aac_320":
            return "AAC 320 kbps (High Fidelity M4A)"
        case "aac_256":
            return "iTunes Standard AAC 256 kbps"
        case "alac_16":
            return "ALAC Apple Lossless (16-bit)"
        case "wav_16":
            return "Uncompressed PCM 16-bit / 44.1kHz"
        default:
            return preset
        }
    }

    private func presetDescription(_ preset: String) -> String {
        switch preset {
        case "copy_optimize":
            return "Direct copy • Strict tags & Baseline JPEG"
        case "copy_raw":
            return "Pass-through copy • Unmodified file copy"
        case "mp3_128":
            return "Optimized for speech, podcasts & audiobooks • Compact size"
        case "mp3_192":
            return "High clarity spoken word for podcasts & audiobooks"
        case "aac_128":
            return "Efficient AAC spoken word audio for audiobooks"
        case "flac_16":
            return "CD Quality FLAC 16-bit / 44.1kHz"
        case "flac_24_48":
            return "Studio lossless FLAC 24-bit / 48kHz"
        case "flac_24_96", "flac_24":
            return "Hi-Res studio master FLAC 24-bit / 96kHz"
        case "flac_24_192":
            return "Ultra Hi-Res FLAC 24-bit / 192kHz"
        case "mp3_320":
            return "Maximum fidelity MP3 320 kbps (ID3v2.3 UTF-16)"
        case "mp3_256":
            return "High quality MP3 256 kbps CBR"
        case "mp3_v0":
            return "Variable bitrate MP3 VBR V0 (~245 kbps)"
        case "aac_320":
            return "High fidelity AAC-LC 320 kbps (M4A)"
        case "aac_256":
            return "iTunes standard AAC 256 kbps (M4A)"
        case "alac_16":
            return "Apple Lossless 16-bit (M4A)"
        case "wav_16":
            return "Uncompressed PCM 16-bit / 44.1kHz"
        default:
            return "Apple Silicon hardware acceleration"
        }
    }

    private func destinationExtension(for sourceURL: URL) -> String {
        switch selectedPreset {
        case "copy_optimize", "copy_raw":
            let ext = sourceURL.pathExtension.lowercased()
            if ext == "m4b" { return "m4a" } // Remux .m4b audiobooks into .m4a for Walkman hardware playback
            return ext
        case "flac_16", "flac_24_48", "flac_24_96", "flac_24", "flac_24_192":
            return "flac"
        case "mp3_320", "mp3_256", "mp3_v0", "mp3_192", "mp3_128":
            return "mp3"
        case "aac_320", "aac_256", "aac_128", "alac_16":
            return "m4a"
        case "wav_16":
            return "wav"
        default:
            return "flac"
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            isImporting = true
            importStatusMessage = "Accessing dropped files..."
            importCurrent = 0
            importTotal = 0
            importProgress = 0.0
            importCurrentTitle = ""
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var droppedURLs: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                droppedURLs.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            if droppedURLs.isEmpty {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    self.isImporting = false
                }
                return
            }
            self.addURLsToQueue(droppedURLs)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        var types: [UTType] = [.audio]
        if let m4bType = UTType(filenameExtension: "m4b") { types.append(m4bType) }
        if let flacType = UTType(filenameExtension: "flac") { types.append(flacType) }
        panel.allowedContentTypes = types

        if panel.runModal() == .OK {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                isImporting = true
                importStatusMessage = "Preparing selected files..."
                importCurrent = 0
                importTotal = 0
                importProgress = 0.0
                importCurrentTitle = ""
            }
            addURLsToQueue(panel.urls)
        }
    }

    private func addURLToQueue(_ url: URL) {
        addURLsToQueue([url])
    }

    private func addURLsToQueue(_ urls: [URL]) {
        importTask?.cancel()

        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            isImporting = true
            importStatusMessage = "Scanning folders & discovering music..."
            importCurrent = 0
            importTotal = 0
            importProgress = 0.0
            importCurrentTitle = ""
        }

        let target = selectedTarget
        let mode = targetMode
        let libTracks = libraryTracks

        importTask = Task.detached(priority: .userInitiated) {
            let supportedExtensions: Set<String> = [
                "flac", "mp3", "m4a", "m4b", "wav", "aac", "alac", "aiff", "dsf", "dff", "wma", "ogg", "opus"
            ]
            var collectedURLs: [URL] = []

            for url in urls {
                if Task.isCancelled { return }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        if let enumerator = FileManager.default.enumerator(
                            at: url,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: [.skipsHiddenFiles]
                        ) {
                            while let fileURL = enumerator.nextObject() as? URL {
                                if Task.isCancelled { return }
                                let ext = fileURL.pathExtension.lowercased()
                                if supportedExtensions.contains(ext) {
                                    collectedURLs.append(fileURL)
                                }
                            }
                        }
                    } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                        collectedURLs.append(url)
                    }
                }
            }

            if Task.isCancelled { return }

            // Natural Finder-style sorting ensures 01 - Song, 02 - Song, ... are perfectly ordered
            collectedURLs.sort { urlA, urlB in
                urlA.path.localizedStandardCompare(urlB.path) == .orderedAscending
            }

            guard !collectedURLs.isEmpty else {
                await MainActor.run {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        self.isImporting = false
                    }
                }
                return
            }

            let total = collectedURLs.count
            await MainActor.run {
                self.importTotal = total
                self.importStatusMessage = "Importing \(total) tracks to Walkman Studio..."
            }

            // Duplicate Guardrail: Check incoming tracks against Walkman library
            var duplicates: [DuplicateImportCandidate] = []
            var nonDuplicates: [URL] = []

            for (index, fileURL) in collectedURLs.enumerated() {
                if Task.isCancelled { return }

                let fileName = fileURL.lastPathComponent
                let progress = Double(index + 1) / Double(total)

                await MainActor.run {
                    self.importCurrent = index + 1
                    self.importProgress = progress
                    self.importCurrentTitle = fileName
                }

                let pathFallback = AudioTagger.extractFromPath(url: fileURL)
                var title = pathFallback.title
                var artist = pathFallback.artist
                var album = pathFallback.album
                var duration: Double = 0

                if let meta = AudioTagger.shared.readMetadata(fileURL: fileURL) {
                    if !meta.title.isEmpty && meta.title.lowercased() != "unknown" { title = meta.title }
                    if !meta.artist.isEmpty && meta.artist.lowercased() != "unknown artist" { artist = meta.artist }
                    if !meta.album.isEmpty && meta.album.lowercased() != "unknown album" { album = meta.album }
                    duration = meta.durationSeconds
                }

                let check = WalkmanDuplicateGuard.shared.checkTrack(
                    title: title,
                    artist: artist,
                    album: album,
                    durationSeconds: duration,
                    sourceURL: fileURL,
                    targetDrive: target,
                    targetMode: mode,
                    existingTracks: libTracks
                )

                if check.isDuplicate {
                    duplicates.append(
                        DuplicateImportCandidate(
                            url: fileURL,
                            title: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
                            artist: artist.isEmpty ? "Unknown Artist" : artist,
                            album: album,
                            durationSeconds: duration,
                            matchingWalkmanTrack: check.matchingTrack,
                            matchReason: check.reason ?? "Already present on Walkman library"
                        )
                    )
                } else {
                    nonDuplicates.append(fileURL)
                }
            }

            if Task.isCancelled { return }

            let finalDuplicates = duplicates
            let finalNonDuplicates = nonDuplicates
            let finalCollected = collectedURLs

            await MainActor.run {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    self.isImporting = false
                }

                if !finalDuplicates.isEmpty {
                    self.duplicateImportCandidates = finalDuplicates
                    self.pendingNonDuplicateURLs = finalNonDuplicates
                    self.pendingAllImportURLs = finalCollected
                    self.showDuplicateImportSheet = true
                } else {
                    for fileURL in finalCollected {
                        self.enqueueSingleFile(fileURL)
                    }
                }
            }
        }
    }

    private func removeDuplicatesFromQueue() {
        withAnimation(.easeInOut(duration: 0.2)) {
            queue.removeAll(where: { $0.isDuplicateOnWalkman })
        }
    }

    private func sortQueueByTrackNumber() {
        withAnimation(.easeInOut(duration: 0.2)) {
            queue.sort { a, b in
                if a.album != b.album && !a.album.isEmpty && !b.album.isEmpty {
                    return a.album.localizedStandardCompare(b.album) == .orderedAscending
                }
                let tA = Int(a.trackNumber.components(separatedBy: "/").first ?? "") ?? 0
                let tB = Int(b.trackNumber.components(separatedBy: "/").first ?? "") ?? 0
                if tA != tB && tA > 0 && tB > 0 {
                    return tA < tB
                }
                return a.sourceURL.path.localizedStandardCompare(b.sourceURL.path) == .orderedAscending
            }
        }
    }

    private func sortQueueByFilename() {
        withAnimation(.easeInOut(duration: 0.2)) {
            queue.sort {
                $0.sourceURL.lastPathComponent.localizedStandardCompare($1.sourceURL.lastPathComponent) == .orderedAscending
            }
        }
    }

    private func sortQueueByArtistAlbum() {
        withAnimation(.easeInOut(duration: 0.2)) {
            queue.sort { a, b in
                if a.artist != b.artist {
                    return a.artist.localizedStandardCompare(b.artist) == .orderedAscending
                }
                if a.album != b.album {
                    return a.album.localizedStandardCompare(b.album) == .orderedAscending
                }
                let tA = Int(a.trackNumber.components(separatedBy: "/").first ?? "") ?? 0
                let tB = Int(b.trackNumber.components(separatedBy: "/").first ?? "") ?? 0
                if tA != tB && tA > 0 && tB > 0 {
                    return tA < tB
                }
                return a.sourceURL.path.localizedStandardCompare(b.sourceURL.path) == .orderedAscending
            }
        }
    }

    private func enqueueSingleFile(_ url: URL, isDuplicate: Bool = false, duplicateInfo: String? = nil) {
        if queue.contains(where: { $0.sourceURL == url }) { return }

        var item = TransferItem(sourceURL: url)
        item.title = WalkmanEngine.sanitizeWalkmanText(url.deletingPathExtension().lastPathComponent)
        item.format = url.pathExtension.uppercased()
        item.isDuplicateOnWalkman = isDuplicate
        item.duplicateMatchInfo = duplicateInfo

        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) {
            item.sizeBytes = attr[.size] as? Int64 ?? 0
        }

        let pathFallback = AudioTagger.extractFromPath(url: url)
        if !pathFallback.artist.isEmpty { item.artist = WalkmanEngine.sanitizeWalkmanText(pathFallback.artist, stripExplicitMarkers: false) }
        if !pathFallback.album.isEmpty { item.album = WalkmanEngine.sanitizeWalkmanText(pathFallback.album) }
        if !pathFallback.title.isEmpty { item.title = WalkmanEngine.sanitizeWalkmanText(pathFallback.title) }
        if !pathFallback.trackNumber.isEmpty { item.trackNumber = pathFallback.trackNumber }

        if !item.isDuplicateOnWalkman {
            let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                title: item.title,
                artist: item.artist,
                album: item.album,
                sourceURL: url,
                targetDrive: selectedTarget,
                targetMode: targetMode,
                existingTracks: libraryTracks
            )
            if dupCheck.isDuplicate {
                item.isDuplicateOnWalkman = true
                item.duplicateMatchInfo = dupCheck.reason
            }
        }

        Task.detached(priority: .userInitiated) {
            let meta = AudioTagger.shared.readMetadata(fileURL: url)
            let artData = AudioTagger.shared.extractCoverArt(fileURL: url)
            let existingLyrics = AudioTagger.shared.extractLyrics(fileURL: url)

            var isOpt = false
            var finalArt = artData
            if let d = artData {
                let check = WalkmanEngine.shared.isBaselineRGBJPEG(data: d)
                isOpt = check.valid
                if !isOpt {
                    if let encoded = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: d, maxDimension: 800) {
                        finalArt = encoded
                        isOpt = true
                    }
                }
            }

            let resolvedArt = finalArt
            let resolvedOpt = isOpt

            await MainActor.run {
                if let idx = self.queue.firstIndex(where: { $0.sourceURL == url }) {
                    if let m = meta {
                        if !m.title.isEmpty && m.title.lowercased() != "unknown" && m.title.lowercased() != "unknown track" && m.title.lowercased() != "unknown title" {
                            self.queue[idx].title = WalkmanEngine.sanitizeWalkmanText(m.title)
                        }
                        if !m.artist.isEmpty && m.artist.lowercased() != "unknown artist" && m.artist.lowercased() != "unknown" {
                            self.queue[idx].artist = WalkmanEngine.sanitizeWalkmanText(m.artist, stripExplicitMarkers: false)
                        }
                        if !m.album.isEmpty && m.album.lowercased() != "unknown album" && m.album.lowercased() != "unknown" {
                            self.queue[idx].album = WalkmanEngine.sanitizeWalkmanText(m.album)
                        }
                        if !m.trackNumber.isEmpty { self.queue[idx].trackNumber = m.trackNumber }
                        if !m.year.isEmpty { self.queue[idx].year = m.year }
                        if !m.genre.isEmpty { self.queue[idx].genre = m.genre }
                        self.queue[idx].durationSeconds = m.durationSeconds
                        self.queue[idx].bitrateKbps = m.bitrateKbps
                        self.queue[idx].sampleRate = m.sampleRate
                        self.queue[idx].bitsPerSample = m.bitsPerSample
                    }
                    self.queue[idx].artworkData = resolvedArt
                    self.queue[idx].isArtworkOptimized = resolvedOpt
                    self.queue[idx].lyrics = existingLyrics
                    self.queue[idx].isLyricsSynced = existingLyrics?.contains("[0") == true

                    if !self.queue[idx].isDuplicateOnWalkman {
                        let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                            title: self.queue[idx].title,
                            artist: self.queue[idx].artist,
                            album: self.queue[idx].album,
                            durationSeconds: self.queue[idx].durationSeconds,
                            sourceURL: url,
                            targetDrive: self.selectedTarget,
                            targetMode: self.targetMode,
                            existingTracks: self.libraryTracks
                        )
                        if dupCheck.isDuplicate {
                            self.queue[idx].isDuplicateOnWalkman = true
                            self.queue[idx].duplicateMatchInfo = dupCheck.reason
                        }
                    }

                    if self.targetMode != .learning && self.autoFetchMetadata && self.queue[idx].isMissingMetadata {
                        self.optimizeSingleTrack(self.queue[idx])
                    }
                    if self.targetMode != .learning && self.fetchLyrics && self.queue[idx].lyrics == nil {
                        self.fetchLyricsForTrack(self.queue[idx])
                    }
                }
            }
        }

        queue.append(item)
    }

    private func togglePreviewPlayback(for item: TransferItem) {
        if player.currentTrack?.id == item.sourceURL.path {
            if player.isPlaying {
                player.pause()
            } else {
                player.play(track: item.toPreviewTrack())
            }
        } else {
            let preview = item.toPreviewTrack()
            var artImg: NSImage? = nil
            if let d = item.artworkData {
                artImg = NSImage(data: d)
            }
            player.play(track: preview, coverArt: artImg, in: queue.map { $0.toPreviewTrack() })
        }
    }

    private func optimizeSingleTrack(_ item: TransferItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].isOptimizing = true

        Task {
            let updated = await Task.detached(priority: .userInitiated) { () -> TransferItem in
                var it = item
                let qTitle = it.title.isEmpty ? it.sourceURL.deletingPathExtension().lastPathComponent : it.title
                let qArtist = it.artist.isEmpty ? "" : it.artist

                if let fetched = await OnlineMetadataService.shared.fetchMetadata(
                    filename: it.sourceURL.lastPathComponent,
                    currentTitle: qTitle,
                    currentArtist: qArtist,
                    currentAlbum: it.album
                ) {
                    if it.title.isEmpty || it.title.lowercased() == "unknown" || it.title.lowercased() == "unknown track" {
                        it.title = WalkmanEngine.sanitizeWalkmanText(fetched.title)
                    }
                    if it.artist.isEmpty || it.artist.lowercased() == "unknown artist" || it.artist.lowercased() == "unknown" {
                        it.artist = WalkmanEngine.sanitizeWalkmanText(fetched.artist, stripExplicitMarkers: false)
                    }
                    if it.album.isEmpty || it.album.lowercased() == "unknown album" || it.album.lowercased() == "unknown" {
                        it.album = WalkmanEngine.sanitizeWalkmanText(fetched.album)
                    }
                    if it.year.isEmpty && !fetched.year.isEmpty {
                        it.year = fetched.year
                    }

                    if it.artworkData == nil, let artData = fetched.artworkData {
                        if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: artData, maxDimension: 800) {
                            it.artworkData = baseline
                            it.isArtworkOptimized = true
                        } else {
                            it.artworkData = artData
                        }
                    } else if it.artworkData == nil, let artURL = fetched.artworkURL {
                        if let (data, _) = try? await URLSession.shared.data(from: artURL) {
                            if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data, maxDimension: 800) {
                                it.artworkData = baseline
                                it.isArtworkOptimized = true
                            }
                        }
                    }
                }

                if let art = it.artworkData, !it.isArtworkOptimized {
                    if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: art, maxDimension: 800) {
                        it.artworkData = baseline
                        it.isArtworkOptimized = true
                    }
                }

                return it
            }.value

            await MainActor.run {
                if let i = self.queue.firstIndex(where: { $0.id == item.id }) {
                    self.queue[i].title = updated.title
                    self.queue[i].artist = updated.artist
                    self.queue[i].album = updated.album
                    self.queue[i].year = updated.year
                    self.queue[i].artworkData = updated.artworkData
                    self.queue[i].isArtworkOptimized = updated.isArtworkOptimized
                    self.queue[i].isOptimizing = false

                    if self.targetMode != .learning && self.fetchLyrics && self.queue[i].lyrics == nil {
                        self.fetchLyricsForTrack(self.queue[i])
                    }
                }
            }
        }
    }

    private func batchOptimizeAll() {
        guard !queue.isEmpty else { return }
        isBatchOptimizing = true
        batchStatusText = "Optimizing tags & cover art..."

        Task {
            for i in 0..<queue.count {
                guard isBatchOptimizing else { break }
                let it = queue[i]
                if it.isMissingMetadata || !it.isArtworkOptimized {
                    await withCheckedContinuation { continuation in
                        optimizeSingleTrack(it)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            continuation.resume()
                        }
                    }
                }
            }
            await MainActor.run {
                self.isBatchOptimizing = false
                self.batchStatusText = nil
            }
        }
    }

    private func fetchLyricsForTrack(_ item: TransferItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].isFetchingOnline = true

        Task {
            let art = item.artist
            let tit = item.title.isEmpty ? item.sourceURL.deletingPathExtension().lastPathComponent : item.title
            let alb = item.album

            let lyr = try? await LyricsService.shared.fetchLyrics(
                title: tit,
                artist: art,
                album: alb,
                durationSeconds: item.durationSeconds
            )

            await MainActor.run {
                if let i = self.queue.firstIndex(where: { $0.id == item.id }) {
                    if let l = lyr {
                        self.queue[i].lyrics = l.lyrics
                        self.queue[i].isLyricsSynced = l.synced
                    }
                    self.queue[i].isFetchingOnline = false
                }
            }
        }
    }

    private func batchFetchAllLyrics() {
        guard !queue.isEmpty else { return }
        isBatchFetchingLyrics = true
        batchStatusText = "Fetching lyrics from LRCLIB..."

        Task {
            for i in 0..<queue.count {
                guard isBatchFetchingLyrics else { break }
                let it = queue[i]
                if it.lyrics == nil {
                    await withCheckedContinuation { continuation in
                        fetchLyricsForTrack(it)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            continuation.resume()
                        }
                    }
                }
            }
            await MainActor.run {
                self.isBatchFetchingLyrics = false
                self.batchStatusText = nil
            }
        }
    }

    private func pickCustomArtwork(for itemId: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data, maxDimension: 800) {
                if let idx = queue.firstIndex(where: { $0.id == itemId }) {
                    queue[idx].artworkData = baseline
                    queue[idx].isArtworkOptimized = true
                }
            }
        }
    }

    private func startBatchTransfer(skipExistingDuplicates: Bool = true) {
        guard let target = selectedTarget else { return }
        isProcessing = true

        Task {
            let targetRootDir = targetMode == .learning
                ? URL(fileURLWithPath: target.learningDir)
                : URL(fileURLWithPath: target.musicDir)

            for i in 0..<queue.count {
                guard queue[i].status == .pending else { continue }
                queue[i].status = .converting

                let src = queue[i].sourceURL

                // Last-mile metadata recovery defense:
                var curArtist = WalkmanEngine.sanitizeWalkmanText(queue[i].artist, stripExplicitMarkers: false).trimmingCharacters(in: .whitespacesAndNewlines)
                var curAlbum = WalkmanEngine.sanitizeWalkmanText(queue[i].album).trimmingCharacters(in: .whitespacesAndNewlines)
                var curTitle = WalkmanEngine.sanitizeWalkmanText(queue[i].title).trimmingCharacters(in: .whitespacesAndNewlines)
                var curTrackNum = queue[i].trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)

                let isArtistUnknown = curArtist.isEmpty || curArtist.lowercased() == "unknown artist" || curArtist.lowercased() == "unknown"
                let isAlbumUnknown = curAlbum.isEmpty || curAlbum.lowercased() == "unknown album" || curAlbum.lowercased() == "unknown"
                let isTitleUnknown = curTitle.isEmpty || curTitle.lowercased() == "unknown" || curTitle.lowercased() == "unknown track" || curTitle.lowercased() == "unknown title"

                if isArtistUnknown || isAlbumUnknown || isTitleUnknown {
                    if let recovered = AudioTagger.shared.readMetadata(fileURL: src) {
                        let recArtist = WalkmanEngine.sanitizeWalkmanText(recovered.artist, stripExplicitMarkers: false)
                        let recAlbum = WalkmanEngine.sanitizeWalkmanText(recovered.album)
                        let recTitle = WalkmanEngine.sanitizeWalkmanText(recovered.title)

                        if isArtistUnknown && !recArtist.isEmpty && recArtist.lowercased() != "unknown artist" && recArtist.lowercased() != "unknown" {
                            curArtist = recArtist
                            queue[i].artist = recArtist
                        }
                        if isAlbumUnknown && !recAlbum.isEmpty && recAlbum.lowercased() != "unknown album" && recAlbum.lowercased() != "unknown" {
                            curAlbum = recAlbum
                            queue[i].album = recAlbum
                        }
                        if isTitleUnknown && !recTitle.isEmpty && recTitle.lowercased() != "unknown" && recTitle.lowercased() != "unknown track" && recTitle.lowercased() != "unknown title" {
                            curTitle = recTitle
                            queue[i].title = recTitle
                        }
                        if curTrackNum.isEmpty && !recovered.trackNumber.isEmpty {
                            curTrackNum = recovered.trackNumber
                            queue[i].trackNumber = recovered.trackNumber
                        }
                    }
                }

                let stillArtistUnknown = curArtist.isEmpty || curArtist.lowercased() == "unknown artist" || curArtist.lowercased() == "unknown"
                let stillAlbumUnknown = curAlbum.isEmpty || curAlbum.lowercased() == "unknown album" || curAlbum.lowercased() == "unknown"
                let stillTitleUnknown = curTitle.isEmpty || curTitle.lowercased() == "unknown" || curTitle.lowercased() == "unknown track" || curTitle.lowercased() == "unknown title"

                if stillArtistUnknown || stillAlbumUnknown || stillTitleUnknown {
                    let fromPath = AudioTagger.extractFromPath(url: src)
                    let pArtist = WalkmanEngine.sanitizeWalkmanText(fromPath.artist, stripExplicitMarkers: false)
                    let pAlbum = WalkmanEngine.sanitizeWalkmanText(fromPath.album)
                    let pTitle = WalkmanEngine.sanitizeWalkmanText(fromPath.title)

                    if stillArtistUnknown && !pArtist.isEmpty && pArtist.lowercased() != "unknown artist" && pArtist.lowercased() != "unknown" {
                        curArtist = pArtist
                        queue[i].artist = pArtist
                    }
                    if stillAlbumUnknown && !pAlbum.isEmpty && pAlbum.lowercased() != "unknown album" && pAlbum.lowercased() != "unknown" {
                        curAlbum = pAlbum
                        queue[i].album = pAlbum
                    }
                    if stillTitleUnknown && !pTitle.isEmpty && pTitle.lowercased() != "unknown" && pTitle.lowercased() != "unknown track" {
                        curTitle = pTitle
                        queue[i].title = pTitle
                    }
                }

                if curTitle.isEmpty || curTitle.lowercased() == "unknown" || curTitle.lowercased() == "unknown track" || curTitle.lowercased() == "unknown title" {
                    let stem = WalkmanEngine.sanitizeWalkmanText(src.deletingPathExtension().lastPathComponent)
                    if !stem.isEmpty && stem.lowercased() != "unknown" {
                        curTitle = stem
                        queue[i].title = stem
                    }
                }

                let cleanArtist = WalkmanEngine.shared.sanitizeFilename(curArtist.isEmpty ? "Unknown Artist" : curArtist)
                let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(curAlbum.isEmpty ? "Unknown Album" : curAlbum)
                var cleanTitle = WalkmanEngine.shared.sanitizeFilename(curTitle)
                let trackNum = curTrackNum.isEmpty ? "01" : curTrackNum

                if cleanTitle.isEmpty || cleanTitle.lowercased() == "unknown" {
                    let stem = WalkmanEngine.shared.sanitizeFilename(src.deletingPathExtension().lastPathComponent)
                    if !stem.isEmpty && stem.lowercased() != "unknown" {
                        cleanTitle = stem
                    } else {
                        cleanTitle = "Track \(trackNum)"
                    }
                }

                let ext = destinationExtension(for: src)

                let dest = WalkmanEngine.shared.targetTrackURL(
                    musicRoot: targetRootDir,
                    artist: cleanArtist,
                    album: cleanAlbum,
                    trackNum: trackNum,
                    title: cleanTitle,
                    ext: ext
                )

                let albumDir = dest.deletingLastPathComponent()

                // Duplicate Guardrail: Check if track is already present on target Walkman storage
                if skipExistingDuplicates {
                    let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                        title: curTitle,
                        artist: curArtist,
                        album: curAlbum,
                        durationSeconds: queue[i].durationSeconds,
                        sourceURL: src,
                        targetDrive: target,
                        targetMode: targetMode,
                        existingTracks: libraryTracks
                    )
                    if dupCheck.isDuplicate || FileManager.default.fileExists(atPath: dest.path) {
                        let reason = dupCheck.reason ?? "Already exists on \(target.name)"
                        await MainActor.run {
                            if i < self.queue.count {
                                self.queue[i].status = .skipped(reason)
                                self.queue[i].isDuplicateOnWalkman = true
                                self.queue[i].duplicateMatchInfo = reason
                            }
                        }
                        continue
                    }
                }

                do {
                    try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)

                    // 1. Audio Transfer / Transcode
                    if selectedPreset == "copy_optimize" || selectedPreset == "copy_raw" {
                        if src.pathExtension.lowercased() == ext.lowercased() {
                            try? FileManager.default.removeItem(at: dest)
                            try FileManager.default.copyItem(at: src, to: dest)
                        } else {
                            try await WalkmanEngine.shared.transcodeAudio(
                                sourceURL: src,
                                destinationURL: dest,
                                preset: "copy",
                                normalizeVolume: false
                            )
                        }
                    } else {
                        try await WalkmanEngine.shared.transcodeAudio(
                            sourceURL: src,
                            destinationURL: dest,
                            preset: selectedPreset,
                            normalizeVolume: normalizeVolume
                        )
                    }

                    // 2. Hardware Metadata & Baseline JPEG Embedding
                    if selectedPreset != "copy_raw" {
                        var finalArtData = queue[i].artworkData
                        if optimizeArtwork, let art = finalArtData {
                            finalArtData = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: art, maxDimension: 800) ?? art
                        }

                        let destExt = dest.pathExtension.lowercased()
                        if destExt == "flac" || destExt == "mp3" || destExt == "m4a" || destExt == "alac" || destExt == "mp4" {
                            let rawTitle = WalkmanEngine.sanitizeWalkmanText(queue[i].title).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagTitle = (rawTitle.isEmpty || rawTitle.lowercased() == "unknown" || rawTitle.lowercased() == "unknown track" || rawTitle.lowercased() == "unknown title") ? cleanTitle : rawTitle
                            let rawArtist = WalkmanEngine.sanitizeWalkmanText(queue[i].artist, stripExplicitMarkers: false).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagArtist = (rawArtist.isEmpty || rawArtist.lowercased() == "unknown artist" || rawArtist.lowercased() == "unknown") ? (cleanArtist.lowercased() == "unknown artist" ? nil : cleanArtist) : rawArtist
                            let rawAlbum = WalkmanEngine.sanitizeWalkmanText(queue[i].album).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagAlbum = (rawAlbum.isEmpty || rawAlbum.lowercased() == "unknown album" || rawAlbum.lowercased() == "unknown") ? (cleanAlbum.lowercased() == "unknown album" ? nil : cleanAlbum) : rawAlbum
                            
                            let rawTrackNum = queue[i].trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagTrackNum = (!rawTrackNum.isEmpty && rawTrackNum != "0") ? rawTrackNum : trackNum
                            let tagYear = queue[i].year.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Category Optimization: Set "Language Learning" genre for Walkman firmware classification
                            let rawGenre = queue[i].genre.trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagGenre: String?
                            if targetMode == .learning {
                                let lowerG = rawGenre.lowercased()
                                if lowerG.contains("audiobook") || lowerG.contains("podcast") || lowerG.contains("speech") {
                                    tagGenre = rawGenre
                                } else {
                                    tagGenre = "Language Learning"
                                }
                            } else {
                                tagGenre = rawGenre.isEmpty ? nil : rawGenre
                            }

                            // 2a. Resolve lyrics if enabled
                            var finalLyrics = queue[i].lyrics
                            if targetMode != .learning && fetchLyrics {
                                if finalLyrics == nil || finalLyrics!.isEmpty {
                                    let tit = queue[i].title.isEmpty ? src.deletingPathExtension().lastPathComponent : queue[i].title
                                    if let fetched = try? await LyricsService.shared.fetchLyrics(
                                        title: tit,
                                        artist: queue[i].artist,
                                        album: queue[i].album,
                                        durationSeconds: queue[i].durationSeconds
                                    ) {
                                        finalLyrics = fetched.lyrics
                                        let syn = fetched.synced
                                        await MainActor.run {
                                            if i < self.queue.count {
                                                self.queue[i].lyrics = fetched.lyrics
                                                self.queue[i].isLyricsSynced = syn
                                            }
                                        }
                                    }
                                }
                            }

                            do {
                                try AudioTagger.shared.writeMetadata(
                                    fileURL: dest,
                                    title: tagTitle.isEmpty ? nil : tagTitle,
                                    artist: tagArtist?.isEmpty == true ? nil : tagArtist,
                                    album: tagAlbum?.isEmpty == true ? nil : tagAlbum,
                                    trackNumber: tagTrackNum.isEmpty ? nil : tagTrackNum,
                                    year: tagYear.isEmpty ? nil : tagYear,
                                    genre: tagGenre,
                                    coverArtData: finalArtData,
                                    lyrics: finalLyrics
                                )
                            } catch {
                                print("[TransferQueue] Error writing metadata to \(dest.lastPathComponent): \(error)")
                            }
                        }
                    }

                    // 2b. Sony 12 Tone Analysis / SenseMe Injection
                    if autoSenseMe {
                        let destExt = dest.pathExtension.lowercased()
                        if destExt == "flac" || destExt == "mp3" || destExt == "m4a" || destExt == "alac" {
                            let inspectRes = SenseMeEngine.shared.inspect(fileURL: dest)
                            if !inspectRes.isAnalyzed {
                                if destExt == "flac", src.pathExtension.lowercased() == "flac",
                                   let existingPayload = SenseMeEngine.shared.extractPayload(fileURL: src) {
                                    try? SenseMeEngine.shared.injectFLAC(fileURL: dest, payload: existingPayload)
                                } else if destExt == "mp3", src.pathExtension.lowercased() == "mp3",
                                   let existingPayload = SenseMeEngine.shared.extractPayload(fileURL: src) {
                                    try? SenseMeEngine.shared.injectMP3(fileURL: dest, payload: existingPayload)
                                } else {
                                    _ = try? await SenseMeEngine.shared.analyzeAndInject(fileURL: dest)
                                }
                            }
                        }
                    }

                    // 3. Companion .LRC Lyrics / Transcript Writing
                    if targetMode != .learning {
                        var lyrToWrite = queue[i].lyrics
                        if (lyrToWrite == nil || lyrToWrite!.isEmpty) && fetchLyrics {
                            let tit = queue[i].title.isEmpty ? src.deletingPathExtension().lastPathComponent : queue[i].title
                            if let fetched = try? await LyricsService.shared.fetchLyrics(
                                title: tit,
                                artist: queue[i].artist,
                                album: queue[i].album,
                                durationSeconds: queue[i].durationSeconds
                            ) {
                                lyrToWrite = fetched.lyrics
                            }
                        }
                        if let lyr = lyrToWrite, !lyr.isEmpty {
                            try? WalkmanEngine.shared.writeCompanionLyrics(
                                destinationAudioURL: dest,
                                lyrics: lyr,
                                durationSeconds: queue[i].durationSeconds
                            )
                        }
                    }

                    // 4. Save folder.jpg and cover.jpg in Album Folder for Walkman Album browser
                    if (saveFolderJpg || targetMode == .learning), let art = queue[i].artworkData {
                        try? WalkmanEngine.shared.writeAlbumFolderArtwork(albumDirectoryURL: albumDir, artworkData: art)
                    }

                    // 5. Clean macOS Extended Attributes & AppleDouble Shadows
                    let cPath = (dest.path as NSString).fileSystemRepresentation
                    removexattr(cPath, "com.apple.TextEncoding", 0)
                    let dotfile = albumDir.appendingPathComponent("._" + dest.lastPathComponent)
                    try? FileManager.default.removeItem(at: dotfile)
                    
                    // 6. Recent Transfers Optimization: Stagger file modification timestamp
                    // so the Walkman hardware SQLite database lists them at the top of "Recent Transfers"
                    // in sequential chronological chapter order
                    let transferTimestamp = Date().addingTimeInterval(Double(i) * 0.2)
                    try? FileManager.default.setAttributes([
                        .modificationDate: transferTimestamp,
                        .creationDate: transferTimestamp
                    ], ofItemAtPath: dest.path)
                    
                    sync()

                    queue[i].status = .success
                } catch {
                    queue[i].status = .failed(error.localizedDescription)
                }
            }

            // 7. Playlists Optimization: Generate Language Study M3U8 Playlist
            // Groups transferred files by album/series into /LEARNING/{Album}.m3u8 so the Walkman's
            // "Language Study -> Playlists" screen immediately displays the complete playable playlist!
            if targetMode == .learning {
                var albumGroups: [String: [String]] = [:]
                for itm in queue where itm.status == .success {
                    let cArtist = WalkmanEngine.shared.sanitizeFilename(itm.artist.isEmpty ? "Unknown Artist" : itm.artist)
                    let cAlbum = WalkmanEngine.shared.sanitizeFilename(itm.album.isEmpty ? "Unknown Album" : itm.album)
                    let ext = destinationExtension(for: itm.sourceURL)
                    let tInt = Int(itm.trackNumber.components(separatedBy: "/").first ?? "1") ?? 1
                    let trackPrefix = String(format: "%02d", tInt)
                    let cTitle = WalkmanEngine.shared.sanitizeFilename(itm.title.isEmpty ? itm.sourceURL.deletingPathExtension().lastPathComponent : itm.title)
                    let filename = "\(trackPrefix) - \(cTitle).\(ext)"
                    let relPath = "\(cArtist)/\(cAlbum)/\(filename)"
                    albumGroups[cAlbum, default: []].append(relPath)
                }
                
                for (albumName, relTracks) in albumGroups {
                    _ = try? WalkmanEngine.shared.writePlaylist(
                        musicDir: targetRootDir,
                        name: albumName,
                        relativeTracks: relTracks
                    )
                }
            }

            if isLocalDestination {
                LocalMusicLibraryService.shared.addFolders(urls: [targetRootDir])
                LocalMusicLibraryService.shared.rescanFolder(url: targetRootDir)
            }

            isProcessing = false
            onTransferComplete()
        }
    }
}

// -----------------------------------------------------------------------------
// ENHANCED QUEUE ITEM ROW (PREMIUM GLASS CARD DESIGN)
// -----------------------------------------------------------------------------
private struct QueueItemRow: View {
    @Binding var item: TransferItem
    let isThisPlaying: Bool
    let destinationExtension: String
    var rootFolderName: String = "MUSIC"
    var isLearningMode: Bool = false
    let onTogglePlay: () -> Void
    let onPickArtwork: () -> Void
    let onOptimize: () -> Void
    let onFetchLyrics: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Play / Pause preview button
                Button(action: onTogglePlay) {
                    ZStack {
                        Circle()
                            .fill(isThisPlaying ? AnyShapeStyle(WalkmanTheme.silverGradient) : AnyShapeStyle(Color.white.opacity(isHovered ? 0.16 : 0.09)))
                            .frame(width: 32, height: 32)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isThisPlaying ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white)
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(isThisPlaying ? "Pause audio preview" : "Play audio preview")

                // Cover Artwork Thumbnail with Hardware Compliance Badge
                ZStack(alignment: .bottomTrailing) {
                    if let artData = item.artworkData, let img = NSImage(data: artData) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.tertiary)
                            )
                    }

                    // Compliance indicator dot
                    if item.artworkData != nil {
                        Circle()
                            .fill(item.isArtworkOptimized ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isThisPlaying ? WalkmanTheme.silver : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                .onTapGesture {
                    onPickArtwork()
                }
                .help("Click to select custom album art or inspect compliance")

                // Track Details & Metadata Hierarchy
                VStack(alignment: .leading, spacing: 3) {
                    // Line 1: Track Number Badge + Title & Badges
                    HStack(spacing: 6) {
                        let tNum = item.trackNumber.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? ""
                        if !tNum.isEmpty, let numInt = Int(tNum), numInt > 0 {
                            Text(String(format: "%02d", numInt))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(WalkmanTheme.hiResGold.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                        .stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.75)
                                )
                                .help("Track \(numInt)")
                        }

                        Text(item.title.isEmpty ? item.sourceURL.deletingPathExtension().lastPathComponent : item.title)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if item.bitsPerSample > 16 || item.sampleRate > 48000 {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(WalkmanTheme.hiResGoldGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 2.5))
                        }

                        if item.isDuplicateOnWalkman {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                Text("On Walkman")
                                    .font(WalkmanFont.badge)
                            }
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 2.5))
                            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.orange.opacity(0.4), lineWidth: 0.6))
                            .help(item.duplicateMatchInfo ?? "Already present on Walkman library")
                        }
                    }

                    // Line 2: Artist • Album (Year)
                    HStack(spacing: 5) {
                        let artistText = item.artist.isEmpty ? "Unknown Artist" : item.artist
                        let albumText = item.album.isEmpty ? "Unknown Album" : item.album
                        Text("\(artistText) • \(albumText)")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !item.year.isEmpty {
                            Text("(\(item.year))")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Line 3: Tech Specs & Route Preview
                    HStack(spacing: 6) {
                        let quality = item.sampleRate > 0 ? "\(item.bitsPerSample)b/\(item.sampleRate/1000)k" : item.format
                        Text(quality)
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white.opacity(0.85))

                        if item.bitrateKbps > 0 {
                            Text("\(item.bitrateKbps)k")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if item.durationSeconds > 0 {
                            Text(WalkmanEngine.formatDuration(item.durationSeconds))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if let lyr = item.lyrics, !lyr.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 8))
                                Text(item.isLyricsSynced ? "Synced .LRC" : "Plain Lyrics")
                                    .font(WalkmanFont.badge)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        }

                        // Subtle clean destination breadcrumb
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                            let cleanArtist = WalkmanEngine.shared.sanitizeFilename(item.artist.isEmpty ? "Unknown Artist" : item.artist)
                            let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(item.album.isEmpty ? "Unknown Album" : item.album)
                            let cleanTitle = WalkmanEngine.shared.sanitizeFilename(item.title.isEmpty ? item.sourceURL.deletingPathExtension().lastPathComponent : item.title)
                            let tInt = Int(item.trackNumber.components(separatedBy: "/").first ?? "1") ?? 1
                            let trackPrefix = String(format: "%02d", tInt)
                            Text("/\(rootFolderName)/\(cleanArtist)/\(cleanAlbum)/\(trackPrefix) - \(cleanTitle).\(destinationExtension)")
                                .font(WalkmanFont.monoSmall)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.secondary.opacity(0.65))
                    }
                }

                Spacer()

                // Status Badge
                switch item.status {
                case .pending:
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 5, height: 5)
                        Text("Ready")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())

                case .optimizing:
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        Text("Optimizing...")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())

                case .converting:
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("Transferring...")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(WalkmanTheme.hiResGold.opacity(0.15))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .clipShape(Capsule())

                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Transferred")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())

                case .skipped(let reason):
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(WalkmanFont.badge)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .help(reason)

                case .failed(let err):
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text(err)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Row Action Buttons
                HStack(spacing: 4) {
                    if !isLearningMode && item.isMissingMetadata {
                        Button(action: onOptimize) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .padding(6)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Auto-fetch missing metadata from internet")
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHovered ? .white : .secondary)
                            .padding(6)
                            .background(Color.white.opacity(isHovered ? 0.12 : 0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit tags, artwork, lyrics, and destination in popup window")

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.white.opacity(isHovered ? 0.08 : 0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isThisPlaying ? Color.white.opacity(0.08) : (isHovered ? WalkmanTheme.cardHover : WalkmanTheme.card.opacity(0.55)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isThisPlaying ? WalkmanTheme.silver.opacity(0.4) : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04)), lineWidth: 1)
        )
        .onHover { h in isHovered = h }
        .onTapGesture(count: 2) {
            onEdit()
        }
        .contextMenu {
            Button(action: onTogglePlay) {
                Label(isThisPlaying ? "Pause Preview" : "Play Preview", systemImage: isThisPlaying ? "pause.fill" : "play.fill")
            }
            Divider()
            if !isLearningMode {
                Button(action: onOptimize) {
                    Label("Fetch Online Tags & Cover Art", systemImage: "sparkles")
                }
                Button(action: onFetchLyrics) {
                    Label("Fetch Synchronized Lyrics (.LRC)", systemImage: "quote.bubble")
                }
            }
            Button(action: onPickArtwork) {
                Label("Choose Custom Album Art...", systemImage: "photo")
            }
            Button(action: onEdit) {
                Label("Edit Metadata & Artwork...", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Queue", systemImage: "trash")
            }
        }
    }
}

// MARK: - Transfer Mode Segmented Bar View (Liquid Glass Matched Geometry)
private struct TransferModeSegmentedBarView: View {
    @Binding var targetMode: TransferTargetMode
    let onSelectMode: (TransferTargetMode) -> Void

    @Namespace private var modeNamespace
    @State private var activeModeId: String = TransferTargetMode.music.id

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TransferTargetMode.allCases) { mode in
                TransferModeTabPillView(
                    mode: mode,
                    isSelected: activeModeId == mode.id,
                    namespace: modeNamespace,
                    onSelect: {
                        guard targetMode != mode else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeModeId = mode.id
                        }
                        onSelectMode(mode)
                    }
                )
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeModeId = targetMode.id
        }
        .onChange(of: targetMode) { _, newMode in
            if activeModeId != newMode.id {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeModeId = newMode.id
                }
            }
        }
    }
}

private struct TransferModeTabPillView: View {
    let mode: TransferTargetMode
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovered = false

    private var labelTitle: String {
        switch mode {
        case .music:
            return "Music Library"
        case .learning:
            return "Language Study"
        }
    }

    private var isGold: Bool {
        mode == .learning
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                Text(labelTitle)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    (isGold ? WalkmanTheme.hiResGoldLight : Color.white) :
                    (isHovered ? (isGold ? WalkmanTheme.hiResGoldLight : Color.white) : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        ActiveModePillBackground(isGold: isGold, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeTransferModeHighlight", in: namespace)
                    } else if isHovered {
                        HoverModePillBackground()
                    } else {
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

// MARK: - Active & Hover Mode Pill Backgrounds (Liquid Glass Sliding Lens)
private struct ActiveModePillBackground: View {
    let isGold: Bool
    var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Translucent Body Fill
            if isGold {
                WalkmanTheme.hiResGold.opacity(isHovered ? 0.24 : 0.18)
            } else {
                Color.white.opacity(isHovered ? 0.20 : 0.16)
            }

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
                    isGold ?
                        WalkmanTheme.hiResGold.opacity(isHovered ? 0.70 : 0.55) :
                        Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.30 : 0.22),
            radius: isHovered ? 4 : 2.5,
            x: 0,
            y: 1
        )
    }
}

private struct HoverModePillBackground: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.09)
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
            Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Hardware Optimization Toggle Chip View (32pt Liquid Glass Capsule)
private struct HardwareOptimizationToggleChipView: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let help: String
    var disabled: Bool = false

    @State private var isHovered = false

    private var isEffectivelyOn: Bool {
        !disabled && isOn
    }

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            HStack(spacing: 5.5) {
                Image(systemName: isEffectivelyOn ? "\(icon).fill" : icon)
                    .font(.system(size: 10.5, weight: isEffectivelyOn ? .semibold : .regular))
                    .foregroundStyle(
                        isEffectivelyOn ?
                            WalkmanTheme.silverLight :
                            (isHovered ? Color.white : WalkmanTheme.silverMuted)
                    )

                Text(title)
                    .font(.system(size: 12, weight: isEffectivelyOn ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(
                        isEffectivelyOn ?
                            Color.white :
                            (isHovered ? Color.white : WalkmanTheme.silverMuted)
                    )

                if isEffectivelyOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                ZStack {
                    if isEffectivelyOn {
                        Color.white.opacity(isHovered ? 0.18 : 0.14)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(isHovered ? 0.38 : 0.28), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5.5)
                            Spacer(minLength: 0)
                        }
                    } else if isHovered {
                        Color.white.opacity(0.09)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.18), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5)
                            Spacer(minLength: 0)
                        }
                    } else {
                        Color.white.opacity(0.04)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isEffectivelyOn ?
                            Color.white.opacity(isHovered ? 0.48 : 0.38) :
                            (isHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
                        lineWidth: 0.85
                    )
            )
            .shadow(
                color: Color.black.opacity(isEffectivelyOn ? (isHovered ? 0.25 : 0.16) : (isHovered ? 0.12 : 0)),
                radius: isHovered ? 3 : 2,
                x: 0,
                y: 1
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .zIndex(isHovered ? 2 : 1)
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1.0)
        .help(help)
        .onHover { hovering in
            guard !disabled else { return }
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

// MARK: - Transfer Batch Action Button (32pt Liquid Glass Capsule)
private struct TransferBatchActionButton: View {
    let title: String
    let icon: String
    var isLoading: Bool = false
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.5) {
                if isLoading {
                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(height: 32)
            .foregroundStyle(
                isDestructive ?
                    (isHovered ? Color(red: 255/255, green: 130/255, blue: 120/255) : Color(red: 255/255, green: 105/255, blue: 95/255)) :
                    (isHovered ? Color.white : WalkmanTheme.silverLight)
            )
            .background(
                ZStack {
                    if isDestructive {
                        Color.red.opacity(isHovered ? 0.18 : 0.10)
                    } else {
                        Color.white.opacity(isHovered ? 0.12 : 0.06)
                    }

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHovered ? 0.20 : 0.10), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 5)
                        Spacer(minLength: 0)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isDestructive ?
                            Color.red.opacity(isHovered ? 0.40 : 0.22) :
                            Color.white.opacity(isHovered ? 0.22 : 0.10),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0), radius: 2, y: 1)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .zIndex(isHovered ? 2 : 1)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .help(help)
        .onHover { hovering in
            guard !isDisabled else { return }
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

// MARK: - Liquid Glass Dropdown Menu (38pt Standard Dropdown)
private struct LiquidGlassDropdownMenu<Content: View>: View {
    let title: String
    @ViewBuilder let menuContent: () -> Content

    @State private var isHovered = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                ZStack {
                    Color.white.opacity(isHovered ? 0.12 : 0.07)
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHovered ? 0.24 : 0.14), location: 0.0),
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.32 : 0.14), lineWidth: 0.85)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.20 : 0.10), radius: 2, y: 1)
            .scaleEffect(isHovered ? 1.015 : 1.0)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
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

// MARK: - Safe Scroll Clip Disabler (macOS 14+ with fallback)
private extension View {
    @ViewBuilder
    func disableScrollClipIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}

// MARK: - Import Progress Bar (Liquid Glass)
private struct ImportProgressBar: View {
    let progress: Double
    let isIndeterminate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Capsule Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.85))

                // Fill Bar
                if !isIndeterminate {
                    let fillWidth = max(8, geo.size.width * CGFloat(min(max(progress, 0.0), 1.0)))
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: WalkmanTheme.silverLight, location: 0.0),
                                    .init(color: WalkmanTheme.silver, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .overlay(
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.60), location: 0.0),
                                        .init(color: Color.clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 3)
                                Spacer(minLength: 0)
                            }
                            .clipShape(Capsule())
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                } else {
                    IndeterminateLiquidGlassBar()
                }
            }
        }
        .frame(height: 8)
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82), value: progress)
    }
}

// MARK: - Indeterminate Liquid Glass Bar
private struct IndeterminateLiquidGlassBar: View {
    @State private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { _ in
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.0), location: max(0.0, phase - 0.2)),
                            .init(color: Color.white.opacity(0.55), location: min(max(0.0, phase), 1.0)),
                            .init(color: Color.white.opacity(0.0), location: min(1.0, phase + 0.2))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
    }
}
