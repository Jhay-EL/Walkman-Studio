import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Hashable {
    case overview = "Device Overview"
    case library = "All Songs"
    case recentlyAdded = "Recently Added"
    case albums = "Albums"
    case artists = "Artists"
    case hiRes = "Hi-Res Audio"
    case playlists = "Playlist"
    case duplicates = "Duplicates"
    case transfer = "Transfer & Convert"
    case backupRestore = "Backup & Restore"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .overview: return "hifispeaker.fill"
        case .library: return "music.note.list"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .hiRes: return "waveform.badge.magnifyingglass"
        case .playlists: return "list.bullet.rectangle"
        case .duplicates: return "doc.on.doc"
        case .transfer: return "arrow.up.arrow.down.circle"
        case .backupRestore: return "arrow.triangle.2.circlepath.circle"
        }
    }
}

public struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    var devices: [WalkmanDevice] = []
    let drives: [WalkmanDrive]
    var activeDevice: WalkmanDevice? = nil
    let trackCount: Int
    var recentlyAddedCount: Int = 0
    var albumCount: Int = 0
    var artistCount: Int = 0
    var hiResCount: Int = 0
    var duplicateCount: Int = 0
    let queueCount: Int
    var deviceInfo: WalkmanDeviceInfo? = nil
    var activeDrive: WalkmanDrive? = nil
    var onSelectDevice: ((WalkmanDevice) -> Void)? = nil
    var onSelectDrive: ((WalkmanDrive) -> Void)? = nil
    var onOpenAbout: (() -> Void)? = nil

    public var body: some View {
        List {
            // DEVICE Section
            if devices.count > 1 {
                Section("CONNECTED DEVICES (\(devices.count))") {
                    ForEach(devices) { device in
                        let isDeviceActive = (activeDevice?.id == device.id)
                        let isOverviewSelected = (selectedTab == .overview && isDeviceActive)

                        DeviceMultiSidebarCard(
                            device: device,
                            isDeviceActive: isDeviceActive,
                            isOverviewSelected: isOverviewSelected,
                            onSelectDevice: {
                                onSelectDevice?(device)
                            }
                        )

                        ForEach(device.drives) { drive in
                            let isCurrent = activeDrive?.mountPoint == drive.mountPoint
                            DriveSidebarRow(
                                drive: drive,
                                isCurrent: isCurrent,
                                isIndented: true,
                                onSelect: {
                                    if !isDeviceActive {
                                        onSelectDevice?(device)
                                    }
                                    onSelectDrive?(drive)
                                }
                            )
                        }
                    }
                }
            } else {
                Section("DEVICE") {
                    DeviceConnectedSidebarRow(
                        selectedTab: $selectedTab,
                        deviceInfo: deviceInfo,
                        mountPoint: activeDrive?.mountPoint ?? drives.first?.mountPoint
                    )

                    ForEach(drives) { drive in
                        let isCurrent = activeDrive?.mountPoint == drive.mountPoint
                        DriveSidebarRow(
                            drive: drive,
                            isCurrent: isCurrent,
                            isIndented: false,
                            onSelect: { onSelectDrive?(drive) }
                        )
                    }
                }
            }

            // LIBRARY Section
            Section("LIBRARY") {
                SidebarRow(
                    tab: .library,
                    selectedTab: $selectedTab,
                    title: "All Songs",
                    icon: "music.note.list",
                    badge: trackCount > 0 ? "\(trackCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .recentlyAdded,
                    selectedTab: $selectedTab,
                    title: "Recently Added",
                    icon: "clock.arrow.circlepath",
                    badge: recentlyAddedCount > 0 ? "\(recentlyAddedCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .albums,
                    selectedTab: $selectedTab,
                    title: "Albums",
                    icon: "square.stack",
                    badge: albumCount > 0 ? "\(albumCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .artists,
                    selectedTab: $selectedTab,
                    title: "Artists",
                    icon: "music.mic",
                    badge: artistCount > 0 ? "\(artistCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .hiRes,
                    selectedTab: $selectedTab,
                    title: "Hi-Res Audio",
                    icon: "waveform.badge.magnifyingglass",
                    badge: hiResCount > 0 ? "\(hiResCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .playlists,
                    selectedTab: $selectedTab,
                    title: "Playlist",
                    icon: "list.bullet.rectangle",
                    badge: nil
                )
            }

            // TOOLS Section
            Section("TOOLS") {
                SidebarRow(
                    tab: .duplicates,
                    selectedTab: $selectedTab,
                    title: "Duplicates",
                    icon: "doc.on.doc",
                    badge: duplicateCount > 0 ? "\(duplicateCount.formatted())" : nil
                )

                SidebarRow(
                    tab: .transfer,
                    selectedTab: $selectedTab,
                    title: "Transfer & Convert",
                    icon: "arrow.up.arrow.down.circle",
                    badge: queueCount > 0 ? "\(queueCount)" : nil
                )

                SidebarRow(
                    tab: .backupRestore,
                    selectedTab: $selectedTab,
                    title: "Backup & Restore",
                    icon: "arrow.triangle.2.circlepath.circle",
                    badge: nil
                )
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let onAbout = onOpenAbout {
                AboutSidebarButton(action: onAbout)
            }
        }
    }
}

