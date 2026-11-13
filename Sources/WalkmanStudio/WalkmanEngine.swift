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

    private static let playlistTrimChars = CharacterSet(charactersIn: "/ \t\r\n")
    private static let playlistSlashChars = CharacterSet(charactersIn: "/")
    private static let volumesRootPattern = #"(?i)^volumes/[^/]+/(?:music|learning)/+"#

    /// Returns `true` when a stored relative track path still carries an unwanted root/volume prefix or leading `./` or `\`.
    public static func needsPathCanonicalization(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.contains("\\") || trimmed.hasPrefix("/") || trimmed.hasPrefix("./") {
            return true
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("music/") || lower.hasPrefix("learning/") {
            return true
        }
        return trimmed.range(of: volumesRootPattern, options: .regularExpression) != nil
    }

    /// Converts any playlist/library path (`Volumes/<Drive>/MUSIC/...`, `/Volumes/...`, `MUSIC/...`, `./...`, backslashes)
    /// into a Sony Walkman hardware-compliant forward-slash relative path anchored to the music/learning directory.
    public static func canonicalPlaylistRelativePath(_ rawPath: String, baseDirPath: String? = nil) -> String {
        var norm = rawPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: playlistTrimChars)
            .precomposedStringWithCanonicalMapping

        while norm.hasPrefix("./") {
            norm = String(norm.dropFirst(2)).trimmingCharacters(in: playlistSlashChars)
        }

        var strippedExplicitRoot = false
        if let baseDirPath = baseDirPath, !baseDirPath.isEmpty {
            let candidateBases = [
                baseDirPath,
                URL(fileURLWithPath: baseDirPath).resolvingSymlinksInPath().path
            ]
            for rawBase in candidateBases {
                let normBase = rawBase
                    .replacingOccurrences(of: "\\", with: "/")
                    .trimmingCharacters(in: playlistTrimChars)
                    .precomposedStringWithCanonicalMapping
                if !normBase.isEmpty,
                   let baseRange = norm.range(of: normBase + "/", options: [.anchored, .caseInsensitive]) {
                    norm = String(norm[baseRange.upperBound...]).trimmingCharacters(in: playlistSlashChars)
                    strippedExplicitRoot = true
                    break
                }
            }
        }

        while norm.hasPrefix("./") {
            norm = String(norm.dropFirst(2)).trimmingCharacters(in: playlistSlashChars)
        }

        if let volRange = norm.range(of: volumesRootPattern, options: .regularExpression) {
            norm = String(norm[volRange.upperBound...]).trimmingCharacters(in: playlistSlashChars)
            strippedExplicitRoot = true
        }

        if !strippedExplicitRoot {
            let lower = norm.lowercased()
            if lower.hasPrefix("music/") {
                norm = String(norm.dropFirst(6)).trimmingCharacters(in: playlistSlashChars)
            } else if lower.hasPrefix("learning/") {
                norm = String(norm.dropFirst(9)).trimmingCharacters(in: playlistSlashChars)
            }
        }

        return norm
    }

    /// Inspects actual directory entries at `mountURL` to preserve true on-disk casing (`MUSIC` vs `Music`) on case-insensitive FAT32/exFAT drives.
    public func resolvedMusicDirectory(at mountURL: URL, fallbackToRoot: Bool = false) -> String {
        if let entryNames = try? FileManager.default.contentsOfDirectory(atPath: mountURL.path) {
            let visibleNames = entryNames.filter { !$0.hasPrefix(".") }
            if let exactUpper = visibleNames.first(where: { $0 == "MUSIC" }) {
                return mountURL.appendingPathComponent(exactUpper).path
            }
            if let caseMatch = visibleNames.first(where: { $0.lowercased() == "music" }) {
                return mountURL.appendingPathComponent(caseMatch).path
            }
        }
        let upper = mountURL.appendingPathComponent("MUSIC")
        let title = mountURL.appendingPathComponent("Music")
        if FileManager.default.fileExists(atPath: upper.path) {
            return upper.path
        }
        if FileManager.default.fileExists(atPath: title.path) {
            return title.path
        }
        return fallbackToRoot ? mountURL.path : upper.path
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
            let norm = Self.canonicalPlaylistRelativePath(track, baseDirPath: musicDir.path)
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

            let posix = Self.canonicalPlaylistRelativePath(line)

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

    /// Reads raw playlist entries and checks if any broken `Volumes/...`, leading `/`, or `MUSIC/` entries
    /// resolve cleanly to an existing file on `baseDirURL`, returning normalized tracks and repair count.
    public func inspectPlaylistForPathRepairs(
        at url: URL,
        baseDirURL: URL
    ) -> (tracks: [String], repairedCount: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""
        guard !content.isEmpty else { return ([], 0) }

        var cleaned = content
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        let fm = FileManager.default
        var results: [String] = []
        var repairedCount = 0

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let normalizedLine = line.replacingOccurrences(of: "\\", with: "/").precomposedStringWithCanonicalMapping
            let candidate = Self.canonicalPlaylistRelativePath(normalizedLine, baseDirPath: baseDirURL.path)
            guard !candidate.isEmpty else { continue }

            if candidate != normalizedLine {
                let targetURL = baseDirURL.appendingPathComponent(candidate)
                if fm.fileExists(atPath: targetURL.path) {
                    repairedCount += 1
                    results.append(candidate)
                    continue
                }
            }
            results.append(candidate)
        }
        return (tracks: results, repairedCount: repairedCount)
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
        guard FileManager.default.fileExists(atPath: mountPoint) else {
            return ([], true)
        }

        var deleted: [String] = []

        // 1. Locate and run dot_clean -m with safety watchdog
        let dotCleanCandidates = ["/usr/sbin/dot_clean", "/usr/bin/dot_clean"]
        if let dotCleanPath = dotCleanCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: dotCleanPath)
            process.arguments = ["-m", mountPoint]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                // 10-second safety watchdog: terminate if dot_clean hangs so eject is never blocked
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + 10.0)
                timer.setEventHandler { [weak process] in
                    if process?.isRunning == true {
                        process?.terminate()
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()
            } catch {
                // If dot_clean fails to launch, proceed to manual cleanup without blocking
            }
        }

        // 2. Remove remaining macOS shadow files and ._* metadata
        let targetNames: Set<String> = [".ds_store"]
        let targetDirs: Set<String> = [".spotlight-v100", ".trashes", ".fseventsd"]

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: mountPoint)

        if let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                let name = fileURL.lastPathComponent.lowercased()
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

                if isDir && targetDirs.contains(name) {
                    enumerator.skipDescendants()
                    try? fileManager.removeItem(at: fileURL)
                    deleted.append(fileURL.path)
                    continue
                }

                if targetNames.contains(name) || fileURL.lastPathComponent.hasPrefix("._") {
                    try? fileManager.removeItem(at: fileURL)
                    deleted.append(fileURL.path)
                }
            }
        }

        return (deleted, true)
    }

    public func unmountDrive(mountPoint: String) async -> (success: Bool, message: String) {
        guard FileManager.default.fileExists(atPath: mountPoint) else {
            return (true, "Volume already unmounted")
        }

        let volURL = URL(fileURLWithPath: mountPoint)

        // 1. Try native Cocoa NSWorkspace unmount & eject first (same as Finder Eject)
        var cocoaSucceeded = false
        var cocoaError: String = ""

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volURL)
            cocoaSucceeded = true
        } catch {
            cocoaError = error.localizedDescription
        }

        if cocoaSucceeded || !FileManager.default.fileExists(atPath: mountPoint) {
            return (true, "Volume successfully ejected by macOS")
        }

        // 2. Fallback to /usr/sbin/diskutil unmount with timeout
        let diskutilCandidates = ["/usr/sbin/diskutil", "/usr/bin/diskutil"]
        guard let diskutilPath = diskutilCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return (false, cocoaError.isEmpty ? "diskutil not found" : cocoaError)
        }

        func runDiskutil(arguments: [String], timeout: Double) -> (success: Bool, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskutilPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { [weak process] in
                    if process?.isRunning == true {
                        process?.terminate()
                    }
                }
                timer.resume()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()

                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (process.terminationStatus == 0, output)
            } catch {
                return (false, error.localizedDescription)
            }
        }

        let res1 = runDiskutil(arguments: ["unmount", mountPoint], timeout: 5.0)
        if res1.success || !FileManager.default.fileExists(atPath: mountPoint) {
            return (true, res1.output)
        }

        // 3. Fallback: Force unmount if normal unmount failed
        let res2 = runDiskutil(arguments: ["unmountDisk", "force", mountPoint], timeout: 5.0)
        let isNowGone = !FileManager.default.fileExists(atPath: mountPoint)
        return (res2.success || isNowGone, res2.output.isEmpty ? res1.output : res2.output)
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
            if customStorageURL?.path == drive.mountPoint {
                clearCustomStorage()
            }
        }
        return (allDeleted, results)
    }

    // -----------------------------------------------------------------------
    // Custom / Manual Storage Support (MTP & Android Bridges)
    // -----------------------------------------------------------------------
    public private(set) var customStorageURL: URL? = nil

    public func setCustomStorageFolder(url: URL) -> Bool {
        _ = url.startAccessingSecurityScopedResource()
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "walkman_custom_storage_bookmark")
            UserDefaults.standard.set(url.path, forKey: "walkman_custom_storage_path")
        }
        self.customStorageURL = url
        return true
    }

    public func clearCustomStorage() {
        if let url = customStorageURL {
            url.stopAccessingSecurityScopedResource()
        }
        customStorageURL = nil
        UserDefaults.standard.removeObject(forKey: "walkman_custom_storage_bookmark")
        UserDefaults.standard.removeObject(forKey: "walkman_custom_storage_path")
    }

    public func restoreCustomStorageFromBookmarkIfNeeded() {
        guard customStorageURL == nil else { return }
        guard let bookmark = UserDefaults.standard.data(forKey: "walkman_custom_storage_bookmark") else { return }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            _ = url.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: url.path) {
                self.customStorageURL = url
            }
        }
    }

    public func makeCustomWalkmanDrive(from url: URL) -> WalkmanDrive {
        let connectedUsb = WalkmanUSBDetector.shared.connectedDevices.first(where: { $0.isAndroid })
        let driveName = connectedUsb != nil ? "\(connectedUsb!.modelName) Storage" : (url.lastPathComponent.isEmpty ? "Walkman Storage" : url.lastPathComponent)

        let path = url.path
        var statv = statvfs()
        var totalBytes: Int64 = 128_000_000_000 // Default 128GB (WM1AM2 size)
        var freeBytes: Int64 = 64_000_000_000

        if statvfs(path, &statv) == 0 && statv.f_frsize > 0 && statv.f_blocks > 0 {
            let blockSize = Int64(statv.f_frsize)
            totalBytes = blockSize * Int64(statv.f_blocks)
            freeBytes = blockSize * Int64(statv.f_bavail)
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path) {
            if let total = (attrs[.systemSize] as? NSNumber)?.int64Value, total > 0 {
                totalBytes = total
            }
            if let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value {
                freeBytes = free
            }
        }

        let usedBytes = max(0, totalBytes - freeBytes)
        let percentUsed = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0

        let musicDir = resolvedMusicDirectory(at: url, fallbackToRoot: true)

        return WalkmanDrive(
            name: driveName,
            mountPoint: url.path,
            type: .internal,
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            percentUsed: percentUsed,
            hasCfw: false,
            musicDir: musicDir
        )
    }

    // -----------------------------------------------------------------------
    // Drive Detection (Strict Supported Sony Walkman Verification)
    // -----------------------------------------------------------------------
    public func detectDrives() -> [WalkmanDrive] {
        var drives: [WalkmanDrive] = []
        lastUnsupportedModel = nil
        restoreCustomStorageFromBookmarkIfNeeded()

        let volumesURL = URL(fileURLWithPath: "/Volumes")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [
                .volumeIsReadOnlyKey,
                .volumeIsRemovableKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            if let customURL = customStorageURL, FileManager.default.fileExists(atPath: customURL.path) {
                return [makeCustomWalkmanDrive(from: customURL)]
            }
            return []
        }

        var rootStat = stat()
        stat("/", &rootStat)

        let systemVolumes: Set<String> = ["MACINTOSH HD", "RECOVERY", "PREBOOT", "VM", "UPDATE"]

        // Phase 1: Filter out system volumes, DMGs, non-FAT32/exFAT/FUSE, and read-only filesystems
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

            // Support FAT32 (msdos), ExFAT, FUSE/MTP virtual filesystems, and Sony Walkman volumes
            var sfs = statfs()
            guard statfs(path, &sfs) == 0 else { continue }
            let fstype = withUnsafePointer(to: &sfs.f_fstypename, {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0).lowercased() }
            })
            let isFatOrExfat = (fstype == "msdos" || fstype == "exfat")
            let isFuseOrVirtual = fstype.contains("fuse") || fstype.contains("macdroid") || fstype.contains("virtual") || fstype == "nullfs"
            let hasSonyWalkmanIndicator = FileManager.default.fileExists(atPath: volURL.appendingPathComponent("Android/data/com.sony.walkman").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("Android/data/com.sony.snei.walkman").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("Sony_Card.IND").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("DevIcon.fil").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("default-capability.xml").path)
                || FileManager.default.fileExists(atPath: volURL.appendingPathComponent("DEFAULT-CAPABILITY.XML").path)

            guard isFatOrExfat || isFuseOrVirtual || hasSonyWalkmanIndicator else {
                continue
            }

            // Must be writable (read-only DMGs, ISOs, and protected volumes are rejected)
            let res = try? volURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
            if res?.volumeIsReadOnly == true {
                continue
            }

            var statv = statvfs()
            _ = statvfs(path, &statv)
            let blockSize = Int64(statv.f_frsize)
            var totalBytes = blockSize * Int64(statv.f_blocks)
            if totalBytes <= 0 {
                if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                   let sysSize = attrs[.systemSize] as? NSNumber, sysSize.int64Value > 0 {
                    totalBytes = sysSize.int64Value
                } else if isFuseOrVirtual || hasSonyWalkmanIndicator {
                    totalBytes = 128_000_000_000 // Sensible default for MTP virtual drives
                }
            }
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

        // Phase 3: Check for companion MicroSD cards when an authentic internal Walkman is mounted
        // Standalone MicroSD cards must pass Phase 2 inspection with authentic Sony signatures
        if !internalCandidates.isEmpty {
            for cand in candidates {
                let upperName = cand.name.uppercased()
                let isSdNamed = upperName == "SD_CARD" || upperName.contains("SD_CARD") || upperName.contains("MEMORY_CARD") || upperName.contains("SONY_CARD")
                let hasMusic = FileManager.default.fileExists(atPath: cand.url.appendingPathComponent("MUSIC").path)
                    || FileManager.default.fileExists(atPath: cand.url.appendingPathComponent("Music").path)
                
                let alreadyInternal = internalCandidates.contains(where: { $0.path == cand.path })
                let alreadySd = microsdCandidates.contains(where: { $0.path == cand.path })
                
                if isSdNamed && hasMusic && !alreadyInternal && !alreadySd {
                    microsdCandidates.append(cand)
                }
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

            let musicPath = resolvedMusicDirectory(at: cand.url, fallbackToRoot: false)

            return WalkmanDrive(
                name: displayName,
                mountPoint: cand.path,
                type: type,
                totalBytes: totalBytes,
                usedBytes: usedBytes,
                freeBytes: freeBytes,
                percentUsed: percentUsed,
                hasCfw: cfwExists,
                musicDir: musicPath
            )
        }

        for intDrive in internalCandidates {
            drives.append(makeDrive(cand: intDrive, type: .internal))
        }

        for sdDrive in microsdCandidates {
            drives.append(makeDrive(cand: sdDrive, type: .microsd))
        }

        // Phase 5: Append custom/manual storage if user connected an MTP folder and it isn't already listed
        if let customURL = customStorageURL, FileManager.default.fileExists(atPath: customURL.path) {
            if !drives.contains(where: { $0.mountPoint == customURL.path }) {
                drives.append(makeCustomWalkmanDrive(from: customURL))
            }
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
    /// 1. Walkman NW-A45/A55/A50/A30 requires chronological [mm:ss.xx] timestamps to unlock and display lyrics in the lyrics viewer.
    ///    If plain text lyrics are provided, timestamps are synthesized sequentially across the song's duration.
    /// 2. Enforces standard CRLF (\r\n) line endings, UTF-8 without BOM, strict [mm:ss.xx] timestamps, BMP sanitization, and chronological order.
    public func writeCompanionLyrics(
        destinationAudioURL: URL,
        lyrics: String,
        durationSeconds: Double = 0,
        offsetSeconds: Double = 0.0,
        synthesizePlainTimestamps: Bool = true
    ) throws {
        let lrcURL = destinationAudioURL.deletingPathExtension().appendingPathExtension("lrc")
        let formattedLyrics = prepareWalkmanLRC(
            lyrics: lyrics,
            durationSeconds: durationSeconds,
            offsetSeconds: offsetSeconds,
            synthesizePlainTimestamps: synthesizePlainTimestamps
        )
        guard !formattedLyrics.isEmpty else { return }

        do {
            try formattedLyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        } catch {
            // Non-atomic fallback for external FAT32/exFAT Walkman volumes
            try formattedLyrics.write(to: lrcURL, atomically: false, encoding: .utf8)
        }

        let cPath = (lrcURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        let dotfileURL = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()
    }

    /// Prepares lyrics text for Sony Walkman: ensures every line has [mm:ss.xx] timestamps, CRLF endings,
    /// chronological ordering, strips incompatible headers, removes BOM and emojis/non-BMP chars, and adjusts for any global offset.
    public func prepareWalkmanLRC(
        lyrics: String,
        durationSeconds: Double = 0,
        offsetSeconds: Double = 0.0,
        synthesizePlainTimestamps: Bool = true
    ) -> String {
        // Strip BOM (\u{FEFF}) explicitly to prevent RTOS font parser corruption
        let cleanInput = lyrics.replacingOccurrences(of: "\u{FEFF}", with: "")
        let rawLines = cleanInput.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rawLines.isEmpty else { return "" }

        // 1. Check for global [offset:+/-ms] tag (e.g. [offset:500] or [offset:-200])
        var totalOffsetSeconds = offsetSeconds
        for line in rawLines {
            let lower = line.lowercased()
            if lower.hasPrefix("[offset:") {
                let inside = lower.dropFirst(8).replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                if let ms = Double(inside) {
                    totalOffsetSeconds += (ms / 1000.0)
                }
            }
        }

        // 2. Regex to match timestamp tag(s) like [mm:ss.xx], [m:ss.xxx], or [hh:mm:ss.xx]
        let timestampRegex = try? NSRegularExpression(
            pattern: "\\[(?:(\\d{1,3}):)?(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]",
            options: []
        )

        struct TimedLine {
            let timeSeconds: Double
            let formattedText: String
        }

        var timedLines: [TimedLine] = []
        var hasAnyTimestamps = false

        for line in rawLines {
            if line.isEmpty { continue }
            let lower = line.lowercased()
            // Skip non-lyric metadata headers that break or confuse Walkman RTOS parser
            if lower.hasPrefix("[ti:") || lower.hasPrefix("[ar:") ||
               lower.hasPrefix("[al:") || lower.hasPrefix("[by:") ||
               lower.hasPrefix("[offset:") || lower.hasPrefix("[length:") ||
               lower.hasPrefix("[re:") || lower.hasPrefix("[ve:") {
                continue
            }

            let nsLine = line as NSString
            let matches = timestampRegex?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? []

            if !matches.isEmpty {
                hasAnyTimestamps = true
                let rawText = timestampRegex?.stringByReplacingMatches(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length),
                    withTemplate: ""
                ) ?? ""

                let trimmedText = rawText.trimmingCharacters(in: .whitespaces)
                let sanitizedText = WalkmanEngine.sanitizeWalkmanText(trimmedText, stripExplicitMarkers: false)
                let textFormatted = sanitizedText.isEmpty ? "" : (rawText.hasPrefix(" ") ? " " + sanitizedText : sanitizedText)

                for match in matches {
                    var h = 0.0
                    var m = 0.0
                    var s = 0.0
                    var cs = 0.0

                    if match.range(at: 1).location != NSNotFound {
                        h = Double(nsLine.substring(with: match.range(at: 1))) ?? 0.0
                    }
                    if match.range(at: 2).location != NSNotFound {
                        m = Double(nsLine.substring(with: match.range(at: 2))) ?? 0.0
                    }
                    if match.range(at: 3).location != NSNotFound {
                        s = Double(nsLine.substring(with: match.range(at: 3))) ?? 0.0
                    }
                    if match.range(at: 4).location != NSNotFound {
                        let msStr = nsLine.substring(with: match.range(at: 4))
                        if msStr.count == 1 {
                            cs = (Double(msStr) ?? 0.0) * 10.0
                        } else if msStr.count == 2 {
                            cs = Double(msStr) ?? 0.0
                        } else if msStr.count >= 3 {
                            let prefix = String(msStr.prefix(2))
                            cs = Double(prefix) ?? 0.0
                        }
                    }

                    let totalSec = (h * 3600.0) + (m * 60.0) + s + (cs / 100.0)
                    let adjustedSec = max(0.0, totalSec + totalOffsetSeconds)
                    timedLines.append(TimedLine(timeSeconds: adjustedSec, formattedText: textFormatted))
                }
            }
        }

        if hasAnyTimestamps && !timedLines.isEmpty {
            // Sort chronologically as strictly required by Sony Walkman OS
            timedLines.sort { $0.timeSeconds < $1.timeSeconds }

            // Drop leading empty timestamp line (e.g. [00:00.00] with no text) which causes NW-A55 parser hang
            while let first = timedLines.first, first.formattedText.isEmpty {
                timedLines.removeFirst()
            }

            var formattedLines: [String] = []
            for item in timedLines {
                let totalS = Int(item.timeSeconds)
                let minutes = totalS / 60
                let seconds = totalS % 60
                let centis = Int(((item.timeSeconds - Double(totalS)) * 100.0).rounded())
                let lineStr = String(format: "[%02d:%02d.%02d]%@", minutes, seconds, min(99, max(0, centis)), item.formattedText)
                formattedLines.append(lineStr)
            }
            if !formattedLines.isEmpty {
                return formattedLines.joined(separator: "\r\n") + "\r\n"
            }
        }

        // Plain text lyrics: sanitize and synthesize sequential timestamps for NW-A55 display compatibility
        let nonEmptyLines = rawLines.compactMap { line -> String? in
            let clean = WalkmanEngine.sanitizeWalkmanText(line, stripExplicitMarkers: false)
            return clean.isEmpty ? nil : clean
        }
        guard !nonEmptyLines.isEmpty else { return "" }

        if !synthesizePlainTimestamps {
            return nonEmptyLines.joined(separator: "\r\n") + "\r\n"
        }

        let effectiveDuration = durationSeconds > 10.0 ? durationSeconds : Double(max(60, nonEmptyLines.count * 4))
        let startSec: Double = 2.5
        let endSec: Double = max(startSec + 2.0, effectiveDuration - 3.0)
        let step: Double = (endSec - startSec) / Double(max(1, nonEmptyLines.count))

        var timedLinesOut: [String] = []
        for (i, line) in nonEmptyLines.enumerated() {
            let t = startSec + Double(i) * step
            let totalS = Int(t)
            let m = totalS / 60
            let s = totalS % 60
            let cs = Int(((t - Double(totalS)) * 100.0).rounded())
            timedLinesOut.append(String(format: "[%02d:%02d.%02d]%@", m, s, min(99, max(0, cs)), line))
        }

        return timedLinesOut.joined(separator: "\r\n") + "\r\n"
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
