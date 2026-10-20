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
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    private var selectedTrack: Track? {
        guard let id = selectedTrackId else { return player.currentTrack }
        return tracks.first(where: { $0.id == id }) ?? player.currentTrack
    }
    
    private func refreshDrives() {
        isRefreshingDrives = true
        let detected = WalkmanEngine.shared.detectDrives()
        self.drives = detected
        
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
                            .fill(WalkmanTheme.gold.opacity(0.12))
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: "cable.connector.horizontal")
                            .font(.system(size: 36))
                            .foregroundStyle(WalkmanTheme.gold)
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
                        .background(WalkmanTheme.goldGradient)
                        .foregroundStyle(.black)
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
                        queueCount: queueCount
                    )
                    .frame(minWidth: 200, idealWidth: 230)
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
                                    onRefresh: { refreshDrives() }
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
                                
                            case .dsp:
                                WalkmanOneDspView(
                                    drives: drives,
                                    activeDrive: activeDrive
                                )
                            }
                        }
                        
                        // Audio Preview & Playback Bar
                        TrackPreviewBar(onOpenInspector: {
                            self.showInspector = true
                        })
                    }
                    .inspector(isPresented: $showInspector) {
                        MetadataStudioView(
                            track: selectedTrack,
                            onSaved: { refreshLibrary() }
                        )
                        .inspectorColumnWidth(min: 270, ideal: 310, max: 360)
                    }
                }
                .toolbar {
                    // Drive Selector in Toolbar (Always displays Icon + Label)
                    ToolbarItem(placement: .navigation) {
                        if !drives.isEmpty {
                            Menu {
                                ForEach(drives) { d in
                                    Button {
                                        activeDrive = d
                                        refreshLibrary()
                                    } label: {
                                        HStack {
                                            if activeDrive?.mountPoint == d.mountPoint {
                                                Image(systemName: "checkmark")
                                            }
                                            Text(d.type == .internal ? "Internal Storage (\(d.name))" : "SD Card (\(d.name))")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: activeDrive?.type == .internal ? "internaldrive" : "sdcard")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(WalkmanTheme.gold)
                                    
                                    Text(activeDrive?.type == .internal ? "Internal Storage" : "SD Card")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .menuStyle(.borderlessButton)
                            .help("Switch between Internal Storage and SD Card")
                        }
                    }
                    
                    // Center Subtitle
                    ToolbarItem(placement: .principal) {
                        Text("Sony Walkman NW-A55L")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    
                    // Trailing Action Controls
                    ToolbarItemGroup(placement: .primaryAction) {
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
                        
                        // Trailing Inspector Toggle
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
            refreshDrives()
        }
        .sheet(isPresented: $showEjectSheet) {
            CleanEjectSheet(
                drives: drives,
                onEjectComplete: { refreshDrives() },
                onDismiss: { showEjectSheet = false }
            )
        }
    }
}
