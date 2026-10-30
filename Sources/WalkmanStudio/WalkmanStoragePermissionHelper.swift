import SwiftUI
import AppKit

// MARK: - Walkman Storage Permission Helper
public enum WalkmanStoragePermissionHelper {

    /// Checks if an error is a macOS TCC or file permission error
    public static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        // Cocoa error codes: 257 (NSFileReadNoPermissionError), 513 (NSFileWriteNoPermissionError), 512 (NSFileWriteUnknownError)
        if ns.domain == NSCocoaErrorDomain && (ns.code == 257 || ns.code == 513 || ns.code == 512) {
            return true
        }
        // POSIX error codes: 1 (EPERM), 13 (EACCES)
        if ns.domain == NSPOSIXErrorDomain && (ns.code == 1 || ns.code == 13) {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("permission") || desc.contains("permitted") || desc.contains("access") || desc.contains("privilege")
    }

    /// Resolves the root volume URL for any file path (e.g. /Volumes/SD_CARD)
    public static func getVolumeURL(for fileURL: URL) -> URL? {
        let path = fileURL.standardized.path
        if path.hasPrefix("/Volumes/") {
            let components = path.split(separator: "/")
            if components.count >= 2 {
                return URL(fileURLWithPath: "/Volumes/" + String(components[1]))
            }
        }
        return nil
    }

    /// Resolves the user-facing drive name from a file URL
    public static func getDriveName(for fileURL: URL) -> String {
        if let vol = getVolumeURL(for: fileURL) {
            return vol.lastPathComponent
        }
        return "Walkman Storage"
    }

    /// Prompts the user with an NSOpenPanel to grant access to the storage volume/folder
    @MainActor
    public static func requestAccess(for fileURL: URL, completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        let driveName = getDriveName(for: fileURL)
        panel.title = "Grant Walkman Storage Access"
        panel.message = "Please select \"\(driveName)\" and click \"Grant Access\" to allow Walkman Studio to save metadata and lyrics changes."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let volumeURL = getVolumeURL(for: fileURL) ?? fileURL.deletingLastPathComponent()
        panel.directoryURL = volumeURL

        let response = panel.runModal()
        if response == .OK, let selectedURL = panel.url {
            _ = selectedURL.startAccessingSecurityScopedResource()
            completion(true)
        } else {
            completion(false)
        }
    }

    /// Opens macOS System Settings directly to Files and Folders / Removable Volumes privacy panel
    public static func openSystemPrivacySettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_RemovableVolume",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for urlStr in settingsURLs {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

// MARK: - Storage Permission Request Sheet
public struct StoragePermissionRequestSheet: View {
    let fileURL: URL
    let onGranted: () -> Void
    let onDismiss: () -> Void

    @State private var isGrantHovered: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    private var driveName: String {
        WalkmanStoragePermissionHelper.getDriveName(for: fileURL)
    }

    public init(fileURL: URL, onGranted: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onGranted = onGranted
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dismiss Bar
            HStack {
                Spacer()
                SheetCloseButton(action: onDismiss)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.85), Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
                .shadow(color: Color.orange.opacity(0.35), radius: 8, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage Permission Required")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(.white)

                    Text("macOS requires authorization to modify files on \(driveName)")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Divider()
                .background(Color.white.opacity(0.08))

            // Informational Body
            VStack(alignment: .leading, spacing: 14) {
                Text("Sony Walkman devices and MicroSD cards are protected by macOS privacy controls. Before Walkman Studio can save tags, album artwork, or synchronized lyrics directly to your music, permission must be granted for this drive.")
                    .font(WalkmanFont.body)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .font(.system(size: 14))
                        Text("Click \"Grant Access...\" below and choose \(driveName) to authorize Walkman Studio immediately.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Color.orange)
                            .font(.system(size: 14))
                        Text("Or open System Settings > Privacy & Security > Files and Folders to enable access.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
            }
            .padding(24)

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer Actions
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    WalkmanStoragePermissionHelper.openSystemPrivacySettings()
                }
                .font(WalkmanFont.bodyMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(isSettingsHovered ? 0.12 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(Color.white.opacity(0.85))
                .buttonStyle(.plain)
                .onHover { isSettingsHovered = $0 }

                Spacer()

                Button("Cancel", action: onDismiss)
                    .font(WalkmanFont.bodyMedium)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .buttonStyle(.plain)
                    .onHover { isCancelHovered = $0 }

                Button(action: {
                    WalkmanStoragePermissionHelper.requestAccess(for: fileURL) { granted in
                        if granted {
                            onGranted()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Grant Access...")
                            .font(WalkmanFont.headline)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8.5)
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.9), Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                    )
                    .scaleEffect(isGrantHovered ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { isGrantHovered = $0 }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .background(
            ZStack {
                Color(red: 16 / 255, green: 16 / 255, blue: 18 / 255)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.04),
                        Color.clear,
                        Color.black.opacity(0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
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
    }
}
