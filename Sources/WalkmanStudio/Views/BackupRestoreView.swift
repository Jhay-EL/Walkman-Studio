import SwiftUI
import AppKit

public struct BackupRestoreView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let tracks: [Track]
    let cachedAlbums: [AlbumItem]
    let deviceInfo: WalkmanDeviceInfo?
    let onRestoreComplete: () -> Void

    fileprivate enum Mode: String, CaseIterable, Identifiable {
        case backup = "Backup Walkman"
        case restore = "Restore to Walkman"
        var id: String { rawValue }
    }

    @State private var selectedMode: Mode = .backup

    // Backup State
    @State private var sourceDriveMount: String = ""
    @State private var selectedScope: BackupScopeType = .full
    @State private var selectedAlbumKeys: Set<String> = []
    @State private var selectedTrackPaths: Set<String> = []
    @State private var sourceTracks: [Track] = []
    @State private var sourceAlbums: [AlbumItem] = []
    @State private var destinations: [BackupDestination] = [
        BackupDestination(
            id: "local_mac",
            type: .local,
            name: "Local Mac Storage",
            path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Walkman Studio Backups").path,
            url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Walkman Studio Backups"),
            isAvailable: true,
            descriptionText: "~/Music/Walkman Studio Backups"
        )
    ]
    @State private var selectedDestinationId: String = "local_mac"
    @State private var isEncrypted: Bool = false
    @State private var passphrase: String = ""
    @State private var confirmPassphrase: String = ""
    @State private var showPassphrase: Bool = false
    @State private var customFolderKey: String = ""
    @State private var estimatedCount: Int = 0
    @State private var estimatedBytes: Int64 = 0

    // In-Flight Backup
    @State private var isBackingUp: Bool = false
    @State private var backupProgress: BackupProgress? = nil
    @State private var backupSuccessURL: URL? = nil
    @State private var backupErrorMessage: String? = nil
    @State private var isBackupSuccessHovered: Bool = false
    @State private var backupSuccessDismissTask: Task<Void, Never>? = nil

    // Scope Pickers State
    @State private var showAlbumPickerSheet: Bool = false
    @State private var showTrackPickerSheet: Bool = false
    @State private var showBackupConfirmSheet: Bool = false
    @State private var showRestoreConfirmSheet: Bool = false
    @State private var albumSearchText: String = ""
    @State private var trackSearchText: String = ""

    // Restore State
    @State private var discoveredBackups: [DiscoveredBackup] = []
    @State private var selectedBackup: DiscoveredBackup? = nil
    @State private var targetDriveMount: String = ""
    @State private var restorePassphrase: String = ""
    @State private var isRestoring: Bool = false
    @State private var restoreProgress: BackupProgress? = nil
    @State private var restoreSuccessResult: RestoreResult? = nil
    @State private var restoreErrorMessage: String? = nil
    @State private var isRestoreSuccessHovered: Bool = false
    @State private var restoreSuccessDismissTask: Task<Void, Never>? = nil

    public init(
        drives: [WalkmanDrive],
        activeDrive: WalkmanDrive?,
        tracks: [Track],
        cachedAlbums: [AlbumItem],
        deviceInfo: WalkmanDeviceInfo?,
        onRestoreComplete: @escaping () -> Void
    ) {
        self.drives = drives
        self.activeDrive = activeDrive
        self.tracks = tracks
        self.cachedAlbums = cachedAlbums
        self.deviceInfo = deviceInfo
        self.onRestoreComplete = onRestoreComplete
        _sourceDriveMount = State(initialValue: activeDrive?.mountPoint ?? drives.first?.mountPoint ?? "")
        _targetDriveMount = State(initialValue: activeDrive?.mountPoint ?? drives.first?.mountPoint ?? "")
    }

    private var currentSourceDrive: WalkmanDrive? {
        drives.first(where: { $0.mountPoint == sourceDriveMount }) ?? activeDrive ?? drives.first
    }

    private var currentTargetDrive: WalkmanDrive? {
        drives.first(where: { $0.mountPoint == targetDriveMount }) ?? activeDrive ?? drives.first
    }

    private var currentDestination: BackupDestination? {
        destinations.first(where: { $0.id == selectedDestinationId }) ?? destinations.first
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private func cleanDriveName(_ drive: WalkmanDrive) -> String {
        var name = drive.name
        name = name.replacingOccurrences(of: " (MicroSD)", with: "")
        name = name.replacingOccurrences(of: " (Internal)", with: "")
        name = name.replacingOccurrences(of: "(MicroSD)", with: "")
        name = name.replacingOccurrences(of: "(Internal)", with: "")
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return drive.type == .internal ? "Internal Flash" : "MicroSD Card"
        }
        return name
    }

    private func recalculateEstimatedScope() {
        guard let drive = currentSourceDrive else {
            self.estimatedCount = 0
            self.estimatedBytes = 0
            return
        }

        let mount = drive.mountPoint
        switch selectedScope {
        case .full:
            var count = 0
            var trackBytes: Int64 = 0
            for tr in sourceTracks where tr.fullPath.hasPrefix(mount) {
                count += 1
                trackBytes += tr.sizeBytes
            }
            self.estimatedCount = count
            self.estimatedBytes = max(trackBytes, drive.usedBytes)

        case .playlists:
            var count = 0
            var trackBytes: Int64 = 0
            for tr in sourceTracks where tr.fullPath.hasPrefix(mount) {
                count += 1
                trackBytes += tr.sizeBytes
            }
            self.estimatedCount = count
            self.estimatedBytes = trackBytes

        case .learning:
            var count = 0
            var bytes: Int64 = 0
            for tr in sourceTracks where tr.fullPath.hasPrefix(mount) && (tr.isLanguageStudy || tr.fullPath.contains("/LEARNING")) {
                count += 1
                bytes += tr.sizeBytes
            }
            self.estimatedCount = count
            self.estimatedBytes = bytes

        case .albums:
            var count = 0
            var bytes: Int64 = 0
            for tr in sourceTracks where tr.fullPath.hasPrefix(mount) {
                let key = "\(tr.album.lowercased())|\(tr.artist.lowercased())"
                if selectedAlbumKeys.contains(key) || selectedAlbumKeys.contains(tr.album.lowercased()) {
                    count += 1
                    bytes += tr.sizeBytes
                }
            }
            self.estimatedCount = count
            self.estimatedBytes = bytes

        case .tracks:
            var count = 0
            var bytes: Int64 = 0
            for tr in sourceTracks where tr.fullPath.hasPrefix(mount) && selectedTrackPaths.contains(tr.fullPath) {
                count += 1
                bytes += tr.sizeBytes
            }
            self.estimatedCount = count
            self.estimatedBytes = bytes
        }
    }

    private func updateSourceDriveTracks(mount: String) {
        guard let drive = drives.first(where: { $0.mountPoint == mount }) ?? currentSourceDrive else {
            self.sourceTracks = []
            self.sourceAlbums = []
            recalculateEstimatedScope()
            return
        }

        // Fast-path: if this drive is activeDrive and ContentView already scanned its tracks, use them immediately
        if drive.mountPoint == activeDrive?.mountPoint && !tracks.isEmpty {
            self.sourceTracks = tracks
            self.sourceAlbums = cachedAlbums
            recalculateEstimatedScope()
        } else {
            // Instant SQLite lookup (< 1ms, zero USB disk I/O)
            let cached = LibraryScanner.shared.loadCachedTracks(forMount: drive.mountPoint)
            if !cached.isEmpty {
                self.sourceTracks = cached
                self.sourceAlbums = AlbumsView.buildAlbums(from: cached)
                recalculateEstimatedScope()
            } else if drive.usedBytes > 0 {
                self.estimatedBytes = drive.usedBytes
            }
        }

        // Background task: reconcile files and count total files (including playlists, .lrc, .jpg)
        refreshSourceDriveAsync(drive: drive)
    }

    private func refreshSourceDriveAsync(drive: WalkmanDrive) {
        let mount = drive.mountPoint
        Task.detached(priority: .userInitiated) {
            var scanDirs: [URL] = [URL(fileURLWithPath: drive.musicDir)]
            let learningURL = URL(fileURLWithPath: drive.learningDir)
            if FileManager.default.fileExists(atPath: learningURL.path) {
                scanDirs.append(learningURL)
            }

            // 1. Fast background scan with LibraryScanner to discover any uncached or modified tracks
            let result = await LibraryScanner.shared.scan(directories: scanDirs)
            let albums = AlbumsView.buildAlbums(from: result.tracks)

            // 2. Count total regular files in /MUSIC and /LEARNING for full library scope accuracy (.m3u8, .lrc, .jpg, etc.)
            var totalFiles = 0
            let fm = FileManager.default
            for dir in scanDirs {
                if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        let name = fileURL.lastPathComponent.lowercased()
                        if name == ".ds_store" || name.hasPrefix("._") || name.hasPrefix(".spotlight") || name.hasPrefix(".trashes") {
                            continue
                        }
                        if name == "devicon.fil" || name == "default-capability.xml" || name.contains("system volume information") {
                            continue
                        }
                        totalFiles += 1
                    }
                }
            }

            let finalFileCount = totalFiles

            await MainActor.run {
                guard self.sourceDriveMount == mount else { return }
                self.sourceTracks = result.tracks
                self.sourceAlbums = albums

                if self.selectedScope == .full {
                    self.estimatedCount = max(result.tracks.count, finalFileCount)
                    let trackBytes = result.tracks.reduce(0) { $0 + $1.sizeBytes }
                    self.estimatedBytes = max(trackBytes, drive.usedBytes)
                } else {
                    self.recalculateEstimatedScope()
                }
            }
        }
    }

    private func refreshDestinationsAsync() {
        let walkmanMounts = Set(drives.map(\.mountPoint))
        let customPath = UserDefaults.standard.string(forKey: "walkman_custom_backup_dest")

        Task.detached(priority: .userInitiated) {
            let detected = BackupRestoreService.shared.detectAvailableDestinations(
                walkmanMountPoints: walkmanMounts,
                customPath: customPath
            )
            let found = BackupRestoreService.shared.discoverBackups(in: detected)

            await MainActor.run {
                self.destinations = detected
                if !detected.contains(where: { $0.id == self.selectedDestinationId }) {
                    if let firstAvail = detected.first(where: { $0.isAvailable }) {
                        self.selectedDestinationId = firstAvail.id
                    } else if let first = detected.first {
                        self.selectedDestinationId = first.id
                    }
                }
                self.discoveredBackups = found
                if self.selectedBackup == nil || !found.contains(where: { $0.url == self.selectedBackup?.url }) {
                    self.selectedBackup = found.first
                }
            }
        }
    }

    private func scheduleBackupSuccessAutoDismiss(seconds: Double = 5.0) {
        backupSuccessDismissTask?.cancel()
        backupSuccessDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if !isBackupSuccessHovered {
                withAnimation(.easeInOut(duration: 0.35)) {
                    backupSuccessURL = nil
                }
            }
        }
    }

    private func scheduleRestoreSuccessAutoDismiss(seconds: Double = 5.0) {
        restoreSuccessDismissTask?.cancel()
        restoreSuccessDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if !isRestoreSuccessHovered {
                withAnimation(.easeInOut(duration: 0.35)) {
                    restoreSuccessResult = nil
                }
            }
        }
    }

    // MARK: - Main Body
    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation & Segmented Bar
            topBar

            Divider()
                .overlay(WalkmanTheme.border)

            // Content Area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if selectedMode == .backup {
                        backupView
                    } else {
                        restoreView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 88)
            }
        }
        .background(WalkmanTheme.background)
        .onAppear {
            if sourceDriveMount.isEmpty, let d = currentSourceDrive {
                sourceDriveMount = d.mountPoint
            }
            if targetDriveMount.isEmpty, let d = currentTargetDrive {
                targetDriveMount = d.mountPoint
            }
            updateSourceDriveTracks(mount: sourceDriveMount)
            refreshDestinationsAsync()
        }
        .onDisappear {
            backupSuccessDismissTask?.cancel()
            restoreSuccessDismissTask?.cancel()
        }
        .onChange(of: selectedScope) { _, _ in
            recalculateEstimatedScope()
        }
        .onChange(of: sourceDriveMount) { _, newMount in
            selectedAlbumKeys.removeAll()
            selectedTrackPaths.removeAll()
            updateSourceDriveTracks(mount: newMount)
        }
        .onChange(of: selectedAlbumKeys) { _, _ in
            recalculateEstimatedScope()
        }
        .onChange(of: selectedTrackPaths) { _, _ in
            recalculateEstimatedScope()
        }
        .sheet(isPresented: $showAlbumPickerSheet) {
            BackupAlbumPickerSheet(
                albums: sourceAlbums,
                selectedAlbumKeys: $selectedAlbumKeys,
                sourceDriveName: currentSourceDrive.map { cleanDriveName($0) } ?? "Sony Walkman",
                onDone: { showAlbumPickerSheet = false }
            )
        }
        .sheet(isPresented: $showTrackPickerSheet) {
            BackupTrackPickerSheet(
                tracks: sourceTracks,
                selectedTrackPaths: $selectedTrackPaths,
                sourceDriveName: currentSourceDrive.map { cleanDriveName($0) } ?? "Sony Walkman",
                onDone: { showTrackPickerSheet = false }
            )
        }
        .sheet(isPresented: $showBackupConfirmSheet) {
            if let source = currentSourceDrive, let dest = currentDestination {
                BackupConfirmationSheet(
                    sourceDrive: source,
                    destination: dest,
                    scopeType: selectedScope,
                    estimatedCount: estimatedCount,
                    estimatedBytes: estimatedBytes,
                    isEncrypted: isEncrypted,
                    onConfirm: {
                        showBackupConfirmSheet = false
                        startBackup()
                    },
                    onCancel: {
                        showBackupConfirmSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $showRestoreConfirmSheet) {
            if let backup = selectedBackup, let target = currentTargetDrive {
                RestoreConfirmationSheet(
                    backup: backup,
                    targetDrive: target,
                    passphraseProvided: !restorePassphrase.isEmpty,
                    onConfirm: {
                        showRestoreConfirmSheet = false
                        startRestore()
                    },
                    onCancel: {
                        showRestoreConfirmSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout
            HStack(spacing: 16) {
                topBarTitleGroup(compactSubtitle: false)
                Spacer(minLength: 12)
                topBarModeSwitcher
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            // Compact/Narrow layout
            VStack(alignment: .leading, spacing: 10) {
                topBarTitleGroup(compactSubtitle: true)
                topBarModeSwitcher
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func topBarTitleGroup(compactSubtitle: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(WalkmanTheme.hiResGoldGradient)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text("Backup & Restore")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(compactSubtitle ? "Safeguard or restore your Walkman library locally or to external storage" : "Safeguard or restore your Walkman library locally to your Mac or direct to an external drive")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
        }
    }

    private var topBarModeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { mode in
                ModeSwitcherTabButton(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMode = mode
                        }
                        if mode == .restore {
                            refreshDestinationsAsync()
                        }
                    }
                )
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - BACKUP VIEW
    private var backupView: some View {
        VStack(spacing: 16) {
            // Section 1: Source Partition
            sourcePartitionCard

            // Section 2: Backup Scope
            backupScopeCard

            // Section 3: Destination Storage
            destinationCard

            // Section 4: Cryptographic Encryption
            encryptionCard

            // Section 5: Progress / Action Panel
            backupActionPanel
        }
    }

    // MARK: - Source Partition Card
    private var sourcePartitionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("1. SOURCE WALKMAN PARTITION", systemImage: "hifispeaker.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let info = deviceInfo {
                        Text(info.displayName)
                            .font(WalkmanFont.subheadlineMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Label("1. SOURCE WALKMAN PARTITION", systemImage: "hifispeaker.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    if let info = deviceInfo {
                        Text(info.displayName)
                            .font(WalkmanFont.subheadlineMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if drives.isEmpty {
                Text("No Walkman drive connected.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(drives) { drive in
                            sourcePartitionDriveButton(drive: drive)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(drives) { drive in
                            sourcePartitionDriveButton(drive: drive)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private func sourcePartitionDriveButton(drive: WalkmanDrive) -> some View {
        let isSelected = currentSourceDrive?.mountPoint == drive.mountPoint
        return Button(action: {
            sourceDriveMount = drive.mountPoint
        }) {
            HStack(spacing: 10) {
                Image(systemName: drive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(cleanDriveName(drive))
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(drive.type == .internal ? "Internal Flash" : "MicroSD Card")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? WalkmanTheme.hiResGold.opacity(0.18) : Color.white.opacity(0.06))
                            .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : .secondary)
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text("\(formatBytes(drive.usedBytes)) used • \(formatBytes(drive.freeBytes)) free")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .fixedSize()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? WalkmanTheme.hiResGold.opacity(0.6) : WalkmanTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Backup Scope Card
    private var backupScopeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("2. BACKUP SCOPE", systemImage: "square.grid.2x2.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    backupScopeSelectionPill
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("2. BACKUP SCOPE", systemImage: "square.grid.2x2.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    backupScopeSelectionPill
                }
            }

            // Scope Options Grid
            VStack(spacing: 8) {
                ForEach(BackupScopeType.allCases) { scope in
                    let isSelected = selectedScope == scope
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedScope = scope
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: scope.icon)
                                .font(.system(size: 15))
                                .frame(width: 24)
                                .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(scope.title)
                                    .font(WalkmanFont.bodyBold)
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .lineLimit(1)

                                Text(scope.subtitle)
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            if scope == .albums {
                                Button(action: { showAlbumPickerSheet = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checklist")
                                        Text(selectedAlbumKeys.isEmpty ? "Select Albums..." : "\(selectedAlbumKeys.count) Albums")
                                    }
                                    .font(WalkmanFont.calloutBold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(.plain)
                            } else if scope == .tracks {
                                Button(action: { showTrackPickerSheet = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "music.note.list")
                                        Text(selectedTrackPaths.isEmpty ? "Select Tracks..." : "\(selectedTrackPaths.count) Tracks")
                                    }
                                    .font(WalkmanFont.calloutBold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(.plain)
                            }

                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
                                .fixedSize()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.015))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSelected ? WalkmanTheme.hiResGold.opacity(0.4) : WalkmanTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private var backupScopeSelectionPill: some View {
        HStack(spacing: 6) {
            Text("\(estimatedCount.formatted()) items selected")
                .font(WalkmanFont.subheadlineBold)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("•")
                .foregroundStyle(.secondary)
            Text(formatBytes(estimatedBytes))
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.hiResGold)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Destination Card
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("3. DESTINATION (LOCAL & EXTERNAL)", systemImage: "internaldrive.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    chooseCustomFolderButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("3. DESTINATION (LOCAL & EXTERNAL)", systemImage: "internaldrive.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    chooseCustomFolderButton
                }
            }

            VStack(spacing: 8) {
                ForEach(destinations) { dest in
                    let isSelected = selectedDestinationId == dest.id
                    HStack(spacing: 12) {
                        Button(action: {
                            selectedDestinationId = dest.id
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: dest.icon)
                                    .font(.system(size: 16))
                                    .frame(width: 24)
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(dest.name)
                                            .font(WalkmanFont.bodyBold)
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                                            .lineLimit(1)

                                        if let free = dest.freeBytes {
                                            Text("\(formatBytes(free)) free")
                                                .font(WalkmanFont.badge)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Color.white.opacity(0.08))
                                                .foregroundStyle(WalkmanTheme.silverMuted)
                                                .clipShape(Capsule())
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                    }

                                    Text(dest.descriptionText)
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 4)

                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
                                    .fixedSize()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.015))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isSelected ? WalkmanTheme.hiResGold.opacity(0.4) : WalkmanTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // If no external drive is plugged in, show helpful connect banner
                if !destinations.contains(where: { $0.type == .externalDrive }) {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 15))
                            .frame(width: 24)
                            .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("External Drive / USB Storage")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)

                            Text("Connect a USB flash drive or external SSD to back up directly to external storage.")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.01))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(WalkmanTheme.border.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private var chooseCustomFolderButton: some View {
        Button(action: { chooseCustomFolder() }) {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.plus")
                Text("Choose Custom Folder...")
            }
            .font(WalkmanFont.calloutMedium)
            .foregroundStyle(WalkmanTheme.silverMuted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Encryption Card
    private var encryptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("4. SECURITY & CRYPTOGRAPHY", systemImage: "lock.shield.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: $isEncrypted.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .tint(WalkmanTheme.hiResGold)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Encrypt Backup Container (AES-256-GCM)")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(isEncrypted ? .white : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("Slow / High Security")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isEncrypted ? WalkmanTheme.hiResGold.opacity(0.2) : Color.white.opacity(0.05))
                        .foregroundStyle(isEncrypted ? WalkmanTheme.hiResGold : .secondary)
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text("Applies 256-bit AES encryption with PBKDF2-HMAC-SHA256 (100,000 rounds) key derivation. Stream hashing across large FLAC audio files is computationally intensive (slower transfer), but completely protects confidential music tracks on local storage or external flash drives.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isEncrypted {
                Divider()
                    .overlay(WalkmanTheme.border)

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WalkmanTheme.hiResGold)
                            .frame(width: 18)

                        if showPassphrase {
                            TextField("Enter Backup Encryption Passphrase", text: $passphrase)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.body)
                        } else {
                            SecureField("Enter Backup Encryption Passphrase", text: $passphrase)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.body)
                        }

                        Button(action: { showPassphrase.toggle() }) {
                            Image(systemName: showPassphrase ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(WalkmanTheme.border, lineWidth: 1)
                    )

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 13))
                            .foregroundStyle(passwordsMatch ? Color.green : WalkmanTheme.silverMuted)
                            .frame(width: 18)

                        if showPassphrase {
                            TextField("Confirm Passphrase", text: $confirmPassphrase)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.body)
                        } else {
                            SecureField("Confirm Passphrase", text: $confirmPassphrase)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.body)
                        }

                        if !confirmPassphrase.isEmpty {
                            Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(passwordsMatch ? Color.green : Color.red)
                        }
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(WalkmanTheme.border, lineWidth: 1)
                    )

                    if !passphrase.isEmpty && !confirmPassphrase.isEmpty && !passwordsMatch {
                        Text("Passphrases do not match.")
                            .font(WalkmanFont.calloutMedium)
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEncrypted ? WalkmanTheme.hiResGold.opacity(0.4) : WalkmanTheme.border, lineWidth: 1)
        )
    }

    private var passwordsMatch: Bool {
        !passphrase.isEmpty && passphrase == confirmPassphrase
    }

    // MARK: - Backup Action Panel
    private var backupActionPanel: some View {
        VStack(spacing: 12) {
            if let err = backupErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.red)
                        .fixedSize()
                    Text(err)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button("Dismiss") { backupErrorMessage = nil }
                        .font(WalkmanFont.calloutMedium)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let successURL = backupSuccessURL {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.green)
                            .fixedSize()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup Completed Successfully!")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("Saved to \(successURL.lastPathComponent)")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 8)

                        backupRevealInFinderButton(url: successURL)
                        backupSuccessDismissButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.green)
                                .fixedSize()

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Backup Completed Successfully!")
                                    .font(WalkmanFont.bodyBold)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text("Saved to \(successURL.lastPathComponent)")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            backupSuccessDismissButton
                        }

                        backupRevealInFinderButton(url: successURL)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
                .onHover { hovering in
                    isBackupSuccessHovered = hovering
                    if hovering {
                        backupSuccessDismissTask?.cancel()
                    } else {
                        scheduleBackupSuccessAutoDismiss(seconds: 5.0)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

            if isBackingUp, let prog = backupProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(prog.phase.rawValue)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(prog.itemsProcessed) of \(prog.totalItems) files (\(Int(prog.fractionCompleted * 100))%)")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    ProgressView(value: prog.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(WalkmanTheme.hiResGold)

                    HStack {
                        Text(prog.currentItemName)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text("\(formatBytes(prog.bytesProcessed)) / \(formatBytes(prog.totalBytes))")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel Backup") {
                            BackupRestoreService.shared.cancel()
                        }
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to Back Up")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("\(estimatedCount) files (\(formatBytes(estimatedBytes))) → \(currentDestination?.name ?? "Destination")")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        backupStartButton(fullWidth: false)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to Back Up")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("\(estimatedCount) files (\(formatBytes(estimatedBytes))) → \(currentDestination?.name ?? "Destination")")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                        }

                        backupStartButton(fullWidth: true)
                    }
                }
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WalkmanTheme.border, lineWidth: 1)
                )
            }
        }
    }

    private func backupRevealInFinderButton(url: URL) -> some View {
        Button(action: {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }) {
            HStack(spacing: 5) {
                Image(systemName: "finder")
                Text("Reveal in Finder")
            }
            .font(WalkmanFont.calloutBold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WalkmanTheme.silverGradient)
            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private var backupSuccessDismissButton: some View {
        Button(action: {
            backupSuccessDismissTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) {
                backupSuccessURL = nil
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .padding(6)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }

    private func backupStartButton(fullWidth: Bool) -> some View {
        Button(action: { showBackupConfirmSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: isEncrypted ? "lock.fill" : "arrow.up.circle.fill")
                Text(isEncrypted ? "Start Encrypted Backup" : "Start Backup")
                    .lineLimit(1)
            }
            .font(WalkmanFont.bodyBold)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(canStartBackup ? WalkmanTheme.hiResGoldGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            .foregroundStyle(canStartBackup ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStartBackup)
    }

    private var canStartBackup: Bool {
        guard let drive = currentSourceDrive, drive.usedBytes > 0 else { return false }
        guard let dest = currentDestination, dest.isAvailable else { return false }
        if isEncrypted && !passwordsMatch { return false }
        if selectedScope == .albums && selectedAlbumKeys.isEmpty { return false }
        if selectedScope == .tracks && selectedTrackPaths.isEmpty { return false }
        if isBackingUp { return false }
        return true
    }

    private func startBackup() {
        guard let source = currentSourceDrive, let dest = currentDestination else { return }
        backupErrorMessage = nil
        backupSuccessDismissTask?.cancel()
        backupSuccessURL = nil
        isBackingUp = true

        let config = BackupScopeConfig(
            type: selectedScope,
            selectedAlbumKeys: selectedAlbumKeys,
            selectedTrackPaths: selectedTrackPaths
        )
        let pass = isEncrypted ? passphrase : nil

        Task {
            do {
                let savedURL = try await BackupRestoreService.shared.performBackup(
                    sourceDrive: source,
                    destination: dest,
                    scope: config,
                    allTracks: sourceTracks,
                    deviceInfo: deviceInfo,
                    isEncrypted: isEncrypted,
                    passphrase: pass
                ) { prog in
                    Task { @MainActor in
                        self.backupProgress = prog
                    }
                }

                await MainActor.run {
                    self.isBackingUp = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.backupSuccessURL = savedURL
                    }
                    self.refreshDestinationsAsync()
                    self.scheduleBackupSuccessAutoDismiss(seconds: 5.0)
                }
            } catch {
                await MainActor.run {
                    self.isBackingUp = false
                    self.backupErrorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - RESTORE VIEW
    private var restoreView: some View {
        VStack(spacing: 16) {
            // Section 1: Discovered Backups List
            discoveredBackupsCard

            // Section 2: Selected Backup Inspection
            if let backup = selectedBackup {
                backupInspectionCard(backup: backup)
            }

            // Section 3: Target Walkman Device
            targetWalkmanCard

            // Section 4: Decryption Password (if encrypted)
            if let backup = selectedBackup, backup.isEncrypted {
                restoreDecryptionCard
            }

            // Section 5: Restore Action Panel
            restoreActionPanel
        }
    }

    // MARK: - Discovered Backups Card
    private var discoveredBackupsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("1. SELECT BACKUP ARCHIVE", systemImage: "clock.arrow.circlepath")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    discoveredBackupsActions
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("1. SELECT BACKUP ARCHIVE", systemImage: "clock.arrow.circlepath")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    discoveredBackupsActions
                }
            }

            if discoveredBackups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 28))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))

                    Text("No Walkman Backups Found")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("No .walkmanbackup or .walkmanbackup.enc archives found in local Mac storage or external drives. Click 'Browse Other Backup...' to select an archive from Finder.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(discoveredBackups) { b in
                        let isSelected = selectedBackup?.url == b.url
                        Button(action: {
                            selectedBackup = b
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: b.isEncrypted ? "lock.doc.fill" : "doc.zipper")
                                    .font(.system(size: 18))
                                    .foregroundStyle(b.isEncrypted ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(b.manifest?.deviceName ?? b.filename)
                                            .font(WalkmanFont.bodyBold)
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
                                            .lineLimit(1)

                                        if b.isEncrypted {
                                            Text("AES-256-GCM")
                                                .font(WalkmanFont.badge)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(WalkmanTheme.hiResGold.opacity(0.2))
                                                .foregroundStyle(WalkmanTheme.hiResGold)
                                                .clipShape(Capsule())
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }

                                        Text(b.destinationType.rawValue)
                                            .font(WalkmanFont.badge)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.white.opacity(0.06))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }

                                    HStack(spacing: 8) {
                                        Text(b.manifest?.scopeSummary ?? (b.isEncrypted ? "Encrypted Archive" : "Walkman Bundle"))
                                            .font(WalkmanFont.calloutMedium)
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                            .lineLimit(1)

                                        Text("•")
                                            .foregroundStyle(.secondary)

                                        Text(b.dateModified.formatted(date: .abbreviated, time: .shortened))
                                            .font(WalkmanFont.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Text("•")
                                            .foregroundStyle(.secondary)

                                        Text(formatBytes(b.sizeBytes))
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 4)

                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
                                    .fixedSize()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.07) : Color.white.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isSelected ? WalkmanTheme.hiResGold.opacity(0.5) : WalkmanTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private var discoveredBackupsActions: some View {
        HStack(spacing: 8) {
            Button(action: { browseOtherBackupFile() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                    Text("Browse Other Backup...")
                }
                .font(WalkmanFont.calloutMedium)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)

            Button(action: { refreshDestinationsAsync() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .buttonStyle(.plain)
            .help("Rescan backup destinations")
        }
    }

    // MARK: - Selected Backup Inspection Card
    private func backupInspectionCard(backup: DiscoveredBackup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("BACKUP METADATA & CONTENTS", systemImage: "info.circle.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(backup.url.lastPathComponent)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Label("BACKUP METADATA & CONTENTS", systemImage: "info.circle.fill")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .lineLimit(1)

                    Text(backup.url.lastPathComponent)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            ViewThatFits(in: .horizontal) {
                // Wide: 4-column horizontal stack
                HStack(spacing: 20) {
                    inspectionStatItem(title: "Source Model", value: backup.manifest?.deviceName ?? "Sony Walkman", isMono: false, isGold: false)
                    Divider().frame(height: 32).overlay(WalkmanTheme.border)
                    inspectionStatItem(title: "Created", value: backup.dateModified.formatted(date: .abbreviated, time: .shortened), isMono: false, isGold: false)
                    Divider().frame(height: 32).overlay(WalkmanTheme.border)
                    inspectionStatItem(title: "Total Size", value: formatBytes(backup.sizeBytes), isMono: true, isGold: true)
                    Divider().frame(height: 32).overlay(WalkmanTheme.border)
                    inspectionStatItem(title: "Files", value: backup.manifest != nil ? "\(backup.manifest!.totalFiles) items" : "Protected", isMono: false, isGold: false)
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Narrow: 2x2 grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    inspectionStatItem(title: "Source Model", value: backup.manifest?.deviceName ?? "Sony Walkman", isMono: false, isGold: false)
                    inspectionStatItem(title: "Created", value: backup.dateModified.formatted(date: .abbreviated, time: .shortened), isMono: false, isGold: false)
                    inspectionStatItem(title: "Total Size", value: formatBytes(backup.sizeBytes), isMono: true, isGold: true)
                    inspectionStatItem(title: "Files", value: backup.manifest != nil ? "\(backup.manifest!.totalFiles) items" : "Protected", isMono: false, isGold: false)
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private func inspectionStatItem(title: String, value: String, isMono: Bool, isGold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(WalkmanFont.callout)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .lineLimit(1)
            Text(value)
                .font(isMono ? WalkmanFont.mono : WalkmanFont.bodyBold)
                .foregroundStyle(isGold ? WalkmanTheme.hiResGold : .white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Target Walkman Card
    private var targetWalkmanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2. TARGET WALKMAN RESTORE PARTITION", systemImage: "hifispeaker.fill")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(WalkmanTheme.hiResGold)
                .lineLimit(1)

            if drives.isEmpty {
                Text("No target Walkman connected to restore into.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(drives) { drive in
                            targetPartitionDriveButton(drive: drive)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(drives) { drive in
                            targetPartitionDriveButton(drive: drive)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    private func targetPartitionDriveButton(drive: WalkmanDrive) -> some View {
        let isSelected = currentTargetDrive?.mountPoint == drive.mountPoint
        return Button(action: {
            targetDriveMount = drive.mountPoint
        }) {
            HStack(spacing: 10) {
                Image(systemName: drive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(cleanDriveName(drive))
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(drive.type == .internal ? "Internal Flash" : "MicroSD Card")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? WalkmanTheme.hiResGold.opacity(0.18) : Color.white.opacity(0.06))
                            .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : .secondary)
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text("\(formatBytes(drive.freeBytes)) available")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .fixedSize()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? WalkmanTheme.hiResGold.opacity(0.6) : WalkmanTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore Decryption Card
    private var restoreDecryptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3. DECRYPTION PASSPHRASE", systemImage: "key.fill")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(WalkmanTheme.hiResGold)

            Text("This backup is encrypted with AES-256-GCM. Enter the secret passphrase set during backup to authenticate and unpack your audio files.")
                .font(WalkmanFont.callout)
                .foregroundStyle(WalkmanTheme.silverMuted)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .frame(width: 18)

                SecureField("Enter Decryption Passphrase", text: $restorePassphrase)
                    .textFieldStyle(.plain)
                    .font(WalkmanFont.body)
            }
            .padding(10)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WalkmanTheme.border, lineWidth: 1)
            )
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Restore Action Panel
    private var restoreActionPanel: some View {
        VStack(spacing: 12) {
            if let err = restoreErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.red)
                        .fixedSize()
                    Text(err)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button("Dismiss") { restoreErrorMessage = nil }
                        .font(WalkmanFont.calloutMedium)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let res = restoreSuccessResult {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.green)
                            .fixedSize()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Completed Successfully!")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("Restored \(res.totalFilesRestored) files (\(formatBytes(res.totalBytesRestored))) to Walkman. Ghost files purged & database ready.")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        restoreSuccessDismissButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.green)
                                .fixedSize()

                            Text("Restore Completed Successfully!")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer()

                            restoreSuccessDismissButton
                        }

                        Text("Restored \(res.totalFilesRestored) files (\(formatBytes(res.totalBytesRestored))) to Walkman. Ghost files purged & database ready.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
                .onHover { hovering in
                    isRestoreSuccessHovered = hovering
                    if hovering {
                        restoreSuccessDismissTask?.cancel()
                    } else {
                        scheduleRestoreSuccessAutoDismiss(seconds: 5.0)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }

            if isRestoring, let prog = restoreProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(prog.phase.rawValue)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(prog.itemsProcessed) of \(prog.totalItems) files (\(Int(prog.fractionCompleted * 100))%)")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    ProgressView(value: prog.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(WalkmanTheme.hiResGold)

                    HStack {
                        Text(prog.currentItemName)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text("\(formatBytes(prog.bytesProcessed)) / \(formatBytes(prog.totalBytes))")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel Restore") {
                            BackupRestoreService.shared.cancel()
                        }
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                let targetName = currentTargetDrive != nil ? cleanDriveName(currentTargetDrive!) : "Walkman"
                ViewThatFits(in: .horizontal) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore into \(targetName)")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("Reconstructs clean /MUSIC and /LEARNING directory trees without ghost files.")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        restoreStartButton(fullWidth: false)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore into \(targetName)")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("Reconstructs clean /MUSIC and /LEARNING directory trees without ghost files.")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                        }

                        restoreStartButton(fullWidth: true)
                    }
                }
                .padding(14)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WalkmanTheme.border, lineWidth: 1)
                )
            }
        }
    }

    private var restoreSuccessDismissButton: some View {
        Button(action: {
            restoreSuccessDismissTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) {
                restoreSuccessResult = nil
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .padding(6)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }

    private func restoreStartButton(fullWidth: Bool) -> some View {
        Button(action: { showRestoreConfirmSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                Text("Restore to Walkman")
                    .lineLimit(1)
            }
            .font(WalkmanFont.bodyBold)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(canStartRestore ? WalkmanTheme.hiResGoldGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            .foregroundStyle(canStartRestore ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canStartRestore)
    }

    private var canStartRestore: Bool {
        guard let _ = selectedBackup else { return false }
        guard let _ = currentTargetDrive else { return false }
        if let b = selectedBackup, b.isEncrypted && restorePassphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if isRestoring { return false }
        return true
    }

    private func startRestore() {
        guard let backup = selectedBackup, let target = currentTargetDrive else { return }
        restoreErrorMessage = nil
        restoreSuccessDismissTask?.cancel()
        restoreSuccessResult = nil
        isRestoring = true

        let pass = backup.isEncrypted ? restorePassphrase : nil

        Task {
            do {
                let result = try await BackupRestoreService.shared.performRestore(
                    backupURL: backup.url,
                    targetDrive: target,
                    passphrase: pass
                ) { prog in
                    Task { @MainActor in
                        self.restoreProgress = prog
                    }
                }

                await MainActor.run {
                    self.isRestoring = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.restoreSuccessResult = result
                    }
                    self.onRestoreComplete()
                    self.scheduleRestoreSuccessAutoDismiss(seconds: 5.0)
                }
            } catch {
                await MainActor.run {
                    self.isRestoring = false
                    self.restoreErrorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Custom Folders & Open Panels
    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Backup Folder"
        panel.message = "Choose a local folder or external drive directory for Walkman Studio backups."

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "walkman_custom_backup_dest")
            refreshDestinationsAsync()
            selectedDestinationId = "custom_dir"
        }
    }

    private func browseOtherBackupFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Backup"
        panel.message = "Select a .walkmanbackup bundle or .walkmanbackup.enc encrypted archive to restore."

        if panel.runModal() == .OK, let url = panel.url {
            let isEnc = url.pathExtension.lowercased() == "enc" || url.lastPathComponent.hasSuffix(".enc")
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let size = attrs?[.size] as? Int64 ?? 0

            let manualBackup = DiscoveredBackup(
                url: url,
                filename: url.lastPathComponent,
                destinationType: .custom,
                isEncrypted: isEnc,
                dateModified: modDate,
                sizeBytes: size
            )
            self.discoveredBackups.insert(manualBackup, at: 0)
            self.selectedBackup = manualBackup
        }
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS BACKUP ALBUM PICKER SHEET
// -----------------------------------------------------------------------------
private struct BackupAlbumPickerSheet: View {
    let albums: [AlbumItem]
    @Binding var selectedAlbumKeys: Set<String>
    let sourceDriveName: String
    let onDone: () -> Void

    @State private var searchText: String = ""
    @State private var selectedFilter: AlbumFilter = .all
    @Namespace private var filterNamespace
    @State private var isDoneHovered = false
    @State private var isCancelHovered = false

    private enum AlbumFilter: String, CaseIterable, Identifiable {
        case all = "All Albums"
        case selected = "Selected"
        case hiRes = "Hi-Res Only"
        var id: String { rawValue }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private var filteredAlbums: [AlbumItem] {
        albums.filter { alb in
            if !searchText.isEmpty {
                let matchesName = alb.name.localizedCaseInsensitiveContains(searchText)
                let matchesArtist = alb.artist.localizedCaseInsensitiveContains(searchText)
                if !matchesName && !matchesArtist { return false }
            }
            switch selectedFilter {
            case .all:
                return true
            case .selected:
                return selectedAlbumKeys.contains(alb.id)
            case .hiRes:
                return alb.isHiRes
            }
        }
    }

    private var totalSelectedTracks: Int {
        var count = 0
        for alb in albums where selectedAlbumKeys.contains(alb.id) {
            count += alb.trackCount
        }
        return count
    }

    private var totalSelectedBytes: Int64 {
        var bytes: Int64 = 0
        for alb in albums where selectedAlbumKeys.contains(alb.id) {
            for tr in alb.tracks {
                bytes += tr.sizeBytes
            }
        }
        return bytes
    }

    private func badgeCount(for filter: AlbumFilter) -> String {
        switch filter {
        case .all:
            return "\(albums.count)"
        case .selected:
            return "\(selectedAlbumKeys.count)"
        case .hiRes:
            let count = albums.filter(\.isHiRes).count
            return "\(count)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onDone)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WalkmanTheme.hiResGold.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WalkmanTheme.hiResGoldGradient)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.85)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Albums to Back Up")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("\(sourceDriveName) • \(selectedAlbumKeys.count) of \(albums.count) albums selected • \(totalSelectedTracks) tracks (\(formatBytes(totalSelectedBytes)))")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Search & Filter Toolbar
            HStack(spacing: 10) {
                // Liquid Glass Search Input
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    TextField("Search Albums or Artists...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.body)
                        .foregroundStyle(.white)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(searchText.isEmpty ? Color.white.opacity(0.12) : Color.white.opacity(0.28), lineWidth: 0.85)
                )

                // Segmented Filter Pills
                HStack(spacing: 4) {
                    ForEach(AlbumFilter.allCases) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedFilter = filter
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text(filter.rawValue)
                                    .font(WalkmanFont.calloutBold)
                                    .lineLimit(1)

                                Text(badgeCount(for: filter))
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(selectedFilter == filter ? Color.white : WalkmanTheme.silverMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(selectedFilter == filter ? 0.22 : 0.08))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if selectedFilter == filter {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.white.opacity(0.16))
                                            .matchedGeometryEffect(id: "albumFilterHighlight", in: filterNamespace)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(Color.white.opacity(0.32), lineWidth: 0.85)
                                            )
                                    }
                                }
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .fixedSize(horizontal: true, vertical: false)

                // Quick Select / Clear Actions
                Button(action: {
                    for alb in filteredAlbums {
                        selectedAlbumKeys.insert(alb.id)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 11))
                        Text("Select All")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silver)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    selectedAlbumKeys.removeAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.square")
                            .font(.system(size: 11))
                        Text("Clear")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Album List View
            if filteredAlbums.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 44))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))
                    Text("No Albums Found")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    Text("Try adjusting your search query or filter selection.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredAlbums) { alb in
                            AlbumPickerRow(
                                album: alb,
                                isChecked: selectedAlbumKeys.contains(alb.id),
                                onToggle: {
                                    if selectedAlbumKeys.contains(alb.id) {
                                        selectedAlbumKeys.remove(alb.id)
                                    } else {
                                        selectedAlbumKeys.insert(alb.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Action Bar
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedAlbumKeys.count) Albums Selected")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)

                    Text("\(totalSelectedTracks) tracks • \(formatBytes(totalSelectedBytes)) staging footprint")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()

                Button(action: onDone) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(isCancelHovered ? 0.09 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.18 : 0.09), lineWidth: 0.8)
                        )
                        .scaleEffect(isCancelHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isCancelHovered = $0 }

                Button(action: onDone) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(selectedAlbumKeys.isEmpty ? "Done" : "Apply (\(selectedAlbumKeys.count) Albums)")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(isDoneHovered ? 0.35 : 0.18), radius: isDoneHovered ? 6 : 3, y: isDoneHovered ? 3 : 1)
                    .scaleEffect(isDoneHovered ? 1.025 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isDoneHovered = $0 }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 820, height: 720)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 12)
    }
}

private struct AlbumPickerRow: View {
    let album: AlbumItem
    let isChecked: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private var albumBytes: Int64 {
        album.tracks.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Tactile checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isChecked ? WalkmanTheme.hiResGold : Color.white.opacity(0.08))
                        .frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isChecked ? WalkmanTheme.hiResGoldLight : Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                }

                // Artwork Thumbnail
                Group {
                    if let rep = album.representativeTrack {
                        TrackCoverThumbnail(track: rep, size: 44)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    } else {
                        ZStack {
                            Color.white.opacity(0.06)
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(album.artist) • \(album.trackCount) tracks")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if album.isHiRes {
                    Text("Hi-Res Audio")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGold.opacity(0.20))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.8)
                        )
                }

                Text(album.primaryFormat)
                    .font(WalkmanFont.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .clipShape(Capsule())

                Text(formatBytes(albumBytes))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isChecked ? Color.white.opacity(0.07) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.015)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isChecked ? WalkmanTheme.hiResGold.opacity(0.35) : (isHovered ? Color.white.opacity(0.15) : WalkmanTheme.border), lineWidth: 0.85)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS BACKUP TRACK PICKER SHEET
// -----------------------------------------------------------------------------
private struct BackupTrackPickerSheet: View {
    let tracks: [Track]
    @Binding var selectedTrackPaths: Set<String>
    let sourceDriveName: String
    let onDone: () -> Void

    @State private var searchText: String = ""
    @State private var selectedFilter: TrackFilter = .all
    @Namespace private var filterNamespace
    @State private var isDoneHovered = false
    @State private var isCancelHovered = false

    private enum TrackFilter: String, CaseIterable, Identifiable {
        case all = "All Tracks"
        case selected = "Selected"
        case hiRes = "Hi-Res Only"
        var id: String { rawValue }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private var filteredTracks: [Track] {
        tracks.filter { tr in
            if !searchText.isEmpty {
                let matchesTitle = tr.title.localizedCaseInsensitiveContains(searchText)
                let matchesArtist = tr.artist.localizedCaseInsensitiveContains(searchText)
                let matchesAlbum = tr.album.localizedCaseInsensitiveContains(searchText)
                let matchesFormat = tr.format.localizedCaseInsensitiveContains(searchText)
                if !matchesTitle && !matchesArtist && !matchesAlbum && !matchesFormat {
                    return false
                }
            }
            let isHiRes = tr.bitsPerSample > 16 || tr.sampleRate > 48000
            switch selectedFilter {
            case .all:
                return true
            case .selected:
                return selectedTrackPaths.contains(tr.fullPath)
            case .hiRes:
                return isHiRes
            }
        }
    }

    private var totalSelectedBytes: Int64 {
        var bytes: Int64 = 0
        for tr in tracks where selectedTrackPaths.contains(tr.fullPath) {
            bytes += tr.sizeBytes
        }
        return bytes
    }

    private func badgeCount(for filter: TrackFilter) -> String {
        switch filter {
        case .all:
            return "\(tracks.count)"
        case .selected:
            return "\(selectedTrackPaths.count)"
        case .hiRes:
            let count = tracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }.count
            return "\(count)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onDone)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WalkmanTheme.hiResGold.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 20))
                        .foregroundStyle(WalkmanTheme.hiResGoldGradient)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.85)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Tracks to Back Up")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("\(sourceDriveName) • \(selectedTrackPaths.count) of \(tracks.count) tracks selected • \(formatBytes(totalSelectedBytes))")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Search & Filter Toolbar
            HStack(spacing: 10) {
                // Liquid Glass Search Input
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverMuted)

                    TextField("Search Tracks, Artists, or Albums...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.body)
                        .foregroundStyle(.white)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(searchText.isEmpty ? Color.white.opacity(0.12) : Color.white.opacity(0.28), lineWidth: 0.85)
                )

                // Segmented Filter Pills
                HStack(spacing: 4) {
                    ForEach(TrackFilter.allCases) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedFilter = filter
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text(filter.rawValue)
                                    .font(WalkmanFont.calloutBold)
                                    .lineLimit(1)

                                Text(badgeCount(for: filter))
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(selectedFilter == filter ? Color.white : WalkmanTheme.silverMuted)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(selectedFilter == filter ? 0.22 : 0.08))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if selectedFilter == filter {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.white.opacity(0.16))
                                            .matchedGeometryEffect(id: "trackFilterHighlight", in: filterNamespace)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(Color.white.opacity(0.32), lineWidth: 0.85)
                                            )
                                    }
                                }
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .fixedSize(horizontal: true, vertical: false)

                // Quick Actions
                Button(action: {
                    for tr in filteredTracks {
                        selectedTrackPaths.insert(tr.fullPath)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.square")
                            .font(.system(size: 11))
                        Text("Select All")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silver)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    selectedTrackPaths.removeAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.square")
                            .font(.system(size: 11))
                        Text("Clear")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Track List View
            if filteredTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 44))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))
                    Text("No Tracks Found")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    Text("Try adjusting your search query or filter selection.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredTracks) { tr in
                            TrackPickerRow(
                                track: tr,
                                isChecked: selectedTrackPaths.contains(tr.fullPath),
                                onToggle: {
                                    if selectedTrackPaths.contains(tr.fullPath) {
                                        selectedTrackPaths.remove(tr.fullPath)
                                    } else {
                                        selectedTrackPaths.insert(tr.fullPath)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Action Bar
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedTrackPaths.count) Tracks Selected")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)

                    Text("\(formatBytes(totalSelectedBytes)) staging footprint")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()

                Button(action: onDone) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(isCancelHovered ? 0.09 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.18 : 0.09), lineWidth: 0.8)
                        )
                        .scaleEffect(isCancelHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isCancelHovered = $0 }

                Button(action: onDone) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(selectedTrackPaths.isEmpty ? "Done" : "Apply (\(selectedTrackPaths.count) Tracks)")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(isDoneHovered ? 0.35 : 0.18), radius: isDoneHovered ? 6 : 3, y: isDoneHovered ? 3 : 1)
                    .scaleEffect(isDoneHovered ? 1.025 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isDoneHovered = $0 }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 860, height: 720)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 12)
    }
}

