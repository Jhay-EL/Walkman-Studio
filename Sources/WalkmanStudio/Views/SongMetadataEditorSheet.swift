import SwiftUI
import AppKit

public struct SongMetadataEditorSheet: View {
    let track: Track
    let onSaved: () -> Void
    let onSavedTrack: ((Track) -> Void)?
    let onDismiss: () -> Void

    @ObservedObject private var player = AudioPlayerService.shared

    public enum EditorTab: String, CaseIterable, Identifiable {
        case tags = "Tags & Specs"
        case artwork = "Album Artwork"
        case lyrics = "Lyrics (.LRC)"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .tags: return "tag.fill"
            case .artwork: return "photo.fill"
            case .lyrics: return "quote.bubble.fill"
            }
        }
    }

    @State private var selectedTab: EditorTab = .tags

    // Tag fields
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var trackNumber: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""

    // Artwork state
    @State private var coverImage: NSImage?
    @State private var coverData: Data?
    @State private var originalCoverData: Data?
    @State private var isCoverArtModified: Bool = false
    @State private var validationStatus: (valid: Bool, message: String)?
    @State private var isTargeted: Bool = false
    @State private var isFetchingOnlineArt: Bool = false

    // Lyrics state
    @State private var lyrics: String? = nil
    @State private var originalLyrics: String? = nil
    @State private var lyricsDraft: String = ""
    @State private var isLyricsModified: Bool = false
    @State private var isFetchingLyrics: Bool = false
    @State private var lyricsStatusMessage: String? = nil
    @State private var lyricsErrorMessage: String? = nil

    // SenseMe state
    @State private var isAnalyzingSenseMe: Bool = false
    @State private var senseMeInfo: SenseMeInfo? = nil
    @State private var isSenseMeAnalyzed: Bool = false

    // Save state
    @State private var isSaving: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isError: Bool = false
    @State private var isFetchingOnlineInfo: Bool = false
    @State private var showTrimCutSheet: Bool = false

    // Hover states for footer buttons
    @State private var isCancelHovered: Bool = false
    @State private var isSaveHovered: Bool = false

    public init(
        track: Track,
        onSaved: @escaping () -> Void = {},
        onSavedTrack: ((Track) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.track = track
        self.onSaved = onSaved
        self.onSavedTrack = onSavedTrack
        self.onDismiss = onDismiss
    }

    private func loadInitialData() {
        title = track.title
        artist = track.artist
        album = track.album
        trackNumber = track.trackNum
        year = track.year
        genre = track.genre

        let url = URL(fileURLWithPath: track.fullPath)

        DispatchQueue.global(qos: .userInitiated).async {
            let art = AudioTagger.shared.extractCoverArt(fileURL: url)
            let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
            let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
            let img = art != nil ? NSImage(data: art!) : nil
            let meta = AudioTagger.shared.readMetadata(fileURL: url)
            let sInfo = SenseMeEngine.shared.inspect(fileURL: url)

            DispatchQueue.main.async {
                self.originalCoverData = art
                self.coverData = art
                self.coverImage = img
                self.validationStatus = val
                self.senseMeInfo = sInfo
                self.isSenseMeAnalyzed = sInfo.isAnalyzed || self.track.isSenseMeAnalyzed

                self.originalLyrics = lyr
                self.lyrics = lyr
                self.lyricsDraft = lyr ?? ""

                if let m = meta {
                    if self.year.isEmpty && !m.year.isEmpty {
                        self.year = m.year
                    }
                    if self.genre.isEmpty && !m.genre.isEmpty {
                        self.genre = m.genre
                    }
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
        panel.prompt = "Choose Artwork"
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
        let cleanArtist = artist.isEmpty ? track.artist : artist
        let cleanAlbum = album.isEmpty ? track.album : album
        let defaultName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        ArtworkExportService.exportCustomArtwork(data: coverData, image: coverImage, suggestedFilename: defaultName)
    }

    private func fetchOnlineArtwork() {
        guard !isFetchingOnlineArt else { return }
        isFetchingOnlineArt = true
        let searchTitle = title.isEmpty ? track.title : title
        let searchArtist = artist.isEmpty ? track.artist : artist
        let searchAlbum = album.isEmpty ? track.album : album

        Task {
            if let artData = await OnlineMetadataService.shared.fetchArtworkOnly(title: searchTitle, artist: searchArtist, album: searchAlbum) {
                await MainActor.run {
                    self.handleNewImageData(artData)
                    self.isFetchingOnlineArt = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineArt = false
                    self.statusMessage = "No online artwork found"
                    self.isError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage == "No online artwork found" { self.statusMessage = nil }
                    }
                }
            }
        }
    }

    private func fetchOnlineMetadataInfo() {
        guard !isFetchingOnlineInfo else { return }
        isFetchingOnlineInfo = true

        let searchTitle = title.isEmpty ? track.title : title
        let searchArtist = artist.isEmpty ? track.artist : artist
        let searchAlbum = album.isEmpty ? track.album : album
        let filename = track.filename

        Task {
            if let meta = await OnlineMetadataService.shared.fetchMetadata(
                filename: filename,
                currentTitle: searchTitle,
                currentArtist: searchArtist,
                currentAlbum: searchAlbum
            ) {
                await MainActor.run {
                    if !meta.title.isEmpty { self.title = meta.title }
                    if !meta.artist.isEmpty { self.artist = meta.artist }
                    if !meta.album.isEmpty { self.album = meta.album }
                    if !meta.trackNumber.isEmpty && self.trackNumber.isEmpty { self.trackNumber = meta.trackNumber }
                    if !meta.year.isEmpty { self.year = meta.year }
                    if !meta.genre.isEmpty { self.genre = meta.genre }
                    if let artData = meta.artworkData, self.coverData == nil || self.coverData?.isEmpty == true {
                        self.handleNewImageData(artData)
                    }
                    self.isFetchingOnlineInfo = false
                    self.statusMessage = "Metadata matched from \(meta.source)"
                    self.isError = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if self.statusMessage?.contains("matched from") == true { self.statusMessage = nil }
                    }
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineInfo = false
                    self.statusMessage = "No online metadata found"
                    self.isError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage == "No online metadata found" { self.statusMessage = nil }
                    }
                }
            }
        }
    }

    private func fetchLyricsOnline() {
        guard !isFetchingLyrics else { return }
        isFetchingLyrics = true
        lyricsErrorMessage = nil
        lyricsStatusMessage = nil

        let trackTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.title : self.title
        let trackArtist = self.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.artist : self.artist
        let trackAlbum = self.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.album : self.album
        let duration = track.durationSeconds

        Task {
            do {
                let result = try await LyricsService.shared.fetchLyrics(
                    title: trackTitle,
                    artist: trackArtist,
                    album: trackAlbum,
                    durationSeconds: duration
                )

                await MainActor.run {
                    self.lyricsDraft = result.lyrics
                    self.lyrics = result.lyrics
                    self.isLyricsModified = true
                    self.isFetchingLyrics = false
                    self.lyricsStatusMessage = result.synced ? "Synced .LRC found!" : "Lyrics found!"

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.lyricsStatusMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingLyrics = false
                    self.lyricsErrorMessage = "No lyrics found online"

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        self.lyricsErrorMessage = nil
                    }
                }
            }
        }
    }

    private func analyzeSongSenseMe() {
        guard !isAnalyzingSenseMe else { return }
        isAnalyzingSenseMe = true
        statusMessage = "Analyzing 12 Tone acoustic features..."
        isError = false
        let url = URL(fileURLWithPath: track.fullPath)

        Task {
            do {
                let info = try await SenseMeEngine.shared.analyzeAndInject(fileURL: url)
                LibraryScanner.shared.updateCachedSenseMe(fullPath: track.fullPath, info: info)
                await MainActor.run {
                    self.senseMeInfo = info
                    self.isSenseMeAnalyzed = true
                    self.isAnalyzingSenseMe = false
                    self.statusMessage = "12 Tone metadata injected successfully!"
                    self.isError = false
                    
                    var updatedTrack = self.track
                    updatedTrack.isSenseMeAnalyzed = true
                    updatedTrack.senseMeBpm = info.bpm
                    updatedTrack.senseMeValence = info.valence
                    updatedTrack.senseMeArousal = info.arousal
                    updatedTrack.senseMeChannels = info.channels
                    updatedTrack.senseMeHighlightSec = info.highlightSec
                    self.onSavedTrack?(updatedTrack)

                    NotificationCenter.default.post(
                        name: .trackMetadataDidUpdate,
                        object: nil,
                        userInfo: ["trackId": self.track.id, "track": updatedTrack]
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if self.statusMessage == "12 Tone metadata injected successfully!" {
                            self.statusMessage = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzingSenseMe = false
                    self.statusMessage = "SenseMe analysis failed: \(error.localizedDescription)"
                    self.isError = true
                }
            }
        }
    }

    private func saveAllChanges() {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = "Saving tags & artwork to Walkman..."
        isError = false

        let saveTitle = self.title
        let saveArtist = self.artist
        let saveAlbum = self.album
        let saveTrackNum = self.trackNumber
        let saveYear = self.year
        let saveGenre = self.genre
        let saveCover = self.isCoverArtModified ? self.coverData : nil
        let saveLyricsText = self.lyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let didLyricsChange = (lyricsDraft != (originalLyrics ?? ""))

        Task {
            let url = URL(fileURLWithPath: track.fullPath)
            do {
                // 1. Write tags and embedded artwork
                try AudioTagger.shared.writeMetadata(
                    fileURL: url,
                    title: saveTitle,
                    artist: saveArtist,
                    album: saveAlbum,
                    trackNumber: saveTrackNum,
                    year: saveYear,
                    genre: saveGenre,
                    coverArtData: saveCover
                )

                // 2. Handle lyrics if changed
                if didLyricsChange {
                    if saveLyricsText.isEmpty {
                        try? AudioTagger.shared.deleteLyrics(fileURL: url)
                    } else {
                        try? AudioTagger.shared.saveLyrics(fileURL: url, lyrics: saveLyricsText)
                    }
                }

                // 3. Invalidate caches
                AudioTagger.shared.invalidateCaches(fileURL: url)
                CoverArtCache.shared.invalidate(forFullPath: track.fullPath, artist: track.primaryArtist, album: track.album)
                LibraryScanner.shared.invalidate(fullPath: track.fullPath)

                var updatedTrack = track
                updatedTrack.title = saveTitle
                updatedTrack.artist = saveArtist
                updatedTrack.album = saveAlbum
                updatedTrack.trackNum = saveTrackNum
                updatedTrack.year = saveYear
                updatedTrack.genre = saveGenre
                updatedTrack.isSenseMeAnalyzed = self.isSenseMeAnalyzed
                if let s = self.senseMeInfo, s.isAnalyzed {
                    updatedTrack.senseMeBpm = s.bpm
                    updatedTrack.senseMeValence = s.valence
                    updatedTrack.senseMeArousal = s.arousal
                    updatedTrack.senseMeChannels = s.channels
                    updatedTrack.senseMeHighlightSec = s.highlightSec
                }
                if self.isCoverArtModified {
                    updatedTrack.hasArtwork = (saveCover != nil)
                }

                await MainActor.run {
                    self.isSaving = false
                    self.statusMessage = "Saved successfully!"
                    self.isError = false
                    self.onSavedTrack?(updatedTrack)
                    self.onSaved()

                    NotificationCenter.default.post(
                        name: .trackMetadataDidUpdate,
                        object: nil,
                        userInfo: ["trackId": track.id, "track": updatedTrack]
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.onDismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.statusMessage = "Error saving: \(error.localizedDescription)"
                    self.isError = true
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

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    private var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Hero Summary Card
            heroSummaryCard

            // Liquid Glass Segmented Control
            EditorSegmentedBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .tags:
                        tagsAndSpecsTab
                    case .artwork:
                        artworkTab
                    case .lyrics:
                        lyricsTab
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
            }

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Footer Bar
            footerBar
        }
        .frame(minWidth: 960, idealWidth: 1040, maxWidth: 1160, minHeight: 660, idealHeight: 740, maxHeight: 860)
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
        .sheet(isPresented: $showTrimCutSheet) {
            TrimAndCutSheet(
                track: track,
                onSaved: {
                    onSaved()
                    onDismiss()
                },
                onDismiss: {
                    showTrimCutSheet = false
                }
            )
        }
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

                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Song Metadata Editor")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Text(track.filename)
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

    // MARK: - Hero Summary Card
    private var heroSummaryCard: some View {
        HStack(spacing: 16) {
            // Artwork thumbnail
            ZStack {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    TrackCoverThumbnail(track: track, size: 60)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 7) {
                    Text(title.isEmpty ? track.filename : title)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .fixedSize()
                    }
                }

                let dispArtist = artist.isEmpty ? track.artist : artist
                let dispAlbum = album.isEmpty ? track.album : album
                Text("\(dispArtist) — \(dispAlbum)")
                    .font(WalkmanFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(formatDuration(track.durationSeconds))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.tertiary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps) kbps" : "Lossless")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions: Preview & Trim & Cut
            HStack(spacing: 10) {
                let isThisPlaying = (player.currentTrack?.id == track.id && player.isPlaying)
                LiquidGlassActionButton(
                    icon: isThisPlaying ? "pause.fill" : "play.fill",
                    label: isThisPlaying ? "Playing" : "Preview",
                    isProminent: isThisPlaying,
                    action: {
                        if isThisPlaying {
                            player.pause()
                        } else {
                            player.play(track: track)
                        }
                    }
                )

                LiquidGlassActionButton(
                    icon: "scissors",
                    label: "Trim & Cut...",
                    action: { showTrimCutSheet = true }
                )
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 12, borderOpacity: 0.28)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Tags & Specs Tab
    private var tagsAndSpecsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Action to fetch online info
            HStack {
                Text("SONG TAGS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                Spacer()

                LiquidGlassActionButton(
                    icon: isFetchingOnlineInfo ? "arrow.triangle.2.circlepath" : "sparkles",
                    label: isFetchingOnlineInfo ? "Matching..." : "Auto-Fill Online Info",
                    isDisabled: isFetchingOnlineInfo,
                    action: fetchOnlineMetadataInfo
                )
                .help("Query iTunes and Deezer databases to auto-populate title, artist, album, year, and genre")
            }

            // Input Fields Grid
            VStack(spacing: 10) {
                EditorField(label: "Title", text: $title)

                HStack(spacing: 12) {
                    EditorField(label: "Artist", text: $artist)
                    EditorField(label: "Album", text: $album)
                }

                HStack(spacing: 12) {
                    EditorField(label: "Track #", text: $trackNumber)
                    EditorField(label: "Year", text: $year)
                    EditorField(label: "Genre", text: $genre)
                }
            }

            // SONY 12 TONE / SENSEME
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SONY 12 TONE / SENSEME")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)

                    Spacer()

                    LiquidGlassActionButton(
                        icon: isAnalyzingSenseMe ? "arrow.triangle.2.circlepath" : "waveform.path.ecg",
                        label: isAnalyzingSenseMe ? "Analyzing..." : (isSenseMeAnalyzed ? "Re-Analyze SenseMe" : "Analyze SenseMe (12 Tone)"),
                        isDisabled: isAnalyzingSenseMe,
                        action: analyzeSongSenseMe
                    )
                    .help("Extract 12-Tone chroma, tempo, mood, and channels, then embed hardware-compatible SenseMe metadata")
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSenseMeAnalyzed ? Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18) : Color.white.opacity(0.04))
                            .frame(width: 32, height: 32)
                        Image(systemName: isSenseMeAnalyzed ? "checkmark.circle.fill" : (isAnalyzingSenseMe ? "arrow.triangle.2.circlepath" : "circle.dashed"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSenseMeAnalyzed ? Color(red: 255/255, green: 185/255, blue: 50/255) : Color.white.opacity(0.3))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSenseMeAnalyzed ? "SenseMe Analyzed" : (isAnalyzingSenseMe ? "Analyzing Acoustic Features..." : "Not Analyzed"))
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(isSenseMeAnalyzed ? Color.white : Color.secondary)
                        Text(isSenseMeAnalyzed ? "12 Tone acoustic metadata is embedded in audio file" : "No 12 Tone metadata embedded in file")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(isSenseMeAnalyzed ? WalkmanTheme.silverMuted : Color.white.opacity(0.35))
                    }

                    Spacer()

                    if isSenseMeAnalyzed {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("12 TONE")
                                .font(WalkmanFont.badge)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18)))
                        .overlay(Capsule().stroke(Color(red: 255/255, green: 165/255, blue: 30/255).opacity(0.55), lineWidth: 0.8))
                        .foregroundStyle(Color(red: 255/255, green: 195/255, blue: 80/255))
                    } else if !isAnalyzingSenseMe {
                        Text("NOT ANALYZED")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(12)
                .liquidGlass(cornerRadius: 10, borderOpacity: 0.22)
            }

            // Audio Specs Card
            VStack(alignment: .leading, spacing: 8) {
                Text("AUDIO PROPERTIES & HARDWARE TAGS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 6) {
                            specLine(label: "Audio Format", value: "\(track.format) (\(track.bitsPerSample)-bit / \(track.sampleRate) Hz)")
                            specLine(label: "Bitrate", value: track.bitrateKbps > 0 ? "\(track.bitrateKbps) kbps" : "Lossless")
                            specLine(label: "Duration", value: formatDuration(track.durationSeconds))
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 6) {
                            specLine(label: "File Size", value: formatSize(track.sizeBytes))
                            specLine(label: "Hardware Tags", value: track.format == "MP3" ? "Strict ID3v2.3 (UTF-16)" : "Vorbis Comments")
                            specLine(label: "File Path", value: track.fullPath, canCopy: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .liquidGlass(cornerRadius: 10, borderOpacity: 0.22)
            }
        }
    }

    // MARK: - Artwork Tab
    private var artworkTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ALBUM ARTWORK")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(.tertiary)

            HStack(alignment: .top, spacing: 24) {
                // Artwork display with drag & drop
                VStack(spacing: 12) {
                    ZStack {
                        if let img = coverImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 270, height: 270)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                                )
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.25))
                                    .frame(width: 270, height: 270)
                                    .background(Color.white.opacity(0.02))

                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 38))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("Drop Artwork Here")
                                        .font(WalkmanFont.calloutMedium)
                                        .foregroundStyle(.secondary)
                                    Text("Or click to select image")
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
                    .help("Click or drag-and-drop to choose album cover art")
                    .contextMenu {
                        if coverImage != nil || coverData != nil {
                            Button(action: exportArtworkToMac) {
                                Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                            }
                            Divider()
                        }
                        Button(action: selectArtworkFile) {
                            Label("Choose Image File...", systemImage: "folder")
                        }
                        Button(action: fetchOnlineArtwork) {
                            Label("Fetch Online Cover Art", systemImage: "arrow.down.circle")
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
                        HStack(spacing: 5) {
                            Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(st.valid ? Color.green : Color.orange)
                            Text(st.message)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                // Artwork Actions & Information
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Walkman Hardware Artwork Engine")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("Sony Walkman display chips require Baseline RGB JPEG format with a maximum resolution of 800×800. Progressive JPEGs and CMYK color profiles freeze the Walkman screen. Walkman Studio automatically converts imported artwork into strict Baseline RGB JPEG.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 10, borderOpacity: 0.22)

                    // Action buttons
                    VStack(alignment: .leading, spacing: 8) {
                        LiquidGlassActionButton(
                            icon: "folder",
                            label: "Choose Image File...",
                            action: selectArtworkFile
                        )

                        LiquidGlassActionButton(
                            icon: isFetchingOnlineArt ? "arrow.triangle.2.circlepath" : "arrow.down.circle",
                            label: isFetchingOnlineArt ? "Searching Online..." : "Fetch Online Cover Art",
                            isDisabled: isFetchingOnlineArt,
                            action: fetchOnlineArtwork
                        )

                        if coverImage != nil || coverData != nil {
                            LiquidGlassActionButton(
                                icon: "square.and.arrow.down",
                                label: "Export Cover Art to Mac...",
                                action: exportArtworkToMac
                            )
                        }

                        if coverImage != nil {
                            LiquidGlassActionButton(
                                icon: "trash",
                                label: "Remove Artwork",
                                isDestructive: true,
                                action: removeArtwork
                            )
                        }

                        if isCoverArtModified {
                            LiquidGlassActionButton(
                                icon: "arrow.uturn.backward",
                                label: "Revert to Original",
                                action: revertArtwork
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Lyrics Tab
    private var lyricsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SONY WALKMAN .LRC LYRICS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let msg = lyricsStatusMessage {
                    Text(msg)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.green)
                } else if let err = lyricsErrorMessage {
                    Text(err)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.orange)
                } else if !lyricsDraft.isEmpty {
                    Text(lyricsDraft.contains("[") ? "Synced .LRC" : "Plain Lyrics")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(Capsule())
                }

                LiquidGlassActionButton(
                    icon: isFetchingLyrics ? "arrow.triangle.2.circlepath" : "arrow.down.circle",
                    label: isFetchingLyrics ? "Fetching..." : "Fetch Online Lyrics",
                    isDisabled: isFetchingLyrics,
                    action: fetchLyricsOnline
                )

                if !lyricsDraft.isEmpty {
                    LiquidGlassActionButton(
                        icon: "trash",
                        label: "Clear",
                        isDestructive: true,
                        action: {
                            lyricsDraft = ""
                            isLyricsModified = true
                        }
                    )
                }
            }

            TextEditor(text: $lyricsDraft)
                .font(WalkmanFont.mono)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 280, maxHeight: 440)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .onChange(of: lyricsDraft) { _, _ in
                    isLyricsModified = true
                }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Walkman non-Android OS reads synchronized [mm:ss.xx] lines from .LRC files next to the music file.")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func specLine(label: String, value: String, canCopy: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if canCopy {
                CopySpecButton(value: value)
            }
        }
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 12) {
            // Status message
            if let msg = statusMessage {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isError ? Color.orange : Color.green)
                    }
                    Text(msg)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(isError ? Color.orange : (isSaving ? WalkmanTheme.silverLight : Color.green))
                }
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .font(WalkmanFont.calloutMedium)
            .padding(.horizontal, 20)
            .padding(.vertical, 8.5)
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

            Button(action: saveAllChanges) {
                HStack(spacing: 7) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 14, height: 14)
                        Text("Saving...")
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Save Metadata")
                    }
                }
                .font(WalkmanFont.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 9.5)
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
                            .frame(height: 5.5)
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
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

