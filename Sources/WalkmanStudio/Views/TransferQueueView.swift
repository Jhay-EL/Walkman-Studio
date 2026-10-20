import SwiftUI

public struct TransferQueueView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let onTransferComplete: () -> Void

    @State private var targetDriveId: String = ""
    @State private var selectedPreset: String = "copy"
    @State private var queue: [TransferItem] = []
    @State private var isProcessing: Bool = false
    @State private var isTargeted: Bool = false

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
        VStack(spacing: 16) {
            // Configuration Row
            HStack(spacing: 14) {
                // Target Drive
                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION DRIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $targetDriveId) {
                        ForEach(drives) { d in
                            Text(d.name).tag(d.mountPoint)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WalkmanTheme.gold)

                    Text("Organized to /MUSIC/Artist/Album/")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 11)

                // Transcode Preset
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONVERSION PRESET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $selectedPreset) {
                        Text("Direct Copy (Pass-through)").tag("copy")
                        Text("Transcode to FLAC 16-bit (Lossless)").tag("flac_16")
                        Text("Transcode to FLAC 24-bit (Hi-Res)").tag("flac_24")
                        Text("Transcode to MP3 320 kbps (ID3v2.3)").tag("mp3_320")
                    }
                    .pickerStyle(.menu)
                    .tint(WalkmanTheme.gold)

                    Text("Apple Silicon hardware acceleration")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 11)

                // Start Action Button
                VStack(alignment: .leading, spacing: 6) {
                    Text("BATCH QUEUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Button(action: startBatchTransfer) {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11))
                            }
                            Text(isProcessing ? "Processing..." : "Start Transfer (\(queue.count))")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(queue.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(WalkmanTheme.goldGradient))
                        .foregroundStyle(queue.isEmpty ? Color.white.opacity(0.5) : Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(queue.isEmpty || isProcessing)

                    Text("\(queue.filter { $0.status == .success }.count) of \(queue.count) completed")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 11)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Native Finder Drag & Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isTargeted ? WalkmanTheme.gold : WalkmanTheme.border,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(isTargeted ? WalkmanTheme.gold.opacity(0.05) : WalkmanTheme.card.opacity(0.4))

                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(WalkmanTheme.gold)

                    Text("Drag & Drop Audio Files or Folders from Finder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Supports FLAC, MP3, WAV, ALAC, M4A, AIFF, DSD")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Button(action: openFilePicker) {
                        Text("Browse Files...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(WalkmanTheme.cardHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WalkmanTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(height: 140)
            .padding(.horizontal, 20)
            .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            // Queue List
            if !queue.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Files in Queue (\(queue.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button(action: { queue.removeAll() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear")
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessing)
                    }
                    .padding(12)
                    .background(WalkmanTheme.card.opacity(0.8))
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(queue) { item in
                                queueRow(item: item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                Divider().foregroundStyle(WalkmanTheme.border.opacity(0.3))
                            }
                        }
                    }
                }
                .liquidGlass(cornerRadius: 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            } else {
                Spacer()
            }
        }
    }

    private func queueRow(item: TransferItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Text(item.sourceURL.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            switch item.status {
            case .pending:
                Text("Pending")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WalkmanTheme.card)
                    .clipShape(Capsule())
            case .converting:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Converting...")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.gold)
                }
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Transferred")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
            case .failed(let err):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }

            Button(action: {
                queue.removeAll(where: { $0.id == item.id })
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
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
                        if !queue.contains(where: { $0.sourceURL == fileURL }) {
                            queue.append(TransferItem(sourceURL: fileURL))
                        }
                    }
                }
            } else {
                if !queue.contains(where: { $0.sourceURL == url }) {
                    queue.append(TransferItem(sourceURL: url))
                }
            }
        }
    }

    private func startBatchTransfer() {
        guard let target = selectedTarget else { return }
        isProcessing = true

        Task {
            let musicDir = URL(fileURLWithPath: target.musicDir)

            for i in 0..<queue.count {
                guard queue[i].status == .pending else { continue }
                queue[i].status = .converting

                let src = queue[i].sourceURL
                let stem = src.deletingPathExtension().lastPathComponent
                let ext = selectedPreset == "mp3_320" ? "mp3" : (selectedPreset == "copy" ? src.pathExtension : "flac")

                let dest = WalkmanEngine.shared.targetTrackURL(
                    musicRoot: musicDir,
                    artist: "Unknown Artist",
                    album: "Unknown Album",
                    trackNum: "1",
                    title: stem,
                    ext: ext
                )

                do {
                    if selectedPreset == "copy" && src.pathExtension.lowercased() == ext.lowercased() {
                        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: src, to: dest)
                    } else {
                        try await WalkmanEngine.shared.transcodeAudio(sourceURL: src, destinationURL: dest, preset: selectedPreset)
                    }
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
