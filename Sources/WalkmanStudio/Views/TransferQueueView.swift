import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TransferQueueView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let onTransferComplete: () -> Void

    @State private var targetDriveId: String = ""
    @State private var targetMode: TransferTargetMode = .music
    @State private var selectedPreset: String = "copy_optimize"
    @State private var queue: [TransferItem] = []
    @State private var isProcessing: Bool = false
    @State private var isTargeted: Bool = false
    @State private var queueSearchText: String = ""

    // Liquid Glass Sheets
    @State private var itemToEdit: TransferItem? = nil
    @State private var showTransferConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false

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

    public init(drives: [WalkmanDrive], activeDrive: WalkmanDrive?, onTransferComplete: @escaping () -> Void) {
        self.drives = drives
        self.activeDrive = activeDrive
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

    private var modeButtonsView: some View {
        HStack(spacing: 3) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    targetMode = .music
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Music Library (/MUSIC)")
                        .font(WalkmanFont.calloutBold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(targetMode == .music ? Color.white.opacity(0.14) : Color.clear)
                )
                .foregroundStyle(targetMode == .music ? .white : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    targetMode = .learning
                    if selectedPreset == "flac_16" || selectedPreset == "flac_24_96" {
                        selectedPreset = "copy_optimize"
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Language Study & Audiobooks (/LEARNING)")
                        .font(WalkmanFont.calloutBold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(targetMode == .learning ? WalkmanTheme.hiResGold.opacity(0.2) : Color.clear)
                )
                .foregroundStyle(targetMode == .learning ? WalkmanTheme.hiResGold : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var modeInformationalPill: some View {
        Group {
            if targetMode == .learning {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                    Text("DPC Speed (0.5x–2.0x) • A-B Repeat • Quick Replay (3s/10s)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.hiResGold.opacity(0.95))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WalkmanTheme.hiResGold.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.25), lineWidth: 0.8)
                )
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text("Standard Walkman Library • Playlists • Hi-Res Audio")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
            }
        }
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // -------------------------------------------------------------
                // PANEL 0: DESTINATION MODE SELECTOR (Music vs Language Study)
                // -------------------------------------------------------------
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        modeButtonsView
                        Spacer()
                        modeInformationalPill
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        modeButtonsView
                        modeInformationalPill
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // -------------------------------------------------------------
                // PANEL 1: CONFIGURATION CONTROL DECK (EQUAL-WIDTH CARDS)
                // -------------------------------------------------------------
                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let cardWidth = max(0, (geo.size.width - spacing * 2) / 3.0)
                    let cardHeight: CGFloat = 100

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
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(WalkmanTheme.silver)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                        .liquidGlass(cornerRadius: 11)

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
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(WalkmanTheme.silver)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                        .liquidGlass(cornerRadius: 11)

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
                                            .scaleEffect(0.65)
                                        let doneCount = queue.filter { $0.status == .success }.count
                                        Text("Transferring (\(doneCount)/\(queue.count))...")
                                            .font(WalkmanFont.calloutBold)
                                    } else {
                                        Image(systemName: queue.isEmpty ? "arrow.right.circle" : "arrow.right.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(queue.isEmpty ? "Queue Empty" : "Start Transfer (\(queue.count))")
                                            .font(WalkmanFont.calloutBold)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    Group {
                                        if queue.isEmpty {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                        } else if isProcessing {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.35))
                                        } else {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(white: 0.94), Color(white: 0.80)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        }
                                    }
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(queue.isEmpty ? Color.white.opacity(0.08) : Color.white.opacity(0.35), lineWidth: 0.5)
                                )
                                .foregroundStyle(queue.isEmpty ? Color.white.opacity(0.35) : Color(red: 18/255, green: 18/255, blue: 22/255))
                                .shadow(color: queue.isEmpty ? Color.clear : Color.black.opacity(0.3), radius: 2.5, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
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
                        .liquidGlass(cornerRadius: 11)
                    }
                }
                .frame(height: 100)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // -------------------------------------------------------------
                // PANEL 2: HARDWARE OPTIMIZATION CAPSULES & BATCH ACTIONS
                // -------------------------------------------------------------
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
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
                    }

                    Spacer()

                    if !queue.isEmpty {
                        batchToolbarButtons
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(cornerRadius: 9)
                .padding(.horizontal, 16)

                // -------------------------------------------------------------
                // PANEL 3: EMPTY DROPZONE vs POPULATED QUEUE CONTAINER
                // -------------------------------------------------------------
                if queue.isEmpty {
                    // EMPTY STATE: Large, inviting drop zone
                    emptyDropZone
                        .padding(.horizontal, 16)
                        .padding(.bottom, 88)
                } else {
                    // POPULATED STATE: High-end Queue View (No huge redundant drop box!)
                    VStack(spacing: 0) {
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
                                HStack(spacing: 5) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)

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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Sort")
                                        .font(WalkmanFont.calloutMedium)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(.plain)
                            .help("Sort queue items by track number, filename, or album")

                            // Add More Files Button
                            Button(action: openFilePicker) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Add Files...")
                                        .font(WalkmanFont.calloutMedium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Add more audio files or folders to the transfer queue")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(WalkmanTheme.card.opacity(0.9))
                        .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)

                        // Scrollable Queue Cards List
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredQueueIndices.filter { $0 < queue.count }, id: \.self) { idx in
                                    QueueItemRow(
                                        item: $queue[idx],
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
                onConfirm: {
                    showTransferConfirmation = false
                    startBatchTransfer()
                },
                onCancel: {
                    showTransferConfirmation = false
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
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                        Text("Browse Audio Files or Folders...")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // -------------------------------------------------------------------------
    // HARDWARE TOGGLE CAPSULE CHIP
    // -------------------------------------------------------------------------
    private func toggleChip(title: String, icon: String, isOn: Binding<Bool>, help: String, disabled: Bool = false) -> some View {
        let isEffectivelyOn = !disabled && isOn.wrappedValue
        return Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 5) {
                Image(systemName: isEffectivelyOn ? "\(icon).fill" : icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isEffectivelyOn ? WalkmanTheme.silverLight : .secondary)
                Text(title)
                    .font(WalkmanFont.subheadlineMedium)
                    .foregroundStyle(isEffectivelyOn ? .white : .secondary)
                if isEffectivelyOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isEffectivelyOn ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isEffectivelyOn ? WalkmanTheme.silver.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
        .help(help)
    }

    // -------------------------------------------------------------------------
    // BATCH TOOLBAR BUTTONS
    // -------------------------------------------------------------------------
    private var batchToolbarButtons: some View {
        HStack(spacing: 6) {
            if targetMode != .learning {
                Button(action: batchOptimizeAll) {
                    HStack(spacing: 4) {
                        if isBatchOptimizing {
                            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                        }
                        Text(isBatchOptimizing ? "Optimizing..." : "Optimize All")
                            .font(WalkmanFont.subheadlineMedium)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBatchOptimizing || isProcessing)
                .help("Fetches missing metadata and optimizes cover artwork to Baseline RGB JPEG for all tracks")

                Button(action: batchFetchAllLyrics) {
                    HStack(spacing: 4) {
                        if isBatchFetchingLyrics {
                            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 10))
                        }
                        Text(isBatchFetchingLyrics ? "Fetching..." : "Fetch Lyrics")
                            .font(WalkmanFont.subheadlineMedium)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBatchFetchingLyrics || isProcessing)
                .help("Fetches synchronized .LRC lyrics for all tracks in the queue")
            }

            Button(action: {
                if !queue.isEmpty {
                    showClearConfirmation = true
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Clear")
                        .font(WalkmanFont.subheadlineMedium)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color(red: 255/255, green: 110/255, blue: 100/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .help("Clear all tracks from the queue")
        }
    }

    // -------------------------------------------------------------------------
    // HELPERS & INGESTION
    // -------------------------------------------------------------------------
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
            addURLsToQueue(panel.urls)
        }
    }

    private func addURLToQueue(_ url: URL) {
        addURLsToQueue([url])
    }

    private func addURLsToQueue(_ urls: [URL]) {
        let supportedExtensions: Set<String> = [
            "flac", "mp3", "m4a", "m4b", "wav", "aac", "alac", "aiff", "dsf", "dff", "wma", "ogg", "opus"
        ]
        var collectedURLs: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for case let fileURL as URL in enumerator {
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

        // Natural Finder-style sorting ensures 01 - Song, 02 - Song, ... are perfectly ordered
        collectedURLs.sort { urlA, urlB in
            urlA.path.localizedStandardCompare(urlB.path) == .orderedAscending
        }

        for fileURL in collectedURLs {
            enqueueSingleFile(fileURL)
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

    private func enqueueSingleFile(_ url: URL) {
        if queue.contains(where: { $0.sourceURL == url }) { return }

        var item = TransferItem(sourceURL: url)
        item.title = WalkmanEngine.sanitizeWalkmanText(url.deletingPathExtension().lastPathComponent)
        item.format = url.pathExtension.uppercased()

        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) {
            item.sizeBytes = attr[.size] as? Int64 ?? 0
        }

        let pathFallback = AudioTagger.extractFromPath(url: url)
        if !pathFallback.artist.isEmpty { item.artist = WalkmanEngine.sanitizeWalkmanText(pathFallback.artist, stripExplicitMarkers: false) }
        if !pathFallback.album.isEmpty { item.album = WalkmanEngine.sanitizeWalkmanText(pathFallback.album) }
        if !pathFallback.title.isEmpty { item.title = WalkmanEngine.sanitizeWalkmanText(pathFallback.title) }
        if !pathFallback.trackNumber.isEmpty { item.trackNumber = pathFallback.trackNumber }

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

    private func startBatchTransfer() {
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
                    if targetMode != .learning && fetchLyrics {
                        var lyrToWrite = queue[i].lyrics
                        if lyrToWrite == nil || lyrToWrite!.isEmpty {
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