// MARK: - Subviews & Controls

private struct EditorSegmentedBar: View {
    @Binding var selectedTab: SongMetadataEditorSheet.EditorTab
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 5) {
            ForEach(SongMetadataEditorSheet.EditorTab.allCases) { tab in
                EditorTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabNamespace,
                    action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }
}

private struct EditorTabButton: View {
    let tab: SongMetadataEditorSheet.EditorTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.65)))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "activeEditorTab", in: namespace)

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
                        .matchedGeometryEffect(id: "activeEditorTabSheen", in: namespace)
                    } else if isHovered {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    }
                }
            )
            .overlay(
                Group {
                    if isSelected {
                        Capsule()
                            .stroke(Color.white.opacity(0.32), lineWidth: 0.85)
                            .matchedGeometryEffect(id: "activeEditorTabBorder", in: namespace)
                    }
                }
            )
            .shadow(color: isSelected ? Color.black.opacity(0.25) : Color.clear, radius: 3, y: 1)
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct EditorField: View {
    let label: String
    @Binding var text: String
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            Text(label)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(isFocused ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)

            HStack(spacing: 8) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .focused($isFocused)

                if !text.isEmpty && isFocused {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                        .frame(height: 5)
                        Spacer(minLength: 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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

private struct LiquidGlassActionButton: View {
    let icon: String
    let label: String
    var isProminent: Bool = false
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .bold))
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                ZStack {
                    if isProminent {
                        WalkmanTheme.silverGradient
                    } else if isDestructive {
                        Color.red.opacity(isHovered ? 0.22 : 0.12)
                    } else {
                        Color.white.opacity(isHovered ? 0.14 : 0.07)
                    }

                    if !isProminent {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(isHovered ? 0.25 : 0.12), location: 0.0),
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
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isProminent ? Color.white.opacity(0.4) :
                        (isDestructive ? Color.red.opacity(isHovered ? 0.4 : 0.2) :
                        Color.white.opacity(isHovered ? 0.28 : 0.12)),
                        lineWidth: 0.8
                    )
            )
            .foregroundStyle(
                isProminent ? Color(red: 20/255, green: 20/255, blue: 24/255) :
                (isDestructive ? Color(red: 255/255, green: 120/255, blue: 110/255) :
                (isHovered ? Color.white : WalkmanTheme.silverLight))
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.12), radius: isHovered ? 4 : 2, y: 1)
            .scaleEffect(isHovered && !isDisabled ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { h in
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
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

private struct CopySpecButton: View {
    let value: String
    @State private var copied: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copied = false
                }
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5))
                if copied {
                    Text("Copied")
                        .font(.system(size: 9.5, weight: .medium))
                }
            }
            .foregroundStyle(copied ? Color.green : (isHovered ? .white : WalkmanTheme.silverMuted))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(isHovered ? 0.08 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
        .onHover { h in
            isHovered = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
