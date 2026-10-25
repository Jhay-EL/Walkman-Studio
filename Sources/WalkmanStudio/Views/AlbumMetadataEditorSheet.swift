import SwiftUI
import AppKit

public struct AlbumMetadataEditorSheet: View {
    let album: AlbumItem
    let onSaved: () -> Void
    let onDismiss: () -> Void

    public struct EditableTrackRow: Identifiable {
        public var id: String { track.id }
        public let track: Track
        public var trackNum: String
        public var title: String
        public var artist: String
    }

    // Album-wide tags
    @State private var albumName: String = ""
    @State private var albumArtist: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    @State private var applyArtistToAll: Bool = false

    // Artwork state
    @State private var coverImage: NSImage? = nil
    @State private var coverData: Data? = nil
    @State private var originalCoverData: Data? = nil
    @State private var isCoverArtModified: Bool = false
    @State private var validationStatus: (valid: Bool, message: String)? = nil
    @State private var isTargeted: Bool = false
    @State private var isFetchingOnlineArt: Bool = false

    // Tracklist
    @State private var trackRows: [EditableTrackRow] = []

    // Saving state
    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0.0
    @State private var saveStatus: String = ""
    @State private var errorMessage: String? = nil
    @State private var isFetchingOnlineInfo: Bool = false

    // Hover states
    @State private var isCancelHovered: Bool = false
    @State private var isSaveHovered: Bool = false

    public init(album: AlbumItem, onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.album = album
        self.onSaved = onSaved
        self.onDismiss = onDismiss
    }

