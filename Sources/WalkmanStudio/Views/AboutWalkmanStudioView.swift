import SwiftUI
import AppKit

// MARK: - About Tabs
public enum AboutTab: Int, CaseIterable, Identifiable {
    case hardware = 0
    case supportedDAPs = 1
    case engineRules = 2
    case developerSupport = 3

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .hardware: return "Hardware"
        case .supportedDAPs: return "Supported DAPs"
        case .engineRules: return "Engine Rules"
        case .developerSupport: return "Developer & Support"
        }
    }

    var icon: String {
        switch self {
        case .hardware: return "cpu"
        case .supportedDAPs: return "music.note.list"
        case .engineRules: return "gearshape.2"
        case .developerSupport: return "person.crop.circle"
        }
    }
}

public struct AboutWalkmanStudioView: View {
    let currentDeviceInfo: WalkmanDeviceInfo?
    let onDismiss: () -> Void
    
    @State private var selectedTab: AboutTab = .hardware
    
    public init(currentDeviceInfo: WalkmanDeviceInfo?, onDismiss: @escaping () -> Void) {
        self.currentDeviceInfo = currentDeviceInfo
        self.onDismiss = onDismiss
    }
    
    private var appIcon: NSImage? {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: iconURL) {
            return img
        }
        return NSImage(contentsOfFile: "assets/icon.png")
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onDismiss)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)
            
            // Hero App Header (Apple macOS 27 Liquid Glass Style)
            VStack(spacing: 7) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.85)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(WalkmanTheme.silverGradient)
                            .frame(width: 74, height: 74)
                        Text("W.")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                
                Text("Walkman Studio")
                    .font(WalkmanFont.title1)
                    .foregroundStyle(.primary)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0") • Universal (Apple Silicon & Intel)")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Non-Android Sony OS / Linux Architecture")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(WalkmanTheme.silver)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
            }
            .padding(.top, -12)
            .padding(.bottom, 16)
            
            // Liquid Glass Segmented Pill Bar
            AboutSegmentedBar(selectedTab: $selectedTab)
                .padding(.bottom, 16)
            
            // Tab Content
            Group {
                switch selectedTab {
                case .hardware:
                    hardwareTabView
                case .supportedDAPs:
                    supportedModelsTabView
                case .engineRules:
                    engineRulesTabView
                case .developerSupport:
                    developerTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 8)
            
            // Bottom Action Footer
            HStack(alignment: .center) {
                Text("Sony & Walkman are registered trademarks of Sony Group Corporation.")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                
                Spacer()
                
                PrimaryDoneButton(action: onDismiss)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        // Studio Window Dimensions (Optimized macOS Modal Layout)
        .frame(width: 780, height: 650)
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
    
    // MARK: - Tab 0: Hardware View
    private var hardwareTabView: some View {
        VStack(spacing: 14) {
            if let dev = currentDeviceInfo {
                HStack(spacing: 14) {
                    WalkmanDeviceIconView(size: 48, deviceInfo: dev)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(dev.displayName)
                                .font(WalkmanFont.title3)
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 5) {
                                Circle().fill(Color.green).frame(width: 5.5, height: 5.5)
                                Text("Verified")
                                    .font(WalkmanFont.badge.weight(.bold))
                                    .foregroundStyle(Color.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.green.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        
                        Text("Connected via USB Mass Storage • S-Master HX DAC")
                            .font(WalkmanFont.subheadlineMedium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
                )
                
                // Specifications Grid
                VStack(spacing: 1) {
                    SpecRow(label: "Hardware Model", value: dev.modelRaw)
                    SpecRow(label: "Firmware Version", value: "v\(dev.firmwareVersion)")
                    SpecRow(label: "Screen Engine", value: "\(dev.displayResolution) (Baseline RGB)")
                    SpecRow(label: "Internal Flash", value: String(format: "%.1f GB", dev.internalCapacityGb))
                    SpecRow(label: "Audio Pipeline", value: "S-Master HX, DSEE HX, Vinyl")
                    SpecRow(label: "Tag Standard", value: "Strict ID3v2.3 (UTF-16) & Vorbis")
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
                )
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 34))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    
                    Text("No Walkman Connected")
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Connect your Sony Walkman via USB in Mass Storage mode to inspect hardware specifications.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.85)
                )
            }
        }
    }
    
    // MARK: - Tab 1: Supported Models View
    private var supportedModelsTabView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(WalkmanDeviceDetector.supportedSeriesCategories, id: \.category) { cat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cat.category.uppercased())
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                        
                        VStack(spacing: 1) {
                            ForEach(cat.models) { m in
                                HStack(spacing: 12) {
                                    WalkmanDeviceIconView(
                                        size: 32,
                                        modelName: m.modelCode,
                                        hasBackground: false
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.modelCode)
                                            .font(WalkmanFont.bodyMedium)
                                            .foregroundStyle(.primary)
                                        Text(m.description)
                                            .font(WalkmanFont.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(m.storageOptions)
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.03))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.85)
                        )
                    }
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Android Walkmans (NW-A100/A300, NW-ZX500) use MTP and are not supported.")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.85)
                )
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Tab 2: Engine Rules View
    private var engineRulesTabView: some View {
        VStack(spacing: 10) {
            RuleCard(
                icon: "photo.artframe",
                title: "Baseline RGB JPEG Artwork",
                detail: "Strips progressive passes, CMYK color spaces, and limits resolution to 800×800 to prevent display engine freezes."
            )
            RuleCard(
                icon: "tag",
                title: "Strict ID3v2.3 (UTF-16)",
                detail: "Enforces UTF-16 with BOM (encoding=1) and binary ID3v2.3 tags, avoiding ID3v2.4 database corruption."
            )
            RuleCard(
                icon: "list.bullet.rectangle",
                title: "CRLF Relative .M3U8 Playlists",
                detail: "Writes Windows-compliant CRLF (\\r\\n) line endings and relative POSIX paths directly into /MUSIC/."
            )
            RuleCard(
                icon: "sparkles",
                title: "macOS Shadow File Purge",
                detail: "Merges AppleDouble forks with dot_clean -m and removes ._* and .DS_Store ghost files before safe eject."
            )
        }
    }
    
    // MARK: - Tab 3: Developer & Support View
    private var developerTabView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                // Developer Profile Hero Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 50 / 255, green: 56 / 255, blue: 72 / 255),
                                            Color(red: 26 / 255, green: 28 / 255, blue: 38 / 255)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                )
                            
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(WalkmanTheme.silverLight)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("John Lloyd Malabanan")
                                    .font(WalkmanFont.title2)
                                    .foregroundStyle(.primary)
                                
                                Text("Creator")
                                    .font(WalkmanFont.badge)
                                    .foregroundStyle(WalkmanTheme.hiResGold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(WalkmanTheme.hiResGold.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(WalkmanTheme.hiResGold.opacity(0.30), lineWidth: 0.8)
                                    )
                            }
                            
                            Text("GitHub: @Jhay-EL • Software Engineer & Audiophile")
                                .font(WalkmanFont.subheadlineMedium)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text("Walkman Studio was designed and engineered from the ground up to solve the challenges of using modern macOS with Sony Walkman digital audio players. It automates strict ID3v2.3 tagging, Baseline RGB JPEG cover art conversion, synchronized lyrics synchronization, dual-partition routing, and AppleDouble ghost file cleanup.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
                )
                
                // Links Grid
                HStack(spacing: 12) {
                    // GitHub Profile Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                            
                            Text("GitHub Profile")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Text("Follow @Jhay-EL on GitHub to view open-source projects, releases, and development activity.")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        
                        Spacer(minLength: 4)
                        
                        TactileLinkButton(
                            title: "github.com/Jhay-EL",
                            icon: "arrow.up.forward",
                            url: "https://github.com/Jhay-EL"
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.85)
                    )
                    
                    // Walkman Studio Repo Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                            
                            Text("Project Repository")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Text("Star Walkman Studio on GitHub, report issues, contribute features, and read source documentation.")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        
                        Spacer(minLength: 4)
                        
                        TactileLinkButton(
                            title: "Jhay-EL/Walkman-Studio",
                            icon: "arrow.up.forward",
                            url: "https://github.com/Jhay-EL/Walkman-Studio"
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.85)
                    )
                }
                
                // Buy Me a Coffee Support Banner
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.18))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("Support Walkman Studio Development")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.primary)
                            
                            Text("Buy Me a Coffee")
                                .font(WalkmanFont.badge)
                                .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.30), lineWidth: 0.8)
                                )
                        }
                        
                        Text("If Walkman Studio enhances your music listening experience, consider buying a coffee to support maintenance and hardware testing.")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    TactileLinkButton(
                        title: "Support",
                        icon: "cup.and.saucer.fill",
                        url: "https://www.buymeacoffee.com/jhayel",
                        isAccent: true
                    )
                }
                .padding(12)
                .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.22), lineWidth: 0.85)
                )
                
                // Contact & Licensing Footer Info
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Contact:")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                        Button(action: {
                            openURL("mailto:jl.temporary@outlook.it")
                        }) {
                            Text("jl.temporary@outlook.it")
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .onHover { h in
                            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("License: MIT (Free & Open Source)")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Liquid Glass Segmented Pill Bar
private struct AboutSegmentedBar: View {
    @Binding var selectedTab: AboutTab
    @Namespace private var tabNamespace
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(AboutTab.allCases) { tab in
                AboutTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabNamespace,
                    action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.85)
        )
    }
}

