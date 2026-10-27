import Foundation
import AppKit

public extension Notification.Name {
    static let artistArtworkDidChange = Notification.Name("WalkmanStudio.artistArtworkDidChange")
}

/// High-performance artist photo artwork cache.
/// Fetches official artist portrait photos from Deezer's public music API,
/// checks local Walkman artist directories, falls back to embedded album artwork,
/// and caches everything to local Mac SSD and memory with zero UI stutter.
public final class ArtistArtCache: @unchecked Sendable {
    public static let shared = ArtistArtCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".walkman_artist_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private let networkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.sony.walkmanstudio.artist_art_queue"
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private var negativeCache: Set<String> = []
    private let lock = NSLock()

    private init() {
        memoryCache.countLimit = 600
        memoryCache.totalCostLimit = 80 * 1024 * 1024 // ~80 MB
    }

    private func diskKey(for artistName: String) -> String {
        let clean = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14695981039346656037
        for byte in clean.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    /// Synchronous memory/SSD check. Returns image if cached, nil otherwise without blocking.
    public func cachedImage(for artistName: String) -> NSImage? {
        let clean = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.lowercased() == "unknown artist" { return nil }

        let mKey = clean as NSString
        if let img = memoryCache.object(forKey: mKey) {
            return img
        }

        let key = diskKey(for: clean)
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        if FileManager.default.fileExists(atPath: fileURL.path),
           let img = NSImage(contentsOf: fileURL) {
            memoryCache.setObject(img, forKey: mKey)
            return img
        }

        return nil
    }

    /// Asynchronous loader that never blocks the main UI thread.
    public func loadArtistImage(
        for artistName: String,
        representativeTrack: Track? = nil,
        forceRefresh: Bool = false,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) {
        let clean = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean.lowercased() == "unknown artist" {
            completion(nil)
            return
        }

        let mKey = clean as NSString
        let key = diskKey(for: clean)

        if !forceRefresh {
            // 1. In-memory cache hit (0 ms)
            if let img = memoryCache.object(forKey: mKey) {
                completion(img)
                return
            }

            // 2. Negative cache check
            lock.lock()
            if negativeCache.contains(key) {
                lock.unlock()
                completion(nil)
                return
            }
            lock.unlock()

            // 3. Fast local SSD disk cache hit (<0.2 ms)
            let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                    if let img = NSImage(contentsOf: fileURL) {
                        self?.memoryCache.setObject(img, forKey: mKey)
                        DispatchQueue.main.async { completion(img) }
                    } else {
                        DispatchQueue.main.async { completion(nil) }
                    }
                }
                return
            }

            // 4. Persistent negative cache check
            let noneURL = diskCacheURL.appendingPathComponent("\(key).none")
            if FileManager.default.fileExists(atPath: noneURL.path) {
                lock.lock()
                negativeCache.insert(key)
                lock.unlock()
                completion(nil)
                return
            }
        }

