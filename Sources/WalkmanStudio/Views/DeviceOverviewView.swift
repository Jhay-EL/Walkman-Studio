import SwiftUI
import AppKit

public struct DeviceOverviewView: View {
    var devices: [WalkmanDevice] = []
    let drives: [WalkmanDrive]
    var activeDevice: WalkmanDevice? = nil
    var activeDrive: WalkmanDrive? = nil
    let tracks: [Track]
    var precomputedStats: (albums: Int, artists: Int, hiRes: Int)? = nil
    let onNavigateToTab: (NavigationTab) -> Void
    let onOpenEject: () -> Void
    let onRefresh: () -> Void
    var onSelectDevice: ((WalkmanDevice) -> Void)? = nil
    var onSelectDrive: ((WalkmanDrive) -> Void)? = nil
    var deviceInfo: WalkmanDeviceInfo? = nil
    var onOpenAbout: (() -> Void)? = nil
    var isEjecting: Bool = false
    
    @State private var stats: (albums: Int, artists: Int, hiRes: Int) = (0, 0, 0)
    @State private var lastSyncedTrackCount: Int = -1
    
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
            let isCompact = width < 880
            let isNarrow = width < 580
            let isSmallest = width < 420
            
            ZStack(alignment: .top) {
                // macOS 27 Golden Gate Ambient Atmosphere (Caustic Lighting behind Liquid Glass)
                atmosphericBackdrop
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: isNarrow ? 16 : 22) {
                        if devices.count > 1 {
                            deviceSwitcherBar
                        }
                        heroHeaderView(isCompact: isCompact, isNarrow: isNarrow, isSmallest: isSmallest)
                        storageAllocationSection(isCompact: isCompact)
                        quickWorkflowsSection(isCompact: isCompact)
                        hardwareComplianceSection(isNarrow: isNarrow)
                    }
                    .padding(isNarrow ? 12 : 18)
                    .padding(.bottom, 88)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .onAppear {
            syncStats()
        }
        .onChange(of: tracks.count) { _, _ in
            syncStats()
        }
    }
    
    // -------------------------------------------------------------------------
    // SOLID MATTE BACKDROP (Zero Gradient, Clean Obsidian Chassis)
    // -------------------------------------------------------------------------
    private var atmosphericBackdrop: some View {
        WalkmanTheme.background
    }
    
    private func syncStats() {
        if let p = precomputedStats, (p.albums > 0 || p.artists > 0 || tracks.isEmpty) {
            self.stats = p
            self.lastSyncedTrackCount = tracks.count
            return
        }
        guard lastSyncedTrackCount != tracks.count else { return }
        lastSyncedTrackCount = tracks.count
        
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

    // -------------------------------------------------------------------------
    // MULTI-DEVICE SWITCHER BAR
    // -------------------------------------------------------------------------
    private var deviceSwitcherBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                Text("CONNECTED WALKMAN PLAYERS (\(devices.count))")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(devices) { dev in
                        let isSelected = (activeDevice?.id == dev.id) || (activeDevice == nil && dev.id == devices.first?.id)
                        DeviceSegmentPill(
                            device: dev,
                            isSelected: isSelected,
                            onSelect: { onSelectDevice?(dev) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 2)
    }
    
    // -------------------------------------------------------------------------
    // HERO HEADER (Liquid Glass Stage)
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func heroHeaderView(isCompact: Bool, isNarrow: Bool, isSmallest: Bool) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: isSmallest ? 12 : 14) {
                HStack(alignment: .top, spacing: isSmallest ? 10 : 14) {
                    // Liquid Glass Pedestal for Device Icon
                    LiquidGlassDeviceShowcase(
                        size: isSmallest ? 48 : (isNarrow ? 56 : 64),
                        mountPoint: internalDrive?.mountPoint ?? drives.first?.mountPoint,
                        deviceInfo: deviceInfo
                    )
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(deviceInfo?.displayName ?? "Sony Walkman")
                            .font(isSmallest ? .system(size: 16, weight: .bold) : (isNarrow ? .system(size: 18, weight: .bold) : .system(size: 21, weight: .bold)))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        HStack(spacing: 6) {
                            liquidHiResBadge
                            
                            if let fw = deviceInfo?.firmwareVersion {
                                liquidFwBadge(version: fw)
                            }
                        }
                        
                        if !isSmallest {
                            HStack(spacing: 5) {
                                Image(systemName: "cable.connector.horizontal")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.white.opacity(0.35))
                                Text("Connected via USB Mass Storage • Sony OS")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.top, 1)
                        }
                    }
                    
                    if !isNarrow {
                        Spacer(minLength: 6)
                        cleanEjectLiquidButton
                    }
                }
                
                if isNarrow {
                    cleanEjectLiquidButton
                        .frame(maxWidth: isSmallest ? .infinity : nil, alignment: .trailing)
                }
                
                // Specular Glass Divider
                specularGlassDivider
                
                // Liquid Stat Chips
                if isNarrow {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                        LiquidStatChip(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silverLight)
                        LiquidStatChip(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack.fill", color: Color(red: 200/255, green: 210/255, blue: 235/255))
                        LiquidStatChip(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: Color(red: 175/255, green: 220/255, blue: 245/255))
                        LiquidStatChip(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight, isGold: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        LiquidStatChip(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silverLight)
                        LiquidStatChip(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack.fill", color: Color(red: 200/255, green: 210/255, blue: 235/255))
                        LiquidStatChip(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: Color(red: 175/255, green: 220/255, blue: 245/255))
                        LiquidStatChip(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight, isGold: true)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 18) {
                // Liquid Glass Pedestal for Device Icon
                LiquidGlassDeviceShowcase(
                    size: 70,
                    mountPoint: internalDrive?.mountPoint ?? drives.first?.mountPoint,
                    deviceInfo: deviceInfo
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        Text(deviceInfo?.displayName ?? "Sony Walkman")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        
                        liquidHiResBadge
                        
                        if let fw = deviceInfo?.firmwareVersion {
                            liquidFwBadge(version: fw)
                        }
                    }
                    
                    HStack(spacing: 5) {
                        Image(systemName: "cable.connector.horizontal")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.35))
                        Text("Connected via USB Mass Storage • Sony OS / Linux Architecture")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Liquid Stat Chips Row
                    HStack(spacing: 8) {
                        LiquidStatChip(title: "\(tracks.count.formatted()) Tracks", icon: "music.note", color: WalkmanTheme.silverLight)
                        LiquidStatChip(title: "\(effectiveStats.albums.formatted()) Albums", icon: "square.stack.fill", color: Color(red: 200/255, green: 210/255, blue: 235/255))
                        LiquidStatChip(title: "\(effectiveStats.artists.formatted()) Artists", icon: "music.mic", color: Color(red: 175/255, green: 220/255, blue: 245/255))
                        LiquidStatChip(title: "\(effectiveStats.hiRes.formatted()) Hi-Res", icon: "waveform.badge.magnifyingglass", color: WalkmanTheme.hiResGoldLight, isGold: true)
                    }
                    .padding(.top, 4)
                }
                
                Spacer(minLength: 12)
                
                cleanEjectLiquidButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
    
    // Liquid Glass Hi-Res Badge
    private var liquidHiResBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 8.5, weight: .black))
            Text("Hi-Res Audio")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            ZStack {
                WalkmanTheme.hiResGoldGradient
                
                // Specular liquid reflection
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
        )
        .foregroundStyle(Color(red: 22/255, green: 20/255, blue: 18/255))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), WalkmanTheme.hiResGoldLight.opacity(0.8), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
    }
    
    // Liquid Glass Firmware Badge
    private func liquidFwBadge(version: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "cpu")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text("FW v\(version)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            ZStack {
                Color.white.opacity(0.08)
                // Specular reflection
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
        )
    }
    
    // Liquid Glass Eject Action Button
    private var cleanEjectLiquidButton: some View {
        Button(action: onOpenEject) {
            HStack(spacing: 6) {
                if isEjecting {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                    Text("Ejecting...")
                } else {
                    Image(systemName: "eject.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Eject")
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .foregroundStyle(Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255))
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
        .disabled(isEjecting)
        .help("Safely unmount device and purge macOS shadow files (.DS_Store / AppleDouble)")
    }
    
    private var specularGlassDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white.opacity(0.12), location: 0.2),
                        .init(color: .white.opacity(0.15), location: 0.5),
                        .init(color: .white.opacity(0.12), location: 0.8),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 2)
    }
    
    // -------------------------------------------------------------------------
    // STORAGE ALLOCATION
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func storageAllocationSection(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text("STORAGE ALLOCATION")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: .infinity), spacing: 12)], spacing: 12) {
                internalDriveCard
                microsdDriveCard
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
                    icon: "internaldrive.fill",
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
                    icon: "internaldrive.fill",
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
                    icon: "sdcard.fill",
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
                    icon: "sdcard.fill",
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
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text("QUICK WORKFLOWS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            .padding(.horizontal, 4)
            
            if isCompact {
                VStack(spacing: 10) {
                    ActionCard(
                        title: "Music Library",
                        description: "Browse \(tracks.count.formatted()) tracks across \(effectiveStats.albums.formatted()) albums and \(effectiveStats.artists.formatted()) artists.",
                        icon: "music.note.list",
                        iconTint: Color(red: 165/255, green: 180/255, blue: 245/255),
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.library) }
                    )
                    
                    ActionCard(
                        title: "Transfer & Convert",
                        description: "Drag-and-drop audio files from Finder with automatic FFmpeg transcoding.",
                        icon: "arrow.up.arrow.down.circle.fill",
                        iconTint: Color(red: 130/255, green: 215/255, blue: 245/255),
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.transfer) }
                    )
                    
                    ActionCard(
                        title: "Playlist",
                        description: "Manage hardware-compliant CRLF POSIX playlists saved in /MUSIC/.",
                        icon: "list.bullet.rectangle.portrait.fill",
                        iconTint: Color(red: 150/255, green: 230/255, blue: 200/255),
                        isHorizontalRow: true,
                        action: { onNavigateToTab(.playlists) }
                    )
                }
            } else {
                HStack(spacing: 14) {
                    ActionCard(
                        title: "Music Library",
                        description: "Browse \(tracks.count.formatted()) tracks across \(effectiveStats.albums.formatted()) albums and \(effectiveStats.artists.formatted()) artists.",
                        icon: "music.note.list",
                        iconTint: Color(red: 165/255, green: 180/255, blue: 245/255),
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.library) }
                    )
                    
                    ActionCard(
                        title: "Transfer & Convert",
                        description: "Drag-and-drop audio files from Finder with automatic FFmpeg transcoding.",
                        icon: "arrow.up.arrow.down.circle.fill",
                        iconTint: Color(red: 130/255, green: 215/255, blue: 245/255),
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.transfer) }
                    )
                    
                    ActionCard(
                        title: "Playlist",
                        description: "Manage hardware-compliant CRLF POSIX playlists saved in /MUSIC/.",
                        icon: "list.bullet.rectangle.portrait.fill",
                        iconTint: Color(red: 150/255, green: 230/255, blue: 200/255),
                        isHorizontalRow: false,
                        action: { onNavigateToTab(.playlists) }
                    )
                }
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // HARDWARE COMPLIANCE (System Inspector Glass Panel)
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func hardwareComplianceSection(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isNarrow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("SONY HARDWARE COMPLIANCE")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                    }
                    
                    if let onAbout = onOpenAbout {
                        aboutLiquidButton(onAbout)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("SONY NON-ANDROID HARDWARE COMPLIANCE")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                    }
                    
                    Spacer()
                    
                    if let onAbout = onOpenAbout {
                        aboutLiquidButton(onAbout)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text("Active & Enforced")
                                .font(WalkmanFont.monoSmall.weight(.bold))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Unified Liquid Glass Panel
            VStack(spacing: 0) {
                ComplianceRow(
                    title: "Baseline RGB JPEG Artwork",
                    detail: "Non-progressive, no CMYK, max 800×800 px encoded via Apple ImageIO",
                    badge: "800×800 px • ImageIO",
                    isEnforced: true
                )
                
                complianceDivider
                
                ComplianceRow(
                    title: "Strict ID3v2.3 (UTF-16) Tagging",
                    detail: "MP3s written with ID3v2.3 encoding=1 to prevent Sony player freeze bugs",
                    badge: "ID3v2.3 • UTF-16",
                    isEnforced: true
                )
                
                complianceDivider
                
                ComplianceRow(
                    title: "FAT32 / exFAT Path Sanitization",
                    detail: "Illegal characters < > : \" / \\ | ? * and trailing dots stripped automatically",
                    badge: "FAT32/exFAT • Clean",
                    isEnforced: true
                )
                
                complianceDivider
                
                ComplianceRow(
                    title: "CRLF Relative POSIX Playlists",
                    detail: "M3U8 playlists formatted with \\r\\n line endings inside /MUSIC/",
                    badge: "M3U8 • CRLF",
                    isEnforced: true
                )
                
                complianceDivider
                
                ComplianceRow(
                    title: "macOS Shadow File Purging",
                    detail: "dot_clean -m automatically merges AppleDouble forks and removes ._* / .DS_Store",
                    badge: "dot_clean • No ._*",
                    isEnforced: true
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlass(cornerRadius: 16, borderOpacity: 0.38)
        }
    }
    
    private var complianceDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.02), location: 0.0),
                        .init(color: .white.opacity(0.08), location: 0.2),
                        .init(color: .white.opacity(0.08), location: 0.8),
                        .init(color: .white.opacity(0.02), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.75)
            .padding(.horizontal, 6)
    }
    
    private func aboutLiquidButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(WalkmanTheme.silverLight)
                Text("About & Supported Devices")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 4.5)
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .capsule, cornerRadius: 16))
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS DEVICE SHOWCASE (ELEVATED PEDESTAL)
// -----------------------------------------------------------------------------
private struct LiquidGlassDeviceShowcase: View {
    let size: CGFloat
    let mountPoint: String?
    let deviceInfo: WalkmanDeviceInfo?
    
