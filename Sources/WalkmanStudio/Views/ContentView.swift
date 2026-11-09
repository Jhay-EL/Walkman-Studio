import SwiftUI
import AppKit
import Combine
import QuartzCore

private struct DriveLibraryCache: Sendable {
    var tracks: [Track] = []
    var cachedArtists: [ArtistItem] = []
    var cachedAlbums: [AlbumItem] = []
    var cachedRecentTracks: [Track] = []
    var cachedLanguageTracks: [Track] = []
    var libraryStats: (albums: Int, artists: Int, hiRes: Int, recentlyAdded: Int, languageStudy: Int) = (0, 0, 0, 0, 0)
    var isLoaded: Bool = false
}

public struct ContentView: View {
    @State private var drives: [WalkmanDrive] = []
    @State private var devices: [WalkmanDevice] = []
    @State private var activeDevice: WalkmanDevice? = nil
    @State private var activeDrive: WalkmanDrive?
    @State private var tracks: [Track] = []
    @State private var isScanning: Bool = false
    @State private var isRefreshingDrives: Bool = false
    @State private var selectedTab: NavigationTab = .localLibrary
    @State private var selectedTrackId: String?
    @State private var showInspector: Bool = true
    @State private var isEjecting: Bool = false
    @State private var queueCount: Int = 0
    @State private var deviceInfo: WalkmanDeviceInfo? = nil
    @State private var showAboutSheet: Bool = false
    @State private var showManageFoldersSheet: Bool = false
    @State private var trackToEdit: Track? = nil
    @State private var trackListToEdit: [Track] = []
    @State private var trackToTrimCut: Track? = nil
    @State private var albumToEdit: AlbumItem? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isFullScreenPlayerPresented: Bool = false
    @State private var showingMtpHelpSheet: Bool = false
    @ObservedObject private var usbDetector = WalkmanUSBDetector.shared
    @State private var driveCache: [String: DriveLibraryCache] = [:]
    @State private var libraryScanTask: Task<Void, Never>? = nil

    // Window tracking & Track Detail (Inspector) expansion state
    @State private var hostWindow: NSWindow? = nil
    @State private var savedWidthBeforeInspector: CGFloat? = nil
    @State private var savedShiftOnInspectorOpen: CGFloat = 0
    @State private var expectedWidthWithInspector: CGFloat = 0
    
    @ObservedObject private var player = AudioPlayerService.shared
    @ObservedObject private var localLibrary = LocalMusicLibraryService.shared
    
