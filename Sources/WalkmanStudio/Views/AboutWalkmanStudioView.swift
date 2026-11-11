import SwiftUI
import AppKit

// MARK: - About Tabs
public enum AboutTab: Int, CaseIterable, Identifiable {
    case hardware = 0
    case supportedDAPs = 1
    case developerSupport = 2
    case updates = 3

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .hardware: return "Hardware"
        case .supportedDAPs: return "Supported DAPs"
        case .developerSupport: return "Developer & Support"
        case .updates: return "Updates"
        }
    }

    var icon: String {
        switch self {
        case .hardware: return "cpu"
        case .supportedDAPs: return "music.note.list"
        case .developerSupport: return "person.crop.circle"
        case .updates: return "arrow.down.circle"
        }
    }
}

public struct AboutWalkmanStudioView: View {
    let currentDeviceInfo: WalkmanDeviceInfo?
    let initialTab: AboutTab
    let onDismiss: () -> Void
    
    @State private var selectedTab: AboutTab
    @State private var showActiveTransferConfirm: Bool = false
    @ObservedObject private var updateService = AppUpdateService.shared
    @ObservedObject private var transferService = TransferQueueService.shared
    
    public init(
        currentDeviceInfo: WalkmanDeviceInfo?,
        initialTab: AboutTab = .hardware,
        onDismiss: @escaping () -> Void
    ) {
        self.currentDeviceInfo = currentDeviceInfo
        self.initialTab = initialTab
        self.onDismiss = onDismiss
        self._selectedTab = State(initialValue: initialTab)
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
    
    private var appLogoImage: NSImage? {
        if let bundleURL = Bundle.main.url(forResource: "walkman_logo_emblem", withExtension: "png"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        if let localImg = NSImage(contentsOfFile: "assets/walkman_logo_emblem.png") {
            return localImg
        }
        return appIcon
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
            VStack(spacing: 8) {
                if let logo = appLogoImage {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 6)
                } else if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 6)
                } else {
                    Text("W.")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .shadow(color: WalkmanTheme.hiResGold.opacity(0.35), radius: 10)
                }
                
                Text("Walkman Studio")
                    .font(WalkmanFont.title1)
                    .foregroundStyle(.primary)
                
                Text("Version \(updateService.currentVersionString) (\(updateService.currentBuildNumberString)) • \(updateService.runningBuildArchitecture.displayName)")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Universal Sony Walkman Architecture • Sony OS & Android DAP")
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
            .padding(.top, -18)
            .padding(.bottom, 16)
            
            // Liquid Glass Segmented Pill Bar
            AboutSegmentedBar(
                selectedTab: $selectedTab,
                hasAvailableUpdate: updateService.hasAvailableUpdate
            )
            .padding(.bottom, 16)
            
            // Tab Content
            Group {
                switch selectedTab {
                case .hardware:
                    hardwareTabView
                case .supportedDAPs:
                    supportedModelsTabView
                case .developerSupport:
                    developerTabView
                case .updates:
                    updatesTabView
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
        .onAppear {
            selectedTab = initialTab
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkForUpdates)) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedTab = .updates
            }
        }
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
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.green)
                    Text("Fully supports both classic Sony OS (Linux DAP) and modern Android-based Walkmans (NW-A100, NW-A300, NW-ZX500, NW-ZX700, NW-WM1M2).")
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
    
    // MARK: - Tab 2: Developer & Support View
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
                            
                            Text("GitHub: @Jhay-EL • UX/UI Designer & Software Developer")
                                .font(WalkmanFont.subheadlineMedium)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text("Walkman Studio was designed and engineered from the ground up to solve the challenges of using modern macOS with Sony Walkman digital audio players. It automates strict ID3v2.3 & FLAC tagging, Baseline RGB JPEG cover art conversion, Sony 12 Tone / SenseMe acoustic analysis, synchronized .LRC lyrics, batch metadata editing, dual-partition storage routing, and AppleDouble ghost file cleanup.")
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

    // MARK: - Tab 4: Updates View
    private var hasActiveTransfers: Bool {
        transferService.queue.contains { $0.status == .optimizing || $0.status == .converting }
    }

    private var updatesTabView: some View {
        let target = updateService.installTarget

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                // Status & Primary Action Hero Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        updateStatusIconView

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(updateHeadlineTitle)
                                    .font(WalkmanFont.title3)
                                    .foregroundStyle(.primary)

                                updateStatusBadge
                            }

                            Text("Installed: v\(updateService.currentVersionString) • \(updateService.runningBuildArchitecture.shortLabel) • Target: \(target.destinationAppURL.path)")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let lastChecked = updateService.lastCheckedAt {
                                Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 8)

                        updatePrimaryActionControl
                    }

                    // Active download / verification / ready bar
                    switch updateService.state {
                    case .downloading(let rel, let progress, let written, let total):
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: max(0.0, min(1.0, progress)))
                                .progressViewStyle(.linear)
                                .tint(WalkmanTheme.hiResGold)

                            HStack {
                                Text(rel.preferredAsset?.name ?? "Downloading archive...")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(formatBytes(written)) of \(formatBytes(max(total, written))) (\(Int((progress * 100).rounded()))%)")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    case .verifying(let rel, let stage):
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 16, height: 16)
                            Text(stage)
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(WalkmanTheme.silverLight)
                            Spacer()
                            Text(rel.tagName)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    case .readyToInstall(_, _, let checksumVerified):
                        HStack(spacing: 8) {
                            Image(systemName: checksumVerified ? "checkmark.shield.fill" : "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(checksumVerified ? Color.green : WalkmanTheme.silverLight)
                            Text(checksumVerified
                                 ? "Archive verified via SHA-256 checksum & code signature. Click Install & Relaunch to update cleanly."
                                 : "Archive extracted & code-signature verified. Click Install & Relaunch to update.")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.22), lineWidth: 0.8)
                        )

                    case .installing:
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 16, height: 16)
                            Text("Closing Walkman Studio, replacing app bundle, and relaunching...")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(WalkmanTheme.silverLight)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    case .failed(let message):
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.orange)
                                .padding(.top, 1)
                            Text(message)
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(Color.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
                        )

                    default:
                        EmptyView()
                    }

                    // Contextual Notices (Dev binary, Translocation, Read-only volume, Active Transfers)
                    if !target.isBundledApp {
                        updateNoticeRow(
                            icon: "hammer.fill",
                            color: WalkmanTheme.silverLight,
                            text: "Running unbundled build: release updates install cleanly into /Applications/Walkman Studio.app."
                        )
                    } else if target.isSourceOnReadOnlyVolume || target.isAppTranslocated {
                        updateNoticeRow(
                            icon: "externaldrive.badge.checkmark",
                            color: WalkmanTheme.silverLight,
                            text: "Running from a read-only or translocated volume: update will install to /Applications/Walkman Studio.app."
                        )
                    }

                    if hasActiveTransfers {
                        updateNoticeRow(
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: Color.orange,
                            text: "A Transfer & Convert job is currently in progress. Wait for transfers to finish before relaunching."
                        )
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
                )

                // Automatic Checks & Quick Links Bar
                HStack(spacing: 12) {
                    Toggle(isOn: $updateService.autoCheckOnLaunch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for updates automatically")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.primary)
                            Text("Checks GitHub Releases (Jhay-EL/Walkman-Studio) in the background on startup.")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Spacer(minLength: 8)

                    TactileLinkButton(
                        title: "GitHub Releases",
                        icon: "arrow.up.forward",
                        url: updateService.availableRelease?.htmlURL.absoluteString ?? AppUpdateService.releasesPageURL.absoluteString
                    )

                    TactileLinkButton(
                        title: "Mirror",
                        icon: "externaldrive.fill",
                        url: AppUpdateService.googleDriveMirrorURL.absoluteString
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.85)
                )

                // Release Notes Panel
                if let release = updateService.availableRelease {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(release.title)
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if let published = release.publishedAt {
                                Text(published.formatted(date: .abbreviated, time: .omitted))
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(.secondary)
                            }

                            if let asset = release.preferredAsset {
                                Text("• \(asset.flavorLabel) (\(formatBytes(asset.sizeBytes)))")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.07))

                        ReleaseNotesFormattedView(markdown: release.releaseNotes)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.85)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                            Text("Direct GitHub Release Installer")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.primary)
                        }
                        Text("Updates are fetched directly from github.com/Jhay-EL/Walkman-Studio, verified against SHA256SUMS.txt, checked for code-signature integrity, and applied automatically without manual DMG mounting.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.85)
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .alert("Transfer in Progress", isPresented: $showActiveTransferConfirm) {
            Button("Wait for Transfers", role: .cancel) {}
            Button("Quit, Update & Relaunch", role: .destructive) {
                updateService.installAndRelaunch()
            }
        } message: {
            Text("Walkman Studio is currently writing or converting files for your Walkman. Installing now will terminate those tasks before relaunching.")
        }
    }

    private func updateNoticeRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var updateStatusIconView: some View {
        let iconSpec: (symbol: String, color: Color, isLoading: Bool) = {
            switch updateService.state {
            case .checking:
                return ("arrow.triangle.2.circlepath", WalkmanTheme.silverLight, true)
            case .upToDate:
                return ("checkmark.seal.fill", Color.green, false)
            case .available:
                return ("arrow.down.circle.fill", WalkmanTheme.hiResGold, false)
            case .downloading, .verifying, .installing:
                return ("arrow.down.circle.fill", WalkmanTheme.silverLight, true)
            case .readyToInstall:
                return ("checkmark.circle.fill", Color.green, false)
            case .failed:
                return ("exclamationmark.triangle.fill", Color.orange, false)
            case .idle:
                return ("arrow.triangle.2.circlepath", WalkmanTheme.silverLight, false)
            }
        }()

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconSpec.color.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(iconSpec.color.opacity(0.28), lineWidth: 0.85)
                )

            if iconSpec.isLoading {
                ProgressView()
                    .scaleEffect(0.75)
            } else {
                Image(systemName: iconSpec.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconSpec.color)
            }
        }
    }

    private var updateHeadlineTitle: String {
        switch updateService.state {
        case .idle: return "Software Updates"
        case .checking: return "Checking GitHub Releases..."
        case .upToDate: return "Walkman Studio is Up to Date"
        case .available(let rel): return "Walkman Studio \(rel.tagName) Available"
        case .downloading(let rel, _, _, _): return "Downloading \(rel.tagName)..."
        case .verifying(let rel, _): return "Preparing \(rel.tagName)..."
        case .readyToInstall(let rel, _, _): return "\(rel.tagName) Ready to Install"
        case .installing(let rel): return "Installing \(rel.tagName)..."
        case .failed: return "Update Check Failed"
        }
    }

    @ViewBuilder
    private var updateStatusBadge: some View {
        switch updateService.state {
        case .upToDate:
            statusPill("v\(updateService.currentVersionString)", color: .green)
        case .available(let rel):
            statusPill("New • \(rel.tagName)", color: WalkmanTheme.hiResGold)
        case .readyToInstall(let rel, _, _):
            statusPill("Staged • \(rel.tagName)", color: .green)
        case .failed:
            statusPill("Retry Needed", color: .orange)
        default:
            EmptyView()
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(WalkmanFont.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.32), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private var updatePrimaryActionControl: some View {
        switch updateService.state {
        case .idle, .upToDate:
            TactileActionButton(
                title: "Check for Updates",
                icon: "arrow.triangle.2.circlepath",
                isAccent: false
            ) {
                updateService.checkForUpdates(userInitiated: true)
            }
        case .checking:
            TactileActionButton(
                title: "Checking...",
                icon: "hourglass",
                isAccent: false,
                isDisabled: true
            ) {}
        case .available(let rel):
            TactileActionButton(
                title: "Download & Prepare",
                icon: "arrow.down.circle.fill",
                isAccent: true,
                accentColor: WalkmanTheme.hiResGold
            ) {
                updateService.downloadAndStageUpdate(rel)
            }
        case .downloading:
            TactileActionButton(
                title: "Cancel",
                icon: "xmark",
                isAccent: false
            ) {
                updateService.cancelDownload()
            }
        case .verifying, .installing:
            TactileActionButton(
                title: "Working...",
                icon: "gearshape.2",
                isAccent: false,
                isDisabled: true
            ) {}
        case .readyToInstall:
            TactileActionButton(
                title: "Install & Relaunch",
                icon: "arrow.clockwise.circle.fill",
                isAccent: true,
                accentColor: .green
            ) {
                if hasActiveTransfers {
                    showActiveTransferConfirm = true
                } else {
                    updateService.installAndRelaunch()
                }
            }
        case .failed:
            TactileActionButton(
                title: "Retry Check",
                icon: "arrow.clockwise",
                isAccent: false
            ) {
                updateService.checkForUpdates(userInitiated: true)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

// MARK: - Release Notes Formatter
private struct ReleaseNotesFormattedView: View {
    let markdown: String

    var body: some View {
        let lines = markdown.components(separatedBy: .newlines)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 2)
                } else if trimmed.hasPrefix("### ") {
                    Text(trimmed.dropFirst(4))
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("## ") {
                    Text(trimmed.dropFirst(3))
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.primary)
                        .padding(.top, 5)
                } else if trimmed.hasPrefix("# ") {
                    Text(trimmed.dropFirst(2))
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.primary)
                } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 7) {
                        Text("•")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(WalkmanTheme.hiResGold)
                        inlineMarkdownText(String(trimmed.dropFirst(2)))
                    }
                    .padding(.leading, 4)
                } else {
                    inlineMarkdownText(trimmed)
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func inlineMarkdownText(_ source: String) -> some View {
        if let attr = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .font(WalkmanFont.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(source)
                .font(WalkmanFont.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Liquid Glass Segmented Pill Bar
private struct AboutSegmentedBar: View {
    @Binding var selectedTab: AboutTab
    let hasAvailableUpdate: Bool
    @Namespace private var tabNamespace
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AboutTab.allCases) { tab in
                AboutTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    showBadgeDot: tab == .updates && hasAvailableUpdate,
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
    let showBadgeDot: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if showBadgeDot {
                    Circle()
                        .fill(WalkmanTheme.hiResGold)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.68)))
            .padding(.horizontal, 15)
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

// MARK: - Tactile Action Button
private struct TactileActionButton: View {
    let title: String
    let icon: String
    var isAccent: Bool = false
    var accentColor: Color = WalkmanTheme.hiResGold
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6.5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(WalkmanFont.calloutBold)
            }
            .foregroundStyle(
                isDisabled
                    ? Color.white.opacity(0.42)
                    : (isAccent
                        ? (isHovered ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255) : accentColor)
                        : (isHovered ? Color.white : WalkmanTheme.silverLight))
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                ZStack {
                    if isAccent && !isDisabled {
                        if isHovered {
                            accentColor
                        } else {
                            accentColor.opacity(0.16)
                        }
                    } else {
                        Color.white.opacity(isHovered && !isDisabled ? 0.14 : 0.07)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isAccent && !isDisabled
                            ? accentColor.opacity(isHovered ? 0.72 : 0.36)
                            : Color.white.opacity(isHovered && !isDisabled ? 0.25 : 0.12),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered && !isDisabled ? 0.25 : 0.08), radius: isHovered ? 4 : 2, y: isHovered ? 2 : 1)
            .scaleEffect(isHovered && !isDisabled ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { h in
            guard !isDisabled else { isHovered = false; return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
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
