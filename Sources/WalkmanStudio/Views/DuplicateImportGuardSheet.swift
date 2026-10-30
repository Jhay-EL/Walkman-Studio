import SwiftUI
import AppKit

// MARK: - Duplicate Import Guard Sheet
public struct DuplicateImportGuardSheet: View {
    let candidates: [DuplicateImportCandidate]
    let nonDuplicateCount: Int
    let totalCount: Int
    let targetDriveName: String
    let onSkipDuplicates: () -> Void
    let onAddAll: () -> Void
    let onCancel: () -> Void

    @State private var isPrimaryHovered: Bool = false
    @State private var isSecondaryHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    public init(
        candidates: [DuplicateImportCandidate],
        nonDuplicateCount: Int,
        totalCount: Int,
        targetDriveName: String = "Walkman",
        onSkipDuplicates: @escaping () -> Void,
        onAddAll: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.nonDuplicateCount = nonDuplicateCount
        self.totalCount = totalCount
        self.targetDriveName = targetDriveName
        self.onSkipDuplicates = onSkipDuplicates
        self.onAddAll = onAddAll
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Dismiss Bar
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
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

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
                .shadow(color: Color.orange.opacity(0.35), radius: 8, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Duplicate Tracks Detected")
                        .font(WalkmanFont.title)
                        .foregroundStyle(.white)

                    Text(nonDuplicateCount > 0
                         ? "\(candidates.count) of \(totalCount) track(s) already exist in your \(targetDriveName) library."
                         : "All \(candidates.count) selected track(s) are already present in your \(targetDriveName) library.")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            // Content Section
            VStack(spacing: 12) {
                // Info Banner
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.orange)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duplicate Prevention Guardrail")
                            .font(WalkmanFont.calloutBold)
                            .foregroundStyle(.white)

                        Text("To protect your Walkman storage and keep your playlists clean from duplicate audio files, you can choose to skip existing tracks.")
                            .font(WalkmanFont.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                )

                // List of Detected Duplicates
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DETECTED DUPLICATES (\(candidates.count))")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if nonDuplicateCount > 0 {
                            Text("\(nonDuplicateCount) new tracks ready to add")
                                .font(WalkmanFont.caption)
                                .foregroundStyle(Color.green)
                        }
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(candidates) { candidate in
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.orange.opacity(0.15))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.orange)
                                            )
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.title)
                                            .font(WalkmanFont.bodyMedium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            Text(candidate.artist.isEmpty ? "Unknown Artist" : candidate.artist)
                                                .font(WalkmanFont.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)

                                            Text("•")
                                                .font(WalkmanFont.caption)
                                                .foregroundStyle(.tertiary)

                                            Text(candidate.matchReason)
                                                .font(WalkmanFont.caption)
                                                .foregroundStyle(.orange)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Text(candidate.url.pathExtension.uppercased())
                                        .font(WalkmanFont.badge)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer Actions
            HStack(alignment: .center, spacing: 10) {
                // Cancel
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isCancelHovered ? 0.25 : 0.12), lineWidth: 0.85)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .onHover { isCancelHovered = $0 }

                Spacer()

                // Add All Anyway
                Button(action: onAddAll) {
                    Text("Add All Anyway (\(totalCount))")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(isSecondaryHovered ? 0.14 : 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(isSecondaryHovered ? 0.30 : 0.15), lineWidth: 0.85)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isSecondaryHovered = $0 }

                // Skip Duplicates (Primary Button)
                if nonDuplicateCount > 0 {
                    Button(action: onSkipDuplicates) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Skip Duplicates (Add \(nonDuplicateCount) New)")
                                .font(WalkmanFont.calloutBold)
                        }
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8.5)
                        .background(WalkmanTheme.silverGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                        )
                        .scaleEffect(isPrimaryHovered ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .onHover { isPrimaryHovered = $0 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 540)
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
