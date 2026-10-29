import Foundation
import Combine
import AppKit
import CryptoKit

public struct DuplicateTrackItem: Identifiable, Hashable, Sendable {
    public var id: String { track.fullPath }
    public let track: Track
    public let driveName: String
    public let driveType: DriveType
    public let mountPoint: String

    public var isInternal: Bool { driveType == .internal }
    public var isMicroSD: Bool { driveType == .microsd }
    public var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }
}

public enum DuplicateMatchReason: String, CaseIterable, Identifiable, Sendable {
    case exactFile = "Exact File Match"
    case bitExactAudio = "Bit-Exact Audio (FLAC MD5)"
    case isrcMatch = "Official Master (ISRC Match)"
    case sameAlbum = "Same Album Copy"
    case strayCopy = "Untagged / Stray Copy"
    case crossDrive = "Cross-Drive Redundant"
    case crossAlbum = "Cross-Album Match"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .exactFile: return "doc.on.doc.fill"
        case .bitExactAudio: return "waveform.badge.checkmark"
        case .isrcMatch: return "seal.fill"
        case .sameAlbum: return "rectangle.stack.fill"
        case .strayCopy: return "folder.badge.questionmark"
        case .crossDrive: return "arrow.triangle.2.circlepath"
        case .crossAlbum: return "music.note.list"
        }
    }
}

public enum DuplicateDetectionScope: String, CaseIterable, Identifiable, Sendable {
    case exactSameAlbum = "Exact & Same Album"
    case crossAlbum = "Include Cross-Album"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .exactSameAlbum:
            return "Exact & Same Album"
        case .crossAlbum:
            return "Include Cross-Album"
        }
    }

    public var description: String {
        switch self {
        case .exactSameAlbum:
            return "Safe: Matches identical files, duplicate tracks within the same album, stray copies, and cross-drive redundant songs without breaking complete albums."
        case .crossAlbum:
            return "Loose: Matches identical song titles across different releases (Studio Albums, Singles, Greatest Hits, and Compilations). Deleting tracks may leave albums incomplete."
        }
    }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public var id: String // Unique match key
    public let title: String
    public let artist: String
    public let album: String
    public let matchReason: DuplicateMatchReason
    public var items: [DuplicateTrackItem]

    public var isCrossDrive: Bool {
        let drives = Set(items.map { $0.mountPoint })
        return drives.count > 1
    }

    public var hasQualityDifference: Bool {
        guard let first = items.first else { return false }
        let isFirstLossless = DuplicateFinderService.isLosslessFormat(first.track.format)

        return items.contains { item in
            let itemLossless = DuplicateFinderService.isLosslessFormat(item.track.format)

            // 1. Lossless vs Lossy discrepancy
            if itemLossless != isFirstLossless {
                return true
            }

            // 2. Both lossless: check bit depth and sample rate
            if itemLossless {
                return item.track.bitsPerSample != first.track.bitsPerSample ||
                       item.track.sampleRate != first.track.sampleRate
            }

            // 3. Both lossy: check format and bitrate discrepancy
            if item.track.format.uppercased() != first.track.format.uppercased() {
                return true
            }
            return abs(item.track.bitrateKbps - first.track.bitrateKbps) >= 48
        }
    }

    public var totalSizeBytes: Int64 {
        items.reduce(0) { $0 + $1.track.sizeBytes }
    }

    /// Highest quality / best recommended track to keep
    public var suggestedItemToKeep: DuplicateTrackItem? {
        items.max { a, b in
            let scoreA = qualityScore(for: a)
            let scoreB = qualityScore(for: b)
            if scoreA != scoreB {
                return scoreA < scoreB
            }
            // If quality is equal and this is a cross-drive duplicate, prefer MicroSD
            // to free up precious Internal Flash storage on the Walkman
            if a.isMicroSD && !b.isMicroSD {
                return false
            }
            if b.isMicroSD && !a.isMicroSD {
                return true
            }
            // Prefer item with complete metadata over "Unknown Album" or "Unknown Artist"
            let aHasMetadata = !a.track.album.isEmpty && a.track.album.lowercased() != "unknown album" && !a.track.artist.isEmpty && a.track.artist.lowercased() != "unknown artist"
            let bHasMetadata = !b.track.album.isEmpty && b.track.album.lowercased() != "unknown album" && !b.track.artist.isEmpty && b.track.artist.lowercased() != "unknown artist"
            if aHasMetadata != bHasMetadata {
                return !aHasMetadata && bHasMetadata
            }
            // Prefer clean filename without copy markers like (1), - Copy, - WORKSTATION-PC
            let aIsCopy = DuplicateFinderService.hasCopySuffix(a.track.filename)
            let bIsCopy = DuplicateFinderService.hasCopySuffix(b.track.filename)
            if aIsCopy != bIsCopy {
                return aIsCopy && !bIsCopy
            }
            // Prefer organized path over stray folder
            let aIsStray = a.track.fullPath.contains("Unknown Artist") || a.track.fullPath.contains("Unknown Album")
            let bIsStray = b.track.fullPath.contains("Unknown Artist") || b.track.fullPath.contains("Unknown Album")
            if aIsStray != bIsStray {
                return aIsStray && !bIsStray
            }
            // If on the same drive, prefer the one with cover artwork
            if a.track.hasArtwork != b.track.hasArtwork {
                return !a.track.hasArtwork && b.track.hasArtwork
            }
            return a.track.sizeBytes < b.track.sizeBytes
        }
    }

    /// Estimated recoverable bytes if keeping only the suggested item
    public var recoverableBytes: Int64 {
        guard let keep = suggestedItemToKeep else { return 0 }
        return max(0, totalSizeBytes - keep.track.sizeBytes)
    }

    private func qualityScore(for item: DuplicateTrackItem) -> Int {
        let t = item.track
        var score = 0
        let fmt = t.format.uppercased()

        if fmt == "DSF" || fmt == "DFF" {
            score += 7000
        } else if fmt == "FLAC" || fmt == "ALAC" || fmt == "WAV" || fmt == "AIFF" || fmt == "AIF" {
            score += 5000
        } else if fmt == "M4A" || fmt == "AAC" {
            score += 2000
        } else if fmt == "MP3" {
            score += 1000
        } else {
            score += 500
        }

        if t.bitsPerSample > 16 || t.sampleRate > 48000 {
            score += 3000 // Hi-Res Audio bonus
        }

        if DuplicateFinderService.isLosslessFormat(fmt) {
            score += (t.bitsPerSample * 10) + (t.sampleRate / 1000)
        } else {
            score += min(t.bitrateKbps, 500)
        }

        if t.hasArtwork { score += 100 }
        return score
    }
}

