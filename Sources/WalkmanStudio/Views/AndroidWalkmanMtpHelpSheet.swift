import SwiftUI
import AppKit

public struct AndroidWalkmanMtpHelpSheet: View {
    let onDismiss: () -> Void
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connecting Android Walkmans on Mac")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("NW-WM1AM2, NW-WM1ZM2, NW-ZX707, NW-A306, NW-A105, NW-ZX507")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.04))
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Why MTP notice
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WalkmanTheme.hiResGold)
                            Text("Why isn't internal storage mounted automatically?")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Unlike classic Sony OS Walkmans (NW-A55, NW-ZX300) which use USB Mass Storage (MSC), modern Android-based Walkmans connect strictly using MTP (Media Transfer Protocol) in File Transfer mode. macOS Darwin has no built-in MTP filesystem driver, so internal storage does not automatically appear in Finder.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    
                    Text("Choose one of the 3 easy ways to connect:")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    // Option 1
                    HelpOptionCard(
                        number: "1",
                        badge: "Recommended for Internal Storage",
                        title: "Mount with MacDroid or OpenMTP",
                        description: "Free macOS MTP utilities like MacDroid or OpenMTP mount your Walkman's internal storage directly into Finder (under /Volumes/Internal shared storage). Walkman Studio automatically recognizes this volume and all tracks.",
                        actionTitle: "Learn about MacDroid",
                        actionURL: "https://www.macdroid.app"
                    )
                    
                    // Option 2
                    HelpOptionCard(
                        number: "2",
                        badge: "Fastest Speed (Up to 300 MB/s)",
                        title: "Direct MicroSD Card Reader",
                        description: "If you store music on a MicroSD card, remove it from your Walkman and insert it into your Mac's SD card slot or a USB-C card reader. macOS mounts it as native Mass Storage, enabling maximum transfer speed and instant Walkman Studio recognition.",
                        actionTitle: nil,
                        actionURL: nil
                    )
                    
                    // Option 3
                    HelpOptionCard(
                        number: "3",
                        badge: "Direct Selection",
                        title: "Select Walkman Storage Folder",
                        description: "If your Walkman internal storage is mounted or mapped to a folder on your Mac, click 'Select Walkman Storage Folder' on the connection screen. Walkman Studio will bind it, scan its /Music folder, and remember your choice.",
                        actionTitle: nil,
                        actionURL: nil
                    )
                }
                .padding(20)
            }
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Footer
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("Got It")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.02))
        }
        .frame(width: 540, height: 560)
        .background(WalkmanTheme.background)
    }
}

private struct HelpOptionCard: View {
    let number: String
    let badge: String
    let title: String
    let description: String
    let actionTitle: String?
    let actionURL: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())
                
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(WalkmanTheme.hiResGold.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            
            if let actionTitle = actionTitle, let urlStr = actionURL, let url = URL(string: urlStr) {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