    var body: some View {
        ZStack {
            // Frosted Beveled Pedestal
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    ZStack {
                        // Ambient card background
                        WalkmanTheme.card.opacity(0.7)
                        
                        // Top specular refraction
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.18), location: 0.0),
                                .init(color: .white.opacity(0.04), location: 0.35),
                                .init(color: .clear, location: 0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.45), location: 0.0),
                                    .init(color: .white.opacity(0.15), location: 0.5),
                                    .init(color: .white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
            
            // Walkman Device Image
            WalkmanDeviceIconView(
                size: size * 0.82,
                mountPoint: mountPoint,
                deviceInfo: deviceInfo,
                hasBackground: false
            )
        }
        .frame(width: size, height: size)
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS MULTI-DEVICE SEGMENT PILL
// -----------------------------------------------------------------------------
private struct DeviceSegmentPill: View {
    let device: WalkmanDevice
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                WalkmanDeviceIconView(
                    size: 30,
                    mountPoint: device.primaryMountPoint,
                    deviceInfo: device.deviceInfo,
                    hasBackground: false
                )
                .frame(width: 26, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.specificModel)
                            .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? .white : WalkmanTheme.silverLight)

                        if isSelected {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(WalkmanTheme.hiResGold)
                                    .frame(width: 4, height: 4)
                                Text("ACTIVE")
                                    .font(.system(size: 7.5, weight: .black))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(WalkmanTheme.hiResGold.opacity(0.18))
                            .foregroundStyle(WalkmanTheme.hiResGold)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(WalkmanTheme.hiResGold.opacity(0.4), lineWidth: 0.75)
                            )
                        }
                    }

                    let freeGb = Double(device.freeBytes) / (1024 * 1024 * 1024)
                    let totalGb = Double(device.totalBytes) / (1024 * 1024 * 1024)
                    Text(String(format: "%.1f GB free / %.0f GB", freeGb, totalGb))
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? WalkmanTheme.silverMuted : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .background(
                ZStack {
                    if isSelected {
                        Color.white.opacity(0.10)
                        WalkmanTheme.hiResGold.opacity(0.06)
                    } else {
                        Color.white.opacity(isHovered ? 0.08 : 0.04)
                    }
                    
                    // Specular gloss
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.14), location: 0.0),
                            .init(color: .clear, location: 0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? WalkmanTheme.hiResGold.opacity(0.55) : Color.white.opacity(isHovered ? 0.22 : 0.09),
                        lineWidth: isSelected ? 1.25 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isSelected ? 0.22 : 0.12),
                radius: isSelected ? 4 : 2,
                x: 0,
                y: 1
            )
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// -----------------------------------------------------------------------------
// LIQUID STAT CHIP (MICRO-CAPSULE)
// -----------------------------------------------------------------------------
private struct LiquidStatChip: View {
    let title: String
    let icon: String
    let color: Color
    var isGold: Bool = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isGold ? WalkmanTheme.hiResGoldLight : .white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            ZStack {
                Color.white.opacity(isHovered ? 0.10 : 0.05)
                if isGold {
                    WalkmanTheme.hiResGold.opacity(0.08)
                }
                
                // Specular top highlight
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.15), location: 0),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isGold ? WalkmanTheme.hiResGold.opacity(0.35) : Color.white.opacity(isHovered ? 0.25 : 0.12),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS STORAGE DRIVE CARD
// -----------------------------------------------------------------------------
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
    
    private var isCriticallyFull: Bool {
        percentUsed > 95
    }
    
    var body: some View {
        Button(action: {
            onSelect?()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Header Row
                HStack(alignment: .center, spacing: 10) {
                    // Frosted Medallion Icon
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(isSelected ? 0.45 : 0.2), .white.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                        
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            if isSelected {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(red: 160/255, green: 220/255, blue: 255/255))
                                        .frame(width: 5, height: 5)
                                    Text("Selected")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(Color(red: 235/255, green: 245/255, blue: 255/255))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.16))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 0.8)
                                )
                            }
                        }
                        
                        Text(subtitle)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Liquid Percentage Badge
                    HStack(spacing: 3) {
                        if isCriticallyFull {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.orange)
                        }
                        Text(String(format: "%.1f%%", percentUsed))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(isCriticallyFull ? Color.orange : (isSelected ? .white : WalkmanTheme.silverLight))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        ZStack {
                            Color.white.opacity(0.08)
                            if isCriticallyFull {
                                Color.orange.opacity(0.12)
                            }
                            
                            // Top reflection
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.2), location: 0),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 5)
                                Spacer(minLength: 0)
                            }
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                isCriticallyFull ? Color.orange.opacity(0.4) : Color.white.opacity(0.15),
                                lineWidth: 0.8
                            )
                    )
                }
                
                // Physical Liquid Glass Tube Progress Bar
                GeometryReader { geo in
                    let fillWidth = max(6, geo.size.width * CGFloat(min(1.0, percentUsed / 100.0)))
                    
                    ZStack(alignment: .leading) {
                        // Glass Trench (Outer Channel)
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 8)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                        
                        // Liquid Fluid Fill
                        ZStack(alignment: .topLeading) {
                            // Fluid Base Gradient
                            Capsule()
                                .fill(
                                    isCriticallyFull
                                        ? LinearGradient(colors: [Color(red: 255/255, green: 145/255, blue: 60/255), Color(red: 235/255, green: 90/255, blue: 40/255)], startPoint: .leading, endPoint: .trailing)
                                        : (isSelected ? WalkmanTheme.silverGradient : WalkmanTheme.storageGradient)
                                )
                                .frame(width: fillWidth, height: 8)
                            
                            // Specular Light Tube Sheen (glossy top highlight beam)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.65), location: 0.0),
                                            .init(color: .white.opacity(0.15), location: 0.45),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: fillWidth, height: 3.5)
                        }
                        .shadow(
                            color: Color.black.opacity(0.2),
                            radius: 2,
                            x: 0,
                            y: 1
                        )
                    }
                }
                .frame(height: 8)
                
                // Numbers Footer
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 4, height: 4)
                        Text("\(formatBytes(usedBytes)) Used")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    Text("\(formatBytes(freeBytes)) Available")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.04) : Color.clear)
            )
            .liquidGlass(
                cornerRadius: 15,
                borderOpacity: isSelected ? 0.85 : (isHovered ? 0.5 : 0.35),
                isSelected: isSelected,
                isHovered: isHovered
            )
            .scaleEffect(isHovered && onSelect != nil ? 1.012 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .onHover { isHovered = $0 }
    }
}

