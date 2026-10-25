import SwiftUI
import AppKit

public struct TrackPreviewBar: View {
    @ObservedObject var player = AudioPlayerService.shared
    @ObservedObject var progress = AudioPlayerService.shared.progress
    var isInspectorPresented: Bool = false
    let onOpenInspector: () -> Void

    @State private var dragTime: Double? = nil

    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func secondarySpecs(for track: Track) -> String {
        var parts: [String] = []
        if track.sampleRate > 0 {
            parts.append("\(track.bitsPerSample)b/\(String(format: "%.1f", Double(track.sampleRate)/1000.0))k")
        }
        if track.bitrateKbps > 0 {
            parts.append("\(track.bitrateKbps) kbps")
        }
        return parts.joined(separator: " • ")
    }

    public var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                Divider()
                    .overlay(Color.white.opacity(0.1))

                HStack(spacing: 12) {
                    // LEFT: Track Info & Cover Art Thumbnail
                    let isHiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
                    HStack(spacing: 10) {
                        Button(action: onOpenInspector) {
                            ZStack {
                                if let img = player.currentCoverArt {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 42, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                } else {
                                    TrackCoverThumbnail(track: track, size: 42, isPlaying: player.isPlaying)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(player.isPlaying ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Click to view full metadata details & artwork")

                        VStack(alignment: .leading, spacing: 2.5) {
                            HStack(spacing: 6) {
                                Text(track.title)
                                    .font(WalkmanFont.bodyBold)
                                    .foregroundStyle(player.isPlaying ? .white : Color(white: 0.9))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                if isHiRes {
                                    Text("Hi-Res")
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(WalkmanTheme.hiResGoldGradient)
                                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
                                        .fixedSize()
                                }
                            }

                            Text("\(track.artist) • \(track.album)")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(spacing: 5) {
                                Text(track.format)
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1.5)
                                    .background(isHiRes ? WalkmanTheme.hiResGold.opacity(0.16) : Color.white.opacity(0.10))
                                    .foregroundStyle(isHiRes ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .fixedSize()

                                let specs = secondarySpecs(for: track)
                                if !specs.isEmpty {
                                    Text(specs)
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(isHiRes ? WalkmanTheme.hiResGold.opacity(0.9) : Color.white.opacity(0.45))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .frame(minWidth: 130, idealWidth: 190, maxWidth: 250, alignment: .leading)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 6)

                    // CENTER: Playback Controls & Interactive Scrubber
                    VStack(spacing: 4) {
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
                        HStack(spacing: 6) {
                            let curTime = dragTime ?? progress.currentTime
                            Text(formatTime(curTime))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)

                            Slider(
                                value: Binding(
                                    get: { dragTime ?? progress.currentTime },
                                    set: { newTime in
                                        dragTime = newTime
                                    }
                                ),
                                in: 0...max(1.0, progress.duration),
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
                            .frame(minWidth: 70, idealWidth: 180, maxWidth: 280)

                            Text(formatTime(progress.duration))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 160, maxWidth: 380)
                    .layoutPriority(2)

                    Spacer(minLength: 6)

                    // RIGHT: Volume & Info Inspector Button
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: player.volume > 0.5 ? "speaker.wave.2.fill" : (player.volume > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Slider(value: $player.volume, in: 0...1)
                                .controlSize(.mini)
                                .tint(WalkmanTheme.silver)
                                .frame(minWidth: 44, idealWidth: 60, maxWidth: 75)
                        }

                        if !isInspectorPresented {
                            Button(action: onOpenInspector) {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 12))
                                    Text("Details")
                                        .font(WalkmanFont.subheadlineMedium)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .help("View & edit metadata tags, hardware compliance, and artwork")
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .animation(.easeInOut(duration: 0.2), value: isInspectorPresented)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    WalkmanTheme.card
                        .background(.ultraThinMaterial)
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