private struct TrackPickerRow: View {
    let track: Track
    let isChecked: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private func formatDuration(_ sec: Double) -> String {
        let s = Int(sec)
        let m = s / 60
        let rem = s % 60
        return String(format: "%d:%02d", m, rem)
    }

    private var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Tactile checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isChecked ? WalkmanTheme.hiResGold : Color.white.opacity(0.08))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isChecked ? WalkmanTheme.hiResGoldLight : Color.white.opacity(0.22), lineWidth: 1)
                        .frame(width: 20, height: 20)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title.isEmpty ? track.filename : track.title)
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(track.primaryArtist) — \(track.album)")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isHiRes {
                    Text("Hi-Res • \(track.format)")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(WalkmanTheme.hiResGold.opacity(0.20))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.40), lineWidth: 0.8)
                        )
                } else {
                    Text(track.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .clipShape(Capsule())
                }

                Text(formatDuration(track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 48, alignment: .trailing)

                Text(formatBytes(track.sizeBytes))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isChecked ? Color.white.opacity(0.07) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.015)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isChecked ? WalkmanTheme.hiResGold.opacity(0.35) : (isHovered ? Color.white.opacity(0.14) : WalkmanTheme.border), lineWidth: 0.85)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isHovered ? 1.008 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS BACKUP CONFIRMATION SHEET
