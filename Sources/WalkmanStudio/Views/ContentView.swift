import SwiftUI
import AppKit
import Combine

public struct ContentView: View {
    @State private var drives: [WalkmanDrive] = []
    @State private var devices: [WalkmanDevice] = []
    @State private var activeDevice: WalkmanDevice? = nil
    @State private var activeDrive: WalkmanDrive?
    @State private var tracks: [Track] = []
    @State private var isScanning: Bool = false
    @State private var isRefreshingDrives: Bool = false
    @State private var selectedTab: NavigationTab = .overview
    @State private var selectedTrackId: String?
    @State private var showInspector: Bool = false
    @State private var isEjecting: Bool = false
    @State private var queueCount: Int = 0
    @State private var deviceInfo: WalkmanDeviceInfo? = nil
    @State private var showAboutSheet: Bool = false
    @State private var trackToEdit: Track? = nil
    @State private var trackToTrimCut: Track? = nil
    @State private var albumToEdit: AlbumItem? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    // Real-time macOS workspace volume publishers
    private let didMountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
    private let didUnmountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
    private let willUnmountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willUnmountNotification)
    private let didRenamePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)
    private let didBecomeActivePublisher = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    private let heartbeatTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    @State private var libraryStats: (albums: Int, artists: Int, hiRes: Int, recentlyAdded: Int) = (0, 0, 0, 0)
    @State private var cachedArtists: [ArtistItem] = []
    @State private var cachedAlbums: [AlbumItem] = []
    @State private var cachedRecentTracks: [Track] = []
    @ObservedObject private var duplicateFinder = DuplicateFinderService.shared
    
    private var selectedTrack: Track? {
        if let id = selectedTrackId, let tr = tracks.first(where: { $0.id == id }) {
            return tr
        }
        if let playing = player.currentTrack {
            if let tr = tracks.first(where: { $0.id == playing.id }) {
                return tr
            }
            return playing
        }
        return nil
    }
    
    private func selectDevice(_ device: WalkmanDevice) {
        self.activeDevice = device
        self.deviceInfo = device.deviceInfo
        let devDrives = device.drives
        if let current = activeDrive, devDrives.contains(where: { $0.mountPoint == current.mountPoint }) {
            // Keep current drive if it belongs to this device
        } else {
            // Prefer MicroSD on this device, otherwise internal
            self.activeDrive = device.microsdDrive ?? devDrives.first
        }
        refreshLibrary()
    }

    private func selectDrive(_ drive: WalkmanDrive) {
        if let parentDev = devices.first(where: { $0.drives.contains(where: { $0.mountPoint == drive.mountPoint }) }) {
            self.activeDevice = parentDev
            self.deviceInfo = parentDev.deviceInfo
        }
        self.activeDrive = drive
        refreshLibrary()
    }

    private func refreshDrives() {
        isRefreshingDrives = true
        let detected = WalkmanEngine.shared.detectDrives()
        self.drives = detected
        let detectedDevices = WalkmanDeviceDetector.shared.detectDevices(drives: detected)
        self.devices = detectedDevices

        if detectedDevices.isEmpty {
            self.activeDevice = nil
            self.activeDrive = nil
            self.deviceInfo = nil
            self.tracks = []
            self.cachedArtists = []
            self.cachedAlbums = []
            self.cachedRecentTracks = []
            self.libraryStats = (0, 0, 0, 0)
            self.selectedTrackId = nil
            self.isEjecting = false
            AudioPlayerService.shared.stopAndClear()
        } else {
            // 1. Maintain active device if still connected, otherwise pick first
            if let current = activeDevice, let stillPresent = detectedDevices.first(where: { $0.id == current.id }) {
                self.activeDevice = stillPresent
            } else {
                self.activeDevice = detectedDevices.first
            }
            self.deviceInfo = self.activeDevice?.deviceInfo

            // 2. Maintain active drive for the active device
            let availableDrives = self.activeDevice?.drives ?? detected
            if let current = activeDrive, availableDrives.contains(where: { $0.mountPoint == current.mountPoint }) {
                // Keep current active drive
            } else {
                // Prefer MicroSD on active device if present, otherwise internal
                self.activeDrive = self.activeDevice?.microsdDrive ?? availableDrives.first
            }

            // If the currently playing track was on a drive that is no longer mounted, stop playback
            if let current = AudioPlayerService.shared.currentTrack {
                let stillMounted = detected.contains(where: { current.fullPath.hasPrefix($0.mountPoint) })
                if !stillMounted {
                    AudioPlayerService.shared.stopAndClear()
                }
            }
        }

        isRefreshingDrives = false
        refreshLibrary()
    }
    
    private func performCleanAndEject() {
        guard !drives.isEmpty, !isEjecting else { return }
        isEjecting = true
        AudioPlayerService.shared.stopAndClear()
        
        let drivesToEject = drives
        Task {
            let _ = await WalkmanEngine.shared.cleanAndEject(drives: drivesToEject)
            await MainActor.run {
                self.isEjecting = false
                self.refreshDrives()
            }
        }
    }
    
    private func refreshLibrary() {
        guard let drive = activeDrive else {
            self.tracks = []
            self.cachedArtists = []
            self.cachedAlbums = []
            self.cachedRecentTracks = []
            self.libraryStats = (0, 0, 0, 0)
            self.isScanning = false
            return
        }
        
        isScanning = true
        let expectedMount = drive.mountPoint
        Task {
            var scanDirs: [URL] = [URL(fileURLWithPath: drive.musicDir)]
            let learningURL = URL(fileURLWithPath: drive.learningDir)
            if FileManager.default.fileExists(atPath: learningURL.path) {
                scanDirs.append(learningURL)
            }
            let result = await LibraryScanner.shared.scan(directories: scanDirs)
            
            // Precompute library statistics and models off the main thread once
            let (stats, precomputedArtists, precomputedAlbums, precomputedRecent) = await Task.detached(priority: .userInitiated) {
                let artists = ArtistsView.buildArtists(from: result.tracks)
                let albums = AlbumsView.buildAlbums(from: result.tracks)
                let recent = result.tracks.sorted { $0.dateAdded > $1.dateAdded }
                
                var albumSet = Set<String>()
                var artistSet = Set<String>()
                var hiRes = 0
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
                var recentCount = 0
                for track in result.tracks {
                    let alb = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
                    let art = track.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                    albumSet.insert(cleanAlb.lowercased())
                    if !art.isEmpty { artistSet.insert(art) }
                    if track.bitsPerSample > 16 || track.sampleRate > 48000 { hiRes += 1 }
                    if track.dateAdded >= thirtyDaysAgo { recentCount += 1 }
                }
                if recentCount == 0 && !result.tracks.isEmpty {
                    recentCount = min(50, result.tracks.count)
                }
                let computedStats = (albumSet.count, artistSet.count, hiRes, recentCount)
                return (computedStats, artists, albums, recent)
            }.value
            
            await MainActor.run {
                guard self.activeDrive?.mountPoint == expectedMount else { return }
                self.tracks = result.tracks
                self.cachedArtists = precomputedArtists
                self.cachedAlbums = precomputedAlbums
                self.cachedRecentTracks = precomputedRecent
                self.libraryStats = stats
                self.isScanning = false
            }

            let allDrives = self.drives
            Task {
                _ = await DuplicateFinderService.shared.scanForDuplicates(drives: allDrives)
            }
        }
    }

    private func updateTracksInMemory(_ updatedTracks: [Track]) {
        guard !updatedTracks.isEmpty else { return }
        var map = [String: Track]()
        for t in updatedTracks {
            map[t.fullPath] = t
        }
        
        var newTracks = self.tracks
        for i in 0..<newTracks.count {
            if let updated = map[newTracks[i].fullPath] {
                newTracks[i] = updated
            }
        }
        self.tracks = newTracks
        
        // Recompute precomputed models immediately for instant zero-latency UI update
        let precomputedArtists = ArtistsView.buildArtists(from: newTracks)
        let precomputedAlbums = AlbumsView.buildAlbums(from: newTracks)
        let precomputedRecent = newTracks.sorted { $0.dateAdded > $1.dateAdded }
        
        self.cachedArtists = precomputedArtists
        self.cachedAlbums = precomputedAlbums
        self.cachedRecentTracks = precomputedRecent
    }
    
    private func deleteTrackFromDevice(_ track: Track) {
        // 1. If currently playing, stop playback immediately
        if player.currentTrack?.id == track.id {
            player.stopAndClear()
        }
        player.currentQueue.removeAll(where: { $0.id == track.id })
        
        // 2. Clear selection if it matches the deleted track
        if selectedTrackId == track.id {
            selectedTrackId = nil
        }
        
        // 3. Immediately update UI state (optimistic removal)
        self.tracks.removeAll(where: { $0.id == track.id })
        self.cachedRecentTracks.removeAll(where: { $0.id == track.id })
        self.cachedAlbums = AlbumsView.buildAlbums(from: self.tracks)
        self.cachedArtists = ArtistsView.buildArtists(from: self.tracks)
        
        var albumSet = Set<String>()
        var artistSet = Set<String>()
        var hiRes = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        var recentCount = 0
        for tr in self.tracks {
            let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
            let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            albumSet.insert(cleanAlb.lowercased())
            if !art.isEmpty { artistSet.insert(art) }
            if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { hiRes += 1 }
            if tr.dateAdded >= thirtyDaysAgo { recentCount += 1 }
        }
        if recentCount == 0 && !self.tracks.isEmpty {
            recentCount = min(50, self.tracks.count)
        }
        self.libraryStats = (albumSet.count, artistSet.count, hiRes, recentCount)
        
        // 4. Physical deletion on device in background
        Task {
            await WalkmanEngine.shared.deleteTrackFile(atPath: track.fullPath)
            CoverArtCache.shared.invalidate(forFullPath: track.fullPath, artist: track.primaryArtist, album: track.album)
            LibraryScanner.shared.removeFromCache(fullPath: track.fullPath)
            
            await MainActor.run {
                // Refresh drive free/used space metrics
                let detected = WalkmanEngine.shared.detectDrives()
                self.drives = detected
                let detectedDevs = WalkmanDeviceDetector.shared.detectDevices(drives: detected)
                self.devices = detectedDevs
                if let curDev = self.activeDevice, let updatedDev = detectedDevs.first(where: { $0.id == curDev.id }) {
                    self.activeDevice = updatedDev
                    self.deviceInfo = updatedDev.deviceInfo
                } else {
                    self.activeDevice = detectedDevs.first
                    self.deviceInfo = self.activeDevice?.deviceInfo
                }
                if let current = self.activeDrive, let updated = detected.first(where: { $0.mountPoint == current.mountPoint }) {
                    self.activeDrive = updated
                }
            }
        }
    }

    private func deleteAlbumFromDevice(_ album: AlbumItem) {
        let albumTracks = album.tracks
        let trackIds = Set(albumTracks.map { $0.id })
        
        // 1. If currently playing a track in this album, stop playback immediately
        if let current = player.currentTrack, trackIds.contains(current.id) {
            player.stopAndClear()
        }
        player.currentQueue.removeAll(where: { trackIds.contains($0.id) })
        
        // 2. Clear selection if it belongs to this album
        if let sel = selectedTrackId, trackIds.contains(sel) {
            selectedTrackId = nil
        }
        
        // 3. Immediately update UI state (optimistic removal)
        self.tracks.removeAll(where: { trackIds.contains($0.id) })
        self.cachedRecentTracks.removeAll(where: { trackIds.contains($0.id) })
        self.cachedAlbums = AlbumsView.buildAlbums(from: self.tracks)
        self.cachedArtists = ArtistsView.buildArtists(from: self.tracks)
        
        var albumSet = Set<String>()
        var artistSet = Set<String>()
        var hiRes = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        var recentCount = 0
        for tr in self.tracks {
            let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
            let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            albumSet.insert(cleanAlb.lowercased())
            if !art.isEmpty { artistSet.insert(art) }
            if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { hiRes += 1 }
            if tr.dateAdded >= thirtyDaysAgo { recentCount += 1 }
        }
        if recentCount == 0 && !self.tracks.isEmpty {
            recentCount = min(50, self.tracks.count)
        }
        self.libraryStats = (albumSet.count, artistSet.count, hiRes, recentCount)
        
        // 4. Physical deletion on device in background
        Task {
            await WalkmanEngine.shared.deleteAlbum(tracks: albumTracks)
            for tr in albumTracks {
                CoverArtCache.shared.invalidate(forFullPath: tr.fullPath, artist: tr.primaryArtist, album: tr.album)
                LibraryScanner.shared.removeFromCache(fullPath: tr.fullPath)
            }
            
            await MainActor.run {
                // Refresh drive free/used space metrics
                let detected = WalkmanEngine.shared.detectDrives()
                self.drives = detected
                let detectedDevs = WalkmanDeviceDetector.shared.detectDevices(drives: detected)
                self.devices = detectedDevs
                if let curDev = self.activeDevice, let updatedDev = detectedDevs.first(where: { $0.id == curDev.id }) {
                    self.activeDevice = updatedDev
                    self.deviceInfo = updatedDev.deviceInfo
                } else {
                    self.activeDevice = detectedDevs.first
                    self.deviceInfo = self.activeDevice?.deviceInfo
                }
                if let current = self.activeDrive, let updated = detected.first(where: { $0.mountPoint == current.mountPoint }) {
                    self.activeDrive = updated
                }
            }
        }
    }
    
    private func checkDrivesHeartbeat() {
        guard !drives.isEmpty else {
            DispatchQueue.global(qos: .utility).async {
                let detected = WalkmanEngine.shared.detectDrives()
                if !detected.isEmpty {
                    DispatchQueue.main.async {
                        self.refreshDrives()
                    }
                }
            }
            return
        }
        
        let currentDrives = drives
        DispatchQueue.global(qos: .utility).async {
            var rootStat = stat()
            stat("/", &rootStat)
            
            let anyDriveLost = currentDrives.contains { drive in
                var volStat = stat()
                if stat(drive.mountPoint, &volStat) != 0 || volStat.st_dev == rootStat.st_dev {
                    return true
                }
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: drive.mountPoint, isDirectory: &isDir)
                return !exists || !isDir.boolValue
            }
            if anyDriveLost {
                DispatchQueue.main.async {
                    self.refreshDrives()
                }
            }
        }
    }
    
    public var body: some View {
        Group {
            if drives.isEmpty && !isRefreshingDrives {
                // Disconnected State
                VStack(spacing: 24) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: "cable.connector.horizontal")
                            .font(.system(size: 36))
                            .foregroundStyle(WalkmanTheme.silver)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Connect Sony Walkman")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Plug in your Sony Walkman via USB cable and ensure USB Mass Storage mode is enabled on the player.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }
                    
                    if let unsupported = WalkmanEngine.shared.lastUnsupportedModel {
                        VStack(spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(WalkmanTheme.hiResGold)
                                Text("Unsupported Model: \(unsupported)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text("Walkman Studio is designed exclusively for non-Android Sony OS Walkmans. Android-based Walkmans use MTP and are not supported.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: 440)
                    }
                    
                    Button(action: refreshDrives) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Detect Drives")
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WalkmanTheme.background)
                .toolbar {
                    Spacer()
                    
                    // Rescan
                    Button(action: { refreshDrives() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh connected drives and reload library")
                }
                .toolbarBackground(.hidden, for: .windowToolbar)
            } else if isScanning && tracks.isEmpty {
                // Caching & Indexing Loading Screen
                VStack(spacing: 24) {
                    Spacer()
                    
                    WalkmanDeviceIconView(
                        size: 84,
                        mountPoint: activeDrive?.mountPoint,
                        deviceInfo: deviceInfo,
                        hasBackground: false
                    )
                    
                    VStack(spacing: 8) {
                        Text("Reading Walkman Library")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.white)
                        
                        Text("Caching music index & album metadata from \(activeDrive?.name ?? "Walkman")...")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }
                    
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(WalkmanTheme.silver)
                            .scaleEffect(1.2)
                        
                        Text("Optimizing library view...")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                    .padding(.top, 6)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WalkmanTheme.background)
            } else {
                // Connected State: Native macOS NavigationSplitView
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        selectedTab: $selectedTab,
                        devices: devices,
                        drives: drives,
                        activeDevice: activeDevice,
                        trackCount: tracks.count,
                        recentlyAddedCount: libraryStats.recentlyAdded,
                        albumCount: libraryStats.albums,
                        artistCount: libraryStats.artists,
                        hiResCount: libraryStats.hiRes,
                        duplicateCount: duplicateFinder.duplicateGroups.count,
                        queueCount: queueCount,
                        deviceInfo: deviceInfo,
                        activeDrive: activeDrive,
                        onSelectDevice: { dev in
                            selectDevice(dev)
                        },
                        onSelectDrive: { drive in
                            selectDrive(drive)
                        },
                        onOpenAbout: { self.showAboutSheet = true }
                    )
                    .frame(width: 260)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 260)
                    .toolbarBackground(.hidden, for: .windowToolbar)
                } detail: {
                    ZStack(alignment: .bottom) {
                        ZStack {
                            WalkmanTheme.background
                                .ignoresSafeArea()
                            
                            switch selectedTab {
                            case .overview:
                                DeviceOverviewView(
                                    devices: devices,
                                    drives: activeDevice?.drives ?? drives,
                                    activeDevice: activeDevice,
                                    activeDrive: activeDrive,
                                    tracks: tracks,
                                    precomputedStats: (albums: libraryStats.albums, artists: libraryStats.artists, hiRes: libraryStats.hiRes),
                                    onNavigateToTab: { tab in selectedTab = tab },
                                    onOpenEject: { performCleanAndEject() },
                                    onRefresh: { refreshDrives() },
                                    onSelectDevice: { dev in
                                        selectDevice(dev)
                                    },
                                    onSelectDrive: { drive in
                                        selectDrive(drive)
                                    },
                                    deviceInfo: deviceInfo,
                                    onOpenAbout: { self.showAboutSheet = true },
                                    isEjecting: isEjecting
                                )
                                
                            case .library:
                                LibraryView(
                                    tracks: tracks,
                                    isLoading: isScanning,
                                    selectedTrackId: $selectedTrackId,
                                    onInspectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onGoToTransfer: {
                                        self.selectedTab = .transfer
                                    },
                                    onDeleteTrack: { track in
                                        deleteTrackFromDevice(track)
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    }
                                )
                                
                            case .recentlyAdded:
                                RecentlyAddedView(
                                    tracks: cachedRecentTracks.isEmpty ? tracks : cachedRecentTracks,
                                    isLoading: isScanning,
                                    selectedTrackId: $selectedTrackId,
                                    onInspectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onGoToTransfer: {
                                        self.selectedTab = .transfer
                                    },
                                    onDeleteTrack: { track in
                                        deleteTrackFromDevice(track)
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    }
                                )
                                
                            case .albums:
                                AlbumsView(
                                    tracks: tracks,
                                    precomputedAlbums: cachedAlbums,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onEditAlbum: { album in
                                        self.albumToEdit = album
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    },
                                    onDeleteAlbum: { album in
                                        deleteAlbumFromDevice(album)
                                    },
                                    onDeleteTrack: { track in
                                        deleteTrackFromDevice(track)
                                    }
                                )
                                
                            case .artists:
                                ArtistsView(
                                    tracks: tracks,
                                    precomputedArtists: cachedArtists,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    }
                                )
                                
                            case .hiRes:
                                HiResAudioView(
                                    tracks: tracks,
                                    precomputedAlbums: cachedAlbums,
                                    precomputedArtists: cachedArtists,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onEditAlbum: { album in
                                        self.albumToEdit = album
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    },
                                    onDeleteAlbum: { album in
                                        deleteAlbumFromDevice(album)
                                    },
                                    onDeleteTrack: { track in
                                        deleteTrackFromDevice(track)
                                    }
                                )
                                
                            case .duplicates:
                                DuplicatesView(
                                    drives: drives,
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onLibraryChanged: {
                                        self.refreshLibrary()
                                    }
                                )
                                
                            case .transfer:
                                TransferQueueView(
                                    drives: drives,
                                    activeDrive: activeDrive,
                                    onTransferComplete: { refreshLibrary() }
                                )
                                .padding(14)
                                
                            case .playlists:
                                PlaylistsView(
                                    activeDrive: activeDrive,
                                    libraryTracks: tracks
                                )
                                .id(activeDrive?.mountPoint ?? "no_drive")
                                .padding(14)

                            case .backupRestore:
                                BackupRestoreView(
                                    drives: drives,
                                    activeDrive: activeDrive,
                                    tracks: tracks,
                                    cachedAlbums: cachedAlbums,
                                    deviceInfo: deviceInfo,
                                    onRestoreComplete: { refreshDrives() }
                                )
                                .padding(14)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        
                        // Audio Preview & Playback Bar (Floating Liquid Glass Container)
                        HStack {
                            Spacer(minLength: 0)
                            TrackPreviewBar(
                                libraryTracks: tracks,
                                isInspectorPresented: showInspector,
                                onOpenInspector: {
                                    if let cur = player.currentTrack {
                                        self.selectedTrackId = cur.id
                                    }
                                    self.showInspector = true
                                }
                            )
                            .frame(maxWidth: 1040)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .background(WalkmanTheme.background.ignoresSafeArea())
                    .adaptiveInspector(isPresented: $showInspector) {
                        MetadataStudioView(
                            track: selectedTrack,
                            onSaved: { refreshLibrary() },
                            onEdit: {
                                if let tr = selectedTrack {
                                    self.trackToEdit = tr
                                }
                            }
                        )
                    }
                    .toolbar {
                        Spacer()
                        
                        // Rescan
                        Button(action: { refreshDrives() }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh connected drives and reload library")
                        
                        // Safe Eject (only shown if a device is connected)
                        if !drives.isEmpty {
                            Button(action: { performCleanAndEject() }) {
                                if isEjecting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Eject", systemImage: "eject.circle")
                                }
                            }
                            .disabled(isEjecting)
                            .help("Clean macOS junk files and safely unmount Walkman")
                        }
                        
                        // Inspector Toggle
                        Button(action: { showInspector.toggle() }) {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Toggle Metadata & Artwork Inspector (Cmd+I)")
                    }
                    .toolbarBackground(.hidden, for: .windowToolbar)
                }
                .navigationSplitViewStyle(.balanced)
                .toolbarBackground(.hidden, for: .windowToolbar)
            }
        }
        .onAppear {
            refreshDrives()
        }
        .onReceive(didMountPublisher) { _ in
            refreshDrives()
        }
        .onReceive(didUnmountPublisher) { _ in
            refreshDrives()
        }
        .onReceive(willUnmountPublisher) { _ in
            refreshDrives()
        }
        .onReceive(didRenamePublisher) { _ in
            refreshDrives()
        }
        .onReceive(didBecomeActivePublisher) { _ in
            checkDrivesHeartbeat()
        }
        .onReceive(heartbeatTimer) { _ in
            checkDrivesHeartbeat()
        }
        .onChange(of: player.currentTrack?.id) {
            if let cur = player.currentTrack, player.isPlaying {
                self.selectedTrackId = cur.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWalkmanStudio)) { _ in
            self.showAboutSheet = true
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutWalkmanStudioView(
                currentDeviceInfo: deviceInfo,
                onDismiss: { showAboutSheet = false }
            )
        }
        .sheet(item: $trackToEdit) { track in
            SongMetadataEditorSheet(
                track: track,
                onSavedTrack: { updatedTrack in
                    if self.player.currentTrack?.id == updatedTrack.id {
                        self.player.updateTrackInfo(track: updatedTrack)
                    }
                    self.updateTracksInMemory([updatedTrack])
                    self.refreshLibrary()
                },
                onDismiss: {
                    trackToEdit = nil
                }
            )
        }
        .sheet(item: $trackToTrimCut) { track in
            TrimAndCutSheet(
                track: track,
                onSaved: {
                    refreshLibrary()
                },
                onDismiss: {
                    trackToTrimCut = nil
                }
            )
        }
        .sheet(item: $albumToEdit) { album in
            AlbumMetadataEditorSheet(
                album: album,
                onSaved: {
                    refreshLibrary()
                },
                onSavedTracks: { updatedTracks in
                    self.updateTracksInMemory(updatedTracks)
                },
                onDismiss: {
                    albumToEdit = nil
                }
            )
        }
    }
}

private extension View {
    @ViewBuilder
    func adaptiveInspector<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.inspector(isPresented: isPresented) {
                content()
                    .inspectorColumnWidth(min: 280, ideal: 300, max: 320)
            }
        } else {
            HStack(spacing: 0) {
                self
                if isPresented.wrappedValue {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                    content()
                        .frame(width: 300)
                        .background(WalkmanTheme.background)
                        .transition(.move(edge: .trailing))
                }
            }
        }
    }
}
