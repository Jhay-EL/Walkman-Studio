import SwiftUI
import AppKit

// MARK: - Transfer Sync Confirmation Sheet
public struct TransferSyncSheet: View {
    let queue: [TransferItem]
    let targetDrive: WalkmanDrive?
    let targetMode: TransferTargetMode
    let preset: String
    let presetDescription: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    public init(
        queue: [TransferItem],
        targetDrive: WalkmanDrive?,
        targetMode: TransferTargetMode,
        preset: String,
        presetDescription: String,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.queue = queue
        self.targetDrive = targetDrive
        self.targetMode = targetMode
        self.preset = preset
        self.presetDescription = presetDescription
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var totalBytes: Int64 {
        queue.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalDuration: Double {
        queue.reduce(0) { $0 + $1.durationSeconds }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Dismiss
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WalkmanTheme.silverGradient)
                        .frame(width: 48, height: 48)

                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                }
                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Sync to Sony Walkman")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.primary)

                        Text("\(queue.count) Tracks")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.hiResGold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(WalkmanTheme.hiResGold.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text("Review target storage drive, conversion preset, and hardware optimization settings.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.top, -10)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // Content Section
            VStack(spacing: 12) {
                // Metric Chips
                HStack(spacing: 10) {
                    MetricChip(
                        icon: "music.note.list",
                        label: "Queue Items",
                        value: "\(queue.count) Tracks",
                        accentColor: WalkmanTheme.silverLight
                    )
                    MetricChip(
                        icon: "internaldrive.badge.arrow.down",
                        label: "Payload Size",
                        value: WalkmanEngine.formatBytes(totalBytes),
                        accentColor: Color.green
                    )
                    MetricChip(
                        icon: "clock",
                        label: "Total Duration",
                        value: WalkmanEngine.formatDuration(totalDuration),
                        accentColor: WalkmanTheme.silverLight
                    )
                }

                // Destination & Preset Summary Card
                VStack(spacing: 1) {
                    SpecRow(label: "Destination Drive", value: "\(targetDrive?.name ?? "WALKMAN") (/\(targetMode.rootFolderName)/)")
                    SpecRow(label: "Conversion Preset", value: presetDescription)
                    SpecRow(label: "Tag Standard", value: "Strict ID3v2.3 (UTF-16) & Vorbis")
                    SpecRow(label: "Artwork Engine", value: "Baseline RGB JPEG (800×800)")
                    SpecRow(label: "AppleDouble Purge", value: "Clean ._* and .DS_Store ghost files")
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
                )

                // Staged Track List Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRACKS TO BE TRANSFERRED (\(queue.count))")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(queue) { itm in
                                HStack(spacing: 10) {
                                    ZStack {
                                        if let art = itm.artworkData, let img = NSImage(data: art) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 32, height: 32)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.06))
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Image(systemName: "music.note")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                                )
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(itm.title.isEmpty ? itm.sourceURL.deletingPathExtension().lastPathComponent : itm.title)
                                            .font(WalkmanFont.bodyMedium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(itm.artist.isEmpty ? "Unknown Artist" : itm.artist)
                                            .font(WalkmanFont.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(itm.format)
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))

                                    Text(WalkmanEngine.formatBytes(itm.sizeBytes))
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 12)

            // Footer
            HStack(alignment: .center) {
                Text("Files are staged chronologically for Walkman Recent Transfers.")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                // Cancel Button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.25 : 0.12), lineWidth: 0.85)
                        )
                        .scaleEffect(isCancelHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isCancelHovered = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                // Start Transfer Button
                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Start Transfer Now")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8.5)
                    .background(WalkmanTheme.silverGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.20), radius: isConfirmHovered ? 6 : 3, x: 0, y: isConfirmHovered ? 2 : 1)
                    .scaleEffect(isConfirmHovered ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isConfirmHovered = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 680, height: 600)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen (Apple Liquid Glass refraction)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }
}

// MARK: - Clear Queue Confirmation Sheet
public struct ClearQueueConfirmSheet: View {
    let queueCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    public init(
        queueCount: Int,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.queueCount = queueCount
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.red.opacity(0.35), lineWidth: 0.85)
                        )
                    Image(systemName: "trash.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.red)
                }

                VStack(spacing: 6) {
                    Text("Clear Transfer Queue?")
                        .font(WalkmanFont.title1)
                        .foregroundStyle(.primary)

                    Text("This will remove all \(queueCount) staged audio tracks from the transfer queue. Original files on your Mac will not be touched.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer()

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack {
                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.25 : 0.12), lineWidth: 0.85)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isCancelHovered = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Clear Queue")
                    }
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.20), radius: isConfirmHovered ? 6 : 3, x: 0, y: isConfirmHovered ? 2 : 1)
                    .scaleEffect(isConfirmHovered ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { h in
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) { isConfirmHovered = h }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 320)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }
}

// MARK: - Metric Chip
private struct MetricChip: View {
    let icon: String
    let label: String
    let value: String
    var accentColor: Color = WalkmanTheme.silverLight

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(value)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }
}

// MARK: - Spec Row
private struct SpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(WalkmanFont.calloutMedium)
                .foregroundStyle(WalkmanTheme.silverMuted)
            Spacer()
            Text(value)
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8.5)
        .background(Color.white.opacity(0.035))
    }
}

// MARK: - Sheet Close Button
private struct SheetCloseButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.14 : 0.07))
                    .frame(width: 28, height: 28)

                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.25 : 0.12), lineWidth: 0.8)
                    .frame(width: 28, height: 28)

                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.65))
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