// -----------------------------------------------------------------------------
private struct BackupConfirmationSheet: View {
    let sourceDrive: WalkmanDrive
    let destination: BackupDestination
    let scopeType: BackupScopeType
    let estimatedCount: Int
    let estimatedBytes: Int64
    let isEncrypted: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmHovered = false
    @State private var isCancelHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private func cleanDriveName(_ drive: WalkmanDrive) -> String {
        var name = drive.name
        name = name.replacingOccurrences(of: " (MicroSD)", with: "")
        name = name.replacingOccurrences(of: " (Internal)", with: "")
        name = name.replacingOccurrences(of: "(MicroSD)", with: "")
        name = name.replacingOccurrences(of: "(Internal)", with: "")
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return drive.type == .internal ? "Internal Flash" : "MicroSD Card"
        }
        return name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WalkmanTheme.hiResGold.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WalkmanTheme.hiResGoldGradient)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.85)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Walkman Backup")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("Verify backup scope, storage payload, and destination parameters")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Body Overview Cards
            ScrollView {
                VStack(spacing: 14) {
                    sourcePartitionCard
                    destinationCard
                    scopePayloadGrid
                    securityChecklistCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Action Bar
            HStack(spacing: 14) {
                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(isCancelHovered ? 0.09 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.18 : 0.09), lineWidth: 0.8)
                        )
                        .scaleEffect(isCancelHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isCancelHovered = $0 }

                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        Image(systemName: isEncrypted ? "lock.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(isEncrypted ? "Start Encrypted Backup" : "Start Backup")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.18), radius: isConfirmHovered ? 6 : 3, y: isConfirmHovered ? 3 : 1)
                    .scaleEffect(isConfirmHovered ? 1.025 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isConfirmHovered = $0 }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 680, height: 580)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 12)
    }

    private var sourcePartitionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceDrive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                .font(.system(size: 20))
                .foregroundStyle(WalkmanTheme.hiResGold)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Source Walkman Partition")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text(cleanDriveName(sourceDrive))
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.white)

                Text(sourceDrive.mountPoint)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(sourceDrive.type == .internal ? "Internal Flash" : "MicroSD Card")
                    .font(WalkmanFont.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silver)
                    .clipShape(Capsule())

                Text("\(formatBytes(sourceDrive.usedBytes)) used")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }

    private var destinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: destination.type == .local ? "laptopcomputer" : "externaldrive.fill")
                .font(.system(size: 20))
                .foregroundStyle(WalkmanTheme.silver)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Backup Target Destination")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text(destination.name)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.white)

                Text(destination.descriptionText)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(destination.type == .local ? "Local Mac" : "External SSD")
                .font(WalkmanFont.badge)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silver)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }

    private var scopePayloadGrid: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backup Scope")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                HStack(spacing: 6) {
                    Image(systemName: scopeType.icon)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                    Text(scopeType.title)
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated Payload")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                HStack(spacing: 6) {
                    Text("\(estimatedCount.formatted()) files")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(.white)
                    Text("•")
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text(formatBytes(estimatedBytes))
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
            )
        }
    }

    private var securityChecklistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isEncrypted ? "lock.shield.fill" : "shield.slash")
                    .foregroundStyle(isEncrypted ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)
                Text(isEncrypted ? "AES-256-GCM Encrypted Container (PBKDF2 Key Derivation)" : "Standard Unencrypted Container")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 16) {
                Label("ID3v2.3 & Vorbis Tags Preserved", systemImage: "checkmark.circle.fill")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Label("Companion .LRC Lyrics Included", systemImage: "checkmark.circle.fill")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Label("AppleDouble Cleaned", systemImage: "checkmark.circle.fill")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.85)
        )
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS RESTORE CONFIRMATION SHEET
// -----------------------------------------------------------------------------
private struct RestoreConfirmationSheet: View {
    let backup: DiscoveredBackup
    let targetDrive: WalkmanDrive
    let passphraseProvided: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmHovered = false
    @State private var isCancelHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    private func cleanDriveName(_ drive: WalkmanDrive) -> String {
        var name = drive.name
        name = name.replacingOccurrences(of: " (MicroSD)", with: "")
        name = name.replacingOccurrences(of: " (Internal)", with: "")
        name = name.replacingOccurrences(of: "(MicroSD)", with: "")
        name = name.replacingOccurrences(of: "(Internal)", with: "")
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return drive.type == .internal ? "Internal Flash" : "MicroSD Card"
        }
        return name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WalkmanTheme.hiResGold.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WalkmanTheme.hiResGoldGradient)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WalkmanTheme.hiResGold.opacity(0.35), lineWidth: 0.85)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Library Restore")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("Verify source archive parameters and target Sony Walkman drive")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Body Overview Cards
            ScrollView {
                VStack(spacing: 14) {
                    archiveCard
                    targetDeviceCard
                    restorationGrid
                    noticeCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer Action Bar
            HStack(spacing: 14) {
                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(isCancelHovered ? 0.09 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.18 : 0.09), lineWidth: 0.8)
                        )
                        .scaleEffect(isCancelHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isCancelHovered = $0 }

                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Restore Walkman Library")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(WalkmanTheme.hiResGoldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.18), radius: isConfirmHovered ? 6 : 3, y: isConfirmHovered ? 3 : 1)
                    .scaleEffect(isConfirmHovered ? 1.025 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { isConfirmHovered = $0 }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 680, height: 580)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 12)
    }

    private var archiveCard: some View {
        HStack(spacing: 12) {
            Image(systemName: backup.isEncrypted ? "lock.doc.fill" : "doc.zipper")
                .font(.system(size: 20))
                .foregroundStyle(backup.isEncrypted ? WalkmanTheme.hiResGold : WalkmanTheme.silver)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Source Backup Archive")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text(backup.filename)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Modified \(backup.dateModified.formatted(date: .abbreviated, time: .shortened))")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(backup.isEncrypted ? "Encrypted" : "Standard")
                    .font(WalkmanFont.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(backup.isEncrypted ? WalkmanTheme.hiResGold : WalkmanTheme.silver)
                    .clipShape(Capsule())

                Text(formatBytes(backup.sizeBytes))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }

    private var targetDeviceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: targetDrive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                .font(.system(size: 20))
                .foregroundStyle(WalkmanTheme.hiResGold)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Target Walkman Destination")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text(cleanDriveName(targetDrive))
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.white)

                Text(targetDrive.mountPoint)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatBytes(targetDrive.freeBytes)) free")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Text("of \(formatBytes(targetDrive.totalBytes)) total")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }

    private var restorationGrid: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restoration Target")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(WalkmanTheme.hiResGold)
                    Text("/MUSIC & /LEARNING Roots")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Integrity Protocol")
                    .font(WalkmanFont.subheadlineBold)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                    Text("Safe Non-Destructive Sync")
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
            )
        }
    }

    private var noticeCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(WalkmanTheme.hiResGold)

            Text("Restoration unpacks track files, companion synchronized .LRC lyrics, and .M3U8 playlists directly to your Sony Walkman storage. Existing non-conflicting tracks are safely retained.")
                .font(WalkmanFont.callout)
                .foregroundStyle(WalkmanTheme.silverMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.85)
        )
    }
}

// -----------------------------------------------------------------------------
// REUSABLE SHEET CLOSE BUTTON
// -----------------------------------------------------------------------------
private struct SheetCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovered ? .white : WalkmanTheme.silverMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isHovered ? Color.white.opacity(0.30) : Color.white.opacity(0.12),
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
    }
}

// -----------------------------------------------------------------------------
// MODE SWITCHER TAB BUTTON (ROUNDED CLICK BOX WITH HOVER EFFECT)
// -----------------------------------------------------------------------------
private struct ModeSwitcherTabButton: View {
    let mode: BackupRestoreView.Mode
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: mode == .backup ? "arrow.up.doc.fill" : "arrow.down.doc.fill")
                    .font(.system(size: 11))
                Text(mode.rawValue)
                    .font(WalkmanFont.calloutBold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.001)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.30) : (isHovered ? Color.white.opacity(0.18) : Color.clear),
                        lineWidth: 0.8
                    )
            )
            .foregroundStyle(isSelected ? .white : (isHovered ? .white : .secondary))
            .scaleEffect(isHovered ? 1.025 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
