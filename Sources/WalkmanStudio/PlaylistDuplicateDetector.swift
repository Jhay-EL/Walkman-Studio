import Foundation

public enum PlaylistDuplicateMatchType: Sendable, Hashable {
    case exactPath
    case sameSong

    public var label: String {
        switch self {
        case .exactPath: return "Exact File"
        case .sameSong: return "Same Song"
        }
    }
}

public enum PlaylistDedupeKeepStrategy: String, CaseIterable, Identifiable, Sendable {
    case keepHighestQuality = "Keep Highest Quality"
    case keepFirstOccurrence = "Keep First Position"

    public var id: String { rawValue }
}

public struct PlaylistDuplicateEntry: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let path: String
    public let track: Track?
    public let canonicalPathKey: String
    public let qualityScore: Int

    public var sequenceNumber: Int { index + 1 }

    public var formatSummary: String {
        guard let tr = track else { return "Unresolved Path" }
        let fmt = tr.format.isEmpty ? "AUDIO" : tr.format.uppercased()
        if DuplicateFinderService.isLosslessFormat(fmt) && (tr.bitsPerSample > 0 || tr.sampleRate > 0) {
            let sr = tr.sampleRate > 0 ? String(format: "%.1fkHz", Double(tr.sampleRate) / 1000.0).replacingOccurrences(of: ".0kHz", with: "kHz") : ""
            let bd = tr.bitsPerSample > 0 ? "\(tr.bitsPerSample)-bit" : ""
            let specs = [bd, sr].filter { !$0.isEmpty }.joined(separator: "/")
            return specs.isEmpty ? fmt : "\(fmt) \(specs)"
        }
        if tr.bitrateKbps > 0 {
            return "\(fmt) \(tr.bitrateKbps)kbps"
        }
        return fmt
    }
}

public struct PlaylistDuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let matchType: PlaylistDuplicateMatchType
    public let displayTitle: String
    public let displayArtist: String
    public let entries: [PlaylistDuplicateEntry]
    public let hasQualityDifference: Bool

    public var extraCount: Int {
        max(0, entries.count - 1)
    }

    public func keptIndex(for strategy: PlaylistDedupeKeepStrategy) -> Int {
        switch strategy {
        case .keepFirstOccurrence:
            return entries.first?.index ?? 0
        case .keepHighestQuality:
            return bestQualityEntry?.index ?? entries.first?.index ?? 0
        }
    }

    private var bestQualityEntry: PlaylistDuplicateEntry? {
        entries.max { a, b in
            if a.qualityScore != b.qualityScore {
                return a.qualityScore < b.qualityScore
            }
            let aHasMeta = Self.hasCompleteMetadata(a.track)
            let bHasMeta = Self.hasCompleteMetadata(b.track)
            if aHasMeta != bHasMeta {
                return !aHasMeta && bHasMeta
            }
            let aIsCopy = DuplicateFinderService.hasCopySuffix(a.track?.filename ?? (a.path as NSString).lastPathComponent)
            let bIsCopy = DuplicateFinderService.hasCopySuffix(b.track?.filename ?? (b.path as NSString).lastPathComponent)
            if aIsCopy != bIsCopy {
                return aIsCopy && !bIsCopy
            }
            // Equal quality: prefer the earliest position in the playlist
            return a.index > b.index
        }
    }

    private static func hasCompleteMetadata(_ track: Track?) -> Bool {
        guard let tr = track else { return false }
        let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let art = tr.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !alb.isEmpty && alb != "unknown album" && !art.isEmpty && art != "unknown artist"
    }
}

public struct PlaylistDuplicateRowInfo: Hashable, Sendable {
    public let groupID: String
    public let matchType: PlaylistDuplicateMatchType
    public let copyNumber: Int
    public let totalCopies: Int
    public let isRecommendedKeep: Bool
    public let hasQualityDifference: Bool
}

public struct PlaylistDuplicateAnalysis: Sendable, Equatable {
    public let groups: [PlaylistDuplicateGroup]
    public let annotationsByIndex: [Int: PlaylistDuplicateRowInfo]
    public let duplicateIndices: Set<Int>
    public let totalExtraCopies: Int

    public static let empty = PlaylistDuplicateAnalysis(
        groups: [],
        annotationsByIndex: [:],
        duplicateIndices: [],
        totalExtraCopies: 0
    )

    public var isEmpty: Bool {
        groups.isEmpty
    }

    public func extraCopyIndices(strategy: PlaylistDedupeKeepStrategy) -> Set<Int> {
        var toRemove: Set<Int> = []
        for group in groups {
            let keepIdx = group.keptIndex(for: strategy)
            for entry in group.entries where entry.index != keepIdx {
                toRemove.insert(entry.index)
            }
        }
        return toRemove
    }

    public func keepingIndices(strategy: PlaylistDedupeKeepStrategy) -> Set<Int> {
        var toKeep: Set<Int> = []
        for group in groups {
            toKeep.insert(group.keptIndex(for: strategy))
        }
        return toKeep
    }

