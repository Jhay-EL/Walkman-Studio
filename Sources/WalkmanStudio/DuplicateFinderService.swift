import Foundation
import Combine
import AppKit

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
    case sameAlbum = "Same Album Copy"
    case strayCopy = "Untagged / Stray Copy"
    case crossDrive = "Cross-Drive Redundant"
    case crossAlbum = "Cross-Album Match"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .exactFile: return "doc.on.doc.fill"
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
            #"\s*\(\d+\)$"#,
            #"\s*-\s*copy.*$"#,
            #"_\d+$"#,
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

    public static func cleanFilenameForMatching(_ filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        let patterns = [
            #"\s*\(\d+\)$"#,
            #"\s*-\s*copy.*$"#,
            #"_\d+$"#,
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

        guard !scanDirs.isEmpty else {
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

        // 1. Scan/retrieve all tracks across all drives via LibraryScanner
        let result = await LibraryScanner.shared.scan(directories: scanDirs)
        let allTracks = result.tracks
        let currentScope = self.detectionScope

        // 2. Run duplicate clustering in background
        let groups = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            return Self.computeDuplicateGroups(tracks: allTracks, drives: drives, scope: currentScope)
        }.value

        let crossCount = groups.filter { $0.isCrossDrive }.count
        let qualityCount = groups.filter { $0.hasQualityDifference }.count
        let recoverable = groups.reduce(0) { $0 + $1.recoverableBytes }

        await MainActor.run {
            self.cachedTracks = allTracks
            self.cachedDrives = drives
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
            return ("Internal Flash", .internal, "/Volumes/WALKMAN")
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

        // MARK: - Phase 1: Exact File / Content Match (Identical Size & Duration on Same Drive)
        var sizeDurationBuckets: [String: [Track]] = [:]
        for track in tracks {
            guard track.sizeBytes > 100_000, track.durationSeconds > 5.0 else { continue }
            let driveMount = resolveDrive(for: track).mountPoint
            let roundedDur = Int((track.durationSeconds * 10).rounded())
            let key = "\(driveMount)::\(track.sizeBytes)::\(roundedDur)::\(track.format.uppercased())"
            sizeDurationBuckets[key, default: []].append(track)
        }

        for (_, bucket) in sizeDurationBuckets where bucket.count > 1 {
            let items = bucket.map { makeItem($0) }
            for tr in bucket { assignedPaths.insert(tr.fullPath) }
            let first = bucket[0]
            let cleanTitle = first.title.isEmpty ? first.filename : first.title
            let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
            let groupId = "exact::\(first.fullPath)::\(bucket.count)"
            results.append(DuplicateGroup(
                id: groupId,
                title: cleanTitle,
                artist: cleanArtist,
                album: first.album,
                matchReason: .exactFile,
                items: items
            ))
        }

        // MARK: - Phase 2: Cross-Drive Duplicates (Internal Flash vs MicroSD)
        var crossDriveTitleArtistBuckets: [String: [Track]] = [:]
        for track in tracks where !assignedPaths.contains(track.fullPath) {
            let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
            let aKey = normalizeArtist(track.artist)
            guard !tKey.isEmpty else { continue }
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

                    if intTrack.durationSeconds > 0 && sdTrack.durationSeconds > 0 {
                        return abs(intTrack.durationSeconds - sdTrack.durationSeconds) <= 1.5
                    }
                    return true
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
                    let v2 = extractVersionTag(from: "\(leader.title) \(leader.album) \(leader.fullPath)")
                    guard v1 == v2 else { continue }

                    if track.durationSeconds <= 0 || leader.durationSeconds <= 0 ||
                       abs(track.durationSeconds - leader.durationSeconds) <= 2.0 {
                        clusters[i].append(track)
                        placed = true
                        break
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
                        return abs(u.durationSeconds - t.durationSeconds) <= 1.5
                    }
                    return true
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
            guard !fnKey.isEmpty else { continue }
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
                        if track.durationSeconds <= 0 || leader.durationSeconds <= 0 ||
                           abs(track.durationSeconds - leader.durationSeconds) <= 1.5 {
                            clusters[i].append(track)
                            placed = true
                            break
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

                        if track.durationSeconds <= 0 || leader.durationSeconds <= 0 ||
                           abs(track.durationSeconds - leader.durationSeconds) <= 2.0 {
                            clusters[i].append(track)
                            placed = true
                            break
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
