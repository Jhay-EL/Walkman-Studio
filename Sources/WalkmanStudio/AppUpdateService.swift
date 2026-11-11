import Foundation
import AppKit
import CryptoKit
import SwiftUI

// MARK: - Semantic Version

/// Parsed semantic version supporting optional `v` prefix, variable segment counts, and pre-release suffixes.
public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let revision: Int
    public let preRelease: String
    public let rawValue: String

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPrefix: String
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            withoutPrefix = String(trimmed.dropFirst())
        } else {
            withoutPrefix = trimmed
        }

        // Ignore build metadata after '+'
        let coreAndPre = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let hyphenParts = coreAndPre.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericPart = String(hyphenParts[0])
        let preReleasePart = hyphenParts.count > 1 ? String(hyphenParts[1]) : ""

        let dotParts = numericPart.split(separator: ".", omittingEmptySubsequences: false)
        guard !dotParts.isEmpty, dotParts.count <= 4 else { return nil }

        var nums: [Int] = []
        for part in dotParts {
            guard let value = Int(part), value >= 0 else { return nil }
            nums.append(value)
        }

        self.major = nums.count > 0 ? nums[0] : 0
        self.minor = nums.count > 1 ? nums[1] : 0
        self.patch = nums.count > 2 ? nums[2] : 0
        self.revision = nums.count > 3 ? nums[3] : 0
        self.preRelease = preReleasePart
        self.rawValue = withoutPrefix
    }

    public var description: String {
        let core = revision > 0 ? "\(major).\(minor).\(patch).\(revision)" : "\(major).\(minor).\(patch)"
        return preRelease.isEmpty ? core : "\(core)-\(preRelease)"
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.revision == rhs.revision
            && lhs.preRelease == rhs.preRelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(revision)
        hasher.combine(preRelease)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }

        // Stable release is newer than pre-release of same version tuple
        if lhs.preRelease.isEmpty && rhs.preRelease.isEmpty { return false }
        if lhs.preRelease.isEmpty { return false }
        if rhs.preRelease.isEmpty { return true }

        let lhsIDs = lhs.preRelease.split(separator: ".")
        let rhsIDs = rhs.preRelease.split(separator: ".")
        let count = max(lhsIDs.count, rhsIDs.count)

        for i in 0..<count {
            if i >= lhsIDs.count { return true }
            if i >= rhsIDs.count { return false }
            let a = String(lhsIDs[i])
            let b = String(rhsIDs[i])
            if let ai = Int(a), let bi = Int(b) {
                if ai != bi { return ai < bi }
            } else if a != b {
                return a < b
            }
        }
        return false
    }
}

// MARK: - Build & Asset Models

public enum UpdateBuildArchitecture: String, CaseIterable, Sendable {
    case universal
    case arm64
    case intel

    public var displayName: String {
        switch self {
        case .universal: return "Universal (Apple Silicon & Intel)"
        case .arm64: return "Apple Silicon (arm64)"
        case .intel: return "Intel (x86_64)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .universal: return "Universal"
        case .arm64: return "Apple Silicon"
        case .intel: return "Intel"
        }
    }
}

public enum UpdateArchiveKind: String, Sendable {
    case zip
    case dmg
}

public struct GitHubAssetPayload: Decodable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: String
    public let size: Int64
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public init(name: String, browserDownloadURL: String, size: Int64, contentType: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.contentType = contentType
    }
}

public struct GitHubReleasePayload: Decodable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let publishedAt: String?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [GitHubAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
        case assets
    }
}

public struct UpdateAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let sizeBytes: Int64
    public let archiveKind: UpdateArchiveKind
    public let flavorLabel: String

    public init(name: String, downloadURL: URL, sizeBytes: Int64, archiveKind: UpdateArchiveKind, flavorLabel: String) {
        self.name = name
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.archiveKind = archiveKind
        self.flavorLabel = flavorLabel
    }
}

public struct UpdateReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tagName: String
    public let title: String
    public let releaseNotes: String
    public let publishedAt: Date?
    public let htmlURL: URL
    public let preferredAsset: UpdateAsset?
    public let checksumFileURL: URL?

    public var isChecksumVerifiedPossible: Bool {
        checksumFileURL != nil
    }
}

