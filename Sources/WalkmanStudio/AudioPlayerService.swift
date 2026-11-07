import Foundation
import AVFoundation
import AppKit
import Combine
import MediaPlayer

public final class PlaybackProgress: ObservableObject, @unchecked Sendable {
    @Published public var currentTime: Double = 0.0
    @Published public var duration: Double = 0.0

    public init(currentTime: Double = 0.0, duration: Double = 0.0) {
        self.currentTime = currentTime
        self.duration = duration
    }
}

public final class AudioPlayerService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AudioPlayerService()

    /// Dedicated high-frequency playback progress object.
    /// Observers of AudioPlayerService won't be invalidated by sub-second timer ticks.
    public let progress = PlaybackProgress()

    @Published public var currentTrack: Track?
    @Published public var isPlaying: Bool = false
    @Published public var volume: Float = 0.8 {
        didSet {
            player.volume = volume
        }
    }
    @Published public var currentCoverArt: NSImage?
    @Published public var isSeeking: Bool = false
    @Published public var isShuffle: Bool = false
    @Published public var isRepeat: Bool = false
    
    /// Timestamp where the current track started (e.g. SensMe highlight position)
    @Published public var currentHighlightStartTime: Double? = nil

    /// If set (e.g. 45.0 for SensMe Highlight Preview mode), automatically advances to the next track when duration is reached
    @Published public var highlightPreviewDuration: Double? = nil

    /// Optional callback to customize next track starting time in specialized modes like SensMe (isManualSkip indicates whether user skipped)
    public var onAdvanceToNextTrack: ((_ nextTrack: Track, _ isManualSkip: Bool) -> Double?)? = nil

    /// Convenience accessors forwarding to `progress`
    public var currentTime: Double {
        get { progress.currentTime }
        set { progress.currentTime = newValue }
    }
    public var duration: Double {
        get { progress.duration }
        set { progress.duration = newValue }
    }

    private var player: AVPlayer = AVPlayer()
    private var timeObserverToken: Any?
    private var localKeyMonitor: Any?
    public var currentQueue: [Track] = []

    /// Optional external tracks provider (e.g. from connected Walkman DAP or Local Library)
    public var fallbackTracksProvider: (@MainActor () -> [Track])?

    /// Optional dynamic queue provider for the currently selected/focused tab (e.g. Songs, Recently Added)
    public var activeQueueProvider: (@MainActor () -> [Track]?)?

    /// Effective queue guaranteed to return a usable list of tracks
    public var effectiveQueue: [Track] {
        if Thread.isMainThread {
            if let active = MainActor.assumeIsolated({ activeQueueProvider?() }), !active.isEmpty {
                return active
            }
        }
        if !currentQueue.isEmpty {
            return currentQueue
        }
        if Thread.isMainThread {
            if let list = MainActor.assumeIsolated({ fallbackTracksProvider?() }), !list.isEmpty {
                return list
            }
        }
        return LocalMusicLibraryService.shared.tracks
    }

    private override init() {
        super.init()
        player.volume = volume
        setupTimeObserver()
        setupEndObserver()
        setupRemoteCommands()
        setupSystemMediaKeyMonitor()
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 44100)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            let sec = CMTimeGetSeconds(time)
            self.progress.currentTime = sec
            
            // Check if SensMe Highlight Preview duration has elapsed (e.g. 45 seconds from highlight start)
            if let start = self.currentHighlightStartTime, let maxDur = self.highlightPreviewDuration, maxDur > 0 {
                if sec >= (start + maxDur) {
                    self.playNext()
                }
            }
        }
    }

    private func setupEndObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.playNext(isManualSkip: false)
        }
    }

    // =========================================================================
    // SYSTEM DEVICE CONTROLS: MPRemoteCommandCenter & MPNowPlayingInfoCenter
    // =========================================================================

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Toggle Play / Pause (Media Key Play/Pause, Touch Bar, AirPods, Bluetooth headsets)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pause()
            return .success
        }

        // Next Track (Media Key Next F9, Touch Bar Next, Bluetooth Next)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playNext()
            return .success
        }

        // Previous Track (Media Key Prev F7, Touch Bar Prev, Bluetooth Prev)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playPrevious()
            return .success
        }

        // Scrubbing on Touch Bar / Now Playing Slider
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: posEvent.positionTime)
            return .success
        }
    }

    // =========================================================================
    // HARDWARE KEYBOARD EVENT MONITOR: SPACEBAR & FUNCTION ROW MEDIA KEYS
    // =========================================================================

    private func setupSystemMediaKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            guard let self = self else { return event }

            // 1. SPACEBAR HANDLING (keyCode 49)
            // Works globally in Walkman Studio regardless of table or view focus.
            if event.type == .keyDown && event.keyCode == 49 {
                // If user is currently focused in an editable text field / search field, pass space through
                if let responder = NSApp.keyWindow?.firstResponder {
                    if responder is NSTextView || responder is NSTextField || responder is NSText {
                        return event
                    }
                }
                self.togglePlayPause()
                return nil // Consumed: prevents table selection jump or audio beep
            }

            // 2. FUNCTION ROW KEYS & KEYBOARD SHORTCUTS
            if event.type == .keyDown {
                // F7 (keyCode 98) -> Previous Track
                if event.keyCode == 98 {
                    self.playPrevious()
                    return nil
                }
                // F8 (keyCode 100) -> Play / Pause
                if event.keyCode == 100 {
                    self.togglePlayPause()
                    return nil
                }
                // F9 (keyCode 101) -> Next Track
                if event.keyCode == 101 {
                    self.playNext()
                    return nil
                }

                // Cmd + Right Arrow (keyCode 124) -> Next Track
                if event.modifierFlags.contains(.command) && event.keyCode == 124 {
                    self.playNext()
                    return nil
                }
                // Cmd + Left Arrow (keyCode 123) -> Previous Track
                if event.modifierFlags.contains(.command) && event.keyCode == 123 {
                    self.playPrevious()
                    return nil
                }
            }

            // 3. SYSTEM-DEFINED HARDWARE MEDIA KEYS (NSSystemDefined Subtype 8)
            if event.type == .systemDefined && event.subtype.rawValue == 8 {
                let keyCode = Int32((event.data1 & 0xFFFF0000) >> 16)
                let keyFlags = (event.data1 & 0x0000FFFF)
                let isKeyDown = (((keyFlags & 0xFF00) >> 8)) == 0xA

                if isKeyDown {
                    switch keyCode {
                    case NX_KEYTYPE_PLAY:
                        self.togglePlayPause()
                        return nil
                    case NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST:
                        self.playNext()
                        return nil
                    case NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND:
                        self.playPrevious()
                        return nil
                    default:
                        break
                    }
                }
            }

            return event
        }
    }

    public func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.title.isEmpty ? track.filename : track.title
        info[MPMediaItemPropertyArtist] = track.artist.isEmpty ? "Unknown Artist" : track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album.isEmpty ? "Unknown Album" : track.album
        let dur = progress.duration > 0 ? progress.duration : track.durationSeconds
        info[MPMediaItemPropertyPlaybackDuration] = max(1.0, dur)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        if let art = currentCoverArt {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func prepare(track: Track, in queue: [Track] = [], autoPlay: Bool = false, startTime: Double? = nil) {
        if let current = currentTrack, current.id == track.id {
            if !queue.isEmpty {
                self.currentQueue = queue
            }
            if let start = startTime {
                self.currentHighlightStartTime = start
                self.progress.currentTime = start
                self.isSeeking = true
                let target = CMTime(seconds: start, preferredTimescale: 44100)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    guard let self = self, finished else { return }
                    self.isSeeking = false
                    let actual = CMTimeGetSeconds(self.player.currentTime())
                    self.progress.currentTime = (actual.isFinite && actual >= 0) ? actual : start
                    if autoPlay && !self.isPlaying {
                        self.player.play()
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                    }
                }
            } else if autoPlay && !isPlaying {
                player.play()
                self.isPlaying = true
                updateNowPlayingInfo()
            }
            return
        }
        self.currentTrack = track
        if !queue.isEmpty {
            self.currentQueue = queue
        } else if self.currentQueue.isEmpty {
            self.currentQueue = effectiveQueue
        }
        let initialTime = startTime ?? 0.0
        self.progress.currentTime = initialTime
        self.progress.duration = track.durationSeconds
        self.isPlaying = autoPlay
        self.currentHighlightStartTime = (initialTime > 0) ? initialTime : nil

        let url = URL(fileURLWithPath: track.fullPath)
        
        // Asynchronous asset loading off the main UI thread with sample-accurate duration & timing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let item = AVPlayerItem(asset: asset)
            let assetDur = CMTimeGetSeconds(asset.duration)
            
            DispatchQueue.main.async {
                guard let self = self, self.currentTrack?.id == track.id else { return }
                if assetDur.isFinite && assetDur > 0 {
                    self.progress.duration = assetDur
                }
                if initialTime > 0 {
                    self.isSeeking = true
                }
                self.player.replaceCurrentItem(with: item)
                if initialTime > 0 {
                    let target = CMTime(seconds: initialTime, preferredTimescale: 44100)
                    self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                        guard let self = self, finished else { return }
                        self.isSeeking = false
                        let actual = CMTimeGetSeconds(self.player.currentTime())
                        self.progress.currentTime = (actual.isFinite && actual >= 0) ? actual : initialTime
                        if self.isPlaying {
                            self.player.play()
                        }
                        self.updateNowPlayingInfo()
                    }
                } else {
                    if self.isPlaying {
                        self.player.play()
                    }
                    self.updateNowPlayingInfo()
                }
            }
        }

        loadArtwork(for: track)
        updateNowPlayingInfo()
    }

    public func play(track: Track, coverArt: NSImage? = nil, in queue: [Track] = [], startTime: Double? = nil) {
        if currentTrack?.id == track.id {
            if !queue.isEmpty {
                self.currentQueue = queue
            }
            if let cover = coverArt {
                self.currentCoverArt = cover
            }
            if let start = startTime {
                self.currentHighlightStartTime = start
                self.progress.currentTime = start
                self.isSeeking = true
                let target = CMTime(seconds: start, preferredTimescale: 44100)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    guard let self = self, finished else { return }
                    self.isSeeking = false
                    let actual = CMTimeGetSeconds(self.player.currentTime())
                    self.progress.currentTime = (actual.isFinite && actual >= 0) ? actual : start
                    if !self.isPlaying {
                        self.player.play()
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                    }
                }
            } else if !isPlaying {
                player.play()
                self.isPlaying = true
                updateNowPlayingInfo()
            }
            return
        }

        prepare(track: track, in: queue, autoPlay: true, startTime: startTime)
        if let cover = coverArt {
            self.currentCoverArt = cover
        }
        updateNowPlayingInfo()
    }

    public func play() {
        if currentTrack != nil {
            player.play()
            self.isPlaying = true
            updateNowPlayingInfo()
        } else if let first = effectiveQueue.first {
            play(track: first, in: effectiveQueue)
        }
    }

    public func playOrToggle(track: Track, coverArt: NSImage? = nil, in queue: [Track] = [], startTime: Double? = nil) {
        if currentTrack?.id == track.id {
            if let start = startTime {
                seek(to: start)
            }
            if let cover = coverArt {
                self.currentCoverArt = cover
            }
            togglePlayPause()
            return
        }
        play(track: track, coverArt: coverArt, in: queue, startTime: startTime)
    }

    public func pause() {
        player.pause()
        self.isPlaying = false
        updateNowPlayingInfo()
    }

    public func stopAndClear() {
        pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentQueue = []
        currentHighlightStartTime = nil
        highlightPreviewDuration = nil
        onAdvanceToNextTrack = nil
        progress.currentTime = 0.0
        progress.duration = 0.0
        currentCoverArt = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to seconds: Double) {
        self.isSeeking = true
        progress.currentTime = seconds
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 44100)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }
            self.isSeeking = false
            let actual = CMTimeGetSeconds(self.player.currentTime())
            if actual.isFinite && actual >= 0 {
                self.progress.currentTime = actual
            }
            self.updateNowPlayingInfo()
        }
        updateNowPlayingInfo()
    }

    /// Accurately jump to a specific timestamp in a track, seamlessly loading/playing it if necessary.
    public func seekTo(time seconds: Double, in track: Track? = nil) {
        let targetTrack = track ?? currentTrack
        guard let target = targetTrack else { return }

        if currentTrack?.id == target.id && player.currentItem != nil {
            self.isSeeking = true
            self.progress.currentTime = seconds
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 44100)
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard let self = self, finished else { return }
                self.isSeeking = false
                let actual = CMTimeGetSeconds(self.player.currentTime())
                if actual.isFinite && actual >= 0 {
                    self.progress.currentTime = actual
                }
                self.updateNowPlayingInfo()
            }
            if !isPlaying {
                player.play()
                self.isPlaying = true
            }
            updateNowPlayingInfo()
        } else {
            play(track: target, startTime: seconds)
        }
    }

    public func playNext(isManualSkip: Bool = true) {
        let queue: [Track]
        if Thread.isMainThread, let active = MainActor.assumeIsolated({ activeQueueProvider?() }), !active.isEmpty {
            queue = active
            self.currentQueue = active
        } else {
            queue = effectiveQueue
        }
        guard !queue.isEmpty else { return }

        guard let current = currentTrack else {
            if let first = queue.first {
                let start = onAdvanceToNextTrack?(first, isManualSkip)
                play(track: first, in: queue, startTime: start)
            }
            return
        }

        if isShuffle && queue.count > 1 {
            let candidates = queue.filter { $0.id != current.id }
            if let random = candidates.randomElement() {
                let start = onAdvanceToNextTrack?(random, isManualSkip)
                play(track: random, in: queue, startTime: start)
                return
            }
        }

        if let idx = queue.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = idx + 1
            if nextIdx < queue.count {
                let next = queue[nextIdx]
                let start = onAdvanceToNextTrack?(next, isManualSkip)
                play(track: next, in: queue, startTime: start)
            } else if let first = queue.first {
                // Loop around queue
                let start = onAdvanceToNextTrack?(first, isManualSkip)
                play(track: first, in: queue, startTime: start)
            }
        } else {
            if let first = queue.first {
                let start = onAdvanceToNextTrack?(first, isManualSkip)
                play(track: first, in: queue, startTime: start)
            }
        }
    }

    public func playPrevious(isManualSkip: Bool = true) {
        let queue: [Track]
        if Thread.isMainThread, let active = MainActor.assumeIsolated({ activeQueueProvider?() }), !active.isEmpty {
            queue = active
            self.currentQueue = active
        } else {
            queue = effectiveQueue
        }
        guard !queue.isEmpty else { return }

        guard let current = currentTrack else {
            if let first = queue.first {
                let start = onAdvanceToNextTrack?(first, isManualSkip)
                play(track: first, in: queue, startTime: start)
            }
            return
        }

        // If played more than 3 seconds, standard media player rewind to start
        if progress.currentTime > 3.0 {
            seek(to: 0)
            return
        }

        if let idx = queue.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = idx - 1
            if prevIdx >= 0 {
                let prev = queue[prevIdx]
                let start = onAdvanceToNextTrack?(prev, isManualSkip)
                play(track: prev, in: queue, startTime: start)
            } else if let last = queue.last {
                let start = onAdvanceToNextTrack?(last, isManualSkip)
                play(track: last, in: queue, startTime: start)
            } else {
                seek(to: 0)
            }
        } else {
            if let last = queue.last {
                let start = onAdvanceToNextTrack?(last, isManualSkip)
                play(track: last, in: queue, startTime: start)
            } else {
                seek(to: 0)
            }
        }
    }

    public func updateTrackInfo(track: Track) {
        if currentTrack?.id == track.id {
            self.currentTrack = track
            loadArtwork(for: track)
            updateNowPlayingInfo()
        }
        for (idx, tr) in currentQueue.enumerated() {
            if tr.id == track.id {
                currentQueue[idx] = track
            }
        }
    }

    private func loadArtwork(for track: Track) {
        if let cached = CoverArtCache.shared.thumbnail(for: track) {
            self.currentCoverArt = cached
            self.updateNowPlayingInfo()
            return
        }
        CoverArtCache.shared.loadThumbnail(for: track, targetSize: 300) { [weak self] img in
            DispatchQueue.main.async {
                if self?.currentTrack?.id == track.id {
                    self?.currentCoverArt = img
                    self?.updateNowPlayingInfo()
                }
            }
        }
    }
}
