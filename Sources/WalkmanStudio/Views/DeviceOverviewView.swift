import SwiftUI

public struct DeviceOverviewView: View {
    let drives: [WalkmanDrive]
    var activeDrive: WalkmanDrive? = nil
    let tracks: [Track]
    var precomputedStats: (albums: Int, artists: Int, hiRes: Int)? = nil
    let onNavigateToTab: (NavigationTab) -> Void
    let onOpenEject: () -> Void
    let onRefresh: () -> Void
    var onSelectDrive: ((WalkmanDrive) -> Void)? = nil
    var deviceInfo: WalkmanDeviceInfo? = nil
    var onOpenAbout: (() -> Void)? = nil
    var isEjecting: Bool = false
    
    @State private var stats: (albums: Int, artists: Int, hiRes: Int) = (0, 0, 0)
    
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
    
    private var effectiveStats: (albums: Int, artists: Int, hiRes: Int) {
        if let p = precomputedStats, (p.albums > 0 || p.artists > 0 || tracks.isEmpty) {
            return p
        }
        return stats
    }
    
    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let isCompact = width < 760
            let isNarrow = width < 520
            let isSmallest = width < 380
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: isNarrow ? 12 : 20) {
                    heroHeaderView(isCompact: isCompact, isNarrow: isNarrow, isSmallest: isSmallest)
                    storageAllocationSection(isCompact: isCompact)
                    quickWorkflowsSection(isCompact: isCompact)
                    hardwareComplianceSection(isNarrow: isNarrow)
                }
                .padding(isNarrow ? 10 : 16)
                .frame(width: max(0, width), alignment: .top)
            }
        }
        .clipped()
        .onAppear {
            syncStats()
        }
        .onChange(of: tracks.count) { _, _ in
            syncStats()
        }
    }
    
    private func syncStats() {
        if let p = precomputedStats, (p.albums > 0 || p.artists > 0 || tracks.isEmpty) {
            self.stats = p
        } else {
            Task.detached(priority: .userInitiated) {
                var albumSet = Set<String>()
                var artistSet = Set<String>()
                var hiRes = 0
                for track in self.tracks {
                    let alb = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
                    let art = track.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
                    albumSet.insert("\(art)|\(alb)")
                    if !art.isEmpty { artistSet.insert(art) }
                    if track.bitsPerSample > 16 || track.sampleRate > 48000 { hiRes += 1 }
                }
                let res = (albumSet.count, artistSet.count, hiRes)
                await MainActor.run {
                    self.stats = res
                }
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // HERO HEADER
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func heroHeaderView(isCompact: Bool, isNarrow: Bool, isSmallest: Bool) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: isSmallest ? 10 : 12) {
                HStack(alignment: .top, spacing: isSmallest ? 10 : 12) {
                    WalkmanDeviceIconView(
                        size: isSmallest ? 44 : (isNarrow ? 52 : 60),
                        mountPoint: internalDrive?.mountPoint ?? drives.first?.mountPoint
                    )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deviceInfo?.displayName ?? "Sony Walkman")
                            .font(isSmallest ? WalkmanFont.headline : (isNarrow ? WalkmanFont.title2 : WalkmanFont.title1))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        HStack(spacing: 5) {
                            Text("Hi-Res Audio")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(WalkmanTheme.hiResGoldGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(Capsule())
                                .shadow(color: WalkmanTheme.hiResGold.opacity(0.35), radius: 3, x: 0, y: 1)
                            
                            if let fw = deviceInfo?.firmwareVersion {
                                Text("FW v\(fw)")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if !isSmallest {
                            Text("Connected via USB Mass Storage • Sony OS")
                                .font(WalkmanFont.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if !isNarrow {
                        Spacer(minLength: 6)
                        cleanEjectButton
                    }
                }
                
                if isNarrow {
                    cleanEjectButton
                        .frame(maxWidth: isSmallest ? .infinity : nil, alignment: .trailing)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Stats Grid
                if isNarrow {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                        statItem(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight)
                    }
                } else {
                    HStack(spacing: 14) {
                        statItem(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight)
                    }
                }
            }
            .padding(isSmallest ? 12 : 14)
            .liquidGlass(cornerRadius: 14)
        } else {
            HStack(spacing: 16) {
                WalkmanDeviceIconView(
                    size: 64,
                    mountPoint: internalDrive?.mountPoint ?? drives.first?.mountPoint
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(deviceInfo?.displayName ?? "Sony Walkman")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.white)
                        
                        Text("Hi-Res Audio")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(Capsule())
                            .shadow(color: WalkmanTheme.hiResGold.opacity(0.35), radius: 4, x: 0, y: 1)
                        
                        if let fw = deviceInfo?.firmwareVersion {
                            Text("FW v\(fw)")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text("Connected via USB Mass Storage • Sony OS / Linux Architecture")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 14) {
                        statItem(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: WalkmanTheme.silver)
                        statItem(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight)
                    }
                    .padding(.top, 2)
                }
                
                Spacer(minLength: 10)
                
                cleanEjectButton
            }
            .padding(18)
            .liquidGlass(cornerRadius: 16)
        }
    }
    
    private var cleanEjectButton: some View {
        Button(action: onOpenEject) {
            HStack(spacing: 5) {
                if isEjecting {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Ejecting...")
                } else {
                    Image(systemName: "eject.circle.fill")
                    Text("Eject")
                }
            }
            .font(WalkmanFont.calloutBold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(WalkmanTheme.silverGradient)
            .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isEjecting)
        .help("Clean macOS ghost files and safely unmount Walkman")
    }
    
    private func statItem(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(color)
            Text(title)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    // -------------------------------------------------------------------------
    // STORAGE ALLOCATION
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func storageAllocationSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STORAGE ALLOCATION")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            if isCompact {
                VStack(spacing: 10) {
                    internalDriveCard
                    microsdDriveCard
                }
            } else {
                HStack(spacing: 12) {
                    internalDriveCard
                    microsdDriveCard
                }
            }
        }
    }
    
    private var internalDriveCard: some View {
        Group {
            if let d = internalDrive {
                let isSelected = activeDrive?.mountPoint == d.mountPoint
                StorageDriveCard(
                    title: "Internal WALKMAN",
                    subtitle: "/Volumes/\(d.name)",
                    icon: "internaldrive",
                    usedBytes: d.usedBytes,
                    freeBytes: d.freeBytes,
                    totalBytes: d.totalBytes,
                    percentUsed: d.percentUsed,
                    formatBytes: formatBytes,
                    isSelected: isSelected,
                    onSelect: { onSelectDrive?(d) }
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
                    formatBytes: formatBytes,
                    isSelected: false,
                    onSelect: nil
                )
            }
        }
    }
    
    private var microsdDriveCard: some View {
        Group {
            if let d = microsdDrive {
                let isSelected = activeDrive?.mountPoint == d.mountPoint
                StorageDriveCard(
                    title: "MicroSD Expansion",
                    subtitle: "/Volumes/\(d.name)",
                    icon: "sdcard",
                    usedBytes: d.usedBytes,
                    freeBytes: d.freeBytes,
                    totalBytes: d.totalBytes,
                    percentUsed: d.percentUsed,
                    formatBytes: formatBytes,
                    isSelected: isSelected,
                    onSelect: { onSelectDrive?(d) }
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
                    formatBytes: formatBytes,
                    isSelected: false,
                    onSelect: nil
                )
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // QUICK WORKFLOWS
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func quickWorkflowsSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK WORKFLOWS")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            if isCompact {
                VStack(spacing: 8) {
                    ActionCard(
                        title: "Music Library",
                        description: "Browse \(tracks.count.formatted()) tracks across \(effectiveStats.albums.formatted()) albums and \(effectiveStats.artists.formatted()) artists.",
                        icon: "music.note.list",
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.library) }
                    )
                    
                    ActionCard(
                        title: "Transfer & Convert",
                        description: "Drag-and-drop audio files from Finder with automatic FFmpeg transcoding.",
                        icon: "arrow.up.arrow.down.circle",
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.transfer) }
                    )
                    
                    ActionCard(
                        title: "Playlists (.M3U8)",
                        description: "Manage hardware-compliant CRLF POSIX playlists saved in /MUSIC/.",
                        icon: "list.bullet.rectangle",
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.playlists) }
                    )
                }
            } else {
                HStack(spacing: 12) {
                    ActionCard(
                        title: "Music Library",
                        description: "Browse \(tracks.count.formatted()) tracks across \(effectiveStats.albums.formatted()) albums and \(effectiveStats.artists.formatted()) artists.",
                        icon: "music.note.list",
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.library) }
                    )
                    
                    ActionCard(
                        title: "Transfer & Convert",
                        description: "Drag-and-drop audio files from Finder with automatic FFmpeg transcoding.",
                        icon: "arrow.up.arrow.down.circle",
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.transfer) }
                    )
                    
                    ActionCard(
                        title: "Playlists (.M3U8)",
                        description: "Manage hardware-compliant CRLF POSIX playlists saved in /MUSIC/.",
                        icon: "list.bullet.rectangle",
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.playlists) }
                    )
                }
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // HARDWARE COMPLIANCE
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func hardwareComplianceSection(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isNarrow {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SONY HARDWARE COMPLIANCE")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.secondary)
                    
                    if let onAbout = onOpenAbout {
                        aboutButton(onAbout)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                HStack {
                    Text("SONY NON-ANDROID HARDWARE COMPLIANCE")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.secondary)
                    Spacer()
                    
                    if let onAbout = onOpenAbout {
                        aboutButton(onAbout)
                    } else {
                        Text("Active & Enforced")
                            .font(WalkmanFont.monoSmall.weight(.bold))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                    }
                }
                .padding(.horizontal, 4)
            }
            
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
            .padding(12)
            .liquidGlass(cornerRadius: 12)
        }
    }
    
    private func aboutButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5))
                Text("About & Supported Devices")
                    .font(WalkmanFont.subheadlineMedium)
            }
            .foregroundStyle(WalkmanTheme.silverLight)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onSelect?()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(title)
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            if isSelected {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(WalkmanTheme.silverLight)
                                        .frame(width: 5, height: 5)
                                    Text("Selected")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(WalkmanTheme.silverLight)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(WalkmanTheme.silver.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(WalkmanTheme.silver.opacity(0.45), lineWidth: 0.8)
                                )
                            }
                        }
                        
                        Text(subtitle)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight.opacity(0.75) : .secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    Text(String(format: "%.1f%%", percentUsed))
                        .font(WalkmanFont.monoSmall.weight(.bold))
                        .foregroundStyle(percentUsed > 95 ? Color.orange : (isSelected ? .white : WalkmanTheme.silver))
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 7)
                        
                        Capsule()
                            .fill(isSelected ? WalkmanTheme.silverGradient : WalkmanTheme.storageGradient)
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, percentUsed / 100.0))), height: 7)
                    }
                }
                .frame(height: 7)
                
                // Numbers
                HStack {
                    Text("\(formatBytes(usedBytes)) Used")
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Text("\(formatBytes(freeBytes)) Available")
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.04) : Color.clear)
            )
            .liquidGlass(cornerRadius: 12, borderOpacity: isSelected ? 0.75 : 0.35)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? WalkmanTheme.silverLight.opacity(0.65) : (isHovered && onSelect != nil ? Color.white.opacity(0.15) : Color.clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct ActionCard: View {
    let title: String
    let description: String
    let icon: String
    var isHorizontalRow: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if isHorizontalRow {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .frame(width: 22)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(WalkmanFont.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(description)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 10)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(WalkmanFont.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(description)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .liquidGlass(cornerRadius: 12)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ComplianceRow: View {
    let title: String
    let detail: String
    let isEnforced: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isEnforced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(isEnforced ? Color.green : Color.orange)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