    // Real-time macOS workspace volume publishers
    private let didMountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
    private let didUnmountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
    private let willUnmountPublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willUnmountNotification)
    private let didRenamePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)
    private let didBecomeActivePublisher = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    private let heartbeatTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    @State private var libraryStats: (albums: Int, artists: Int, hiRes: Int, recentlyAdded: Int, languageStudy: Int) = (0, 0, 0, 0, 0)
    @State private var cachedArtists: [ArtistItem] = []
    @State private var cachedAlbums: [AlbumItem] = []
    @State private var cachedRecentTracks: [Track] = []
    @State private var cachedLanguageTracks: [Track] = []
    @State private var targetAlbumName: String? = nil
    @State private var targetAlbumArtist: String? = nil
    @State private var targetArtistName: String? = nil
    @ObservedObject private var duplicateFinder = DuplicateFinderService.shared
    
    private var selectedTrack: Track? {
        if let id = selectedTrackId {
            if let tr = tracks.first(where: { $0.id == id }) {
                return tr
            }
            if let tr = cachedRecentTracks.first(where: { $0.id == id }) {
                return tr
            }
            if let tr = cachedLanguageTracks.first(where: { $0.id == id }) {
                return tr
            }
            if let tr = localLibrary.tracks.first(where: { $0.id == id }) {
                return tr
            }
            if let playing = player.currentTrack, playing.id == id {
                return playing
            }
        }
        if let playing = player.currentTrack {
            if let tr = tracks.first(where: { $0.id == playing.id }) {
                return tr
            }
            if let tr = cachedRecentTracks.first(where: { $0.id == playing.id }) {
                return tr
            }
            if let tr = cachedLanguageTracks.first(where: { $0.id == playing.id }) {
                return tr
            }
            if let tr = localLibrary.tracks.first(where: { $0.id == playing.id }) {
                return tr
            }
            return playing
        }
        return nil
    }

    private func getEditingTrackList(for track: Track) -> [Track] {
        if !trackListToEdit.isEmpty && trackListToEdit.contains(where: { $0.id == track.id }) {
            return trackListToEdit
        }
        
        let pool = localLibrary.tracks.contains(where: { $0.id == track.id }) ? localLibrary.tracks : tracks

        // If track belongs to an album, group all tracks for this album and sort by trackNum
        let trimmedAlb = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlb.isEmpty {
            if let found = cachedAlbums.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedAlb) == .orderedSame }) {
                if found.tracks.contains(where: { $0.id == track.id }) || found.tracks.count > 1 {
                    return found.tracks
                }
            }
            if let found = LocalMusicLibraryService.shared.precomputedAlbums.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedAlb) == .orderedSame }) {
                if found.tracks.contains(where: { $0.id == track.id }) || found.tracks.count > 1 {
                    return found.tracks
                }
            }
            let matching = pool.filter {
                $0.album.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(trimmedAlb) == .orderedSame
            }
            if matching.count > 1 {
                return matching.sorted {
                    let num0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    let num1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                    if num0 != num1 && num0 > 0 && num1 > 0 {
                        return num0 < num1
                    }
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            }
        }

        if selectedTab == .recentlyAdded {
            return cachedRecentTracks.isEmpty ? tracks : cachedRecentTracks
        }
        if selectedTab == .hiRes {
            return tracks.filter { $0.bitsPerSample > 16 || $0.sampleRate > 48000 }
        }
        if selectedTab == .languageStudy {
            return cachedLanguageTracks
        }
        return pool
    }

    private var editingTrackList: [Track] {
        guard let track = trackToEdit else { return [] }
        return getEditingTrackList(for: track)
    }
    
    private func selectDevice(_ device: WalkmanDevice) {
        self.activeDevice = device
        self.deviceInfo = device.deviceInfo
        let devDrives = device.drives
        let targetDrive: WalkmanDrive?
        if let current = activeDrive, devDrives.contains(where: { $0.mountPoint == current.mountPoint }) {
            // Keep current drive if it belongs to this device
            targetDrive = current
        } else {
            // Prefer MicroSD on this device, otherwise internal
            targetDrive = device.microsdDrive ?? devDrives.first
        }
        if let target = targetDrive {
            selectDrive(target)
        }
    }

    private func selectDrive(_ drive: WalkmanDrive) {
        if let parentDev = devices.first(where: { $0.drives.contains(where: { $0.mountPoint == drive.mountPoint }) }) {
            self.activeDevice = parentDev
            self.deviceInfo = parentDev.deviceInfo
        }
        
        guard activeDrive?.mountPoint != drive.mountPoint else { return }
        
        libraryScanTask?.cancel()
        libraryScanTask = nil
        selectedTrackId = nil
        self.activeDrive = drive
        
        if let cached = driveCache[drive.mountPoint], cached.isLoaded {
            self.tracks = cached.tracks
            self.cachedArtists = cached.cachedArtists
            self.cachedAlbums = cached.cachedAlbums
            self.cachedRecentTracks = cached.cachedRecentTracks
            self.cachedLanguageTracks = cached.cachedLanguageTracks
            self.libraryStats = cached.libraryStats
            self.isScanning = false
        } else {
            self.tracks = []
            self.cachedArtists = []
            self.cachedAlbums = []
            self.cachedRecentTracks = []
            self.cachedLanguageTracks = []
            self.libraryStats = (0, 0, 0, 0, 0)
            self.isScanning = true
        }
        refreshLibrary()
    }

    private func selectCustomStorageFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Walkman Storage Folder"
        panel.message = "Select the mounted storage volume or Music folder of your Sony Walkman."
        panel.prompt = "Connect Storage"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        panel.directoryURL = volumesURL
        
        let response = panel.runModal()
        if response == .OK, let selectedURL = panel.url {
            _ = WalkmanEngine.shared.setCustomStorageFolder(url: selectedURL)
            self.refreshDrives()
        }
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
            self.cachedLanguageTracks = []
            self.libraryStats = (0, 0, 0, 0, 0)
            self.driveCache.removeAll()
            self.isEjecting = false
            if let current = AudioPlayerService.shared.currentTrack, !localLibrary.tracks.contains(where: { $0.id == current.id }) {
                AudioPlayerService.shared.stopAndClear()
            }
            if selectedTab == .overview || selectedTab == .library || selectedTab == .recentlyAdded || selectedTab == .albums || selectedTab == .artists || selectedTab == .hiRes || selectedTab == .languageStudy || selectedTab == .playlists || selectedTab == .backupRestore {
                self.selectedTab = .localLibrary
            }
        } else {
            // Clean up unmounted drives from driveCache
            let currentMounts = Set(detected.map { $0.mountPoint })
            self.driveCache = self.driveCache.filter { currentMounts.contains($0.key) }

            // 1. Maintain active device if still connected, otherwise pick first
            if let current = activeDevice, let stillPresent = detectedDevices.first(where: { $0.id == current.id }) {
                self.activeDevice = stillPresent
            } else {
                self.activeDevice = detectedDevices.first
            }
            self.deviceInfo = self.activeDevice?.deviceInfo

            // 2. Maintain active drive for the active device
            let availableDrives = self.activeDevice?.drives ?? detected
            let targetDrive: WalkmanDrive?
            if let current = activeDrive, availableDrives.contains(where: { $0.mountPoint == current.mountPoint }) {
                targetDrive = current
            } else {
                targetDrive = self.activeDevice?.microsdDrive ?? availableDrives.first
            }

            if let target = targetDrive, activeDrive?.mountPoint != target.mountPoint {
                self.activeDrive = target
                if let cached = driveCache[target.mountPoint], cached.isLoaded {
                    self.tracks = cached.tracks
                    self.cachedArtists = cached.cachedArtists
                    self.cachedAlbums = cached.cachedAlbums
                    self.cachedRecentTracks = cached.cachedRecentTracks
                    self.cachedLanguageTracks = cached.cachedLanguageTracks
                    self.libraryStats = cached.libraryStats
                } else {
                    self.tracks = []
                    self.cachedArtists = []
                    self.cachedAlbums = []
                    self.cachedRecentTracks = []
                    self.cachedLanguageTracks = []
                    self.libraryStats = (0, 0, 0, 0, 0)
                }
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
            self.cachedLanguageTracks = []
            self.libraryStats = (0, 0, 0, 0, 0)
            self.isScanning = false
            return
        }
        
        isScanning = true
        let expectedMount = drive.mountPoint
        
        libraryScanTask?.cancel()
        libraryScanTask = Task {
            var scanDirs: [URL] = [URL(fileURLWithPath: drive.musicDir)]
            let learningURL = URL(fileURLWithPath: drive.learningDir)
            if FileManager.default.fileExists(atPath: learningURL.path) {
                scanDirs.append(learningURL)
            }
            if Task.isCancelled { return }
            let result = await LibraryScanner.shared.scan(directories: scanDirs)
            if Task.isCancelled { return }
            
            // Precompute library statistics and models off the main thread once
            let (stats, precomputedArtists, precomputedAlbums, precomputedRecent, precomputedLanguage) = await Task.detached(priority: .userInitiated) {
                let artists = ArtistsView.buildArtists(from: result.tracks)
                let albums = AlbumsView.buildAlbums(from: result.tracks)
                let recent = result.tracks.sorted { $0.dateAdded > $1.dateAdded }
                let language = result.tracks.filter { $0.isLanguageStudy }
                
                var albumSet = Set<String>()
                var artistSet = Set<String>()
                var hiRes = 0
                let languageStudy = language.count
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
                let computedStats = (albumSet.count, artistSet.count, hiRes, recentCount, languageStudy)
                return (computedStats, artists, albums, recent, language)
            }.value
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                let cacheEntry = DriveLibraryCache(
                    tracks: result.tracks,
                    cachedArtists: precomputedArtists,
                    cachedAlbums: precomputedAlbums,
                    cachedRecentTracks: precomputedRecent,
                    cachedLanguageTracks: precomputedLanguage,
                    libraryStats: stats,
                    isLoaded: true
                )
                self.driveCache[expectedMount] = cacheEntry
                
                guard self.activeDrive?.mountPoint == expectedMount else { return }
                self.tracks = result.tracks
                self.cachedArtists = precomputedArtists
                self.cachedAlbums = precomputedAlbums
                self.cachedRecentTracks = precomputedRecent
                self.cachedLanguageTracks = precomputedLanguage
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
        let precomputedLanguage = newTracks.filter { $0.isLanguageStudy }
        
        self.cachedArtists = precomputedArtists
        self.cachedAlbums = precomputedAlbums
        self.cachedRecentTracks = precomputedRecent
        self.cachedLanguageTracks = precomputedLanguage
        
        // Update all relevant driveCache entries
        for (mount, cached) in driveCache {
            var updatedCacheTracks = cached.tracks
            var didModify = false
            for i in 0..<updatedCacheTracks.count {
                if let updated = map[updatedCacheTracks[i].fullPath] {
                    updatedCacheTracks[i] = updated
                    didModify = true
                }
            }
            if didModify {
                let cacheArtists = ArtistsView.buildArtists(from: updatedCacheTracks)
                let cacheAlbums = AlbumsView.buildAlbums(from: updatedCacheTracks)
                let cacheRecent = updatedCacheTracks.sorted { $0.dateAdded > $1.dateAdded }
                let cacheLanguage = updatedCacheTracks.filter { $0.isLanguageStudy }
                driveCache[mount] = DriveLibraryCache(
                    tracks: updatedCacheTracks,
                    cachedArtists: cacheArtists,
                    cachedAlbums: cacheAlbums,
                    cachedRecentTracks: cacheRecent,
                    cachedLanguageTracks: cacheLanguage,
                    libraryStats: cached.libraryStats,
                    isLoaded: true
                )
            }
        }
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
        self.cachedLanguageTracks.removeAll(where: { $0.id == track.id })
        self.cachedAlbums = AlbumsView.buildAlbums(from: self.tracks)
        self.cachedArtists = ArtistsView.buildArtists(from: self.tracks)
        
        var albumSet = Set<String>()
        var artistSet = Set<String>()
        var hiRes = 0
        var languageStudy = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        var recentCount = 0
        for tr in self.tracks {
            let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
            let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            albumSet.insert(cleanAlb.lowercased())
            if !art.isEmpty { artistSet.insert(art) }
            if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { hiRes += 1 }
            if tr.isLanguageStudy { languageStudy += 1 }
            if tr.dateAdded >= thirtyDaysAgo { recentCount += 1 }
        }
        if recentCount == 0 && !self.tracks.isEmpty {
            recentCount = min(50, self.tracks.count)
        }
        self.libraryStats = (albumSet.count, artistSet.count, hiRes, recentCount, languageStudy)
        
        // Also remove from driveCache
        for (mount, cached) in driveCache {
            if cached.tracks.contains(where: { $0.id == track.id }) {
                var updatedCacheTracks = cached.tracks
                updatedCacheTracks.removeAll(where: { $0.id == track.id })
                let cacheRecent = cached.cachedRecentTracks.filter { $0.id != track.id }
                let cacheLanguage = cached.cachedLanguageTracks.filter { $0.id != track.id }
                let cacheAlbums = AlbumsView.buildAlbums(from: updatedCacheTracks)
                let cacheArtists = ArtistsView.buildArtists(from: updatedCacheTracks)
                
                var cAlbumSet = Set<String>()
                var cArtistSet = Set<String>()
                var cHiRes = 0
                var cLanguageStudy = 0
                var cRecentCount = 0
                for tr in updatedCacheTracks {
                    let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
                    let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                    cAlbumSet.insert(cleanAlb.lowercased())
                    if !art.isEmpty { cArtistSet.insert(art) }
                    if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { cHiRes += 1 }
                    if tr.isLanguageStudy { cLanguageStudy += 1 }
                    if tr.dateAdded >= thirtyDaysAgo { cRecentCount += 1 }
                }
                if cRecentCount == 0 && !updatedCacheTracks.isEmpty {
                    cRecentCount = min(50, updatedCacheTracks.count)
                }
                driveCache[mount] = DriveLibraryCache(
                    tracks: updatedCacheTracks,
                    cachedArtists: cacheArtists,
                    cachedAlbums: cacheAlbums,
                    cachedRecentTracks: cacheRecent,
                    cachedLanguageTracks: cacheLanguage,
                    libraryStats: (cAlbumSet.count, cArtistSet.count, cHiRes, cRecentCount, cLanguageStudy),
                    isLoaded: true
                )
            }
        }
        
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
        self.cachedLanguageTracks.removeAll(where: { trackIds.contains($0.id) })
        self.cachedAlbums = AlbumsView.buildAlbums(from: self.tracks)
        self.cachedArtists = ArtistsView.buildArtists(from: self.tracks)
        
        var albumSet = Set<String>()
        var artistSet = Set<String>()
        var hiRes = 0
        var languageStudy = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        var recentCount = 0
        for tr in self.tracks {
            let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
            let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            albumSet.insert(cleanAlb.lowercased())
            if !art.isEmpty { artistSet.insert(art) }
            if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { hiRes += 1 }
            if tr.isLanguageStudy { languageStudy += 1 }
            if tr.dateAdded >= thirtyDaysAgo { recentCount += 1 }
        }
        if recentCount == 0 && !self.tracks.isEmpty {
            recentCount = min(50, self.tracks.count)
        }
        self.libraryStats = (albumSet.count, artistSet.count, hiRes, recentCount, languageStudy)
        
        // Also remove from driveCache
        for (mount, cached) in driveCache {
            let hasAlbumTracks = cached.tracks.contains(where: { trackIds.contains($0.id) })
            if hasAlbumTracks {
                var updatedCacheTracks = cached.tracks
                updatedCacheTracks.removeAll(where: { trackIds.contains($0.id) })
                let cacheRecent = cached.cachedRecentTracks.filter { !trackIds.contains($0.id) }
                let cacheLanguage = cached.cachedLanguageTracks.filter { !trackIds.contains($0.id) }
                let cacheAlbums = AlbumsView.buildAlbums(from: updatedCacheTracks)
                let cacheArtists = ArtistsView.buildArtists(from: updatedCacheTracks)
                
                var cAlbumSet = Set<String>()
                var cArtistSet = Set<String>()
                var cHiRes = 0
                var cLanguageStudy = 0
                var cRecentCount = 0
                for tr in updatedCacheTracks {
                    let alb = tr.album.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanAlb = alb.isEmpty ? "Unknown Album" : alb
                    let art = tr.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                    cAlbumSet.insert(cleanAlb.lowercased())
                    if !art.isEmpty { cArtistSet.insert(art) }
                    if tr.bitsPerSample > 16 || tr.sampleRate > 48000 { cHiRes += 1 }
                    if tr.isLanguageStudy { cLanguageStudy += 1 }
                    if tr.dateAdded >= thirtyDaysAgo { cRecentCount += 1 }
                }
                if cRecentCount == 0 && !updatedCacheTracks.isEmpty {
                    cRecentCount = min(50, updatedCacheTracks.count)
                }
                driveCache[mount] = DriveLibraryCache(
                    tracks: updatedCacheTracks,
                    cachedArtists: cacheArtists,
                    cachedAlbums: cacheAlbums,
                    cachedRecentTracks: cacheRecent,
                    cachedLanguageTracks: cacheLanguage,
                    libraryStats: (cAlbumSet.count, cArtistSet.count, cHiRes, cRecentCount, cLanguageStudy),
                    isLoaded: true
                )
            }
        }
        
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
    
    @ViewBuilder
    private var disconnectedDeviceView: some View {
        Group {
            if let usbDev = usbDetector.connectedDevices.first(where: { $0.isAndroid }) {
                usbMtpConnectedDeviceView(usbDev)
            } else {
                pureDisconnectedDeviceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WalkmanTheme.background)
    }

    private func resolvedUsbDeviceTitle(_ usbDev: ConnectedUSBWalkman) -> String {
        let name = usbDev.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("sony") {
            return name
        } else if name.lowercased().contains("walkman") {
            return "Sony \(name)"
        } else {
            return "Sony Walkman \(name)"
        }
    }

    @ViewBuilder
    private func usbMtpConnectedDeviceView(_ usbDev: ConnectedUSBWalkman) -> some View {
        VStack(spacing: 22) {
            Spacer()
            
            // Hero Icon / Hardware Avatar
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(WalkmanTheme.card)
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
                    
                    WalkmanDeviceIconView(
                        size: 72,
                        modelName: usbDev.modelName,
                        hasBackground: false
                    )
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("USB Connected • MTP File Transfer")
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(Color.green.opacity(0.95))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.green.opacity(0.28), lineWidth: 0.8)
                )
            }
            
            // Device Title & macOS MTP Notice
            VStack(spacing: 6) {
                Text(resolvedUsbDeviceTitle(usbDev))
                    .font(WalkmanFont.title2)
                    .foregroundStyle(.white)
                
                Text("Android Walkmans connect in MTP mode. macOS does not mount internal storage into Finder automatically.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            
            // Guidance Info Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 32, height: 32)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(WalkmanTheme.hiResGoldLight)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Direct Music Folder Selection (Recommended)")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(.white)
                        Text("Select your Walkman's Music folder directly to manage tracks, tags, and fetch companion .lrc lyrics instantly.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                Divider()
                    .overlay(Color.white.opacity(0.08))
                
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 32, height: 32)
                        Image(systemName: "externaldrive.badge.wifi")
                            .font(.system(size: 14))
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Finder Virtual Volume Mount")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(.white)
                        Text("Use free macOS MTP utilities (like MacDroid or OpenMTP) to mount storage to /Volumes/ for automatic scanning.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WalkmanTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 500)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
            
            // Single Unified Action Controls (Zero Duplication)
            HStack(spacing: 12) {
                Button(action: selectCustomStorageFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Select Storage Folder...")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
                .help("Browse and select your Walkman's Music folder or MicroSD card directory")
                
                Button(action: { showingMtpHelpSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Mac Transfer Guide")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                .help("Open step-by-step instructions for Android Walkman file transfer on macOS")
                
                Button(action: refreshDrives) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Detect Drives")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                .help("Scan macOS volumes for mounted Walkman storage or inserted MicroSD cards")
            }
            .padding(.top, 4)
            
            Spacer()
        }
    }

    @ViewBuilder
    private var pureDisconnectedDeviceView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 3)
                
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 36))
                    .foregroundStyle(WalkmanTheme.silver)
            }
            
            VStack(spacing: 8) {
                Text("Connect Sony Walkman")
                    .font(WalkmanFont.title1)
                    .foregroundStyle(.white)
                
                Text("Plug in your Sony Walkman via USB cable or insert your MicroSD card. Both classic Sony OS and modern Android-based Walkmans are supported.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            
            if let unsupported = WalkmanEngine.shared.lastUnsupportedModel {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(WalkmanTheme.hiResGold)
                        Text("Unrecognized Device: \(unsupported)")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(.white)
                    }
                    Text("Ensure your Sony Walkman or MicroSD card is properly formatted with a /Music/ or /MUSIC/ directory.")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: 440)
            }
            
            HStack(spacing: 12) {
                Button(action: refreshDrives) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Detect Drives")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
                .help("Scan macOS volumes for mounted Walkman storage or inserted MicroSD cards")
                
                Button(action: selectCustomStorageFolder) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Select Storage Folder...")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                .help("Select a Walkman Music folder or MicroSD card manually")
                
                Button(action: { showingMtpHelpSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Mac Transfer Guide")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                .help("Instructions for Android Walkman file transfer on macOS")
            }
            
            Spacer()
        }
    }

    @ViewBuilder
    private var walkmanLoadingView: some View {
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
    }

    public var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                SidebarView(
                    selectedTab: $selectedTab,
                    devices: devices,
                    drives: drives,
                    activeDevice: activeDevice,
                    trackCount: tracks.count,
                    localTrackCount: localLibrary.tracks.count,
                    localSenseMeCount: localLibrary.tracks.filter { $0.isSenseMeAnalyzed }.count,
                    isWalkmanConnected: !drives.isEmpty,
                    recentlyAddedCount: libraryStats.recentlyAdded,
                    albumCount: libraryStats.albums,
                    artistCount: libraryStats.artists,
                    hiResCount: libraryStats.hiRes,
                    languageStudyCount: libraryStats.languageStudy,
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
                .removeSidebarToggle()
            } detail: {
                ZStack(alignment: .bottom) {
                    ZStack {
                        WalkmanTheme.background
                            .ignoresSafeArea()
                        
                        switch selectedTab {
                        case .overview:
                            if drives.isEmpty {
                                disconnectedDeviceView
                            } else {
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
                            }

                        case .localLibrary:
                            LocalLibraryView(
                                tracks: localLibrary.tracks,
                                folders: localLibrary.folders,
                                isLoading: localLibrary.isScanning,
                                drives: drives,
                                activeDrive: activeDrive,
                                selectedTrackId: $selectedTrackId,
                                onInspectTrack: { track in
                                    self.selectedTrackId = track.id
                                    self.showInspector = true
                                },
                                onDeleteTrack: { track in
                                    localLibrary.deleteTrack(track: track, moveToTrash: false)
                                },
                                onEditTrack: { track in
                                    self.trackToEdit = track
                                },
                                onEditTrackWithList: { track, list in
                                    self.trackListToEdit = list
                                    self.trackToEdit = track
                                },
                                onTrimCutTrack: { track in
                                    self.trackToTrimCut = track
                                },
                                onGoToTransfer: {
                                    self.selectedTab = .transfer
                                },
                                onEditAlbum: { album in
                                    self.albumToEdit = album
                                },
                                onTransferComplete: {
                                    self.refreshLibrary()
                                }
                            )

                        case .senseMe:
                            SenseMeChannelsView(
                                onInspectTrack: { track in
                                    self.selectedTrackId = track.id
                                    self.showInspector = true
                                },
                                onEditTrack: { track in
                                    self.trackToEdit = track
                                },
                                onTrimCutTrack: { track in
                                    self.trackToTrimCut = track
                                },
                                onGoToTransfer: {
                                    self.selectedTab = .transfer
                                },
                                onNavigateToLocalLibrary: {
                                    self.selectedTab = .localLibrary
                                }
                            )
                            
                        case .library:
                            if isScanning && tracks.isEmpty {
                                walkmanLoadingView
                            } else {
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
                                    },
                                    onNavigateToArtist: { artist in
                                        self.targetArtistName = artist
                                        self.selectedTab = .artists
                                    },
                                    onNavigateToAlbum: { album, artist in
                                        self.targetAlbumName = album
                                        self.targetAlbumArtist = artist
                                        self.selectedTab = .albums
                                    }
                                )
                                .id("library_\(activeDrive?.mountPoint ?? "no_drive")")
                            }
                                
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
                                    },
                                    onNavigateToArtist: { artist in
                                        self.targetArtistName = artist
                                        self.selectedTab = .artists
                                    },
                                    onNavigateToAlbum: { album, artist in
                                        self.targetAlbumName = album
                                        self.targetAlbumArtist = artist
                                        self.selectedTab = .albums
                                    }
                                )
                                .id("recent_\(activeDrive?.mountPoint ?? "no_drive")")
                                
                            case .albums:
                                AlbumsView(
                                    tracks: tracks,
                                    precomputedAlbums: cachedAlbums,
                                    initialSelectedAlbumName: targetAlbumName,
                                    initialSelectedAlbumArtist: targetAlbumArtist,
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
                                    onEditTrackWithList: { track, list in
                                        self.trackListToEdit = list
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
                                .id("albums_\(activeDrive?.mountPoint ?? "no_drive")_\(targetAlbumName ?? "all")")
                                
                            case .artists:
                                ArtistsView(
                                    tracks: tracks,
                                    precomputedArtists: cachedArtists,
                                    initialSelectedArtistName: targetArtistName,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onEditTrackWithList: { track, list in
                                        self.trackListToEdit = list
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    }
                                )
                                .id("artists_\(activeDrive?.mountPoint ?? "no_drive")_\(targetArtistName ?? "all")")
                                
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
                                    onEditTrackWithList: { track, list in
                                        self.trackListToEdit = list
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
                                .id("hires_\(activeDrive?.mountPoint ?? "no_drive")")
                                
                            case .languageStudy:
                                LanguageStudyView(
                                    tracks: cachedLanguageTracks,
                                    activeDrive: activeDrive,
                                    onSelectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    },
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onEditTrackWithList: { track, list in
                                        self.trackListToEdit = list
                                        self.trackToEdit = track
                                    },
                                    onTrimCutTrack: { track in
                                        self.trackToTrimCut = track
                                    },
                                    onDeleteTrack: { track in
                                        deleteTrackFromDevice(track)
                                    },
                                    onNavigateToTransfer: {
                                        self.selectedTab = .transfer
                                    }
                                )
                                .id("language_\(activeDrive?.mountPoint ?? "no_drive")")
                                
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
                                    libraryTracks: tracks,
                                    onTransferComplete: { refreshLibrary() }
                                )
                                .padding(14)
                                
                            case .playlists:
                                PlaylistsView(
                                    activeDrive: activeDrive,
                                    libraryTracks: tracks,
                                    onEditTrack: { track in
                                        self.trackToEdit = track
                                    },
                                    onEditTrackWithList: { track, list in
                                        self.trackListToEdit = list
                                        self.trackToEdit = track
                                    },
                                    onInspectTrack: { track in
                                        self.selectedTrackId = track.id
                                        self.showInspector = true
                                    }
                                )
                                .id("playlists_\(activeDrive?.mountPoint ?? "no_drive")")
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
                                libraryTracks: !tracks.isEmpty ? tracks : localLibrary.tracks,
                                isInspectorPresented: showInspector,
                                onOpenInspector: {
                                    if let cur = player.currentTrack {
                                        self.selectedTrackId = cur.id
                                    }
                                    self.showInspector = true
                                },
                                onOpenFullScreen: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        self.isFullScreenPlayerPresented = true
                                    }
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
                    .adaptiveInspector(isPresented: Binding(
                        get: { showInspector && !isFullScreenPlayerPresented },
                        set: { showInspector = $0 }
                    )) {
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
                        if !isFullScreenPlayerPresented {
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
                            Button(action: {
                                if !showInspector && selectedTrackId == nil, let cur = player.currentTrack {
                                    self.selectedTrackId = cur.id
                                }
                                showInspector.toggle()
                            }) {
                                Label("Inspector", systemImage: "sidebar.trailing")
                            }
                            .help("Toggle Metadata & Artwork Inspector (Cmd+I)")
                            .keyboardShortcut("i", modifiers: [.command])
                        }
                    }
                    .toolbarBackground(.hidden, for: .windowToolbar)
                    .removeSidebarToggle()
                }
                .navigationSplitViewStyle(.balanced)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .toolbar(isFullScreenPlayerPresented ? .hidden : .visible, for: .windowToolbar)
                .removeSidebarToggle()
                .opacity(isFullScreenPlayerPresented ? 0 : 1)

            if isFullScreenPlayerPresented {
                FullScreenNowPlayingView(
                    isPresented: $isFullScreenPlayerPresented,
                    libraryTracks: !tracks.isEmpty ? tracks : localLibrary.tracks
                )
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985)),
                    removal: .opacity.combined(with: .scale(scale: 0.985))
                ))
                .zIndex(100)
            }
        }
        .onAppear {
            refreshDrives()
            AudioPlayerService.shared.fallbackTracksProvider = {
                !tracks.isEmpty ? tracks : localLibrary.tracks
            }
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
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab != .albums {
                targetAlbumName = nil
                targetAlbumArtist = nil
            }
            if newTab != .artists {
                targetArtistName = nil
            }
        }
        .onChange(of: player.currentTrack?.id) { _, newTrackId in
            if let newId = newTrackId {
                self.selectedTrackId = newId
            }
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if isPlaying, let cur = player.currentTrack {
                self.selectedTrackId = cur.id
            }
        }
        .onChange(of: isFullScreenPlayerPresented) {
            FullScreenNowPlayingView.setWindowToolbarVisible(!isFullScreenPlayerPresented)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWalkmanStudio)) { _ in
            self.showAboutSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .manageLocalFolders)) { _ in
            self.showManageFoldersSheet = true
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutWalkmanStudioView(
                currentDeviceInfo: deviceInfo,
                onDismiss: { showAboutSheet = false }
            )
        }
        .sheet(isPresented: $showManageFoldersSheet) {
            ManageLocalFoldersSheet(
                onDismiss: { showManageFoldersSheet = false }
            )
        }
        .sheet(isPresented: $showingMtpHelpSheet) {
            AndroidWalkmanMtpHelpSheet(
                onDismiss: { showingMtpHelpSheet = false }
            )
        }
        .sheet(item: $trackToEdit) { track in
            SongMetadataEditorSheet(
                track: track,
                trackList: getEditingTrackList(for: track),
                onSavedTrack: { updatedTrack in
                    if self.player.currentTrack?.id == updatedTrack.id {
                        self.player.updateTrackInfo(track: updatedTrack)
                    }
                    if self.localLibrary.tracks.contains(where: { $0.id == updatedTrack.id }) {
                        self.localLibrary.updateTrack(track: updatedTrack)
                    } else {
                        self.updateTracksInMemory([updatedTrack])
                        self.refreshLibrary()
                    }
                    if let idx = self.trackListToEdit.firstIndex(where: { $0.id == updatedTrack.id }) {
                        self.trackListToEdit[idx] = updatedTrack
                    }
                },
                onDismiss: {
                    trackToEdit = nil
                    trackListToEdit = []
                }
            )
        }
        .sheet(item: $trackToTrimCut) { track in
            TrimAndCutSheet(
                track: track,
                onSaved: {
                    if self.localLibrary.tracks.contains(where: { $0.id == track.id }) {
                        self.localLibrary.rescanAllFolders()
                    } else {
                        self.refreshLibrary()
                    }
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
                    for t in updatedTracks {
                        if self.localLibrary.tracks.contains(where: { $0.id == t.id }) {
                            self.localLibrary.updateTrack(track: t)
                        }
                    }
                    self.updateTracksInMemory(updatedTracks)
                },
                onDismiss: {
                    albumToEdit = nil
                }
            )
        }
        .background(WindowAccessor { window in
            self.hostWindow = window
        })
        .onChange(of: showInspector) { isPresented in
            handleInspectorVisibilityChanged(isPresented: isPresented)
        }
    }

    // -------------------------------------------------------------------------
    // WINDOW EXPANSION ON TRACK DETAIL (INSPECTOR) TOGGLE
    // -------------------------------------------------------------------------
    private func handleInspectorVisibilityChanged(isPresented: Bool) {
        guard let window = hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }

        // Do not attempt window frame resize in macOS native fullscreen
        if window.styleMask.contains(.fullScreen) { return }

        let inspectorWidth: CGFloat = 300.0
        let minW: CGFloat = window.minSize.width > 0 ? window.minSize.width : 1320
        let currentFrame = window.frame
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? currentFrame

        if isPresented {
            // Record pre-open width
            self.savedWidthBeforeInspector = currentFrame.size.width

            let targetWidth = min(currentFrame.size.width + inspectorWidth, visibleFrame.width)
            self.expectedWidthWithInspector = targetWidth

            var targetOriginX = currentFrame.origin.x
            if targetOriginX + targetWidth > visibleFrame.maxX {
                let overflow = (targetOriginX + targetWidth) - visibleFrame.maxX
                targetOriginX = max(visibleFrame.minX, targetOriginX - overflow)
            }
            self.savedShiftOnInspectorOpen = currentFrame.origin.x - targetOriginX

            var newFrame = currentFrame
            newFrame.origin.x = targetOriginX
            newFrame.size.width = targetWidth

            window.setFrame(newFrame, display: true)
        } else {
            // Determine contracted target width
            let targetWidth: CGFloat
            if let saved = savedWidthBeforeInspector, abs(currentFrame.size.width - expectedWidthWithInspector) < 15 {
                targetWidth = max(saved, minW)
            } else {
                targetWidth = max(currentFrame.size.width - inspectorWidth, minW)
            }

            var targetOriginX = currentFrame.origin.x
            if savedShiftOnInspectorOpen > 0, abs(currentFrame.size.width - expectedWidthWithInspector) < 15 {
                targetOriginX = min(currentFrame.origin.x + savedShiftOnInspectorOpen, visibleFrame.maxX - targetWidth)
            }

            self.savedWidthBeforeInspector = nil
            self.savedShiftOnInspectorOpen = 0
            self.expectedWidthWithInspector = 0

            var newFrame = currentFrame
            newFrame.origin.x = targetOriginX
            newFrame.size.width = targetWidth

            window.setFrame(newFrame, display: true)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window {
                onWindow(w)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window {
                onWindow(w)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func adaptiveInspector<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self
            .padding(.trailing, isPresented.wrappedValue ? 301 : 0)
            .animation(nil, value: isPresented.wrappedValue)
            .overlay(alignment: .trailing) {
                if isPresented.wrappedValue {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 1)
                        content()
                            .frame(width: 300)
                            .background(WalkmanTheme.background)
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: isPresented.wrappedValue)
    }

    @ViewBuilder
    func removeSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
