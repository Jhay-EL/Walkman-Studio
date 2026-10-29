import Foundation
import SQLite3
import AppKit
import Combine
import CoreServices

// -----------------------------------------------------------------------------
// Real-Time Filesystem Monitoring via macOS FSEvents (Recursive Directory Watcher)
// -----------------------------------------------------------------------------
private final class LocalLibraryFolderWatcher: @unchecked Sendable {
    private var streamRef: FSEventStreamRef?
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func updatePaths(_ paths: [String]) {
        stop()
        let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !validPaths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<LocalLibraryFolderWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            watcher.onChange()
        }

        let cfPaths = validPaths as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1.0 second coalescing latency
            flags
        ) else { return }

        self.streamRef = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }

    deinit {
        stop()
    }
}

public final class LocalMusicLibraryService: ObservableObject, @unchecked Sendable {
    public static let shared = LocalMusicLibraryService()

    @Published public private(set) var tracks: [Track] = []
    @Published public private(set) var folders: [LocalMusicFolder] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanStatusText: String? = nil
    @Published public private(set) var precomputedAlbums: [AlbumItem] = []
    @Published public private(set) var precomputedArtists: [ArtistItem] = []
    @Published public private(set) var totalSizeBytes: Int64 = 0
    @Published public private(set) var hiResCount: Int = 0

    private let supportedExts: Set<String> = [
        "flac", "mp3", "m4a", "m4b", "aac", "alac", "wav", "aif", "aiff", "dsf", "dff", "ape", "wma"
    ]

