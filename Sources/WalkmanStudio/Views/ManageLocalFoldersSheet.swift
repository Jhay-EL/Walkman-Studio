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
            // Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.08))

            // Content
            if localService.folders.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                folderListView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 680, height: 560)
        .background(WalkmanTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
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
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Manage Local Folders")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(localService.folders.count) Folders")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }

                Text("Configure local folders indexed into Walkman Studio's database (~/.walkman_local_library.db)")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer()

            // Add Folder Button
            Button(action: openFolderPicker) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add Folder...")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(WalkmanTheme.silverGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .help("Select music directories from your Mac or external drive")

            // Rescan All Button
            Button(action: { localService.rescanAllFolders() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(localService.isScanning ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight)
                    .rotationEffect(localService.isScanning ? .degrees(360) : .zero)
                    .animation(localService.isScanning ? .linear(duration: 1.0).repeatForever(autoreverses: false) : .default, value: localService.isScanning)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .disabled(localService.isScanning)
            .help("Rescan all local music folders for changes")

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    // MARK: - Folder List View
    private var folderListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 10) {
                ForEach(localService.folders) { folder in
                    folderRowView(folder)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Folder Row View
    private func folderRowView(_ folder: LocalMusicFolder) -> some View {
        HStack(spacing: 14) {
            // Folder Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(WalkmanTheme.silver)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(folder.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text("\(folder.trackCount) tracks")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())

                    Text(ByteCountFormatter.string(fromByteCount: folder.totalBytes, countStyle: .file))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Text(folder.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Last scanned: \(folder.lastScanned.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.40))
            }

            Spacer(minLength: 8)

            // Actions
            HStack(spacing: 6) {
                // Rescan
                Button(action: { localService.rescanFolder(url: folder.url) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Rescan this folder")

                // Reveal in Finder
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Show in Finder")

                // Remove
                Button(action: {
                    self.folderToRemove = folder
                    self.showRemoveConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Remove folder from library database")
            }
        }
        .padding(12)
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 72, height: 72)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            VStack(spacing: 6) {
                Text("No Local Music Folders Added")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text("Add folders from your Mac or external drive to index and manage music in Walkman Studio without requiring a connected Walkman.")
                    .font(.system(size: 12))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: openFolderPicker) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Music Folder...")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(WalkmanTheme.silverGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("SQLite Database: ~/.walkman_local_library.db")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }

            Spacer()

            Text("\(localService.tracks.count) total tracks indexed")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(WalkmanTheme.silverLight)

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
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
}