// -----------------------------------------------------------------------------
// LIQUID GLASS ACTION CARD (INTERACTIVE WORKFLOW TILE)
// -----------------------------------------------------------------------------
private struct ActionCard: View {
    let title: String
    let description: String
    let icon: String
    var iconTint: Color = WalkmanTheme.silverLight
    var isHorizontalRow: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            if isHorizontalRow {
                HStack(spacing: 12) {
                    // Liquid Glass Icon Medallion
                    iconMedallion
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(description)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 6)
                    
                    // Translucent Circular Forward Button
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isHovered ? 0.15 : 0.06))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 0.75)
                            )
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.35))
                            .offset(x: isHovered ? 1.5 : 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 14, borderOpacity: isHovered ? 0.6 : 0.32, isHovered: isHovered)
                .scaleEffect(isHovered ? 1.01 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        iconMedallion
                        Spacer()
                        
                        // Translucent Circular Forward Button
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(isHovered ? 0.15 : 0.06))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 0.75)
                                )
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.35))
                                .offset(x: isHovered ? 1.5 : 0)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        Text(description)
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .liquidGlass(cornerRadius: 15, borderOpacity: isHovered ? 0.6 : 0.32, isHovered: isHovered)
                .scaleEffect(isHovered ? 1.015 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var iconMedallion: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconTint.opacity(isHovered ? 0.22 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [iconTint.opacity(0.45), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.12), radius: 3, x: 0, y: 1)
            
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconTint)
        }
    }
}

// -----------------------------------------------------------------------------
// SONY HARDWARE COMPLIANCE ROW (INSPECTOR STYLE)
// -----------------------------------------------------------------------------
private struct ComplianceRow: View {
    let title: String
    let detail: String
    var badge: String? = nil
    let isEnforced: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Verified Indicator (Clean tactile badge - No Glow)
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 22, height: 22)
                
                Image(systemName: isEnforced ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEnforced ? Color.green : Color.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 6)
            
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    )
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.035) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
