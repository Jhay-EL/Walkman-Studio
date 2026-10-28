import SwiftUI
import AppKit

// MARK: - Queue Item Editor Tab
public enum QueueEditorTab: String, CaseIterable, Identifiable {
    case tags = "Tags & Metadata"
    case artwork = "Cover Artwork"
    case lyrics = "Lyrics (.LRC)"
    case specs = "Audio Specs & Route"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .tags: return "tag"
        case .artwork: return "photo"
        case .lyrics: return "quote.bubble"
        case .specs: return "waveform"
        }
    }
}

// MARK: - Queue Item Editor Sheet (Apple macOS 27 Liquid Glass)
public struct QueueItemEditorSheet: View {
    let item: TransferItem
    let destinationExtension: String
    let rootFolderName: String
    let onSave: (TransferItem) -> Void
    let onDismiss: () -> Void

    @State private var editableItem: TransferItem
    @State private var selectedTab: QueueEditorTab = .tags
    @State private var isFetchingOnline: Bool = false
    @State private var isFetchingLyrics: Bool = false
    @State private var isHoveringDone: Bool = false
    @State private var isHoveringCancel: Bool = false
    @Namespace private var tabNamespace

    public init(
        item: TransferItem,
        destinationExtension: String,
        rootFolderName: String,
        onSave: @escaping (TransferItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.destinationExtension = destinationExtension
        self.rootFolderName = rootFolderName
        self.onSave = onSave
        self.onDismiss = onDismiss
        self._editableItem = State(initialValue: item)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            if let converted = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data, maxDimension: 800) {
                editableItem.artworkData = converted
                editableItem.isArtworkOptimized = true
            } else {
                editableItem.artworkData = data
                editableItem.isArtworkOptimized = false
            }
        }
    }

    private func optimizeExistingArtwork() {
        if let art = editableItem.artworkData,
           let opt = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: art, maxDimension: 800) {
            editableItem.artworkData = opt
            editableItem.isArtworkOptimized = true
        }
    }

    private func fetchOnlineMetadata() {
        isFetchingOnline = true
        Task {
            let filename = editableItem.sourceURL.lastPathComponent
            let currentTitle = editableItem.title.isEmpty ? nil : editableItem.title
            let currentArtist = editableItem.artist.isEmpty ? nil : editableItem.artist
            let currentAlbum = editableItem.album.isEmpty ? nil : editableItem.album
            if let meta = await OnlineMetadataService.shared.fetchMetadata(
                filename: filename,
                currentTitle: currentTitle,
                currentArtist: currentArtist,
                currentAlbum: currentAlbum
            ) {
                await MainActor.run {
                    if !meta.title.isEmpty { editableItem.title = meta.title }
                    if !meta.artist.isEmpty { editableItem.artist = meta.artist }
                    if !meta.album.isEmpty { editableItem.album = meta.album }
                    if !meta.year.isEmpty { editableItem.year = meta.year }
                    if !meta.genre.isEmpty { editableItem.genre = meta.genre }
                    if let artData = meta.artworkData {
                        if let opt = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: artData, maxDimension: 800) {
                            editableItem.artworkData = opt
                            editableItem.isArtworkOptimized = true
                        } else {
                            editableItem.artworkData = artData
                            editableItem.isArtworkOptimized = false
                        }
                    }
                    isFetchingOnline = false
                }
            } else {
                await MainActor.run { isFetchingOnline = false }
            }
        }
    }

    private func fetchOnlineLyrics() {
        isFetchingLyrics = true
        Task {
            let title = editableItem.title.isEmpty ? editableItem.sourceURL.deletingPathExtension().lastPathComponent : editableItem.title
            let artist = editableItem.artist
            let dur = editableItem.durationSeconds
            if let lyr = try? await LyricsService.shared.fetchLyrics(title: title, artist: artist, album: editableItem.album, durationSeconds: dur) {
                await MainActor.run {
                    editableItem.lyrics = lyr.lyrics
                    editableItem.isLyricsSynced = lyr.synced
                    isFetchingLyrics = false
                }
            } else {
                await MainActor.run { isFetchingLyrics = false }
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onDismiss)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Hero Track Summary
            HStack(spacing: 14) {
                // Cover Thumbnail
                ZStack {
                    if let artData = editableItem.artworkData, let img = NSImage(data: artData) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 24))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(editableItem.title.isEmpty ? editableItem.sourceURL.deletingPathExtension().lastPathComponent : editableItem.title)
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if editableItem.bitsPerSample > 16 || editableItem.sampleRate > 48000 {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(WalkmanTheme.hiResGoldGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text(editableItem.artist.isEmpty ? "Unknown Artist" : editableItem.artist)
                        .font(WalkmanFont.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(editableItem.format)
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        if editableItem.sampleRate > 0 {
                            Text("\(editableItem.bitsPerSample)b/\(Int(editableItem.sampleRate/1000))k")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if editableItem.bitrateKbps > 0 {
                            Text("\(editableItem.bitrateKbps)k")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        if editableItem.durationSeconds > 0 {
                            Text(WalkmanEngine.formatDuration(editableItem.durationSeconds))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                        }

                        Text("•  \(WalkmanEngine.formatBytes(editableItem.sizeBytes))")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // Liquid Glass Segmented Pill Bar
            HStack(spacing: 5) {
                ForEach(QueueEditorTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.68))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 36)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(Color.white.opacity(0.16))
                                        .matchedGeometryEffect(id: "activeQueueTab", in: tabNamespace)

                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            stops: [
                                                .init(color: .white.opacity(0.35), location: 0.0),
                                                .init(color: .clear, location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 6)
                                        Spacer(minLength: 0)
                                    }
                                    .clipShape(Capsule())
                                    .matchedGeometryEffect(id: "activeQueueTabSheen", in: tabNamespace)
                                }
                            }
                        )
                        .overlay(
                            Group {
                                if selectedTab == tab {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.32), lineWidth: 0.85)
                                        .matchedGeometryEffect(id: "activeQueueTabBorder", in: tabNamespace)
                                }
                            }
                        )
                        .shadow(color: selectedTab == tab ? Color.black.opacity(0.25) : Color.clear, radius: 3, y: 1)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
            )
            .padding(.bottom, 16)

            // Tab Content
            Group {
                switch selectedTab {
                case .tags:
                    tagsTabView
                case .artwork:
                    artworkTabView
                case .lyrics:
                    lyricsTabView
                case .specs:
                    specsTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 12)

            // Bottom Action Footer
            HStack(alignment: .center) {
                Text("Staged file: will be written directly to \(rootFolderName) on sync.")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                // Cancel Button
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(isHoveringCancel ? 0.12 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isHoveringCancel ? 0.25 : 0.12), lineWidth: 0.85)
                        )
                        .scaleEffect(isHoveringCancel ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isHoveringCancel = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                // Done Button
                Button(action: {
                    onSave(editableItem)
                }) {
                    Text("Apply & Update Track")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8.5)
                        .background(WalkmanTheme.silverGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                        )
                        .shadow(color: Color.black.opacity(isHoveringDone ? 0.35 : 0.20), radius: isHoveringDone ? 6 : 3, x: 0, y: isHoveringDone ? 2 : 1)
                        .scaleEffect(isHoveringDone ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isHoveringDone = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 780, height: 720)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen (Apple Liquid Glass refraction)
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
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
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

    // MARK: - Tab 1: Tags
    private var tagsTabView: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                // Column 1
                VStack(spacing: 12) {
                    QueueEditorField(label: "Song Title", text: $editableItem.title)
                    QueueEditorField(label: "Artist", text: $editableItem.artist)
                    QueueEditorField(label: "Album", text: $editableItem.album)
                }

                // Column 2
                VStack(spacing: 12) {
                    QueueEditorField(label: "Track Number", text: $editableItem.trackNumber)
                    QueueEditorField(label: "Year / Release Date", text: $editableItem.year)
                    QueueEditorField(label: "Genre", text: $editableItem.genre)
                }
            }

            Spacer(minLength: 12)

            // Auto-fetch online tags action banner
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(WalkmanTheme.hiResGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Automated Hardware Metadata")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.primary)
                    Text("Auto-fetch verified artist, album, release year, and high-res cover art from iTunes & Deezer.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: fetchOnlineMetadata) {
                    HStack(spacing: 6) {
                        if isFetchingOnline {
                            ProgressView().scaleEffect(0.65)
                            Text("Fetching...")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Auto-Fetch Tags")
                        }
                    }
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7.5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFetchingOnline)
            }
            .padding(14)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
            )
        }
    }

    // MARK: - Tab 2: Artwork
    private var artworkTabView: some View {
        HStack(spacing: 24) {
            // Artwork Preview Box
            VStack(spacing: 10) {
                ZStack {
                    if let artData = editableItem.artworkData, let img = NSImage(data: artData) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 190, height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 190, height: 190)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 38))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("No Artwork Embedded")
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(.tertiary)
                                }
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)

                // Hardware Status Pill
                if editableItem.artworkData != nil {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(editableItem.isArtworkOptimized ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(editableItem.isArtworkOptimized ? "Baseline RGB JPEG (800×800)" : "Unverified JPEG/PNG")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(editableItem.isArtworkOptimized ? Color.green : Color.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((editableItem.isArtworkOptimized ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Artwork Action Options
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sony Walkman Artwork Standards")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.primary)
                    Text("The Sony Walkman hardware display engine freezes on progressive JPEGs and CMYK color profiles. Walkman Studio converts all embedded covers to Baseline RGB JPEG at 800×800 resolution.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                HStack(spacing: 10) {
                    Button(action: chooseImage) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose Image from Mac...")
                        }
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.85)
                        )
                    }
                    .buttonStyle(.plain)

                    if editableItem.artworkData != nil && !editableItem.isArtworkOptimized {
                        Button(action: optimizeExistingArtwork) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Optimize to Baseline RGB")
                            }
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(WalkmanTheme.hiResGold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(WalkmanTheme.hiResGold.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(WalkmanTheme.hiResGold.opacity(0.30), lineWidth: 0.85)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if editableItem.artworkData != nil {
                        Button(action: {
                            editableItem.artworkData = nil
                            editableItem.isArtworkOptimized = false
                        }) {
                            Text("Remove")
                                .font(WalkmanFont.calloutBold)
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Tab 3: Lyrics
    private var lyricsTabView: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.green)
                    Text("Synchronized Lyrics (.LRC)")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.primary)

                    if editableItem.isLyricsSynced {
                        Text("Synced")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button(action: fetchOnlineLyrics) {
                    HStack(spacing: 6) {
                        if isFetchingLyrics {
                            ProgressView().scaleEffect(0.6)
                            Text("Fetching...")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Fetch Online Lyrics")
                        }
                    }
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFetchingLyrics)
            }

            TextEditor(text: Binding(
                get: { editableItem.lyrics ?? "" },
                set: {
                    editableItem.lyrics = $0
                    editableItem.isLyricsSynced = $0.contains("[00:") || $0.contains("[01:")
                }
            ))
            .font(WalkmanFont.mono)
            .padding(10)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
            )
        }
    }

    // MARK: - Tab 4: Specs & Route
    private var specsTabView: some View {
        VStack(spacing: 14) {
            // Specifications Grid
            VStack(spacing: 1) {
                SpecRow(label: "Source Audio Format", value: editableItem.format)
                SpecRow(label: "Sample Rate", value: "\(Int(editableItem.sampleRate)) Hz")
                SpecRow(label: "Bit Depth", value: "\(editableItem.bitsPerSample)-bit")
                SpecRow(label: "Audio Bitrate", value: "\(editableItem.bitrateKbps) kbps")
                SpecRow(label: "File Duration", value: WalkmanEngine.formatDuration(editableItem.durationSeconds))
                SpecRow(label: "Payload Size", value: WalkmanEngine.formatBytes(editableItem.sizeBytes))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
            )

            // Route Destination Preview Card
            VStack(alignment: .leading, spacing: 6) {
                Text("DESTINATION PATH ON WALKMAN")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                let cleanArtist = WalkmanEngine.shared.sanitizeFilename(editableItem.artist.isEmpty ? "Unknown Artist" : editableItem.artist)
                let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(editableItem.album.isEmpty ? "Unknown Album" : editableItem.album)
                let cleanTitle = WalkmanEngine.shared.sanitizeFilename(editableItem.title.isEmpty ? editableItem.sourceURL.deletingPathExtension().lastPathComponent : editableItem.title)
                let tInt = Int(editableItem.trackNumber.components(separatedBy: "/").first ?? "1") ?? 1
                let trackPrefix = String(format: "%02d", tInt)
                let pathString = "/\(rootFolderName)/\(cleanArtist)/\(cleanAlbum)/\(trackPrefix) - \(cleanTitle).\(destinationExtension)"

                Text(pathString)
                    .font(WalkmanFont.mono)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
            )

            Spacer()
        }
    }
}

// MARK: - Queue Editor Field
private struct QueueEditorField: View {
    let label: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(isFocused ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(WalkmanFont.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .background(Color.white.opacity(isFocused ? 0.08 : (isHovered ? 0.06 : 0.04)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? WalkmanTheme.silverLight.opacity(0.5)
                                : (isHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.10)),
                            lineWidth: isFocused ? 1.0 : 0.85
                        )
                )
                .focused($isFocused)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Spec Row
private struct SpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(WalkmanFont.calloutMedium)
                .foregroundStyle(WalkmanTheme.silverMuted)
            Spacer()
            Text(value)
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8.5)
        .background(Color.white.opacity(0.035))
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
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
