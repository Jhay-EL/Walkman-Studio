import Foundation
import CommonCrypto
import CryptoKit
import AppKit
import Darwin

// MARK: - Enums & Models

public enum BackupDestinationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case local = "Local Mac Storage"
    case externalDrive = "External Drive"
    case custom = "Custom Folder"

    // Legacy cases retained for backward compatibility with existing manifest decoders
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"
    case iCloud = "iCloud Drive"

    public var id: String { rawValue }

    public var defaultIcon: String {
        switch self {
        case .local: return "internaldrive.fill"
        case .externalDrive: return "externaldrive.fill"
        case .custom: return "folder.fill"
        case .googleDrive: return "externaldrive.badge.icloud"
        case .oneDrive: return "cloud.fill"
        case .iCloud: return "icloud.fill"
        }
    }
}

public struct BackupDestination: Identifiable, Hashable, Sendable {
    public let id: String
    public let type: BackupDestinationType
    public let name: String
    public let path: String
    public let url: URL
    public let isAvailable: Bool
    public let freeBytes: Int64?
    public let descriptionText: String
    public let icon: String

    public init(
        id: String,
        type: BackupDestinationType,
        name: String,
        path: String,
        url: URL,
        isAvailable: Bool,
        freeBytes: Int64? = nil,
        descriptionText: String,
        icon: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.path = path
        self.url = url
        self.isAvailable = isAvailable
        self.freeBytes = freeBytes
        self.descriptionText = descriptionText
        self.icon = icon ?? type.defaultIcon
    }
}

public enum BackupScopeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case full = "full"
    case playlists = "playlists"
    case learning = "learning"
    case albums = "albums"
    case tracks = "tracks"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "Full Device Library"
        case .playlists: return "Playlists Only (.M3U8)"
        case .learning: return "Language Study (/LEARNING)"
        case .albums: return "Selected Albums"
        case .tracks: return "Selected Tracks"
        }
    }

    public var subtitle: String {
        switch self {
        case .full: return "Back up all music, language study, companion lyrics, and playlists."
        case .playlists: return "Back up all .M3U8 playlists and all songs referenced in them."
        case .learning: return "Back up the entire /LEARNING folder (audiobooks, podcasts, lessons)."
        case .albums: return "Manually select specific albums to back up."
        case .tracks: return "Manually select individual tracks to back up."
        }
    }

    public var icon: String {
        switch self {
        case .full: return "opticaldisc.fill"
        case .playlists: return "list.bullet.rectangle.portrait.fill"
        case .learning: return "character.book.closed.fill"
        case .albums: return "square.stack.fill"
        case .tracks: return "music.note"
        }
    }
}

public struct BackupScopeConfig: Sendable {
    public var type: BackupScopeType
    public var selectedAlbumKeys: Set<String>
    public var selectedTrackPaths: Set<String>

    public init(
        type: BackupScopeType,
        selectedAlbumKeys: Set<String> = [],
        selectedTrackPaths: Set<String> = []
    ) {
        self.type = type
        self.selectedAlbumKeys = selectedAlbumKeys
        self.selectedTrackPaths = selectedTrackPaths
    }
}

public struct BackupManifest: Codable, Identifiable, Sendable, Hashable, Equatable {
    public var id: UUID
    public var version: String
    public var createdAt: Date
    public var deviceName: String
    public var deviceModel: String
    public var sourceDriveMount: String
    public var sourceDriveName: String
    public var sourceDriveType: String
    public var scopeType: BackupScopeType
    public var scopeSummary: String
    public var isEncrypted: Bool
    public var totalFiles: Int
    public var totalBytes: Int64
    public var files: [BackupFileEntry]

    public init(
        id: UUID = UUID(),
        version: String = "1.0",
        createdAt: Date = Date(),
        deviceName: String,
        deviceModel: String,
        sourceDriveMount: String,
        sourceDriveName: String,
        sourceDriveType: String,
        scopeType: BackupScopeType,
        scopeSummary: String,
        isEncrypted: Bool,
        totalFiles: Int,
        totalBytes: Int64,
        files: [BackupFileEntry]
    ) {
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.sourceDriveMount = sourceDriveMount
        self.sourceDriveName = sourceDriveName
        self.sourceDriveType = sourceDriveType
        self.scopeType = scopeType
        self.scopeSummary = scopeSummary
        self.isEncrypted = isEncrypted
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.files = files
    }
}

public struct BackupFileEntry: Codable, Identifiable, Sendable, Hashable, Equatable {
    public var id: String { relativePath }
    public var relativePath: String
    public var sizeBytes: Int64

    public init(relativePath: String, sizeBytes: Int64) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
    }
}

