import SwiftUI
import AppKit

public struct TrackPreviewBar: View {
    @ObservedObject var player = AudioPlayerService.shared
    @ObservedObject var progress = AudioPlayerService.shared.progress
    var libraryTracks: [Track] = []
    var isInspectorPresented: Bool = false
    let onOpenInspector: () -> Void

    @State private var dragTime: Double? = nil
    @State private var isArtworkHovered: Bool = false
    @State private var lastNonZeroVolume: Float = 0.8

    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    public var body: some View {
        HStack(spacing: 12) {
            // LEFT: Transport controls (Shuffle, Prev, Play/Pause, Next, Repeat)
            transportControlsZone

            // CENTER: Now Playing Display Pod
            centerDisplayPod

            // RIGHT: Volume & Details Inspector Toggle
            trailingControlsZone
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(height: 56)
        .background(
            ZStack {
                // Native Apple macOS ultra-thin frosted glass material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Translucent obsidian veil (reveals UI elements underneath while keeping controls sharp)
                Color(red: 16 / 255, green: 17 / 255, blue: 21 / 255)
                    .opacity(0.42)

                // Subtle white ambient reflection
                Color.white
                    .opacity(0.035)

                // Top specular refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.25), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.09), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
    }

    // MARK: - Left: Transport Controls
    private var transportControlsZone: some View {
        HStack(spacing: 9) {
            // Shuffle
            PlayerIconButton(
                systemName: "shuffle",
                size: 11,
                isActive: player.isShuffle,
                helpText: player.isShuffle ? "Shuffle: On" : "Shuffle: Off",
                action: { player.isShuffle.toggle() }
            )

            // Previous
            PlayerIconButton(
                systemName: "backward.fill",
                size: 12,
                isActive: false,
                isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                helpText: "Previous track",
                action: { player.playPrevious() }
            )

            // Play / Pause prominent circular button
            PlayPauseCircleButton(
                isPlaying: player.isPlaying,
                isEnabled: player.currentTrack != nil || !libraryTracks.isEmpty,
                action: {
                    if player.currentTrack != nil {
                        player.togglePlayPause()
                    } else if let first = libraryTracks.first {
                        player.play(track: first, in: libraryTracks)
                    }
                }
            )

            // Next
            PlayerIconButton(
                systemName: "forward.fill",
                size: 12,
                isActive: false,
                isDisabled: player.currentTrack == nil && libraryTracks.isEmpty,
                helpText: "Next track",
                action: { player.playNext() }
            )

            // Repeat
            PlayerIconButton(
                systemName: "repeat",
                size: 11,
                isActive: player.isRepeat,
                helpText: player.isRepeat ? "Repeat: On" : "Repeat: Off",
                action: { player.isRepeat.toggle() }
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Center: Display Pod
    private var centerDisplayPod: some View {
        ZStack {
            // Display pod inner glass styling (translucent)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.16), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )

            if let track = player.currentTrack {
                activeTrackDisplay(for: track)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                idleDisplay
                    .padding(.horizontal, 12)
            }
        }
        .frame(minWidth: 240, maxWidth: 640)
        .frame(height: 42)
    }

    @ViewBuilder
    private func activeTrackDisplay(for track: Track) -> some View {
        let isHiRes = track.bitsPerSample > 16 || track.sampleRate > 48000
        HStack(spacing: 8) {
            // Artwork thumbnail (clickable to open inspector)
            Button(action: onOpenInspector) {
                ZStack {
                    if let img = player.currentCoverArt {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        TrackCoverThumbnail(track: track, size: 34, isPlaying: player.isPlaying)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            isArtworkHovered ? Color.white.opacity(0.40) : (player.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.12)),
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(isArtworkHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isArtworkHovered)
            }
            .buttonStyle(.plain)
            .help("Click to view full metadata details & artwork")
            .onHover { h in
                isArtworkHovered = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Metadata & Scrubber
            VStack(alignment: .leading, spacing: 1.5) {
                // Top row: Title and Artist only
                HStack(spacing: 5) {
                    Text(track.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(player.isPlaying ? .white : Color(white: 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.7))

                    Text(track.artist)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Bottom row: Timeline scrubber
                HStack(spacing: 5) {
                    let curTime = dragTime ?? progress.currentTime
                    Text(formatTime(curTime))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { dragTime ?? progress.currentTime },
                            set: { newTime in dragTime = newTime }
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
                    .tint(isHiRes ? WalkmanTheme.hiResGold : WalkmanTheme.silver)

                    Text(formatTime(progress.duration))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                }
            }
        }
    }

    private var idleDisplay: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))

            Text("Walkman Studio")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(WalkmanTheme.silverLight)

            Text("•")
                .font(.system(size: 8))
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.4))

            Text("Ready • Select a track to play")
                .font(.system(size: 11))
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right: Volume Control
    private var trailingControlsZone: some View {
        HStack(spacing: 6) {
            Button(action: {
                if player.volume > 0.001 {
                    lastNonZeroVolume = player.volume
                    player.volume = 0.0
                } else {
                    player.volume = lastNonZeroVolume > 0.05 ? lastNonZeroVolume : 0.8
                }
            }) {
                Image(systemName: player.volume > 0.5 ? "speaker.wave.2.fill" : (player.volume > 0.001 ? "speaker.wave.1.fill" : "speaker.slash.fill"))
                    .font(.system(size: 12))
                    .foregroundStyle(player.volume > 0.001 ? WalkmanTheme.silverMuted : Color.white.opacity(0.4))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(player.volume > 0.001 ? "Mute" : "Unmute")
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .tint(WalkmanTheme.silver)
                .frame(width: 76)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Subviews

private struct PlayerIconButton: View {
    let systemName: String
    let size: CGFloat
    let isActive: Bool
    var isDisabled: Bool = false
    let helpText: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: isActive ? .bold : .medium))
                .foregroundStyle(
                    isDisabled ? Color.white.opacity(0.20) :
                    (isActive ? WalkmanTheme.hiResGold : (isHovered ? .white : Color.white.opacity(0.65)))
                )
                .frame(width: 24, height: 24)
                .scaleEffect(isHovered && !isDisabled ? 1.10 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .onHover { h in
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct PlayPauseCircleButton: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isEnabled ?
                                (isHovered ? [Color.white, Color(white: 0.92)] : [Color(white: 0.95), Color(white: 0.82)]) :
                                [Color.white.opacity(0.3), Color.white.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 32, height: 32)

                // Specular top highlight
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.45 : 0.25), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
                    .offset(x: isPlaying ? 0 : 1)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.45 : 0.25), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.20), radius: isHovered ? 3.5 : 2, x: 0, y: 1.5)
            .scaleEffect(isHovered && isEnabled ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.space, modifiers: [])
        .help(isPlaying ? "Pause (Space)" : "Play (Space)")
        .onHover { h in
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
