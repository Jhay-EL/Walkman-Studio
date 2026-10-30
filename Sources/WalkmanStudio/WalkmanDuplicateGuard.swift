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

    public init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        durationSeconds: Double = 0,
        matchingWalkmanTrack: Track? = nil,
        matchReason: String
    ) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.matchingWalkmanTrack = matchingWalkmanTrack
        self.matchReason = matchReason
    }
}

// =============================================================================
// WALKMAN DUPLICATE GUARD
// Protects Walkman storage from duplicate audio files during ingestion and sync
// =============================================================================

public final class WalkmanDuplicateGuard: Sendable {
    public static let shared = WalkmanDuplicateGuard()

    private init() {}

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
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: albumDir.path) {
                    let sanitizedTitleLower = cleanTitle.lowercased()
                    for f in contents {
                        let fLower = f.lowercased()
                        // Matches if the filename contains the exact song title stem
                        if fLower.contains(sanitizedTitleLower) && !f.hasPrefix(".") {
                            return DuplicateCheckResult(
                                isDuplicate: true,
                                matchingTrack: nil,
                                reason: "File already exists on \(drive.name) (\(albumDir.lastPathComponent)/\(f))"
                            )
                        }
                    }
                }
            }
        }

        // 2. Walkman Library Metadata & Normalized Matching
        let tracksToCheck: [Track]
        if !existingTracks.isEmpty {
            tracksToCheck = existingTracks
        } else if let drive = targetDrive {
            tracksToCheck = LibraryScanner.shared.loadCachedTracks(forMount: drive.mountPoint)
        } else {
            tracksToCheck = []
        }

        guard !tracksToCheck.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
        }

        let rawCandidateTitle = title.isEmpty ? (sourceURL?.deletingPathExtension().lastPathComponent ?? "") : title
        let normTitle = DuplicateFinderService.normalizeTitle(rawCandidateTitle)
        let normArtist = DuplicateFinderService.normalizeArtist(artist)
        let normAlbum = DuplicateFinderService.normalizeAlbum(album)

        guard !normTitle.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
        }

        for tr in tracksToCheck {
            let trTitle = DuplicateFinderService.normalizeTitle(tr.title)
            let trArtist = DuplicateFinderService.normalizeArtist(tr.artist)
            let trAlbum = DuplicateFinderService.normalizeAlbum(tr.album)

            // Case A: Normalized Title and Artist Match
            if trTitle == normTitle && !normArtist.isEmpty && trArtist == normArtist {
                // If duration is known for both, ensure duration is within 5 seconds
                if durationSeconds > 5.0 && tr.durationSeconds > 5.0 {
                    if abs(durationSeconds - tr.durationSeconds) <= 5.0 {
                        return DuplicateCheckResult(
                            isDuplicate: true,
                            matchingTrack: tr,
                            reason: "Matches '\(tr.title)' by \(tr.artist) on \(tr.album)"
                        )
                    }
                } else {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchingTrack: tr,
                        reason: "Matches '\(tr.title)' by \(tr.artist) on \(tr.album)"
                    )
                }
            }

            // Case B: Same Album + Title Match (compilations, OSTs, or soundtrack albums)
            if trTitle == normTitle && !normAlbum.isEmpty && trAlbum == normAlbum {
                return DuplicateCheckResult(
                    isDuplicate: true,
                    matchingTrack: tr,
                    reason: "Matches '\(tr.title)' on album '\(tr.album)'"
                )
            }

            // Case C: Exact Audio Filename Match on Walkman filesystem
            if let src = sourceURL, src.lastPathComponent.lowercased() == tr.filename.lowercased() {
                return DuplicateCheckResult(
                    isDuplicate: true,
                    matchingTrack: tr,
                    reason: "Identical filename '\(tr.filename)' in \(tr.album)"
                )
            }
        }

        return DuplicateCheckResult(isDuplicate: false, matchingTrack: nil, reason: nil)
    }
}
