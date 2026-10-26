import Foundation
import AVFoundation
import AppKit

public enum AudioTrimMode: String, CaseIterable, Identifiable, Sendable {
    case trim = "trim" // Keep selection [start, end]
    case cut = "cut"   // Remove selection [start, end], splice [0, start] + [end, total]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trim: return "Trim (Keep Selection)"
        case .cut: return "Cut (Remove Selection)"
        }
    }

    public var icon: String {
        switch self {
        case .trim: return "scissors"
        case .cut: return "scissors.badge.ellipsis"
        }
    }

    public var description: String {
        switch self {
        case .trim:
            return "Retains only the highlighted audio between Start and End. The beginning and ending outside the markers are removed."
        case .cut:
            return "Removes the highlighted audio between Start and End. The audio before Start and after End are seamlessly spliced together."
        }
    }
}

public enum AudioChannelMode: String, CaseIterable, Identifiable, Sendable {
    case original = "original"         // Preserve source channels
    case swapLR = "swap_lr"           // Invert L & R (Swap stereo channels)
    case mono = "mono"                 // Downmix to Mono (1 channel)
    case stereo = "stereo"             // Force Stereo (2 channels)
    case leftOnly = "left_only"       // Left Channel Only (Duplicate L to L+R)
    case rightOnly = "right_only"     // Right Channel Only (Duplicate R to L+R)
    case muteLeft = "mute_left"       // Mute Left Channel (Right Only Output)
    case muteRight = "mute_right"     // Mute Right Channel (Left Only Output)
    case invertPhase = "invert_phase" // 180° Phase Polarity Flip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: return "Original (Keep Source)"
        case .swapLR: return "Invert L & R (Swap Stereo)"
        case .mono: return "Downmix to Mono (1 Ch)"
        case .stereo: return "Stereo (2 Channels)"
        case .leftOnly: return "Left Only (L → Both)"
        case .rightOnly: return "Right Only (R → Both)"
        case .muteLeft: return "Mute Left Channel"
        case .muteRight: return "Mute Right Channel"
        case .invertPhase: return "Invert Phase (-180°)"
        }
    }

    public var shortName: String {
        switch self {
        case .original: return "Original"
        case .swapLR: return "Invert L/R"
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .leftOnly: return "Left Only"
        case .rightOnly: return "Right Only"
        case .muteLeft: return "Mute Left"
        case .muteRight: return "Mute Right"
        case .invertPhase: return "Invert Phase"
        }
    }

    public var icon: String {
        switch self {
        case .original: return "speaker.wave.2"
        case .swapLR: return "arrow.left.arrow.right"
        case .mono: return "speaker.wave.1"
        case .stereo: return "speaker.wave.3"
        case .leftOnly: return "arrow.left.to.line"
        case .rightOnly: return "arrow.right.to.line"
        case .muteLeft: return "speaker.slash"
        case .muteRight: return "speaker.slash.fill"
        case .invertPhase: return "waveform.path"
        }
    }
}

public enum AudioSaveDestination: String, CaseIterable, Identifiable, Sendable {
    case overwrite = "overwrite"     // Overwrite Original File
    case newFile = "new_file"       // Save as New File alongside
    case exportMac = "export_mac"   // Choose destination via Save Panel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overwrite: return "Overwrite Original Track"
        case .newFile: return "Save as New File"
        case .exportMac: return "Export to Mac..."
        }
    }

    public var icon: String {
        switch self {
        case .overwrite: return "arrow.triangle.2.circlepath"
        case .newFile: return "doc.badge.plus"
        case .exportMac: return "square.and.arrow.down"
        }
    }
}

public struct TrimCutOptions: Sendable {
    public var mode: AudioTrimMode
    public var startTime: Double
    public var endTime: Double
    public var totalDuration: Double
    public var channelMode: AudioChannelMode
    public var fadeInDuration: Double
    public var fadeOutDuration: Double
    public var gainDb: Double
    public var destination: AudioSaveDestination
    public var customOutputURL: URL?
    public var preserveTags: Bool

