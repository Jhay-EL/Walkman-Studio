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
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public var id: String { fullPath }
    public let name: String
    public let filename: String
    public let trackCount: Int
    public var tracks: [String]
    public let fullPath: String
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

public struct AlbumItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(artist)|\(name)" }
    public let name: String
    public let artist: String
    public let year: String
    public let trackCount: Int
    public let tracks: [Track]
    public var representativeTrack: Track? { tracks.first }
    public var isHiRes: Bool {
        tracks.contains { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
    }
}

public struct ArtistItem: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let albumCount: Int
    public let trackCount: Int
    public let albums: [AlbumItem]
    public let tracks: [Track]
}

public enum TransferStatus: Equatable, Sendable {
    case pending
    case converting
    case success
    case failed(String)
}

public struct TransferItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var filename: String { sourceURL.lastPathComponent }
    public var status: TransferStatus

    public init(sourceURL: URL, status: TransferStatus = .pending) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.status = status
    }
}
