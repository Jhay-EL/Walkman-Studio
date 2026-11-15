import SwiftUI
import AppKit

public struct AlbumMetadataEditorSheet: View {
    let album: AlbumItem
    let onSaved: () -> Void
    var onSavedTracks: (([Track]) -> Void)? = nil
    let onDismiss: () -> Void

    public struct EditableTrackRow: Identifiable {
        public var id: String { track.id }
        public var track: Track
        public var trackNum: String
        public var title: String
        public var artist: String
        public var isSenseMeAnalyzed: Bool
        public var hasLyrics: Bool
        public var isSyncedLyrics: Bool

        public init(
            track: Track,
            trackNum: String,
            title: String,
            artist: String,
            isSenseMeAnalyzed: Bool,
            hasLyrics: Bool = false,
            isSyncedLyrics: Bool = false
        ) {
            self.track = track
            self.trackNum = trackNum
            self.title = title
            self.artist = artist
            self.isSenseMeAnalyzed = isSenseMeAnalyzed
            self.hasLyrics = hasLyrics
            self.isSyncedLyrics = isSyncedLyrics
        }
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
    @State private var isAnalyzingSenseMe: Bool = false
    @State private var senseMeProgress: (current: Int, total: Int, title: String)? = nil
    @State private var senseMeStatusMessage: String? = nil
    @State private var showPermissionSheet: Bool = false
    @State private var permissionFileURL: URL? = nil

    // Lyrics state
    @State private var isFetchingLyrics: Bool = false
    @State private var lyricsProgress: (current: Int, total: Int, title: String)? = nil
    @State private var showBatchLyricsSheet: Bool = false