    public init(
        mode: AudioTrimMode = .trim,
        startTime: Double = 0.0,
        endTime: Double = 0.0,
        totalDuration: Double = 0.0,
        channelMode: AudioChannelMode = .original,
        fadeInDuration: Double = 0.0,
        fadeOutDuration: Double = 0.0,
        gainDb: Double = 0.0,
        destination: AudioSaveDestination = .overwrite,
        customOutputURL: URL? = nil,
        preserveTags: Bool = true
    ) {
        self.mode = mode
        self.startTime = startTime
        self.endTime = endTime
        self.totalDuration = totalDuration
        self.channelMode = channelMode
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.gainDb = gainDb
        self.destination = destination
        self.customOutputURL = customOutputURL
        self.preserveTags = preserveTags
    }

    public var outputDuration: Double {
        if mode == .trim {
            return max(0.01, endTime - startTime)
        } else {
            return max(0.01, totalDuration - (endTime - startTime))
        }
    }
}

public final class TrimCutService: @unchecked Sendable {
    public static let shared = TrimCutService()

    private let ffmpegPath: String = {
        let homebrew = "/opt/homebrew/bin/ffmpeg"
        if FileManager.default.fileExists(atPath: homebrew) {
            return homebrew
        }
        return "/usr/local/bin/ffmpeg"
    }()

    private init() {}

    // -----------------------------------------------------------------------
    // Inspect Audio Hardware Properties (Channels, Sample Rate, Duration)
    // -----------------------------------------------------------------------
    public func inspectAudio(fileURL: URL) -> (channelCount: Int, sampleRate: Double, duration: Double)? {
        if let audioFile = try? AVAudioFile(forReading: fileURL) {
            let format = audioFile.processingFormat
            let channels = Int(format.channelCount)
            let sampleRate = format.sampleRate
            let duration = Double(audioFile.length) / (sampleRate > 0 ? sampleRate : 44100.0)
            return (channelCount: channels, sampleRate: sampleRate, duration: duration)
        }
        return nil
    }

    // -----------------------------------------------------------------------
    // Fast High-Fidelity Waveform Peaks Generator (AVAudioFile + FFmpeg Fallback)
    // -----------------------------------------------------------------------
    public func generateWaveform(fileURL: URL, barCount: Int = 600) async -> [Float] {
        return await Task.detached(priority: .userInitiated) { [self] in
            // 1. Try native AVAudioFile strided reading
            if let peaks = self.readWaveformNative(fileURL: fileURL, barCount: barCount), !peaks.isEmpty {
                return peaks
            }

            // 2. Fallback to FFmpeg raw PCM downsampling
            return self.readWaveformFFmpeg(fileURL: fileURL, barCount: barCount)
        }.value
    }

