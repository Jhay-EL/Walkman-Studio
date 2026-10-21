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
    // Hardware Constraint 4: FAT32 / exFAT Sanitization
    // -----------------------------------------------------------------------
    public func sanitizeFilename(_ name: String, maxLength: Int = 120) -> String {
        var clean = name
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
    // Hardware Constraint 5: Playlist Format (.M3U8 with CRLF in /MUSIC/)
    // -----------------------------------------------------------------------
    public func writePlaylist(musicDir: URL, name: String, relativeTracks: [String]) throws -> URL {
        var cleanName = sanitizeFilename(name)
        if !cleanName.lowercased().hasSuffix(".m3u8") && !cleanName.lowercased().hasSuffix(".m3u") {
            cleanName += ".m3u8"
        }
        let playlistURL = musicDir.appendingPathComponent(cleanName)

        var lines = ["#EXTM3U"]
        for track in relativeTracks {
            let posix = track.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            lines.append(posix)
        }

        let content = lines.joined(separator: "\r\n") + "\r\n"
        try content.write(to: playlistURL, atomically: true, encoding: .utf8)
        
        // 1. Remove macOS extended attributes to avoid ._<name> AppleDouble files on ExFAT/FAT32
        let cPath = (playlistURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        
        // 2. Remove companion ._ AppleDouble shadow file if created
        let dotfileURL = playlistURL.deletingLastPathComponent().appendingPathComponent("._" + playlistURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        
        // 3. Force kernel buffer flush to physical flash storage
        sync()

        return playlistURL
    }

    public func readPlaylist(at url: URL) -> [String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
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
    public func transcodeAudio(sourceURL: URL, destinationURL: URL, preset: String) async throws {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        var args = ["-y", "-i", sourceURL.path]
        switch preset {
        case "copy":
            args.append(contentsOf: ["-c:a", "copy"])
        case "flac_16":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s16"])
        case "flac_24":
            args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s32"])
        case "mp3_320":
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", "320k"])
        default:
            args.append(contentsOf: ["-c:a", "flac"])
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
}
