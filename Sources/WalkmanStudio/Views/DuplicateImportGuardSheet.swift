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

    @State private var expandedCandidateIds: Set<String> = []
    @State private var isSubmitting: Bool = false

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
            .padding(.top, 14)
            .padding(.horizontal, 20)

            headerView

            // Content Section
            VStack(spacing: 12) {
                guardrailBanner
                detectedDuplicatesSection
            }
            .padding(.horizontal, 24)
            .layoutPriority(1)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 10)

            footerActions
        }
        .frame(minWidth: 620, idealWidth: 700, maxWidth: 920, minHeight: 480, idealHeight: 580, maxHeight: 860)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("DETECTED DUPLICATES (\(candidates.count))")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer()

                if nonDuplicateCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(nonDuplicateCount) ready to add")
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

                // Expand All / Collapse Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        if expandedCandidateIds.count == candidates.count {
                            expandedCandidateIds.removeAll()
                        } else {
                            expandedCandidateIds = Set(candidates.map { $0.id })
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: expandedCandidateIds.count == candidates.count ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(expandedCandidateIds.count == candidates.count ? "Collapse Details" : "Expand All Details")
                            .font(WalkmanFont.subheadlineMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 2)
            }
            .frame(minHeight: 180, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func isCandidateExpanded(_ candidate: DuplicateImportCandidate) -> Bool {
        expandedCandidateIds.contains(candidate.id)
    }

    private func toggleCandidateExpanded(_ candidate: DuplicateImportCandidate) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            if expandedCandidateIds.contains(candidate.id) {
                expandedCandidateIds.remove(candidate.id)
            } else {
                expandedCandidateIds.insert(candidate.id)
            }
        }
    }

    // MARK: - Candidate Row
    private func candidateRow(_ candidate: DuplicateImportCandidate) -> some View {
        let isExpanded = isCandidateExpanded(candidate)

        return VStack(alignment: .leading, spacing: 7) {
            // Source / Incoming File Row (Clickable to expand/collapse)
            Button(action: {
                toggleCandidateExpanded(candidate)
            }) {
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

                            if !candidate.album.isEmpty {
                                Text("•")
                                    .font(WalkmanFont.caption)
                                    .foregroundStyle(Color.white.opacity(0.25))

                                Text(candidate.album)
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.8))
                                    .lineLimit(1)
                            }
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

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.leading, 2)
                }
            }
            .buttonStyle(.plain)

            // Destination Duplicate Conflict Callout
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.orange)

                HStack(spacing: 5) {
                    let driveLabel = candidate.destinationDriveName.isEmpty ? targetDriveName : candidate.destinationDriveName
                    Text(driveLabel)
                        .font(WalkmanFont.badge)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 0.7)
                        )

                    Text(candidate.matchReason)
                        .font(WalkmanFont.caption)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(isExpanded ? 3 : 1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if let quality = candidate.destinationQualityDescription {
                    Text(quality)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.orange.opacity(0.20), lineWidth: 0.75)
            )

            // Expanded Comparison Panel (When clicked)
            if isExpanded {
                candidateExpandedDetailsView(candidate)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(isExpanded ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(isExpanded ? 0.16 : 0.06), lineWidth: 0.8)
        )
    }

    // MARK: - Expanded Details Comparison View
    private func candidateExpandedDetailsView(_ candidate: DuplicateImportCandidate) -> some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                // Wide layout: 2 side-by-side columns
                HStack(alignment: .top, spacing: 8) {
                    incomingDetailsCard(candidate)
                    existingDetailsCard(candidate)
                }

                // Compact layout: stacked vertically
                VStack(spacing: 8) {
                    incomingDetailsCard(candidate)
                    existingDetailsCard(candidate)
                }
            }

            // Resolution Advice
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(WalkmanTheme.hiResGold)

                Text("Skipping will keep the existing file on \(candidate.destinationDriveName) and avoid redundant storage usage.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.top, 4)
    }

    private func incomingDetailsCard(_ candidate: DuplicateImportCandidate) -> some View {
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: candidate.url.path)[.size] as? Int64) ?? 0
        let formattedSize = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        let formattedDuration = candidate.durationSeconds > 0 ? WalkmanEngine.formatDuration(candidate.durationSeconds) : nil

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WalkmanTheme.silver)
                Text("INCOMING SOURCE")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Spacer()
                Text(candidate.url.pathExtension.uppercased())
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            Text(candidate.title)
                .font(WalkmanFont.bodyMedium)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let dur = formattedDuration {
                    Text(dur)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                if sizeBytes > 0 {
                    Text("•")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text(formattedSize)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }

            Text(candidate.url.path)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help(candidate.url.path)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 0.75))
    }

    private func existingDetailsCard(_ candidate: DuplicateImportCandidate) -> some View {
        let track = candidate.matchingWalkmanTrack
        let formattedSize = track != nil && track!.sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: track!.sizeBytes, countStyle: .file) : nil
        let formattedDuration = track != nil && track!.durationSeconds > 0 ? WalkmanEngine.formatDuration(track!.durationSeconds) : nil
        let driveName = candidate.destinationDriveName.isEmpty ? targetDriveName : candidate.destinationDriveName
        let relPath = candidate.destinationRelativePath ?? track?.relativePath ?? candidate.url.lastPathComponent

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.orange)
                Text("ON \(driveName.uppercased())")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(Color.orange.opacity(0.9))
                Spacer()
                if let qual = candidate.destinationQualityDescription {
                    Text(qual)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }

            Text(track?.title.isEmpty == false ? track!.title : candidate.title)
                .font(WalkmanFont.bodyMedium)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let dur = formattedDuration {
                    Text(dur)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
                if let sz = formattedSize {
                    Text("•")
                        .font(WalkmanFont.caption)
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text(sz)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }

            Text(relPath)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help(track?.fullPath ?? relPath)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.18), lineWidth: 0.75))
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
            .disabled(isSubmitting)

            Spacer()

            // Add All Anyway
            if nonDuplicateCount > 0 {
                Button(action: {
                    isSubmitting = true
                    onAddAll()
                }) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Add All Anyway")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
                .disabled(isSubmitting)
            } else {
                Button(action: {
                    isSubmitting = true
                    onAddAll()
                }) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Add All Anyway")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }

            // Skip Duplicates (Primary Button when duplicates can be skipped)
            if nonDuplicateCount > 0 {
                Button(action: {
                    isSubmitting = true
                    onSkipDuplicates()
                }) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text("Skip Duplicates")
                            .font(WalkmanFont.calloutBold)
                    }
                    .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
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
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.arrow.set()
            }
        }
    }
}