    private func loadInitialData() {
        self.albumName = album.name
        self.albumArtist = album.artist
        self.year = album.year

        let existingGenre = album.tracks.first(where: { !$0.genre.isEmpty })?.genre ?? ""
        self.genre = existingGenre

        let isVarious = album.artist.lowercased().contains("various") || album.artist.lowercased().contains("soundtrack")
        let uniqueArtists = Set(album.tracks.map { $0.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.applyArtistToAll = (!isVarious && uniqueArtists.count <= 1)

        self.trackRows = album.tracks.map { tr in
            EditableTrackRow(
                track: tr,
                trackNum: tr.trackNum,
                title: tr.title,
                artist: tr.artist
            )
        }

        if let rep = album.representativeTrack {
            let url = URL(fileURLWithPath: rep.fullPath)
            DispatchQueue.global(qos: .userInitiated).async {
                let art = AudioTagger.shared.extractCoverArt(fileURL: url)
                let img = art != nil ? NSImage(data: art!) : nil
                let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil

                DispatchQueue.main.async {
                    self.originalCoverData = art
                    self.coverData = art
                    self.coverImage = img
                    self.validationStatus = val
                }
            }
        }
    }

    private func handleNewImageData(_ data: Data) {
        if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data) {
            self.coverData = baseline
            self.coverImage = NSImage(data: baseline)
            self.validationStatus = WalkmanEngine.shared.isBaselineRGBJPEG(data: baseline)
            self.isCoverArtModified = true
        }
    }

    private func selectArtworkFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.prompt = "Choose Album Artwork"
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            handleNewImageData(data)
        }
    }

    private func removeArtwork() {
        self.coverData = Data()
        self.coverImage = nil
        self.validationStatus = nil
        self.isCoverArtModified = true
    }

    private func revertArtwork() {
        self.coverData = originalCoverData
        self.coverImage = originalCoverData != nil ? NSImage(data: originalCoverData!) : nil
        self.validationStatus = originalCoverData != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: originalCoverData!) : nil
        self.isCoverArtModified = false
    }

    private func exportArtworkToMac() {
        let cleanArtist = albumArtist.isEmpty ? album.artist : albumArtist
        let cleanAlbum = albumName.isEmpty ? album.name : albumName
        let defaultName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        ArtworkExportService.exportCustomArtwork(data: coverData, image: coverImage, suggestedFilename: defaultName)
    }

    private func fetchOnlineArtwork() {
        guard !isFetchingOnlineArt else { return }
        isFetchingOnlineArt = true

        let searchTitle = albumName.isEmpty ? album.name : albumName
        let searchArtist = albumArtist.isEmpty ? album.artist : albumArtist

        Task {
            if let artData = await OnlineMetadataService.shared.fetchArtworkOnly(title: searchTitle, artist: searchArtist, album: searchTitle) {
                await MainActor.run {
                    self.handleNewImageData(artData)
                    self.isFetchingOnlineArt = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineArt = false
                    self.errorMessage = "No online artwork found"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func fetchOnlineAlbumMetadata() {
        guard !isFetchingOnlineInfo else { return }
        isFetchingOnlineInfo = true
        errorMessage = nil

        let searchTitle = albumName.isEmpty ? album.name : albumName
        let searchArtist = albumArtist.isEmpty ? album.artist : albumArtist
        let repFile = album.representativeTrack?.filename ?? "01.flac"

        Task {
            if let meta = await OnlineMetadataService.shared.fetchMetadata(
                filename: repFile,
                currentTitle: searchTitle,
                currentArtist: searchArtist,
                currentAlbum: searchTitle
            ) {
                await MainActor.run {
                    if !meta.album.isEmpty && meta.album.lowercased() != "unknown album" {
                        self.albumName = meta.album
                    }
                    if !meta.artist.isEmpty && meta.artist.lowercased() != "unknown artist" {
                        self.albumArtist = meta.artist
                    }
                    if !meta.year.isEmpty {
                        self.year = meta.year
                    }
                    if !meta.genre.isEmpty {
                        self.genre = meta.genre
                    }
                    if let artData = meta.artworkData, self.coverData == nil || self.coverData?.isEmpty == true {
                        self.handleNewImageData(artData)
                    }
                    self.isFetchingOnlineInfo = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineInfo = false
                    self.errorMessage = "No online album metadata found"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func autoNumberTracks() {
        for i in 0..<trackRows.count {
            trackRows[i].trackNum = "\(i + 1)"
        }
    }

    private func padTrackNumbers() {
        for i in 0..<trackRows.count {
            trackRows[i].trackNum = String(format: "%02d", i + 1)
        }
    }

    private func sortTracksByTrackNum() {
        trackRows.sort { a, b in
            let nA = Int(a.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            let nB = Int(b.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            if nA != nB && nA > 0 && nB > 0 {
                return nA < nB
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func sortTracksByTitle() {
        trackRows.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func moveTrack(from index: Int, up: Bool) {
        let targetIndex = up ? index - 1 : index + 1
        guard targetIndex >= 0 && targetIndex < trackRows.count else { return }
        trackRows.swapAt(index, targetIndex)
    }

    private func saveAlbumChanges() {
        guard !isSaving else { return }
        isSaving = true
        saveProgress = 0.0
        saveStatus = "Preparing album metadata..."
        errorMessage = nil

        let newAlbumName = self.albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAlbumName = newAlbumName.isEmpty ? album.name : newAlbumName
        let finalAlbumArtist = self.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalYear = self.year.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGenre = self.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApplyArtist = self.applyArtistToAll

        let rows = self.trackRows
        let artModified = self.isCoverArtModified
        let artDataToSave = self.coverData

        Task.detached(priority: .userInitiated) {
            let total = rows.count

            var encodedArtwork: Data? = nil
            if artModified {
                if let raw = artDataToSave, !raw.isEmpty {
                    encodedArtwork = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: raw, maxDimension: 800)
                } else if artDataToSave?.isEmpty == true {
                    encodedArtwork = Data()
                }
            }

            for (index, row) in rows.enumerated() {
                await MainActor.run {
                    self.saveProgress = Double(index) / Double(max(1, total))
                    self.saveStatus = "Updating track \(index + 1) of \(total): \(row.title)..."
                }

                let trackURL = URL(fileURLWithPath: row.track.fullPath)
                let trackTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackArtist = shouldApplyArtist ? finalAlbumArtist : row.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackNum = row.trackNum.trimmingCharacters(in: .whitespacesAndNewlines)

                do {
                    try AudioTagger.shared.writeMetadata(
                        fileURL: trackURL,
                        title: trackTitle.isEmpty ? row.track.title : trackTitle,
                        artist: trackArtist.isEmpty ? row.track.artist : trackArtist,
                        album: finalAlbumName,
                        trackNumber: trackNum.isEmpty ? row.track.trackNum : trackNum,
                        year: finalYear,
                        genre: finalGenre,
                        coverArtData: artModified ? encodedArtwork : nil
                    )

                    AudioTagger.shared.invalidateCaches(fileURL: trackURL)
                    CoverArtCache.shared.invalidate(forFullPath: row.track.fullPath, artist: row.track.primaryArtist, album: row.track.album)
                    LibraryScanner.shared.invalidate(fullPath: row.track.fullPath)
                } catch {
                    print("[AlbumMetadataEditor] Error saving track \(row.track.filename): \(error.localizedDescription)")
                }
            }

            if artModified {
                let albumDirs = Set(rows.map { URL(fileURLWithPath: $0.track.fullPath).deletingLastPathComponent() })
                for dir in albumDirs {
                    if let baseline = encodedArtwork, !baseline.isEmpty {
                        try? WalkmanEngine.shared.writeAlbumFolderArtwork(albumDirectoryURL: dir, artworkData: baseline)
                    } else if encodedArtwork?.isEmpty == true {
                        for cand in ["cover.jpg", "folder.jpg", "Cover.jpg", "Folder.jpg"] {
                            let f = dir.appendingPathComponent(cand)
                            try? FileManager.default.removeItem(at: f)
                        }
                    }
                }
            }

            await MainActor.run {
                self.saveProgress = 1.0
                self.saveStatus = "Saved album successfully!"
                self.isSaving = false
                NotificationCenter.default.post(
                    name: .trackMetadataDidUpdate,
                    object: nil,
                    userInfo: [:]
                )
                self.onSaved()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.onDismiss()
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Main Content Area
            ScrollView {
                VStack(spacing: 16) {
                    // Top Section: Album Artwork + Album-Wide Tags
                    HStack(alignment: .top, spacing: 20) {
                        artworkColumn
                            .frame(width: 230)

                        albumTagsColumn
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 14, borderOpacity: 0.28)

                    // Bottom Section: Tracklist & Track Numbers
                    tracklistSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Footer Bar
            footerBar
        }
        .frame(minWidth: 880, idealWidth: 940, maxWidth: 1040, minHeight: 580, idealHeight: 680, maxHeight: 820)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
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
        .onAppear {
            loadInitialData()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WalkmanTheme.silverGradient)
                    .frame(width: 30, height: 30)

                Image(systemName: "square.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Album Metadata Editor")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Text("\(album.name) • \(album.trackCount) tracks • \(album.primaryFormat)")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }

            Spacer()

            SheetCloseButton(action: onDismiss)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Artwork Column
    private var artworkColumn: some View {
        VStack(spacing: 9) {
            ZStack {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.22))
                            .frame(width: 200, height: 200)
                            .background(Color.white.opacity(0.02))

                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Text("Drop Artwork")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(.secondary)
                            Text("Auto Baseline RGB")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectArtworkFile()
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    if let d = data {
                        DispatchQueue.main.async {
                            self.handleNewImageData(d)
                        }
                    }
                }
                return true
            }
            .help("Click or drag-and-drop to update album artwork across all tracks")
            .contextMenu {
                if coverImage != nil || (coverData != nil && coverData?.isEmpty == false) {
                    Button(action: exportArtworkToMac) {
                        Label("Export Album Artwork to Mac...", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                }
                Button(action: selectArtworkFile) {
                    Label("Choose Artwork...", systemImage: "photo")
                }
                Button(action: fetchOnlineArtwork) {
                    Label("Fetch Online Artwork", systemImage: "arrow.down.circle")
                }
                if coverImage != nil {
                    Divider()
                    Button(role: .destructive, action: removeArtwork) {
                        Label("Remove Artwork", systemImage: "trash")
                    }
                }
            }

            // Compliance status pill
            if let st = validationStatus {
                HStack(spacing: 4) {
                    Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(st.valid ? Color.green : Color.orange)
                    Text(st.message)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Artwork Action Buttons
            HStack(spacing: 6) {
                Button(action: selectArtworkFile) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Choose...")
                            .font(WalkmanFont.subheadlineMedium)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                AlbumIconSquareButton(
                    icon: isFetchingOnlineArt ? "arrow.triangle.2.circlepath" : "arrow.down.circle",
                    isDisabled: isFetchingOnlineArt,
                    helpText: "Fetch Online Artwork",
                    action: fetchOnlineArtwork
                )

                if coverImage != nil || (coverData != nil && coverData?.isEmpty == false) {
                    AlbumIconSquareButton(
                        icon: "square.and.arrow.down",
                        helpText: "Export Album Artwork to Mac...",
                        action: exportArtworkToMac
                    )
                }

                if coverImage != nil {
                    AlbumIconSquareButton(
                        icon: "trash",
                        isDestructive: true,
                        helpText: "Remove artwork from all album tracks",
                        action: removeArtwork
                    )
                }

                if isCoverArtModified {
                    AlbumIconSquareButton(
                        icon: "arrow.uturn.backward",
                        helpText: "Revert to original album artwork",
                        action: revertArtwork
                    )
                }
            }

            Text("Updates embedded artwork in all \(album.trackCount) tracks & writes folder.jpg / cover.jpg")
                .font(WalkmanFont.subheadline)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Album Tags Column
    private var albumTagsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ALBUM PROPERTIES (APPLIED TO ALL TRACKS)")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: fetchOnlineAlbumMetadata) {
                    HStack(spacing: 4) {
                        if isFetchingOnlineInfo {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                            Text("Matching...")
                                .font(WalkmanFont.subheadlineMedium)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Auto-Fill Album Info")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFetchingOnlineInfo)
                .help("Query iTunes and Deezer databases to match album title, artist, year, and genre")
            }

            AlbumInputField(label: "Album Title", text: $albumName)

            VStack(alignment: .leading, spacing: 4) {
                AlbumInputField(label: "Album Artist", text: $albumArtist)

                Toggle("Apply this artist to all track tags", isOn: $applyArtistToAll)
                    .font(WalkmanFont.subheadline)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.top, 2)
            }

            HStack(spacing: 12) {
                AlbumInputField(label: "Release Year", text: $year)
                AlbumInputField(label: "Genre", text: $genre)
            }
        }
    }

    // MARK: - Tracklist Section
    private var tracklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tracklist Header & Quick Actions
            HStack {
                HStack(spacing: 6) {
                    Text("TRACKLIST & TRACK NUMBERS")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)

                    Text("(\(trackRows.count))")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Quick Action Buttons
                HStack(spacing: 6) {
                    Button(action: autoNumberTracks) {
                        HStack(spacing: 4) {
                            Image(systemName: "list.number")
                                .font(.system(size: 10))
                            Text("Auto-Number (1..N)")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(Color.white.opacity(0.07))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Automatically renumbers all tracks from 1 to \(trackRows.count)")

                    Button(action: padTrackNumbers) {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 10))
                            Text("Pad (01..N)")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(Color.white.opacity(0.07))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Formats track numbers with leading zero (01, 02...) for optimal Walkman alphabetical folder sorting")

                    Button(action: sortTracksByTrackNum) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.07))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Sort list by track number")

                    Button(action: sortTracksByTitle) {
                        Image(systemName: "textformat.abc")
                            .font(.system(size: 10))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.07))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Sort list by track title")
                }
            }

            // Tracklist Table
            VStack(spacing: 0) {
                // Table Column Header
                HStack(spacing: 12) {
                    Text("#")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .center)

                    Text("Order")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .center)

                    Text("Track Title")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !applyArtistToAll {
                        Text("Track Artist")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .frame(width: 220, alignment: .leading)
                    }

                    Text("Format")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .center)

                    Text("Duration")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.035))

                Divider()
                    .overlay(Color.white.opacity(0.06))

                // Track Rows
                VStack(spacing: 0) {
                    ForEach(Array(trackRows.enumerated()), id: \.element.id) { index, row in
                        TrackRowView(
                            index: index,
                            totalCount: trackRows.count,
                            row: $trackRows[index],
                            applyArtistToAll: applyArtistToAll,
                            onMoveUp: { moveTrack(from: index, up: true) },
                            onMoveDown: { moveTrack(from: index, up: false) },
                            formatDuration: formatDuration
                        )

                        if index < trackRows.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.04))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        VStack(spacing: 8) {
            // Progress Bar (during batch save)
            if isSaving {
                VStack(spacing: 4) {
                    HStack {
                        ProgressView(value: saveProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(WalkmanTheme.silver)
                    }

                    HStack {
                        Text(saveStatus)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverLight)
                        Spacer()
                        Text("\(Int(saveProgress * 100))%")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            HStack(spacing: 12) {
                if let err = errorMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.orange)
                    }
                } else if !isSaving && !saveStatus.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                        Text(saveStatus)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(Color.green)
                    }
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .font(WalkmanFont.subheadlineMedium)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isCancelHovered ? 0.22 : 0.10), lineWidth: 0.8)
                )
                .foregroundStyle(isCancelHovered ? .white : WalkmanTheme.silverLight)
                .buttonStyle(.plain)
                .disabled(isSaving)
                .onHover { h in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                        isCancelHovered = h
                    }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Button(action: saveAlbumChanges) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                            Text("Saving Album...")
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Save Album (\(trackRows.count) Tracks)")
                        }
                    }
                    .font(WalkmanFont.calloutBold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7.5)
                    .background(
                        ZStack {
                            WalkmanTheme.silverGradient
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.40), location: 0.0),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 5)
                                Spacer(minLength: 0)
                            }
                            .clipShape(Capsule())
                        }
                    )
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(isSaveHovered ? 0.35 : 0.20), radius: isSaveHovered ? 4 : 2, y: 1.5)
                    .scaleEffect(isSaveHovered && !isSaving ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                        isSaveHovered = h
                    }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Track Row View
private struct TrackRowView: View {
    let index: Int
    let totalCount: Int
    @Binding var row: AlbumMetadataEditorSheet.EditableTrackRow
    let applyArtistToAll: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let formatDuration: (Double) -> String

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Track Number TextField
            TextField("", text: $row.trackNum)
                .textFieldStyle(.plain)
                .font(WalkmanFont.mono)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
                .frame(width: 44)

            // Reorder Up/Down buttons
            HStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(index == totalCount - 1)
            }
            .frame(width: 42)

            // Title TextField
            TextField("", text: $row.title)
                .textFieldStyle(.plain)
                .font(WalkmanFont.bodyMedium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                )
                .frame(maxWidth: .infinity)

            // Artist TextField (if not applied to all)
            if !applyArtistToAll {
                TextField("", text: $row.artist)
                    .textFieldStyle(.plain)
                    .font(WalkmanFont.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                    )
                    .frame(width: 220)
            }

            // Format
            Text(row.track.format)
                .font(WalkmanFont.badge)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .center)

            // Duration
            Text(formatDuration(row.track.durationSeconds))
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.white.opacity(0.045) : (index % 2 == 1 ? Color.white.opacity(0.015) : Color.clear))
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.75)) {
                isHovered = h
            }
        }
    }
}

