import Foundation

public enum DriveType: String, Codable, Sendable {
    case `internal`
    case microsd
}

public struct WalkmanDrive: Identifiable, Hashable, Sendable {
    public var id: String { mountPoint }
    public let name: String
    public let mountPoint: String
    public let type: DriveType
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let freeBytes: Int64
    public let percentUsed: Double
    public let hasCfw: Bool
    public let musicDir: String

    public var learningDir: String {
        URL(fileURLWithPath: mountPoint).appendingPathComponent("LEARNING").path
    }

    public init(name: String, mountPoint: String, type: DriveType, totalBytes: Int64, usedBytes: Int64, freeBytes: Int64, percentUsed: Double, hasCfw: Bool, musicDir: String) {
        self.name = name
        self.mountPoint = mountPoint
        self.type = type
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.percentUsed = percentUsed
        self.hasCfw = hasCfw
        self.musicDir = musicDir
    }
}

public enum TransferTargetMode: String, CaseIterable, Identifiable, Sendable {
    case music = "music"
    case learning = "learning"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .music: return "Music Library"
        case .learning: return "Language Study & Audiobooks"
        }
    }

    public var rootFolderName: String {
        switch self {
        case .music: return "MUSIC"
        case .learning: return "LEARNING"
        }
    }

    public var icon: String {
        switch self {
        case .music: return "music.note"
        case .learning: return "character.book.closed.fill"
        }
    }
}

public struct Track: Identifiable, Hashable, Sendable {
    public var id: String { fullPath }
    public let filename: String
    public let relativePath: String
    public let fullPath: String
    public let format: String // "FLAC", "MP3", "M4A", etc.
    public var title: String
    public var artist: String
    public var album: String
    public var trackNum: String
    public var year: String
    public var genre: String
    public var durationSeconds: Double
    public var bitrateKbps: Int
    public var sampleRate: Int
    public var bitsPerSample: Int
    public var hasArtwork: Bool
    public let sizeBytes: Int64
    public var dateAdded: Date

    public init(
        filename: String,
        relativePath: String,
        fullPath: String,
        format: String,
        title: String,
        artist: String,
        album: String,
        trackNum: String,
        year: String,
        genre: String,
        durationSeconds: Double,
        bitrateKbps: Int,
        sampleRate: Int,
        bitsPerSample: Int,
        hasArtwork: Bool,
        sizeBytes: Int64,
        dateAdded: Date = Date()
    ) {
        self.filename = filename
        self.relativePath = relativePath
        self.fullPath = fullPath
        self.format = format
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNum = trackNum
        self.year = year
        self.genre = genre
        self.durationSeconds = durationSeconds
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        self.hasArtwork = hasArtwork
        self.sizeBytes = sizeBytes
        self.dateAdded = dateAdded
    }
}

extension Track {
    /// Extracts the primary artist name, stripping guest/featured artists (e.g. "6CycleMind, Ebe Dancel" -> "6CycleMind").
    public var primaryArtist: String {
        Track.parsePrimaryAndFeaturedArtist(from: artist).primary
    }

    /// Whether this track belongs to Language Study mode (/LEARNING/ or language/audiobook/podcast genre)
    public var isLanguageStudy: Bool {
        fullPath.contains("/LEARNING/") ||
        genre.localizedCaseInsensitiveContains("language") ||
        genre.localizedCaseInsensitiveContains("audiobook") ||
        genre.localizedCaseInsensitiveContains("podcast") ||
        genre.localizedCaseInsensitiveContains("learning")
    }

    /// Extracts any featured or guest artists if present.
    public var featuredArtist: String? {
        Track.parsePrimaryAndFeaturedArtist(from: artist).featured
    }

    /// Parses an artist string into primary artist and optional featured artist string.
    public static func parsePrimaryAndFeaturedArtist(from raw: String) -> (primary: String, featured: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("Unknown Artist", nil)
        }

        let lower = trimmed.lowercased()