    /// Removes specified 0-based indices while preserving original order of all remaining entries.
    public static func deduplicatedPaths(from paths: [String], removing indicesToRemove: Set<Int>) -> [String] {
        guard !indicesToRemove.isEmpty else { return paths }
        return paths.indices.compactMap { idx in
            indicesToRemove.contains(idx) ? nil : paths[idx]
        }
    }
}

/// Fast single-pass in-memory duplicate analyzer for Walkman playlists (.m3u8 / .m3u).
public enum PlaylistDuplicateDetector {
    private static let trimChars = CharacterSet(charactersIn: "/ \t\r\n")
    private static let slashChars = CharacterSet(charactersIn: "/")
    private static let ignoredArtists: Set<String> = [
        "", "unknown", "unknown artist", "various", "various artists", "va"
    ]

    /// Canonicalizes playlist relative/absolute track paths across slash, case, `./`, `MUSIC/`, and `LEARNING/` differences.
    public static func normalizePathKey(_ path: String) -> String {
        var s = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: trimChars)
            .lowercased()
        while s.hasPrefix("./") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: slashChars)
        }
        if s.hasPrefix("music/") {
            s = String(s.dropFirst(6)).trimmingCharacters(in: slashChars)
        } else if s.hasPrefix("learning/") {
            s = String(s.dropFirst(9)).trimmingCharacters(in: slashChars)
        }
        return s
    }

    /// Analyzes duplicate tracks within a single playlist (both repeated paths and same-song cross-file copies).
    public static func analyze(resolvedTracks: [(path: String, track: Track?)]) -> PlaylistDuplicateAnalysis {
        guard resolvedTracks.count > 1 else { return .empty }

        // Pass 1: Group entries sharing identical normalized file path.
        var pathBuckets: [String: [PlaylistDuplicateEntry]] = [:]
        var bucketOrder: [String] = []
        pathBuckets.reserveCapacity(resolvedTracks.count)

        for (idx, pair) in resolvedTracks.enumerated() {
            let key = normalizePathKey(pair.path)
            guard !key.isEmpty else { continue }
            let entry = PlaylistDuplicateEntry(
                index: idx,
                path: pair.path,
                track: pair.track,
                canonicalPathKey: key,
                qualityScore: pair.track.map(DuplicateFinderService.qualityScore(for:)) ?? 0
            )
            if pathBuckets[key] == nil {
                bucketOrder.append(key)
            }
            pathBuckets[key, default: []].append(entry)
        }

        // Pass 2: Merge distinct canonical path clusters whose resolved metadata refers to the same song.
        struct SongBucket {
            var entries: [PlaylistDuplicateEntry]
            var distinctPathKeys: Set<String>
            var representativeTrack: Track?
            var durationSeconds: Double
        }

        var songKeyClusters: [String: [SongBucket]] = [:]
        var exactOnlyBuckets: [(key: String, entries: [PlaylistDuplicateEntry])] = []

        for key in bucketOrder {
            guard let entries = pathBuckets[key], let firstEntry = entries.first else { continue }
            if let tr = entries.compactMap(\.track).first,
               let sig = sameSongSignature(for: tr) {
                let dur = sig.durationSeconds
                var merged = false

                if var existingList = songKeyClusters[sig.key] {
                    for idx in existingList.indices {
                        let existingDur = existingList[idx].durationSeconds
                        if durationsCompatible(dur, existingDur) {
                            existingList[idx].entries.append(contentsOf: entries)
                            existingList[idx].distinctPathKeys.insert(key)
                            if existingList[idx].durationSeconds <= 0 && dur > 0 {
                                existingList[idx].durationSeconds = dur
                            }
                            merged = true
                            break
                        }
                    }
                    if !merged {
                        existingList.append(SongBucket(
                            entries: entries,
                            distinctPathKeys: [key],
                            representativeTrack: firstEntry.track,
                            durationSeconds: dur
                        ))
                    }
                    songKeyClusters[sig.key] = existingList
                } else {
                    songKeyClusters[sig.key] = [SongBucket(
                        entries: entries,
                        distinctPathKeys: [key],
                        representativeTrack: firstEntry.track,
                        durationSeconds: dur
                    )]
                }
                continue
            }

            if entries.count > 1 {
                exactOnlyBuckets.append((key: key, entries: entries))
            }
        }

        var groups: [PlaylistDuplicateGroup] = []

        for (songKey, clusterList) in songKeyClusters {
            for (clusterIdx, cluster) in clusterList.enumerated() where cluster.entries.count > 1 {
                let sortedEntries = cluster.entries.sorted { $0.index < $1.index }
                let matchType: PlaylistDuplicateMatchType = cluster.distinctPathKeys.count > 1 ? .sameSong : .exactPath
                let rep = cluster.representativeTrack ?? sortedEntries.compactMap(\.track).first
                let title = rep?.title.isEmpty == false ? rep!.title : ((sortedEntries[0].path as NSString).lastPathComponent)
                let artist = rep?.artist ?? ""
                let hasQualityDiff = computeHasQualityDifference(in: sortedEntries)

                groups.append(PlaylistDuplicateGroup(
                    id: "\(songKey)#\(clusterIdx)#\(sortedEntries[0].index)",
                    matchType: matchType,
                    displayTitle: title,
                    displayArtist: artist,
                    entries: sortedEntries,
                    hasQualityDifference: hasQualityDiff
                ))
            }
        }

        for bucket in exactOnlyBuckets {
            let sortedEntries = bucket.entries.sorted { $0.index < $1.index }
            let fallbackName = (sortedEntries[0].path as NSString).lastPathComponent
            groups.append(PlaylistDuplicateGroup(
                id: "path|\(bucket.key)",
                matchType: .exactPath,
                displayTitle: fallbackName,
                displayArtist: "",
                entries: sortedEntries,
                hasQualityDifference: false
            ))
        }

        groups.sort { ($0.entries.first?.index ?? 0) < ($1.entries.first?.index ?? 0) }

        var annotationsByIndex: [Int: PlaylistDuplicateRowInfo] = [:]
        var duplicateIndices: Set<Int> = []
        var totalExtras = 0

        for group in groups {
            totalExtras += group.extraCount
            let defaultStrategy: PlaylistDedupeKeepStrategy = group.hasQualityDifference ? .keepHighestQuality : .keepFirstOccurrence
            let keepIdx = group.keptIndex(for: defaultStrategy)
            for (copyIdx, entry) in group.entries.enumerated() {
                duplicateIndices.insert(entry.index)
                annotationsByIndex[entry.index] = PlaylistDuplicateRowInfo(
                    groupID: group.id,
                    matchType: group.matchType,
                    copyNumber: copyIdx + 1,
                    totalCopies: group.entries.count,
                    isRecommendedKeep: entry.index == keepIdx,
                    hasQualityDifference: group.hasQualityDifference
                )
            }
        }

        return PlaylistDuplicateAnalysis(
            groups: groups,
            annotationsByIndex: annotationsByIndex,
            duplicateIndices: duplicateIndices,
            totalExtraCopies: totalExtras
        )
    }

    /// Looks up a resolved track in memory by canonical relative path or lowercase filename fallback.
    public static func lookupTrack(for path: String, in trackLookup: [String: Track]) -> Track? {
        let normKey = normalizePathKey(path)
        if let tr = trackLookup[normKey] {
            return tr
        }
        let fn = (path as NSString).lastPathComponent.lowercased()
        return trackLookup[fn]
    }

    /// Lightweight extra-duplicate counter for playlist sidebar badges without disk reads.
    public static func countExtraCopies(in paths: [String], trackLookup: [String: Track]) -> Int {
        guard paths.count > 1 else { return 0 }
        let resolved: [(path: String, track: Track?)] = paths.map { path in
            (path, lookupTrack(for: path, in: trackLookup))
        }
        return analyze(resolvedTracks: resolved).totalExtraCopies
    }

    /// Returns whether adding `candidatePath` / `candidateTrack` would duplicate an existing playlist entry.
    public static func matchTypeWhenAdding(
        candidatePath: String,
        candidateTrack: Track?,
        to existingPaths: [String],
        resolveTrack: (String) -> Track?
    ) -> PlaylistDuplicateMatchType? {
        let candidateKey = normalizePathKey(candidatePath)
        guard !candidateKey.isEmpty else { return nil }

        for path in existingPaths {
            if normalizePathKey(path) == candidateKey {
                return .exactPath
            }
        }

        guard let candTrack = candidateTrack,
              let candSig = sameSongSignature(for: candTrack) else {
            return nil
        }

        for path in existingPaths {
            if let existingTrack = resolveTrack(path),
               let existingSig = sameSongSignature(for: existingTrack),
               existingSig.key == candSig.key,
               durationsCompatible(candSig.durationSeconds, existingSig.durationSeconds) {
                return .sameSong
            }
        }
        return nil
    }

    private static func sameSongSignature(for track: Track) -> (key: String, durationSeconds: Double)? {
        let trimmedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleSource = trimmedTitle.isEmpty
            ? (track.filename as NSString).deletingPathExtension
            : trimmedTitle
        let exactTitle = exactTextKey(titleSource)
        let exactArtist = exactTextKey(track.artist)
        guard !exactTitle.isEmpty, !ignoredArtists.contains(exactArtist) else {
            return nil
        }
        return (key: "\(exactArtist)|\(exactTitle)", durationSeconds: track.durationSeconds)
    }

    /// Compares exact track titles/artists case-insensitively with normalized Unicode/whitespace,
    /// intentionally preserving suffixes such as `(Remastered)`, `(feat. ...)`, `(Live)`, or versions.
    private static func exactTextKey(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func durationsCompatible(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs <= 0 || rhs <= 0 || abs(lhs - rhs) <= 4.0
    }

    private static func computeHasQualityDifference(in entries: [PlaylistDuplicateEntry]) -> Bool {
        let tracks = entries.compactMap(\.track)
        guard let first = tracks.first else { return false }
        return tracks.dropFirst().contains {
            DuplicateFinderService.hasQualityDifference(between: first, and: $0)
        }
    }
}
