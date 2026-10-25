import SwiftUI
import AppKit

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
        case .albums: return "square.stack.fill"
        case .artists: return "music.mic"
        case .hiRes: return "waveform.badge.magnifyingglass"
        case .playlists: return "list.bullet.rectangle.portrait.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .transfer: return "arrow.up.arrow.down.circle.fill"
        case .backupRestore: return "arrow.triangle.2.circlepath.circle.fill"
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

    @ViewBuilder
    private func sidebarSectionHeader(_ title: String, isFirst: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.82))
            .textCase(nil)
            .padding(.top, isFirst ? 4 : 22)
            .padding(.bottom, 6)
            .padding(.leading, 4)
    }

    public var body: some View {
        List {
            // -----------------------------------------------------------------
            // DEVICE Section
            // -----------------------------------------------------------------
            if devices.count > 1 {
                Section(header: sidebarSectionHeader("Connected Devices (\(devices.count))", isFirst: true)) {
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
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

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
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))
                        }
                    }
                }
            } else {
                Section(header: sidebarSectionHeader("Device", isFirst: true)) {
                    DeviceConnectedSidebarRow(
                        selectedTab: $selectedTab,
                        deviceInfo: deviceInfo,
                        mountPoint: activeDrive?.mountPoint ?? drives.first?.mountPoint
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                    ForEach(drives) { drive in
                        let isCurrent = activeDrive?.mountPoint == drive.mountPoint
                        DriveSidebarRow(
                            drive: drive,
                            isCurrent: isCurrent,
                            isIndented: false,
                            onSelect: { onSelectDrive?(drive) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))
                    }
                }
            }

            // -----------------------------------------------------------------
            // LIBRARY Section
            // -----------------------------------------------------------------
            Section(header: sidebarSectionHeader("Library")) {
                SidebarRow(
                    tab: .library,
                    selectedTab: $selectedTab,
                    title: "All Songs",
                    icon: "music.note.list",
                    badge: trackCount > 0 ? "\(trackCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .recentlyAdded,
                    selectedTab: $selectedTab,
                    title: "Recently Added",
                    icon: "clock.arrow.circlepath",
                    badge: recentlyAddedCount > 0 ? "\(recentlyAddedCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .albums,
                    selectedTab: $selectedTab,
                    title: "Albums",
                    icon: "square.stack.fill",
                    badge: albumCount > 0 ? "\(albumCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .artists,
                    selectedTab: $selectedTab,
                    title: "Artists",
                    icon: "music.mic",
                    badge: artistCount > 0 ? "\(artistCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .hiRes,
                    selectedTab: $selectedTab,
                    title: "Hi-Res Audio",
                    icon: "waveform.badge.magnifyingglass",
                    badge: hiResCount > 0 ? "\(hiResCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .playlists,
                    selectedTab: $selectedTab,
                    title: "Playlist",
                    icon: "list.bullet.rectangle.portrait.fill",
                    badge: nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))
            }

            // -----------------------------------------------------------------
            // TOOLS Section
            // -----------------------------------------------------------------
            Section(header: sidebarSectionHeader("Tools")) {
                SidebarRow(
                    tab: .duplicates,
                    selectedTab: $selectedTab,
                    title: "Duplicates",
                    icon: "doc.on.doc.fill",
                    badge: duplicateCount > 0 ? "\(duplicateCount.formatted())" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .transfer,
                    selectedTab: $selectedTab,
                    title: "Transfer & Convert",
                    icon: "arrow.up.arrow.down.circle.fill",
                    badge: queueCount > 0 ? "\(queueCount)" : nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))

                SidebarRow(
                    tab: .backupRestore,
                    selectedTab: $selectedTab,
                    title: "Backup & Restore",
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    badge: nil
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3.5, leading: 10, bottom: 3.5, trailing: 10))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(WalkmanTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if let onAbout = onOpenAbout {
                AboutSidebarButton(action: onAbout)
            }
        }
    }
}