    public init(
        album: AlbumItem,
        onSaved: @escaping () -> Void,
        onSavedTracks: (([Track]) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.album = album
        self.onSaved = onSaved
        self.onSavedTracks = onSavedTracks
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
            let isSenseMe = tr.isSenseMeAnalyzed || SenseMeEngine.shared.inspect(fileURL: URL(fileURLWithPath: tr.fullPath)).isAnalyzed
            let url = URL(fileURLWithPath: tr.fullPath)
            let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
            let hasLyr = lyr != nil && !lyr!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isSynced = hasLyr && (lyr!.contains("[0") || lyr!.contains("[1") || lyr!.contains("[2"))
            return EditableTrackRow(
                track: tr,
                trackNum: tr.trackNum,
                title: tr.title,
                artist: tr.artist,
                isSenseMeAnalyzed: isSenseMe,
                hasLyrics: hasLyr,
                isSyncedLyrics: isSynced
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

    private var unanalyzedTracksCount: Int {
        trackRows.filter { !$0.isSenseMeAnalyzed }.count
    }

    private func refreshTrackRowsLyrics() {
        for i in 0..<trackRows.count {
            let url = URL(fileURLWithPath: trackRows[i].track.fullPath)
            let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
            let hasLyr = lyr != nil && !lyr!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isSynced = hasLyr && (lyr!.contains("[0") || lyr!.contains("[1") || lyr!.contains("[2"))
            trackRows[i].hasLyrics = hasLyr
            trackRows[i].isSyncedLyrics = isSynced
        }
    }

    private func fetchLyricsForSingleTrack(_ row: EditableTrackRow) {
        guard !isFetchingLyrics else { return }
        fetchLyricsForTracks([row])
    }

    private func fetchLyricsForTracks(_ targets: [EditableTrackRow]) {
        guard !isFetchingLyrics && !targets.isEmpty else { return }
        isFetchingLyrics = true
        lyricsProgress = (0, targets.count, targets[0].title)

        let curAlbumName = self.albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAlbum = curAlbumName.isEmpty ? album.name : curAlbumName
        let applyArtist = self.applyArtistToAll
        let curAlbumArtist = self.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            for (idx, row) in targets.enumerated() {
                await MainActor.run {
                    self.lyricsProgress = (idx + 1, targets.count, row.title)
                }

                let effectiveTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.track.title : row.title
                let effectiveArtist = row.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (applyArtist ? curAlbumArtist : row.track.artist) : row.artist

                let trackURL = URL(fileURLWithPath: row.track.fullPath)
                do {
                    var res = try await LyricsService.shared.fetchLyrics(
                        title: effectiveTitle,
                        artist: effectiveArtist,
                        album: finalAlbum,
                        durationSeconds: row.track.durationSeconds
                    )

                    if res.synced {
                        let (calibrated, _) = await AudioAcousticAligner.shared.calibrateLRC(
                            audioURL: trackURL,
                            lyrics: res.lyrics,
                            durationSeconds: row.track.durationSeconds
                        )
                        res = LyricsResult(synced: true, lyrics: calibrated, source: res.source)
                    }

                    try AudioTagger.shared.saveLyrics(
                        fileURL: trackURL,
                        lyrics: res.lyrics,
                        durationSeconds: row.track.durationSeconds
                    )

                    await MainActor.run {
                        if let i = self.trackRows.firstIndex(where: { $0.id == row.id }) {
                            self.trackRows[i].hasLyrics = true
                            self.trackRows[i].isSyncedLyrics = res.synced
                        }
                    }
                } catch {
                    if WalkmanStoragePermissionHelper.isPermissionError(error) {
                        await MainActor.run {
                            self.permissionFileURL = trackURL
                            self.showPermissionSheet = true
                        }
                    }
                }
            }

            await MainActor.run {
                self.isFetchingLyrics = false
                self.lyricsProgress = nil
            }
        }
    }

    private func analyzeAlbumSenseMe() {
        guard !isAnalyzingSenseMe && !trackRows.isEmpty else { return }
        let unanalyzed = trackRows.filter { !$0.isSenseMeAnalyzed }
        let isForce = unanalyzed.isEmpty
        let targets = isForce ? trackRows : unanalyzed
        guard !targets.isEmpty else { return }

        isAnalyzingSenseMe = true
        senseMeProgress = (0, targets.count, targets[0].title)
        senseMeStatusMessage = nil

        Task {
            var successCount = 0
            var permErrorURL: URL? = nil

            for (idx, row) in targets.enumerated() {
                await MainActor.run {
                    self.senseMeProgress = (idx + 1, targets.count, row.title)
                }
                let url = URL(fileURLWithPath: row.track.fullPath)
                do {
                    let info = try await SenseMeEngine.shared.analyzeAndInject(fileURL: url, forceReanalyze: isForce)
                    LibraryScanner.shared.updateCachedSenseMe(fullPath: row.track.fullPath, info: info)

                    await MainActor.run {
                        if let i = self.trackRows.firstIndex(where: { $0.id == row.id }) {
                            self.trackRows[i].isSenseMeAnalyzed = true
                            self.trackRows[i].track.isSenseMeAnalyzed = true
                            self.trackRows[i].track.senseMeBpm = info.bpm
                            self.trackRows[i].track.senseMeValence = info.valence
                            self.trackRows[i].track.senseMeArousal = info.arousal
                            self.trackRows[i].track.senseMeChannels = info.channels
                            self.trackRows[i].track.senseMeHighlightSec = info.highlightSec

                            let updatedTrack = self.trackRows[i].track
                            NotificationCenter.default.post(
                                name: .trackMetadataDidUpdate,
                                object: nil,
                                userInfo: ["trackId": updatedTrack.id, "track": updatedTrack]
                            )
                        }
                    }
                    successCount += 1
                } catch {
                    if WalkmanStoragePermissionHelper.isPermissionError(error) {
                        permErrorURL = url
                    }
                    print("[AlbumMetadataEditor] SenseMe analysis error for '\(row.title)': \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isAnalyzingSenseMe = false
                self.senseMeProgress = nil
                if let pURL = permErrorURL {
                    self.permissionFileURL = pURL
                    self.showPermissionSheet = true
                }
                if successCount > 0 {
                    self.senseMeStatusMessage = isForce ? "Re-analyzed SenseMe for \(successCount) track(s)" : "SenseMe analyzed for \(successCount) track(s)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        self.senseMeStatusMessage = nil
                    }
                }
            }
        }
    }

    private func analyzeSingleTrack(_ row: EditableTrackRow) {
        guard !isAnalyzingSenseMe else { return }
        isAnalyzingSenseMe = true
        senseMeProgress = (1, 1, row.title)
        senseMeStatusMessage = nil

        let isForce = row.isSenseMeAnalyzed

        Task {
            let url = URL(fileURLWithPath: row.track.fullPath)
            do {
                let info = try await SenseMeEngine.shared.analyzeAndInject(fileURL: url, forceReanalyze: isForce)
                LibraryScanner.shared.updateCachedSenseMe(fullPath: row.track.fullPath, info: info)

                await MainActor.run {
                    if let i = self.trackRows.firstIndex(where: { $0.id == row.id }) {
                        self.trackRows[i].isSenseMeAnalyzed = true
                        self.trackRows[i].track.isSenseMeAnalyzed = true
                        self.trackRows[i].track.senseMeBpm = info.bpm
                        self.trackRows[i].track.senseMeValence = info.valence
                        self.trackRows[i].track.senseMeArousal = info.arousal
                        self.trackRows[i].track.senseMeChannels = info.channels
                        self.trackRows[i].track.senseMeHighlightSec = info.highlightSec

                        let updatedTrack = self.trackRows[i].track
                        NotificationCenter.default.post(
                            name: .trackMetadataDidUpdate,
                            object: nil,
                            userInfo: ["trackId": updatedTrack.id, "track": updatedTrack]
                        )
                    }
                    self.isAnalyzingSenseMe = false
                    self.senseMeProgress = nil
                    self.senseMeStatusMessage = "SenseMe analyzed for \(row.title)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        self.senseMeStatusMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzingSenseMe = false
                    self.senseMeProgress = nil
                    if WalkmanStoragePermissionHelper.isPermissionError(error) {
                        self.permissionFileURL = url
                        self.showPermissionSheet = true
                    }
                }
            }
        }
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

            var updatedTracks: [Track] = []
            var permissionErrorURL: URL? = nil

            for (index, row) in rows.enumerated() {
                await MainActor.run {
                    self.saveProgress = Double(index) / Double(max(1, total))
                    self.saveStatus = "Updating track \(index + 1) of \(total): \(row.title)..."
                }

                let trackURL = URL(fileURLWithPath: row.track.fullPath)
                let trackTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackArtist = shouldApplyArtist ? finalAlbumArtist : row.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackNum = row.trackNum.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = trackTitle.isEmpty ? row.track.title : trackTitle
                let finalArtist = trackArtist.isEmpty ? row.track.artist : trackArtist
                let finalTrackNum = trackNum.isEmpty ? row.track.trackNum : trackNum

                do {
                    try AudioTagger.shared.writeMetadata(
                        fileURL: trackURL,
                        title: finalTitle,
                        artist: finalArtist,
                        album: finalAlbumName,
                        trackNumber: finalTrackNum,
                        year: finalYear,
                        genre: finalGenre,
                        coverArtData: artModified ? encodedArtwork : nil
                    )

                    AudioTagger.shared.invalidateCaches(fileURL: trackURL)
                    
                    // Invalidate previous and updated artwork caches
                    CoverArtCache.shared.invalidate(forFullPath: row.track.fullPath, artist: row.track.primaryArtist, album: row.track.album)
                    CoverArtCache.shared.invalidate(forFullPath: row.track.fullPath, artist: finalArtist, album: finalAlbumName)
                    
                    // If new cover image exists, write directly to CoverArtCache for instant zero-latency preview
                    if artModified, let enc = encodedArtwork, !enc.isEmpty, let newImg = NSImage(data: enc) {
                        CoverArtCache.shared.storeThumbnail(newImg, forFullPath: row.track.fullPath, artist: finalArtist, album: finalAlbumName)
                    }

                    let hasArt = artModified ? (encodedArtwork != nil && !encodedArtwork!.isEmpty) : row.track.hasArtwork

                    // Update SQLite database directly with fresh metadata & modification time
                    LibraryScanner.shared.updateTrackInCache(
                        fullPath: row.track.fullPath,
                        title: finalTitle,
                        artist: finalArtist,
                        album: finalAlbumName,
                        trackNum: finalTrackNum,
                        year: finalYear,
                        genre: finalGenre,
                        hasArtwork: hasArt
                    )

                    var updated = row.track
                    updated.title = finalTitle
                    updated.artist = finalArtist
                    updated.album = finalAlbumName
                    updated.trackNum = finalTrackNum
                    updated.year = finalYear
                    updated.genre = finalGenre
                    updated.hasArtwork = hasArt
                    updated.isSenseMeAnalyzed = row.isSenseMeAnalyzed
                    if row.isSenseMeAnalyzed {
                        updated.senseMeBpm = row.track.senseMeBpm
                        updated.senseMeValence = row.track.senseMeValence
                        updated.senseMeArousal = row.track.senseMeArousal
                        updated.senseMeChannels = row.track.senseMeChannels
                        updated.senseMeHighlightSec = row.track.senseMeHighlightSec
                    }
                    updatedTracks.append(updated)
                } catch {
                    if WalkmanStoragePermissionHelper.isPermissionError(error) {
                        permissionErrorURL = trackURL
                    }
                    print("[AlbumMetadataEditor] Error saving track \(row.track.filename): \(error.localizedDescription)")
                }
            }

            if let permURL = permissionErrorURL, updatedTracks.isEmpty {
                await MainActor.run {
                    self.isSaving = false
                    self.permissionFileURL = permURL
                    self.showPermissionSheet = true
                    self.saveStatus = "Storage permission required to edit files."
                }
                return
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

            let finalTracks = updatedTracks

            await MainActor.run {
                self.saveProgress = 1.0
                self.saveStatus = "Saved album successfully!"
                self.isSaving = false
                NotificationCenter.default.post(
                    name: .trackMetadataDidUpdate,
                    object: nil,
                    userInfo: ["albumName": finalAlbumName, "albumArtist": finalAlbumArtist, "tracks": finalTracks]
                )
                self.onSavedTracks?(finalTracks)
                self.onSaved()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
                VStack(spacing: 18) {
                    // Top Section: Album Artwork + Album-Wide Tags
                    HStack(alignment: .top, spacing: 22) {
                        artworkColumn
                            .frame(width: 255)

                        albumTagsColumn
                    }
                    .padding(16)
                    .studioGlassCard(cornerRadius: 14)

                    // Bottom Section: Tracklist & Track Numbers
                    tracklistSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Footer Bar
            footerBar
        }
        .frame(minWidth: 1040, idealWidth: 1120, maxWidth: 1240, minHeight: 700, idealHeight: 780, maxHeight: 900)
        .modalGlassChassis(cornerRadius: 16)
        .sheet(isPresented: $showPermissionSheet) {
            if let fURL = permissionFileURL ?? trackRows.first.map({ URL(fileURLWithPath: $0.track.fullPath) }) {
                StoragePermissionRequestSheet(
                    fileURL: fURL,
                    onGranted: {
                        showPermissionSheet = false
                        permissionFileURL = nil
                        saveAlbumChanges()
                    },
                    onDismiss: {
                        showPermissionSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $showBatchLyricsSheet) {
            BatchLyricsGeneratorSheet(
                allTracks: trackRows.map(\.track),
                selectedTracks: [],
                tabContext: .albums(
                    selectedAlbumName: self.albumName.isEmpty ? album.name : self.albumName,
                    albumTrackCount: trackRows.count
                ),
                onDismiss: {
                    showBatchLyricsSheet = false
                    refreshTrackRowsLyrics()
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
            LiquidGlassIconBadge(icon: "square.stack.fill", size: 32)

            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Artwork Column
    private var artworkColumn: some View {
        VStack(spacing: 12) {
            ZStack {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230, height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.22))
                            .frame(width: 230, height: 230)
                            .background(Color.white.opacity(0.02))

                        VStack(spacing: 7) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 36))
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

            // Artwork Action Buttons
            HStack(spacing: 8) {
                Button(action: selectArtworkFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Choose...")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ALBUM PROPERTIES (APPLIED TO ALL TRACKS)")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: fetchOnlineAlbumMetadata) {
                    HStack(spacing: 5) {
                        if isFetchingOnlineInfo {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                                .frame(width: 12, height: 12)
                            Text("Matching...")
                                .font(WalkmanFont.calloutBold)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Auto-Fill Album Info")
                                .font(WalkmanFont.calloutBold)
                        }
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                .disabled(isFetchingOnlineInfo)
                .help("Query iTunes and Deezer databases to match album title, artist, year, and genre")
            }

            AlbumInputField(label: "Album Title", text: $albumName)

            VStack(alignment: .leading, spacing: 5) {
                AlbumInputField(label: "Album Artist", text: $albumArtist)

                Toggle("Apply this artist to all track tags", isOn: $applyArtistToAll)
                    .font(WalkmanFont.subheadline)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.top, 3)
            }

            HStack(spacing: 14) {
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
                HStack(spacing: 8) {
                    Text("TRACKLIST & TRACK NUMBERS")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)

                    Text("(\(trackRows.count))")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(.secondary)

                    if let msg = senseMeStatusMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(WalkmanTheme.hiResGold)
                            Text(msg)
                                .font(WalkmanFont.captionBold)
                                .foregroundStyle(WalkmanTheme.silverLight)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WalkmanTheme.hiResGold.opacity(0.12))
                        .clipShape(Capsule())
                        .transition(.opacity)
                    }
                }

                Spacer()

                // Quick Action Buttons
                HStack(spacing: 8) {
                    Button(action: autoNumberTracks) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.number")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Auto-Number (1..N)")
                                .font(WalkmanFont.calloutBold)
                        }
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .help("Automatically renumbers all tracks from 1 to \(trackRows.count)")

                    Button(action: padTrackNumbers) {
                        HStack(spacing: 5) {
                            Image(systemName: "number")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Pad (01..N)")
                                .font(WalkmanFont.calloutBold)
                        }
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .help("Formats track numbers with leading zero (01, 02...) for optimal Walkman alphabetical folder sorting")

                    Button(action: sortTracksByTrackNum) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .help("Sort list by track number")

                    Button(action: sortTracksByTitle) {
                        Image(systemName: "textformat.abc")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .help("Sort list by track title")

                    Button(action: analyzeAlbumSenseMe) {
                        HStack(spacing: 5) {
                            if isAnalyzingSenseMe, let prog = senseMeProgress {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                                Text("\(prog.current)/\(prog.total)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            } else {
                                Image(systemName: unanalyzedTracksCount > 0 ? "waveform.path.ecg" : "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(unanalyzedTracksCount > 0 ? WalkmanTheme.silverLight : WalkmanTheme.hiResGold)
                                Text(unanalyzedTracksCount > 0 ? "Analyze SenseMe (\(unanalyzedTracksCount))" : "Re-Analyze SenseMe")
                                    .font(WalkmanFont.calloutBold)
                            }
                        }
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .disabled(isAnalyzingSenseMe || trackRows.isEmpty)
                    .help(unanalyzedTracksCount > 0 ? "Analyze \(unanalyzedTracksCount) track(s) for Sony 12 Tone / SenseMe and embed hardware-compatible metadata" : "Re-analyze all tracks in this album for Sony 12 Tone / SenseMe")

                    Button(action: { showBatchLyricsSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "quote.bubble")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Fetch Lyrics...")
                                .font(WalkmanFont.calloutBold)
                        }
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .disabled(trackRows.isEmpty)
                    .help("Open LRC Fetcher to search and sync lyrics for all or selected tracks in this album")
                }
            }

            // Tracklist Table
            VStack(spacing: 0) {
                // Table Column Header
                HStack(spacing: 12) {
                    Text("#")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 50, alignment: .center)

                    Text("Order")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .center)

                    Text("Track Title")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !applyArtistToAll {
                        Text("Track Artist")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .frame(width: 240, alignment: .leading)
                    }

                    Text("Format")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .center)

                    Text("SenseMe")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 65, alignment: .center)

                    Text("Lyrics")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .center)

                    Text("Duration")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
                            onAnalyzeSenseMe: { analyzeSingleTrack(row) },
                            onFetchLyrics: { fetchLyricsForSingleTrack(row) },
                            formatDuration: formatDuration
                        )

                        if index < trackRows.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.04))
                        }
                    }
                }
            }
            .studioGlassCard(cornerRadius: 12)
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
                if permissionFileURL != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(saveStatus)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.orange)

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
                } else if let err = errorMessage {
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

                Button(action: saveAlbumChanges) {
                    HStack(spacing: 7) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                            Text("Saving Album...")
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Save Album (\(trackRows.count) Tracks)")
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
}

// MARK: - Track Row View
private struct TrackRowView: View {
    let index: Int
    let totalCount: Int
    @Binding var row: AlbumMetadataEditorSheet.EditableTrackRow
    let applyArtistToAll: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAnalyzeSenseMe: () -> Void
    let onFetchLyrics: () -> Void
    let formatDuration: (Double) -> String

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Track Number TextField
            TextField("", text: $row.trackNum)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 6.5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
                .frame(width: 50)

            // Reorder Up/Down buttons
            HStack(spacing: 3) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 5))
                .disabled(index == 0)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 5))
                .disabled(index == totalCount - 1)
            }
            .frame(width: 48)

            // Title TextField
            TextField("", text: $row.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                )
                .frame(maxWidth: .infinity)

            // Artist TextField (if not applied to all)
            if !applyArtistToAll {
                TextField("", text: $row.artist)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                    )
                    .frame(width: 240)
            }

            // Format
            Text(row.track.format)
                .font(WalkmanFont.badge)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .center)

            // SenseMe Badge
            if row.isSenseMeAnalyzed {
                HStack(spacing: 2.5) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 7.5, weight: .bold))
                    Text("12 TONE")
                        .font(WalkmanFont.badge)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(WalkmanTheme.hiResGold.opacity(0.18)))
                .overlay(Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.8))
                .foregroundStyle(WalkmanTheme.hiResGoldLight)
                .frame(width: 65, alignment: .center)
                .help("Sony 12 Tone / SenseMe Analyzed" + (row.track.senseMeChannels.isEmpty ? "" : " • \(row.track.senseMeChannels.joined(separator: ", "))"))
            } else {
                Text("—")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .frame(width: 65, alignment: .center)
            }

            // Lyrics Badge
            if row.hasLyrics {
                HStack(spacing: 2.5) {
                    Image(systemName: row.isSyncedLyrics ? "quote.bubble.fill" : "doc.text.fill")
                        .font(.system(size: 7))
                    Text(row.isSyncedLyrics ? ".LRC" : "TXT")
                        .font(WalkmanFont.badge)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(row.isSyncedLyrics ? WalkmanTheme.hiResGold.opacity(0.18) : Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(row.isSyncedLyrics ? WalkmanTheme.hiResGold.opacity(0.35) : Color.white.opacity(0.15), lineWidth: 0.8))
                .foregroundStyle(row.isSyncedLyrics ? WalkmanTheme.hiResGoldLight : WalkmanTheme.silverLight)
                .frame(width: 60, alignment: .center)
            } else {
                Text("—")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .frame(width: 60, alignment: .center)
            }

            // Duration
            Text(formatDuration(row.track.durationSeconds))
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isHovered ? Color.white.opacity(0.045) : (index % 2 == 1 ? Color.white.opacity(0.015) : Color.clear)
        )
        .contextMenu {
            Button(action: onFetchLyrics) {
                Label(row.hasLyrics ? "Re-Fetch Lyrics (.LRC)" : "Fetch Lyrics (.LRC)", systemImage: "quote.bubble")
            }
            Divider()
            Button(action: onAnalyzeSenseMe) {
                Label(row.isSenseMeAnalyzed ? "Re-Analyze SenseMe (12 Tone)" : "Analyze SenseMe (12 Tone)", systemImage: "waveform.path.ecg")
            }
        }
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

private struct AlbumIconSquareButton: View {
    let icon: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    var helpText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isDestructive ? Color(red: 255/255, green: 120/255, blue: 110/255) : WalkmanTheme.silverLight)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: isDestructive ? .destructive : .glass, cornerRadius: 8))
        .disabled(isDisabled)
        .help(helpText)
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
