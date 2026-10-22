import SwiftUI

public struct TopStorageBarView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    let onSelectDrive: (WalkmanDrive) -> Void
    let onRefresh: () -> Void
    let onOpenEject: () -> Void
    let isRefreshing: Bool
    var isEjecting: Bool = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 GB" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb < 1 {
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f GB", gb)
    }

    private var internalDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .internal })
    }

    private var microsdDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .microsd })
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Sony Walkman Branding
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WalkmanTheme.silverGradient)
                        .frame(width: 34, height: 34)

                    Text("W.")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("WALKMAN STUDIO")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)

                        Text("WALKMAN")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Text("Native Apple Silicon")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text("Signature Edition")
                            .font(WalkmanFont.subheadlineMedium)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                }
            }

            Spacer()

            // Dual Storage Drives Gauge
            HStack(spacing: 12) {
                // Internal Walkman Gauge
                if let drive = internalDrive {
                    driveGaugeButton(
                        drive: drive,
                        icon: "internaldrive",
                        isSelected: activeDrive?.mountPoint == drive.mountPoint
                    )
                } else {
                    disconnectedPill(title: "Internal WALKMAN: Disconnected")
                }

                // MicroSD Gauge
                if let drive = microsdDrive {
                    driveGaugeButton(
                        drive: drive,
                        icon: "sdcard",
                        isSelected: activeDrive?.mountPoint == drive.mountPoint
                    )
                } else {
                    disconnectedPill(title: "MicroSD: Empty")
                }

                // Rescan Button
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .padding(8)
                        .background(WalkmanTheme.card)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(WalkmanTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Rescan Walkman storage volumes")
            }

            Spacer()

            // 1-Click Eject & Clean
            Button(action: onOpenEject) {
                HStack(spacing: 6) {
                    if isEjecting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text("Ejecting...")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    } else {
                        Image(systemName: "eject.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silver)

                        Text("Eject")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(WalkmanTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(WalkmanTheme.silver.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(activeDrive == nil || isEjecting)
            .opacity((activeDrive == nil || isEjecting) ? 0.4 : 1.0)
            .help("Run dot_clean -m, purge macOS ghost files, and safely unmount Walkman")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(WalkmanTheme.obsidian.opacity(0.95))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)
    }

    private func driveGaugeButton(drive: WalkmanDrive, icon: String, isSelected: Bool) -> some View {
        Button(action: { onSelectDrive(drive) }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? WalkmanTheme.silverLight : .secondary)

                    Text(drive.name)
                        .font(WalkmanFont.bodyMedium)
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    HStack(spacing: 2) {
                        Text(formatBytes(drive.freeBytes))
                            .font(WalkmanFont.monoSmall.weight(.bold))
                            .foregroundStyle(.white)
                        Text("/ \(formatBytes(drive.totalBytes)) free")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(WalkmanTheme.storageGradient)
                            .frame(width: geo.size.width * CGFloat(min(1.0, max(0.01, drive.percentUsed / 100.0))), height: 3)
                    }
                }
                .frame(width: 170, height: 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? WalkmanTheme.cardHover : WalkmanTheme.card.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? WalkmanTheme.silver.opacity(0.6) : WalkmanTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func disconnectedPill(title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
            Text(title)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WalkmanTheme.card.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(WalkmanTheme.border.opacity(0.5), lineWidth: 1)
        )
    }
}
