import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Hashable {
    case overview = "NW-A55L Overview"
    case library = "All Songs"
    case albums = "Albums"
    case artists = "Artists"
    case hiRes = "Hi-Res Audio"
    case transfer = "Transfer & Convert"
    case playlists = "Playlists (.M3U8)"
    case dsp = "Walkman One DSP"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .overview: return "hifispeaker.fill"
        case .library: return "music.note.list"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .hiRes: return "waveform.badge.magnifyingglass"
        case .transfer: return "arrow.up.arrow.down.circle"
        case .playlists: return "list.bullet.rectangle"
        case .dsp: return "slider.vertical.3"
        }
    }
}

public struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    let drives: [WalkmanDrive]
    let trackCount: Int
    let queueCount: Int

    public var body: some View {
        List {
            // DEVICE Section
            Section("DEVICE") {
                SidebarRow(
                    tab: .overview,
                    selectedTab: $selectedTab,
                    title: "NW-A55L Overview",
                    icon: "hifispeaker.fill",
                    badge: nil
                )
                
                ForEach(drives) { drive in
                    HStack(spacing: 8) {
                        Image(systemName: drive.type == .internal ? "internaldrive" : "sdcard")
                            .font(.system(size: 12))
                            .foregroundStyle(WalkmanTheme.gold)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(drive.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            let freeGb = Double(drive.freeBytes) / (1024 * 1024 * 1024)
                            Text(String(format: "%.1f GB free", freeGb))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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
                    tab: .albums,
                    selectedTab: $selectedTab,
                    title: "Albums",
                    icon: "square.stack",
                    badge: nil
                )

                SidebarRow(
                    tab: .artists,
                    selectedTab: $selectedTab,
                    title: "Artists",
                    icon: "music.mic",
                    badge: nil
                )

                SidebarRow(
                    tab: .hiRes,
                    selectedTab: $selectedTab,
                    title: "Hi-Res Audio",
                    icon: "waveform.badge.magnifyingglass",
                    badge: nil
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
                    tab: .dsp,
                    selectedTab: $selectedTab,
                    title: "Walkman One DSP",
                    icon: "slider.vertical.3",
                    badge: nil
                )
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // Minimal Hardware compliance badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("NW-A55L Compliant (Baseline RGB / ID3v2.3)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct SidebarRow: View {
    let tab: NavigationTab
    @Binding var selectedTab: NavigationTab
    let title: String
    let icon: String
    let badge: String?

    var body: some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selectedTab == tab ? WalkmanTheme.gold : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .white : .primary)

                Spacer()

                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selectedTab == tab ? WalkmanTheme.gold.opacity(0.25) : Color.white.opacity(0.08))
                        .foregroundStyle(selectedTab == tab ? WalkmanTheme.gold : .secondary)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
