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

            headerView

            // Content Section
            VStack(spacing: 12) {
                guardrailBanner
                detectedDuplicatesSection
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Divider()
                .overlay(Color.white.opacity(0.08))

            footerActions
        }
        .frame(width: 540)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(sheetBorder)
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            // Unthemed Liquid Glass Header Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)

                // Top specular light refraction sheen
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.28), location: 0.0),
                            .init(color: Color.white.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)
                    Spacer(minLength: 0)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverLight)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.40), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.6),
                                .init(color: Color.white.opacity(0.06), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Duplicate Tracks Detected")
                    .font(WalkmanFont.title)
                    .foregroundStyle(WalkmanTheme.silverLight)

                let subtitle = nonDuplicateCount > 0
                    ? "\(candidates.count) of \(totalCount) track(s) already exist in your \(targetDriveName) library."
                    : "All \(candidates.count) selected track(s) are already present in your \(targetDriveName) library."

                Text(subtitle)
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    // MARK: - Guardrail Banner
    private var guardrailBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverLight)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate Prevention Guardrail")
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(WalkmanTheme.silverLight)

                Text("To protect your Walkman storage and keep your playlists clean from duplicate audio files, you can choose to skip existing tracks.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            ZStack {
                Color.white.opacity(0.05)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.14), location: 0.0),
                            .init(color: Color.white.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    // MARK: - Detected Duplicates Section
    private var detectedDuplicatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DETECTED DUPLICATES (\(candidates.count))")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Spacer()
                if nonDuplicateCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(nonDuplicateCount) new tracks ready to add")
                            .font(WalkmanFont.subheadlineMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - Candidate Row
    private func candidateRow(_ candidate: DuplicateImportCandidate) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WalkmanTheme.silver)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(WalkmanFont.bodyMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(candidate.artist.isEmpty ? "Unknown Artist" : candidate.artist)
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .lineLimit(1)

                    Text("•")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(Color.white.opacity(0.25))

                    Text(candidate.matchReason)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                        )
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(candidate.url.pathExtension.uppercased())
                .font(WalkmanFont.badge)
                .foregroundStyle(WalkmanTheme.silverLight)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - Footer Actions
    private var footerActions: some View {
        HStack(alignment: .center, spacing: 12) {
            // Cancel
            Button(action: onCancel) {
                Text("Cancel")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .keyboardShortcut(.cancelAction)

            Spacer()

            // Add All Anyway
            if nonDuplicateCount > 0 {
                Button(action: onAddAll) {
                    Text("Add All Anyway")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            } else {
                Button(action: onAddAll) {
                    Text("Add All Anyway")
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
                .keyboardShortcut(.defaultAction)
            }

            // Skip Duplicates (Primary Button when duplicates can be skipped)
            if nonDuplicateCount > 0 {
                Button(action: onSkipDuplicates) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Skip Duplicates")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Sheet Background & Border
    private var sheetBackground: some View {
        ZStack {
            WalkmanTheme.card.opacity(0.92)
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.22), location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }

    private var sheetBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.35), location: 0.0),
                        .init(color: Color.white.opacity(0.12), location: 0.5),
                        .init(color: Color.white.opacity(0.06), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
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
                    .stroke(Color.white.opacity(isHovered ? 0.28 : 0.12), lineWidth: 0.8)
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
