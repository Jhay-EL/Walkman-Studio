import SwiftUI
import AppKit
import Combine

public struct ContentView: View {
    @State private var drives: [WalkmanDrive] = []
    @State private var activeDrive: WalkmanDrive?
    @State private var tracks: [Track] = []
    @State private var isScanning: Bool = false
    @State private var isRefreshingDrives: Bool = false
    @State private var selectedTab: NavigationTab = .overview
    @State private var selectedTrackId: String?
    @State private var showInspector: Bool = false
    @State private var showEjectSheet: Bool = false
    @State private var queueCount: Int = 0
    @State private var deviceInfo: WalkmanDeviceInfo? = nil
    @State private var showAboutSheet: Bool = false
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
    
    private var selectedTrack: Track? {
        // When music is playing or loaded on the music player, make sure the music details panel matches what is playing
        if let playing = player.currentTrack {
            if player.isPlaying || selectedTrackId == nil || selectedTrackId == playing.id {
                return playing
            }
            if let id = selectedTrackId, let tr = tracks.first(where: { $0.id == id }) {
                return tr
            }
            return playing
        }
        guard let id = selectedTrackId else { return nil }
        return tracks.first(where: { $0.id == id })
    }
    
    private func refreshDrives() {
        isRefreshingDrives = true
        let detected = WalkmanEngine.shared.detectDrives()
        self.drives = detected
        self.deviceInfo = WalkmanDeviceDetector.shared.detect(drives: detected)
        
        if detected.isEmpty {
            self.activeDrive = nil
            self.tracks = []
            self.cachedArtists = []
            self.cachedAlbums = []
            self.cachedRecentTracks = []
            self.libraryStats = (0, 0, 0, 0)
            self.selectedTrackId = nil
            self.showEjectSheet = false
            AudioPlayerService.shared.stopAndClear()
        } else {
            if let current = activeDrive, detected.contains(where: { $0.mountPoint == current.mountPoint }) {
                // Keep current active drive
            } else {
                // Prefer MicroSD if present (larger storage with music), otherwise internal
                self.activeDrive = detected.first(where: { $0.type == .microsd }) ?? detected.first
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
            let result = await LibraryScanner.shared.scan(musicDir: URL(fileURLWithPath: drive.musicDir))
            
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
                        drives: drives,
                        trackCount: tracks.count,
                        recentlyAddedCount: libraryStats.recentlyAdded,
                        albumCount: libraryStats.albums,
                        artistCount: libraryStats.artists,
                        hiResCount: libraryStats.hiRes,
                        queueCount: queueCount,
                        deviceInfo: deviceInfo,
                        activeDrive: activeDrive,
                        onSelectDrive: { drive in
                            activeDrive = drive
                            refreshLibrary()
                        },
                        onOpenAbout: { self.showAboutSheet = true }
                    )
                    .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
                    .animation(nil, value: showInspector)
                    .toolbarBackground(.hidden, for: .windowToolbar)
                } detail: {
                    VStack(spacing: 0) {
                        ZStack {
                            WalkmanTheme.background
                                .ignoresSafeArea()
                            
                            switch selectedTab {
                            case .overview:
                                DeviceOverviewView(
                                    drives: drives,
                                    tracks: tracks,
                                    onNavigateToTab: { tab in selectedTab = tab },
                                    onOpenEject: { showEjectSheet = true },
                                    onRefresh: { refreshDrives() },
                                    deviceInfo: deviceInfo,
                                    onOpenAbout: { self.showAboutSheet = true }
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
                                    }
                                )
                                
                            case .albums:
                                AlbumsView(
                                    tracks: tracks,
                                    precomputedAlbums: cachedAlbums,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    }
                                )
                                
                            case .artists:
                                ArtistsView(
                                    tracks: tracks,
                                    precomputedArtists: cachedArtists,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    }
                                )
                                
                            case .hiRes:
                                HiResAudioView(
                                    tracks: tracks,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
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
                                .padding(14)
                            }
                        }
                        
                        // Audio Preview & Playback Bar
                        TrackPreviewBar(
                            isInspectorPresented: showInspector,
                            onOpenInspector: {
                                if let cur = player.currentTrack {
                                    self.selectedTrackId = cur.id
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    self.showInspector = true
                                }
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WalkmanTheme.background.ignoresSafeArea())
                    .inspector(isPresented: $showInspector) {
                        MetadataStudioView(
                            track: selectedTrack,
                            onSaved: { refreshLibrary() }
                        )
                        .inspectorColumnWidth(min: 270, ideal: 310, max: 360)
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
                            Button(action: { showEjectSheet = true }) {
                                Label("Eject", systemImage: "eject.circle")
                            }
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
        .sheet(isPresented: $showEjectSheet) {
            CleanEjectSheet(
                drives: drives,
                onEjectComplete: { refreshDrives() },
                onDismiss: { showEjectSheet = false }
            )
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutWalkmanStudioView(
                currentDeviceInfo: deviceInfo,
                onDismiss: { showAboutSheet = false }
            )
        }
    }
}
