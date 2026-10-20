import SwiftUI

public struct DeviceOverviewView: View {
    let drives: [WalkmanDrive]
    let tracks: [Track]
    let onNavigateToTab: (NavigationTab) -> Void
    let onOpenEject: () -> Void
    let onRefresh: () -> Void
    var deviceInfo: WalkmanDeviceInfo? = nil
    var onOpenAbout: (() -> Void)? = nil
    
    private var internalDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .internal })
    }
    
    private var microsdDrive: WalkmanDrive? {
        drives.first(where: { $0.type == .microsd })
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 GB" }
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb < 1 {
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f GB", gb)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Device Header (Finder / Apple Devices Style)
                HStack(spacing: 20) {
                    // Device Icon (Accurate Sony Walkman Hardware Icon)
                    WalkmanDeviceIconView(
                        size: 68,
                        mountPoint: internalDrive?.mountPoint ?? drives.first?.mountPoint
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(deviceInfo?.displayName ?? "Sony Walkman NW-A55L")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Hi-Res Audio")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(WalkmanTheme.silver)
                                .clipShape(Capsule())
                            
                            if let fw = deviceInfo?.firmwareVersion {
                                Text("FW v\(fw)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text("Connected via USB Mass Storage • Sony OS / Linux Architecture")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Label("\(tracks.count.formatted()) Tracks Indexed", systemImage: "music.note")
                            Label(internalDrive != nil ? "Internal Storage Ready" : "Internal Offline", systemImage: "internaldrive")
                            Label(microsdDrive != nil ? "MicroSD Ready" : "No MicroSD", systemImage: "sdcard")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                    }
                    
                    Spacer()
                    
                    // Quick Action: Clean & Safe Eject
                    Button(action: onOpenEject) {
                        HStack(spacing: 6) {
                            Image(systemName: "eject.circle.fill")
                            Text("Clean Junk & Eject")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .liquidGlass(cornerRadius: 16)
                
                // Storage Capacities (Apple HIG Gauges)
                VStack(alignment: .leading, spacing: 14) {
                    Text("STORAGE ALLOCATION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    
                    HStack(spacing: 16) {
                        // Internal Storage
                        if let d = internalDrive {
                            StorageDriveCard(
                                title: "Internal WALKMAN",
                                subtitle: "/Volumes/\(d.name)",
                                icon: "internaldrive",
                                usedBytes: d.usedBytes,
                                freeBytes: d.freeBytes,
                                totalBytes: d.totalBytes,
                                percentUsed: d.percentUsed,
                                formatBytes: formatBytes
                            )
                        } else {
                            StorageDriveCard(
                                title: "Internal WALKMAN",
                                subtitle: "Not Mounted",
                                icon: "internaldrive",
                                usedBytes: 0,
                                freeBytes: 0,
                                totalBytes: 0,
                                percentUsed: 0,
                                formatBytes: formatBytes
                            )
                        }
                        
                        // MicroSD Storage
                        if let d = microsdDrive {
                            StorageDriveCard(
                                title: "MicroSD Expansion",
                                subtitle: "/Volumes/\(d.name)",
                                icon: "sdcard",
                                usedBytes: d.usedBytes,
                                freeBytes: d.freeBytes,
                                totalBytes: d.totalBytes,
                                percentUsed: d.percentUsed,
                                formatBytes: formatBytes
                            )
                        } else {
                            StorageDriveCard(
                                title: "MicroSD Expansion",
                                subtitle: "Slot Empty",
                                icon: "sdcard",
                                usedBytes: 0,
                                freeBytes: 0,
                                totalBytes: 0,
                                percentUsed: 0,
                                formatBytes: formatBytes
                            )
                        }
                    }
                }
                
                // Quick Navigation Cards
                VStack(alignment: .leading, spacing: 14) {
                    Text("QUICK WORKFLOWS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ActionCard(
                            title: "Music Library",
                            description: "Browse \(tracks.count.formatted()) tracks, search by artist or album, and inspect tags.",
                            icon: "music.note.list",
                            action: { onNavigateToTab(.library) }
                        )
                        
                        ActionCard(
                            title: "Transfer & Convert",
                            description: "Drag-and-drop audio files from Finder with automatic FFmpeg transcoding.",
                            icon: "arrow.up.arrow.down.circle",
                            action: { onNavigateToTab(.transfer) }
                        )
                        
                        ActionCard(
                            title: "Playlists (.M3U8)",
                            description: "Manage hardware-compliant CRLF POSIX playlists saved in /MUSIC/.",
                            icon: "list.bullet.rectangle",
                            action: { onNavigateToTab(.playlists) }
                        )
                    }
                }
                
                // Strict Hardware Constraints Checklist (Live Status)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SONY NON-ANDROID HARDWARE COMPLIANCE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        
                        if let onAbout = onOpenAbout {
                            Button(action: onAbout) {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                    Text("About & Supported Devices")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Active & Enforced")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    VStack(spacing: 8) {
                        ComplianceRow(
                            title: "Baseline RGB JPEG Artwork",
                            detail: "Non-progressive, no CMYK, max 800×800 px encoded via Apple ImageIO",
                            isEnforced: true
                        )
                        ComplianceRow(
                            title: "Strict ID3v2.3 (UTF-16) Tagging",
                            detail: "MP3s written with ID3v2.3 encoding=1 to prevent Sony player freeze bugs",
                            isEnforced: true
                        )
                        ComplianceRow(
                            title: "FAT32 / exFAT Path Sanitization",
                            detail: "Illegal characters < > : \" / \\ | ? * and trailing dots stripped automatically",
                            isEnforced: true
                        )
                        ComplianceRow(
                            title: "CRLF Relative POSIX Playlists",
                            detail: "M3U8 playlists formatted with \\r\\n line endings inside /MUSIC/",
                            isEnforced: true
                        )
                        ComplianceRow(
                            title: "macOS Shadow File Purging",
                            detail: "dot_clean -m automatically merges AppleDouble forks and removes ._* / .DS_Store",
                            isEnforced: true
                        )
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 12)
                }
            }
            .padding(20)
        }
    }
}

private struct StorageDriveCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let usedBytes: Int64
    let freeBytes: Int64
    let totalBytes: Int64
    let percentUsed: Double
    let formatBytes: (Int64) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%.1f%%", percentUsed))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(percentUsed > 95 ? Color.orange : WalkmanTheme.silver)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(WalkmanTheme.storageGradient)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, percentUsed / 100.0))), height: 8)
                }
            }
            .frame(height: 8)
            
            // Numbers
            HStack {
                Text("\(formatBytes(usedBytes)) Used")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(formatBytes(freeBytes)) Available")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 14)
    }
}

private struct ActionCard: View {
    let title: String
    let description: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

private struct ComplianceRow: View {
    let title: String
    let detail: String
    let isEnforced: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isEnforced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(isEnforced ? Color.green : Color.orange)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
