import SwiftUI
import AppKit

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
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    private var selectedTrack: Track? {
        guard let id = selectedTrackId else { return player.currentTrack }
        return tracks.first(where: { $0.id == id }) ?? player.currentTrack
    }
    
    private func refreshDrives() {
        isRefreshingDrives = true
        let detected = WalkmanEngine.shared.detectDrives()
        self.drives = detected
        self.deviceInfo = WalkmanDeviceDetector.shared.detect(drives: detected)
        
        if let current = activeDrive, detected.contains(where: { $0.mountPoint == current.mountPoint }) {
            // Keep current active drive
        } else {
            // Prefer MicroSD if present (larger storage with music), otherwise internal
            self.activeDrive = detected.first(where: { $0.type == .microsd }) ?? detected.first
        }
        
        isRefreshingDrives = false
        refreshLibrary()
    }
    
    private func refreshLibrary() {
        guard let drive = activeDrive else {
            self.tracks = []
            return
        }
        
        isScanning = true
        Task {
            let result = await LibraryScanner.shared.scan(musicDir: URL(fileURLWithPath: drive.musicDir))
            await MainActor.run {
                self.tracks = result.tracks
                self.isScanning = false
            }
        }
    }
    
    private func setupVolumeNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { _ in
            refreshDrives()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { _ in
            refreshDrives()
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
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Plug in your Sony NW-A55L via WM-PORT USB cable and ensure USB Mass Storage mode is enabled on the player.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    
                    Button(action: refreshDrives) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Detect Drives")
                        }
                        .font(.system(size: 11, weight: .semibold))
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
            } else {
                // Connected State: Native macOS NavigationSplitView
                NavigationSplitView {
                    SidebarView(
                        selectedTab: $selectedTab,
                        drives: drives,
                        trackCount: tracks.count,
                        queueCount: queueCount,
                        deviceInfo: deviceInfo,
                        activeDrive: activeDrive,
                        onSelectDrive: { drive in
                            activeDrive = drive
                            refreshLibrary()
                        },
                        onOpenAbout: { self.showAboutSheet = true }
                    )
                    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
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
                                
                            case .albums:
                                AlbumsView(
                                    tracks: tracks,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    }
                                )
                                
                            case .artists:
                                ArtistsView(
                                    tracks: tracks,
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
                        TrackPreviewBar(onOpenInspector: {
                            self.showInspector = true
                        })
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WalkmanTheme.background.ignoresSafeArea())
                    .inspector(isPresented: $showInspector) {
                        MetadataStudioView(
                            track: selectedTrack,
                            onSaved: { refreshLibrary() },
                            onClose: { self.showInspector = false }
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
                        
                        // Safe Eject
                        Button(action: { showEjectSheet = true }) {
                            Label("Eject", systemImage: "eject.circle")
                        }
                        .help("Clean macOS junk files and safely unmount Walkman")
                        
                        // Inspector Toggle
                        Button(action: { showInspector.toggle() }) {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Toggle Metadata & Artwork Inspector (Cmd+I)")
                    }
                }
            }
        }
        .onAppear {
            setupVolumeNotifications()
            NotificationCenter.default.addObserver(
                forName: .showAboutWalkmanStudio,
                object: nil,
                queue: .main
            ) { _ in
                self.showAboutSheet = true
            }
            refreshDrives()
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