    private let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".walkman_local_library.db").path
    }()

    private let lock = NSLock()
    private var folderWatcher: LocalLibraryFolderWatcher?
    private var debounceTimer: Task<Void, Never>?
    private var hasPendingScan: Bool = false

    private init() {
        initDatabase()
        loadFromDatabase()
        setupFolderWatcher()
        setupAppLifecycleObserver()
    }

    private func setupFolderWatcher() {
        folderWatcher = LocalLibraryFolderWatcher { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleFileSystemChange()
            }
        }
        updateWatcherPaths()
    }

    public func updateWatcherPaths() {
        let paths = folders.map(\.path)
        folderWatcher?.updatePaths(paths)
    }

    private func setupAppLifecycleObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleFileSystemChange()
            }
        }
    }

    @MainActor
    private func handleFileSystemChange() {
        debounceTimer?.cancel()
        debounceTimer = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s debounce to allow Finder file writes to settle
            guard !Task.isCancelled else { return }

            if self.isScanning {
                self.hasPendingScan = true
                return
            }
            self.rescanAllFolders()
        }
    }

    // -------------------------------------------------------------------------
    // SQLite Database Setup
    // -------------------------------------------------------------------------
    private func getDB() -> OpaquePointer? {
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            return nil
        }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        return db
    }

    private func initDatabase() {
        guard let db = getDB() else { return }
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE IF NOT EXISTS local_library_folders (
            id TEXT PRIMARY KEY,
            path TEXT UNIQUE,
            display_name TEXT,
            date_added REAL,
            last_scanned REAL,
            track_count INTEGER DEFAULT 0,
            total_bytes INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS local_library_tracks (
            full_path TEXT PRIMARY KEY,
            folder_id TEXT,
            mtime REAL,
            size INTEGER,
            format TEXT,
            title TEXT,
            artist TEXT,
            album TEXT,
            track_num TEXT,
            year TEXT,
            genre TEXT,
            duration_seconds REAL,
            bitrate_kbps INTEGER,
            sample_rate INTEGER,
            bits_per_sample INTEGER,
            has_artwork INTEGER,
            relative_path TEXT,
            date_added REAL,
            is_senseme INTEGER DEFAULT 0,
            senseme_bpm REAL DEFAULT 0,
            senseme_valence REAL DEFAULT 0,
            senseme_arousal REAL DEFAULT 0,
            senseme_channels TEXT DEFAULT '',
            senseme_highlight_sec REAL DEFAULT 0,
            FOREIGN KEY(folder_id) REFERENCES local_library_folders(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_local_folder ON local_library_tracks(folder_id);
        CREATE INDEX IF NOT EXISTS idx_local_artist ON local_library_tracks(artist);
        CREATE INDEX IF NOT EXISTS idx_local_album ON local_library_tracks(album);
        """

        sqlite3_exec(db, schema, nil, nil, nil)
    }

    // -------------------------------------------------------------------------
    // Database Retrieval
    // -------------------------------------------------------------------------
    public func loadFromDatabase() {
        guard let db = getDB() else { return }
        defer { sqlite3_close(db) }

        // 1. Load Folders
        var loadedFolders: [LocalMusicFolder] = []
        let folderQuery = "SELECT id, path, display_name, date_added, last_scanned, track_count, total_bytes FROM local_library_folders ORDER BY date_added ASC;"
        var fStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, folderQuery, -1, &fStmt, nil) == SQLITE_OK {
            while sqlite3_step(fStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(fStmt, 0))
                let path = String(cString: sqlite3_column_text(fStmt, 1))
                let name = sqlite3_column_text(fStmt, 2).map { String(cString: $0) } ?? URL(fileURLWithPath: path).lastPathComponent
                let dateAddedSec = sqlite3_column_double(fStmt, 3)
                let lastScannedSec = sqlite3_column_double(fStmt, 4)
                let trackCount = Int(sqlite3_column_int(fStmt, 5))
                let totalBytes = sqlite3_column_int64(fStmt, 6)

                let folder = LocalMusicFolder(
                    id: id,
                    path: path,
                    displayName: name,
                    dateAdded: Date(timeIntervalSince1970: dateAddedSec > 0 ? dateAddedSec : Date().timeIntervalSince1970),
                    lastScanned: Date(timeIntervalSince1970: lastScannedSec > 0 ? lastScannedSec : Date().timeIntervalSince1970),
                    trackCount: trackCount,
                    totalBytes: totalBytes
                )
                loadedFolders.append(folder)
            }
            sqlite3_finalize(fStmt)
        }

        // 2. Load Tracks
        var loadedTracks: [Track] = []
        let trackQuery = """
        SELECT full_path, mtime, size, format, title, artist, album, track_num, year, genre,
               duration_seconds, bitrate_kbps, sample_rate, bits_per_sample, has_artwork, relative_path, date_added,
               is_senseme, senseme_bpm, senseme_valence, senseme_arousal, senseme_channels, senseme_highlight_sec
        FROM local_library_tracks;
        """
        var tStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, trackQuery, -1, &tStmt, nil) == SQLITE_OK {
            while sqlite3_step(tStmt) == SQLITE_ROW {
                let fPath = String(cString: sqlite3_column_text(tStmt, 0))
                let mtime = sqlite3_column_double(tStmt, 1)
                let size = sqlite3_column_int64(tStmt, 2)
                let fmt = String(cString: sqlite3_column_text(tStmt, 3))
                let title = sqlite3_column_text(tStmt, 4).map { String(cString: $0) } ?? ""
                let artist = sqlite3_column_text(tStmt, 5).map { String(cString: $0) } ?? "Unknown Artist"
                let album = sqlite3_column_text(tStmt, 6).map { String(cString: $0) } ?? "Unknown Album"
                let trackNum = sqlite3_column_text(tStmt, 7).map { String(cString: $0) } ?? ""
                let year = sqlite3_column_text(tStmt, 8).map { String(cString: $0) } ?? ""
                let genre = sqlite3_column_text(tStmt, 9).map { String(cString: $0) } ?? ""
                let duration = sqlite3_column_double(tStmt, 10)
                let bitrate = Int(sqlite3_column_int(tStmt, 11))
                let sampleRate = Int(sqlite3_column_int(tStmt, 12))
                let bitsPerSample = Int(sqlite3_column_int(tStmt, 13))
                let hasArt = sqlite3_column_int(tStmt, 14) != 0
                let relPath = sqlite3_column_text(tStmt, 15).map { String(cString: $0) } ?? URL(fileURLWithPath: fPath).lastPathComponent
                let dateAddedSec = sqlite3_column_double(tStmt, 16)
                let effectiveAdded = dateAddedSec > 0 ? dateAddedSec : mtime
                let dateAdded = Date(timeIntervalSince1970: effectiveAdded > 0 ? effectiveAdded : CFAbsoluteTimeGetCurrent() + 978307200.0)

                let isSenseMe = sqlite3_column_int(tStmt, 17) != 0
                let sBpm = sqlite3_column_double(tStmt, 18)
                let sValence = sqlite3_column_double(tStmt, 19)
                let sArousal = sqlite3_column_double(tStmt, 20)
                let channelsStr = sqlite3_column_text(tStmt, 21).map { String(cString: $0) } ?? ""
                let sChannels = channelsStr.isEmpty ? [] : channelsStr.components(separatedBy: ",")
                let sHighlight = sqlite3_column_double(tStmt, 22)

                let cleanTitle = WalkmanEngine.sanitizeWalkmanText(title)
                let cleanArtist = WalkmanEngine.sanitizeWalkmanText(artist, stripExplicitMarkers: false)
                let cleanAlbum = WalkmanEngine.sanitizeWalkmanText(album)
                let fallbackTitle = WalkmanEngine.sanitizeWalkmanText(URL(fileURLWithPath: fPath).deletingPathExtension().lastPathComponent)

                let tr = Track(
                    filename: URL(fileURLWithPath: fPath).lastPathComponent,
                    relativePath: relPath,
                    fullPath: fPath,
                    format: fmt,
                    title: cleanTitle.isEmpty ? (fallbackTitle.isEmpty ? "Unknown Track" : fallbackTitle) : cleanTitle,
                    artist: cleanArtist.isEmpty ? "Unknown Artist" : cleanArtist,
                    album: cleanAlbum.isEmpty ? "Unknown Album" : cleanAlbum,
                    trackNum: trackNum.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")),
                    year: year,
                    genre: genre,
                    durationSeconds: duration,
                    bitrateKbps: bitrate,
                    sampleRate: sampleRate,
                    bitsPerSample: bitsPerSample,
                    hasArtwork: hasArt,
                    sizeBytes: size,
                    dateAdded: dateAdded,
                    isSenseMeAnalyzed: isSenseMe,
                    senseMeBpm: sBpm > 0 ? sBpm : nil,
                    senseMeValence: isSenseMe ? sValence : nil,
                    senseMeArousal: isSenseMe ? sArousal : nil,
                    senseMeChannels: sChannels,
                    senseMeHighlightSec: sHighlight > 0 ? sHighlight : nil
                )
                loadedTracks.append(tr)
            }
            sqlite3_finalize(tStmt)
        }

        self.folders = loadedFolders
        self.tracks = loadedTracks
        recomputeStats(with: loadedTracks)
        reInspectAllSenseMe()
    }

    private func recomputeStats(with trackList: [Track]) {
        let albums = AlbumsView.buildAlbums(from: trackList)
        let artists = ArtistsView.buildArtists(from: trackList)
        var totalBytes: Int64 = 0
        var hiRes = 0
        for tr in trackList {
            totalBytes += tr.sizeBytes
            if tr.bitsPerSample > 16 || tr.sampleRate > 48000 {
                hiRes += 1
            }
        }
        self.precomputedAlbums = albums
        self.precomputedArtists = artists
        self.totalSizeBytes = totalBytes
        self.hiResCount = hiRes
    }

    // -------------------------------------------------------------------------
    // Folder Management
    // -------------------------------------------------------------------------
    public func addFolders(urls: [URL]) {
        guard !urls.isEmpty else { return }
        var newFolders: [LocalMusicFolder] = []

        if let db = getDB() {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            let insertSql = "INSERT OR IGNORE INTO local_library_folders (id, path, display_name, date_added, last_scanned, track_count, total_bytes) VALUES (?, ?, ?, ?, ?, 0, 0);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSql, -1, &stmt, nil) == SQLITE_OK {
                for url in urls {
                    let path = url.standardizedFileURL.path
                    guard FileManager.default.fileExists(atPath: path) else { continue }
                    // Prevent duplicate folder paths
                    if folders.contains(where: { $0.path == path }) { continue }

                    let id = UUID().uuidString
                    let name = url.lastPathComponent.isEmpty ? "Music Folder" : url.lastPathComponent
                    let now = Date().timeIntervalSince1970

                    sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 2, (path as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(stmt, 3, (name as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(stmt, 4, now)
                    sqlite3_bind_double(stmt, 5, now)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)

                    let f = LocalMusicFolder(
                        id: id,
                        path: path,
                        displayName: name,
                        dateAdded: Date(timeIntervalSince1970: now),
                        lastScanned: Date(timeIntervalSince1970: now)
                    )
                    newFolders.append(f)
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_close(db)
        }

        if !newFolders.isEmpty {
            self.folders.append(contentsOf: newFolders)
            self.updateWatcherPaths()
            Task {
                await rescanFolders(newFolders)
            }
        }
    }

    public func removeFolder(id: String) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        let folderPath = folder.path

        if let db = getDB() {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            let delTracks = "DELETE FROM local_library_tracks WHERE folder_id = ?;"
            var tStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delTracks, -1, &tStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(tStmt, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_step(tStmt)
                sqlite3_finalize(tStmt)
            }

            let delFolder = "DELETE FROM local_library_folders WHERE id = ?;"
            var fStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, delFolder, -1, &fStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(fStmt, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_step(fStmt)
                sqlite3_finalize(fStmt)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_close(db)
        }

        self.folders.removeAll(where: { $0.id == id })
        self.tracks.removeAll(where: { $0.fullPath.hasPrefix(folderPath) })
        recomputeStats(with: self.tracks)
        self.updateWatcherPaths()
    }

    // -------------------------------------------------------------------------
    // Incremental Scanner
    // -------------------------------------------------------------------------
    public func rescanAllFolders() {
        guard !self.isScanning else {
            self.hasPendingScan = true
            return
        }
        let targets = self.folders
        guard !targets.isEmpty else { return }
        Task {
            await rescanFolders(targets)
        }
    }

    public func rescanFolder(url: URL) {
        let targetPath = url.standardizedFileURL.path
        if let match = folders.first(where: { targetPath.hasPrefix($0.path) || $0.path == targetPath }) {
            guard !self.isScanning else {
                self.hasPendingScan = true
                return
            }
            Task {
                await rescanFolders([match])
            }
        }
    }

    private func rescanFolders(_ targets: [LocalMusicFolder]) async {
        await MainActor.run {
            self.isScanning = true
            self.scanStatusText = "Scanning folders..."
        }

        let fileManager = FileManager.default
        var updatedTracksMap = [String: Track]()
        for t in self.tracks {
            updatedTracksMap[t.fullPath] = t
        }

        for folder in targets {
            let scanURL = folder.url
            guard fileManager.fileExists(atPath: scanURL.path) else { continue }

            await MainActor.run {
                self.scanStatusText = "Indexing \(folder.displayName)..."
            }

            // Read existing cached mtimes and sizes from SQLite for this folder
            var cachedMtimes: [String: Double] = [:]
            var cachedSizes: [String: Int64] = [:]
            if let db = getDB() {
                let q = "SELECT full_path, mtime, size FROM local_library_tracks WHERE folder_id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, (folder.id as NSString).utf8String, -1, nil)
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let path = String(cString: sqlite3_column_text(stmt, 0))
                        let mtime = sqlite3_column_double(stmt, 1)
                        let size = sqlite3_column_int64(stmt, 2)
                        cachedMtimes[path] = mtime
                        cachedSizes[path] = size
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }

            // Enumerate files on disk
            var discoveredPaths = Set<String>()
            var filesToEnrich: [(url: URL, fullPath: String, size: Int64, mtime: Double, relPath: String, ext: String)] = []

            if let enumerator = fileManager.enumerator(
                at: scanURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let filename = fileURL.lastPathComponent
                    if filename.hasPrefix("._") || filename.hasPrefix(".") { continue }

                    let ext = fileURL.pathExtension.lowercased()
                    guard self.supportedExts.contains(ext) else { continue }

                    let fullPath = fileURL.path
                    discoveredPaths.insert(fullPath)

                    let rValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let curMtime = rValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
                    let curSize = Int64(rValues?.fileSize ?? 0)
                    let cachedMtime = cachedMtimes[fullPath] ?? 0
                    let cachedSize = cachedSizes[fullPath] ?? 0

                    if abs(cachedMtime - curMtime) < 1.0 && cachedSize == curSize, updatedTracksMap[fullPath] != nil {
                        // File is unchanged
                        continue
                    } else {
                        let relPath = fullPath.replacingOccurrences(of: scanURL.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        filesToEnrich.append((fileURL, fullPath, curSize, curMtime, relPath, ext))
                    }
                }
            }

            // Detect deleted files
            var deletedPaths = [String]()
            for cachedPath in cachedMtimes.keys {
                if !discoveredPaths.contains(cachedPath) {
                    deletedPaths.append(cachedPath)
                }
            }

            // Remove deleted files from DB and in-memory
            if !deletedPaths.isEmpty {
                if let db = getDB() {
                    sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
                    let delSql = "DELETE FROM local_library_tracks WHERE full_path = ?;"
                    var dStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delSql, -1, &dStmt, nil) == SQLITE_OK {
                        for delPath in deletedPaths {
                            sqlite3_bind_text(dStmt, 1, (delPath as NSString).utf8String, -1, nil)
                            sqlite3_step(dStmt)
                            sqlite3_reset(dStmt)
                            updatedTracksMap.removeValue(forKey: delPath)
                        }
                        sqlite3_finalize(dStmt)
                    }
                    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                    sqlite3_close(db)
                }
            }

            // Enrich new or modified files
            if !filesToEnrich.isEmpty {
                var newTracks: [Track] = []
                let db = getDB()
                if let db = db {
                    sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
                }

                let insertSql = """
                INSERT OR REPLACE INTO local_library_tracks
                (full_path, folder_id, mtime, size, format, title, artist, album, track_num, year, genre,
                 duration_seconds, bitrate_kbps, sample_rate, bits_per_sample, has_artwork, relative_path, date_added,
                 is_senseme, senseme_bpm, senseme_valence, senseme_arousal, senseme_channels, senseme_highlight_sec)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
                var insertStmt: OpaquePointer?
                if let db = db {
                    _ = sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil)
                }

                for item in filesToEnrich {
                    let fileURL = item.url
                    let meta = AudioTagger.shared.readMetadata(fileURL: fileURL)
                    // High-speed on-board acoustic analyzer (Pure Swift / zero CPU spikes)
                    let senseMe = SenseMeEngine.shared.analyzeTrackOnBoard(fileURL: fileURL, metadata: meta, injectSMFM: false)
                    let cleanTitle = WalkmanEngine.sanitizeWalkmanText(meta?.title ?? "")
                    let cleanArtist = WalkmanEngine.sanitizeWalkmanText(meta?.artist ?? "", stripExplicitMarkers: false)
                    let cleanAlbum = WalkmanEngine.sanitizeWalkmanText(meta?.album ?? "")
                    let fallbackStem = WalkmanEngine.sanitizeWalkmanText(fileURL.deletingPathExtension().lastPathComponent)

                    let title = cleanTitle.isEmpty ? (fallbackStem.isEmpty ? "Unknown Track" : fallbackStem) : cleanTitle
                    let artist = cleanArtist.isEmpty ? "Unknown Artist" : cleanArtist
                    let album = cleanAlbum.isEmpty ? "Unknown Album" : cleanAlbum
                    let trackNum = meta?.trackNumber ?? ""
                    let year = meta?.year ?? ""
                    let genre = meta?.genre ?? ""
                    let duration = meta?.durationSeconds ?? 0
                    let bitrate = meta?.bitrateKbps ?? 0
                    let sampleRate = meta?.sampleRate ?? 44100
                    let bitsPerSample = meta?.bitsPerSample ?? 16
                    let hasArt = meta?.hasArtwork ?? false
                    let dateAdded = Date(timeIntervalSince1970: item.mtime > 0 ? item.mtime : Date().timeIntervalSince1970)

                    let tr = Track(
                        filename: fileURL.lastPathComponent,
                        relativePath: item.relPath,
                        fullPath: item.fullPath,
                        format: item.ext.uppercased(),
                        title: title,
                        artist: artist,
                        album: album,
                        trackNum: trackNum,
                        year: year,
                        genre: genre,
                        durationSeconds: duration,
                        bitrateKbps: bitrate,
                        sampleRate: sampleRate,
                        bitsPerSample: bitsPerSample,
                        hasArtwork: hasArt,
                        sizeBytes: item.size,
                        dateAdded: dateAdded,
                        isSenseMeAnalyzed: senseMe.isAnalyzed,
                        senseMeBpm: senseMe.isAnalyzed ? senseMe.bpm : nil,
                        senseMeValence: senseMe.isAnalyzed ? senseMe.valence : nil,
                        senseMeArousal: senseMe.isAnalyzed ? senseMe.arousal : nil,
                        senseMeChannels: senseMe.channels,
                        senseMeHighlightSec: senseMe.highlightSec > 0 ? senseMe.highlightSec : nil
                    )

                    newTracks.append(tr)
                    updatedTracksMap[item.fullPath] = tr

                    if let stmt = insertStmt {
                        sqlite3_bind_text(stmt, 1, (item.fullPath as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 2, (folder.id as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(stmt, 3, item.mtime)
                        sqlite3_bind_int64(stmt, 4, item.size)
                        sqlite3_bind_text(stmt, 5, (item.ext.uppercased() as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 6, (title as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 7, (artist as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 8, (album as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 9, (trackNum as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 10, (year as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 11, (genre as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(stmt, 12, duration)
                        sqlite3_bind_int(stmt, 13, Int32(bitrate))
                        sqlite3_bind_int(stmt, 14, Int32(sampleRate))
                        sqlite3_bind_int(stmt, 15, Int32(bitsPerSample))
                        sqlite3_bind_int(stmt, 16, hasArt ? 1 : 0)
                        sqlite3_bind_text(stmt, 17, (item.relPath as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(stmt, 18, dateAdded.timeIntervalSince1970)
                        sqlite3_bind_int(stmt, 19, senseMe.isAnalyzed ? 1 : 0)
                        sqlite3_bind_double(stmt, 20, senseMe.bpm)
                        sqlite3_bind_double(stmt, 21, senseMe.valence)
                        sqlite3_bind_double(stmt, 22, senseMe.arousal)
                        sqlite3_bind_text(stmt, 23, (senseMe.channels.joined(separator: ",") as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(stmt, 24, senseMe.highlightSec)

                        sqlite3_step(stmt)
                        sqlite3_reset(stmt)
                    }
                }

                if let db = db {
                    if let stmt = insertStmt { sqlite3_finalize(stmt) }
                    sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                    sqlite3_close(db)
                }
            }

            // Update folder metrics in DB
            let totalFolderTracks = discoveredPaths.count
            var totalFolderBytes: Int64 = 0
            for path in discoveredPaths {
                if let tr = updatedTracksMap[path] {
                    totalFolderBytes += tr.sizeBytes
                }
            }

            if let db = getDB() {
                let updateFolderSql = "UPDATE local_library_folders SET last_scanned = ?, track_count = ?, total_bytes = ? WHERE id = ?;"
                var uStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, updateFolderSql, -1, &uStmt, nil) == SQLITE_OK {
                    sqlite3_bind_double(uStmt, 1, Date().timeIntervalSince1970)
                    sqlite3_bind_int(uStmt, 2, Int32(totalFolderTracks))
                    sqlite3_bind_int64(uStmt, 3, totalFolderBytes)
                    sqlite3_bind_text(uStmt, 4, (folder.id as NSString).utf8String, -1, nil)
                    sqlite3_step(uStmt)
                    sqlite3_finalize(uStmt)
                }
                sqlite3_close(db)
            }

            // Update folder in memory
            if let idx = self.folders.firstIndex(where: { $0.id == folder.id }) {
                var f = self.folders[idx]
                f.lastScanned = Date()
                f.trackCount = totalFolderTracks
                f.totalBytes = totalFolderBytes
                self.folders[idx] = f
            }
        }

        let allFinalTracks = Array(updatedTracksMap.values)
        await MainActor.run {
            self.tracks = allFinalTracks
            self.recomputeStats(with: allFinalTracks)
            self.isScanning = false
            self.scanStatusText = nil
            if self.hasPendingScan {
                self.hasPendingScan = false
                self.rescanAllFolders()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Track Management & In-Memory Mutations
    // -------------------------------------------------------------------------
    public func updateTrack(track: Track) {
        if let idx = tracks.firstIndex(where: { $0.fullPath == track.fullPath }) {
            tracks[idx] = track
            recomputeStats(with: tracks)
        }

        // Commit metadata update to SQLite
        if let db = getDB() {
            let sql = """
            UPDATE local_library_tracks
            SET title = ?, artist = ?, album = ?, track_num = ?, year = ?, genre = ?
            WHERE full_path = ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (track.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (track.artist as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (track.album as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (track.trackNum as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (track.year as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (track.genre as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (track.fullPath as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }
    }

    public func deleteTrack(track: Track, moveToTrash: Bool = false) {
        tracks.removeAll(where: { $0.fullPath == track.fullPath })
        recomputeStats(with: tracks)

        if let db = getDB() {
            let sql = "DELETE FROM local_library_tracks WHERE full_path = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (track.fullPath as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }

        if moveToTrash {
            let url = URL(fileURLWithPath: track.fullPath)
            NSWorkspace.shared.recycle([url], completionHandler: nil)
        }
    }

    public func reInspectAllSenseMe() {
        let currentTracks = self.tracks
        guard !currentTracks.isEmpty else { return }

        guard let db = getDB() else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        let updateSql = """
        UPDATE local_library_tracks
        SET is_senseme = ?, senseme_bpm = ?, senseme_valence = ?, senseme_arousal = ?, senseme_channels = ?, senseme_highlight_sec = ?
        WHERE full_path = ?;
        """
        var updateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK {
            var updatedList = currentTracks
            var modified = false
            for i in 0..<updatedList.count {
                let tr = updatedList[i]
                let url = URL(fileURLWithPath: tr.fullPath)
                guard FileManager.default.fileExists(atPath: tr.fullPath) else { continue }
                let senseMe = SenseMeEngine.shared.inspect(fileURL: url)
                if senseMe.isAnalyzed != tr.isSenseMeAnalyzed || (senseMe.isAnalyzed && tr.senseMeChannels.isEmpty) {
                    updatedList[i].isSenseMeAnalyzed = senseMe.isAnalyzed
                    updatedList[i].senseMeBpm = senseMe.isAnalyzed ? senseMe.bpm : nil
                    updatedList[i].senseMeValence = senseMe.isAnalyzed ? senseMe.valence : nil
                    updatedList[i].senseMeArousal = senseMe.isAnalyzed ? senseMe.arousal : nil
                    updatedList[i].senseMeChannels = senseMe.channels
                    updatedList[i].senseMeHighlightSec = senseMe.highlightSec > 0 ? senseMe.highlightSec : nil
                    modified = true

                    if let stmt = updateStmt {
                        sqlite3_bind_int(stmt, 1, senseMe.isAnalyzed ? 1 : 0)
                        sqlite3_bind_double(stmt, 2, senseMe.bpm)
                        sqlite3_bind_double(stmt, 3, senseMe.valence)
                        sqlite3_bind_double(stmt, 4, senseMe.arousal)
                        sqlite3_bind_text(stmt, 5, (senseMe.channels.joined(separator: ",") as NSString).utf8String, -1, nil)
                        sqlite3_bind_double(stmt, 6, senseMe.highlightSec)
                        sqlite3_bind_text(stmt, 7, (tr.fullPath as NSString).utf8String, -1, nil)
                        sqlite3_step(stmt)
                        sqlite3_reset(stmt)
                    }
                }
            }
            if let stmt = updateStmt { sqlite3_finalize(stmt) }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_close(db)
            if modified {
                self.tracks = updatedList
            }
        } else {
            sqlite3_close(db)
        }
    }

    public func analyzeLocalTracksWithSenseMe(forceReanalyzeAll: Bool = false, progressHandler: @escaping (Int, Int, String) -> Void) async {
        let targets = forceReanalyzeAll ? self.tracks : self.tracks.filter { !$0.isSenseMeAnalyzed }
        guard !targets.isEmpty else { return }

        let total = targets.count
        var updatedResults: [(String, SenseMeInfo)] = []

        let db = self.getDB()
        if let db = db {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        }
        let updateSql = """
        UPDATE local_library_tracks
        SET is_senseme = 1, senseme_bpm = ?, senseme_valence = ?, senseme_arousal = ?, senseme_channels = ?, senseme_highlight_sec = ?
        WHERE full_path = ?;
        """
        var updateStmt: OpaquePointer?
        if let db = db {
            _ = sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil)
        }

        for (idx, tr) in targets.enumerated() {
            let url = URL(fileURLWithPath: tr.fullPath)
            guard FileManager.default.fileExists(atPath: tr.fullPath) else { continue }
            progressHandler(idx + 1, total, tr.title)

            // High-speed on-board acoustic analysis
            let info = SenseMeEngine.shared.analyzeTrackOnBoard(fileURL: url, injectSMFM: true)
            if info.isAnalyzed {
                updatedResults.append((tr.fullPath, info))

                if let stmt = updateStmt {
                    sqlite3_bind_double(stmt, 1, info.bpm)
                    sqlite3_bind_double(stmt, 2, info.valence)
                    sqlite3_bind_double(stmt, 3, info.arousal)
                    sqlite3_bind_text(stmt, 4, (info.channels.joined(separator: ",") as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(stmt, 5, info.highlightSec)
                    sqlite3_bind_text(stmt, 6, (tr.fullPath as NSString).utf8String, -1, nil)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
            }
        }

        if let stmt = updateStmt { sqlite3_finalize(stmt) }
        if let db = db {
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            sqlite3_close(db)
        }

        let resultsToApply = updatedResults
        await MainActor.run {
            for (path, info) in resultsToApply {
                if let pos = self.tracks.firstIndex(where: { $0.fullPath == path }) {
                    self.tracks[pos].isSenseMeAnalyzed = true
                    self.tracks[pos].senseMeBpm = info.bpm
                    self.tracks[pos].senseMeValence = info.valence
                    self.tracks[pos].senseMeArousal = info.arousal
                    self.tracks[pos].senseMeChannels = info.channels
                    self.tracks[pos].senseMeHighlightSec = info.highlightSec > 0 ? info.highlightSec : nil
                }
            }
        }
    }
}
