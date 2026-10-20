import SwiftUI
import AppKit

public struct TrackPreviewBar: View {
    @ObservedObject var player = AudioPlayerService.shared
    let onOpenInspector: () -> Void

    @State private var dragTime: Double? = nil

    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    public var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                Divider()
                    .overlay(Color.white.opacity(0.1))

                HStack(spacing: 16) {
                    // LEFT: Track Info & Cover Art Thumbnail
                    HStack(spacing: 12) {
                        Button(action: onOpenInspector) {
                            ZStack {
                                if let img = player.currentCoverArt {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                } else {
                                    TrackCoverThumbnail(track: track, size: 44, isPlaying: player.isPlaying)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(player.isPlaying ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Click to view full metadata details & artwork")

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(track.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(player.isPlaying ? .white : Color(white: 0.9))
                                    .lineLimit(1)

                                let isHiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
                                if isHiRes {
                                    Text("Hi-Res")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.15))
                                        .foregroundStyle(WalkmanTheme.silver)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                }
                            }

                            Text("\(track.artist) • \(track.album)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(track.format)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(WalkmanTheme.silverMuted)

                                if track.sampleRate > 0 {
                                    Text("\(track.bitsPerSample)b/\(String(format: "%.1f", Double(track.sampleRate)/1000.0))k")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }

                                if track.bitrateKbps > 0 {
                                    Text("• \(track.bitrateKbps) kbps")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }

                    Spacer()

                    // CENTER: Playback Controls & Interactive Scrubber
                    VStack(spacing: 6) {
                        HStack(spacing: 16) {
                            Button(action: { player.playPrevious() }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Previous track")

                            Button(action: { player.togglePlayPause() }) {
                                ZStack {
                                    Circle()
                                        .fill(WalkmanTheme.silverGradient)
                                        .frame(width: 32, height: 32)

                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
                                        .offset(x: player.isPlaying ? 0 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.space, modifiers: [])
                            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")

                            Button(action: { player.playNext() }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Next track")
                        }

                        // Scrubber Slider Row
                        HStack(spacing: 8) {
                            let curTime = dragTime ?? player.currentTime
                            Text(formatTime(curTime))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)

                            Slider(
                                value: Binding(
                                    get: { dragTime ?? player.currentTime },
                                    set: { newTime in
                                        dragTime = newTime
                                    }
                                ),
                                in: 0...max(1.0, player.duration),
                                onEditingChanged: { editing in
                                    if editing {
                                        player.isSeeking = true
                                    } else {
                                        if let target = dragTime {
                                            player.seek(to: target)
                                        }
                                        dragTime = nil
                                    }
                                }
                            )
                            .controlSize(.mini)
                            .tint(WalkmanTheme.silver)
                            .frame(width: 280)

                            Text(formatTime(player.duration))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                        }
                    }

                    Spacer()

                    // RIGHT: Volume & Info Inspector Button
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: player.volume > 0.5 ? "speaker.wave.2.fill" : (player.volume > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Slider(value: $player.volume, in: 0...1)
                                .controlSize(.mini)
                                .tint(WalkmanTheme.silver)
                                .frame(width: 70)
                        }

                        Button(action: onOpenInspector) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text("Details")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("View & edit metadata tags, hardware compliance, and artwork")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    WalkmanTheme.card
                        .background(.ultraThinMaterial)
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
