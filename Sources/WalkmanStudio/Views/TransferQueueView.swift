import SwiftUI
import AppKit

public struct TransferQueueView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let onTransferComplete: () -> Void

    @State private var targetDriveId: String = ""
    @State private var selectedPreset: String = "copy_optimize"
    @State private var queue: [TransferItem] = []
    @State private var isProcessing: Bool = false
    @State private var isTargeted: Bool = false

    // Hardware Optimization & Sync Toggles
    @State private var optimizeArtwork: Bool = true
    @State private var fetchLyrics: Bool = true
    @State private var autoFetchMetadata: Bool = true
    @State private var saveFolderJpg: Bool = true
    @State private var normalizeVolume: Bool = false

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
        _targetDriveId = State(initialValue: activeDrive?.mountPoint ?? drives.first?.mountPoint ?? "")
    }

    private var selectedTarget: WalkmanDrive? {
        drives.first(where: { $0.mountPoint == targetDriveId }) ?? activeDrive
    }

    public var body: some View {
        VStack(spacing: 14) {
            // -------------------------------------------------------------
            // PANEL 1: CONFIGURATION BAR (EQUAL-WIDTH & EQUAL-HEIGHT CARDS)
            // -------------------------------------------------------------
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let cardWidth = max(0, (geo.size.width - spacing * 2) / 3.0)
                let cardHeight: CGFloat = 86

                HStack(spacing: spacing) {
                    // Target Drive
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESTINATION DRIVE")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Picker("", selection: $targetDriveId) {
                            ForEach(drives) { d in
                                Text(d.name).tag(d.mountPoint)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(WalkmanTheme.silver)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 2)

                        if let target = selectedTarget {
                            let freeGB = Double(target.freeBytes) / 1_073_741_824.0
                            let totalGB = Double(target.totalBytes) / 1_073_741_824.0
                            Text(String(format: "%.1f GB free / %.1f GB total", freeGB, totalGB))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("No Walkman drive detected")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                    .liquidGlass(cornerRadius: 11)

                    // Conversion Preset
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONVERSION PRESET")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Picker("", selection: $selectedPreset) {
                            Section("Pass-Through & Optimization") {
                                Text("Optimize Metadata Only (Direct Pass-Through)").tag("copy_optimize")
                                Text("Direct Copy (Raw Passthrough)").tag("copy_raw")
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
                        .pickerStyle(.menu)
                        .tint(WalkmanTheme.silver)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 2)

                        Text(presetDescription(selectedPreset))
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(selectedPreset == "copy_optimize" ? WalkmanTheme.silverLight : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                    .liquidGlass(cornerRadius: 11)

                    // Batch Actions & Transfer Button
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BATCH QUEUE")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Button(action: startBatchTransfer) {
                            HStack(spacing: 6) {
                                if isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                Text(isProcessing ? "Transferring..." : "Start Transfer (\(queue.count))")
                                    .font(WalkmanFont.calloutBold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 21)
                            .padding(.vertical, 1)
                            .background(queue.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(WalkmanTheme.silverGradient))
                            .foregroundStyle(queue.isEmpty ? Color.white.opacity(0.5) : Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(queue.isEmpty || isProcessing || isBatchOptimizing || isBatchFetchingLyrics)

                        Spacer(minLength: 2)

                        let doneCount = queue.filter { $0.status == .success }.count
                        Text("\(doneCount) of \(queue.count) transferred")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                    .liquidGlass(cornerRadius: 11)
                }
            }
            .frame(height: 86)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // -------------------------------------------------------------
            // PANEL 2: HARDWARE OPTIMIZATION OPTIONS & BATCH TOOLBAR
            // -------------------------------------------------------------
            ViewThatFits(in: .horizontal) {
                // Wide layout: single horizontal bar
                HStack(spacing: 12) {
                    HStack(spacing: 14) {
                        toggleArtwork
                        toggleLyrics
                        toggleMetadata
                        toggleFolderJpg
                        toggleLoudnorm
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    if !queue.isEmpty {
                        batchToolbarButtons
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                // Compact layout: responsive list / grid that never cramps labels
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 185, maximum: .infinity), spacing: 12, alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        toggleArtwork
                        toggleLyrics
                        toggleMetadata
                        toggleFolderJpg
                        toggleLoudnorm
                    }

                    if !queue.isEmpty {
                        HStack(spacing: 8) {
                            if let msg = batchStatusText {
                                Text(msg)
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                            Spacer()
                            batchToolbarButtons
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlass(cornerRadius: 8)
            .padding(.horizontal, 16)

            // -------------------------------------------------------------
            // PANEL 3: NATIVE FINDER DRAG & DROP ZONE
            // -------------------------------------------------------------
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isTargeted ? WalkmanTheme.silver : WalkmanTheme.border,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(isTargeted ? Color.white.opacity(0.08) : WalkmanTheme.card.opacity(0.4))

                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(WalkmanTheme.silver)

                    Text("Drag & Drop Audio Files or Folders from Finder")
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.white)

                    Text("Supports FLAC, MP3, WAV, ALAC, M4A, AIFF, DSD • Auto-organized to /MUSIC/Artist/Album/")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)

                    Button(action: openFilePicker) {
                        Text("Browse Files...")
                            .font(WalkmanFont.calloutMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(WalkmanTheme.cardHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WalkmanTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(14)
            }
            .frame(height: queue.isEmpty ? 160 : 105)
            .padding(.horizontal, 16)
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            // -------------------------------------------------------------
            // PANEL 4: QUEUE LIST WITH IN-LINE PREVIEW & METADATA CARDS
            // -------------------------------------------------------------
            if !queue.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Files in Queue (\(queue.count))")
                            .font(WalkmanFont.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        let missingCount = queue.filter { $0.isMissingMetadata }.count
                        if missingCount > 0 {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 11))
                                Text("\(missingCount) missing tags / artwork")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(WalkmanTheme.card.opacity(0.8))
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach($queue) { $item in
                                queueRow(item: $item)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                Divider().foregroundStyle(WalkmanTheme.border.opacity(0.25))
                            }
                        }
                    }
                }
                .liquidGlass(cornerRadius: 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                Spacer()
            }
        }
    }

    // -------------------------------------------------------------------------
    // QUEUE ROW COMPONENT
    // -------------------------------------------------------------------------
    private func queueRow(item: Binding<TransferItem>) -> some View {
        let it = item.wrappedValue
        let isThisPlaying = player.isPlaying && player.currentTrack?.id == it.sourceURL.path

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // In-line Audio Preview Play / Pause Button
                Button(action: {
                    togglePreviewPlayback(for: it)
                }) {
                    ZStack {
                        Circle()
                            .fill(isThisPlaying ? AnyShapeStyle(WalkmanTheme.silverGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(width: 34, height: 34)

                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isThisPlaying ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white)
                            .offset(x: isThisPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(isThisPlaying ? "Pause preview" : "Play audio preview")

                // Artwork Thumbnail with Hardware Compliance Badge
                ZStack(alignment: .bottomTrailing) {
                    if let artData = it.artworkData, let img = NSImage(data: artData) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tertiary)
                            )
                    }

                    // Compliance icon badge
                    if it.artworkData != nil {
                        Image(systemName: it.isArtworkOptimized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(it.isArtworkOptimized ? .green : .orange)
                            .background(Color.black.clipShape(Circle()))
                            .offset(x: 3, y: 3)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isThisPlaying ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: 1)
                )
                .onTapGesture {
                    pickCustomArtwork(for: it.id)
                }
                .help("Click to select custom album art or inspect compliance")

                // Track Information
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(it.title.isEmpty ? it.sourceURL.deletingPathExtension().lastPathComponent : it.title)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if it.bitsPerSample > 16 || it.sampleRate > 48000 {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(WalkmanTheme.hiResGoldGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(spacing: 6) {
                        let artistText = it.artist.isEmpty ? "Unknown Artist" : it.artist
                        let albumText = it.album.isEmpty ? "Unknown Album" : it.album
                        Text("\(artistText) • \(albumText)")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !it.year.isEmpty {
                            Text("(\(it.year))")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Format specs & status pills
                    HStack(spacing: 6) {
                        let quality = it.sampleRate > 0 ? "\(it.bitsPerSample)b/\(it.sampleRate/1000)k" : it.format
                        Text(quality)
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white.opacity(0.85))

                        if it.bitrateKbps > 0 {
                            Text("\(it.bitrateKbps)k")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if it.durationSeconds > 0 {
                            Text(formatDuration(it.durationSeconds))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if let lyr = it.lyrics, !lyr.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 8))
                                Text(it.isLyricsSynced ? "Synced .LRC" : "Plain Lyrics")
                                    .font(WalkmanFont.badge)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Destination Folder Route Preview
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DESTINATION PATH")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.tertiary)

                    let cleanArtist = WalkmanEngine.shared.sanitizeFilename(it.artist.isEmpty ? "Unknown Artist" : it.artist)
                    let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(it.album.isEmpty ? "Unknown Album" : it.album)
                    let cleanTitle = WalkmanEngine.shared.sanitizeFilename(it.title.isEmpty ? it.sourceURL.deletingPathExtension().lastPathComponent : it.title)
                    let tInt = Int(it.trackNumber.components(separatedBy: "/").first ?? "1") ?? 1
                    let trackPrefix = String(format: "%02d", tInt)
                    let targetExt = destinationExtension(for: it.sourceURL)

                    Text("/MUSIC/\(cleanArtist)/\(cleanAlbum)/\(trackPrefix) - \(cleanTitle).\(targetExt)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)
                }
                .frame(maxWidth: 240, alignment: .trailing)

                // Item Status Pill
                switch it.status {
                case .pending:
                    Text("Pending")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(WalkmanTheme.card)
                        .clipShape(Capsule())
                case .optimizing:
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        Text("Optimizing...")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                case .converting:
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6)
                        Text("Converting...")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                case .success:
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Transferred")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(.green)
                    }
                case .failed(let err):
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                // Row Quick Actions
                HStack(spacing: 6) {
                    // Optimize Button
                    Button(action: {
                        optimizeSingleTrack(item.wrappedValue)
                    }) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(it.isMissingMetadata ? Color.orange : WalkmanTheme.silver)
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(it.isOptimizing || isProcessing)
                    .help(it.isMissingMetadata ? "Fetch missing metadata from internet and optimize cover art" : "Re-optimize cover art and metadata")

                    // Lyrics Button
                    Button(action: {
                        fetchLyricsForTrack(item.wrappedValue)
                    }) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(it.lyrics != nil ? Color.green : Color.secondary)
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(it.isFetchingOnline || isProcessing)
                    .help("Fetch synchronized lyrics from internet")

                    // Edit Tags Toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            item.isExpanded.wrappedValue.toggle()
                        }
                    }) {
                        Image(systemName: it.isExpanded ? "chevron.up" : "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(WalkmanTheme.silver)
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit tags and folder designation manually")

                    // Remove Button
                    Button(action: {
                        queue.removeAll(where: { $0.id == it.id })
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }

            // Inline Tag Editor Drawer
            if it.isExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        InlineField(label: "Title", text: item.title)
                        InlineField(label: "Artist", text: item.artist)
                        InlineField(label: "Album", text: item.album)
                    }
                    HStack(spacing: 8) {
                        InlineField(label: "Track #", text: item.trackNumber)
                        InlineField(label: "Year", text: item.year)
                        InlineField(label: "Genre", text: item.genre)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WalkmanTheme.border.opacity(0.5), lineWidth: 1))
                .padding(.top, 4)
            }
        }
    }

    // -------------------------------------------------------------------------
    // PANEL 2 HARDWARE OPTIMIZATION SUBVIEWS
    // -------------------------------------------------------------------------
    private var toggleArtwork: some View {
        Toggle(isOn: $optimizeArtwork) {
            HStack(spacing: 5) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 11))
                Text("Optimize Cover Art")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .toggleStyle(.checkbox)
        .tint(WalkmanTheme.silver)
        .help("Converts cover artwork to strict Baseline RGB JPEG (max 800x800) compliant with Sony Walkman display engine")
    }

    private var toggleLyrics: some View {
        Toggle(isOn: $fetchLyrics) {
            HStack(spacing: 5) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 11))
                Text("Sync .LRC Lyrics")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .toggleStyle(.checkbox)
        .tint(WalkmanTheme.silver)
        .help("Automatically downloads synchronized lyrics from the internet and writes paired .lrc file in the album folder")
    }

    private var toggleMetadata: some View {
        Toggle(isOn: $autoFetchMetadata) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                Text("Auto-Fetch Missing Tags")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .toggleStyle(.checkbox)
        .tint(WalkmanTheme.silver)
        .help("Queries iTunes & Deezer online databases when songs have missing title, artist, album, or cover art")
    }

    private var toggleFolderJpg: some View {
        Toggle(isOn: $saveFolderJpg) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                Text("Save folder.jpg")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .toggleStyle(.checkbox)
        .tint(WalkmanTheme.silver)
        .help("Writes folder.jpg and cover.jpg into the Walkman album folder for native album browsing")
    }

    private var toggleLoudnorm: some View {
        Toggle(isOn: $normalizeVolume) {
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                Text("EBU R128 Leveling")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .toggleStyle(.checkbox)
        .tint(WalkmanTheme.silver)
        .disabled(selectedPreset == "copy_optimize" || selectedPreset == "copy_raw")
        .help("Normalizes track loudness using EBU R128 standard during transcoding to prevent sudden volume jumps")
    }

    private var batchToolbarButtons: some View {
        HStack(spacing: 8) {
            Button(action: batchOptimizeAll) {
                HStack(spacing: 4) {
                    if isBatchOptimizing {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isBatchOptimizing ? "Optimizing..." : "Optimize All")
                        .font(WalkmanFont.subheadlineMedium)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WalkmanTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isBatchOptimizing || isProcessing)
            .help("Fetches missing metadata from internet and optimizes cover artwork to Baseline RGB JPEG for all tracks")

            Button(action: batchFetchAllLyrics) {
                HStack(spacing: 4) {
                    if isBatchFetchingLyrics {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "music.mic")
                    }
                    Text(isBatchFetchingLyrics ? "Fetching..." : "Fetch Lyrics")
                        .font(WalkmanFont.subheadlineMedium)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WalkmanTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isBatchFetchingLyrics || isProcessing)
            .help("Fetches synchronized .LRC lyrics for all tracks in the queue")

            Button(action: { queue.removeAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Clear")
                        .font(WalkmanFont.subheadlineMedium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }

    // -------------------------------------------------------------------------
    // HELPERS & INGESTION
    // -------------------------------------------------------------------------
    private func presetDescription(_ preset: String) -> String {
        switch preset {
        case "copy_optimize":
            return "Bit-perfect copy • Enforces strict ID3v2.3/Vorbis & Baseline JPEG"
        case "copy_raw":
            return "Pass-through copy • Unmodified file copy"
        case "flac_16":
            return "CD Quality lossless FLAC 16-bit / 44.1kHz"
        case "flac_24_48":
            return "Studio lossless FLAC 24-bit / 48kHz"
        case "flac_24_96", "flac_24":
            return "Hi-Res studio master FLAC 24-bit / 96kHz"
        case "flac_24_192":
            return "Ultra Hi-Res FLAC 24-bit / 192kHz"
        case "mp3_320":
            return "Maximum fidelity MP3 320 kbps (Strict ID3v2.3 UTF-16)"
        case "mp3_256":
            return "High quality MP3 256 kbps CBR"
        case "mp3_v0":
            return "Variable bitrate MP3 VBR V0 (~245 kbps)"
        case "aac_320":
            return "High fidelity AAC-LC 320 kbps in M4A container"
        case "aac_256":
            return "iTunes standard AAC 256 kbps in M4A container"
        case "alac_16":
            return "Apple Lossless 16-bit in M4A container"
        case "wav_16":
            return "Uncompressed PCM 16-bit / 44.1kHz"
        default:
            return "Apple Silicon hardware acceleration"
        }
    }

    private func destinationExtension(for sourceURL: URL) -> String {
        switch selectedPreset {
        case "copy_optimize", "copy_raw":
            return sourceURL.pathExtension.lowercased()
        case "flac_16", "flac_24_48", "flac_24_96", "flac_24", "flac_24_192":
            return "flac"
        case "mp3_320", "mp3_256", "mp3_v0":
            return "mp3"
        case "aac_320", "aac_256", "alac_16":
            return "m4a"
        case "wav_16":
            return "wav"
        default:
            return "flac"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    addURLToQueue(url)
                }
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]

        if panel.runModal() == .OK {
            for url in panel.urls {
                addURLToQueue(url)
            }
        }
    }

    private func addURLToQueue(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        let ext = fileURL.pathExtension.lowercased()
                        if ["flac", "mp3", "m4a", "wav", "aac", "alac", "aiff", "dsf", "dff"].contains(ext) {
                            enqueueSingleFile(fileURL)
                        }
                    }
                }
            } else {
                enqueueSingleFile(url)
            }
        }
    }

    private func enqueueSingleFile(_ url: URL) {
        if queue.contains(where: { $0.sourceURL == url }) { return }

        // Create item with basic info
        var item = TransferItem(sourceURL: url)
        item.title = WalkmanEngine.sanitizeWalkmanText(url.deletingPathExtension().lastPathComponent)
        item.format = url.pathExtension.uppercased()

        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) {
            item.sizeBytes = attr[.size] as? Int64 ?? 0
        }

        // Pre-populate with directory/filename heuristics immediately so tags are never empty
        let pathFallback = AudioTagger.extractFromPath(url: url)
        if !pathFallback.artist.isEmpty { item.artist = WalkmanEngine.sanitizeWalkmanText(pathFallback.artist, stripExplicitMarkers: false) }
        if !pathFallback.album.isEmpty { item.album = WalkmanEngine.sanitizeWalkmanText(pathFallback.album) }
        if !pathFallback.title.isEmpty { item.title = WalkmanEngine.sanitizeWalkmanText(pathFallback.title) }

        // Read local tags asynchronously
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

                    // Auto-fetch if missing metadata and enabled
                    if self.autoFetchMetadata && self.queue[idx].isMissingMetadata {
                        self.optimizeSingleTrack(self.queue[idx])
                    } else if self.fetchLyrics && self.queue[idx].lyrics == nil {
                        self.fetchLyricsForTrack(self.queue[idx])
                    }
                }
            }
        }

        queue.append(item)
    }

    // -------------------------------------------------------------------------
    // AUDIO PREVIEW PLAYBACK
    // -------------------------------------------------------------------------
    private func togglePreviewPlayback(for item: TransferItem) {
        let isThisPlaying = player.isPlaying && player.currentTrack?.id == item.sourceURL.path

        if isThisPlaying {
            player.pause()
        } else {
            let previewTrack = item.toPreviewTrack()
            var img: NSImage? = nil
            if let d = item.artworkData {
                img = NSImage(data: d)
            }
            player.play(track: previewTrack, coverArt: img)
        }
    }

    // -------------------------------------------------------------------------
    // OPTIMIZATION & ONLINE METADATA FETCHING
    // -------------------------------------------------------------------------
    private func optimizeSingleTrack(_ item: TransferItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].status = .optimizing
        queue[idx].isOptimizing = true

        Task {
            var currentTitle = WalkmanEngine.sanitizeWalkmanText(queue[idx].title)
            var currentArtist = WalkmanEngine.sanitizeWalkmanText(queue[idx].artist, stripExplicitMarkers: false)
            var currentAlbum = WalkmanEngine.sanitizeWalkmanText(queue[idx].album)
            var currentTrackNum = queue[idx].trackNumber
            var currentYear = queue[idx].year
            var currentGenre = queue[idx].genre
            var currentArt = queue[idx].artworkData

            // First, check if currentTitle is empty or "unknown"; if so, try local tag reader
            let isCurrentTitleUnknown = currentTitle.isEmpty || currentTitle.lowercased() == "unknown" || currentTitle.lowercased() == "unknown track" || currentTitle.lowercased() == "unknown title"
            let isCurrentArtistUnknown = currentArtist.isEmpty || currentArtist.lowercased() == "unknown artist" || currentArtist.lowercased() == "unknown"
            let isCurrentAlbumUnknown = currentAlbum.isEmpty || currentAlbum.lowercased() == "unknown album" || currentAlbum.lowercased() == "unknown"

            if isCurrentTitleUnknown || isCurrentArtistUnknown || isCurrentAlbumUnknown {
                if let local = AudioTagger.shared.readMetadata(fileURL: queue[idx].sourceURL) {
                    if isCurrentTitleUnknown && !local.title.isEmpty && local.title.lowercased() != "unknown" && local.title.lowercased() != "unknown track" {
                        currentTitle = WalkmanEngine.sanitizeWalkmanText(local.title)
                    }
                    if isCurrentArtistUnknown && !local.artist.isEmpty && local.artist.lowercased() != "unknown artist" && local.artist.lowercased() != "unknown" {
                        currentArtist = WalkmanEngine.sanitizeWalkmanText(local.artist, stripExplicitMarkers: false)
                    }
                    if isCurrentAlbumUnknown && !local.album.isEmpty && local.album.lowercased() != "unknown album" && local.album.lowercased() != "unknown" {
                        currentAlbum = WalkmanEngine.sanitizeWalkmanText(local.album)
                    }
                }
            }

            let hasValidTitle = !currentTitle.isEmpty && currentTitle.lowercased() != "unknown" && currentTitle.lowercased() != "unknown track" && currentTitle.lowercased() != "unknown title"
            let hasValidArtist = !currentArtist.isEmpty && currentArtist.lowercased() != "unknown artist" && currentArtist.lowercased() != "unknown"
            let hasValidAlbum = !currentAlbum.isEmpty && currentAlbum.lowercased() != "unknown album" && currentAlbum.lowercased() != "unknown"

            // 1. If metadata or art is missing, query internet
            if !hasValidTitle || !hasValidArtist || !hasValidAlbum || currentArt == nil {
                // If we already have title & artist, but only need cover art:
                if hasValidTitle && hasValidArtist && currentArt == nil {
                    if let art = await OnlineMetadataService.shared.fetchArtworkOnly(
                        title: currentTitle,
                        artist: currentArtist,
                        album: hasValidAlbum ? currentAlbum : ""
                    ) {
                        currentArt = art
                    }
                }

                // If still missing tags or art:
                if (!hasValidTitle || !hasValidArtist || !hasValidAlbum || currentArt == nil) {
                    if let online = await OnlineMetadataService.shared.fetchMetadata(
                        filename: queue[idx].filename,
                        currentTitle: hasValidTitle ? currentTitle : nil,
                        currentArtist: hasValidArtist ? currentArtist : nil,
                        currentAlbum: hasValidAlbum ? currentAlbum : nil
                    ) {
                        // CRITICAL: NEVER overwrite an existing valid title!
                        if !hasValidTitle && !online.title.isEmpty && online.title.lowercased() != "unknown" && online.title.lowercased() != "unknown track" {
                            currentTitle = WalkmanEngine.sanitizeWalkmanText(online.title)
                        }
                        if !hasValidArtist && !online.artist.isEmpty && online.artist.lowercased() != "unknown artist" && online.artist.lowercased() != "unknown" {
                            currentArtist = WalkmanEngine.sanitizeWalkmanText(online.artist, stripExplicitMarkers: false)
                        }
                        if !hasValidAlbum && !online.album.isEmpty && online.album.lowercased() != "unknown album" && online.album.lowercased() != "unknown" {
                            currentAlbum = WalkmanEngine.sanitizeWalkmanText(online.album)
                        }
                        if (currentTrackNum.isEmpty || currentTrackNum == "1") && !online.trackNumber.isEmpty {
                            currentTrackNum = online.trackNumber
                        }
                        if currentYear.isEmpty && !online.year.isEmpty {
                            currentYear = online.year
                        }
                        if currentGenre.isEmpty && !online.genre.isEmpty {
                            currentGenre = online.genre
                        }
                        if currentArt == nil, let d = online.artworkData {
                            currentArt = d
                        }
                    }
                }
            }

            // 2. Optimize artwork to Baseline RGB JPEG
            var isOpt = false
            if let d = currentArt {
                if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: d, maxDimension: 800) {
                    currentArt = baseline
                    isOpt = true
                }
            }

            // 3. Fetch Lyrics if enabled and missing
            var lyricsStr = queue[idx].lyrics
            var lyricsSynced = queue[idx].isLyricsSynced
            if self.fetchLyrics && (lyricsStr == nil || lyricsStr?.isEmpty == true) && !currentTitle.isEmpty && !currentArtist.isEmpty {
                if let res = try? await LyricsService.shared.fetchLyrics(
                    title: currentTitle,
                    artist: currentArtist,
                    album: currentAlbum,
                    durationSeconds: queue[idx].durationSeconds
                ) {
                    lyricsStr = res.lyrics
                    lyricsSynced = res.synced
                }
            }

            await MainActor.run {
                guard let targetIdx = self.queue.firstIndex(where: { $0.id == item.id }) else { return }
                self.queue[targetIdx].title = currentTitle
                self.queue[targetIdx].artist = currentArtist
                self.queue[targetIdx].album = currentAlbum
                self.queue[targetIdx].trackNumber = currentTrackNum
                self.queue[targetIdx].year = currentYear
                self.queue[targetIdx].genre = currentGenre
                self.queue[targetIdx].artworkData = currentArt
                self.queue[targetIdx].isArtworkOptimized = isOpt
                self.queue[targetIdx].lyrics = lyricsStr
                self.queue[targetIdx].isLyricsSynced = lyricsSynced
                self.queue[targetIdx].status = .pending
                self.queue[targetIdx].isOptimizing = false
            }
        }
    }

    private func batchOptimizeAll() {
        guard !isBatchOptimizing else { return }
        isBatchOptimizing = true
        batchStatusText = "Optimizing all tracks..."

        Task {
            for item in queue {
                optimizeSingleTrack(item)
                try? await Task.sleep(nanoseconds: 200_000_000) // gentle 200ms stagger
            }
            await MainActor.run {
                self.isBatchOptimizing = false
                self.batchStatusText = "All tracks optimized!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if self.batchStatusText == "All tracks optimized!" {
                        self.batchStatusText = nil
                    }
                }
            }
        }
    }

    private func fetchLyricsForTrack(_ item: TransferItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].isFetchingOnline = true

        Task {
            let title = queue[idx].title
            let artist = queue[idx].artist
            let album = queue[idx].album
            let duration = queue[idx].durationSeconds

            if let res = try? await LyricsService.shared.fetchLyrics(
                title: title,
                artist: artist,
                album: album,
                durationSeconds: duration
            ) {
                await MainActor.run {
                    guard let targetIdx = self.queue.firstIndex(where: { $0.id == item.id }) else { return }
                    self.queue[targetIdx].lyrics = res.lyrics
                    self.queue[targetIdx].isLyricsSynced = res.synced
                    self.queue[targetIdx].isFetchingOnline = false
                }
            } else {
                await MainActor.run {
                    guard let targetIdx = self.queue.firstIndex(where: { $0.id == item.id }) else { return }
                    self.queue[targetIdx].isFetchingOnline = false
                }
            }
        }
    }

    private func batchFetchAllLyrics() {
        guard !isBatchFetchingLyrics else { return }
        isBatchFetchingLyrics = true
        batchStatusText = "Fetching lyrics..."

        Task {
            for item in queue {
                if item.lyrics == nil {
                    fetchLyricsForTrack(item)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            await MainActor.run {
                self.isBatchFetchingLyrics = false
                self.batchStatusText = "Lyrics sync complete!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if self.batchStatusText == "Lyrics sync complete!" {
                        self.batchStatusText = nil
                    }
                }
            }
        }
    }

    private func pickCustomArtwork(for itemId: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url, let rawData = try? Data(contentsOf: url) {
            let opt = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: rawData, maxDimension: 800) ?? rawData
            let check = WalkmanEngine.shared.isBaselineRGBJPEG(data: opt)
            if let idx = queue.firstIndex(where: { $0.id == itemId }) {
                queue[idx].artworkData = opt
                queue[idx].isArtworkOptimized = check.valid
            }
        }
    }

    // -------------------------------------------------------------------------
    // BATCH TRANSFER PIPELINE
    // -------------------------------------------------------------------------
    private func startBatchTransfer() {
        guard let target = selectedTarget else { return }
        isProcessing = true

        Task {
            let musicDir = URL(fileURLWithPath: target.musicDir)

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

                // If still unknown, fall back to directory and filename heuristics
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

                // If title is STILL unknown, fall back to source filename stem
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
                    musicRoot: musicDir,
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

                    // 2. Hardware Metadata & Baseline JPEG Embedding (unless copy_raw)
                    if selectedPreset != "copy_raw" {
                        var finalArtData = queue[i].artworkData
                        if optimizeArtwork, let art = finalArtData {
                            finalArtData = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: art, maxDimension: 800) ?? art
                        }

                        let destExt = dest.pathExtension.lowercased()
                        if destExt == "flac" || destExt == "mp3" {
                            let rawTitle = WalkmanEngine.sanitizeWalkmanText(queue[i].title).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagTitle = (rawTitle.isEmpty || rawTitle.lowercased() == "unknown" || rawTitle.lowercased() == "unknown track" || rawTitle.lowercased() == "unknown title") ? cleanTitle : rawTitle
                            let rawArtist = WalkmanEngine.sanitizeWalkmanText(queue[i].artist, stripExplicitMarkers: false).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagArtist = (rawArtist.isEmpty || rawArtist.lowercased() == "unknown artist" || rawArtist.lowercased() == "unknown") ? (cleanArtist.lowercased() == "unknown artist" ? nil : cleanArtist) : rawArtist
                            let rawAlbum = WalkmanEngine.sanitizeWalkmanText(queue[i].album).trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagAlbum = (rawAlbum.isEmpty || rawAlbum.lowercased() == "unknown album" || rawAlbum.lowercased() == "unknown") ? (cleanAlbum.lowercased() == "unknown album" ? nil : cleanAlbum) : rawAlbum
                            let tagTrackNum = queue[i].trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagYear = queue[i].year.trimmingCharacters(in: .whitespacesAndNewlines)
                            let tagGenre = queue[i].genre.trimmingCharacters(in: .whitespacesAndNewlines)

                            do {
                                try AudioTagger.shared.writeMetadata(
                                    fileURL: dest,
                                    title: tagTitle.isEmpty ? nil : tagTitle,
                                    artist: tagArtist?.isEmpty == true ? nil : tagArtist,
                                    album: tagAlbum?.isEmpty == true ? nil : tagAlbum,
                                    trackNumber: tagTrackNum.isEmpty ? nil : tagTrackNum,
                                    year: tagYear.isEmpty ? nil : tagYear,
                                    genre: tagGenre.isEmpty ? nil : tagGenre,
                                    coverArtData: finalArtData
                                )
                            } catch {
                                print("[TransferQueue] Error writing metadata to \(dest.lastPathComponent): \(error)")
                            }
                        }
                    }

                    // 3. Companion .LRC Lyrics Writing
                    if fetchLyrics, let lyr = queue[i].lyrics, !lyr.isEmpty {
                        try? WalkmanEngine.shared.writeCompanionLyrics(destinationAudioURL: dest, lyrics: lyr)
                    }

                    // 4. Save folder.jpg and cover.jpg in Album Folder
                    if saveFolderJpg, let art = queue[i].artworkData {
                        try? WalkmanEngine.shared.writeAlbumFolderArtwork(albumDirectoryURL: albumDir, artworkData: art)
                    }

                    // 5. Clean macOS Extended Attributes & AppleDouble Shadows
                    let cPath = (dest.path as NSString).fileSystemRepresentation
                    removexattr(cPath, "com.apple.TextEncoding", 0)
                    let dotfile = albumDir.appendingPathComponent("._" + dest.lastPathComponent)
                    try? FileManager.default.removeItem(at: dotfile)
                    sync()

                    queue[i].status = .success
                } catch {
                    queue[i].status = .failed(error.localizedDescription)
                }
            }

            isProcessing = false
            onTransferComplete()
        }
    }
}

// -----------------------------------------------------------------------------
// COMPACT INLINE FIELD FOR DRAWER EDITOR
// -----------------------------------------------------------------------------
private struct InlineField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(.tertiary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(WalkmanFont.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}
