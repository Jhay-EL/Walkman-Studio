import SwiftUI
import AppKit

public struct BackupRestoreView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let tracks: [Track]
    let cachedAlbums: [AlbumItem]
    let deviceInfo: WalkmanDeviceInfo?
    let onRestoreComplete: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
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

    // Scope Pickers State
    @State private var showAlbumPickerSheet: Bool = false
    @State private var showTrackPickerSheet: Bool = false
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
                .padding(18)
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
            albumPickerSheet
        }
        .sheet(isPresented: $showTrackPickerSheet) {
            trackPickerSheet
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WalkmanTheme.hiResGoldGradient)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Backup & Restore")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("Safeguard or restore your Walkman library locally to your Mac or direct to an external drive")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }

            Spacer()

            // Segmented Mode Switcher
            HStack(spacing: 4) {
                ForEach(Mode.allCases) { mode in
                    modeSwitcherButton(for: mode)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(WalkmanTheme.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func modeSwitcherButton(for mode: Mode) -> some View {
        let isSelected = selectedMode == mode
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMode = mode
            }
            if mode == .restore {
                refreshDestinationsAsync()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode == .backup ? "arrow.up.doc.fill" : "arrow.down.doc.fill")
                    .font(.system(size: 11))
                Text(mode.rawValue)
                    .font(WalkmanFont.calloutBold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
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
            HStack {
                Label("1. SOURCE WALKMAN PARTITION", systemImage: "hifispeaker.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                if let info = deviceInfo {
                    Text(info.displayName)
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(.secondary)
                }
            }

            if drives.isEmpty {
                Text("No Walkman drive connected.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(drives) { drive in
                        let isSelected = currentSourceDrive?.mountPoint == drive.mountPoint
                        Button(action: {
                            sourceDriveMount = drive.mountPoint
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: drive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(drive.name)
                                            .font(WalkmanFont.bodyBold)
                                            .foregroundStyle(isSelected ? .white : .secondary)

                                        Text(drive.type == .internal ? "Internal Flash" : "MicroSD Card")
                                            .font(WalkmanFont.badge)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(isSelected ? WalkmanTheme.hiResGold.opacity(0.18) : Color.white.opacity(0.06))
                                            .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : .secondary)
                                            .clipShape(Capsule())
                                    }

                                    Text("\(formatBytes(drive.usedBytes)) used • \(formatBytes(drive.freeBytes)) free")
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(WalkmanTheme.hiResGold)
                                }
                            }
                            .padding(12)
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

    // MARK: - Backup Scope Card
    private var backupScopeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("2. BACKUP SCOPE", systemImage: "square.grid.2x2.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(estimatedCount.formatted()) items selected")
                        .font(WalkmanFont.subheadlineBold)
                        .foregroundStyle(.white)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(formatBytes(estimatedBytes))
                        .font(WalkmanFont.mono)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
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

                                Text(scope.subtitle)
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }

                            Spacer()

                            if scope == .albums {
                                Button(action: { showAlbumPickerSheet = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checklist")
                                        Text(selectedAlbumKeys.isEmpty ? "Select Albums..." : "\(selectedAlbumKeys.count) Albums Chosen")
                                    }
                                    .font(WalkmanFont.calloutBold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            } else if scope == .tracks {
                                Button(action: { showTrackPickerSheet = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "music.note.list")
                                        Text(selectedTrackPaths.isEmpty ? "Select Tracks..." : "\(selectedTrackPaths.count) Tracks Chosen")
                                    }
                                    .font(WalkmanFont.calloutBold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
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

    // MARK: - Destination Card
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("3. DESTINATION (LOCAL MAC & EXTERNAL STORAGE)", systemImage: "internaldrive.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                Button(action: { chooseCustomFolder() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose Custom Folder...")
                    }
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .buttonStyle(.plain)
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

                                        if let free = dest.freeBytes {
                                            Text("\(formatBytes(free)) free")
                                                .font(WalkmanFont.badge)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Color.white.opacity(0.08))
                                                .foregroundStyle(WalkmanTheme.silverMuted)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(dest.descriptionText)
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
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

                            Text("Connect a USB flash drive or external SSD to back up directly to external storage.")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(.secondary)
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

    // MARK: - Encryption Card
    private var encryptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("4. SECURITY & CRYPTOGRAPHY", systemImage: "lock.shield.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                Toggle("", isOn: $isEncrypted.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .tint(WalkmanTheme.hiResGold)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Encrypt Backup Container (AES-256-GCM)")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(isEncrypted ? .white : .secondary)

                    Text("Slow / High Security")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isEncrypted ? WalkmanTheme.hiResGold.opacity(0.2) : Color.white.opacity(0.05))
                        .foregroundStyle(isEncrypted ? WalkmanTheme.hiResGold : .secondary)
                        .clipShape(Capsule())
                }

                Text("Applies 256-bit AES encryption with PBKDF2-HMAC-SHA256 (100,000 rounds) key derivation. Stream hashing across large FLAC audio files is computationally intensive (slower transfer), but completely protects confidential music tracks on local storage or external flash drives.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
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
                    Text(err)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button("Dismiss") { backupErrorMessage = nil }
                        .font(WalkmanFont.calloutMedium)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let successURL = backupSuccessURL {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup Completed Successfully!")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("Saved to \(successURL.lastPathComponent)")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    Button(action: {
                        NSWorkspace.shared.selectFile(successURL.path, inFileViewerRootedAtPath: successURL.deletingLastPathComponent().path)
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
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }

            if isBackingUp, let prog = backupProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(prog.phase.rawValue)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(prog.itemsProcessed) of \(prog.totalItems) files (\(Int(prog.fractionCompleted * 100))%)")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Back Up")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("\(estimatedCount) files (\(formatBytes(estimatedBytes))) → \(currentDestination?.name ?? "Destination")")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    Button(action: { startBackup() }) {
                        HStack(spacing: 8) {
                            Image(systemName: isEncrypted ? "lock.fill" : "arrow.up.circle.fill")
                            Text(isEncrypted ? "Start Encrypted Backup" : "Start Backup")
                        }
                        .font(WalkmanFont.bodyBold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(canStartBackup ? WalkmanTheme.hiResGoldGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .foregroundStyle(canStartBackup ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartBackup)
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
                    self.backupSuccessURL = savedURL
                    self.refreshDestinationsAsync()
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
            HStack {
                Label("1. SELECT BACKUP ARCHIVE", systemImage: "clock.arrow.circlepath")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                Button(action: { browseOtherBackupFile() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Browse Other Backup File...")
                    }
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverMuted)
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

            if discoveredBackups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 28))
                        .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.5))

                    Text("No Walkman Backups Found")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)

                    Text("No .walkmanbackup or .walkmanbackup.enc archives found in local Mac storage or external drives. Click 'Browse Other Backup File...' to select an archive from Finder.")
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

                                        if b.isEncrypted {
                                            Text("AES-256-GCM")
                                                .font(WalkmanFont.badge)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(WalkmanTheme.hiResGold.opacity(0.2))
                                                .foregroundStyle(WalkmanTheme.hiResGold)
                                                .clipShape(Capsule())
                                        }

                                        Text(b.destinationType.rawValue)
                                            .font(WalkmanFont.badge)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.white.opacity(0.06))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                            .clipShape(Capsule())
                                    }

                                    HStack(spacing: 8) {
                                        Text(b.manifest?.scopeSummary ?? (b.isEncrypted ? "Encrypted Archive" : "Walkman Bundle"))
                                            .font(WalkmanFont.calloutMedium)
                                            .foregroundStyle(WalkmanTheme.silverMuted)

                                        Text("•")
                                            .foregroundStyle(.secondary)

                                        Text(b.dateModified.formatted(date: .abbreviated, time: .shortened))
                                            .font(WalkmanFont.callout)
                                            .foregroundStyle(.secondary)

                                        Text("•")
                                            .foregroundStyle(.secondary)

                                        Text(formatBytes(b.sizeBytes))
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                    }
                                }

                                Spacer()

                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : Color.white.opacity(0.2))
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

    // MARK: - Selected Backup Inspection Card
    private func backupInspectionCard(backup: DiscoveredBackup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("BACKUP METADATA & CONTENTS", systemImage: "info.circle.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()

                Text(backup.url.lastPathComponent)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source Model")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text(backup.manifest?.deviceName ?? "Sony Walkman")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                }

                Divider().frame(height: 32).overlay(WalkmanTheme.border)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Created")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text(backup.dateModified.formatted(date: .abbreviated, time: .shortened))
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                }

                Divider().frame(height: 32).overlay(WalkmanTheme.border)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Size")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text(formatBytes(backup.sizeBytes))
                        .font(WalkmanFont.mono)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }

                Divider().frame(height: 32).overlay(WalkmanTheme.border)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Files")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Text(backup.manifest != nil ? "\(backup.manifest!.totalFiles) items" : "Protected")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.white)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WalkmanTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Target Walkman Card
    private var targetWalkmanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("2. TARGET WALKMAN RESTORE PARTITION", systemImage: "hifispeaker.fill")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Spacer()
            }

            if drives.isEmpty {
                Text("No target Walkman connected to restore into.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(drives) { drive in
                        let isSelected = currentTargetDrive?.mountPoint == drive.mountPoint
                        Button(action: {
                            targetDriveMount = drive.mountPoint
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: drive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(drive.name)
                                            .font(WalkmanFont.bodyBold)
                                            .foregroundStyle(isSelected ? .white : .secondary)

                                        Text(drive.type == .internal ? "Internal Flash" : "MicroSD Card")
                                            .font(WalkmanFont.badge)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(isSelected ? WalkmanTheme.hiResGold.opacity(0.18) : Color.white.opacity(0.06))
                                            .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : .secondary)
                                            .clipShape(Capsule())
                                    }

                                    Text("\(formatBytes(drive.freeBytes)) available")
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(WalkmanTheme.hiResGold)
                                }
                            }
                            .padding(12)
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
                    Text(err)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button("Dismiss") { restoreErrorMessage = nil }
                        .font(WalkmanFont.calloutMedium)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let res = restoreSuccessResult {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore Completed Successfully!")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("Restored \(res.totalFilesRestored) files (\(formatBytes(res.totalBytesRestored))) to Walkman. Ghost files purged & database ready.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }

            if isRestoring, let prog = restoreProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(prog.phase.rawValue)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(prog.itemsProcessed) of \(prog.totalItems) files (\(Int(prog.fractionCompleted * 100))%)")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore into \(currentTargetDrive?.name ?? "Walkman")")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("Reconstructs clean /MUSIC and /LEARNING directory trees without macOS ghost files.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    Button(action: { startRestore() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Restore to Walkman")
                        }
                        .font(WalkmanFont.bodyBold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(canStartRestore ? WalkmanTheme.hiResGoldGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .foregroundStyle(canStartRestore ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color.white.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartRestore)
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
                    self.restoreSuccessResult = result
                    self.onRestoreComplete()
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

    // MARK: - Album Picker Sheet
    private var albumPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Albums to Back Up")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") { showAlbumPickerSheet = false }
                    .font(WalkmanFont.calloutBold)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    TextField("Search Albums or Artists...", text: $albumSearchText)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.body)
                }
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Select All") {
                    for alb in sourceAlbums {
                        selectedAlbumKeys.insert(alb.id)
                    }
                }
                .font(WalkmanFont.calloutMedium)
                .buttonStyle(.plain)

                Button("Clear") {
                    selectedAlbumKeys.removeAll()
                }
                .font(WalkmanFont.calloutMedium)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider().overlay(WalkmanTheme.border)

            let filtered = sourceAlbums.filter { alb in
                if albumSearchText.isEmpty { return true }
                return alb.name.localizedCaseInsensitiveContains(albumSearchText) ||
                       alb.artist.localizedCaseInsensitiveContains(albumSearchText)
            }

            List(filtered) { alb in
                let isChecked = selectedAlbumKeys.contains(alb.id)
                HStack(spacing: 12) {
                    Button(action: {
                        if isChecked {
                            selectedAlbumKeys.remove(alb.id)
                        } else {
                            selectedAlbumKeys.insert(alb.id)
                        }
                    }) {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(isChecked ? WalkmanTheme.hiResGold : Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alb.name)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("\(alb.artist) • \(alb.trackCount) tracks")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    if alb.isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.hiResGold.opacity(0.2))
                            .foregroundStyle(WalkmanTheme.hiResGold)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 540, minHeight: 450)
        .background(WalkmanTheme.background)
    }

    // MARK: - Track Picker Sheet
    private var trackPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Tracks to Back Up")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") { showTrackPickerSheet = false }
                    .font(WalkmanFont.calloutBold)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    TextField("Search Tracks, Artists, or Albums...", text: $trackSearchText)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.body)
                }
                .padding(8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Select All") {
                    for tr in sourceTracks {
                        selectedTrackPaths.insert(tr.fullPath)
                    }
                }
                .font(WalkmanFont.calloutMedium)
                .buttonStyle(.plain)

                Button("Clear") {
                    selectedTrackPaths.removeAll()
                }
                .font(WalkmanFont.calloutMedium)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider().overlay(WalkmanTheme.border)

            let filtered = sourceTracks.filter { tr in
                if trackSearchText.isEmpty { return true }
                return tr.title.localizedCaseInsensitiveContains(trackSearchText) ||
                       tr.artist.localizedCaseInsensitiveContains(trackSearchText) ||
                       tr.album.localizedCaseInsensitiveContains(trackSearchText)
            }

            List(filtered) { tr in
                let isChecked = selectedTrackPaths.contains(tr.fullPath)
                HStack(spacing: 12) {
                    Button(action: {
                        if isChecked {
                            selectedTrackPaths.remove(tr.fullPath)
                        } else {
                            selectedTrackPaths.insert(tr.fullPath)
                        }
                    }) {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(isChecked ? WalkmanTheme.hiResGold : Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr.title)
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("\(tr.artist) — \(tr.album)")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }

                    Spacer()

                    Text(tr.format)
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .clipShape(Capsule())

                    Text(formatBytes(tr.sizeBytes))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 580, minHeight: 480)
        .background(WalkmanTheme.background)
    }
}
