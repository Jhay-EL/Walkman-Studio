import SwiftUI
import AppKit

public struct AboutWalkmanStudioView: View {
    let currentDeviceInfo: WalkmanDeviceInfo?
    let onDismiss: () -> Void
    
    @State private var selectedTab: Int = 0
    
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
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            
            // Hero App Header (Apple macOS System Style)
            VStack(spacing: 6) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(WalkmanTheme.silverGradient)
                            .frame(width: 68, height: 68)
                        Text("W.")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                
                Text("Walkman Studio")
                    .font(WalkmanFont.title1)
                    .foregroundStyle(.primary)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0") • Universal (Apple Silicon & Intel)")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Non-Android Sony OS / Linux Architecture")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .padding(.top, -6)
            .padding(.bottom, 12)
            
            // Developer Attribution & Action Card
            developerHeaderCard
            
            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Hardware").tag(0)
                Text("Supported DAPs").tag(1)
                Text("Engine Rules").tag(2)
                Text("Developer & Support").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 480)
            .padding(.bottom, 12)
            
            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    hardwareTabView
                case 1:
                    supportedModelsTabView
                case 2:
                    engineRulesTabView
                default:
                    developerTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            
            // Bottom Action Footer
            HStack(alignment: .center) {
                Text("Sony & Walkman are registered trademarks of Sony Group Corporation.")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .font(WalkmanFont.calloutBold)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 680, height: 660)
        .background(WalkmanTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - Developer Attribution Card
    private var developerHeaderCard: some View {
        HStack(spacing: 12) {
            // Developer Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 45 / 255, green: 50 / 255, blue: 64 / 255),
                                Color(red: 24 / 255, green: 26 / 255, blue: 34 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Developer:")
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(.secondary)
                    
                    Text("John Lloyd Malabanan")
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(.primary)
                    
                    Text("(@Jhay-EL)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                
                Text("Creator and Lead Software Engineer of Walkman Studio")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Direct Link Buttons: GitHub & Buy Me a Coffee
            HStack(spacing: 8) {
                // GitHub Button
                Button(action: {
                    openURL("https://github.com/Jhay-EL")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("GitHub")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Visit John Lloyd Malabanan's GitHub profile (https://github.com/Jhay-EL)")
                
                // Buy Me a Coffee Button
                Button(action: {
                    openURL("https://www.buymeacoffee.com/jhayel")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                        Text("Buy Me a Coffee")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Support development on Buy Me a Coffee (https://www.buymeacoffee.com/jhayel)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
    
    // MARK: - Tab 0: Hardware View
    private var hardwareTabView: some View {
        VStack(spacing: 12) {
            if let dev = currentDeviceInfo {
                HStack(spacing: 12) {
                    WalkmanDeviceIconView(size: 44, deviceInfo: dev)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(dev.displayName)
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text("Verified")
                                    .font(WalkmanFont.badge.weight(.bold))
                                    .foregroundStyle(Color.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        
                        Text("Connected via USB Mass Storage • S-Master HX DAC")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Specifications Grid
                VStack(spacing: 1) {
                    SpecRow(label: "Hardware Model", value: dev.modelRaw)
                    SpecRow(label: "Firmware Version", value: "v\(dev.firmwareVersion)")
                    SpecRow(label: "Screen Engine", value: "\(dev.displayResolution) (Baseline RGB)")
                    SpecRow(label: "Internal Flash", value: String(format: "%.1f GB", dev.internalCapacityGb))
                    SpecRow(label: "Audio Pipeline", value: "S-Master HX, DSEE HX, Vinyl")
                    SpecRow(label: "Tag Standard", value: "Strict ID3v2.3 (UTF-16) & Vorbis")
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 28))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    
                    Text("No Walkman Connected")
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Connect your Sony Walkman via USB in Mass Storage mode to inspect hardware specifications.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
    
    // MARK: - Tab 1: Supported Models View
    private var supportedModelsTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(WalkmanDeviceDetector.supportedSeriesCategories, id: \.category) { cat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cat.category.uppercased())
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                        
                        VStack(spacing: 1) {
                            ForEach(cat.models) { m in
                                HStack(spacing: 10) {
                                    WalkmanDeviceIconView(
                                        size: 30,
                                        modelName: m.modelCode,
                                        hasBackground: false
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 1) {
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.03))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Android Walkmans (NW-A100/A300, NW-ZX500) use MTP and are not supported.")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Tab 2: Engine Rules View
    private var engineRulesTabView: some View {
        VStack(spacing: 8) {
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
        ScrollView {
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
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 32))
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
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(WalkmanTheme.hiResGold.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Text("GitHub: @Jhay-EL • Software Engineer & Audiophile")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text("Walkman Studio was designed and engineered from the ground up to solve the challenges of using modern macOS with Sony Walkman digital audio players. It automates strict ID3v2.3 tagging, Baseline RGB JPEG cover art conversion, synchronized lyrics synchronization, dual-partition routing, and AppleDouble ghost file cleanup.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(14)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                
                // Links Grid
                HStack(spacing: 10) {
                    // GitHub Profile Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 14, weight: .bold))
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
                        
                        Button(action: {
                            openURL("https://github.com/Jhay-EL")
                        }) {
                            HStack(spacing: 5) {
                                Text("github.com/Jhay-EL")
                                    .font(WalkmanFont.calloutBold)
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    // Walkman Studio Repo Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14, weight: .semibold))
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
                        
                        Button(action: {
                            openURL("https://github.com/Jhay-EL/Walkman-Studio")
                        }) {
                            HStack(spacing: 5) {
                                Text("Jhay-EL/Walkman-Studio")
                                    .font(WalkmanFont.calloutBold)
                                Image(systemName: "arrow.up.forward")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                
                // Buy Me a Coffee Support Banner
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.18))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Support Walkman Studio Development")
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.primary)
                            
                            Text("Buy Me a Coffee")
                                .font(WalkmanFont.badge)
                                .foregroundStyle(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        Text("If Walkman Studio enhances your music listening experience, consider buying a coffee to support maintenance and hardware testing.")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        openURL("https://www.buymeacoffee.com/jhayel")
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Support")
                                .font(WalkmanFont.calloutBold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255))
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 255 / 255, green: 221 / 255, blue: 0 / 255).opacity(0.2), lineWidth: 1)
                )
                
                // Contact & Licensing Footer Info
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 11))
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
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("License: MIT (Free & Open Source)")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 2)
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
                .font(WalkmanFont.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(WalkmanFont.mono)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
    }
}

private struct RuleCard: View {
    let icon: String
    let title: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(WalkmanTheme.silver)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
