import Foundation
import SQLite3

public final class LibraryScanner: @unchecked Sendable {
    public static let shared = LibraryScanner()
    private init() {}

    private let supportedExts: Set<String> = [
        "flac", "mp3", "m4a", "alac", "wav", "aif", "aiff", "dsf", "dff", "ape", "wma"
    ]

    private let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".walkman_library_cache.db").path
    }()

    private func getDB() -> OpaquePointer? {
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            return nil
        }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS tracks_cache (
                full_path TEXT PRIMARY KEY,
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
                date_added REAL
            );
            CREATE INDEX IF NOT EXISTS idx_cache_path ON tracks_cache(full_path);
        """, nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE tracks_cache ADD COLUMN date_added REAL DEFAULT 0;", nil, nil, nil)
        return db
    }

    public func scan(musicDir: URL) async -> (tracks: [Track], albums: [String], artists: [String]) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: musicDir.path) else {
                    continuation.resume(returning: ([], [], []))
                    return
                }

                var cachedTracks: [String: Track] = [:]
                var albumsSet = Set<String>()
                var artistsSet = Set<String>()

                // 1. Read existing cache from SQLite
                if let db = self.getDB() {
                    let query = """
                    SELECT full_path, mtime, size, format, title, artist, album, track_num, year, genre,
                           duration_seconds, bitrate_kbps, sample_rate, bits_per_sample, has_artwork, relative_path, date_added
                    FROM tracks_cache
                    WHERE full_path LIKE ?;
                    """
                    var stmt: OpaquePointer?
                    let searchPrefix = "\(musicDir.path)/%"
                    if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(stmt, 1, (searchPrefix as NSString).utf8String, -1, nil)
                        while sqlite3_step(stmt) == SQLITE_ROW {
                            let fPath = String(cString: sqlite3_column_text(stmt, 0))
                            let mtime = sqlite3_column_double(stmt, 1)
                            let size = sqlite3_column_int64(stmt, 2)
                            let fmt = String(cString: sqlite3_column_text(stmt, 3))
                            let title = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                            let artist = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "Unknown Artist"
                            let album = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "Unknown Album"
                            let trackNum = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
                            let year = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
                            let genre = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
                            let duration = sqlite3_column_double(stmt, 10)
                            let bitrate = Int(sqlite3_column_int(stmt, 11))
                            let sampleRate = Int(sqlite3_column_int(stmt, 12))
                            let bitsPerSample = Int(sqlite3_column_int(stmt, 13))
                            let hasArt = sqlite3_column_int(stmt, 14) != 0
                            let relPath = sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? URL(fileURLWithPath: fPath).lastPathComponent
                            let dateAddedSec = sqlite3_column_double(stmt, 16)
                            let effectiveAdded = dateAddedSec > 0 ? dateAddedSec : mtime
                            let dateAdded = Date(timeIntervalSince1970: effectiveAdded > 0 ? effectiveAdded : CFAbsoluteTimeGetCurrent() + 978307200.0)

                            let tr = Track(
                                filename: URL(fileURLWithPath: fPath).lastPathComponent,
                                relativePath: relPath,
                                fullPath: fPath,
                                format: fmt,
                                title: title.isEmpty ? URL(fileURLWithPath: fPath).deletingPathExtension().lastPathComponent : title,
                                artist: artist,
                                album: album,
                                trackNum: trackNum.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")),
                                year: year,
                                genre: genre,
                                durationSeconds: duration,
                                bitrateKbps: bitrate,
                                sampleRate: sampleRate,
                                bitsPerSample: bitsPerSample,
                                hasArtwork: hasArt,
                                sizeBytes: size,
                                dateAdded: dateAdded
                            )
                            cachedTracks[fPath] = tr
                        }
                        sqlite3_finalize(stmt)
                    }
                    sqlite3_close(db)
                }

                // 2. Quickly reconcile with directory entries
                var finalTracks: [Track] = []
                var pendingEnrichment: [(path: String, size: Int64, relPath: String, ext: String)] = []

                if let enumerator = fileManager.enumerator(
                    at: musicDir,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    options: [.skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        let filename = fileURL.lastPathComponent
                        if filename.hasPrefix("._") || filename.hasPrefix(".") { continue }

                        let ext = fileURL.pathExtension.lowercased()
                        guard self.supportedExts.contains(ext) else { continue }

                        let fullPath = fileURL.path
                        if let cached = cachedTracks[fullPath], cached.durationSeconds > 0 {
                            finalTracks.append(cached)
                            artistsSet.insert(cached.artist)
                            albumsSet.insert("\(cached.artist) - \(cached.album)")
                        } else {
                            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                            let relPath = fullPath.replacingOccurrences(of: musicDir.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            pendingEnrichment.append((fullPath, Int64(size), relPath, ext))
                        }
                    }
                }

                // 3. Fast-enrich any uncached files
                if !pendingEnrichment.isEmpty {
                    var newRows: [Track] = []
                    let db = self.getDB()
                    if let db = db {
                        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
                    }

                    let insertSql = """
                    INSERT OR REPLACE INTO tracks_cache
                    (full_path, mtime, size, format, title, artist, album, track_num, year, genre, duration_seconds, bitrate_kbps, sample_rate, bits_per_sample, has_artwork, relative_path, date_added)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    var insStmt: OpaquePointer?
                    if let db = db {
                        sqlite3_prepare_v2(db, insertSql, -1, &insStmt, nil)
                    }

                    for item in pendingEnrichment {
                        let parsed = self.parseAudioFile(path: item.path, size: item.size, ext: item.ext, relPath: item.relPath)
                        newRows.append(parsed)
                        artistsSet.insert(parsed.artist)
                        albumsSet.insert("\(parsed.artist) - \(parsed.album)")

                        if let insStmt = insStmt {
                            let pStr = (parsed.fullPath as NSString).utf8String
                            let fmtStr = (parsed.format as NSString).utf8String
                            let tStr = (parsed.title as NSString).utf8String
                            let aStr = (parsed.artist as NSString).utf8String
                            let alStr = (parsed.album as NSString).utf8String
                            let trkStr = (parsed.trackNum as NSString).utf8String
                            let yStr = (parsed.year as NSString).utf8String
                            let gStr = (parsed.genre as NSString).utf8String
                            let rStr = (parsed.relativePath as NSString).utf8String

                            sqlite3_bind_text(insStmt, 1, pStr, -1, nil)
                            sqlite3_bind_double(insStmt, 2, CFAbsoluteTimeGetCurrent())
                            sqlite3_bind_int64(insStmt, 3, parsed.sizeBytes)
                            sqlite3_bind_text(insStmt, 4, fmtStr, -1, nil)
                            sqlite3_bind_text(insStmt, 5, tStr, -1, nil)
                            sqlite3_bind_text(insStmt, 6, aStr, -1, nil)
                            sqlite3_bind_text(insStmt, 7, alStr, -1, nil)
                            sqlite3_bind_text(insStmt, 8, trkStr, -1, nil)
                            sqlite3_bind_text(insStmt, 9, yStr, -1, nil)
                            sqlite3_bind_text(insStmt, 10, gStr, -1, nil)
                            sqlite3_bind_double(insStmt, 11, parsed.durationSeconds)
                            sqlite3_bind_int(insStmt, 12, Int32(parsed.bitrateKbps))
                            sqlite3_bind_int(insStmt, 13, Int32(parsed.sampleRate))
                            sqlite3_bind_int(insStmt, 14, Int32(parsed.bitsPerSample))
                            sqlite3_bind_int(insStmt, 15, parsed.hasArtwork ? 1 : 0)
                            sqlite3_bind_text(insStmt, 16, rStr, -1, nil)
                            sqlite3_bind_double(insStmt, 17, parsed.dateAdded.timeIntervalSince1970)

                            sqlite3_step(insStmt)
                            sqlite3_reset(insStmt)
                        }
                    }

                    if let db = db {
                        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                        sqlite3_finalize(insStmt)
                        sqlite3_close(db)
                    }

                    finalTracks.append(contentsOf: newRows)
                }

                continuation.resume(returning: (
                    tracks: finalTracks,
                    albums: albumsSet.sorted(),
                    artists: artistsSet.sorted()
                ))
            }
        }
    }

    private func parseAudioFile(path: String, size: Int64, ext: String, relPath: String) -> Track {
        var s = stat()
        var dateAdded = Date()
        if stat(path, &s) == 0 {
            let btime = Double(s.st_birthtimespec.tv_sec)
            let mtime = Double(s.st_mtimespec.tv_sec)
            let chosen = btime > 0 ? btime : mtime
            if chosen > 0 {
                dateAdded = Date(timeIntervalSince1970: chosen)
            }
        }

        let parts = relPath.components(separatedBy: "/")
        var defArtist = "Unknown Artist"
        var defAlbum = "Unknown Album"

        if parts.count >= 3 {
            defArtist = parts[0]
            defAlbum = parts[1]
        } else if parts.count == 2 {
            defAlbum = parts[0]
        }

        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var defTitle = stem
        var defTrackNum = ""

        if let regex = try? NSRegularExpression(pattern: #"^(\d+)[\.\s\-_]+(.*)$"#, options: []),
           let match = regex.firstMatch(in: stem, range: NSRange(location: 0, length: stem.utf16.count)) {
            if let r1 = Range(match.range(at: 1), in: stem) {
                defTrackNum = String(stem[r1]).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                if defTrackNum.isEmpty { defTrackNum = "1" }
            }
            if let r2 = Range(match.range(at: 2), in: stem) {
                defTitle = String(stem[r2]).trimmingCharacters(in: .whitespaces)
            }
        }

        if ext == "flac", let info = parseFlacHeader(path: path, fileSize: size) {
            return Track(
                filename: URL(fileURLWithPath: path).lastPathComponent,
                relativePath: relPath,
                fullPath: path,
                format: "FLAC",
                title: info.title.isEmpty ? defTitle : info.title,
                artist: info.artist.isEmpty ? defArtist : info.artist,
                album: info.album.isEmpty ? defAlbum : info.album,
                trackNum: info.trackNum.isEmpty ? defTrackNum : info.trackNum,
                year: info.year,
                genre: info.genre,
                durationSeconds: info.durationSeconds,
                bitrateKbps: info.bitrateKbps,
                sampleRate: info.sampleRate,
                bitsPerSample: info.bitsPerSample,
                hasArtwork: info.hasArtwork,
                sizeBytes: size,
                dateAdded: dateAdded
            )
        }

        return Track(
            filename: URL(fileURLWithPath: path).lastPathComponent,
            relativePath: relPath,
            fullPath: path,
            format: ext.uppercased(),
            title: defTitle,
            artist: defArtist,
            album: defAlbum,
            trackNum: defTrackNum,
            year: "",
            genre: "",
            durationSeconds: 0,
            bitrateKbps: 0,
            sampleRate: 44100,
            bitsPerSample: 16,
            hasArtwork: true,
            sizeBytes: size,
            dateAdded: dateAdded
        )
    }

    private struct FlacHeaderInfo {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var trackNum: String = ""
        var year: String = ""
        var genre: String = ""
        var sampleRate: Int = 44100
        var bitsPerSample: Int = 16
        var durationSeconds: Double = 0
        var bitrateKbps: Int = 0
        var hasArtwork: Bool = false
    }

    private func parseFlacHeader(path: String, fileSize: Int64) -> FlacHeaderInfo? {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        var res = FlacHeaderInfo()
        var isLast = false

        while !isLast {
            guard let bh = try? handle.read(upToCount: 4), bh.count == 4 else { break }
            isLast = (bh[0] & 0x80) != 0
            let type = Int(bh[0] & 0x7F)
            let len = (Int(bh[1]) << 16) | (Int(bh[2]) << 8) | Int(bh[3])

            if type == 0 && len >= 34 { // STREAMINFO
                guard let d = try? handle.read(upToCount: len), d.count >= 34 else { break }
                let b10_17 = d.subdata(in: 10..<18)
                let raw = b10_17.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let sr = Int((raw >> 44) & 0xFFFFF)
                let bps = Int(((raw >> 36) & 0x1F) + 1)
                let samples = Int64(raw & 0xFFFFFFFFF)
                res.sampleRate = sr
                res.bitsPerSample = bps
                if sr > 0 {
                    res.durationSeconds = Double(samples) / Double(sr)
                    if res.durationSeconds > 0 {
                        res.bitrateKbps = Int((Double(fileSize) * 8.0) / (res.durationSeconds * 1000.0))
                    }
                }
            } else if type == 4 { // VORBIS_COMMENT
                guard let d = try? handle.read(upToCount: len), d.count == len else { break }
                var offset = 0
                if offset + 4 <= d.count {
                    let vLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                    offset += 4 + vLen
                    if offset + 4 <= d.count {
                        let count = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                        offset += 4
                        for _ in 0..<count {
                            guard offset + 4 <= d.count else { break }
                            let cLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                            offset += 4
                            guard offset + cLen <= d.count else { break }
                            if let s = String(data: d.subdata(in: offset..<offset+cLen), encoding: .utf8) {
                                let parts = s.components(separatedBy: "=")
                                if parts.count >= 2 {
                                    let k = parts[0].uppercased()
                                    let v = parts[1...].joined(separator: "=")
                                    if k == "TITLE" { res.title = v }
                                    else if k == "ARTIST" { res.artist = v }
                                    else if k == "ALBUM" { res.album = v }
                                    else if k == "TRACKNUMBER" || k == "TRACK" { res.trackNum = v }
                                    else if k == "DATE" || k == "YEAR" { res.year = String(v.prefix(4)) }
                                    else if k == "GENRE" { res.genre = v }
                                }
                            }
                            offset += cLen
                        }
                    }
                }
            } else if type == 6 { // PICTURE
                res.hasArtwork = true
                try? handle.seek(toOffset: handle.offsetInFile + UInt64(len))
            } else {
                try? handle.seek(toOffset: handle.offsetInFile + UInt64(len))
            }
        }
        return res
    }
}
