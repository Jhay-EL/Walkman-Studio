import SwiftUI

public struct CleanEjectSheet: View {
    let drives: [WalkmanDrive]
    let onEjectComplete: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedDrivePath: String = "ALL"
    @State private var isCleaning: Bool = false
    @State private var isFinished: Bool = false
    @State private var statusMessage: String = "Ready to purge macOS dotfiles and safely eject."
    @State private var deletedFiles: [String] = []
    @State private var unmountResults: [String: Bool] = [:]
    
    public init(drives: [WalkmanDrive], onEjectComplete: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.drives = drives
        self.onEjectComplete = onEjectComplete
        self.onDismiss = onDismiss
    }
    
    private func runCleanAndEject() {
        isCleaning = true
        statusMessage = "Executing dot_clean -m & scanning for shadow files..."
        
        Task {
            var allDeleted: [String] = []
            var targetDrives: [WalkmanDrive] = []
            
            if selectedDrivePath == "ALL" {
                targetDrives = drives
            } else if let match = drives.first(where: { $0.mountPoint == selectedDrivePath }) {
                targetDrives = [match]
            }
            
            for drive in targetDrives {
                await MainActor.run {
                    statusMessage = "Purging shadow files on \(drive.name)..."
                }
                let cleanResult = await WalkmanEngine.shared.cleanGhostFiles(mountPoint: drive.mountPoint)
                allDeleted.append(contentsOf: cleanResult.deleted)
                
                await MainActor.run {
                    statusMessage = "Unmounting \(drive.name)..."
                }
                let unmountResult = await WalkmanEngine.shared.unmountDrive(mountPoint: drive.mountPoint)
                await MainActor.run {
                    unmountResults[drive.name] = unmountResult.success
                }
            }
            
            await MainActor.run {
                self.deletedFiles = allDeleted
                self.isCleaning = false
                self.isFinished = true
                self.statusMessage = "All volumes cleaned and safely ejected."
                self.onEjectComplete()
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isFinished ? Color.green.opacity(0.15) : Color.white.opacity(0.10))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isFinished ? "checkmark.circle.fill" : "eject.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isFinished ? Color.green : WalkmanTheme.silver)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isFinished ? "Safe to Disconnect" : "Clean macOS Junk & Safe Eject")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Complies with Sony NW-A55L FAT32/exFAT hardware rules")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if !isFinished && !isCleaning {
                // Volume Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("SELECT VOLUMES TO EJECT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    
                    Picker("", selection: $selectedDrivePath) {
                        Text("All Walkman Drives (\(drives.count) Volumes)").tag("ALL")
                        ForEach(drives) { d in
                            Text(d.name).tag(d.mountPoint)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 10)
                
                // Explanatory checklist
                VStack(alignment: .leading, spacing: 8) {
                    Text("AUTOMATIC ACTIONS PERFORMED:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WalkmanTheme.silver)
                        Text("Executes native macOS `dot_clean -m` to merge AppleDouble resource forks")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WalkmanTheme.silver)
                        Text("Deletes hidden .DS_Store, .Spotlight-V100, .Trashes, and ._* ghost files")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WalkmanTheme.silver)
                        Text("Unmounts safely via diskutil so device does not trigger corrupted filesystem errors")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 10)
            } else {
                // Progress / Results View
                VStack(spacing: 14) {
                    if isCleaning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(WalkmanTheme.silver)
                            .scaleEffect(1.2)
                            .padding(.top, 10)
                    }
                    
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFinished ? Color.green : .white)
                    
                    if isFinished {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("CLEANUP REPORT")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(deletedFiles.count) Ghost Files Removed")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                            
                            ForEach(Array(unmountResults.keys), id: \.self) { driveName in
                                HStack {
                                    Text(driveName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    let ok = unmountResults[driveName] ?? false
                                    Text(ok ? "Safely Unmounted" : "Failed to unmount")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ok ? Color.green : Color.red)
                                }
                            }
                        }
                        .padding(14)
                        .liquidGlass(cornerRadius: 10)
                    }
                }
                .padding(10)
            }
            
            // Bottom Buttons
            HStack(spacing: 12) {
                Spacer()
                
                if !isCleaning && !isFinished {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    
                    Button(action: runCleanAndEject) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.slash")
                            Text("Purge Junk & Eject")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else if isFinished {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(WalkmanTheme.background)
    }
}
