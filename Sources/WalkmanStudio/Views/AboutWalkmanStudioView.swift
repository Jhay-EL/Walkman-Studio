import SwiftUI

public struct AboutWalkmanStudioView: View {
    let currentDeviceInfo: WalkmanDeviceInfo?
    let onDismiss: () -> Void
    
    @State private var selectedTab: Int = 0
    
    public init(currentDeviceInfo: WalkmanDeviceInfo?, onDismiss: @escaping () -> Void) {
        self.currentDeviceInfo = currentDeviceInfo
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(WalkmanTheme.silverGradient)
                            .frame(width: 28, height: 28)
                        
                        Text("W.")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("About Walkman Studio")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Version 1.2.0 • Native Apple Silicon (ARM64)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(WalkmanTheme.card.opacity(0.8))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .bottom)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Active Device Hardware Detection Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("HARDWARE STATUS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if currentDeviceInfo != nil {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text("Non-Android Sony DAP Verified")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.green)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.secondary)
                                        .frame(width: 6, height: 6)
                                    Text("No Device Connected")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        if let dev = currentDeviceInfo {
                            HStack(spacing: 14) {
                                WalkmanDeviceIconView(size: 44)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(dev.displayName)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                        
                                        if dev.hasCfw {
                                            Text("Walkman One CFW")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.white.opacity(0.15))
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    Text("Model: \(dev.modelRaw) • Firmware: \(dev.firmwareVersion) • Screen: \(dev.displayResolution) • Internal: \(String(format: "%.1f GB", dev.internalCapacityGb))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text("Connect a non-Android Sony Walkman via USB Mass Storage mode to inspect hardware specifications.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 10)
                    
                    // Non-Android Specialization Banner
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                                .foregroundStyle(WalkmanTheme.silver)
                            
                            Text("Engineered Exclusively for Non-Android Sony Walkmans")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Walkman Studio is purpose-built for Sony's proprietary Linux/Sony OS Digital Audio Players. These players run direct hardware DAC pipelines (S-Master HX, DSEE HX, Vinyl Processor) and enforce strict hardware filesystem rules that standard modern software overlooks:")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ComplianceBullet(title: "Baseline RGB JPEG Only", detail: "Sony OS decoders cannot render Progressive JPEGs or CMYK artwork; Walkman Studio strictly enforces 800x800 Baseline RGB.")
                            ComplianceBullet(title: "Strict ID3v2.3 (UTF-16)", detail: "Non-Android firmware misreads ID3v2.4 frames; Walkman Studio converts and saves strictly as ID3v2.3.")
                            ComplianceBullet(title: "CRLF Relative .M3U8 Playlists", detail: "Generates hardware-compatible playlists stored in /MUSIC/ with relative POSIX paths and Windows CRLF line endings.")
                            ComplianceBullet(title: "macOS Ghost File Clean & Eject", detail: "Executes `dot_clean -m` and purges .DS_Store, ._ AppleDouble files, and .Spotlight-V100 before unmounting.")
                        }
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 10)
                    
                    // Categorized Supported Devices List
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("SUPPORTED SONY WALKMAN DEVICES (NON-ANDROID ONLY)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            Text("\(WalkmanDeviceDetector.supportedSeriesCategories.flatMap { $0.models }.count) Models Supported")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.silverLight)
                        }
                        
                        ForEach(WalkmanDeviceDetector.supportedSeriesCategories, id: \.category) { cat in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(cat.category)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .padding(.top, 4)
                                
                                ForEach(cat.models) { m in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("•")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                        
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(m.modelCode)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                
                                                Text("(\(m.series), \(m.releaseYear))")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                
                                                Spacer()
                                                
                                                Text(m.storageOptions)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                            }
                                            
                                            Text(m.description)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.025))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 10)
                    
                    // Explicit Unsupported Notice: Android Walkmans
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange)
                            
                            Text("Unsupported Devices: Android-Based Walkmans")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Walkman Studio does NOT support Android-powered Sony Walkmans. Android models run standard Google Android OS, connect via MTP (Media Transfer Protocol) rather than Mass Storage, and do not have the FAT32/Baseline JPEG/ID3v2.3 hardware limitations:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        ForEach(WalkmanDeviceDetector.unsupportedAndroidModels) { un in
                            HStack(spacing: 8) {
                                Text("✕")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.8))
                                
                                Text(un.modelCode)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                
                                Text("(\(un.androidVersion))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Text(un.reason)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 10)
                }
                .padding(20)
            }
            
            // Bottom Footer
            HStack {
                Text("Designed for Sony NW-A55L & Sony Non-Android DAPs • macOS Apple Silicon")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Done") {
                    onDismiss()
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(WalkmanTheme.silverGradient)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(WalkmanTheme.card.opacity(0.8))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(WalkmanTheme.border), alignment: .top)
        }
        .frame(width: 660, height: 600)
        .background(WalkmanTheme.background)
    }
}

private struct ComplianceBullet: View {
    let title: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(WalkmanTheme.silver)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
