import Foundation

public struct DuplicateCheckResult: Sendable {
    public let isDuplicate: Bool
    public let matchingTrack: Track?
    public let reason: String?

    public init(isDuplicate: Bool, matchingTrack: Track? = nil, reason: String? = nil) {
        self.isDuplicate = isDuplicate
        self.matchingTrack = matchingTrack
        self.reason = reason
    }
}

public struct DuplicateImportCandidate: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Double
    public let matchingWalkmanTrack: Track?
    public let matchReason: String
    public let destinationDriveName: String

    public init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        durationSeconds: Double = 0,
        matchingWalkmanTrack: Track? = nil,
        matchReason: String,
        destinationDriveName: String = "Walkman"
    ) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.matchingWalkmanTrack = matchingWalkmanTrack
        self.matchReason = matchReason
        self.destinationDriveName = destinationDriveName
    }

    public var destinationRelativePath: String? {
        guard let track = matchingWalkmanTrack else { return nil }
        if !track.relativePath.isEmpty {
            return track.relativePath.hasPrefix("/") ? track.relativePath : "/\(track.relativePath)"
        }
        return (track.fullPath as NSString).lastPathComponent
    }

    public var destinationQualityDescription: String? {
        guard let track = matchingWalkmanTrack else { return nil }
        var parts: [String] = []
        if !track.format.isEmpty { parts.append(track.format.uppercased()) }
        if track.bitsPerSample > 0 && track.sampleRate > 0 {
            parts.append("\(track.bitsPerSample)b/\(track.sampleRate / 1000)k")
        } else if track.bitrateKbps > 0 {
            parts.append("\(track.bitrateKbps) kbps")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

// =============================================================================
// WALKMAN DUPLICATE GUARD
// Protects Walkman storage from duplicate audio files during ingestion and sync
// =============================================================================

public final class WalkmanDuplicateGuard: Sendable {
    public static let shared = WalkmanDuplicateGuard()

    private init() {}

    /// Determines whether two artist names refer to the same primary or collaborating artist
    public static func areArtistsCompatible(artistA: String, artistB: String) -> Bool {
        let normA = DuplicateFinderService.normalizeArtist(artistA)
        let normB = DuplicateFinderService.normalizeArtist(artistB)

        // Both empty: allow fallback to strict title+album+duration
        if normA.isEmpty && normB.isEmpty { return true }
        if normA.isEmpty || normB.isEmpty { return false }

        let isUnknownA = normA == "unknown artist" || normA == "unknown"
        let isUnknownB = normB == "unknown artist" || normB == "unknown"
        if isUnknownA || isUnknownB {
            return isUnknownA && isUnknownB
        }

        // 1. Direct normalized match
        if normA == normB { return true }

        // 2. Primary artist comparison (stripping features)
        let primA = DuplicateFinderService.normalizeArtist(Track.parsePrimaryAndFeaturedArtist(from: artistA).primary)
        let primB = DuplicateFinderService.normalizeArtist(Track.parsePrimaryAndFeaturedArtist(from: artistB).primary)
        if !primA.isEmpty && !primB.isEmpty && primA == primB { return true }

        // 3. Featured / Collaborator containment (e.g. "Arthur Miguel" in "Arthur Miguel & Trisha Denise")
        if normA.count >= 4 && normB.contains(normA) { return true }
        if normB.count >= 4 && normA.contains(normB) { return true }

        return false
    }

    /// Checks whether an audio track already exists on the connected Walkman device or library.
    public func checkTrack(
        title: String,
        artist: String,
        album: String = "",
        durationSeconds: Double = 0,
        sourceURL: URL? = nil,
        targetDrive: WalkmanDrive?,
        targetMode: TransferTargetMode = .music,
        existingTracks: [Track] = []
    ) -> DuplicateCheckResult {
        // 1. Physical Target Path & Directory Check on Target Storage
        if let drive = targetDrive {
            let targetRootDir = (targetMode == .learning)
                ? URL(fileURLWithPath: drive.learningDir)
                : URL(fileURLWithPath: drive.musicDir)

            let cleanArtist = WalkmanEngine.shared.sanitizeFilename(artist.isEmpty ? "Unknown Artist" : artist)
            let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(album.isEmpty ? "Unknown Album" : album)
            let rawTitle = title.isEmpty ? (sourceURL?.deletingPathExtension().lastPathComponent ?? "Unknown Track") : title
            let cleanTitle = WalkmanEngine.shared.sanitizeFilename(rawTitle)
            let ext = sourceURL?.pathExtension.lowercased() ?? "flac"

            // Direct check for destination file
            let expectedURL = WalkmanEngine.shared.targetTrackURL(
                musicRoot: targetRootDir,
                artist: cleanArtist,
                album: cleanAlbum,
                trackNum: "01",
                title: cleanTitle,
                ext: ext
            )

            let albumDir = expectedURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: albumDir.path) {
                let isArtistKnown = !artist.isEmpty && artist.lowercased() != "unknown" && artist.lowercased() != "unknown artist"
                if isArtistKnown || cleanArtist == "Unknown Artist" {
                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: albumDir.path) {
                        let normCleanTitle = DuplicateFinderService.normalizeTitle(cleanTitle)
                        for f in contents {
                            if f.hasPrefix(".") { continue }
                            let fStem = (f as NSString).deletingPathExtension
                            let normFTitle = DuplicateFinderService.normalizeTitle(fStem)
                            let fLower = f.lowercased()
                            let cleanLower = cleanTitle.lowercased()

                            // Strict title match inside the album directory
                            let isTitleMatch = !normCleanTitle.isEmpty && (normFTitle == normCleanTitle || fLower == cleanLower)
                            if isTitleMatch {
                                let candidatePath = albumDir.appendingPathComponent(f).path
                                // Prevent self-match if source file and destination are the exact same path on disk
                                if let src = sourceURL, src.path == candidatePath {
                                    continue
                                }
                                if FileManager.default.fileExists(atPath: candidatePath) {
                                    let matchedTr = existingTracks.first(where: { $0.fullPath == candidatePath }) ?? {
                                        let tag = AudioTagger.shared.readMetadata(fileURL: URL(fileURLWithPath: candidatePath))
                                        let attr = try? FileManager.default.attributesOfItem(atPath: candidatePath)
                                        let size = (attr?[.size] as? NSNumber)?.int64Value ?? 0
                                        let rel = candidatePath.hasPrefix(drive.mountPoint)
                                            ? String(candidatePath.dropFirst(drive.mountPoint.count))
                                            : "\(albumDir.lastPathComponent)/\(f)"
                                        return Track(
                                            filename: f,
                                            relativePath: rel,
                                            fullPath: candidatePath,
                                            format: (candidatePath as NSString).pathExtension.uppercased(),
                                            title: (tag?.title.isEmpty == false) ? tag!.title : cleanTitle,
                                            artist: (tag?.artist.isEmpty == false) ? tag!.artist : cleanArtist,
                                            album: (tag?.album.isEmpty == false) ? tag!.album : cleanAlbum,
                                            trackNum: tag?.trackNumber ?? "01",
                                            year: tag?.year ?? "",
                                            genre: tag?.genre ?? "",
                                            durationSeconds: tag?.durationSeconds ?? 0,
                                            bitrateKbps: tag?.bitrateKbps ?? 0,
                                            sampleRate: tag?.sampleRate ?? 0,
                                            bitsPerSample: tag?.bitsPerSample ?? 0,
                                            hasArtwork: false,
                                            sizeBytes: size
                                        )
                                    }()
                                    var qualityPart = ""
                                    if matchedTr.bitsPerSample > 0 && matchedTr.sampleRate > 0 {
                                        qualityPart = " (\(matchedTr.format) • \(matchedTr.bitsPerSample)b/\(matchedTr.sampleRate / 1000)k)"
                                    } else if matchedTr.bitrateKbps > 0 {
                                        qualityPart = " (\(matchedTr.format) • \(matchedTr.bitrateKbps)k)"
                                    } else if !matchedTr.format.isEmpty {
                                        qualityPart = " (\(matchedTr.format))"
                                    }
                                    return DuplicateCheckResult(
                                        isDuplicate: true,
                                        matchingTrack: matchedTr,
                                        reason: "Already on \(drive.name): identical file '\(f)'\(qualityPart)"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Target Storage Metadata & Normalized Matching (Strictly Scoped to targetDrive)
        let tracksToCheck: [Track]
        if let drive = targetDrive {
            let mountPrefix = drive.mountPoint.hasSuffix("/") ? drive.mountPoint : "\(drive.mountPoint)/"
            // Filter provided existingTracks strictly to the destination drive partition
            let driveScoped = existingTracks.filter { $0.fullPath.hasPrefix(mountPrefix) }
            if !driveScoped.isEmpty {
                tracksToCheck = driveScoped
            } else if drive.type != .local {
                // If no tracks were provided for this drive, query SQLite cache for THIS specific mount point
                tracksToCheck = LibraryScanner.shared.loadCachedTracks(forMount: drive.mountPoint)
            } else {
                // Local destination: check LocalMusicLibraryService tracks inside this folder
                tracksToCheck = LocalMusicLibraryService.shared.tracks.filter { $0.fullPath.hasPrefix(mountPrefix) }
            }
        } else {
            // No target drive specified: fallback to provided tracks
            tracksToCheck = existingTracks
        }

        // Physically verify that candidate tracks actually exist on disk (pruning phantom/stale DB cache entries)
        let verifiedTracks = tracksToCheck.filter { tr in
            // Must not match against the source file itself
            if let src = sourceURL, src.path == tr.fullPath {
                return false
            }
            return FileManager.default.fileExists(atPath: tr.fullPath)
        }

        guard !verifiedTracks.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
        }

        let rawCandidateTitle = title.isEmpty ? (sourceURL?.deletingPathExtension().lastPathComponent ?? "") : title
        let normTitle = DuplicateFinderService.normalizeTitle(rawCandidateTitle)
        let normAlbum = DuplicateFinderService.normalizeAlbum(album)

        guard !normTitle.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
        }

        let driveName = targetDrive?.name ?? "destination"
        for tr in verifiedTracks {
            if let drive = targetDrive {
                let mountPrefix = drive.mountPoint.hasSuffix("/") ? drive.mountPoint : "\(drive.mountPoint)/"
                guard tr.fullPath.hasPrefix(mountPrefix) else { continue }
            }
            let trTitle = DuplicateFinderService.normalizeTitle(tr.title)
            let trAlbum = DuplicateFinderService.normalizeAlbum(tr.album)

            var qualityPart = ""
            if tr.bitsPerSample > 0 && tr.sampleRate > 0 {
                qualityPart = " (\(tr.format) • \(tr.bitsPerSample)b/\(tr.sampleRate / 1000)k)"
            } else if tr.bitrateKbps > 0 {
                qualityPart = " (\(tr.format) • \(tr.bitrateKbps)k)"
            } else if !tr.format.isEmpty {
                qualityPart = " (\(tr.format))"
            }

            // CRITICAL: Strict Artist Compatibility Verification
            let artistsMatch = Self.areArtistsCompatible(artistA: artist, artistB: tr.artist)

            // Case A: Normalized Title and Artist Match
            if trTitle == normTitle && artistsMatch {
                // If title is generic (e.g. "Intro", "Outro", "Track 01"), require matching album
                let isGeneric = DuplicateFinderService.isGenericOrAmbiguousTitle(normTitle)
                if isGeneric {
                    guard !normAlbum.isEmpty && trAlbum == normAlbum else { continue }
                }

                // If duration is known for both, ensure duration is within 10 seconds (allowing pregap/silence tolerance)
                if durationSeconds > 5.0 && tr.durationSeconds > 5.0 {
                    if abs(durationSeconds - tr.durationSeconds) <= 10.0 {
                        return DuplicateCheckResult(
                            isDuplicate: true,
                            matchingTrack: tr,
                            reason: "Already on \(driveName): '\(tr.title)' by \(tr.artist)\(qualityPart)"
                        )
                    }
                } else {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchingTrack: tr,
                        reason: "Already on \(driveName): '\(tr.title)' by \(tr.artist)\(qualityPart)"
                    )
                }
            }

            // Case B: Same Album + Title Match (STRICTLY requires matching artist!)
            if trTitle == normTitle && !normAlbum.isEmpty && trAlbum == normAlbum && artistsMatch {
                return DuplicateCheckResult(
                    isDuplicate: true,
                    matchingTrack: tr,
                    reason: "Already on \(driveName): '\(tr.title)' on album '\(tr.album)'\(qualityPart)"
                )
            }

            // Case C: Exact Audio Filename Match (STRICTLY requires matching artist or album!)
            if let src = sourceURL, src.lastPathComponent.lowercased() == tr.filename.lowercased() {
                if artistsMatch || (!normAlbum.isEmpty && trAlbum == normAlbum && artistsMatch) {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchingTrack: tr,
                        reason: "Already on \(driveName): identical file '\(tr.filename)' in \(tr.album)\(qualityPart)"
                    )
                }
            }
        }

        return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
    }
}
