import Foundation
import CoreGraphics
import ImageIO
import AppKit

public final class WalkmanEngine: @unchecked Sendable {
    public static let shared = WalkmanEngine()

    public private(set) var lastUnsupportedModel: String? = nil

    private let ffmpegPath: String = {
        let homebrew = "/opt/homebrew/bin/ffmpeg"
        if FileManager.default.fileExists(atPath: homebrew) {
            return homebrew
        }
        return "/usr/local/bin/ffmpeg"
    }()

    private init() {}

    // -----------------------------------------------------------------------
    // Hardware Constraint 1: Baseline RGB JPEG Encoder
    // -----------------------------------------------------------------------
    public func encodeBaselineRGBJPEG(data: Data, maxDimension: CGFloat = 800) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let origWidth = CGFloat(cgImage.width)
        let origHeight = CGFloat(cgImage.height)

        var newWidth = origWidth
        var newHeight = origHeight

        if origWidth > maxDimension || origHeight > maxDimension {
            let ratio = min(maxDimension / origWidth, maxDimension / origHeight)
            newWidth = (origWidth * ratio).rounded()
            newHeight = (origHeight * ratio).rounded()
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(newWidth),
            height: Int(newHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedCG = context.makeImage() else { return nil }

        let outputData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outputData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyJFIFIsProgressive: false
        ]

        CGImageDestinationAddImage(dest, resizedCG, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        return outputData as Data
    }

    public func isBaselineRGBJPEG(data: Data) -> (valid: Bool, message: String) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (false, "Not a valid image")
        }

        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let colorModel = props[kCGImagePropertyColorModel] as? String ?? ""

        if width > 800 || height > 800 {
            return (false, "Resolution \(width)x\(height) exceeds max 800x800")
        }
        if colorModel != (kCGImagePropertyColorModelRGB as String) {
            return (false, "Color mode is \(colorModel), must be RGB")
        }

        if let jfif = props[kCGImagePropertyJFIFDictionary] as? [CFString: Any],
           let isProg = jfif[kCGImagePropertyJFIFIsProgressive] as? Bool, isProg {
            return (false, "Image is Progressive JPEG (must be Baseline)")
        }