// -----------------------------------------------------------------------------
// ABOUT SIDEBAR BUTTON (LIQUID GLASS CAPSULE)
// -----------------------------------------------------------------------------
private struct AboutSidebarButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isHovered ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                    .frame(width: 22, alignment: .center)

                Text("About Walkman Studio")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovered ? .white : WalkmanTheme.silverLight)

                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(
                ZStack {
                    Color.white.opacity(isHovered ? 0.08 : 0.03)
                    if isHovered {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .clear, location: 1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 6)
                            Spacer(minLength: 0)
                        }
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        Color.white.opacity(isHovered ? 0.28 : 0.08),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: isHovered ? Color.black.opacity(0.2) : .clear,
                radius: 4,
                x: 0,
                y: 1.5
            )
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// -----------------------------------------------------------------------------
// MULTI-DEVICE SIDEBAR CARD
// -----------------------------------------------------------------------------
private struct DeviceMultiSidebarCard: View {
    let device: WalkmanDevice
    let isDeviceActive: Bool
    let isOverviewSelected: Bool
    let onSelectDevice: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelectDevice) {
            HStack(spacing: 11) {
                // Walkman Device Icon (Unboxed)
                WalkmanDeviceIconView(
                    size: 28,
                    mountPoint: device.primaryMountPoint,
                    deviceInfo: device.deviceInfo,
                    hasBackground: false
                )
                .frame(width: 26, height: 28)
                .shadow(color: Color.black.opacity(0.35), radius: 2.5, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(device.specificModel)
                            .font(.system(size: 12.5, weight: isDeviceActive ? .bold : .medium))
                            .foregroundStyle(isDeviceActive ? .white : WalkmanTheme.silverLight)
                            .lineLimit(1)

                        if isDeviceActive {
                            Text("ACTIVE")
                                .font(.system(size: 7.5, weight: .black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(WalkmanTheme.hiResGold.opacity(0.2))
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
                        .font(.system(size: 10.5, design: .monospaced))
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
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(
                ZStack {
                    if isOverviewSelected {
                        Color.white.opacity(0.12)
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.14), location: 0.0),
                                .init(color: .clear, location: 0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else if isDeviceActive {
                        Color.white.opacity(0.06)
                    } else if isHovered {
                        Color.white.opacity(0.04)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isDeviceActive ? WalkmanTheme.hiResGold.opacity(0.4) : Color.white.opacity(isHovered ? 0.15 : 0.05),
                        lineWidth: isDeviceActive ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isDeviceActive ? 0.2 : 0),
                radius: 3,
                x: 0,
                y: 1
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
        .help("Select \(device.displayName) as active Walkman")
    }
}

// -----------------------------------------------------------------------------
// DRIVE SIDEBAR ROW (LIQUID GLASS GAUGED)
// -----------------------------------------------------------------------------
private struct DriveSidebarRow: View {
    let drive: WalkmanDrive
    let isCurrent: Bool
    var isIndented: Bool = false
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                // Miniature Frosted Medallion for Drive
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(Color.white.opacity(isCurrent ? 0.35 : 0.08), lineWidth: 0.75)
                        )
                    
                    Image(systemName: drive.type == .internal ? "internaldrive.fill" : "sdcard.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isCurrent ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .white : WalkmanTheme.silverLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)

                    let freeGb = Double(drive.freeBytes) / (1024 * 1024 * 1024)
                    Text(String(format: "%.1f GB free", freeGb))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrent {
                    // Active Beacon Dot (Clean tactile dot - No Glow)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5.5, height: 5.5)
                        .padding(.trailing, 6)
                }
            }
            .padding(.vertical, 7)
            .padding(.leading, isIndented ? 16 : 9)
            .padding(.trailing, 9)
            .background(
                ZStack {
                    if isCurrent {
                        Color.white.opacity(0.08)
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.09), location: 0.0),
                                .init(color: .clear, location: 0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else if isHovered {
                        Color.white.opacity(0.04)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isCurrent
                            ? LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.12 : 0.0), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
        .help("Select \(drive.name) as active library drive")
    }
}

// -----------------------------------------------------------------------------
// DEVICE CONNECTED SIDEBAR ROW (LIQUID GLASS OVERVIEW TILE)
// -----------------------------------------------------------------------------
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
            HStack(spacing: 12) {
                // Walkman Device Icon (Unboxed, native HIG presentation)
                WalkmanDeviceIconView(
                    size: 32,
                    mountPoint: mountPoint,
                    deviceInfo: deviceInfo,
                    hasBackground: false
                )
                .frame(width: 28, height: 32)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)
                
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(deviceInfo?.specificModel ?? deviceInfo?.displayName ?? "Sony Walkman")
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? .white : WalkmanTheme.silverLight)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                    
                    HStack(spacing: 4.5) {
                        Image(systemName: "hifispeaker.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(isSelected ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)
                        Text("Device Overview")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight : .secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 4)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                ZStack {
                    if isSelected {
                        Color.white.opacity(0.12)
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.14), location: 0.0),
                                .init(color: .white.opacity(0.04), location: 0.4),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else if isHovered {
                        Color.white.opacity(0.05)
                    } else {
                        Color.white.opacity(0.02)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.48), location: 0.0),
                                    .init(color: Color.white.opacity(0.20), location: 0.4),
                                    .init(color: Color.white.opacity(0.06), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.16 : 0.06), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.25) : Color.black.opacity(0.08),
                radius: isSelected ? 5 : 2,
                x: 0,
                y: isSelected ? 2 : 1
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
        .help("View Sony Walkman hardware specs, storage breakdown, and system status")
    }
}

// -----------------------------------------------------------------------------
// SIDEBAR ROW (LIQUID GLASS SELECTION)
// -----------------------------------------------------------------------------
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
            HStack(spacing: 9) {
                // SF Symbol
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        tab == .hiRes
                            ? (isSelected ? WalkmanTheme.hiResGoldLight : WalkmanTheme.hiResGold)
                            : (isSelected ? WalkmanTheme.silverLight : (isHovered ? .white : WalkmanTheme.silverMuted))
                    )
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? .white : WalkmanTheme.silverLight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if let b = badge {
                    if tab == .hiRes {
                        // Liquid Glass Gold Badge
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .font(.system(size: 7.5, weight: .black))
                            Text(b)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            ZStack {
                                WalkmanTheme.hiResGoldGradient
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [.init(color: .white.opacity(0.45), location: 0), .init(color: .clear, location: 1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 5)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        .foregroundStyle(Color(red: 22/255, green: 20/255, blue: 18/255))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(WalkmanTheme.hiResGoldLight.opacity(0.8), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                    } else {
                        // Liquid Glass Counter Pill
                        Text(b)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                ZStack {
                                    Color.white.opacity(isSelected ? 0.18 : 0.08)
                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 1)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 5)
                                        Spacer(minLength: 0)
                                    }
                                }
                            )
                            .foregroundStyle(isSelected ? .white : WalkmanTheme.silverLight)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(isSelected ? 0.28 : 0.10), lineWidth: 0.75)
                            )
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(
                ZStack {
                    if isSelected {
                        // Liquid Glass Selected Plate
                        Color.white.opacity(0.10)
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.12), location: 0.0),
                                .init(color: .white.opacity(0.03), location: 0.4),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else if isHovered {
                        Color.white.opacity(0.045)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.40), location: 0.0),
                                    .init(color: Color.white.opacity(0.15), location: 0.5),
                                    .init(color: Color.white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.12 : 0.0), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.22) : .clear,
                radius: 4,
                x: 0,
                y: 1.5
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovered { isHovered = false; NSCursor.pop() }
        }
    }
}
