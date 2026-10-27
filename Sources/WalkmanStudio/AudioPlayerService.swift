import Foundation
import AVFoundation
import AppKit
import Combine

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
    public var currentQueue: [Track] = []

    private override init() {
        super.init()
        player.volume = volume
        setupTimeObserver()
        setupEndObserver()
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            self.progress.currentTime = CMTimeGetSeconds(time)
        }
    }

    private func setupEndObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.playNext()
        }
    }

    public func prepare(track: Track, in queue: [Track] = [], autoPlay: Bool = false, startTime: Double? = nil) {
        if let current = currentTrack, current.id == track.id {
            if let start = startTime {
                seek(to: start)
            }
            if autoPlay && !isPlaying {
                player.play()
                self.isPlaying = true
            }
            return
        }
        self.currentTrack = track
        if !queue.isEmpty {
            self.currentQueue = queue
        }
        let initialTime = startTime ?? 0.0
        self.progress.currentTime = initialTime
        self.progress.duration = track.durationSeconds
        self.isPlaying = autoPlay

        let url = URL(fileURLWithPath: track.fullPath)
        
        // Asynchronous asset loading off the main UI thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let item = AVPlayerItem(asset: asset)
            
            DispatchQueue.main.async {
                guard let self = self, self.currentTrack?.id == track.id else { return }
                self.player.replaceCurrentItem(with: item)
                if initialTime > 0 {
                    self.isSeeking = true
                    let target = CMTime(seconds: initialTime, preferredTimescale: 600)
                    self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        self?.isSeeking = false
                    }
                }
                if self.isPlaying {
                    self.player.play()
                }
            }
        }

        loadArtwork(for: track)
    }

    public func play(track: Track, coverArt: NSImage? = nil, in queue: [Track] = [], startTime: Double? = nil) {
        if currentTrack?.id == track.id {
            if let cover = coverArt {
                self.currentCoverArt = cover
            }
            if let start = startTime {
                seek(to: start)
            }
            if !isPlaying {
                player.play()
                self.isPlaying = true
            }
            return
        }

        prepare(track: track, in: queue, autoPlay: true, startTime: startTime)
        if let cover = coverArt {
            self.currentCoverArt = cover
        }
    }

    public func play() {
        guard currentTrack != nil else { return }
        player.play()
        self.isPlaying = true
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
    }

    public func stopAndClear() {
        pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentQueue = []
        progress.currentTime = 0.0
        progress.duration = 0.0
        currentCoverArt = nil
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            if currentTrack != nil {
                player.play()
                self.isPlaying = true
            }
        }
    }

    public func seek(to seconds: Double) {
        self.isSeeking = true
        progress.currentTime = seconds
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeeking = false
        }
    }

    /// Accurately jump to a specific timestamp in a track, seamlessly loading/playing it if necessary.
    public func seekTo(time seconds: Double, in track: Track? = nil) {
        let targetTrack = track ?? currentTrack
        guard let target = targetTrack else { return }

        if currentTrack?.id == target.id && player.currentItem != nil {
            self.isSeeking = true
            self.progress.currentTime = seconds
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.isSeeking = false
            }
            if !isPlaying {
                player.play()
                self.isPlaying = true
            }
        } else {
            play(track: target, startTime: seconds)
        }
    }

    public func playNext() {
        guard let current = currentTrack, !currentQueue.isEmpty else { return }
        if isShuffle && currentQueue.count > 1 {
            let candidates = currentQueue.filter { $0.id != current.id }
            if let random = candidates.randomElement() {
                play(track: random, in: currentQueue)
                return
            }
        }
        if let idx = currentQueue.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = idx + 1
            if nextIdx < currentQueue.count {
                play(track: currentQueue[nextIdx], in: currentQueue)
            } else if isRepeat {
                if let first = currentQueue.first {
                    play(track: first, in: currentQueue)
                }
            } else {
                pause()
                seek(to: 0)
            }
        }
    }

    public func playPrevious() {
        guard let current = currentTrack, !currentQueue.isEmpty else { return }
        if progress.currentTime > 3.0 {
            seek(to: 0)
            return
        }
        if let idx = currentQueue.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = idx - 1
            if prevIdx >= 0 {
                play(track: currentQueue[prevIdx], in: currentQueue)
            } else if isRepeat {
                if let last = currentQueue.last {
                    play(track: last, in: currentQueue)
                }
            } else {
                seek(to: 0)
            }
        }
    }

    public func updateTrackInfo(track: Track) {
        if currentTrack?.id == track.id {
            self.currentTrack = track
            loadArtwork(for: track)
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
            return
        }
        CoverArtCache.shared.loadThumbnail(for: track, targetSize: 300) { [weak self] img in
            DispatchQueue.main.async {
                if self?.currentTrack?.id == track.id {
                    self?.currentCoverArt = img
                }
            }
        }
    }
}