// MARK: - Album Input Field
private struct AlbumInputField: View {
    let label: String
    @Binding var text: String
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(label)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(isFocused ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)

            HStack(spacing: 6) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(Color.white)
                    .focused($isFocused)

                if !text.isEmpty && isFocused {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.045))

                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isFocused ? 0.16 : 0.08), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 4)
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.white.opacity(0.35) : (isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.09)),
                        lineWidth: 0.8
                    )
            )
            .onHover { h in
                isHovered = h
            }
        }
    }
}

private struct AlbumIconSquareButton: View {
    let icon: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(
                    isDestructive ?
                        Color(red: 255/255, green: 120/255, blue: 110/255) :
                        (isHovered ? .white : WalkmanTheme.silverLight)
                )
                .frame(width: 26, height: 26)
                .background(
                    isDestructive ?
                        Color.red.opacity(isHovered ? 0.20 : 0.10) :
                        Color.white.opacity(isHovered ? 0.12 : 0.06)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isDestructive ? Color.red.opacity(0.25) : Color.white.opacity(isHovered ? 0.22 : 0.10),
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(isHovered && !isDisabled ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .onHover { h in
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct SheetCloseButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.07))
                    .frame(width: 24, height: 24)

                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.25 : 0.12), lineWidth: 0.8)
                    .frame(width: 24, height: 24)

                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
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