private struct AboutSidebarButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? WalkmanTheme.silverLight : .secondary)
                    .frame(width: 18)

                Text("About Walkman Studio")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(isHovered ? .white : WalkmanTheme.silverMuted)

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct DeviceMultiSidebarCard: View {
    let device: WalkmanDevice
    let isDeviceActive: Bool
    let isOverviewSelected: Bool
    let onSelectDevice: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelectDevice) {
            HStack(spacing: 9) {
                WalkmanDeviceIconView(
                    size: 30,
                    mountPoint: device.primaryMountPoint,
                    deviceInfo: device.deviceInfo,
                    hasBackground: false
                )
                .frame(width: 26, height: 30)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 5) {
                        Text(device.specificModel)
                            .font(.system(size: 12.5, weight: isDeviceActive ? .bold : .medium))
                            .foregroundStyle(isDeviceActive ? .white : WalkmanTheme.silverLight)
                            .lineLimit(1)

                        if isDeviceActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(WalkmanTheme.hiResGold.opacity(0.2))
                                .foregroundStyle(WalkmanTheme.hiResGold)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }

                    let freeGb = Double(device.freeBytes) / (1024 * 1024 * 1024)
                    let totalGb = Double(device.totalBytes) / (1024 * 1024 * 1024)
                    Text(String(format: "%.1f GB free / %.0f GB", freeGb, totalGb))
                        .font(.system(size: 10.5))
                        .foregroundStyle(isDeviceActive ? WalkmanTheme.silverMuted : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isOverviewSelected {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                isOverviewSelected
                    ? Color.white.opacity(0.12)
                    : (isDeviceActive
                        ? Color.white.opacity(0.06)
                        : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isDeviceActive ? WalkmanTheme.hiResGold.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Select \(device.displayName) as active Walkman")
    }
}

private struct DriveSidebarRow: View {
    let drive: WalkmanDrive
    let isCurrent: Bool
    var isIndented: Bool = false
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: drive.type == .internal ? "internaldrive" : "sdcard")
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(drive.name)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .lineLimit(1)

                    let freeGb = Double(drive.freeBytes) / (1024 * 1024 * 1024)
                    Text(String(format: "%.1f GB free", freeGb))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrent {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5.5, height: 5.5)
                        .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 4.5)
            .padding(.leading, isIndented ? 14 : 6)
            .padding(.trailing, 6)
            .background(isCurrent ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Select \(drive.name) as active library drive")
    }
}

private struct DeviceConnectedSidebarRow: View {
    @Binding var selectedTab: NavigationTab
    let deviceInfo: WalkmanDeviceInfo?
    let mountPoint: String?
    @State private var isHovered = false

    private var isSelected: Bool {
        selectedTab == .overview
    }

    var body: some View {
        Button(action: { selectedTab = .overview }) {
            HStack(spacing: 10) {
                WalkmanDeviceIconView(
                    size: 34,
                    mountPoint: mountPoint,
                    deviceInfo: deviceInfo,
                    hasBackground: false
                )
                .frame(width: 32, height: 34)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceInfo?.specificModel ?? deviceInfo?.displayName ?? "Sony Walkman")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                    
                    Text("Device Overview")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? WalkmanTheme.silverLight : .secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.white.opacity(0.10) : (isHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("View Sony Walkman hardware specs, storage breakdown, and system status")
    }
}

private struct SidebarRow: View {
    let tab: NavigationTab
    @Binding var selectedTab: NavigationTab
    let title: String
    let icon: String
    let badge: String?
    @State private var isHovered = false

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(
                        tab == .hiRes
                            ? (isSelected ? WalkmanTheme.hiResGoldLight : WalkmanTheme.hiResGold)
                            : (isSelected ? WalkmanTheme.silverLight : (isHovered ? .white : .secondary))
                    )
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? .white : .primary))

                Spacer()

                if let b = badge {
                    if tab == .hiRes {
                        Text(b)
                            .font(WalkmanFont.pillCounter)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                isSelected
                                    ? WalkmanTheme.hiResGold.opacity(0.28)
                                    : WalkmanTheme.hiResGold.opacity(0.14)
                            )
                            .foregroundStyle(WalkmanTheme.hiResGoldLight)
                            .overlay(
                                Capsule()
                                    .strokeBorder(WalkmanTheme.hiResGold.opacity(isSelected ? 0.7 : 0.35), lineWidth: 0.8)
                            )
                            .clipShape(Capsule())
                    } else {
                        Text(b)
                            .font(WalkmanFont.pillCounter)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight : .secondary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 4.5)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