private struct AboutTabButton: View {
    let tab: AboutTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.68)))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "activeAboutTab", in: namespace)
                        
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 6)
                            Spacer(minLength: 0)
                        }
                        .clipShape(Capsule())
                        .matchedGeometryEffect(id: "activeAboutTabSheen", in: namespace)
                    } else if isHovered {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    }
                }
            )
            .overlay(
                Group {
                    if isSelected {
                        Capsule()
                            .stroke(Color.white.opacity(0.32), lineWidth: 0.85)
                            .matchedGeometryEffect(id: "activeAboutTabBorder", in: namespace)
                    }
                }
            )
            .shadow(color: isSelected ? Color.black.opacity(0.25) : Color.clear, radius: 3, y: 1)
            .scaleEffect(isHovered && !isSelected ? 1.025 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Tactile Link Button
private struct TactileLinkButton: View {
    let title: String
    let icon: String
    let url: String
    var isAccent: Bool = false
    var accentColor: Color = Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255)
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        }) {
            HStack(spacing: 6.5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(WalkmanFont.calloutBold)
            }
            .foregroundStyle(isAccent ? (isHovered ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : accentColor) : (isHovered ? Color.white : WalkmanTheme.silverLight))
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                ZStack {
                    if isAccent {
                        if isHovered {
                            accentColor
                        } else {
                            accentColor.opacity(0.14)
                        }
                    } else {
                        Color.white.opacity(isHovered ? 0.14 : 0.07)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isAccent
                            ? accentColor.opacity(isHovered ? 0.70 : 0.32)
                            : Color.white.opacity(isHovered ? 0.25 : 0.12),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.08), radius: isHovered ? 4 : 2, y: isHovered ? 2 : 1)
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Primary Done Button
private struct PrimaryDoneButton: View {
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(WalkmanFont.calloutBold)
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                .padding(.horizontal, 24)
                .padding(.vertical, 8.5)
                .background(WalkmanTheme.silverGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.20), radius: isHovered ? 6 : 3, x: 0, y: isHovered ? 2 : 1)
                .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
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

// MARK: - Subviews
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

private struct RuleCard: View {
    let icon: String
    let title: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.85)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
        )
    }
}
