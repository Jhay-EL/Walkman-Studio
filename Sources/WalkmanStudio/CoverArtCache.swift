import Foundation
import AppKit
import SwiftUI

public final class CoverArtCache: @unchecked Sendable {
    public static let shared = CoverArtCache()
    
    private let pathCache = NSCache<NSString, NSImage>()
    private let albumCache = NSCache<NSString, NSImage>()
    
    private let diskCacheURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".walkman_art_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    private let ioQueue = DispatchQueue(label: "com.sony.walkmanstudio.artwork_io", qos: .utility)
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()

    private init() {
        pathCache.countLimit = 2500
        albumCache.countLimit = 1200
    }

    private func diskKey(for track: Track) -> String {
        let key = "\(track.primaryArtist)|\(track.album)".lowercased()
        var hasher = Hasher()
        hasher.combine(key)
        return String(format: "%016llx", UInt64(bitPattern: Int64(hasher.finalize())))
    }

    public func thumbnail(for track: Track) -> NSImage? {
        guard track.hasArtwork else { return nil }
        
        let pKey = track.fullPath as NSString
        if let img = pathCache.object(forKey: pKey) {
            return img
        }
        
        let aKey = "\(track.primaryArtist)|\(track.album)" as NSString
        if let img = albumCache.object(forKey: aKey) {
            pathCache.setObject(img, forKey: pKey)
            return img
        }
        
        // Check local SSD disk cache
        let key = diskKey(for: track)
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        if FileManager.default.fileExists(atPath: fileURL.path),
           let img = NSImage(contentsOf: fileURL) {
            pathCache.setObject(img, forKey: pKey)
            albumCache.setObject(img, forKey: aKey)
            return img
        }
        
        return nil
    }

    public func invalidate(forFullPath fullPath: String, artist: String = "", album: String = "") {
        let pKey = fullPath as NSString
        pathCache.removeObject(forKey: pKey)
        if !artist.isEmpty && !album.isEmpty {
            let aKey = "\(artist)|\(album)" as NSString
            albumCache.removeObject(forKey: aKey)
            let key = "\(artist)|\(album)".lowercased()
            var hasher = Hasher()
            hasher.combine(key)
            let hashStr = String(format: "%016llx", UInt64(bitPattern: Int64(hasher.finalize())))
            let fileURL = diskCacheURL.appendingPathComponent("\(hashStr).jpg")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public func loadThumbnail(for track: Track, targetSize: CGFloat = 32, completion: @escaping @Sendable (NSImage?) -> Void) {
        // 1. If track has no embedded artwork according to scanner metadata, skip immediately
        guard track.hasArtwork else {
            completion(nil)
            return
        }

        let pKey = track.fullPath as NSString
        let aKey = "\(track.primaryArtist)|\(track.album)" as NSString
        let key = diskKey(for: track)

        // 2. Memory cache check
        if let img = pathCache.object(forKey: pKey) {
            completion(img)
            return
        }
        if let img = albumCache.object(forKey: aKey) {
            pathCache.setObject(img, forKey: pKey)
            completion(img)
            return
        }

        // 3. Local Mac SSD disk cache check (takes <0.1ms, zero USB load)
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                if let img = NSImage(contentsOf: fileURL) {
                    self?.pathCache.setObject(img, forKey: pKey)
                    self?.albumCache.setObject(img, forKey: aKey)
                    DispatchQueue.main.async { completion(img) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
            return
        }

        // 4. In-flight deduplication: if this album is already loading from USB, wait for it
        lock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        } else {
            inFlight[key] = [completion]
            lock.unlock()
        }

        // 5. Throttled serial read from USB drive (never chokes audio streaming bandwidth)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let url = URL(fileURLWithPath: track.fullPath)
            
            var thumb: NSImage? = nil
            if let data = AudioTagger.shared.extractCoverArt(fileURL: url),
               let fullImg = NSImage(data: data) {
                let renderSize = CGSize(width: max(128, targetSize * 2), height: max(128, targetSize * 2))
                thumb = self.renderThumbnail(from: fullImg, size: renderSize)
                
                // Save to local SSD cache for instant future loads
                if let thumbImg = thumb,
                   let tiff = thumbImg.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    try? jpegData.write(to: fileURL)
                }
            }

            if let validThumb = thumb {
                self.pathCache.setObject(validThumb, forKey: pKey)
                self.albumCache.setObject(validThumb, forKey: aKey)
            }

            // Notify all waiting completion handlers
            self.lock.lock()
            let handlers = self.inFlight.removeValue(forKey: key) ?? []
            self.lock.unlock()

            DispatchQueue.main.async {
                for handler in handlers {
                    handler(thumb)
                }
            }
        }
    }

    private func renderThumbnail(from image: NSImage, size: CGSize) -> NSImage {
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        thumb.unlockFocus()
        return thumb
    }
}

public struct TrackCoverThumbnail: View {
    let track: Track
    var size: CGFloat = 26
    var isPlaying: Bool = false
    @State private var image: NSImage?

    public init(track: Track, size: CGFloat = 26, isPlaying: Bool = false) {
        self.track = track
        self.size = size
        self.isPlaying = isPlaying
    }

    public var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isPlaying ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: isPlaying ? 1 : 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    )
            }

            if isPlaying {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: size, height: size)
                    
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(WalkmanTheme.silver)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: track.id) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        if let cached = CoverArtCache.shared.thumbnail(for: track) {
            self.image = cached
        } else {
            CoverArtCache.shared.loadThumbnail(for: track, targetSize: size) { img in
                Task { @MainActor in
                    self.image = img
                }
            }
        }
    }
}