    private func readWaveformNative(fileURL: URL, barCount: Int) -> [Float]? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }
        let totalFrames = audioFile.length
        guard totalFrames > 0 else { return nil }

        let framesPerBar = totalFrames / Int64(barCount)
        guard framesPerBar > 0 else { return nil }

        let sampleChunkCapacity: AVAudioFrameCount = 512
        guard let sampleBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: sampleChunkCapacity) else {
            return nil
        }

        var rawPeaks: [Float] = []
        rawPeaks.reserveCapacity(barCount)

        for i in 0..<barCount {
            audioFile.framePosition = min(totalFrames - 1, Int64(i) * framesPerBar)
            let framesToRead = min(sampleChunkCapacity, AVAudioFrameCount(max(1, totalFrames - audioFile.framePosition)))
            do {
                try audioFile.read(into: sampleBuffer, frameCount: framesToRead)
                if let floatData = sampleBuffer.floatChannelData {
                    var maxAmplitude: Float = 0.0
                    let channelCount = Int(sampleBuffer.format.channelCount)
                    let readCount = Int(sampleBuffer.frameLength)

                    for ch in 0..<min(2, channelCount) {
                        let chData = floatData[ch]
                        for f in 0..<readCount {
                            let amp = abs(chData[f])
                            if amp > maxAmplitude {
                                maxAmplitude = amp
                            }
                        }
                    }
                    rawPeaks.append(maxAmplitude)
                } else {
                    rawPeaks.append(0.05)
                }
            } catch {
                rawPeaks.append(0.05)
            }
        }

        return normalizePeaks(rawPeaks)
    }

    private func readWaveformFFmpeg(fileURL: URL, barCount: Int) -> [Float] {
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            return Array(repeating: 0.25, count: barCount)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-v", "error",
            "-i", fileURL.path,
            "-ac", "1",
            "-filter:a", "aresample=1000",
            "-f", "f32le",
            "-"
        ]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let sampleCount = data.count / MemoryLayout<Float>.size
            guard sampleCount > 0 else {
                return Array(repeating: 0.25, count: barCount)
            }

            let samples = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }

            let stride = max(1, samples.count / barCount)
            var rawPeaks: [Float] = []
            rawPeaks.reserveCapacity(barCount)

            for i in 0..<barCount {
                let startIdx = i * stride
                let endIdx = min(samples.count, startIdx + stride)
                if startIdx < samples.count {
                    var maxAmp: Float = 0.0
                    for s in startIdx..<endIdx {
                        let val = abs(samples[s])
                        if val > maxAmp { maxAmp = val }
                    }
                    rawPeaks.append(maxAmp)
                } else {
                    rawPeaks.append(0.05)
                }
            }
            return normalizePeaks(rawPeaks)
        } catch {
            return Array(repeating: 0.25, count: barCount)
        }
    }

    private func normalizePeaks(_ peaks: [Float]) -> [Float] {
        guard !peaks.isEmpty else { return [] }
        let maxPeak = peaks.max() ?? 1.0
        let divisor = maxPeak > 0.001 ? maxPeak : 1.0

        return peaks.map { val in
            let normalized = val / divisor
            // Ensure minimum visual bar height of 0.06 and maximum of 1.0
            return max(0.06, min(1.0, normalized))
        }
    }

    // -----------------------------------------------------------------------
    // Execute Trim / Cut & Channel Operations via FFmpeg
    // -----------------------------------------------------------------------
    public func processAudio(
        track: Track,
        options: TrimCutOptions,
        progressHandler: @escaping (String) -> Void
    ) async throws -> URL {
        let sourceURL = URL(fileURLWithPath: track.fullPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "TrimCutService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Source audio file not found: \(track.fullPath)"])
        }

        // Determine destination file URL
        let finalDestinationURL: URL
        switch options.destination {
        case .overwrite:
            finalDestinationURL = sourceURL
        case .newFile:
            let dir = sourceURL.deletingLastPathComponent()
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            let newFilename = "\(baseName) [Trimmed].\(ext)"
            finalDestinationURL = dir.appendingPathComponent(newFilename)
        case .exportMac:
            if let custom = options.customOutputURL {
                finalDestinationURL = custom
            } else {
                throw NSError(domain: "TrimCutService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No export destination provided"])
            }
        }

        // Temporary file on fast local SSD for optimal encoding and atomic write
        let ext = finalDestinationURL.pathExtension.lowercased()
        let tempDir = FileManager.default.temporaryDirectory
        let tempFilename = "walkman_trim_\(UUID().uuidString).\(ext)"
        let tempURL = tempDir.appendingPathComponent(tempFilename)
        try? FileManager.default.removeItem(at: tempURL)

        progressHandler("Building audio filter graph...")

        // Construct filterchain
        var filters: [String] = []

        let startFormatted = String(format: "%.3f", max(0.0, options.startTime))
        let endFormatted = String(format: "%.3f", max(options.startTime + 0.01, options.endTime))

        // 1. Trim vs Cut filter
        if options.mode == .trim {
            filters.append("atrim=start=\(startFormatted):end=\(endFormatted),asetpts=PTS-STARTPTS")
        } else {
            // Cut mode: remove range [startTime, endTime]
            filters.append(#"aselect='not(between(t\,\#(startFormatted)\,\#(endFormatted)))',asetpts=N/SR/TB"#)
        }

        // 2. Channel Mode (Standardized for any input channel layout)
        switch options.channelMode {
        case .original:
            break
        case .swapLR:
            filters.append("aformat=channel_layouts=stereo,pan=stereo|c0=c1|c1=c0")
        case .mono:
            filters.append("aformat=channel_layouts=mono")
        case .stereo:
            filters.append("aformat=channel_layouts=stereo")
        case .leftOnly:
            filters.append("aformat=channel_layouts=stereo,pan=stereo|c0=c0|c1=c0")
        case .rightOnly:
            filters.append("aformat=channel_layouts=stereo,pan=stereo|c0=c1|c1=c1")
        case .muteLeft:
            filters.append("aformat=channel_layouts=stereo,pan=stereo|c0=0*c0|c1=c1")
        case .muteRight:
            filters.append("aformat=channel_layouts=stereo,pan=stereo|c0=c0|c1=0*c1")
        case .invertPhase:
            filters.append("volume=-1")
        }

        // 3. Audio Gain
        if abs(options.gainDb) > 0.05 {
            filters.append(String(format: "volume=%.1fdB", options.gainDb))
        }

        // 4. Fade In
        let outDur = options.outputDuration
        if options.fadeInDuration > 0.05 {
            let actualFadeIn = min(options.fadeInDuration, outDur / 2.0)
            filters.append(String(format: "afade=t=in:ss=0:d=%.2f", actualFadeIn))
        }

        // 5. Fade Out
        if options.fadeOutDuration > 0.05 {
            let actualFadeOut = min(options.fadeOutDuration, outDur / 2.0)
            let fadeStart = max(0.0, outDur - actualFadeOut)
            filters.append(String(format: "afade=t=out:st=%.2f:d=%.2f", fadeStart, actualFadeOut))
        }

        let combinedFilter = filters.joined(separator: ",")

        progressHandler("Encoding audio stream with FFmpeg...")

        var args = [
            "-v", "error",
            "-y",
            "-i", sourceURL.path,
            "-af", combinedFilter
        ]

        // Format-specific encoding
        if ext == "flac" {
            if track.bitsPerSample > 16 || track.sampleRate > 48000 {
                // Hi-Res FLAC preservation
                let sampleFmt = track.bitsPerSample > 16 ? "s32" : "s16"
                let sr = track.sampleRate > 0 ? track.sampleRate : 96000
                args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", sampleFmt, "-ar", "\(sr)"])
            } else {
                args.append(contentsOf: ["-c:a", "flac", "-sample_fmt", "s16", "-ar", "44100"])
            }
        } else if ext == "mp3" {
            let bitrate = track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "320k"
            args.append(contentsOf: ["-c:a", "libmp3lame", "-b:a", bitrate, "-id3v2_version", "3"])
        } else if ext == "m4a" || ext == "aac" || ext == "mp4" {
            let bitrate = track.bitrateKbps > 0 ? "\(track.bitrateKbps)k" : "256k"
            args.append(contentsOf: ["-c:a", "aac", "-b:a", bitrate])
        } else if ext == "wav" {
            args.append(contentsOf: ["-c:a", "pcm_s16le"])
        } else {
            args.append(contentsOf: ["-c:a", "flac"])
        }

        args.append(contentsOf: ["-vn", tempURL.path])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: tempURL)
            let errString = String(data: errData, encoding: .utf8) ?? "FFmpeg processing failed"
            throw NSError(domain: "TrimCutService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errString])
        }

        // Tag and artwork preservation
        if options.preserveTags {
            progressHandler("Writing Walkman-compliant metadata & cover art...")
            let coverArt = AudioTagger.shared.extractCoverArt(fileURL: sourceURL)
            let existingMeta = AudioTagger.shared.readMetadata(fileURL: sourceURL)

            let titleToWrite = existingMeta?.title ?? (track.title.isEmpty ? nil : track.title)
            let artistToWrite = existingMeta?.artist ?? (track.artist.isEmpty ? nil : track.artist)
            let albumToWrite = existingMeta?.album ?? (track.album.isEmpty ? nil : track.album)
            let trackNumToWrite = existingMeta?.trackNumber ?? (track.trackNum.isEmpty ? nil : track.trackNum)
            let yearToWrite = existingMeta?.year ?? (track.year.isEmpty ? nil : track.year)
            let genreToWrite = existingMeta?.genre ?? (track.genre.isEmpty ? nil : track.genre)

            try? AudioTagger.shared.writeMetadata(
                fileURL: tempURL,
                title: titleToWrite,
                artist: artistToWrite,
                album: albumToWrite,
                trackNumber: trackNumToWrite,
                year: yearToWrite,
                genre: genreToWrite,
                coverArtData: coverArt
            )
        }

        progressHandler("Finalizing file...")

        progressHandler("Saving to Walkman storage...")

        // Safely transfer to final location across volumes (FAT32/exFAT compatible)
        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            try FileManager.default.removeItem(at: finalDestinationURL)
        }
        try FileManager.default.copyItem(at: tempURL, to: finalDestinationURL)
        try? FileManager.default.removeItem(at: tempURL)

        // Clear cache and flush to disk
        LibraryScanner.shared.removeFromCache(fullPath: finalDestinationURL.path)

        // Clean any ghost macOS dotfiles
        let dotfile = finalDestinationURL.deletingLastPathComponent().appendingPathComponent("._" + finalDestinationURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfile)
        sync()

        return finalDestinationURL
    }
}