        return (true, "Valid Sony Walkman Baseline RGB JPEG")
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint 4: Sony Walkman Unicode & FAT32/exFAT Sanitization
    // -----------------------------------------------------------------------
    /// Sanitizes text for Sony Walkman hardware compatibility:
    /// 1. Strips non-BMP Unicode characters (code point > 0xFFFF, such as 4-byte UTF-8 emojis,
    ///    specifically the explicit badge '🅴' U+1F174, and all emojis) which cause the
    ///    Sony Walkman RTOS SQLite media scanner to fail and report the title as "Unknown".
    /// 2. Cleans explicit suffix tags like " [Explicit]", " (Explicit)", " [E]", " (E)" from titles
    ///    while preserving the actual song title.
    /// 3. Strips unprintable control characters and variation selectors.
    public static func sanitizeWalkmanText(_ text: String, stripExplicitMarkers: Bool = true) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            // Strip any character outside the Basic Multilingual Plane (scalar > 0xFFFF).
            // Sony Walkman firmware RTOS font and tag parser fails on 4-byte UTF-8 sequences.
            if scalar.value > 0xFFFF {
                continue
            }
            // Strip control characters (C0 and C1 controls)
            if scalar.value < 0x20 || (scalar.value >= 0x7F && scalar.value <= 0x9F) {
                continue
            }
            // Strip variation selectors (U+FE00...U+FE0F)
            if scalar.value >= 0xFE00 && scalar.value <= 0xFE0F {
                continue
            }
            result.unicodeScalars.append(scalar)
        }

        var clean = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if stripExplicitMarkers {
            // Remove common explicit markers like "[Explicit]", "(Explicit)", "[E]", "(E)", "[Explicit Content]"
            clean = clean.replacingOccurrences(
                of: #"\s*[\(\[]\s*(explicit(\s*content)?|e)\s*[\)\]]"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func sanitizeFilename(_ name: String, maxLength: Int = 120) -> String {
        // Strip non-BMP emojis (including '🅴') and explicit badges first
        var clean = Self.sanitizeWalkmanText(name, stripExplicitMarkers: true)
        let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*\0\u{001F}")
        clean = clean.components(separatedBy: illegal).joined(separator: "")
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if clean.isEmpty {
            clean = "Unknown"
        }
        if clean.count > maxLength {
            clean = String(clean.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        return clean
    }

    public func targetTrackURL(musicRoot: URL, artist: String, album: String, trackNum: String, title: String, ext: String) -> URL {
        let cleanArtist = sanitizeFilename(artist)
        let cleanAlbum = sanitizeFilename(album)
        let cleanTitle = sanitizeFilename(title)

        let tInt = Int(trackNum.components(separatedBy: "/").first ?? "1") ?? 1
        let trackPrefix = String(format: "%02d", tInt)
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()

        let filename = "\(trackPrefix) - \(cleanTitle).\(cleanExt)"
        return musicRoot.appendingPathComponent(cleanArtist).appendingPathComponent(cleanAlbum).appendingPathComponent(filename)
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint 5: Playlist Format (.M3U8 with BOM & CRLF in /MUSIC/)
    // -----------------------------------------------------------------------
    public struct PlaylistTrackInfo {
        public let relativePath: String
        public let durationSeconds: Int?
        public let title: String?
        public let artist: String?
        
        public init(relativePath: String, durationSeconds: Int? = nil, title: String? = nil, artist: String? = nil) {
            self.relativePath = relativePath
            self.durationSeconds = durationSeconds
            self.title = title
            self.artist = artist
        }
    }

    public func writePlaylist(
        musicDir: URL,
        name: String,
        relativeTracks: [String],
        trackMetadataLookup: [String: (duration: Int, title: String, artist: String)] = [:]
    ) throws -> URL {
        var cleanName = sanitizeFilename(name)
        if !cleanName.lowercased().hasSuffix(".m3u8") && !cleanName.lowercased().hasSuffix(".m3u") {
            cleanName += ".m3u8"
        }
        let playlistURL = musicDir.appendingPathComponent(cleanName)

        var lines: [String] = ["#EXTM3U"]
        
        for track in relativeTracks {
            var norm = track.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\r\n"))
            while norm.hasPrefix("./") {
                norm = String(norm.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if norm.lowercased().hasPrefix("music/") {
                norm = String(norm.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else if norm.lowercased().hasPrefix("learning/") {
                norm = String(norm.dropFirst(9)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            norm = norm.precomposedStringWithCanonicalMapping
            if norm.isEmpty { continue }

            // Hardware Constraint 5: Sony Walkman NW-A55 Linux RTOS expects relative POSIX paths
            // using forward slashes (/) relative to the /MUSIC/ directory, never Windows backslashes (\).
            lines.append(norm)
        }

        // Hardware Constraint 5: Strict UTF-8 without BOM and CRLF (\r\n) line terminators
        let fullContent = lines.joined(separator: "\r\n") + "\r\n"

        guard let data = fullContent.data(using: .utf8) else {
            throw NSError(
                domain: "WalkmanEngine",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode playlist data as UTF-8."]
            )
        }

        // Direct write (atomically: false) to prevent temporary file rename lock failures on FAT32/exFAT
        try data.write(to: playlistURL, options: [])

        // 1. Force kernel buffer flush to physical flash storage via fsync
        let cPath = (playlistURL.path as NSString).fileSystemRepresentation
        let fd = open(cPath, O_RDWR)
        if fd >= 0 {
            fsync(fd)
            close(fd)
        }

        // 2. Remove macOS extended attributes to avoid ._<name> AppleDouble files on ExFAT/FAT32
        removexattr(cPath, "com.apple.TextEncoding", 0)

        // 3. Remove companion ._ AppleDouble shadow file if created
        let dotfileURL = playlistURL.deletingLastPathComponent().appendingPathComponent("._" + playlistURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)

        // 4. Force flash write-through sync
        sync()

        return playlistURL
    }

    public func readPlaylistDetailed(at url: URL) -> [PlaylistTrackInfo] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        let content: String
        if let s = String(data: data, encoding: .utf8) {
            content = s
        } else if let s = String(data: data, encoding: .utf16) {
            content = s
        } else if let s = String(data: data, encoding: .isoLatin1) {
            content = s
        } else if let s = String(data: data, encoding: .windowsCP1252) {
            content = s
        } else {
            return []
        }

        var cleaned = content
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        var results: [PlaylistTrackInfo] = []
        var lastExtInfDuration: Int? = nil
        var lastExtInfTitle: String? = nil
        var lastExtInfArtist: String? = nil

        let lines = cleaned.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                let rest = String(line.dropFirst(8))
                let commaParts = rest.components(separatedBy: ",")
                if let durStr = commaParts.first?.trimmingCharacters(in: .whitespaces), let dur = Int(durStr) {
                    lastExtInfDuration = dur > 0 ? dur : nil
                }
                if commaParts.count > 1 {
                    let desc = commaParts.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
                    if !desc.isEmpty {
                        if desc.contains(" - ") {
                            let artParts = desc.components(separatedBy: " - ")
                            lastExtInfArtist = artParts.first?.trimmingCharacters(in: .whitespaces)
                            lastExtInfTitle = artParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                        } else {
                            lastExtInfTitle = desc
                        }
                    }
                }
                continue
            }

            if line.hasPrefix("#") {
                continue
            }

            var posix = line.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\r\n"))
            while posix.hasPrefix("./") {
                posix = String(posix.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if posix.lowercased().hasPrefix("music/") {
                posix = String(posix.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            posix = posix.precomposedStringWithCanonicalMapping

            if !posix.isEmpty {
                results.append(PlaylistTrackInfo(
                    relativePath: posix,
                    durationSeconds: lastExtInfDuration,
                    title: lastExtInfTitle,
                    artist: lastExtInfArtist
                ))
            }

            lastExtInfDuration = nil
            lastExtInfTitle = nil
            lastExtInfArtist = nil
        }
        return results
    }

    public func readPlaylist(at url: URL) -> [String] {
        return readPlaylistDetailed(at: url).map(\.relativePath)
    }

    public func renamePlaylist(at url: URL, newName: String) throws -> URL {
        let cleanName = sanitizeFilename(newName)
        if cleanName.isEmpty || cleanName == "Unknown" {
            throw NSError(
                domain: "WalkmanEngine",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Playlist name cannot be empty."]
            )
        }

        var targetFilename = cleanName
        let ext = url.pathExtension.isEmpty ? "m3u8" : url.pathExtension
        if !targetFilename.lowercased().hasSuffix(".m3u8") && !targetFilename.lowercased().hasSuffix(".m3u") {
            targetFilename += ".\(ext)"
        }

        let musicDir = url.deletingLastPathComponent()
        let targetURL = musicDir.appendingPathComponent(targetFilename)

        if targetURL.path == url.path {
            return targetURL
        }

        if targetURL.path.lowercased() != url.path.lowercased() {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                throw NSError(
                    domain: "WalkmanEngine",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "A playlist named '\(targetFilename)' already exists."]
                )
            }
            try FileManager.default.moveItem(at: url, to: targetURL)
        } else {
            // Case-only rename on case-insensitive filesystems (FAT32/exFAT/APFS):
            // Use temporary file to safely perform case rename
            let tempURL = musicDir.appendingPathComponent(".tmp_rename_\(UUID().uuidString).\(ext)")
            try FileManager.default.moveItem(at: url, to: tempURL)
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
        }

        // 1. Remove companion ._ AppleDouble shadow file of old name if present
        let oldDot = url.deletingLastPathComponent().appendingPathComponent("._" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: oldDot)

        // 2. Remove macOS extended attributes on renamed file
        let cPath = (targetURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)

        // 3. Remove companion ._ AppleDouble shadow file of new name if created
        let newDot = targetURL.deletingLastPathComponent().appendingPathComponent("._" + targetURL.lastPathComponent)
        try? FileManager.default.removeItem(at: newDot)

        // 4. Flush buffers to physical flash storage
        sync()

        return targetURL
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint 6: macOS Ghost File Cleanup & Unmount
    // -----------------------------------------------------------------------
    public func cleanGhostFiles(mountPoint: String) async -> (deleted: [String], success: Bool) {
        var deleted: [String] = []

        // 1. Run dot_clean -m
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dot_clean")
        process.arguments = ["-m", mountPoint]
        try? process.run()
        process.waitUntilExit()

        // 2. Remove any remaining macOS shadow files
        let targetNames: Set<String> = [".ds_store"]
        let targetDirs: Set<String> = [".spotlight-v100", ".trashes", ".fseventsd"]

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: mountPoint)

        if let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: []) {
            while let fileURL = enumerator.nextObject() as? URL {
                let name = fileURL.lastPathComponent.lowercased()
                if targetNames.contains(name) || fileURL.lastPathComponent.hasPrefix("._") || targetDirs.contains(name) {
                    try? fileManager.removeItem(at: fileURL)
                    deleted.append(fileURL.path)
                }
            }
        }

        return (deleted, true)
    }

    public func unmountDrive(mountPoint: String) async -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["unmount", mountPoint]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return (true, output)
            } else {
                // Try diskutil unmountDisk force
                let p2 = Process()
                p2.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p2.arguments = ["unmountDisk", "force", mountPoint]
                try? p2.run()
                p2.waitUntilExit()
                return (p2.terminationStatus == 0, output)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    public func cleanAndEject(drives: [WalkmanDrive]) async -> (deleted: [String], unmountResults: [String: Bool]) {
        var allDeleted: [String] = []
        var results: [String: Bool] = [:]
        for drive in drives {
            let cleanResult = await cleanGhostFiles(mountPoint: drive.mountPoint)
            allDeleted.append(contentsOf: cleanResult.deleted)
            sync()
            let unmountResult = await unmountDrive(mountPoint: drive.mountPoint)
            results[drive.name] = unmountResult.success
        }
        return (allDeleted, results)
    }

    // -----------------------------------------------------------------------
    // Drive Detection (Strict Supported Sony Walkman Verification)
    // -----------------------------------------------------------------------
    public func detectDrives() -> [WalkmanDrive] {
        var drives: [WalkmanDrive] = []
        lastUnsupportedModel = nil
        let volumesURL = URL(fileURLWithPath: "/Volumes")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [
                .volumeIsReadOnlyKey,
                .volumeIsRemovableKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var rootStat = stat()
        stat("/", &rootStat)

        let systemVolumes: Set<String> = ["MACINTOSH HD", "RECOVERY", "PREBOOT", "VM", "UPDATE"]

        // Phase 1: Filter out system volumes, DMGs, non-FAT32/exFAT, and read-only filesystems
        var candidates: [(url: URL, path: String, name: String, statv: statvfs)] = []
        for volURL in contents {
            let name = volURL.lastPathComponent.uppercased()
            if systemVolumes.contains(name) || name.hasSuffix(".DMG") {
                continue
            }

            let path = volURL.path
            var volStat = stat()
            if stat(path, &volStat) != 0 || volStat.st_dev == rootStat.st_dev {
                continue
            }

            // Exclusively FAT32 (msdos) or ExFAT - Sony OS non-Android players never use HFS+/APFS/NTFS
            var sfs = statfs()
            guard statfs(path, &sfs) == 0 else { continue }
            let fstype = withUnsafePointer(to: &sfs.f_fstypename, {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0).lowercased() }
            })
            guard fstype == "msdos" || fstype == "exfat" else {
                continue
            }

            // Must be writable (read-only DMGs, ISOs, and protected volumes are rejected)
            let res = try? volURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
            if res?.volumeIsReadOnly == true {
                continue
            }

            var statv = statvfs()
            guard statvfs(path, &statv) == 0 else { continue }
            let blockSize = Int64(statv.f_frsize)
            let totalBytes = blockSize * Int64(statv.f_blocks)
            guard totalBytes > 0 else { continue }

            candidates.append((volURL, path, volURL.lastPathComponent, statv))
        }

        // Phase 2: Check each candidate against authentic Walkman hardware signatures
        var internalCandidates: [(url: URL, path: String, name: String, statv: statvfs)] = []
        var microsdCandidates: [(url: URL, path: String, name: String, statv: statvfs)] = []

        for cand in candidates {
            if let insp = WalkmanDeviceDetector.inspectVolume(at: cand.url), insp.isWalkman {
                guard insp.isSupported else {
                    lastUnsupportedModel = insp.modelRaw ?? "Unsupported Android Walkman"
                    continue
                }

                if insp.isInternal {
                    if !internalCandidates.contains(where: { $0.path == cand.path }) {
                        internalCandidates.append(cand)
                    }
                } else if insp.isMicroSD {
                    if !microsdCandidates.contains(where: { $0.path == cand.path }) {
                        microsdCandidates.append(cand)
                    }
                }
            }
        }

        // Phase 3: Check for companion MicroSD cards formatted as SD_CARD or MEMORY_CARD with a MUSIC/ directory
        for cand in candidates {
            let upperName = cand.name.uppercased()
            let isSdNamed = upperName == "SD_CARD" || upperName.contains("SD_CARD") || upperName.contains("MEMORY_CARD") || upperName.contains("SONY_CARD")
            let hasMusic = FileManager.default.fileExists(atPath: cand.url.appendingPathComponent("MUSIC").path)
            
            let alreadyInternal = internalCandidates.contains(where: { $0.path == cand.path })
            let alreadySd = microsdCandidates.contains(where: { $0.path == cand.path })
            
            if (isSdNamed && hasMusic) && !alreadyInternal && !alreadySd {
                microsdCandidates.append(cand)
            }
        }

        // Phase 4: Construct WalkmanDrive models for verified drives only
        func makeDrive(cand: (url: URL, path: String, name: String, statv: statvfs), type: DriveType) -> WalkmanDrive {
            let blockSize = Int64(cand.statv.f_frsize)
            let totalBytes = blockSize * Int64(cand.statv.f_blocks)
            let freeBytes = blockSize * Int64(cand.statv.f_bavail)
            let usedBytes = totalBytes - freeBytes
            let percentUsed = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0
            let cfwExists = FileManager.default.fileExists(atPath: cand.url.appendingPathComponent("CFW").path)
            
            let displayName: String
            if type == .internal {
                displayName = cand.name
            } else {
                displayName = cand.name.contains("(MicroSD)") ? cand.name : "\(cand.name) (MicroSD)"
            }

            return WalkmanDrive(
                name: displayName,
                mountPoint: cand.path,
                type: type,
                totalBytes: totalBytes,
                usedBytes: usedBytes,
                freeBytes: freeBytes,
                percentUsed: percentUsed,
                hasCfw: cfwExists,
                musicDir: cand.url.appendingPathComponent("MUSIC").path
            )
        }

        for intDrive in internalCandidates {
            drives.append(makeDrive(cand: intDrive, type: .internal))
        }

        for sdDrive in microsdCandidates {
            drives.append(makeDrive(cand: sdDrive, type: .microsd))
        }

        return drives
    }

    // -----------------------------------------------------------------------
    // FFmpeg Audio Transcoding
    // -----------------------------------------------------------------------
    public func transcodeAudio(
        sourceURL: URL,
        destinationURL: URL,
        preset: String,
        normalizeVolume: Bool = false
    ) async throws {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        var args = ["-y", "-i", sourceURL.path]
        switch preset {
        case "copy", "copy_optimize", "copy_raw":
            args.append(contentsOf: ["-c:a", "copy"])
        case "mp3_128":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", "128k", "-id3v2_version", "3"])
        case "mp3_192":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", "192k", "-id3v2_version", "3"])
        case "aac_128":
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "128k"])
        case "flac_16":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s16", "-ar", "44100"])
        case "flac_24_48":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s32", "-ar", "48000"])
        case "flac_24", "flac_24_96":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s32", "-ar", "96000"])
        case "flac_24_192":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s32", "-ar", "192000"])
        case "mp3_320":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", "320k", "-id3v2_version", "3"])
        case "mp3_256":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", "256k", "-id3v2_version", "3"])
        case "mp3_v0":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-q:a", "0", "-id3v2_version", "3"])
        case "aac_320":
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "320k"])
        case "aac_256":
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "256k"])
        case "alac_16":
            args.append(contentsOf: ["-c:a", "alac", "-sample_fmt", "s16p"])
        case "wav_16":
            args.append(contentsOf: ["-c:a", "pcm_s16le", "-ar", "44100"])
        default:
            args.append(contentsOf: ["-c:a", "flac"])
        }

        if normalizeVolume && preset != "copy" && preset != "copy_optimize" && preset != "copy_raw" {
            args.append(contentsOf: ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"])
        }

        args.append(contentsOf: ["-vn", destinationURL.path])

        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? "Unknown FFmpeg error"
            throw NSError(domain: "WalkmanEngine", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    // -----------------------------------------------------------------------
    // Format Helpers (Bytes & Duration)
    // -----------------------------------------------------------------------
    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    public static func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "0:00" }
        let s = Int(seconds)
        let m = s / 60
        let rem = s % 60
        return String(format: "%d:%02d", m, rem)
    }

    /// Saves companion .LRC lyrics file in the destination track folder alongside the audio file.
    /// Ensures compatibility with Sony Walkman firmware:
    /// 1. Walkman NW-A45/A55/A50/A30 requires chronological [mm:ss.xx] timestamps to unlock the "Display Lyrics" option.
    ///    If plain text lyrics are provided, timestamps are synthesized sequentially across the song's duration.
    /// 2. Enforces standard CRLF (\r\n) line endings and clean UTF-8 encoding.
    public func writeCompanionLyrics(destinationAudioURL: URL, lyrics: String, durationSeconds: Double = 0) throws {
        let lrcURL = destinationAudioURL.deletingPathExtension().appendingPathExtension("lrc")
        let formattedLyrics = prepareWalkmanLRC(lyrics: lyrics, durationSeconds: durationSeconds)
        try formattedLyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        let cPath = (lrcURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        let dotfileURL = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()
    }

    /// Prepares lyrics text for Sony Walkman: ensures every line has [mm:ss.xx] timestamps and CRLF endings.
    public func prepareWalkmanLRC(lyrics: String, durationSeconds: Double = 0) -> String {
        let rawLines = lyrics.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let hasAnyTimestamps = rawLines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return (trimmed.hasPrefix("[0") || trimmed.hasPrefix("[1") || trimmed.hasPrefix("[2") || trimmed.hasPrefix("[3")) && trimmed.contains(":")
        }

        if hasAnyTimestamps {
            // Already timestamped: normalize line endings to CRLF and filter out empty lines
            let cleanLines = rawLines.filter { !$0.isEmpty }
            return cleanLines.joined(separator: "\r\n") + "\r\n"
        }

        // Plain text lyrics: synthesize sequential timestamps so the Sony Walkman RTOS firmware
        // accepts the .lrc file and enables the "Display Lyrics" button instead of greying it out.
        let nonEmptyLines = rawLines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return "" }

        let effectiveDuration = durationSeconds > 10.0 ? durationSeconds : Double(max(60, nonEmptyLines.count * 4))
        let startSec: Double = 3.0
        let endSec: Double = max(startSec + 2.0, effectiveDuration - 3.0)
        let step: Double = (endSec - startSec) / Double(max(1, nonEmptyLines.count))

        var timedLines: [String] = []
        for (i, line) in nonEmptyLines.enumerated() {
            let t = startSec + Double(i) * step
            let m = Int(t) / 60
            let s = Int(t) % 60
            let cs = Int((t - Double(Int(t))) * 100)
            timedLines.append(String(format: "[%02d:%02d.%02d]%@", m, s, cs, line))
        }

        return timedLines.joined(separator: "\r\n") + "\r\n"
    }

    /// Saves folder.jpg and cover.jpg Baseline RGB JPEGs in the destination album directory
    public func writeAlbumFolderArtwork(albumDirectoryURL: URL, artworkData: Data) throws {
        guard let baselineJPEG = encodeBaselineRGBJPEG(data: artworkData, maxDimension: 800) else { return }
        let names = ["cover.jpg", "folder.jpg"]
        for name in names {
            let fileURL = albumDirectoryURL.appendingPathComponent(name)
            try? baselineJPEG.write(to: fileURL)
            let cPath = (fileURL.path as NSString).fileSystemRepresentation
            removexattr(cPath, "com.apple.TextEncoding", 0)
            let dotfileURL = albumDirectoryURL.appendingPathComponent("._" + name)
            try? FileManager.default.removeItem(at: dotfileURL)
        }
        sync()
    }

    // -----------------------------------------------------------------------
    // Track Deletion on Device (Without Confirmation)
    // -----------------------------------------------------------------------
    @discardableResult
    public func deleteTrackFile(atPath path: String) async -> Bool {
        let fileManager = FileManager.default
        let fileURL = URL(fileURLWithPath: path)
        var success = true
        
        // 1. Delete the primary audio file
        if fileManager.fileExists(atPath: path) {
            try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: path)
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                NSLog("[WalkmanEngine] Failed to delete audio file at \(path): \(error)")
                success = false
            }
        }
        
        // 2. Delete paired companion .lrc / .LRC lyrics file if present
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        if fileManager.fileExists(atPath: lrcURL.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: lrcURL.path)
            try? fileManager.removeItem(at: lrcURL)
        }
        let upperLrcURL = fileURL.deletingPathExtension().appendingPathExtension("LRC")
        if fileManager.fileExists(atPath: upperLrcURL.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: upperLrcURL.path)
            try? fileManager.removeItem(at: upperLrcURL)
        }
        
        // 3. Delete AppleDouble ._ ghost files created by macOS
        let audioDotfile = fileURL.deletingLastPathComponent().appendingPathComponent("._" + fileURL.lastPathComponent)
        try? fileManager.removeItem(at: audioDotfile)
        
        let lrcDotfile = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? fileManager.removeItem(at: lrcDotfile)
        
        // 4. Clean empty parent folders under /MUSIC/ (Album / Artist directories)
        var parent = fileURL.deletingLastPathComponent()
        while parent.path != "/" && parent.lastPathComponent.uppercased() != "MUSIC" && parent.path.uppercased().contains("/MUSIC/") {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: parent.path) else { break }
            let nonHidden = contents.filter { !$0.hasPrefix(".") && !$0.hasPrefix("._") }
            if nonHidden.isEmpty {
                for item in contents {
                    try? fileManager.removeItem(at: parent.appendingPathComponent(item))
                }
                try? fileManager.removeItem(at: parent)
                parent = parent.deletingLastPathComponent()
            } else {
                break
            }
        }
        
        sync()
        return success
    }

    // -----------------------------------------------------------------------
    // Album Deletion on Device (Without Confirmation)
    // -----------------------------------------------------------------------
    @discardableResult
    public func deleteAlbum(tracks albumTracks: [Track]) async -> Bool {
        guard !albumTracks.isEmpty else { return false }
        let fileManager = FileManager.default
        var allSuccess = true
        var affectedDirs = Set<URL>()
        
        for track in albumTracks {
            let path = track.fullPath
            let fileURL = URL(fileURLWithPath: path)
            affectedDirs.insert(fileURL.deletingLastPathComponent())
            
            // 1. Delete primary audio file
            if fileManager.fileExists(atPath: path) {
                try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: path)
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    NSLog("[WalkmanEngine] Failed to delete audio file at \(path): \(error)")
                    allSuccess = false
                }
            }
            
            // 2. Delete paired companion .lrc / .LRC lyrics file if present
            let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
            if fileManager.fileExists(atPath: lrcURL.path) {
                try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: lrcURL.path)
                try? fileManager.removeItem(at: lrcURL)
            }
            let upperLrcURL = fileURL.deletingPathExtension().appendingPathExtension("LRC")
            if fileManager.fileExists(atPath: upperLrcURL.path) {
                try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: upperLrcURL.path)
                try? fileManager.removeItem(at: upperLrcURL)
            }
            
            // 3. Delete AppleDouble ._ ghost files created by macOS
            let audioDotfile = fileURL.deletingLastPathComponent().appendingPathComponent("._" + fileURL.lastPathComponent)
            try? fileManager.removeItem(at: audioDotfile)
            
            let lrcDotfile = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
            try? fileManager.removeItem(at: lrcDotfile)
        }
        
        // 4. Clean up album folders and artwork if no other audio files remain in them
        let audioExts: Set<String> = ["flac", "mp3", "m4a", "alac", "wav", "aif", "aiff", "dsf", "dff", "ape", "wma"]
        for dir in affectedDirs {
            guard dir.path != "/" && dir.lastPathComponent.uppercased() != "MUSIC" && dir.path.uppercased().contains("/MUSIC/") else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            let remainingAudio = contents.filter { audioExts.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            if remainingAudio.isEmpty {
                // Remove folder artwork, ghost files, and the album directory itself
                try? fileManager.removeItem(at: dir)
                
                // Also check if parent Artist folder is now empty
                var parent = dir.deletingLastPathComponent()
                while parent.path != "/" && parent.lastPathComponent.uppercased() != "MUSIC" && parent.path.uppercased().contains("/MUSIC/") {
                    guard let parentContents = try? fileManager.contentsOfDirectory(atPath: parent.path) else { break }
                    let nonHidden = parentContents.filter { !$0.hasPrefix(".") && !$0.hasPrefix("._") }
                    if nonHidden.isEmpty {
                        for item in parentContents {
                            try? fileManager.removeItem(at: parent.appendingPathComponent(item))
                        }
                        try? fileManager.removeItem(at: parent)
                        parent = parent.deletingLastPathComponent()
                    } else {
                        break
                    }
                }
            }
        }
        
        sync()
        return allSuccess
    }
}