public struct DiscoveredBackup: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let filename: String
    public let destinationType: BackupDestinationType
    public let isEncrypted: Bool
    public let dateModified: Date
    public let sizeBytes: Int64
    public var manifest: BackupManifest?

    public static func == (lhs: DiscoveredBackup, rhs: DiscoveredBackup) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public init(
        url: URL,
        filename: String,
        destinationType: BackupDestinationType,
        isEncrypted: Bool,
        dateModified: Date,
        sizeBytes: Int64,
        manifest: BackupManifest? = nil
    ) {
        self.url = url
        self.filename = filename
        self.destinationType = destinationType
        self.isEncrypted = isEncrypted
        self.dateModified = dateModified
        self.sizeBytes = sizeBytes
        self.manifest = manifest
    }
}

public enum BackupPhase: String, Sendable {
    case idle = "Ready"
    case analyzing = "Analyzing backup scope..."
    case preparing = "Preparing backup container..."
    case copying = "Backing up files..."
    case encrypting = "Encrypting with AES-256-GCM..."
    case restoring = "Restoring files to Walkman..."
    case decrypting = "Decrypting with AES-256-GCM..."
    case finalizing = "Finalizing & purging ghost files..."
    case completed = "Completed"
    case failed = "Failed"
}

public struct BackupProgress: Sendable {
    public var phase: BackupPhase
    public var currentItemName: String
    public var itemsProcessed: Int
    public var totalItems: Int
    public var bytesProcessed: Int64
    public var totalBytes: Int64

    public var fractionCompleted: Double {
        if totalBytes > 0 {
            return min(1.0, max(0.0, Double(bytesProcessed) / Double(totalBytes)))
        }
        if totalItems > 0 {
            return min(1.0, max(0.0, Double(itemsProcessed) / Double(totalItems)))
        }
        return 0.0
    }

    public init(
        phase: BackupPhase = .idle,
        currentItemName: String = "",
        itemsProcessed: Int = 0,
        totalItems: Int = 0,
        bytesProcessed: Int64 = 0,
        totalBytes: Int64 = 0
    ) {
        self.phase = phase
        self.currentItemName = currentItemName
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
        self.bytesProcessed = bytesProcessed
        self.totalBytes = totalBytes
    }
}

public struct RestoreResult: Sendable {
    public let totalFilesRestored: Int
    public let totalBytesRestored: Int64
    public let destinationMount: String
}

// MARK: - BackupRestoreService

public final class BackupRestoreService: @unchecked Sendable {
    public static let shared = BackupRestoreService()

    private let magicEncryptedHeader = "WKMENC01"
    private var isCancelled = false

    private init() {}

    public func cancel() {
        isCancelled = true
    }

    // MARK: - Destination Detection (Local & External Only)

    public func detectAvailableDestinations(
        walkmanMountPoints: Set<String>,
        customPath: String? = nil
    ) -> [BackupDestination] {
        var destinations: [BackupDestination] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Local Mac Storage (Default: ~/Music/Walkman Studio Backups)
        let localDir = home.appendingPathComponent("Music/Walkman Studio Backups")
        destinations.append(BackupDestination(
            id: "local_mac",
            type: .local,
            name: "Local Mac Storage",
            path: localDir.path,
            url: localDir,
            isAvailable: true,
            freeBytes: getFreeSpace(for: localDir),
            descriptionText: "~/Music/Walkman Studio Backups"
        ))

        // 2. External Drives & USB Storage
        let externalVolumes = detectExternalVolumes(excludingWalkman: walkmanMountPoints)
        for extVol in externalVolumes {
            let backupFolder = extVol.url.appendingPathComponent("Walkman Studio Backups")
            destinations.append(BackupDestination(
                id: "ext_\(extVol.url.path)",
                type: .externalDrive,
                name: "External: \(extVol.name)",
                path: backupFolder.path,
                url: backupFolder,
                isAvailable: true,
                freeBytes: extVol.freeBytes,
                descriptionText: "Direct to external storage: \(extVol.url.path)"
            ))
        }

        // 3. Custom Local Folder (if configured)
        if let cp = customPath, !cp.isEmpty {
            let customURL = URL(fileURLWithPath: cp)
            if fm.fileExists(atPath: customURL.path) {
                destinations.append(BackupDestination(
                    id: "custom_dir",
                    type: .custom,
                    name: "Custom: \(customURL.lastPathComponent)",
                    path: customURL.path,
                    url: customURL,
                    isAvailable: true,
                    freeBytes: getFreeSpace(for: customURL),
                    descriptionText: customURL.path
                ))
            }
        }

        return destinations
    }

    private func detectExternalVolumes(excludingWalkman: Set<String>) -> [(url: URL, name: String, freeBytes: Int64)] {
        var results: [(url: URL, name: String, freeBytes: Int64)] = []
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.volumeIsReadOnlyKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var rootStat = stat()
        stat("/", &rootStat)

        let systemVolumes: Set<String> = ["MACINTOSH HD", "RECOVERY", "PREBOOT", "VM", "UPDATE"]

        for volURL in contents {
            let name = volURL.lastPathComponent
            let upper = name.uppercased()
            if systemVolumes.contains(upper) || upper.hasSuffix(".DMG") {
                continue
            }
            if excludingWalkman.contains(volURL.path) {
                continue
            }

            var volStat = stat()
            if stat(volURL.path, &volStat) != 0 || volStat.st_dev == rootStat.st_dev {
                continue
            }

            let res = try? volURL.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey])
            if res?.volumeIsReadOnly == true { continue }
            if let isLocal = res?.volumeIsLocal, !isLocal { continue }

