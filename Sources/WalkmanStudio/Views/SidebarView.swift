import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Hashable {
    case overview = "Device Overview"
    case library = "All Songs"
    case recentlyAdded = "Recently Added"
    case albums = "Albums"
    case artists = "Artists"
    case hiRes = "Hi-Res Audio"
    case duplicates = "Duplicates"
    case transfer = "Transfer & Convert"
    case playlists = "Playlists (.M3U8)"
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
        case .duplicates: return "doc.on.doc"
        case .transfer: return "arrow.up.arrow.down.circle"
        case .playlists: return "list.bullet.rectangle"
        case .backupRestore: return "arrow.triangle.2.circlepath.circle"
        }
    }
}

public struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    let drives: [WalkmanDrive]
    let trackCount: Int
    var recentlyAddedCount: Int = 0
    var albumCount: Int = 0
    var artistCount: Int = 0
    var hiResCount: Int = 0
    var duplicateCount: Int = 0
    let queueCount: Int
    var deviceInfo: WalkmanDeviceInfo? = nil
    var activeDrive: WalkmanDrive? = nil
    var onSelectDrive: ((WalkmanDrive) -> Void)? = nil
    var onOpenAbout: (() -> Void)? = nil

    public var body: some View {
        List {
            // DEVICE Section
            Section("DEVICE") {
                SidebarRow(
                    tab: .overview,
                    selectedTab: $selectedTab,
                    title: "\(deviceInfo?.specificModel ?? "Device") Overview",
                    icon: "hifispeaker.fill",
                    badge: nil
                )
                
                ForEach(drives) { drive in
                    let isCurrent = activeDrive?.mountPoint == drive.mountPoint
                    DriveSidebarRow(
                        drive: drive,
                        isCurrent: isCurrent,
                        onSelect: { onSelectDrive?(drive) }
                    )
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
                    tab: .duplicates,
                    selectedTab: $selectedTab,
                    title: "Duplicates",
                    icon: "doc.on.doc",
                    badge: duplicateCount > 0 ? "\(duplicateCount.formatted())" : nil
                )
            }

            // TOOLS Section
            Section("TOOLS") {
                SidebarRow(
                    tab: .transfer,
                    selectedTab: $selectedTab,
                    title: "Transfer & Convert",
                    icon: "arrow.up.arrow.down.circle",
                    badge: queueCount > 0 ? "\(queueCount)" : nil
                )

                SidebarRow(
                    tab: .playlists,
                    selectedTab: $selectedTab,
                    title: "Playlists (.M3U8)",
                    icon: "list.bullet.rectangle",
                    badge: nil
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

private struct DriveSidebarRow: View {
    let drive: WalkmanDrive
    let isCurrent: Bool
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
                        .fill(WalkmanTheme.silver)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.vertical, 4.5)
            .padding(.horizontal, 6)
            .background(isCurrent ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Select \(drive.name) as active library drive")
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