public enum DuplicateFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Duplicates"
    case crossDrive = "Cross-Drive (Internal vs SD)"
    case qualityDifference = "Quality Discrepancy"
    case sameDrive = "Same Storage"

    public var id: String { rawValue }
}

public final class DuplicateFinderService: ObservableObject, @unchecked Sendable {
    public static let shared = DuplicateFinderService()

    @Published public private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var totalRecoverableBytes: Int64 = 0
    @Published public private(set) var crossDriveCount: Int = 0
    @Published public private(set) var qualityDifferenceCount: Int = 0
    @Published public var detectionScope: DuplicateDetectionScope = .exactSameAlbum {
        didSet {
            if oldValue != detectionScope && !cachedTracks.isEmpty {
                recomputeGroups()
            }
        }
    }

    private var cachedTracks: [Track] = []
    private var cachedDrives: [WalkmanDrive] = []

    private init() {}

    public static func isLosslessFormat(_ fmt: String) -> Bool {
        let u = fmt.uppercased()
        return u == "FLAC" || u == "ALAC" || u == "WAV" || u == "AIFF" || u == "AIF" || u == "DSF" || u == "DFF" || u == "APE"
    }

    public static func hasCopySuffix(_ filename: String) -> Bool {
        let name = (filename as NSString).deletingPathExtension
        let patterns = [
            #"\s+\([1-9]\d{0,1}\)$"#,
            #"\s*-\s*copy.*$"#,
            #"\s+copy\s*\d*$"#,
            #"\s*-\s*[\w\-]+-pc.*$"#
        ]
        for pattern in patterns {
            if name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    public static func isUntaggedOrStray(_ track: Track) -> Bool {
        let alb = track.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let art = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if alb.isEmpty || alb == "unknown album" || alb == "unknown" { return true }
        if art.isEmpty || art == "unknown artist" || art == "unknown" { return true }
        if track.fullPath.contains("Unknown Artist") || track.fullPath.contains("Unknown Album") { return true }
        return false
    }

    /// Checks if a title is generic or ambiguous (e.g., "Track 1", "Audio", "Intro")
    public static func isGenericOrAmbiguousTitle(_ title: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 1 { return true }
        let genericNames = [
            "track", "audio", "untitled", "intro", "outro", "interlude",
            "voice", "recording", "bonus track", "soundtrack"
        ]
        if genericNames.contains(t) { return true }
        if t.range(of: #"^(?:track|audio|title|recording|voice)[\s\-_]*\d{1,3}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Computes a fast content fingerprint for candidate files with identical size.
    /// Reads up to 32KB from the start, 32KB from the middle, and 32KB from the end of the file.
    public static func fastContentFingerprint(at path: String, fileSize: Int64) -> String? {
        guard fileSize > 0 else { return nil }
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fileHandle.close() }

        let sampleSize = 32768 // 32 KB
        var hasher = SHA256()

        do {
            // 1. Start sample
            let startData = try fileHandle.read(upToCount: sampleSize) ?? Data()
            guard !startData.isEmpty else { return nil }
            hasher.update(data: startData)

            // 2. Middle sample
            if fileSize > Int64(sampleSize * 2) {
                let midOffset = (fileSize - Int64(sampleSize)) / 2
                try fileHandle.seek(toOffset: UInt64(midOffset))
                if let midData = try fileHandle.read(upToCount: sampleSize) {
                    hasher.update(data: midData)
                }
            }

            // 3. End sample
            if fileSize > Int64(sampleSize * 3) {
                let endOffset = fileSize - Int64(sampleSize)
                try fileHandle.seek(toOffset: UInt64(endOffset))
                if let endData = try fileHandle.read(upToCount: sampleSize) {
                    hasher.update(data: endData)
                }
            }

            let digest = hasher.finalize()
            return digest.map { String(format: "%02hhx", $0) }.joined()
        } catch {
            return nil
        }
    }

    /// Reads the 16-byte uncompressed audio stream MD5 from a FLAC file header (STREAMINFO block).
    /// Returns 32-character hex string if present and non-zero.
    public static func readFLACAudioStreamMD5(at path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }

        // Check "fLaC" magic (4 bytes)
        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        // Read first metadata block header (4 bytes)
        guard let blockHeader = try? handle.read(upToCount: 4), blockHeader.count == 4 else { return nil }
        let blockType = Int(blockHeader[0] & 0x7F)
        let blockLen = (Int(blockHeader[1]) << 16) | (Int(blockHeader[2]) << 8) | Int(blockHeader[3])

        // Block type 0 is STREAMINFO (must be >= 34 bytes)
        guard blockType == 0, blockLen >= 34 else { return nil }
        guard let streamInfo = try? handle.read(upToCount: blockLen), streamInfo.count >= 34 else { return nil }

        // MD5 of uncompressed audio stream is stored in bytes 18..<34
        let md5Data = streamInfo.subdata(in: 18..<34)
        guard md5Data.contains(where: { $0 != 0 }) else { return nil }

        return md5Data.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Reads the ISRC (International Standard Recording Code) tag from FLAC Vorbis Comments or MP3 ID3v2.
    public static func readFastISRC(at path: String, format: String) -> String? {
        let fmt = format.uppercased()
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }

        if fmt == "FLAC" {
            guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }
            var isLast = false
            while !isLast {
                guard let bh = try? handle.read(upToCount: 4), bh.count == 4 else { break }
                isLast = (bh[0] & 0x80) != 0
                let type = Int(bh[0] & 0x7F)
                let len = (Int(bh[1]) << 16) | (Int(bh[2]) << 8) | Int(bh[3])

                if type == 4 { // VORBIS_COMMENT
                    guard let d = try? handle.read(upToCount: min(len, 262144)), d.count >= 8 else { break }
                    var offset = 0
                    let vendorLen = Int(d[0]) | (Int(d[1]) << 8) | (Int(d[2]) << 16) | (Int(d[3]) << 24)
                    offset += 4 + vendorLen
                    guard offset + 4 <= d.count else { break }
                    let count = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                    offset += 4

                    for _ in 0..<min(count, 150) {
                        guard offset + 4 <= d.count else { break }
                        let cLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                        offset += 4
                        guard offset + cLen <= d.count else { break }
                        if let s = String(data: d.subdata(in: offset..<offset+cLen), encoding: .utf8) {
                            let upper = s.uppercased()
                            if upper.hasPrefix("ISRC=") {
                                let parts = s.components(separatedBy: "=")
                                if parts.count >= 2 {
                                    let val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                    if !val.isEmpty { return val }
                                }
                            }
                        }
                        offset += cLen
                    }
                    break
                } else {
                    guard len > 0 else { break }
                    // Advance handle
                    let cur = handle.offsetInFile
                    try? handle.seek(toOffset: cur + UInt64(len))
                }
            }
        } else if fmt == "MP3" {
            guard let hdr = try? handle.read(upToCount: 10), hdr.count == 10,
                  hdr[0] == 0x49, hdr[1] == 0x44, hdr[2] == 0x33 else { return nil }
            let tagSize = (Int(hdr[6]) << 21) | (Int(hdr[7]) << 14) | (Int(hdr[8]) << 7) | Int(hdr[9])
            guard let tagData = try? handle.read(upToCount: min(tagSize, 131072)) else { return nil }

            var offset = 0
            let flags = hdr[5]
            let version = hdr[3]
            if (flags & 0x40) != 0 && tagData.count >= 4 {
                let extSize = (Int(tagData[0]) << 21) | (Int(tagData[1]) << 14) | (Int(tagData[2]) << 7) | Int(tagData[3])
                offset = max(4, extSize)
            }

            while offset + 10 <= tagData.count {
                let idData = tagData.subdata(in: offset..<offset+4)
                guard let frameID = String(data: idData, encoding: .ascii) else { break }
                let fSize: Int
                if version == 4 {
                    fSize = (Int(tagData[offset+4]) << 21) | (Int(tagData[offset+5]) << 14) | (Int(tagData[offset+6]) << 7) | Int(tagData[offset+7])
                } else {
                    fSize = (Int(tagData[offset+4]) << 24) | (Int(tagData[offset+5]) << 16) | (Int(tagData[offset+6]) << 8) | Int(tagData[offset+7])
                }
                offset += 10
                guard fSize > 0 && offset + fSize <= tagData.count else { break }

                if frameID == "TSRC" {
                    let frameContent = tagData.subdata(in: offset..<offset+fSize)
                    if frameContent.count > 1 {
                        let payload = frameContent.subdata(in: 1..<frameContent.count)
                        let text = String(data: payload, encoding: .isoLatin1) ?? String(data: payload, encoding: .utf8)
                        let val = (text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\n\r")).uppercased()
                        if !val.isEmpty { return val }
                    }
                }
                offset += fSize
            }
        }
        return nil
    }

    /// Confirms acoustic correlation between candidate tracks using SenseMe analysis when available.
    public static func areAcousticallyCorrelated(trackA: Track, trackB: Track) -> Bool {
        if trackA.isSenseMeAnalyzed && trackB.isSenseMeAnalyzed {
            if let bpmA = trackA.senseMeBpm, let bpmB = trackB.senseMeBpm {
                if abs(bpmA - bpmB) > 1.2 {
                    return false
                }
            }
            if let valA = trackA.senseMeValence, let valB = trackB.senseMeValence {
                if abs(valA - valB) > 0.15 {
                    return false
                }
            }
            if let aroA = trackA.senseMeArousal, let aroB = trackB.senseMeArousal {
                if abs(aroA - aroB) > 0.15 {
                    return false
                }
            }
            if !trackA.senseMeChannels.isEmpty && !trackB.senseMeChannels.isEmpty {
                let setA = Set(trackA.senseMeChannels)
                let setB = Set(trackB.senseMeChannels)
                if setA.intersection(setB).isEmpty {
                    return false
                }
            }
        }
        return true
    }

    public static func cleanFilenameForMatching(_ filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        let patterns = [
            #"\s+\([1-9]\d{0,1}\)$"#,
            #"\s*-\s*copy.*$"#,
            #"\s+copy\s*\d*$"#,
            #"\s*-\s*[\w\-]+-pc.*$"#,
            #"^\d{1,3}[\s\.\-_]+\s*"#
        ]
        for pattern in patterns {
            base = base.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let filtered = base.unicodeScalars.filter { allowed.contains($0) }
        return String(filtered).lowercased().split(separator: " ").joined(separator: " ")
    }

    public static func extractVersionTag(from text: String) -> String? {
        let lower = text.lowercased()
        let keywords = [
            "live", "acoustic", "remix", "instrumental", "orchestral", "demo",
            "tayong lahat", "radio edit", "extended", "piano version", "unplugged"
        ]
        for kw in keywords {
            if lower.contains(kw) {
                return kw
            }
        }
        return nil
    }

    /// Re-evaluates duplicate groups in-memory using the current detection scope
    public func recomputeGroups() {
        guard !cachedTracks.isEmpty else { return }
        let tracks = cachedTracks
        let drives = cachedDrives
        let scope = detectionScope

        Task.detached(priority: .userInitiated) {
            let groups = Self.computeDuplicateGroups(tracks: tracks, drives: drives, scope: scope)
            let crossCount = groups.filter { $0.isCrossDrive }.count
            let qualityCount = groups.filter { $0.hasQualityDifference }.count
            let recoverable = groups.reduce(0) { $0 + $1.recoverableBytes }

            await MainActor.run {
                Self.shared.duplicateGroups = groups
                Self.shared.totalRecoverableBytes = recoverable
                Self.shared.crossDriveCount = crossCount
                Self.shared.qualityDifferenceCount = qualityCount
            }
        }
    }

    /// Scans all provided Walkman drives and detects duplicate tracks across and within drives.
    public func scanForDuplicates(drives: [WalkmanDrive]) async -> [DuplicateGroup] {
        await MainActor.run {
            self.isScanning = true
        }

        var scanDirs: [URL] = []
        for drive in drives {
            let musicURL = URL(fileURLWithPath: drive.musicDir)
            if FileManager.default.fileExists(atPath: musicURL.path) && !scanDirs.contains(musicURL) {
                scanDirs.append(musicURL)
            }
            let learningURL = URL(fileURLWithPath: drive.learningDir)
            if FileManager.default.fileExists(atPath: learningURL.path) && !scanDirs.contains(learningURL) {
                scanDirs.append(learningURL)
            }
        }

        var allTracks: [Track] = []
        var effectiveDrives = drives

        if !scanDirs.isEmpty {
            let result = await LibraryScanner.shared.scan(directories: scanDirs)
            allTracks.append(contentsOf: result.tracks)
        }

        // Include local library tracks and folders
        let localTracks = await MainActor.run { LocalMusicLibraryService.shared.tracks }
        let localFolders = await MainActor.run { LocalMusicLibraryService.shared.folders }
        for folder in localFolders {
            let pseudoDrive = WalkmanDrive.localLibrary(at: folder.url, name: folder.displayName)
            if !effectiveDrives.contains(where: { $0.mountPoint == pseudoDrive.mountPoint }) {
                effectiveDrives.append(pseudoDrive)
            }
        }
        for lt in localTracks {
            if !allTracks.contains(where: { $0.id == lt.id }) {
                allTracks.append(lt)
            }
        }

        guard !allTracks.isEmpty else {
            await MainActor.run {
                self.duplicateGroups = []
                self.cachedTracks = []
                self.cachedDrives = []
                self.totalRecoverableBytes = 0
                self.crossDriveCount = 0
                self.qualityDifferenceCount = 0
                self.isScanning = false
            }
            return []
        }

        let finalTracks = allTracks
        let finalDrives = effectiveDrives
        let currentScope = self.detectionScope

        // 2. Run duplicate clustering in background
        let groups = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            return Self.computeDuplicateGroups(tracks: finalTracks, drives: finalDrives, scope: currentScope)
        }.value

        let crossCount = groups.filter { $0.isCrossDrive }.count
        let qualityCount = groups.filter { $0.hasQualityDifference }.count
        let recoverable = groups.reduce(0) { $0 + $1.recoverableBytes }

        await MainActor.run {
            self.cachedTracks = finalTracks
            self.cachedDrives = finalDrives
            self.duplicateGroups = groups
            self.totalRecoverableBytes = recoverable
            self.crossDriveCount = crossCount
            self.qualityDifferenceCount = qualityCount
            self.isScanning = false
        }

        return groups
    }

    /// Pure function to cluster tracks into duplicate groups
    public static func computeDuplicateGroups(
        tracks: [Track],
        drives: [WalkmanDrive],
        scope: DuplicateDetectionScope = .exactSameAlbum
    ) -> [DuplicateGroup] {
        // Build drive lookup
        var driveMap: [String: WalkmanDrive] = [:]
        for drive in drives {
            driveMap[drive.mountPoint] = drive
        }

        func resolveDrive(for track: Track) -> (name: String, type: DriveType, mountPoint: String) {
            for drive in drives {
                if track.fullPath.hasPrefix(drive.mountPoint) {
                    return (drive.name, drive.type, drive.mountPoint)
                }
            }
            // Fallback inference from path
            if track.fullPath.localizedCaseInsensitiveContains("SD_CARD") || track.fullPath.localizedCaseInsensitiveContains("SDCARD") {
                return ("MicroSD Card", .microsd, "/Volumes/SD_CARD")
            }
            if track.fullPath.hasPrefix("/Volumes/") {
                return ("Internal Flash", .internal, "/Volumes/WALKMAN")
            }
            return ("Local Library", .local, (track.fullPath as NSString).deletingLastPathComponent)
        }

        func makeItem(_ track: Track) -> DuplicateTrackItem {
            let driveInfo = resolveDrive(for: track)
            return DuplicateTrackItem(
                track: track,
                driveName: driveInfo.name,
                driveType: driveInfo.type,
                mountPoint: driveInfo.mountPoint
            )
        }

        var assignedPaths = Set<String>()
        var results: [DuplicateGroup] = []

        var fingerprintCache: [String: String] = [:]
        var flacMd5Cache: [String: String] = [:]
        var isrcCache: [String: String] = [:]

        // MARK: - Phase 1a: Verified Exact File Match (Identical Size & Verified Content Hash on Same Drive)
        var sizeBuckets: [String: [Track]] = [:]
        for track in tracks {
            guard track.sizeBytes > 100_000, track.durationSeconds > 5.0 else { continue }
            let driveMount = resolveDrive(for: track).mountPoint
            let key = "\(driveMount)::\(track.sizeBytes)::\(track.format.uppercased())"
            sizeBuckets[key, default: []].append(track)
        }

        for (_, bucket) in sizeBuckets where bucket.count > 1 {
            var clusters: [[Track]] = []
            for track in bucket {
                let fp: String
                if let cached = fingerprintCache[track.fullPath] {
                    fp = cached
                } else if let computed = fastContentFingerprint(at: track.fullPath, fileSize: track.sizeBytes) {
                    fingerprintCache[track.fullPath] = computed
                    fp = computed
                } else {
                    continue
                }

                var placed = false
                for i in 0..<clusters.count {
                    let leader = clusters[i][0]
                    guard let leaderFp = fingerprintCache[leader.fullPath], leaderFp == fp else { continue }

                    // Safety Check 1: Titles must not conflict if both present
                    let tTrack = normalizeTitle(track.title)
                    let tLeader = normalizeTitle(leader.title)
                    if !tTrack.isEmpty && !tLeader.isEmpty && tTrack != tLeader {
                        continue
                    }

                    // Safety Check 2: Artists must not conflict if both present
                    let aTrack = normalizeArtist(track.artist)
                    let aLeader = normalizeArtist(leader.artist)
                    if !aTrack.isEmpty && !aLeader.isEmpty && aTrack != aLeader {
                        continue
                    }

                    clusters[i].append(track)
                    placed = true
                    break
                }
                if !placed {
                    clusters.append([track])
                }
            }

            for cluster in clusters where cluster.count > 1 {
                for tr in cluster { assignedPaths.insert(tr.fullPath) }
                let items = cluster.map { makeItem($0) }
                let first = cluster[0]
                let cleanTitle = first.title.isEmpty ? first.filename : first.title
                let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                let groupId = "exact::\(first.fullPath)::\(cluster.count)"
                results.append(DuplicateGroup(
                    id: groupId,
                    title: cleanTitle,
                    artist: cleanArtist,
                    album: first.album,
                    matchReason: .exactFile,
                    items: items
                ))
            }
        }

        // MARK: - Phase 1b: Bit-Exact Audio via FLAC STREAMINFO MD5 (Same Drive, Different Tags/Art)
        var flacMd5Buckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) && track.format.uppercased() == "FLAC" {
            guard track.durationSeconds > 5.0 else { continue }
            guard let md5 = flacMd5Cache[track.fullPath] ?? readFLACAudioStreamMD5(at: track.fullPath) else { continue }
            flacMd5Cache[track.fullPath] = md5
            let driveMount = resolveDrive(for: track).mountPoint
            flacMd5Buckets["\(driveMount)::\(md5)", default: []].append(track)
        }

        for (_, bucket) in flacMd5Buckets where bucket.count > 1 {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }
            for tr in unassigned { assignedPaths.insert(tr.fullPath) }
            let items = unassigned.map { makeItem($0) }
            let first = unassigned[0]
            let cleanTitle = first.title.isEmpty ? first.filename : first.title
            let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
            let groupId = "flac_md5::\(first.fullPath)::\(unassigned.count)"
            results.append(DuplicateGroup(
                id: groupId,
                title: cleanTitle,
                artist: cleanArtist,
                album: first.album,
                matchReason: .bitExactAudio,
                items: items
            ))
        }

        // MARK: - Phase 1c: Official Master Recording via ISRC (Same Drive)
        var isrcBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            guard track.durationSeconds > 5.0 else { continue }
            guard let isrc = isrcCache[track.fullPath] ?? readFastISRC(at: track.fullPath, format: track.format) else { continue }
            isrcCache[track.fullPath] = isrc
            let driveMount = resolveDrive(for: track).mountPoint
            isrcBuckets["\(driveMount)::\(isrc)", default: []].append(track)
        }

