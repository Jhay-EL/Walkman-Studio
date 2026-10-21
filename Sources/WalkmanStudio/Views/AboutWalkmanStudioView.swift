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
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(WalkmanTheme.silverGradient)
                            .frame(width: 64, height: 64)
                        Text("W.")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                
                Text("Walkman Studio")
                    .font(WalkmanFont.title1)
                    .foregroundStyle(.primary)
                
                Text("Version 1.2.0 • Apple Silicon Native")
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
            .padding(.bottom, 14)
            
            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Hardware").tag(0)
                Text("Supported DAPs").tag(1)
                Text("Engine Rules").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .padding(.bottom, 12)
            
            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    hardwareTabView
                case 1:
                    supportedModelsTabView
                default:
                    engineRulesTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            
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
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 540, height: 520)
        .background(WalkmanTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - Tab 0: Hardware View
    private var hardwareTabView: some View {
        VStack(spacing: 12) {
            if let dev = currentDeviceInfo {
                HStack(spacing: 12) {
                    WalkmanDeviceIconView(size: 44)
                    
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
                                HStack {
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