            var statv = statvfs()
            guard statvfs(volURL.path, &statv) == 0 else { continue }
            let blockSize = Int64(statv.f_frsize)
            let freeBytes = blockSize * Int64(statv.f_bavail)

            results.append((volURL, name, freeBytes))
        }
        return results
    }

    public func getFreeSpace(for url: URL) -> Int64? {
        var statv = statvfs()
        var checkPath = url.path
        if !FileManager.default.fileExists(atPath: checkPath) {
            checkPath = url.deletingLastPathComponent().path
        }
        guard statvfs(checkPath, &statv) == 0 else { return nil }
        let blockSize = Int64(statv.f_frsize)
        return blockSize * Int64(statv.f_bavail)
    }

    // MARK: - Key Derivation & Cryptography

    private func deriveKey(passphrase: String, salt: Data, rounds: UInt32 = 100000) -> SymmetricKey? {
        let keyLength = 32
        var derivedKeyData = Data(count: keyLength)
        let status = derivedKeyData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase,
                    passphrase.utf8.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    rounds,
                    derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    keyLength
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derivedKeyData)
    }

    // MARK: - File Resolution for Backup Scope

    public func resolveFilesToBackup(
        drive: WalkmanDrive,
        scope: BackupScopeConfig,
        allTracks: [Track]
    ) -> [(sourceURL: URL, relativePath: String, sizeBytes: Int64)] {
        var items: [(sourceURL: URL, relativePath: String, sizeBytes: Int64)] = []
        var seenRelativePaths = Set<String>()
        let fm = FileManager.default

        let mountURL = URL(fileURLWithPath: drive.mountPoint)
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        let learningURL = URL(fileURLWithPath: drive.learningDir)

        // Fast in-memory lookup for pre-scanned track sizes to avoid slow USB 2.0 stats
        var trackSizeLookup: [String: Int64] = [:]
        trackSizeLookup.reserveCapacity(allTracks.count)
        for tr in allTracks {
            trackSizeLookup[tr.fullPath] = tr.sizeBytes
        }

        func addFileIfValid(url: URL, relativePath: String, fallbackSize: Int64? = nil) {
            let lower = url.lastPathComponent.lowercased()
            if lower == ".ds_store" || lower.hasPrefix("._") || lower.hasPrefix(".spotlight") || lower.hasPrefix(".trashes") {
                return
            }
            if lower == "devicon.fil" || lower == "default-capability.xml" || lower.contains("system volume information") {
                return
            }
            let cleanRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if seenRelativePaths.contains(cleanRel) { return }

            let size: Int64
            if let fb = fallbackSize, fb > 0 {
                size = fb
            } else if let cached = trackSizeLookup[url.path], cached > 0 {
                size = cached
            } else if let res = try? url.resourceValues(forKeys: [.fileSizeKey]), let fSize = res.fileSize, fSize > 0 {
                size = Int64(fSize)
            } else if let attrs = try? fm.attributesOfItem(atPath: url.path), let fSize = attrs[.size] as? Int64, fSize > 0 {
                size = fSize
            } else {
                return
            }

            seenRelativePaths.insert(cleanRel)
            items.append((url, cleanRel, size))
        }

        switch scope.type {
        case .full:
            // Walk both /MUSIC and /LEARNING
            let rootDirs = [musicURL, learningURL]
            for root in rootDirs {
                guard fm.fileExists(atPath: root.path),
                      let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                    continue
                }
                while let fileURL = enumerator.nextObject() as? URL {
                    let rel = fileURL.path.replacingOccurrences(of: mountURL.path, with: "")
                    addFileIfValid(url: fileURL, relativePath: rel)
                }
            }

        case .playlists:
            // Find all .m3u8 playlists, their referenced songs, lyrics, and folder artwork
            var playlistURLs: [URL] = []
            let searchDirs = [musicURL, learningURL]
            for dir in searchDirs {
                if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for f in contents where f.pathExtension.lowercased() == "m3u8" || f.pathExtension.lowercased() == "m3u" {
                        playlistURLs.append(f)
                    }
                }
            }

            for pURL in playlistURLs {
                let pRel = pURL.path.replacingOccurrences(of: mountURL.path, with: "")
                addFileIfValid(url: pURL, relativePath: pRel)

                let referenced = WalkmanEngine.shared.readPlaylist(at: pURL)
                let parentDir = pURL.deletingLastPathComponent()

                for relTrack in referenced {
                    let trackURL = parentDir.appendingPathComponent(relTrack)
                    if fm.fileExists(atPath: trackURL.path) {
                        let fullRel = trackURL.path.replacingOccurrences(of: mountURL.path, with: "")
                        addFileIfValid(url: trackURL, relativePath: fullRel)

                        // Check companion .lrc
                        let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
                        if fm.fileExists(atPath: lrcURL.path) {
                            let lrcRel = lrcURL.path.replacingOccurrences(of: mountURL.path, with: "")
                            addFileIfValid(url: lrcURL, relativePath: lrcRel)
                        }

                        // Check folder cover.jpg or folder.jpg
                        let folderArt = trackURL.deletingLastPathComponent().appendingPathComponent("cover.jpg")
                        if fm.fileExists(atPath: folderArt.path) {
                            let artRel = folderArt.path.replacingOccurrences(of: mountURL.path, with: "")
                            addFileIfValid(url: folderArt, relativePath: artRel)
                        }
                    }
                }
            }

        case .learning:
            // Walk exclusively /LEARNING
            if fm.fileExists(atPath: learningURL.path),
               let enumerator = fm.enumerator(at: learningURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let rel = fileURL.path.replacingOccurrences(of: mountURL.path, with: "")
                    addFileIfValid(url: fileURL, relativePath: rel)
                }
            }

        case .albums:
            // Match tracks whose album key matches selectedAlbumKeys
            let matchingTracks = allTracks.filter { tr in
                let key = "\(tr.album.lowercased())|\(tr.artist.lowercased())"
                return scope.selectedAlbumKeys.contains(key) || scope.selectedAlbumKeys.contains(tr.album.lowercased())
            }

            for tr in matchingTracks {
                let trackURL = URL(fileURLWithPath: tr.fullPath)
                if fm.fileExists(atPath: trackURL.path) {
                    let rel = trackURL.path.replacingOccurrences(of: mountURL.path, with: "")
                    addFileIfValid(url: trackURL, relativePath: rel)

                    let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
                    if fm.fileExists(atPath: lrcURL.path) {
                        let lrcRel = lrcURL.path.replacingOccurrences(of: mountURL.path, with: "")
                        addFileIfValid(url: lrcURL, relativePath: lrcRel)
                    }

                    let folderArt = trackURL.deletingLastPathComponent().appendingPathComponent("cover.jpg")
                    if fm.fileExists(atPath: folderArt.path) {
                        let artRel = folderArt.path.replacingOccurrences(of: mountURL.path, with: "")
                        addFileIfValid(url: folderArt, relativePath: artRel)
                    }
                }
            }

        case .tracks:
            for fullPath in scope.selectedTrackPaths {
                let trackURL = URL(fileURLWithPath: fullPath)
                if fm.fileExists(atPath: trackURL.path) {
                    let rel = trackURL.path.replacingOccurrences(of: mountURL.path, with: "")
                    addFileIfValid(url: trackURL, relativePath: rel)

                    let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
                    if fm.fileExists(atPath: lrcURL.path) {
                        let lrcRel = lrcURL.path.replacingOccurrences(of: mountURL.path, with: "")
                        addFileIfValid(url: lrcURL, relativePath: lrcRel)
                    }
                }
            }
        }

        return items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    // MARK: - Perform Backup

    public func performBackup(
        sourceDrive: WalkmanDrive,
        destination: BackupDestination,
        scope: BackupScopeConfig,
        allTracks: [Track],
        deviceInfo: WalkmanDeviceInfo?,
        isEncrypted: Bool,
        passphrase: String?,
        onProgress: @escaping (BackupProgress) -> Void
    ) async throws -> URL {
        isCancelled = false
        let fm = FileManager.default

        // 1. Ensure destination directory exists
        try fm.createDirectory(at: destination.url, withIntermediateDirectories: true)

        // 2. Resolve files to back up
        onProgress(BackupProgress(phase: .analyzing, currentItemName: "Scanning scope...", itemsProcessed: 0, totalItems: 0, bytesProcessed: 0, totalBytes: 0))

        let files = resolveFilesToBackup(drive: sourceDrive, scope: scope, allTracks: allTracks)
        guard !files.isEmpty else {
            throw NSError(domain: "BackupRestore", code: 400, userInfo: [NSLocalizedDescriptionKey: "No matching music or playlist files found for the selected scope."])
        }

        let totalBytes = files.reduce(0) { $0 + $1.sizeBytes }
        let totalCount = files.count

        // 3. Format timestamp and base name
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let devModelClean = (deviceInfo?.specificModel ?? sourceDrive.name).replacingOccurrences(of: " ", with: "_")
        let basePackageName = "WalkmanBackup_\(devModelClean)_\(timestamp)"

        let fileEntries = files.map { BackupFileEntry(relativePath: $0.relativePath, sizeBytes: $0.sizeBytes) }
        let scopeSummary: String
        switch scope.type {
        case .full: scopeSummary = "Full Library (\(totalCount) files)"
        case .playlists: scopeSummary = "Playlists Scope (\(totalCount) files)"
        case .learning: scopeSummary = "Language Study (\(totalCount) files)"
        case .albums: scopeSummary = "\(scope.selectedAlbumKeys.count) Albums (\(totalCount) files)"
        case .tracks: scopeSummary = "\(scope.selectedTrackPaths.count) Tracks (\(totalCount) files)"
        }

        let manifest = BackupManifest(
            deviceName: deviceInfo?.displayName ?? sourceDrive.name,
            deviceModel: deviceInfo?.specificModel ?? "Walkman",
            sourceDriveMount: sourceDrive.mountPoint,
            sourceDriveName: sourceDrive.name,
            sourceDriveType: sourceDrive.type.rawValue,
            scopeType: scope.type,
            scopeSummary: scopeSummary,
            isEncrypted: isEncrypted,
            totalFiles: totalCount,
            totalBytes: totalBytes,
            files: fileEntries
        )

        if isEncrypted {
            // MARK: Encrypted Stream Archive (.walkmanbackup.enc)
            guard let pass = passphrase, !pass.isEmpty else {
                throw NSError(domain: "BackupRestore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Passphrase is required for encrypted backups."])
            }

            let targetURL = destination.url.appendingPathComponent("\(basePackageName).walkmanbackup.enc")
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            guard let key = deriveKey(passphrase: pass, salt: salt) else {
                throw NSError(domain: "BackupRestore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Cryptographic key derivation failed."])
            }

            fm.createFile(atPath: targetURL.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: targetURL) else {
                throw NSError(domain: "BackupRestore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not open target backup container for writing."])
            }

            defer { try? handle.close() }

            // Write Magic WKMENC01
            handle.write(magicEncryptedHeader.data(using: .utf8)!)
            // Write Salt (16 bytes)
            handle.write(salt)

            // Write Public Preview Summary (JSON)
            let summaryDict: [String: Any] = [
                "deviceName": manifest.deviceName,
                "deviceModel": manifest.deviceModel,
                "scopeSummary": manifest.scopeSummary,
                "createdAt": ISO8601DateFormatter().string(from: manifest.createdAt),
                "totalFiles": manifest.totalFiles,
                "totalBytes": manifest.totalBytes
            ]
            let summaryData = (try? JSONSerialization.data(withJSONObject: summaryDict, options: [])) ?? Data()
            var sumLen = UInt32(summaryData.count).bigEndian
            handle.write(Data(bytes: &sumLen, count: 4))
            handle.write(summaryData)

            // Write Encrypted Manifest
            let manifestData = try JSONEncoder().encode(manifest)
            let sealedManifest = try AES.GCM.seal(manifestData, using: key).combined!
            var manLen = UInt32(sealedManifest.count).bigEndian
            handle.write(Data(bytes: &manLen, count: 4))
            handle.write(sealedManifest)

            // Write Total Files count
            var countBig = UInt32(totalCount).bigEndian
            handle.write(Data(bytes: &countBig, count: 4))

            // Stream and encrypt each file with throttled progress reporting
            var bytesDone: Int64 = 0
            var lastProgressTime: CFAbsoluteTime = 0

            for (idx, item) in files.enumerated() {
                if isCancelled {
                    try? handle.close()
                    try? fm.removeItem(at: targetURL)
                    throw NSError(domain: "BackupRestore", code: -999, userInfo: [NSLocalizedDescriptionKey: "Backup cancelled by user."])
                }

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressTime >= 0.08 || idx == 0 || idx == totalCount - 1 {
                    lastProgressTime = now
                    onProgress(BackupProgress(
                        phase: .encrypting,
                        currentItemName: item.sourceURL.lastPathComponent,
                        itemsProcessed: idx,
                        totalItems: totalCount,
                        bytesProcessed: bytesDone,
                        totalBytes: totalBytes
                    ))
                }

                // Sequential direct stream read (avoids 4KB page fault penalties over USB 2.0 FAT32)
                let fileData: Data
                if let readHandle = try? FileHandle(forReadingFrom: item.sourceURL) {
                    fileData = readHandle.readDataToEndOfFile()
                    try? readHandle.close()
                } else {
                    fileData = try Data(contentsOf: item.sourceURL)
                }

                let sealedFile = try AES.GCM.seal(fileData, using: key).combined!
                var dLen = UInt64(sealedFile.count).bigEndian
                handle.write(Data(bytes: &dLen, count: 8))
                handle.write(sealedFile)

                bytesDone += item.sizeBytes
            }

            onProgress(BackupProgress(
                phase: .completed,
                currentItemName: "Complete",
                itemsProcessed: totalCount,
                totalItems: totalCount,
                bytesProcessed: totalBytes,
                totalBytes: totalBytes
            ))

            return targetURL

        } else {
            // MARK: Unencrypted Bundle Directory (.walkmanbackup)
            let bundleURL = destination.url.appendingPathComponent("\(basePackageName).walkmanbackup")
            try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

            // Write manifest.json
            let manifestURL = bundleURL.appendingPathComponent("manifest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            // Copy each file into mirrored relative structure with kernel-level copyfile and directory caching
            var bytesDone: Int64 = 0
            var createdDirs = Set<String>()
            var lastProgressTime: CFAbsoluteTime = 0

            for (idx, item) in files.enumerated() {
                if isCancelled {
                    try? fm.removeItem(at: bundleURL)
                    throw NSError(domain: "BackupRestore", code: -999, userInfo: [NSLocalizedDescriptionKey: "Backup cancelled by user."])
                }

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressTime >= 0.08 || idx == 0 || idx == totalCount - 1 {
                    lastProgressTime = now
                    onProgress(BackupProgress(
                        phase: .copying,
                        currentItemName: item.sourceURL.lastPathComponent,
                        itemsProcessed: idx,
                        totalItems: totalCount,
                        bytesProcessed: bytesDone,
                        totalBytes: totalBytes
                    ))
                }

                let targetFileURL = bundleURL.appendingPathComponent(item.relativePath)
                let parentDir = targetFileURL.deletingLastPathComponent()
                let parentDirPath = parentDir.path

                // Ensure parent directory exists (cached to avoid redundant disk stats)
                if !createdDirs.contains(parentDirPath) {
                    if !fm.fileExists(atPath: parentDirPath) {
                        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }
                    createdDirs.insert(parentDirPath)
                }

                // Fast kernel-level copy via copyfile(3)
                // Uses optimized 1MB-4MB kernel buffers and APFS cloning where supported
                let srcPath = item.sourceURL.path
                let dstPath = targetFileURL.path
                let status = copyfile(srcPath, dstPath, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_UNLINK))
                if status != 0 {
                    if fm.fileExists(atPath: dstPath) {
                        try? fm.removeItem(at: targetFileURL)
                    }
                    try fm.copyItem(at: item.sourceURL, to: targetFileURL)
                }

                bytesDone += item.sizeBytes
            }

            onProgress(BackupProgress(
                phase: .completed,
                currentItemName: "Complete",
                itemsProcessed: totalCount,
                totalItems: totalCount,
                bytesProcessed: totalBytes,
                totalBytes: totalBytes
            ))

            return bundleURL
        }
    }

    // MARK: - Discover Existing Backups

    public func discoverBackups(in destinations: [BackupDestination]) -> [DiscoveredBackup] {
        var results: [DiscoveredBackup] = []
        let fm = FileManager.default

        for dest in destinations where dest.isAvailable {
            guard let contents = try? fm.contentsOfDirectory(at: dest.url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            for fileURL in contents {
                let name = fileURL.lastPathComponent
                if name.hasSuffix(".walkmanbackup") {
                    // Unencrypted package
                    let manifestURL = fileURL.appendingPathComponent("manifest.json")
                    var manifest: BackupManifest? = nil
                    if let data = try? Data(contentsOf: manifestURL),
                       let parsed = try? JSONDecoder().decode(BackupManifest.self, from: data) {
                        manifest = parsed
                    }
                    let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
                    let modDate = attrs?[.modificationDate] as? Date ?? Date()
                    let size = manifest?.totalBytes ?? (attrs?[.size] as? Int64 ?? 0)

                    results.append(DiscoveredBackup(
                        url: fileURL,
                        filename: name,
                        destinationType: dest.type,
                        isEncrypted: false,
                        dateModified: modDate,
                        sizeBytes: size,
                        manifest: manifest
                    ))

                } else if name.hasSuffix(".walkmanbackup.enc") {
                    // Encrypted container
                    let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
                    let modDate = attrs?[.modificationDate] as? Date ?? Date()
                    let size = attrs?[.size] as? Int64 ?? 0

                    // Attempt to parse public summary header
                    var manifestPreview: BackupManifest? = nil
                    if let handle = try? FileHandle(forReadingFrom: fileURL) {
                        let magicData = handle.readData(ofLength: 8)
                        if let magic = String(data: magicData, encoding: .utf8), magic == magicEncryptedHeader {
                            _ = handle.readData(ofLength: 16) // salt
                            let sumLenData = handle.readData(ofLength: 4)
                            if sumLenData.count == 4 {
                                let sumLen = Int(sumLenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                                if sumLen > 0 && sumLen < 65536 {
                                    let sumData = handle.readData(ofLength: sumLen)
                                    if let json = try? JSONSerialization.jsonObject(with: sumData) as? [String: Any] {
                                        let devName = json["deviceName"] as? String ?? "Sony Walkman"
                                        let devModel = json["deviceModel"] as? String ?? "Walkman"
                                        let summary = json["scopeSummary"] as? String ?? "Encrypted Backup"
                                        let count = json["totalFiles"] as? Int ?? 0
                                        let bBytes = (json["totalBytes"] as? NSNumber)?.int64Value ?? size

                                        manifestPreview = BackupManifest(
                                            createdAt: modDate,
                                            deviceName: devName,
                                            deviceModel: devModel,
                                            sourceDriveMount: "",
                                            sourceDriveName: devName,
                                            sourceDriveType: "internal",
                                            scopeType: .full,
                                            scopeSummary: summary,
                                            isEncrypted: true,
                                            totalFiles: count,
                                            totalBytes: bBytes,
                                            files: []
                                        )
                                    }
                                }
                            }
                        }
                        try? handle.close()
                    }

                    results.append(DiscoveredBackup(
                        url: fileURL,
                        filename: name,
                        destinationType: dest.type,
                        isEncrypted: true,
                        dateModified: modDate,
                        sizeBytes: size,
                        manifest: manifestPreview
                    ))
                }
            }
        }

        return results.sorted { $0.dateModified > $1.dateModified }
    }

    // MARK: - Restore Backup

    public func performRestore(
        backupURL: URL,
        targetDrive: WalkmanDrive,
        passphrase: String?,
        onProgress: @escaping (BackupProgress) -> Void
    ) async throws -> RestoreResult {
        isCancelled = false
        let fm = FileManager.default
        let isEncrypted = backupURL.pathExtension.lowercased() == "enc" || backupURL.lastPathComponent.hasSuffix(".enc")
        let targetMountURL = URL(fileURLWithPath: targetDrive.mountPoint)

        if isEncrypted {
            // MARK: Restore from Encrypted Container
            guard let pass = passphrase, !pass.isEmpty else {
                throw NSError(domain: "BackupRestore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Passphrase is required to decrypt this backup."])
            }

            guard let handle = try? FileHandle(forReadingFrom: backupURL) else {
                throw NSError(domain: "BackupRestore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not open backup file for reading."])
            }
            defer { try? handle.close() }

            // 1. Verify Magic
            let magicData = handle.readData(ofLength: 8)
            guard let magic = String(data: magicData, encoding: .utf8), magic == magicEncryptedHeader else {
                throw NSError(domain: "BackupRestore", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid backup format or unencrypted file."])
            }

            // 2. Read Salt and derive key
            let salt = handle.readData(ofLength: 16)
            guard let key = deriveKey(passphrase: pass, salt: salt) else {
                throw NSError(domain: "BackupRestore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Key derivation failed."])
            }

            // 3. Skip Public Summary
            let sumLenData = handle.readData(ofLength: 4)
            let sumLen = Int(sumLenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            _ = handle.readData(ofLength: sumLen)

            // 4. Decrypt Manifest
            let manLenData = handle.readData(ofLength: 4)
            guard manLenData.count == 4 else {
                throw NSError(domain: "BackupRestore", code: 400, userInfo: [NSLocalizedDescriptionKey: "Corrupted backup container header."])
            }
            let manLen = Int(manLenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let manBoxData = handle.readData(ofLength: manLen)

            let decryptedManifestData: Data
            do {
                let box = try AES.GCM.SealedBox(combined: manBoxData)
                decryptedManifestData = try AES.GCM.open(box, using: key)
            } catch {
                throw NSError(domain: "BackupRestore", code: 403, userInfo: [NSLocalizedDescriptionKey: "Incorrect decryption password or corrupted backup file."])
            }

            let manifest = try JSONDecoder().decode(BackupManifest.self, from: decryptedManifestData)

            // 5. Check Target Capacity
            if targetDrive.freeBytes < manifest.totalBytes {
                let reqMB = Double(manifest.totalBytes) / 1_048_576.0
                let freeMB = Double(targetDrive.freeBytes) / 1_048_576.0
                throw NSError(domain: "BackupRestore", code: 507, userInfo: [NSLocalizedDescriptionKey: "Insufficient free space on \(targetDrive.name). Requires \(String(format: "%.1f MB", reqMB)), available \(String(format: "%.1f MB", freeMB))."])
            }

            // 6. Read File Count
            let countData = handle.readData(ofLength: 4)
            let fileCount = Int(countData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })

            var bytesRestored: Int64 = 0
            var createdDirs = Set<String>()
            var lastProgressTime: CFAbsoluteTime = 0

            for (idx, entry) in manifest.files.enumerated() {
                if isCancelled {
                    throw NSError(domain: "BackupRestore", code: -999, userInfo: [NSLocalizedDescriptionKey: "Restore cancelled by user."])
                }

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressTime >= 0.08 || idx == 0 || idx == fileCount - 1 {
                    lastProgressTime = now
                    onProgress(BackupProgress(
                        phase: .decrypting,
                        currentItemName: (entry.relativePath as NSString).lastPathComponent,
                        itemsProcessed: idx,
                        totalItems: fileCount,
                        bytesProcessed: bytesRestored,
                        totalBytes: manifest.totalBytes
                    ))
                }

                let lenData = handle.readData(ofLength: 8)
                guard lenData.count == 8 else { break }
                let dLen = Int(lenData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
                let sealedData = handle.readData(ofLength: dLen)

                let fileBytes: Data
                do {
                    let fileBox = try AES.GCM.SealedBox(combined: sealedData)
                    fileBytes = try AES.GCM.open(fileBox, using: key)
                } catch {
                    throw NSError(domain: "BackupRestore", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decrypt \(entry.relativePath). File may be corrupted."])
                }

                // Write file to Walkman target (direct write avoids slow .atomic rename on FAT32/exFAT)
                let targetURL = targetMountURL.appendingPathComponent(entry.relativePath)
                let parentDir = targetURL.deletingLastPathComponent()
                let parentDirPath = parentDir.path

                if !createdDirs.contains(parentDirPath) {
                    if !fm.fileExists(atPath: parentDirPath) {
                        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    }
                    createdDirs.insert(parentDirPath)
                }

                if fm.fileExists(atPath: targetURL.path) {
                    try? fm.removeItem(at: targetURL)
                }
                try fileBytes.write(to: targetURL)

                bytesRestored += entry.sizeBytes
            }

            // 7. Hardware ghost clean & sync
            onProgress(BackupProgress(phase: .finalizing, currentItemName: "Cleaning ghost files...", itemsProcessed: fileCount, totalItems: fileCount, bytesProcessed: bytesRestored, totalBytes: manifest.totalBytes))
            _ = await WalkmanEngine.shared.cleanGhostFiles(mountPoint: targetDrive.mountPoint)
            sync()

            onProgress(BackupProgress(phase: .completed, currentItemName: "Complete", itemsProcessed: fileCount, totalItems: fileCount, bytesProcessed: bytesRestored, totalBytes: manifest.totalBytes))

            return RestoreResult(totalFilesRestored: fileCount, totalBytesRestored: bytesRestored, destinationMount: targetDrive.mountPoint)

        } else {
            // MARK: Restore from Unencrypted Bundle Directory
            let manifestURL = backupURL.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else {
                throw NSError(domain: "BackupRestore", code: 400, userInfo: [NSLocalizedDescriptionKey: "manifest.json missing or invalid in backup bundle."])
            }

            if targetDrive.freeBytes < manifest.totalBytes {
                let reqMB = Double(manifest.totalBytes) / 1_048_576.0
                let freeMB = Double(targetDrive.freeBytes) / 1_048_576.0
                throw NSError(domain: "BackupRestore", code: 507, userInfo: [NSLocalizedDescriptionKey: "Insufficient free space on \(targetDrive.name). Requires \(String(format: "%.1f MB", reqMB)), available \(String(format: "%.1f MB", freeMB))."])
            }

            var bytesRestored: Int64 = 0
            let totalCount = manifest.files.count
            var createdDirs = Set<String>()
            var lastProgressTime: CFAbsoluteTime = 0

            for (idx, entry) in manifest.files.enumerated() {
                if isCancelled {
                    throw NSError(domain: "BackupRestore", code: -999, userInfo: [NSLocalizedDescriptionKey: "Restore cancelled by user."])
                }

                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressTime >= 0.08 || idx == 0 || idx == totalCount - 1 {
                    lastProgressTime = now
                    onProgress(BackupProgress(
                        phase: .restoring,
                        currentItemName: (entry.relativePath as NSString).lastPathComponent,
                        itemsProcessed: idx,
                        totalItems: totalCount,
                        bytesProcessed: bytesRestored,
                        totalBytes: manifest.totalBytes
                    ))
                }

                let sourceFileURL = backupURL.appendingPathComponent(entry.relativePath)
                let targetFileURL = targetMountURL.appendingPathComponent(entry.relativePath)

                if fm.fileExists(atPath: sourceFileURL.path) {
                    let parentDir = targetFileURL.deletingLastPathComponent()
                    let parentDirPath = parentDir.path

                    if !createdDirs.contains(parentDirPath) {
                        if !fm.fileExists(atPath: parentDirPath) {
                            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                        }
                        createdDirs.insert(parentDirPath)
                    }

                    let srcPath = sourceFileURL.path
                    let dstPath = targetFileURL.path
                    let status = copyfile(srcPath, dstPath, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_UNLINK))
                    if status != 0 {
                        if fm.fileExists(atPath: dstPath) {
                            try? fm.removeItem(at: targetFileURL)
                        }
                        try fm.copyItem(at: sourceFileURL, to: targetFileURL)
                    }
                }

                bytesRestored += entry.sizeBytes
            }

            // 7. Hardware ghost clean & sync
            onProgress(BackupProgress(phase: .finalizing, currentItemName: "Cleaning ghost files...", itemsProcessed: totalCount, totalItems: totalCount, bytesProcessed: bytesRestored, totalBytes: manifest.totalBytes))
            _ = await WalkmanEngine.shared.cleanGhostFiles(mountPoint: targetDrive.mountPoint)
            sync()

            onProgress(BackupProgress(phase: .completed, currentItemName: "Complete", itemsProcessed: totalCount, totalItems: totalCount, bytesProcessed: bytesRestored, totalBytes: manifest.totalBytes))

            return RestoreResult(totalFilesRestored: totalCount, totalBytesRestored: bytesRestored, destinationMount: targetDrive.mountPoint)
        }
    }
}