        for (_, bucket) in isrcBuckets where bucket.count > 1 {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }
            var clusters: [[Track]] = []
            for track in unassigned {
                var placed = false
                for i in 0..<clusters.count {
                    let leader = clusters[i][0]
                    if abs(track.durationSeconds - leader.durationSeconds) <= 1.5 {
                        clusters[i].append(track)
                        placed = true
                        break
                    }
                }
                if !placed { clusters.append([track]) }
            }
            for cluster in clusters where cluster.count > 1 {
                for tr in cluster { assignedPaths.insert(tr.fullPath) }
                let items = cluster.map { makeItem($0) }
                let first = cluster[0]
                let cleanTitle = first.title.isEmpty ? first.filename : first.title
                let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                let groupId = "isrc::\(first.fullPath)::\(cluster.count)"
                results.append(DuplicateGroup(
                    id: groupId,
                    title: cleanTitle,
                    artist: cleanArtist,
                    album: first.album,
                    matchReason: .isrcMatch,
                    items: items
                ))
            }
        }

        // MARK: - Phase 2: Cross-Drive Duplicates (Internal Flash vs MicroSD)
        var crossDriveTitleArtistBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
            let aKey = normalizeArtist(track.artist)
            guard !tKey.isEmpty else { continue }
            // Safety: Disallow cross-drive grouping for unknown artist or generic titles
            guard !aKey.isEmpty, !isGenericOrAmbiguousTitle(tKey) else { continue }
            crossDriveTitleArtistBuckets["\(tKey)::\(aKey)", default: []].append(track)
        }

        for (_, bucket) in crossDriveTitleArtistBuckets {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }

            let internalTracks = unassigned.filter { resolveDrive(for: $0).type == .internal }
            let sdTracks = unassigned.filter { resolveDrive(for: $0).type == .microsd }
            guard !internalTracks.isEmpty && !sdTracks.isEmpty else { continue }

            for intTrack in internalTracks {
                guard !assignedPaths.contains(intTrack.fullPath) else { continue }
                let intVer = extractVersionTag(from: "\(intTrack.title) \(intTrack.album) \(intTrack.fullPath)")

                let matches = sdTracks.filter { sdTrack in
                    guard !assignedPaths.contains(sdTrack.fullPath) else { return false }
                    let sdVer = extractVersionTag(from: "\(sdTrack.title) \(sdTrack.album) \(sdTrack.fullPath)")
                    guard intVer == sdVer else { return false }

                    // Tier 1a: FLAC Stream MD5 verification
                    var isConfirmedMatch = false
                    if intTrack.format.uppercased() == "FLAC" && sdTrack.format.uppercased() == "FLAC" {
                        let md5A = flacMd5Cache[intTrack.fullPath] ?? readFLACAudioStreamMD5(at: intTrack.fullPath)
                        let md5B = flacMd5Cache[sdTrack.fullPath] ?? readFLACAudioStreamMD5(at: sdTrack.fullPath)
                        if let a = md5A { flacMd5Cache[intTrack.fullPath] = a }
                        if let b = md5B { flacMd5Cache[sdTrack.fullPath] = b }
                        if let a = md5A, let b = md5B, a == b {
                            isConfirmedMatch = true
                        }
                    }

                    // Tier 1b: ISRC tag verification
                    if !isConfirmedMatch {
                        let isrcA = isrcCache[intTrack.fullPath] ?? readFastISRC(at: intTrack.fullPath, format: intTrack.format)
                        let isrcB = isrcCache[sdTrack.fullPath] ?? readFastISRC(at: sdTrack.fullPath, format: sdTrack.format)
                        if let a = isrcA { isrcCache[intTrack.fullPath] = a }
                        if let b = isrcB { isrcCache[sdTrack.fullPath] = b }
                        if let a = isrcA, let b = isrcB, !a.isEmpty, !b.isEmpty {
                            if a == b {
                                isConfirmedMatch = true
                            } else {
                                return false // Different official recordings
                            }
                        }
                    }

                    // In .exactSameAlbum mode, if audio hash / ISRC did not verify bit-exact identity,
                    // the tracks MUST belong to the same album release to prevent deleting studio tracks!
                    if !isConfirmedMatch && scope == .exactSameAlbum {
                        let albA = normalizeAlbum(intTrack.album)
                        let albB = normalizeAlbum(sdTrack.album)
                        guard !albA.isEmpty, !albB.isEmpty, albA == albB else { return false }
                    }

                    // Tier 2: Duration check
                    if intTrack.durationSeconds > 0 && sdTrack.durationSeconds > 0 {
                        guard abs(intTrack.durationSeconds - sdTrack.durationSeconds) <= 1.5 else { return false }
                    } else if !isConfirmedMatch {
                        return false // Disallow unverified duration-less matches
                    }

                    // Tier 2: SenseMe Acoustic Correlation
                    return areAcousticallyCorrelated(trackA: intTrack, trackB: sdTrack)
                }

                if !matches.isEmpty {
                    let cluster = [intTrack] + matches
                    for tr in cluster { assignedPaths.insert(tr.fullPath) }
                    let items = cluster.map { makeItem($0) }
                    let cleanTitle = intTrack.title.isEmpty ? intTrack.filename : intTrack.title
                    let cleanArtist = intTrack.primaryArtist.isEmpty ? "Unknown Artist" : intTrack.primaryArtist
                    let groupId = "cross::\(intTrack.fullPath)::\(cluster.count)"
                    results.append(DuplicateGroup(
                        id: groupId,
                        title: cleanTitle,
                        artist: cleanArtist,
                        album: intTrack.album,
                        matchReason: .crossDrive,
                        items: items
                    ))
                }
            }
        }

        // MARK: - Phase 3: Same-Drive, Same-Album Duplicates
        var sameAlbumBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            let albKey = normalizeAlbum(track.album)
            guard !albKey.isEmpty else { continue }
            let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
            let aKey = normalizeArtist(track.artist)
            guard !tKey.isEmpty else { continue }
            let driveMount = resolveDrive(for: track).mountPoint
            let key = "\(driveMount)::\(albKey)::\(aKey)::\(tKey)"
            sameAlbumBuckets[key, default: []].append(track)
        }

        for (_, bucket) in sameAlbumBuckets {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }

            var clusters: [[Track]] = []
            for track in unassigned {
                var placed = false
                let v1 = extractVersionTag(from: "\(track.title) \(track.album) \(track.fullPath)")
                for i in 0..<clusters.count {
                    let leader = clusters[i][0]

                    // Safety: If both tracks have distinct positive track numbers, they are different album tracks (e.g. Part 1 vs Part 2)!
                    let tNumA = Int(track.trackNum.components(separatedBy: "/").first ?? "")
                    let tNumLeader = Int(leader.trackNum.components(separatedBy: "/").first ?? "")
                    if let numA = tNumA, let numLeader = tNumLeader, numA > 0, numLeader > 0, numA != numLeader {
                        let aIsCopy = hasCopySuffix(track.filename)
                        let leaderIsCopy = hasCopySuffix(leader.filename)
                        let md5Match = (track.format.uppercased() == "FLAC" && leader.format.uppercased() == "FLAC" &&
                                        flacMd5Cache[track.fullPath] == flacMd5Cache[leader.fullPath] &&
                                        flacMd5Cache[track.fullPath] != nil)
                        guard aIsCopy || leaderIsCopy || md5Match else { continue }
                    }

                    let v2 = extractVersionTag(from: "\(leader.title) \(leader.album) \(leader.fullPath)")
                    guard v1 == v2 else { continue }

                    if track.durationSeconds <= 0 || leader.durationSeconds <= 0 ||
                       abs(track.durationSeconds - leader.durationSeconds) <= 2.0 {
                        if areAcousticallyCorrelated(trackA: track, trackB: leader) {
                            clusters[i].append(track)
                            placed = true
                            break
                        }
                    }
                }
                if !placed {
                    clusters.append([track])
                }
            }

            for cluster in clusters where cluster.count > 1 {
                for tr in cluster { assignedPaths.insert(tr.fullPath) }
                let items = cluster.map { makeItem($0) }
                let first = cluster[0]
                let cleanTitle = first.title.isEmpty ? first.filename : first.title
                let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                let groupId = "same_album::\(first.fullPath)::\(cluster.count)"
                results.append(DuplicateGroup(
                    id: groupId,
                    title: cleanTitle,
                    artist: cleanArtist,
                    album: first.album,
                    matchReason: .sameAlbum,
                    items: items
                ))
            }
        }

        // MARK: - Phase 4: Stray Untagged Copies vs Tagged Albums (Same Drive)
        var candidateStrayBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
            let aKey = normalizeArtist(track.artist)
            guard !tKey.isEmpty else { continue }
            let driveMount = resolveDrive(for: track).mountPoint
            candidateStrayBuckets["\(driveMount)::\(tKey)::\(aKey)", default: []].append(track)
        }

        for (_, bucket) in candidateStrayBuckets {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }

            let unknowns = unassigned.filter { isUntaggedOrStray($0) }
            let tagged = unassigned.filter { !isUntaggedOrStray($0) }
            guard !unknowns.isEmpty && !tagged.isEmpty else { continue }

            for u in unknowns {
                guard !assignedPaths.contains(u.fullPath) else { continue }
                let vU = extractVersionTag(from: "\(u.title) \(u.album) \(u.fullPath)")
                let matchingTagged = tagged.filter { t in
                    guard !assignedPaths.contains(t.fullPath) else { return false }
                    let vT = extractVersionTag(from: "\(t.title) \(t.album) \(t.fullPath)")
                    guard vU == vT else { return false }
                    if u.durationSeconds > 0 && t.durationSeconds > 0 {
                        guard abs(u.durationSeconds - t.durationSeconds) <= 1.5 else { return false }
                    }
                    return areAcousticallyCorrelated(trackA: u, trackB: t)
                }

                if !matchingTagged.isEmpty {
                    let cluster = [u] + matchingTagged
                    for tr in cluster { assignedPaths.insert(tr.fullPath) }
                    let items = cluster.map { makeItem($0) }
                    let leader = matchingTagged[0]
                    let cleanTitle = leader.title.isEmpty ? leader.filename : leader.title
                    let cleanArtist = leader.primaryArtist.isEmpty ? "Unknown Artist" : leader.primaryArtist
                    let groupId = "stray::\(leader.fullPath)::\(cluster.count)"
                    results.append(DuplicateGroup(
                        id: groupId,
                        title: cleanTitle,
                        artist: cleanArtist,
                        album: leader.album,
                        matchReason: .strayCopy,
                        items: items
                    ))
                }
            }
        }

        // MARK: - Phase 5: Normalized Filename Match (Copy Suffixes on Same Drive)
        var filenameBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            let fnKey = cleanFilenameForMatching(track.filename)
            // Safety: Disallow very short or generic filename stems from forming broad buckets
            guard !fnKey.isEmpty, fnKey.count > 2, !isGenericOrAmbiguousTitle(fnKey) else { continue }
            let driveMount = resolveDrive(for: track).mountPoint
            filenameBuckets["\(driveMount)::\(fnKey)", default: []].append(track)
        }

        for (_, bucket) in filenameBuckets {
            let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
            guard unassigned.count > 1 else { continue }

            let hasAnyCopySuffix = unassigned.contains { hasCopySuffix($0.filename) }
            if hasAnyCopySuffix {
                var clusters: [[Track]] = []
                for track in unassigned {
                    var placed = false
                    for i in 0..<clusters.count {
                        let leader = clusters[i][0]

                        // Safety check: titles must not conflict if both present
                        let tTrack = normalizeTitle(track.title)
                        let tLeader = normalizeTitle(leader.title)
                        if !tTrack.isEmpty && !tLeader.isEmpty && tTrack != tLeader {
                            continue
                        }

                        // Safety check: artists must not conflict if both present
                        let aTrack = normalizeArtist(track.artist)
                        let aLeader = normalizeArtist(leader.artist)
                        if !aTrack.isEmpty && !aLeader.isEmpty && aTrack != aLeader {
                            continue
                        }
                        if aTrack.isEmpty && aLeader.isEmpty && track.album != leader.album {
                            continue
                        }

                        // Durations must be valid and within 1.5 seconds
                        guard track.durationSeconds > 5.0 && leader.durationSeconds > 5.0 else { continue }
                        guard abs(track.durationSeconds - leader.durationSeconds) <= 1.5 else { continue }

                        clusters[i].append(track)
                        placed = true
                        break
                    }
                    if !placed {
                        clusters.append([track])
                    }
                }
                for cluster in clusters where cluster.count > 1 {
                    for tr in cluster { assignedPaths.insert(tr.fullPath) }
                    let items = cluster.map { makeItem($0) }
                    let first = cluster[0]
                    let cleanTitle = first.title.isEmpty ? first.filename : first.title
                    let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                    let groupId = "filename::\(first.fullPath)::\(cluster.count)"
                    results.append(DuplicateGroup(
                        id: groupId,
                        title: cleanTitle,
                        artist: cleanArtist,
                        album: first.album,
                        matchReason: .exactFile,
                        items: items
                    ))
                }
            }
        }

        // MARK: - Phase 6: Cross-Album Match (Only in .crossAlbum Scope)
        if scope == .crossAlbum {
            var crossAlbumBuckets: [String: [Track]] = [:]
            for track in tracks where !assignedPaths.contains(track.fullPath) {
                let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
                let aKey = normalizeArtist(track.artist)
                guard !tKey.isEmpty else { continue }
                if aKey.isEmpty && isGenericOrAmbiguousTitle(tKey) { continue }
                crossAlbumBuckets["\(tKey)::\(aKey)", default: []].append(track)
            }

            for (_, bucket) in crossAlbumBuckets {
                let unassigned = bucket.filter { !assignedPaths.contains($0.fullPath) }
                guard unassigned.count > 1 else { continue }

                var clusters: [[Track]] = []
                for track in unassigned {
                    var placed = false
                    let v1 = extractVersionTag(from: "\(track.title) \(track.album) \(track.fullPath)")
                    for i in 0..<clusters.count {
                        let leader = clusters[i][0]
                        let v2 = extractVersionTag(from: "\(leader.title) \(leader.album) \(leader.fullPath)")
                        guard v1 == v2 else { continue }

                        // Tier 1a: ISRC check
                        let isrcTrack = isrcCache[track.fullPath] ?? readFastISRC(at: track.fullPath, format: track.format)
                        let isrcLeader = isrcCache[leader.fullPath] ?? readFastISRC(at: leader.fullPath, format: leader.format)
                        if let a = isrcTrack { isrcCache[track.fullPath] = a }
                        if let b = isrcLeader { isrcCache[leader.fullPath] = b }
                        if let a = isrcTrack, let b = isrcLeader, !a.isEmpty, !b.isEmpty {
                            guard a == b else { continue } // Distinct master recordings
                        }

                        // Tier 1b: FLAC Audio Stream MD5 check
                        if track.format.uppercased() == "FLAC" && leader.format.uppercased() == "FLAC" {
                            let md5A = flacMd5Cache[track.fullPath] ?? readFLACAudioStreamMD5(at: track.fullPath)
                            let md5B = flacMd5Cache[leader.fullPath] ?? readFLACAudioStreamMD5(at: leader.fullPath)
                            if let a = md5A { flacMd5Cache[track.fullPath] = a }
                            if let b = md5B { flacMd5Cache[leader.fullPath] = b }
                            if let a = md5A, let b = md5B, a == b {
                                clusters[i].append(track)
                                placed = true
                                break
                            }
                        }

                        if track.durationSeconds <= 0 || leader.durationSeconds <= 0 ||
                           abs(track.durationSeconds - leader.durationSeconds) <= 2.0 {
                            if areAcousticallyCorrelated(trackA: track, trackB: leader) {
                                clusters[i].append(track)
                                placed = true
                                break
                            }
                        }
                    }
                    if !placed {
                        clusters.append([track])
                    }
                }

                for cluster in clusters where cluster.count > 1 {
                    for tr in cluster { assignedPaths.insert(tr.fullPath) }
                    let items = cluster.map { makeItem($0) }
                    let first = cluster[0]
                    let cleanTitle = first.title.isEmpty ? first.filename : first.title
                    let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                    let groupId = "cross_album::\(first.fullPath)::\(cluster.count)"
                    results.append(DuplicateGroup(
                        id: groupId,
                        title: cleanTitle,
                        artist: cleanArtist,
                        album: first.album,
                        matchReason: .crossAlbum,
                        items: items
                    ))
                }
            }
        }

        // Sort by recoverable space descending (largest savings first)
        results.sort { $0.recoverableBytes > $1.recoverableBytes }
        return results
    }

    /// Normalizes title string for duplicate matching
    public static func normalizeTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading track number e.g. "01 - ", "02. ", "1. ", "01 "
        if let match = s.range(of: #"^\d{1,3}[\s\.\-_]+\s*"#, options: .regularExpression) {
            s.removeSubrange(match)
        }
        // Strip common promotional/video boilerplate noise while PRESERVING distinct song versions
        // (like "Acoustic", "Live", "Remix", "Demo", "Instrumental")
        let noisePatterns = [
            #"\s*[\(\[]\s*official\s+(?:audio|video|music\s+video|lyric\s+video)\s*[\)\]]"#,
            #"\s*[\(\[]\s*lyric\s+video\s*[\)\]]"#,
            #"\s*[\(\[]\s*lyrics?\s*[\)\]]"#,
            #"\s*[\(\[]\s*audio\s*[\)\]]"#,
            #"\s*[\(\[]\s*(?:hd|hq|4k|1080p)\s*[\)\]]"#,
            #"\s*[\(\[]\s*remaster(?:ed)?(?:\s+\d{4})?\s*[\)\]]"#,
            #"\s*-\s*remaster(?:ed)?(?:\s+\d{4})?"#,
            #"\s*[\(\[]\s*(?:feat|ft)\.?\s+[^\)\]]+[\)\]]"#,
            #"\s*(?:feat|ft)\.?\s+.+$"#,
            #"\s*\(\d+\)$"#,
            #"\s*-\s*copy.*$"#,
            #"_\d+$"#,
            #"\s*-\s*[\w\-]+-pc.*$"#
        ]
        for pattern in noisePatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let filtered = s.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(filtered).lowercased()
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// Normalizes artist string for duplicate matching
    public static func normalizeArtist(_ raw: String) -> String {
        let primary = Track.parsePrimaryAndFeaturedArtist(from: raw).primary
        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let filtered = primary.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(filtered).lowercased()
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// Normalizes album string for duplicate matching
    public static func normalizeAlbum(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.lowercased() == "unknown album" || s.lowercased() == "unknown" {
            return ""
        }
        let noisePatterns = [
            #"\s*[\(\[]\s*deluxe(?:\s+edition|\s+version)?\s*[\)\]]"#,
            #"\s*[\(\[]\s*remaster(?:ed)?(?:\s+\d{4})?\s*[\)\]]"#,
            #"\s*-\s*remaster(?:ed)?(?:\s+\d{4})?"#
        ]
        for pattern in noisePatterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let filtered = s.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(filtered).lowercased()
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// Deletes a specific duplicate copy from the device
    public func deleteDuplicateItem(_ item: DuplicateTrackItem) async -> Bool {
        let path = item.track.fullPath

        // 1. Physical removal
        let success = await WalkmanEngine.shared.deleteTrackFile(atPath: path)
        LibraryScanner.shared.removeFromCache(fullPath: path)
        CoverArtCache.shared.invalidate(forFullPath: path, artist: item.track.primaryArtist, album: item.track.album)
        await MainActor.run {
            LocalMusicLibraryService.shared.deleteTrack(track: item.track, moveToTrash: false)
        }

        // 2. Remove from cachedTracks
        self.cachedTracks.removeAll(where: { $0.fullPath == path })

        // 3. Stop playback if this track is playing
        if AudioPlayerService.shared.currentTrack?.fullPath == path {
            AudioPlayerService.shared.stopAndClear()
        }

        // 4. Update in-memory state
        await MainActor.run {
            var updatedGroups: [DuplicateGroup] = []
            for var group in self.duplicateGroups {
                group.items.removeAll(where: { $0.track.fullPath == path })
                if group.items.count > 1 {
                    updatedGroups.append(group)
                }
            }
            self.duplicateGroups = updatedGroups
            self.totalRecoverableBytes = updatedGroups.reduce(0) { $0 + $1.recoverableBytes }
            self.crossDriveCount = updatedGroups.filter { $0.isCrossDrive }.count
            self.qualityDifferenceCount = updatedGroups.filter { $0.hasQualityDifference }.count
        }

        return success
    }

    /// Keeps a single chosen copy in a group and deletes all other duplicate copies
    public func keepOnly(item: DuplicateTrackItem, in group: DuplicateGroup) async {
        let itemsToDelete = group.items.filter { $0.track.fullPath != item.track.fullPath }
        for toDelete in itemsToDelete {
            _ = await deleteDuplicateItem(toDelete)
        }
    }
}