        // 5. In-flight request deduplication
        lock.lock()
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            lock.unlock()
            return
        } else {
            inFlight[key] = [completion]
            lock.unlock()
        }

        // 6. Asynchronous fetch on background utility queue
        queue.addOperation { [weak self] in
            guard let self = self else { return }

            var fetchedImage: NSImage? = nil

            // Priority A: Local artist folder picture if present
            if let track = representativeTrack {
                fetchedImage = self.checkLocalArtistFolder(for: track)
            }

            // Priority B: Official online artist portrait via Deezer public API
            if fetchedImage == nil {
                fetchedImage = self.fetchFromDeezer(artistName: clean)
            }

            // Priority C: Fallback to representative track embedded artwork
            if fetchedImage == nil, let track = representativeTrack, track.hasArtwork {
                fetchedImage = self.extractTrackArtwork(for: track)
            }

            let fileURL = self.diskCacheURL.appendingPathComponent("\(key).jpg")
            let noneURL = self.diskCacheURL.appendingPathComponent("\(key).none")

            if let img = fetchedImage {
                let square = self.renderSquareThumbnail(from: img, targetDimension: 256)
                self.memoryCache.setObject(square, forKey: mKey)

                // Save compressed JPEG to local SSD disk cache
                if let tiff = square.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    try? jpeg.write(to: fileURL)
                }
                try? FileManager.default.removeItem(at: noneURL)

                self.lock.lock()
                self.negativeCache.remove(key)
                self.lock.unlock()

                fetchedImage = square
            } else {
                try? "".write(to: noneURL, atomically: true, encoding: .utf8)
                self.lock.lock()
                self.negativeCache.insert(key)
                self.lock.unlock()
            }

            // Notify in-flight completions
            self.lock.lock()
            let handlers = self.inFlight.removeValue(forKey: key) ?? []
            self.lock.unlock()

            DispatchQueue.main.async {
                for h in handlers {
                    h(fetchedImage)
                }
            }
        }
    }

    /// Checks the physical artist folder on the Walkman for artist.jpg, folder.jpg, etc.
    private func checkLocalArtistFolder(for track: Track) -> NSImage? {
        let trackURL = URL(fileURLWithPath: track.fullPath)
        let albumDir = trackURL.deletingLastPathComponent()
        let artistDir = albumDir.deletingLastPathComponent()

        let candidateNames = ["artist.jpg", "artist.jpeg", "artist.png", "folder.jpg", "cover.jpg"]
        for name in candidateNames {
            let candidate = artistDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path),
               let img = NSImage(contentsOf: candidate) {
                return img
            }
        }
        return nil
    }

    /// Queries the Deezer API for the artist portrait
    private func fetchFromDeezer(artistName: String) -> NSImage? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&?/#%")
        guard let encoded = artistName.addingPercentEncoding(withAllowedCharacters: allowed),
              let searchURL = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)&limit=1") else {
            return nil
        }

        var request = URLRequest(url: searchURL)
        request.setValue("WalkmanStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4.0

        let semaphore = DispatchSemaphore(value: 0)
        var imageURLString: String? = nil

        let task = networkSession.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]],
                  let first = list.first else {
                return
            }

            let foundName = (first["name"] as? String ?? "").lowercased()
            let queryLower = artistName.lowercased()

            // Verify relevance
            let isMatch = foundName == queryLower
                || foundName.contains(queryLower)
                || queryLower.contains(foundName)
                || !Set(queryLower.split(separator: " ")).intersection(Set(foundName.split(separator: " "))).isEmpty

            if isMatch {
                imageURLString = first["picture_medium"] as? String
                    ?? first["picture_big"] as? String
                    ?? first["picture"] as? String
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 4.5)

        guard let imgURLStr = imageURLString, let imgURL = URL(string: imgURLStr) else {
            return nil
        }

        var imgData: Data? = nil
        let imgSem = DispatchSemaphore(value: 0)
        let imgTask = networkSession.dataTask(with: imgURL) { data, _, _ in
            imgData = data
            imgSem.signal()
        }
        imgTask.resume()
        _ = imgSem.wait(timeout: .now() + 5.0)

        if let data = imgData, let img = NSImage(data: data) {
            return img
        }
        return nil
    }

    /// Extracts track embedded artwork as fallback
    private func extractTrackArtwork(for track: Track) -> NSImage? {
        if let existing = CoverArtCache.shared.thumbnail(for: track) {
            return existing
        }
        let url = URL(fileURLWithPath: track.fullPath)
        if let data = AudioTagger.shared.extractCoverArt(fileURL: url),
           let img = NSImage(data: data) {
            return img
        }
        return nil
    }

    /// Sets a user-selected custom portrait image for an artist
    public func setCustomImage(_ image: NSImage, for artistName: String) {
        let clean = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let mKey = clean as NSString
        let key = diskKey(for: clean)
        let square = renderSquareThumbnail(from: image, targetDimension: 256)

        memoryCache.setObject(square, forKey: mKey)

        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        let noneURL = diskCacheURL.appendingPathComponent("\(key).none")
        try? FileManager.default.removeItem(at: noneURL)

        if let tiff = square.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) {
            try? jpeg.write(to: fileURL)
        }

        lock.lock()
        negativeCache.remove(key)
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .artistArtworkDidChange,
                object: nil,
                userInfo: ["artist": clean]
            )
        }
    }

    /// Refreshes the artist photo cache and re-fetches
    public func refresh(artistName: String, representativeTrack: Track? = nil) {
        let clean = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let mKey = clean as NSString
        let key = diskKey(for: clean)

        memoryCache.removeObject(forKey: mKey)
        let fileURL = diskCacheURL.appendingPathComponent("\(key).jpg")
        let noneURL = diskCacheURL.appendingPathComponent("\(key).none")
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: noneURL)

        lock.lock()
        negativeCache.remove(key)
        lock.unlock()

        loadArtistImage(for: clean, representativeTrack: representativeTrack, forceRefresh: true) { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .artistArtworkDidChange,
                    object: nil,
                    userInfo: ["artist": clean]
                )
            }
        }
    }

    /// Crops center square and resizes to target dimension to prevent rectangular distortion
    private func renderSquareThumbnail(from image: NSImage, targetDimension: CGFloat = 256) -> NSImage {
        let targetSize = CGSize(width: targetDimension, height: targetDimension)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let thumb = NSImage(size: targetSize)
        thumb.lockFocus()

        let aspectWidth = imageSize.width
        let aspectHeight = imageSize.height
        let minSide = min(aspectWidth, aspectHeight)
        let cropRect = NSRect(
            x: (aspectWidth - minSide) / 2.0,
            y: (aspectHeight - minSide) / 2.0,
            width: minSide,
            height: minSide
        )

        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: cropRect,
            operation: .copy,
            fraction: 1.0
        )
        thumb.unlockFocus()
        return thumb
    }
}
