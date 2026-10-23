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

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public var id: String // Unique match key
    public let title: String
    public let artist: String
    public var items: [DuplicateTrackItem]

    public var isCrossDrive: Bool {
        let drives = Set(items.map { $0.mountPoint })
        return drives.count > 1
    }

    public var hasQualityDifference: Bool {
        guard let first = items.first else { return false }
        return items.contains { item in
            item.track.format.uppercased() != first.track.format.uppercased() ||
            item.track.bitsPerSample != first.track.bitsPerSample ||
            item.track.sampleRate != first.track.sampleRate ||
            abs(item.track.bitrateKbps - first.track.bitrateKbps) > 64
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
            // If on the same drive, prefer the one with cover artwork or longer duration/larger size
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
            score += 6000
        } else if fmt == "FLAC" || fmt == "ALAC" || fmt == "WAV" || fmt == "AIFF" || fmt == "AIF" {
            score += 4000
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

        score += min(t.bitrateKbps, 2000)
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

    private init() {}

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

        // 2. Run duplicate clustering in background
        let groups = await Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            return Self.computeDuplicateGroups(tracks: allTracks, drives: drives)
        }.value

        let crossCount = groups.filter { $0.isCrossDrive }.count
        let qualityCount = groups.filter { $0.hasQualityDifference }.count
        let recoverable = groups.reduce(0) { $0 + $1.recoverableBytes }

        await MainActor.run {
            self.duplicateGroups = groups
            self.totalRecoverableBytes = recoverable
            self.crossDriveCount = crossCount
            self.qualityDifferenceCount = qualityCount
            self.isScanning = false
        }

        return groups
    }

    /// Pure function to cluster tracks into duplicate groups
    public static func computeDuplicateGroups(tracks: [Track], drives: [WalkmanDrive]) -> [DuplicateGroup] {
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

        // Map candidate tracks by normalized title + artist
        var candidateBuckets: [String: [Track]] = [:]
        for track in tracks {
            let tKey = normalizeTitle(track.title.isEmpty ? track.filename : track.title)
            let aKey = normalizeArtist(track.artist)
            guard !tKey.isEmpty else { continue }
            let key = "\(tKey)::\(aKey)"
            candidateBuckets[key, default: []].append(track)
        }

        var results: [DuplicateGroup] = []

        for (_, bucket) in candidateBuckets where bucket.count > 1 {
            // Check if all tracks in bucket have <= 0 duration
            let withDuration = bucket.filter { $0.durationSeconds > 0 }
            if withDuration.isEmpty {
                // Group by identical normalized title & artist directly
                let items = bucket.map { tr -> DuplicateTrackItem in
                    let driveInfo = resolveDrive(for: tr)
                    return DuplicateTrackItem(
                        track: tr,
                        driveName: driveInfo.name,
                        driveType: driveInfo.type,
                        mountPoint: driveInfo.mountPoint
                    )
                }
                let first = bucket[0]
                let cleanTitle = first.title.isEmpty ? first.filename : first.title
                let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                results.append(DuplicateGroup(
                    id: "\(cleanTitle.lowercased())::\(cleanArtist.lowercased())",
                    title: cleanTitle,
                    artist: cleanArtist,
                    items: items
                ))
                continue
            }

            // Cluster tracks by duration tolerance (+/- 4.0 seconds) to avoid grouping
            // different songs or different long/short remixes together
            var clusters: [[Track]] = []
            for track in bucket {
                var placed = false
                for i in 0..<clusters.count {
                    let avgDuration = clusters[i].reduce(0.0) { $0 + $1.durationSeconds } / Double(clusters[i].count)
                    if track.durationSeconds <= 0 || abs(track.durationSeconds - avgDuration) <= 4.0 {
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
                let items = cluster.map { tr -> DuplicateTrackItem in
                    let driveInfo = resolveDrive(for: tr)
                    return DuplicateTrackItem(
                        track: tr,
                        driveName: driveInfo.name,
                        driveType: driveInfo.type,
                        mountPoint: driveInfo.mountPoint
                    )
                }
                let first = cluster[0]
                let cleanTitle = first.title.isEmpty ? first.filename : first.title
                let cleanArtist = first.primaryArtist.isEmpty ? "Unknown Artist" : first.primaryArtist
                let clusterId = "\(cleanTitle.lowercased())::\(cleanArtist.lowercased())::\(Int(cluster[0].durationSeconds))"
                results.append(DuplicateGroup(
                    id: clusterId,
                    title: cleanTitle,
                    artist: cleanArtist,
                    items: items
                ))
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
            #"\s*(?:feat|ft)\.?\s+.+$"#
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

    /// Deletes a specific duplicate copy from the device
    public func deleteDuplicateItem(_ item: DuplicateTrackItem) async -> Bool {
        let path = item.track.fullPath

        // 1. Physical removal
        let success = await WalkmanEngine.shared.deleteTrackFile(atPath: path)
        LibraryScanner.shared.removeFromCache(fullPath: path)
        CoverArtCache.shared.invalidate(forFullPath: path, artist: item.track.primaryArtist, album: item.track.album)

        // 2. Stop playback if this track is playing
        if AudioPlayerService.shared.currentTrack?.fullPath == path {
            AudioPlayerService.shared.stopAndClear()
        }

        // 3. Update in-memory state
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
