import Foundation
import AVFoundation
import Accelerate

/// Acoustic analysis service to detect audio lead-in silence (mastering pregap)
/// and calibrate LRC timestamps to match actual physical audio playback.
public final class AudioAcousticAligner: Sendable {
    public static let shared = AudioAcousticAligner()

    private init() {}

    /// Typical lead-in silence of modern streaming releases (Spotify, Apple Music)
    /// against which crowdsourced LRCLIB timestamps are originally timed (~150ms).
    public static let standardStreamingLeadInBaseline: Double = 0.15

    /// Detects the exact duration of lead-in silence (in seconds) before audible music begins in the track.
    /// Inspects the first 12 seconds of the audio file via AVAssetReader.
    public func detectLeadInSilence(fileURL: URL) async -> Double {
        let asset = AVURLAsset(url: fileURL)
        let tracks: [AVAssetTrack]
        if #available(macOS 13.0, *) {
            tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        } else {
            tracks = asset.tracks(withMediaType: .audio)
        }
        guard let track = tracks.first else {
            return 0.0
        }

        return await Task.detached(priority: .userInitiated) { () -> Double in
            guard let reader = try? AVAssetReader(asset: asset) else {
                return 0.0
            }

            // Inspect up to the first 12 seconds
            reader.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: 12.0, preferredTimescale: 44100)
            )

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMIsNonInterleaved: false
            ]

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return 0.0 }
            reader.add(output)

            guard reader.startReading() else { return 0.0 }

            let sampleRate: Double = 44100.0
            let windowSize = 1024 // ~23.2ms per window
            // -48 dBFS threshold on 16-bit PCM (32767 * 10^(-48/20) ≈ 130)
            let thresholdRMS: Float = 130.0

            var totalSamplesRead: Int64 = 0
            var detectedLeadInSeconds: Double? = nil

            while reader.status == .reading {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

                var lengthAtOffset = 0
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>? = nil

                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: &totalLength,
                    dataPointerOut: &dataPointer
                )

                guard status == kCMBlockBufferNoErr, let rawBytes = dataPointer, totalLength > 0 else {
                    continue
                }

                let numSamples = totalLength / MemoryLayout<Int16>.size
                rawBytes.withMemoryRebound(to: Int16.self, capacity: numSamples) { int16Pointer in
                    var offset = 0
                    while offset + windowSize <= numSamples {
                        var floatBuffer = [Float](repeating: 0, count: windowSize)
                        for j in 0..<windowSize {
                            floatBuffer[j] = Float(int16Pointer[offset + j])
                        }

                        var rms: Float = 0
                        vDSP_rmsqv(floatBuffer, 1, &rms, vDSP_Length(windowSize))

                        if rms >= thresholdRMS {
                            let sampleIndex = totalSamplesRead + Int64(offset)
                            detectedLeadInSeconds = Double(sampleIndex) / sampleRate
                            break
                        }

                        offset += windowSize
                    }
                }

                totalSamplesRead += Int64(numSamples)
                if detectedLeadInSeconds != nil { break }
            }

            reader.cancelReading()
            return detectedLeadInSeconds ?? 0.0
        }.value
    }

    /// Calculates the recommended timestamp offset (in seconds) by comparing the track's
    /// measured lead-in silence against standard streaming mastering baselines.
    /// Positive offset means lyrics should appear later (to match a longer pregap).
    public func calculateRecommendedPregapOffset(audioLeadIn: Double) -> Double {
        // Only apply if silence exceeds typical streaming padding by at least 150ms
        let delta = audioLeadIn - Self.standardStreamingLeadInBaseline
        if abs(delta) < 0.15 {
            return 0.0
        }
        // Bound offset to sane mastering pregap adjustments (-1.0s to +3.5s)
        return min(3.5, max(-1.0, (delta * 10.0).rounded() / 10.0))
    }

    /// Auto-calibrates an existing LRC string against the audio file's lead-in silence.
    public func calibrateLRC(
        audioURL: URL,
        lyrics: String,
        durationSeconds: Double = 0
    ) async -> (calibratedLyrics: String, offsetApplied: Double) {
        let leadIn = await detectLeadInSilence(fileURL: audioURL)
        let offset = calculateRecommendedPregapOffset(audioLeadIn: leadIn)
        guard abs(offset) >= 0.10 else {
            return (lyrics, 0.0)
        }

        let calibrated = WalkmanEngine.shared.prepareWalkmanLRC(
            lyrics: lyrics,
            durationSeconds: durationSeconds,
            offsetSeconds: offset
        )
        return (calibrated, offset)
    }
}