public struct UpdateInstallTarget: Equatable, Sendable {
    public let destinationAppURL: URL
    public let isBundledApp: Bool
    public let isAppTranslocated: Bool
    public let isSourceOnReadOnlyVolume: Bool
    public let requiresPrivilegeCheckNote: Bool
}

public enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(UpdateReleaseInfo)
    case downloading(UpdateReleaseInfo, progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case verifying(UpdateReleaseInfo, stage: String)
    case readyToInstall(UpdateReleaseInfo, stagedAppURL: URL, checksumVerified: Bool)
    case installing(UpdateReleaseInfo)
    case failed(message: String)
}

public enum AppUpdateError: LocalizedError {
    case invalidResponse(String)
    case rateLimited(resetDescription: String?)
    case noCompatibleAsset
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case invalidBundle(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let msg): return msg
        case .rateLimited(let reset):
            if let reset {
                return "GitHub API rate limit reached. Try again after \(reset), or download from GitHub Releases."
            }
            return "GitHub API rate limit reached. Please try again later or download manually from GitHub."
        case .noCompatibleAsset:
            return "No compatible macOS installer archive (.zip or .dmg) was found in this GitHub release."
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 verification failed. Expected \(expected.prefix(12))..., got \(actual.prefix(12))... Update aborted for safety."
        case .extractionFailed(let msg):
            return "Failed to unpack the update archive: \(msg)"
        case .invalidBundle(let msg):
            return "Downloaded application bundle failed verification: \(msg)"
        case .installFailed(let msg):
            return msg
        }
    }
}

// MARK: - URLSession Download Delegate Bridge

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Int64, Int64) -> Void)?
    var onCompletion: ((Result<URL, Error>) -> Void)?

    private var completed = false
    private let lock = NSLock()

    private func finishOnce(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        onCompletion?(result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finishOnce(.failure(AppUpdateError.invalidResponse("Download failed with HTTP status \(http.statusCode).")))
            return
        }

        // Move out of URLSession's ephemeral temp location immediately before didFinishDownloadingTo returns.
        let preservedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalkmanStudio-Download-\(UUID().uuidString).tmp")
        do {
            try? FileManager.default.removeItem(at: preservedURL)
            try FileManager.default.moveItem(at: location, to: preservedURL)
            finishOnce(.success(preservedURL))
        } catch {
            finishOnce(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finishOnce(.failure(error))
        }
    }
}

// MARK: - AppUpdateService

/// Manages GitHub release discovery, architecture matching, download progress,
/// SHA-256 verification, staging, and atomic self-replacement for Walkman Studio.
@MainActor
public final class AppUpdateService: NSObject, ObservableObject {
    public static let shared = AppUpdateService()

    nonisolated public static let githubOwner = "Jhay-EL"
    nonisolated public static let githubRepo = "Walkman-Studio"
    nonisolated public static let expectedBundleIdentifier = "com.sony.walkmanstudio"
    nonisolated public static let releasesPageURL = URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    nonisolated public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    nonisolated public static let googleDriveMirrorURL = URL(string: "https://drive.google.com/drive/folders/1wC3F0Cdy_iJwdWQvR1VFc5VnvdhyULhd?usp=share_link")!

    private enum DefaultsKey {
        static let autoCheckOnLaunch = "WalkmanStudio.autoCheckUpdatesOnLaunch"
        static let lastCheckTimestamp = "WalkmanStudio.lastUpdateCheckTimestamp"
        static let cachedETag = "WalkmanStudio.cachedReleaseETag"
        static let cachedReleaseJSON = "WalkmanStudio.cachedLatestReleaseJSON"
    }

    private static let automaticCheckInterval: TimeInterval = 12 * 60 * 60