        // Known artists that contain commas, ampersands, or slashes as part of their official name
        let knownExceptions: [String] = [
            "tyler, the creator",
            "earth, wind & fire",
            "crosby, stills, nash & young",
            "crosby, stills & nash",
            "emerson, lake & palmer",
            "blood, sweat & tears",
            "peter, paul and mary",
            "peter, paul & mary",
            "simon & garfunkel",
            "hall & oates",
            "daryl hall & john oates",
            "brooks & dunn",
            "bell biv devoe",
            "kool & the gang",
            "kc & the sunshine band"
        ]

        for known in knownExceptions {
            if lower == known {
                return (trimmed, nil)
            }
            if lower.hasPrefix(known) {
                let rest = trimmed.dropFirst(known.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if rest.isEmpty {
                    return (trimmed, nil)
                }
                let primary = String(trimmed.prefix(known.count))
                let cleanedFeat = stripLeadingFeatTokens(String(rest))
                return (primary, cleanedFeat.isEmpty ? nil : cleanedFeat)
            }
        }

        // 1. Explicit keyword markers: feat., ft., featuring, with (case-insensitive)
        let keywords = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", " Featuring ", " with ", " With "]
        for kw in keywords {
            if let range = trimmed.range(of: kw, options: .caseInsensitive) {
                let primary = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let feat = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !primary.isEmpty {
                    return (primary, feat.isEmpty ? nil : feat)
                }
            }
        }

        // 2. Parenthesized feat: e.g. "Drake (feat. Rihanna)" or "Drake [ft. Rihanna]"
        for (open, close) in [("(", ")"), ("[", "]")] {
            if trimmed.hasSuffix(close), let openIdx = trimmed.range(of: open, options: .backwards)?.lowerBound {
                let primary = String(trimmed[..<openIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                let inside = String(trimmed[openIdx...].dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerInside = inside.lowercased()
                for prefix in ["feat. ", "feat ", "ft. ", "ft ", "featuring ", "with "] {
                    if lowerInside.hasPrefix(prefix) {
                        let feat = String(inside.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !primary.isEmpty {
                            return (primary, feat.isEmpty ? nil : feat)
                        }
                    }
                }
            }
        }

        // 3. Delimiters: comma (", "), semicolon ("; "), forward slashes (" / ", " // ")
        // Split on the first delimiter so e.g. "2 Chainz, Big Sean, Drake" -> "2 Chainz", "Big Sean, Drake"
        let delimiters = [", ", "; ", " / ", " // "]
        for delim in delimiters {
            if let range = trimmed.range(of: delim) {
                let primary = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let feat = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !primary.isEmpty && !feat.isEmpty {
                    return (primary, feat)
                }
            }
        }

        return (trimmed, nil)
    }

    private static func stripLeadingFeatTokens(_ text: String) -> String {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while str.hasPrefix(",") || str.hasPrefix(";") || str.hasPrefix("/") || str.hasPrefix("-") || str.hasPrefix("&") {
            str = String(str.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = str.lowercased()
        for prefix in ["feat. ", "feat ", "ft. ", "ft ", "featuring ", "with "] {
            if lower.hasPrefix(prefix) {
                return String(str.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return str
    }

    /// Formats the guest/featured artists for display on track rows.
    /// Returns nil if track title already contains feat information or if no guest is present.
    public func featuredDisplayString(primaryArtist: String? = nil) -> String? {
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("feat.") || lowerTitle.contains("feat ") || lowerTitle.contains("ft.") || lowerTitle.contains("featuring") {
            return nil
        }

        let raw = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let parsed = Track.parsePrimaryAndFeaturedArtist(from: raw)
        if let feat = parsed.featured, !feat.isEmpty {
            return feat
        }

        if let pa = primaryArtist, !pa.isEmpty, raw.localizedCaseInsensitiveCompare(pa) != .orderedSame {
            if raw.lowercased().hasPrefix(pa.lowercased()) {
                let rest = raw.dropFirst(pa.count)
                let cleaned = Track.stripLeadingFeatTokens(String(rest))
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }

        return nil
    }
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public var id: String { fullPath }
    public let name: String
    public let filename: String
    public let trackCount: Int
    public var tracks: [String]
    public let fullPath: String

    public var isLanguageStudy: Bool {
        fullPath.contains("/LEARNING/")
    }
}

public struct WalkmanDeviceInfo: Sendable, Hashable, Codable {
    public let modelRaw: String // e.g. "NW-A50Series"
    public let marketingName: String // e.g. "WALKMAN NW-A50Series"
    public let displayName: String // e.g. "Sony Walkman NW-A55L"
    public let seriesName: String // e.g. "NW-A50 Series"
    public let specificModel: String // e.g. "NW-A55L"
    public let vendor: String // e.g. "Sony Corporation"
    public let firmwareVersion: String // e.g. "1.02"
    public let isNonAndroid: Bool
    public let hasCfw: Bool
    public let displayResolution: String // e.g. "800x480"
    public let internalCapacityGb: Double
    public let supportedAudioFormats: [String]
    
    public init(
        modelRaw: String,
        marketingName: String,
        displayName: String,
        seriesName: String,
        specificModel: String,
        vendor: String,
        firmwareVersion: String,
        isNonAndroid: Bool,
        hasCfw: Bool,
        displayResolution: String,
        internalCapacityGb: Double,
        supportedAudioFormats: [String]
    ) {
        self.modelRaw = modelRaw
        self.marketingName = marketingName
        self.displayName = displayName
        self.seriesName = seriesName
        self.specificModel = specificModel
        self.vendor = vendor
        self.firmwareVersion = firmwareVersion
        self.isNonAndroid = isNonAndroid
        self.hasCfw = hasCfw
        self.displayResolution = displayResolution
        self.internalCapacityGb = internalCapacityGb
        self.supportedAudioFormats = supportedAudioFormats
    }
}

public struct WalkmanDevice: Identifiable, Hashable, Sendable {
    public var id: String { primaryMountPoint }
    public let deviceInfo: WalkmanDeviceInfo
    public var drives: [WalkmanDrive]

    public var internalDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .internal })
    }

    public var microsdDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .microsd })
    }

    public var primaryMountPoint: String {
        internalDrive?.mountPoint ?? microsdDrive?.mountPoint ?? deviceInfo.specificModel
    }

    public var displayName: String {
        deviceInfo.displayName
    }

    public var specificModel: String {
        deviceInfo.specificModel
    }

    public var seriesName: String {
        deviceInfo.seriesName
    }

    public var totalBytes: Int64 {
        drives.reduce(0) { $0 + $1.totalBytes }
    }

    public var usedBytes: Int64 {
        drives.reduce(0) { $0 + $1.usedBytes }
    }

    public var freeBytes: Int64 {
        drives.reduce(0) { $0 + $1.freeBytes }
    }

    public var percentUsed: Double {
        totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0
    }

    public init(deviceInfo: WalkmanDeviceInfo, drives: [WalkmanDrive]) {
        self.deviceInfo = deviceInfo
        self.drives = drives
    }
}

public struct AlbumItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(name.lowercased())|\(artist.lowercased())" }
    public let name: String
    public let artist: String
    public let year: String
    public let trackCount: Int
    public let tracks: [Track]
    public var representativeTrack: Track? { tracks.first }
    public var isHiRes: Bool {
        tracks.contains { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
    }
    public var latestDateAdded: Date {
        tracks.map(\.dateAdded).max() ?? Date.distantPast
    }
    public var primaryFormat: String {
        tracks.first?.format ?? "FLAC"
    }
    public var isLanguageStudy: Bool {
        tracks.contains(where: \.isLanguageStudy)
    }
}

public struct ArtistItem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let albumCount: Int
    public let trackCount: Int
    public let albums: [AlbumItem]
    public let tracks: [Track]
    public var representativeTrack: Track? {
        tracks.first(where: { $0.hasArtwork }) ?? tracks.first
    }
    public var isLanguageStudy: Bool {
        tracks.contains(where: \.isLanguageStudy)
    }
}

public enum TransferStatus: Equatable, Sendable {
    case pending
    case optimizing
    case converting
    case success
    case failed(String)
}

public struct TransferItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var filename: String { sourceURL.lastPathComponent }
    public var status: TransferStatus

    // Metadata Properties
    public var title: String
    public var artist: String
    public var album: String
    public var trackNumber: String
    public var year: String
    public var genre: String
    public var durationSeconds: Double
    public var bitrateKbps: Int
    public var sampleRate: Int
    public var bitsPerSample: Int
    public var format: String
    public var sizeBytes: Int64

    // Artwork & Optimization
    public var artworkData: Data?
    public var isArtworkOptimized: Bool

    // Lyrics
    public var lyrics: String?
    public var isLyricsSynced: Bool

    // UI & In-Flight State
    public var isFetchingOnline: Bool
    public var isOptimizing: Bool
    public var isExpanded: Bool

    public init(
        sourceURL: URL,
        status: TransferStatus = .pending,
        title: String = "",
        artist: String = "",
        album: String = "",
        trackNumber: String = "1",
        year: String = "",
        genre: String = "",
        durationSeconds: Double = 0,
        bitrateKbps: Int = 0,
        sampleRate: Int = 44100,
        bitsPerSample: Int = 16,
        format: String = "",
        sizeBytes: Int64 = 0,
        artworkData: Data? = nil,
        isArtworkOptimized: Bool = false,
        lyrics: String? = nil,
        isLyricsSynced: Bool = false,
        isFetchingOnline: Bool = false,
        isOptimizing: Bool = false,
        isExpanded: Bool = false
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.status = status
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.year = year
        self.genre = genre
        self.durationSeconds = durationSeconds
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        self.format = format.isEmpty ? sourceURL.pathExtension.uppercased() : format
        self.sizeBytes = sizeBytes
        self.artworkData = artworkData
        self.isArtworkOptimized = isArtworkOptimized
        self.lyrics = lyrics
        self.isLyricsSynced = isLyricsSynced
        self.isFetchingOnline = isFetchingOnline
        self.isOptimizing = isOptimizing
        self.isExpanded = isExpanded
    }

    /// Converts this item into a preview Track compatible with the audio player
    public func toPreviewTrack() -> Track {
        Track(
            filename: filename,
            relativePath: filename,
            fullPath: sourceURL.path,
            format: format.isEmpty ? sourceURL.pathExtension.uppercased() : format,
            title: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            album: album.isEmpty ? "Unknown Album" : album,
            trackNum: trackNumber,
            year: year,
            genre: genre,
            durationSeconds: durationSeconds,
            bitrateKbps: bitrateKbps,
            sampleRate: sampleRate,
            bitsPerSample: bitsPerSample,
            hasArtwork: artworkData != nil,
            sizeBytes: sizeBytes,
            dateAdded: Date()
        )
    }

    /// Indicates whether crucial metadata fields are missing
    public var isMissingMetadata: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        title.lowercased() == "unknown" ||
        title.lowercased() == "unknown track" ||
        title.lowercased() == "unknown title" ||
        artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        artist.lowercased() == "unknown artist" ||
        artist.lowercased() == "unknown" ||
        album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        album.lowercased() == "unknown album" ||
        album.lowercased() == "unknown" ||
        artworkData == nil
    }
}

public struct AudioFileMetadata: Sendable {
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var trackNumber: String = ""
    public var year: String = ""
    public var genre: String = ""
    public var durationSeconds: Double = 0
    public var bitrateKbps: Int = 0
    public var sampleRate: Int = 44100
    public var bitsPerSample: Int = 16
    public var hasArtwork: Bool = false
    
    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        trackNumber: String = "",
        year: String = "",
        genre: String = "",
        durationSeconds: Double = 0,
        bitrateKbps: Int = 0,
        sampleRate: Int = 44100,
        bitsPerSample: Int = 16,
        hasArtwork: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.year = year
        self.genre = genre
        self.durationSeconds = durationSeconds
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        self.hasArtwork = hasArtwork
    }
}
