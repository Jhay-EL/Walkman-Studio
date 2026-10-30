import SwiftUI
import AppKit

public struct SongMetadataEditorSheet: View {
    @State private var track: Track
    @State private var trackList: [Track]
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
    @State private var showPermissionSheet: Bool = false
    @State private var isPermissionError: Bool = false

    private let initialTrackList: [Track]

    public init(
        track: Track,
        trackList: [Track] = [],
        onSaved: @escaping () -> Void = {},
        onSavedTrack: ((Track) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self._track = State(initialValue: track)
        self.initialTrackList = trackList
        let list = trackList.isEmpty ? [track] : trackList
        self._trackList = State(initialValue: list)
        self.onSaved = onSaved
        self.onSavedTrack = onSavedTrack
        self.onDismiss = onDismiss
    }

    private var currentIndex: Int {
        trackList.firstIndex(where: { $0.id == track.id }) ?? 0
    }

    private var canGoPrevious: Bool {
        currentIndex > 0
    }

    private var canGoNext: Bool {
        currentIndex < trackList.count - 1
    }

    private var isModified: Bool {
        title != track.title ||
        artist != track.artist ||
        album != track.album ||
        trackNumber != track.trackNum ||
        year != track.year ||
        genre != track.genre ||
        isCoverArtModified ||
        isLyricsModified
    }

    private func goToPreviousTrack() {
        guard canGoPrevious && !isSaving else { return }
        let prevIndex = currentIndex - 1
        let prevTrack = trackList[prevIndex]
        navigateToTrack(prevTrack)
    }

    private func goToNextTrack() {
        guard canGoNext && !isSaving else { return }
        let nextIndex = currentIndex + 1
        let nextTrack = trackList[nextIndex]
        navigateToTrack(nextTrack)
    }

    private func navigateToTrack(_ targetTrack: Track) {
        if isModified {
            saveAllChanges(dismissOnSuccess: false) {
                switchTrack(to: targetTrack)
            }
        } else {
            switchTrack(to: targetTrack)
        }
    }

    private func switchTrack(to newTrack: Track) {
        if player.isPlaying {
            player.pause()
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            self.track = newTrack
            self.loadInitialData()
        }
    }

    private func loadInitialData() {
        title = track.title
        artist = track.artist
        album = track.album
        trackNumber = track.trackNum
        year = track.year
        genre = track.genre

        isCoverArtModified = false
        isLyricsModified = false
        statusMessage = nil
        isError = false
        lyricsStatusMessage = nil
        lyricsErrorMessage = nil

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

    private func saveAllChanges(dismissOnSuccess: Bool = true, onCompletion: (() -> Void)? = nil) {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = "Saving tags & artwork to Walkman..."
        isError = false

        let currentTrack = self.track
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
            let url = URL(fileURLWithPath: currentTrack.fullPath)
            do {
                // 1. Write tags, embedded lyrics, and embedded artwork
                try AudioTagger.shared.writeMetadata(
                    fileURL: url,
                    title: saveTitle,
                    artist: saveArtist,
                    album: saveAlbum,
                    trackNumber: saveTrackNum,
                    year: saveYear,
                    genre: saveGenre,
                    coverArtData: saveCover,
                    lyrics: saveLyricsText.isEmpty ? nil : saveLyricsText
                )

                // 2. Hardware Compliance: Synchronized Companion .LRC Lyrics for Sony Walkman
                let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
                let lrcExists = FileManager.default.fileExists(atPath: lrcURL.path)

                if saveLyricsText.isEmpty {
                    try? AudioTagger.shared.deleteLyrics(fileURL: url)
                } else if didLyricsChange || !lrcExists {
                    try? WalkmanEngine.shared.writeCompanionLyrics(
                        destinationAudioURL: url,
                        lyrics: saveLyricsText,
                        durationSeconds: currentTrack.durationSeconds
                    )
                }

                // 3. Invalidate & update caches
                AudioTagger.shared.invalidateCaches(fileURL: url)
                CoverArtCache.shared.invalidate(forFullPath: currentTrack.fullPath, artist: currentTrack.primaryArtist, album: currentTrack.album)
                CoverArtCache.shared.invalidate(forFullPath: currentTrack.fullPath, artist: saveArtist, album: saveAlbum)
                if self.isCoverArtModified, let sc = saveCover, !sc.isEmpty, let newImg = NSImage(data: sc) {
                    CoverArtCache.shared.storeThumbnail(newImg, forFullPath: currentTrack.fullPath, artist: saveArtist, album: saveAlbum)
                }
                
                let hasArt = self.isCoverArtModified ? (saveCover != nil && !saveCover!.isEmpty) : currentTrack.hasArtwork
                LibraryScanner.shared.updateTrackInCache(
                    fullPath: currentTrack.fullPath,
                    title: saveTitle,
                    artist: saveArtist,
                    album: saveAlbum,
                    trackNum: saveTrackNum,
                    year: saveYear,
                    genre: saveGenre,
                    hasArtwork: hasArt
                )

                var updatedTrack = currentTrack
                updatedTrack.title = saveTitle
                updatedTrack.artist = saveArtist
                updatedTrack.album = saveAlbum
                updatedTrack.trackNum = saveTrackNum
                updatedTrack.year = saveYear
                updatedTrack.genre = saveGenre
                updatedTrack.hasArtwork = hasArt
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
                    self.track = updatedTrack
                    if let idx = self.trackList.firstIndex(where: { $0.id == updatedTrack.id }) {
                        self.trackList[idx] = updatedTrack
                    }
                    self.onSavedTrack?(updatedTrack)
                    self.onSaved()

                    NotificationCenter.default.post(
                        name: .trackMetadataDidUpdate,
                        object: nil,
                        userInfo: ["trackId": currentTrack.id, "track": updatedTrack]
                    )

                    if dismissOnSuccess {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.onDismiss()
                        }
                    } else {
                        onCompletion?()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    let isPerm = WalkmanStoragePermissionHelper.isPermissionError(error)
                    self.isPermissionError = isPerm
                    if isPerm {
                        self.statusMessage = "Storage permission required to edit file."
                        self.showPermissionSheet = true
                    } else {
                        self.statusMessage = "Error saving: \(error.localizedDescription)"
                    }
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
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Footer Bar
            footerBar
        }
        .frame(minWidth: 960, idealWidth: 1040, maxWidth: 1160, minHeight: 660, idealHeight: 740, maxHeight: 860)
        .modalGlassChassis(cornerRadius: 16)
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
        .sheet(isPresented: $showPermissionSheet) {
            StoragePermissionRequestSheet(
                fileURL: URL(fileURLWithPath: track.fullPath),
                onGranted: {
                    showPermissionSheet = false
                    isPermissionError = false
                    saveAllChanges(dismissOnSuccess: true)
                },
                onDismiss: {
                    showPermissionSheet = false
                }
            )
        }
        .onAppear {
            if self.trackList.count <= 1 && self.initialTrackList.count > 1 {
                self.trackList = self.initialTrackList
            }
            loadInitialData()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            LiquidGlassIconBadge(icon: "music.note", size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Song Metadata Editor")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)

                    if trackList.count > 1 {
                        Text("\(currentIndex + 1) of \(trackList.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    }
                }

                Text(track.filename)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }

            Spacer()

            SheetCloseButton(action: onDismiss)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
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
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)

                    if isHiRes {
                        HiResBadge()
                            .fixedSize()
                    }
                }

                let dispArtist = artist.isEmpty ? track.artist : artist
                let dispAlbum = album.isEmpty ? track.album : album
                Text("\(dispArtist) — \(dispAlbum)")
                    .font(WalkmanFont.body)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(formatDuration(track.durationSeconds))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    Text("•")
                        .foregroundStyle(Color.white.opacity(0.20))

                    Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps) kbps" : "Lossless")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }

            Spacer()

            // Actions: Preview & Trim & Cut
            HStack(spacing: 10) {
                let isThisPlaying = (player.currentTrack?.id == track.id && player.isPlaying)
                Button(action: {
                    if isThisPlaying {
                        player.pause()
                    } else {
                        player.play(track: track)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11.5, weight: .bold))
                        Text(isThisPlaying ? "Playing" : "Preview")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(isThisPlaying ? Color(red: 20/255, green: 20/255, blue: 24/255) : WalkmanTheme.silverLight)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: isThisPlaying ? .prominent : .glass, cornerRadius: 16))

                Button(action: { showTrimCutSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .font(.system(size: 11.5, weight: .bold))
                        Text("Trim & Cut...")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 16))
            }
        }
        .padding(14)
        .studioGlassCard(cornerRadius: 14)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Tags & Specs Tab
    private var tagsAndSpecsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Song Tags & Metadata Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SONG TAGS & METADATA")
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
            }
            .padding(16)
            .studioGlassCard(cornerRadius: 14)

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
                            .fill(Color.white.opacity(isSenseMeAnalyzed ? 0.12 : 0.05))
                            .frame(width: 32, height: 32)
                        Image(systemName: isSenseMeAnalyzed ? "checkmark.circle.fill" : (isAnalyzingSenseMe ? "arrow.triangle.2.circlepath" : "circle.dashed"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSenseMeAnalyzed ? WalkmanTheme.silverLight : Color.white.opacity(0.3))
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
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                        .foregroundStyle(WalkmanTheme.silverLight)
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
                .studioGlassCard(cornerRadius: 12)
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
                .studioGlassCard(cornerRadius: 12)
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
                    .studioGlassCard(cornerRadius: 12)

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
            // Previous & Next Navigation Buttons on the bottom left
            if trackList.count > 1 {
                HStack(spacing: 6) {
                    Button(action: goToPreviousTrack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Previous")
                                .font(WalkmanFont.calloutMedium)
                        }
                        .foregroundStyle(canGoPrevious ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted.opacity(0.35))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                    .disabled(!canGoPrevious || isSaving)
                    .opacity(canGoPrevious ? 1.0 : 0.45)
                    .help(canGoPrevious ? "Previous Track (⌘[)" : "First Track in Album")
                    .keyboardShortcut("[", modifiers: [.command])

                    Button(action: goToNextTrack) {
                        HStack(spacing: 5) {
                            Text("Next")
                                .font(WalkmanFont.calloutMedium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(canGoNext ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted.opacity(0.35))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                    .disabled(!canGoNext || isSaving)
                    .opacity(canGoNext ? 1.0 : 0.45)
                    .help(canGoNext ? "Next Track (⌘])" : "Last Track in Album")
                    .keyboardShortcut("]", modifiers: [.command])

                    Text("\(currentIndex + 1) of \(trackList.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                }
            }

            // Status message
            if let msg = statusMessage {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isPermissionError ? "lock.shield.fill" : (isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                            .font(.system(size: 12))
                            .foregroundStyle(isError ? Color.orange : Color.green)
                    }
                    Text(msg)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(isError ? Color.orange : (isSaving ? WalkmanTheme.silverLight : Color.green))

                    if isPermissionError {
                        Button(action: { showPermissionSheet = true }) {
                            Text("Grant Permission...")
                                .font(WalkmanFont.captionBold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(Color.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Cancel")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 22)
                    .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .disabled(isSaving)
            .keyboardShortcut(.cancelAction)

            Button(action: { saveAllChanges(dismissOnSuccess: true) }) {
                HStack(spacing: 7) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
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
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .padding(.horizontal, 24)
                .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
            .disabled(isSaving)
            .keyboardShortcut(.defaultAction)
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
        HStack(spacing: 4) {
            ForEach(SongMetadataEditorSheet.EditorTab.allCases) { tab in
                EditorTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabNamespace,
                    action: {
                        selectedTab = tab
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
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                Text(tab.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.70)))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "activeEditorTabLens", in: namespace)

                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
                                    .init(color: Color.clear, location: 1.0)
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
                            .fill(Color.white.opacity(0.09))

                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.20), location: 0.0),
                                    .init(color: Color.clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5.5)
                            Spacer(minLength: 0)
                        }
                        .clipShape(Capsule())
                    }
                }
            )
            .overlay(
                Group {
                    if isSelected {
                        Capsule()
                            .stroke(Color.white.opacity(isHovered ? 0.45 : 0.34), lineWidth: 0.85)
                            .matchedGeometryEffect(id: "activeEditorTabBorder", in: namespace)
                    } else if isHovered {
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.85)
                    }
                }
            )
            .shadow(color: isSelected ? Color.black.opacity(0.25) : (isHovered ? Color.black.opacity(0.15) : Color.clear), radius: isSelected ? 3 : 2, y: 1)
            .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(WalkmanFont.calloutBold)
                    .lineLimit(1)
            }
            .foregroundStyle(
                isProminent ? Color(red: 20/255, green: 20/255, blue: 24/255) :
                (isDestructive ? Color.red.opacity(0.90) : WalkmanTheme.silverLight)
            )
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .buttonStyle(
            LiquidGlassButtonStyle(
                variant: isProminent ? .prominent : (isDestructive ? .destructive : .glass),
                cornerRadius: 8
            )
        )
        .disabled(isDisabled)
    }
}

private struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WalkmanTheme.silverLight)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
        .keyboardShortcut(.cancelAction)
        .help("Close")
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
