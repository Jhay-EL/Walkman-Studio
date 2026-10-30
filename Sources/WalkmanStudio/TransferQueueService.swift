import Foundation
import AppKit
import SwiftUI

// =============================================================================
// TRANSFER QUEUE SERVICE
// Manages Transfer & Convert queue, format verification, and direct Walkman transfers
// =============================================================================

@MainActor
public final class TransferQueueService: ObservableObject {
    public static let shared = TransferQueueService()

    @Published public var queue: [TransferItem] = []

    // Sony Walkman DAP Supported Audio Formats (Non-Android Firmware: NW-A30/A40/A50, NW-ZX300, NW-WM1A/WM1Z, etc.)
    public static let supportedWalkmanExtensions: Set<String> = [
        "flac", "mp3", "m4a", "aac", "alac", "wav", "aiff", "aif", "dsf", "dff", "ape", "wma"
    ]

    private init() {}

    // -------------------------------------------------------------------------
    // Format Validation
    // -------------------------------------------------------------------------
    public static func isFormatSupported(ext: String) -> Bool {
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return supportedWalkmanExtensions.contains(clean)
    }

    public static func isTrackSupported(_ track: Track) -> Bool {
        let ext = URL(fileURLWithPath: track.fullPath).pathExtension
        return isFormatSupported(ext: ext)
    }

    // -------------------------------------------------------------------------
    // Queue Ingestion
    // -------------------------------------------------------------------------
    public func enqueue(tracks: [Track]) {
        for track in tracks {
            let url = URL(fileURLWithPath: track.fullPath)
            if queue.contains(where: { $0.sourceURL == url }) {
                continue
            }

            let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationSeconds: track.durationSeconds,
                sourceURL: url,
                targetDrive: nil,
                targetMode: .music
            )

            let item = TransferItem(
                sourceURL: url,
                status: .pending,
                title: track.title.isEmpty ? url.deletingPathExtension().lastPathComponent : track.title,
                artist: track.artist.isEmpty ? "Unknown Artist" : track.artist,
                album: track.album.isEmpty ? "Unknown Album" : track.album,
                trackNumber: track.trackNum.isEmpty ? "1" : track.trackNum,
                year: track.year,
                genre: track.genre,
                durationSeconds: track.durationSeconds,
                bitrateKbps: track.bitrateKbps,
                sampleRate: track.sampleRate,
                bitsPerSample: track.bitsPerSample,
                format: url.pathExtension.uppercased(),
                sizeBytes: track.sizeBytes,
                isDuplicateOnWalkman: dupCheck.isDuplicate,
                duplicateMatchInfo: dupCheck.reason
            )

            let targetUrl = url
            Task.detached(priority: .userInitiated) {
                let artData = AudioTagger.shared.extractCoverArt(fileURL: targetUrl)
                let lyrics = AudioTagger.shared.extractLyrics(fileURL: targetUrl)
                var resolvedArt = artData
                var resolvedOpt = false
                if let d = artData {
                    let check = WalkmanEngine.shared.isBaselineRGBJPEG(data: d)
                    resolvedOpt = check.valid
                    if !resolvedOpt, let encoded = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: d, maxDimension: 800) {
                        resolvedArt = encoded
                        resolvedOpt = true
                    }
                }

                let finalArtwork = resolvedArt
                let finalIsOpt = resolvedOpt

                await MainActor.run {
                    if let idx = self.queue.firstIndex(where: { $0.sourceURL == targetUrl }) {
                        self.queue[idx].artworkData = finalArtwork
                        self.queue[idx].isArtworkOptimized = finalIsOpt
                        self.queue[idx].lyrics = lyrics
                        self.queue[idx].isLyricsSynced = lyrics?.contains("[0") == true
                    }
                }
            }

