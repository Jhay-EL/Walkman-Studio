import SwiftUI
import AppKit

public struct ManageLocalFoldersSheet: View {
    let onDismiss: () -> Void

    @ObservedObject private var localService = LocalMusicLibraryService.shared
    @State private var folderToRemove: LocalMusicFolder? = nil
    @State private var showRemoveConfirmation = false

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Dismiss Control (Liquid Glass Circular Close)
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)

            // Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Scanning Banner (only visible during active manual/import rescan)
            if localService.isScanning {
                scanningStatusBanner
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            // Content
            if localService.folders.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                folderListView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Footer
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 700, height: 580)
        .modalGlassChassis(cornerRadius: 16)
        .confirmationDialog(
            "Remove Folder from Local Library?",
            isPresented: $showRemoveConfirmation,
            presenting: folderToRemove
        ) { folder in
            Button("Remove from Library", role: .destructive) {
                localService.removeFolder(id: folder.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Are you sure you want to remove \"\(folder.displayName)\" from Walkman Studio? All indexed tracks from this folder will be cleared from your local library database. Audio files on disk will NOT be touched.")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        let folderCount = localService.folders.count

        return HStack(spacing: 14) {
            GlassIconTile(
                symbol: "folder.badge.gearshape",
                tint: WalkmanTheme.hiResGold,
                size: 48,
                cornerRadius: 12,
                iconSize: 20
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Manage Local Folders")
                        .font(WalkmanFont.title2)
                        .foregroundStyle(WalkmanTheme.silverLight)

                    Text("\(folderCount) \(folderCount == 1 ? "Folder" : "Folders")")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                        )
                }

                Text("Manage local music directories indexed into Walkman Studio's SQLite library.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                // Add Folder Button (Prominent Liquid Glass Capsule)
                Button(action: openFolderPicker) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add Folder...")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
                .help("Select music directories from your Mac or external drive")

                // Rescan All Button (Liquid Glass Icon Capsule)
                Button(action: { localService.rescanAllFolders() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(localService.isScanning ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
                        .rotationEffect(localService.isScanning ? .degrees(360) : .zero)
                        .animation(
                            localService.isScanning
                                ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                : .default,
                            value: localService.isScanning
                        )
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 18))
                .disabled(localService.isScanning || localService.folders.isEmpty)
                .help("Rescan all monitored local music folders")
            }
        }
    }

    // MARK: - Scanning Status Banner
    private var scanningStatusBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.65)
                .tint(WalkmanTheme.hiResGold)
                .frame(width: 16, height: 16)

            Text(localService.scanStatusText ?? "Scanning local folders...")
                .font(WalkmanFont.calloutMedium)
                .foregroundStyle(WalkmanTheme.silverLight)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WalkmanTheme.hiResGold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(WalkmanTheme.hiResGold.opacity(0.28), lineWidth: 0.85)
        )
    }

    // MARK: - Folder List View
    private var folderListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 10) {
                ForEach(localService.folders) { folder in
                    LocalFolderGlassCard(
                        folder: folder,
                        isScanning: localService.isScanning,
                        onRescan: {
                            localService.rescanFolder(url: folder.url)
                        },
                        onRelocate: {
                            openRelocatePicker(for: folder)
                        },
                        onReveal: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                        },
                        onRemove: {
                            self.folderToRemove = folder
                            self.showRemoveConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            GlassIconTile(
                symbol: "folder.badge.plus",
                tint: WalkmanTheme.silverLight,
                size: 72,
                cornerRadius: 20,
                iconSize: 30
            )

            VStack(spacing: 6) {
                Text("No Local Music Folders Added")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(WalkmanTheme.silverLight)

                Text("Add folders from your Mac or external drive to index and manage music in Walkman Studio without requiring a connected Walkman.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: openFolderPicker) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add Music Folder...")
                        .font(WalkmanFont.calloutBold)
                }
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                .padding(.horizontal, 18)
                .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
        }
        .padding(32)
    }

    // MARK: - Footer
    private var footerView: some View {
        let trackCount = localService.tracks.count

        return HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("SQLite Database: ~/.walkman_local_library.db")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
            )

            Spacer()

            Text("\(trackCount) \(trackCount == 1 ? "track" : "tracks") indexed")
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverMuted)

            Button(action: onDismiss) {
                Text("Done")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 24)
                    .frame(height: 36)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 18))
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions
    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add to Library"
        panel.title = "Select Local Music Folders"

        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                localService.addFolders(urls: urls)
            }
        }
    }

    private func openRelocatePicker(for folder: LocalMusicFolder) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Relocate Folder"
        panel.title = "Choose New Location for \"\(folder.displayName)\""

        if panel.runModal() == .OK, let url = panel.url {
            _ = localService.relocateFolder(id: folder.id, toURL: url)
        }
    }
}

// MARK: - Liquid Glass Icon Tile
private struct GlassIconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 11
    var iconSize: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: size, height: size)

            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.28), location: 0.0),
                        .init(color: Color.white.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size * 0.30)
                Spacer(minLength: 0)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.26), location: 0.0),
                            .init(color: Color.white.opacity(0.08), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
        )
    }
}

// MARK: - Liquid Glass Folder Card
private struct LocalFolderGlassCard: View {
    let folder: LocalMusicFolder
    let isScanning: Bool
    let onRescan: () -> Void
    let onRelocate: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var isHovered: Bool = false

    private var isMissing: Bool {
        folder.isMissing || !folder.existsOnDisk
    }

    var body: some View {
        HStack(spacing: 14) {
            GlassIconTile(
                symbol: isMissing ? "folder.badge.questionmark" : "folder.fill",
                tint: isMissing ? Color.orange : WalkmanTheme.silverLight,
                size: 44,
                cornerRadius: 11,
                iconSize: 18
            )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(folder.displayName)
                        .font(WalkmanFont.headline)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)

                    if isMissing {
                        Text("MISSING OR RENAMED")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.16))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.75)
                            )
                    } else {
                        Text("\(folder.trackCount) \(folder.trackCount == 1 ? "track" : "tracks")")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                            )
                    }

                    Text(ByteCountFormatter.string(fromByteCount: folder.totalBytes, countStyle: .file))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Text(isMissing ? "\(folder.path) (Location not found on disk)" : folder.path)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(isMissing ? Color.orange.opacity(0.88) : WalkmanTheme.silverMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(isMissing
                     ? "Status: Folder moved, renamed, or deleted in Finder"
                     : "Last scanned: \(folder.lastScanned.formatted(date: .abbreviated, time: .shortened))")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(isMissing ? Color.orange.opacity(0.75) : Color.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            // Actions (Liquid Glass Buttons)
            HStack(spacing: 6) {
                if isMissing {
                    Button(action: onRelocate) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 11, weight: .bold))
                            Text("Relocate...")
                                .font(WalkmanFont.subheadlineBold)
                        }
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .gold, cornerRadius: 15))
                    .help("Select new location for renamed or moved folder")
                } else {
                    Button(action: onRescan) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .disabled(isScanning)
                    .help("Rescan this folder")

                    Button(action: onReveal) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                    .help("Show in Finder")
                }

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.90))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .destructive, cornerRadius: 8))
                .help("Remove folder from library database")
            }
        }
        .padding(14)
        .liquidGlass(
            cornerRadius: 13,
            borderOpacity: isMissing ? 0.55 : 0.35,
            isSelected: false,
            isHovered: isHovered,
            tint: isMissing ? Color.orange : nil
        )
        .overlay(
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isHovered ? 0.16 : 0.10), location: 0.0),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 8)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
