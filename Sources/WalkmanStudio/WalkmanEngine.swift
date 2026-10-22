import Foundation
import CoreGraphics
import ImageIO
import AppKit

public final class WalkmanEngine: @unchecked Sendable {
    public static let shared = WalkmanEngine()

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

    // -----------------------------------------------------------------------
    // Drive Detection (Exact Darwin statvfs)
    // -----------------------------------------------------------------------
    public func detectDrives() -> [WalkmanDrive] {
        var drives: [WalkmanDrive] = []
        let volumesURL = URL(fileURLWithPath: "/Volumes")

        guard let contents = try? FileManager.default.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var rootStat = stat()
        stat("/", &rootStat)

        let systemVolumes: Set<String> = ["MACINTOSH HD", "RECOVERY", "PREBOOT", "VM", "UPDATE"]
        let candidates = contents.filter { url in
            let name = url.lastPathComponent.uppercased()
            return !systemVolumes.contains(name) && !name.hasSuffix(".DMG")
        }

        let hasInternal = candidates.contains { url in
            let n = url.lastPathComponent.uppercased()
            return n.contains("WALKMAN") && !n.contains("SD")
        }

        for volURL in candidates {
            let path = volURL.path
            
            // Verify this path is a distinct mounted filesystem and not a lingering folder on the root disk
            var volStat = stat()
            if stat(path, &volStat) != 0 || volStat.st_dev == rootStat.st_dev {
                continue
            }

            let volName = volURL.lastPathComponent.uppercased()

            let isInternal = volName.contains("WALKMAN") && (!volName.contains("SD") && !volName.contains("MICROSD"))
            let sonyCardExists = FileManager.default.fileExists(atPath: volURL.appendingPathComponent("Sony_Card.IND").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("SONY_CARD.IND").path)
                || (volName.contains("SD") && volName.contains("CARD"))
            let musicExists = FileManager.default.fileExists(atPath: volURL.appendingPathComponent("MUSIC").path)
            let cfwExists = FileManager.default.fileExists(atPath: volURL.appendingPathComponent("CFW").path)

            let isSecondarySD = hasInternal && !isInternal

            if isInternal || musicExists || cfwExists || sonyCardExists || isSecondarySD {
                var stat = statvfs()
                if statvfs(path, &stat) == 0 {
                    let blockSize = Int64(stat.f_frsize)
                    let totalBytes = blockSize * Int64(stat.f_blocks)
                    guard totalBytes > 0 else { continue }
                    
                    let freeBytes = blockSize * Int64(stat.f_bavail)
                    let usedBytes = totalBytes - freeBytes
                    let percentUsed = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0

                    let displayName = isInternal ? volURL.lastPathComponent : "\(volURL.lastPathComponent) (MicroSD)"
                    let dType: DriveType = isInternal ? .internal : .microsd

                    drives.append(WalkmanDrive(
                        name: displayName,
                        mountPoint: path,
                        type: dType,
                        totalBytes: totalBytes,
                        usedBytes: usedBytes,
                        freeBytes: freeBytes,
                        percentUsed: percentUsed,
                        hasCfw: cfwExists,
                        musicDir: volURL.appendingPathComponent("MUSIC").path
                    ))
                }
            }
        }

        return drives.sorted { $0.type == .internal && $1.type != .internal }
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
            args.append(contentsOf: ["-c:a", "alac"])
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

    /// Saves companion .LRC lyrics file in the destination track folder alongside the audio file
    public func writeCompanionLyrics(destinationAudioURL: URL, lyrics: String) throws {
        let lrcURL = destinationAudioURL.deletingPathExtension().appendingPathExtension("lrc")
        try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        let cPath = (lrcURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        let dotfileURL = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()
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
}