            queue.append(item)
        }
    }

    public func enqueue(urls: [URL]) {
        for url in urls {
            if queue.contains(where: { $0.sourceURL == url }) { continue }

            var item = TransferItem(sourceURL: url)
            item.title = WalkmanEngine.sanitizeWalkmanText(url.deletingPathExtension().lastPathComponent)
            item.format = url.pathExtension.uppercased()

            if let attr = try? FileManager.default.attributesOfItem(atPath: url.path) {
                item.sizeBytes = attr[.size] as? Int64 ?? 0
            }

            let pathFallback = AudioTagger.extractFromPath(url: url)
            if !pathFallback.artist.isEmpty { item.artist = WalkmanEngine.sanitizeWalkmanText(pathFallback.artist, stripExplicitMarkers: false) }
            if !pathFallback.album.isEmpty { item.album = WalkmanEngine.sanitizeWalkmanText(pathFallback.album) }
            if !pathFallback.title.isEmpty { item.title = WalkmanEngine.sanitizeWalkmanText(pathFallback.title) }
            if !pathFallback.trackNumber.isEmpty { item.trackNumber = pathFallback.trackNumber }

            let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                title: item.title,
                artist: item.artist,
                album: item.album,
                sourceURL: url,
                targetDrive: nil,
                targetMode: .music
            )
            item.isDuplicateOnWalkman = dupCheck.isDuplicate
            item.duplicateMatchInfo = dupCheck.reason

            let targetUrl = url
            Task.detached(priority: .userInitiated) {
                let meta = AudioTagger.shared.readMetadata(fileURL: targetUrl)
                let artData = AudioTagger.shared.extractCoverArt(fileURL: targetUrl)
                let existingLyrics = AudioTagger.shared.extractLyrics(fileURL: targetUrl)

                var resolvedArt = artData
                var resolvedOpt = false
                if let d = artData {
                    let check = WalkmanEngine.shared.isBaselineRGBJPEG(data: d)
                    resolvedOpt = check.valid
                    if !resolvedOpt, let encoded = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: d, maxDimension: 800) {
                        resolvedArt = encoded
                        resolvedOpt = true
                    }
                }

                let finalArtwork = resolvedArt
                let finalIsOpt = resolvedOpt

                await MainActor.run {
                    if let idx = self.queue.firstIndex(where: { $0.sourceURL == targetUrl }) {
                        if let m = meta {
                            if !m.title.isEmpty && m.title.lowercased() != "unknown" {
                                self.queue[idx].title = WalkmanEngine.sanitizeWalkmanText(m.title)
                            }
                            if !m.artist.isEmpty && m.artist.lowercased() != "unknown artist" {
                                self.queue[idx].artist = WalkmanEngine.sanitizeWalkmanText(m.artist, stripExplicitMarkers: false)
                            }
                            if !m.album.isEmpty && m.album.lowercased() != "unknown album" {
                                self.queue[idx].album = WalkmanEngine.sanitizeWalkmanText(m.album)
                            }
                            if !m.trackNumber.isEmpty { self.queue[idx].trackNumber = m.trackNumber }
                            if !m.year.isEmpty { self.queue[idx].year = m.year }
                            if !m.genre.isEmpty { self.queue[idx].genre = m.genre }
                            self.queue[idx].durationSeconds = m.durationSeconds
                            self.queue[idx].bitrateKbps = m.bitrateKbps
                            self.queue[idx].sampleRate = m.sampleRate
                            self.queue[idx].bitsPerSample = m.bitsPerSample
                        }
                        self.queue[idx].artworkData = finalArtwork
                        self.queue[idx].isArtworkOptimized = finalIsOpt
                        self.queue[idx].lyrics = existingLyrics
                        self.queue[idx].isLyricsSynced = existingLyrics?.contains("[0") == true
                    }
                }
            }

            queue.append(item)
        }
    }

    // -------------------------------------------------------------------------
    // Direct Transfer to Sony Walkman (Hardware Compliant)
    // -------------------------------------------------------------------------
    public func transferDirectly(
        tracks: [Track],
        to targetDrive: WalkmanDrive,
        skipDuplicates: Bool = true,
        progress: @escaping (_ current: Int, _ total: Int, _ trackTitle: String) -> Void
    ) async throws -> Int {
        let targetRootDir = URL(fileURLWithPath: targetDrive.musicDir)
        var transferredCount = 0

        for (index, track) in tracks.enumerated() {
            let src = URL(fileURLWithPath: track.fullPath)
            guard FileManager.default.fileExists(atPath: src.path) else {
                continue
            }

            progress(index + 1, tracks.count, track.title.isEmpty ? src.lastPathComponent : track.title)

            // Sanitize names for Sony Walkman filesystem
            let rawArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let curArtist = rawArtist.isEmpty ? "Unknown Artist" : rawArtist
            let rawAlbum = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let curAlbum = rawAlbum.isEmpty ? "Unknown Album" : rawAlbum
            let rawTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let curTitle = rawTitle.isEmpty ? src.deletingPathExtension().lastPathComponent : rawTitle
            let curTrackNum = track.trackNum.trimmingCharacters(in: .whitespacesAndNewlines)

            let cleanArtist = WalkmanEngine.shared.sanitizeFilename(curArtist)
            let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(curAlbum)
            let cleanTitle = WalkmanEngine.shared.sanitizeFilename(curTitle)
            let trackNum = curTrackNum.isEmpty ? "01" : curTrackNum
            let ext = src.pathExtension.lowercased()

            let dest = WalkmanEngine.shared.targetTrackURL(
                musicRoot: targetRootDir,
                artist: cleanArtist,
                album: cleanAlbum,
                trackNum: trackNum,
                title: cleanTitle,
                ext: ext
            )

            // Duplicate Guardrail Check
            if skipDuplicates {
                let dupCheck = WalkmanDuplicateGuard.shared.checkTrack(
                    title: curTitle,
                    artist: curArtist,
                    album: curAlbum,
                    durationSeconds: track.durationSeconds,
                    sourceURL: src,
                    targetDrive: targetDrive,
                    targetMode: .music
                )
                if dupCheck.isDuplicate || FileManager.default.fileExists(atPath: dest.path) {
                    continue
                }
            }

            let albumDir = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)

            // Copy file directly
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)

            // Hardware Compliance 1: Strict Baseline RGB JPEG Cover Art (max 800x800)
            var finalArtData: Data? = nil
            if let extractedArt = AudioTagger.shared.extractCoverArt(fileURL: src) {
                finalArtData = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: extractedArt, maxDimension: 800) ?? extractedArt
            }

            // Save folder.jpg inside album directory for Sony Walkman grid rendering
            if let art = finalArtData {
                try? WalkmanEngine.shared.writeAlbumFolderArtwork(albumDirectoryURL: albumDir, artworkData: art)
            }

            // Hardware Compliance 2: Strict ID3v2.3 UTF-16 on MP3 / Vorbis Comments on FLAC
            let lyrics = AudioTagger.shared.extractLyrics(fileURL: src)
            if ext == "mp3" || ext == "flac" || ext == "m4a" {
                try? AudioTagger.shared.writeMetadata(
                    fileURL: dest,
                    title: curTitle,
                    artist: curArtist,
                    album: curAlbum,
                    trackNumber: trackNum,
                    year: track.year.isEmpty ? nil : track.year,
                    genre: track.genre.isEmpty ? nil : track.genre,
                    coverArtData: finalArtData,
                    lyrics: lyrics
                )
            }

            // Hardware Compliance 3: Sony Walkman Synchronized Companion .LRC Lyrics
            if let lyrics = lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? WalkmanEngine.shared.writeCompanionLyrics(
                    destinationAudioURL: dest,
                    lyrics: lyrics,
                    durationSeconds: track.durationSeconds
                )
            }

            // Hardware Compliance 3: Clean Extended Attributes & AppleDouble Shadows
            let cPath = (dest.path as NSString).fileSystemRepresentation
            removexattr(cPath, "com.apple.TextEncoding", 0)
            let shadowFile = dest.deletingLastPathComponent().appendingPathComponent("._" + dest.lastPathComponent)
            try? FileManager.default.removeItem(at: shadowFile)
            let dsStore = dest.deletingLastPathComponent().appendingPathComponent(".DS_Store")
            try? FileManager.default.removeItem(at: dsStore)

            transferredCount += 1
        }

        return transferredCount
    }
}