    @Published public private(set) var state: AppUpdateState = .idle
    @Published public private(set) var lastCheckedAt: Date? = nil
    @Published public var autoCheckOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckOnLaunch, forKey: DefaultsKey.autoCheckOnLaunch)
        }
    }

    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadSession: URLSession?
    private var checkTask: Task<Void, Never>?
    private var lastProgressEmitTime: TimeInterval = 0

    // MARK: Bundle & Host Metadata

    public var currentVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "3.1.1"
    }

    public var currentBuildNumberString: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "311"
    }

    public var currentSemanticVersion: SemanticVersion {
        SemanticVersion(currentVersionString) ?? SemanticVersion("3.1.1")!
    }

    public var runningBuildArchitecture: UpdateBuildArchitecture {
        Self.detectInstalledBuildArchitecture(bundle: .main, hostSupportsArm64: Self.hostSupportsArm64())
    }

    public var installTarget: UpdateInstallTarget {
        Self.resolveInstallDestination(bundleURL: Bundle.main.bundleURL)
    }

    public var hasAvailableUpdate: Bool {
        switch state {
        case .available, .downloading, .verifying, .readyToInstall, .installing:
            return true
        default:
            return false
        }
    }

    public var availableRelease: UpdateReleaseInfo? {
        switch state {
        case .available(let rel),
             .downloading(let rel, _, _, _),
             .verifying(let rel, _),
             .readyToInstall(let rel, _, _),
             .installing(let rel):
            return rel
        default:
            return nil
        }
    }

    public var availableVersionTag: String? {
        availableRelease?.tagName
    }

    private override init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.autoCheckOnLaunch) == nil {
            defaults.set(true, forKey: DefaultsKey.autoCheckOnLaunch)
        }
        self.autoCheckOnLaunch = defaults.bool(forKey: DefaultsKey.autoCheckOnLaunch)
        let ts = defaults.double(forKey: DefaultsKey.lastCheckTimestamp)
        if ts > 0 {
            self.lastCheckedAt = Date(timeIntervalSince1970: ts)
        }
        super.init()
    }

    // MARK: - Launch & Manual Checking

    public func performAutomaticLaunchCheckIfNeeded() {
        guard autoCheckOnLaunch else { return }
        if case .checking = state { return }
        if hasAvailableUpdate { return }

        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.automaticCheckInterval {
            return
        }
        checkForUpdates(userInitiated: false)
    }

    public func checkForUpdates(userInitiated: Bool) {
        if case .downloading = state { return }
        if case .verifying = state { return }
        if case .installing = state { return }

        checkTask?.cancel()
        if userInitiated || state == .idle {
            state = .checking
        }

        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.runGitHubReleaseCheck(userInitiated: userInitiated)
        }
    }

    private func runGitHubReleaseCheck(userInitiated: Bool) async {
        do {
            let defaults = UserDefaults.standard
            var request = URLRequest(url: Self.latestReleaseAPIURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("WalkmanStudio/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

            if let etag = defaults.string(forKey: DefaultsKey.cachedETag),
               defaults.data(forKey: DefaultsKey.cachedReleaseJSON) != nil {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppUpdateError.invalidResponse("Received invalid response from GitHub.")
            }

            let now = Date()
            if http.statusCode == 304, let cachedData = defaults.data(forKey: DefaultsKey.cachedReleaseJSON) {
                defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.lastCheckTimestamp)
                self.lastCheckedAt = now
                try applyReleasePayloadData(cachedData, checkedAt: now)
                return
            }

            if http.statusCode == 403 || http.statusCode == 429 {
                let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
                if remaining == "0" || http.statusCode == 429 {
                    let resetStr = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                        .flatMap(TimeInterval.init)
                        .map { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .shortened) }
                    throw AppUpdateError.rateLimited(resetDescription: resetStr)
                }
            }

            guard (200...299).contains(http.statusCode) else {
                throw AppUpdateError.invalidResponse("GitHub returned HTTP \(http.statusCode) while checking for updates.")
            }

            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: DefaultsKey.cachedETag)
            }
            defaults.set(data, forKey: DefaultsKey.cachedReleaseJSON)
            defaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.lastCheckTimestamp)
            self.lastCheckedAt = now

            try applyReleasePayloadData(data, checkedAt: now)
        } catch is CancellationError {
            return
        } catch {
            if !userInitiated, case .idle = state {
                // Silent failure on automatic background startup check
                return
            }
            if userInitiated {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private func applyReleasePayloadData(_ data: Data, checkedAt: Date) throws {
        let releasePayload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard let releaseInfo = Self.evaluateReleasePayload(
            releasePayload,
            currentVersion: currentSemanticVersion,
            buildArch: runningBuildArchitecture,
            hostSupportsArm64: Self.hostSupportsArm64()
        ) else {
            // If cached already staged bundle exists for current/older release, ensure clean upToDate state.
            state = .upToDate(checkedAt: checkedAt)
            return
        }

        // Preserve staged state if the exact same newer release was already downloaded & staged.
        if case .readyToInstall(let stagedRelease, let stagedURL, let verified) = state,
           stagedRelease.version == releaseInfo.version,
           FileManager.default.fileExists(atPath: stagedURL.path) {
            state = .readyToInstall(releaseInfo, stagedAppURL: stagedURL, checksumVerified: verified)
            return
        }

        state = .available(releaseInfo)
    }

    // MARK: - Download, Verification & Staging

    public func downloadAndStageUpdate(_ release: UpdateReleaseInfo) {
        guard let asset = release.preferredAsset else {
            state = .failed(message: AppUpdateError.noCompatibleAsset.localizedDescription)
            return
        }

        cancelActiveDownloadTask()
        lastProgressEmitTime = 0
        state = .downloading(release, progress: 0, bytesWritten: 0, totalBytes: asset.sizeBytes)

        Task { [weak self] in
            guard let self else { return }
            do {
                let downloadedArchiveURL = try await self.downloadFile(asset.downloadURL) { [weak self] written, expected in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard case .downloading(let activeRelease, _, _, _) = self.state,
                              activeRelease.version == release.version else {
                            return
                        }
                        let now = ProcessInfo.processInfo.systemUptime
                        let total = expected > 0 ? expected : asset.sizeBytes
                        let ratio = total > 0 ? min(1.0, Double(written) / Double(total)) : 0
                        if now - self.lastProgressEmitTime >= 0.08 || written == total {
                            self.lastProgressEmitTime = now
                            self.state = .downloading(release, progress: ratio, bytesWritten: written, totalBytes: total)
                        }
                    }
                }

                defer {
                    try? FileManager.default.removeItem(at: downloadedArchiveURL)
                }

                // Step 1: SHA-256 verification against SHA256SUMS.txt when available
                var checksumVerified = false
                if let checksumURL = release.checksumFileURL {
                    self.state = .verifying(release, stage: "Verifying SHA-256 checksum...")
                    let expectedMap = try await self.fetchSHA256Map(from: checksumURL)
                    if let expectedHash = expectedMap[asset.name] ?? expectedMap[asset.name.lowercased()] {
                        let actualHash = try await Task.detached(priority: .userInitiated) {
                            try Self.computeSHA256(forFileAt: downloadedArchiveURL)
                        }.value
                        guard actualHash.lowercased() == expectedHash.lowercased() else {
                            throw AppUpdateError.checksumMismatch(expected: expectedHash, actual: actualHash)
                        }
                        checksumVerified = true
                    }
                }

                // Step 2: Unpack into staging cache directory
                self.state = .verifying(release, stage: "Extracting Walkman Studio.app...")
                let stagedAppURL = try await Task.detached(priority: .userInitiated) {
                    try Self.extractAndValidateApp(
                        archiveURL: downloadedArchiveURL,
                        archiveKind: asset.archiveKind,
                        expectedVersion: release.version
                    )
                }.value

                self.state = .readyToInstall(release, stagedAppURL: stagedAppURL, checksumVerified: checksumVerified)
            } catch let urlError as URLError where urlError.code == .cancelled {
                self.state = .available(release)
            } catch is CancellationError {
                self.state = .available(release)
            } catch {
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    public func cancelDownload() {
        let releaseToRestore = availableRelease
        cancelActiveDownloadTask()
        if let releaseToRestore {
            state = .available(releaseToRestore)
        } else {
            state = .idle
        }
    }

    private func cancelActiveDownloadTask() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
    }

    private func downloadFile(
        _ url: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        defer {
            activeDownloadSession?.finishTasksAndInvalidate()
            activeDownloadSession = nil
            activeDownloadTask = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = UpdateDownloadDelegate()
            delegate.onProgress = onProgress
            delegate.onCompletion = { result in
                continuation.resume(with: result)
            }

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.activeDownloadSession = session

            var request = URLRequest(url: url)
            request.setValue("WalkmanStudio/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            self.activeDownloadTask = task
            task.resume()
        }
    }

    private func fetchSHA256Map(from url: URL) async throws -> [String: String] {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("WalkmanStudio/\(currentVersionString)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let content = String(data: data, encoding: .utf8) else {
            throw AppUpdateError.invalidResponse("Unable to download SHA256SUMS.txt to verify update integrity.")
        }
        return Self.parseSHA256Sums(content)
    }

    // MARK: - Atomic Install & Relaunch

    public func installAndRelaunch() {
        guard case .readyToInstall(let release, let stagedAppURL, let checksumVerified) = state else { return }
        guard FileManager.default.fileExists(atPath: stagedAppURL.path) else {
            state = .failed(message: "Staged update bundle could not be found. Please download the update again.")
            return
        }

        let target = installTarget
        let destinationURL = target.destinationAppURL
        let parentDir = destinationURL.deletingLastPathComponent()

        state = .installing(release)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await Self.ensureDirectoryExistsIfUserWritable(parentDir)
                let needsElevation = !Self.isDirectInstallWritable(destinationAppURL: destinationURL)
                let scriptURL = try Self.writeDetachedInstallerScript(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    stagedAppURL: stagedAppURL,
                    destinationAppURL: destinationURL,
                    logURL: Self.updaterLogFileURL()
                )

                if needsElevation {
                    // Attempt authorization up front while user is still present, then relaunch.
                    let elevatedCommand = Self.elevatedAppleScriptCommand(scriptURL: scriptURL)
                    let authSucceeded = await Task.detached(priority: .userInitiated) {
                        var errorDict: NSDictionary?
                        let appleScript = NSAppleScript(source: elevatedCommand)
                        let result = appleScript?.executeAndReturnError(&errorDict)
                        return result != nil && errorDict == nil
                    }.value

                    guard authSucceeded else {
                        try? FileManager.default.removeItem(at: scriptURL)
                        self.state = .readyToInstall(release, stagedAppURL: stagedAppURL, checksumVerified: checksumVerified)
                        return
                    }
                    NSApplication.shared.terminate(nil)
                } else {
                    try Self.launchDetachedUpdaterScript(scriptURL: scriptURL)
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                self.state = .failed(message: "Could not install update: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pure & Testable Helpers

    nonisolated public static func hostSupportsArm64() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    nonisolated public static func detectInstalledBuildArchitecture(
        bundle: Bundle = .main,
        hostSupportsArm64: Bool = AppUpdateService.hostSupportsArm64()
    ) -> UpdateBuildArchitecture {
        let archs = bundle.executableArchitectures?.map(\.intValue) ?? []
        let hasArm64 = archs.contains(NSBundleExecutableArchitectureARM64)
        let hasX86_64 = archs.contains(NSBundleExecutableArchitectureX86_64)

        if hasArm64 && hasX86_64 {
            return .universal
        } else if hasArm64 {
            return .arm64
        } else if hasX86_64 {
            return .intel
        }
        return hostSupportsArm64 ? .universal : .intel
    }

    nonisolated public static func evaluateReleasePayload(
        _ payload: GitHubReleasePayload,
        currentVersion: SemanticVersion,
        buildArch: UpdateBuildArchitecture,
        hostSupportsArm64: Bool
    ) -> UpdateReleaseInfo? {
        guard !payload.draft, !payload.prerelease else { return nil }
        guard let remoteVersion = SemanticVersion(payload.tagName),
              remoteVersion > currentVersion else {
            return nil
        }

        let checksumAsset = payload.assets.first {
            $0.name.caseInsensitiveCompare("SHA256SUMS.txt") == .orderedSame
        }
        let checksumURL = checksumAsset.flatMap { URL(string: $0.browserDownloadURL) }

        let selectedAsset = selectUpdateAsset(
            from: payload.assets,
            targetVersion: remoteVersion,
            buildArch: buildArch,
            hostSupportsArm64: hostSupportsArm64
        )

        let publishedDate: Date? = payload.publishedAt.flatMap { str in
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: str)
        }

        let title = (payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Walkman Studio \(payload.tagName)"
        let notes = (payload.body?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "No release notes provided for \(payload.tagName)."
        let htmlURL = URL(string: payload.htmlURL) ?? releasesPageURL

        return UpdateReleaseInfo(
            version: remoteVersion,
            tagName: payload.tagName,
            title: title,
            releaseNotes: notes,
            publishedAt: publishedDate,
            htmlURL: htmlURL,
            preferredAsset: selectedAsset,
            checksumFileURL: checksumURL
        )
    }

    nonisolated public static func selectUpdateAsset(
        from assets: [GitHubAssetPayload],
        targetVersion: SemanticVersion,
        buildArch: UpdateBuildArchitecture,
        hostSupportsArm64: Bool
    ) -> UpdateAsset? {
        // Build ordered preference list without ever picking an arm64-only build on an Intel-only Mac.
        var suffixOrder: [String]
        switch buildArch {
        case .universal:
            suffixOrder = hostSupportsArm64 ? ["universal", "arm64", "intel"] : ["universal", "intel"]
        case .arm64:
            suffixOrder = hostSupportsArm64 ? ["arm64", "universal", "intel"] : ["universal", "intel"]
        case .intel:
            suffixOrder = hostSupportsArm64 ? ["intel", "universal", "arm64"] : ["intel", "universal"]
        }

        func assetIsCompatibleWithHost(_ nameLower: String) -> Bool {
            if !hostSupportsArm64 && nameLower.contains("arm64") && !nameLower.contains("universal") {
                return false
            }
            return true
        }

        func buildUpdateAsset(_ raw: GitHubAssetPayload, kind: UpdateArchiveKind) -> UpdateAsset? {
            guard let url = URL(string: raw.browserDownloadURL) else { return nil }
            let lower = raw.name.lowercased()
            let flavor: String
            if lower.contains("universal") {
                flavor = UpdateBuildArchitecture.universal.shortLabel
            } else if lower.contains("arm64") {
                flavor = UpdateBuildArchitecture.arm64.shortLabel
            } else if lower.contains("intel") || lower.contains("x86_64") {
                flavor = UpdateBuildArchitecture.intel.shortLabel
            } else {
                flavor = "macOS"
            }
            return UpdateAsset(
                name: raw.name,
                downloadURL: url,
                sizeBytes: raw.size,
                archiveKind: kind,
                flavorLabel: flavor
            )
        }

        let zips = assets.filter {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".zip") && assetIsCompatibleWithHost(lower)
        }
        let dmgs = assets.filter {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".dmg") && assetIsCompatibleWithHost(lower)
        }

        // Prefer .zip archives (clean mount-free extraction via ditto), matching exact version+arch first.
        for extKind in [(zips, UpdateArchiveKind.zip), (dmgs, UpdateArchiveKind.dmg)] {
            let pool = extKind.0
            let kind = extKind.1
            let ext = kind.rawValue

            for suffix in suffixOrder {
                let exactName = "Walkman-Studio-\(targetVersion.description)-\(suffix).\(ext)"
                if let match = pool.first(where: { $0.name.caseInsensitiveCompare(exactName) == .orderedSame }) {
                    return buildUpdateAsset(match, kind: kind)
                }
            }
            for suffix in suffixOrder {
                let matchesSuffix: (GitHubAssetPayload) -> Bool = { item in
                    let lower = item.name.lowercased()
                    if suffix == "intel" {
                        return lower.contains("-intel.\(ext)") || lower.contains("intel") || lower.contains("x86_64")
                    }
                    return lower.contains("-\(suffix).\(ext)") || lower.contains(suffix)
                }
                if let match = pool.first(where: matchesSuffix) {
                    return buildUpdateAsset(match, kind: kind)
                }
            }
            if let fallback = pool.first {
                return buildUpdateAsset(fallback, kind: kind)
            }
        }
        return nil
    }

    nonisolated public static func parseSHA256Sums(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var filename = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if filename.hasPrefix("*") {
                filename.removeFirst()
            }
            let base = URL(fileURLWithPath: filename).lastPathComponent
            result[base] = hash
            result[base.lowercased()] = hash
        }
        return result
    }

    nonisolated public static func computeSHA256(forFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while true {
            let chunk = try handle.read(upToCount: chunkSize)
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated public static func resolveInstallDestination(bundleURL: URL) -> UpdateInstallTarget {
        let applicationsTarget = URL(fileURLWithPath: "/Applications/Walkman Studio.app")
        let isBundled = bundleURL.pathExtension.lowercased() == "app"

        guard isBundled else {
            return UpdateInstallTarget(
                destinationAppURL: applicationsTarget,
                isBundledApp: false,
                isAppTranslocated: false,
                isSourceOnReadOnlyVolume: false,
                requiresPrivilegeCheckNote: !isDirectInstallWritable(destinationAppURL: applicationsTarget)
            )
        }

        let path = bundleURL.path
        let isTranslocated = path.contains("/AppTranslocation/")
        let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        let isReadOnlyVolume = values?.volumeIsReadOnly == true

        let targetURL = (isTranslocated || isReadOnlyVolume) ? applicationsTarget : bundleURL
        return UpdateInstallTarget(
            destinationAppURL: targetURL,
            isBundledApp: true,
            isAppTranslocated: isTranslocated,
            isSourceOnReadOnlyVolume: isReadOnlyVolume,
            requiresPrivilegeCheckNote: !isDirectInstallWritable(destinationAppURL: targetURL)
        )
    }

    nonisolated public static func isDirectInstallWritable(destinationAppURL: URL) -> Bool {
        let fm = FileManager.default
        let parent = destinationAppURL.deletingLastPathComponent()
        if fm.fileExists(atPath: destinationAppURL.path) {
            return fm.isWritableFile(atPath: destinationAppURL.path) && fm.isWritableFile(atPath: parent.path)
        }
        return fm.isWritableFile(atPath: parent.path)
    }

    nonisolated private static func ensureDirectoryExistsIfUserWritable(_ dir: URL) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    nonisolated private static func stagingDirectory(for version: SemanticVersion) throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = caches
            .appendingPathComponent(expectedBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("staged", isDirectory: true)
            .appendingPathComponent(version.description, isDirectory: true)

        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func updaterLogFileURL() -> URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let logsDir = library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("WalkmanStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("updater.log")
    }

    nonisolated private static func extractAndValidateApp(
        archiveURL: URL,
        archiveKind: UpdateArchiveKind,
        expectedVersion: SemanticVersion
    ) throws -> URL {
        let stageDir = try stagingDirectory(for: expectedVersion)
        let appDestination = stageDir.appendingPathComponent("Walkman Studio.app", isDirectory: true)

        switch archiveKind {
        case .zip:
            let extractRoot = stageDir.appendingPathComponent("unzipped", isDirectory: true)
            try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)

            let dittoRes = try runSyncProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractRoot.path])
            guard dittoRes.status == 0 else {
                throw AppUpdateError.extractionFailed(dittoRes.stderr.isEmpty ? "ditto exited with code \(dittoRes.status)" : dittoRes.stderr)
            }

            guard let foundApp = findAppBundle(inside: extractRoot) else {
                throw AppUpdateError.extractionFailed("Walkman Studio.app was not found inside the downloaded archive.")
            }
            try FileManager.default.moveItem(at: foundApp, to: appDestination)
            try? FileManager.default.removeItem(at: extractRoot)

        case .dmg:
            let attachRes = try runSyncProcess(
                "/usr/bin/hdiutil",
                arguments: ["attach", archiveURL.path, "-nobrowse", "-readonly", "-plist"]
            )
            guard attachRes.status == 0,
                  let plist = try? PropertyListSerialization.propertyList(from: attachRes.stdoutData, options: [], format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                throw AppUpdateError.extractionFailed("Could not mount downloaded DMG disk image.")
            }
            defer {
                _ = try? runSyncProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
            }

            let mountURL = URL(fileURLWithPath: mountPoint, isDirectory: true)
            guard let foundApp = findAppBundle(inside: mountURL) else {
                throw AppUpdateError.extractionFailed("Walkman Studio.app was not found inside the disk image.")
            }
            let copyRes = try runSyncProcess("/usr/bin/ditto", arguments: [foundApp.path, appDestination.path])
            guard copyRes.status == 0 else {
                throw AppUpdateError.extractionFailed(copyRes.stderr.isEmpty ? "Failed to copy bundle from disk image." : copyRes.stderr)
            }
        }

        // Remove any quarantine extended attributes so macOS never blocks or translocates the new bundle.
        _ = try? runSyncProcess("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appDestination.path])

        // Validate executable, bundle identifier, version metadata, and code signature integrity.
        let executableURL = appDestination.appendingPathComponent("Contents/MacOS/WalkmanStudio")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw AppUpdateError.invalidBundle("WalkmanStudio binary is missing or not executable.")
        }

        guard let stagedBundle = Bundle(url: appDestination),
              let bundleID = stagedBundle.bundleIdentifier,
              bundleID == expectedBundleIdentifier else {
            throw AppUpdateError.invalidBundle("Unexpected bundle identifier in downloaded package.")
        }

        if let stagedVerStr = stagedBundle.infoDictionary?["CFBundleShortVersionString"] as? String,
           let stagedVer = SemanticVersion(stagedVerStr),
           stagedVer < expectedVersion {
            throw AppUpdateError.invalidBundle("Archive claims \(expectedVersion.description) but contains version \(stagedVer.description).")
        }

        let codesignRes = try runSyncProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appDestination.path])
        guard codesignRes.status == 0 else {
            throw AppUpdateError.invalidBundle(codesignRes.stderr.isEmpty ? "Code signature verification failed." : codesignRes.stderr)
        }

        return appDestination
    }

    nonisolated private static func findAppBundle(inside root: URL) -> URL? {
        let direct = root.appendingPathComponent("Walkman Studio.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let itemURL as URL in enumerator {
            if itemURL.pathExtension.lowercased() == "app" {
                return itemURL
            }
        }
        return nil
    }

    // MARK: - Detached Installer Script Builder (Testable)

    nonisolated public static func buildUpdaterScriptBody(
        pid: Int32,
        stagedAppPath: String,
        destinationAppPath: String,
        logPath: String,
        relaunchDelaySeconds: Double = 0.2
    ) -> String {
        let q = shellSingleQuote
        return """
        #!/usr/bin/env bash
        set -euo pipefail

        PID=\(pid)
        STAGED_APP=\(q(stagedAppPath))
        TARGET_APP=\(q(destinationAppPath))
        LOG_FILE=\(q(logPath))
        BACKUP_APP="${TARGET_APP}.update-backup-${PID}"
        SCRIPT_PATH="${BASH_SOURCE[0]}"

        mkdir -p "$(dirname "$LOG_FILE")"
        exec >>"$LOG_FILE" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Walkman Studio updater started (old PID=$PID)"

        # Wait up to 30s for the running Walkman Studio process to terminate cleanly.
        for _ in $(seq 1 300); do
          if ! kill -0 "$PID" 2>/dev/null; then
            break
          fi
          sleep 0.1
        done

        sleep \(relaunchDelaySeconds)
        mkdir -p "$(dirname "$TARGET_APP")"
        rm -rf "$BACKUP_APP"

        if [ -e "$TARGET_APP" ]; then
          mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
          rm -rf "$BACKUP_APP"
          rm -rf "$(dirname "$STAGED_APP")"
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Bundle replaced at $TARGET_APP"
        else
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Bundle copy failed; rolling back"
          rm -rf "$TARGET_APP"
          if [ -e "$BACKUP_APP" ]; then
            mv "$BACKUP_APP" "$TARGET_APP"
          fi
          rm -f "$SCRIPT_PATH"
          exit 1
        fi

        /usr/bin/open -n "$TARGET_APP"
        rm -f "$SCRIPT_PATH"
        """
    }

    private static func writeDetachedInstallerScript(
        pid: Int32,
        stagedAppURL: URL,
        destinationAppURL: URL,
        logURL: URL
    ) throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkman_studio_updater_\(UUID().uuidString).sh")
        let body = buildUpdaterScriptBody(
            pid: pid,
            stagedAppPath: stagedAppURL.path,
            destinationAppPath: destinationAppURL.path,
            logPath: logURL.path
        )
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func launchDetachedUpdaterScript(scriptURL: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = ["/bin/bash", scriptURL.path]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }

    private static func elevatedAppleScriptCommand(scriptURL: URL) -> String {
        let shellCmd = "/usr/bin/nohup /bin/bash \(shellSingleQuote(scriptURL.path)) >/dev/null 2>&1 &"
        let escapedForAppleScript = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedForAppleScript)\" with administrator privileges"
    }

    nonisolated private static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func runSyncProcess(
        _ launchPath: String,
        arguments: [String]
    ) throws -> (status: Int32, stdoutData: Data, stderr: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let stderrText = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (proc.terminationStatus, outData, stderrText)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
