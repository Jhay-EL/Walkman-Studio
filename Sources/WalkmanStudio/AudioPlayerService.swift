import Foundation
import AVFoundation
import AppKit
import Combine

public final class AudioPlayerService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AudioPlayerService()

    @Published public var currentTrack: Track?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0.0
    @Published public var duration: Double = 0.0
    @Published public var volume: Float = 0.8 {
        didSet {
            player.volume = volume
        }
    }
    @Published public var currentCoverArt: NSImage?
    @Published public var isSeeking: Bool = false

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
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            self.currentTime = CMTimeGetSeconds(time)
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

    public func prepare(track: Track, in queue: [Track] = [], autoPlay: Bool = false) {
        if let current = currentTrack, current.id == track.id {
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
        self.currentTime = 0.0
        self.duration = track.durationSeconds
        self.isPlaying = autoPlay

        let url = URL(fileURLWithPath: track.fullPath)
        
        // Asynchronous asset loading off the main UI thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let item = AVPlayerItem(asset: asset)
            
            DispatchQueue.main.async {
                guard let self = self, self.currentTrack?.id == track.id else { return }
                self.player.replaceCurrentItem(with: item)
                if autoPlay {
                    self.player.play()
                    self.isPlaying = true
                }
            }
        }

        loadArtwork(for: track)
    }

    public func play(track: Track, in queue: [Track] = []) {
        if currentTrack?.id == track.id {
            if !isPlaying {
                player.play()
                self.isPlaying = true
            }
            return
        }

        prepare(track: track, in: queue, autoPlay: true)
    }

    public func pause() {
        player.pause()
        self.isPlaying = false
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
        currentTime = seconds
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeeking = false
        }
    }

    public func playNext() {
        guard let current = currentTrack, !currentQueue.isEmpty else { return }
        if let idx = currentQueue.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = idx + 1
            if nextIdx < currentQueue.count {
                play(track: currentQueue[nextIdx], in: currentQueue)
            } else {
                pause()
                seek(to: 0)
            }
        }
    }

    public func playPrevious() {
        guard let current = currentTrack, !currentQueue.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        if let idx = currentQueue.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = idx - 1
            if prevIdx >= 0 {
                play(track: currentQueue[prevIdx], in: currentQueue)
            } else {
                seek(to: 0)
            }
        }
    }

    private func loadArtwork(for track: Track) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = URL(fileURLWithPath: track.fullPath)
            if let data = AudioTagger.shared.extractCoverArt(fileURL: url),
               let img = NSImage(data: data) {
                DispatchQueue.main.async {
                    if self?.currentTrack?.id == track.id {
                        self?.currentCoverArt = img
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if self?.currentTrack?.id == track.id {
                        self?.currentCoverArt = nil
                    }
                }
            }
        }
    }
}
