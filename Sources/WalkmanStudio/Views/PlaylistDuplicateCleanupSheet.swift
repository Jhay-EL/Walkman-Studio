import SwiftUI

/// Interactive modal sheet for reviewing and selectively removing duplicate track entries from a playlist.
/// Operates exclusively on playlist sequence entries without touching audio files on storage.
public struct PlaylistDuplicateCleanupSheet: View {
    public let playlistName: String
    public let analysis: PlaylistDuplicateAnalysis
    public let onRemoveIndices: (Set<Int>) -> Void
    public let onDismiss: () -> Void

    @State private var strategy: PlaylistDedupeKeepStrategy
    @State private var selectedRemovalIndices: Set<Int>
    @Namespace private var strategyNamespace

    public init(
        playlistName: String,
        analysis: PlaylistDuplicateAnalysis,
        onRemoveIndices: @escaping (Set<Int>) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.playlistName = playlistName
        self.analysis = analysis
        self.onRemoveIndices = onRemoveIndices
        self.onDismiss = onDismiss

        let initialStrategy: PlaylistDedupeKeepStrategy = analysis.groups.contains(where: \.hasQualityDifference)
            ? .keepHighestQuality
            : .keepFirstOccurrence
        _strategy = State(initialValue: initialStrategy)
        _selectedRemovalIndices = State(initialValue: analysis.extraCopyIndices(strategy: initialStrategy))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
                .help("Close (Esc)")
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)

            headerView
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                safetyNoticeBanner
                strategyControlBar
                groupsScrollSection
            }
            .padding(.horizontal, 24)
            .layoutPriority(1)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 10)

            footerActions
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 660, idealWidth: 740, maxWidth: 940, minHeight: 500, idealHeight: 620, maxHeight: 860)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(sheetBorder)
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
        .onChange(of: strategy) { _, newStrategy in
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedRemovalIndices = analysis.extraCopyIndices(strategy: newStrategy)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)

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

                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.gold)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.85)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Review Playlist Duplicates")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(WalkmanTheme.silverLight)

                let groupCount = analysis.groups.count
                let extraCount = analysis.totalExtraCopies
                Text("\(playlistName) • \(groupCount) duplicate \(groupCount == 1 ? "group" : "groups") • \(extraCount) extra \(extraCount == 1 ? "entry" : "entries")")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var safetyNoticeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 90 / 255, green: 210 / 255, blue: 150 / 255))

            Text("Non-destructive playlist cleanup: removing duplicates updates only the .m3u8 / .m3u playlist file. Audio files on Walkman storage stay untouched.")
                .font(WalkmanFont.caption)
                .foregroundStyle(WalkmanTheme.silverLight.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var strategyControlBar: some View {
        HStack(spacing: 12) {
            Text("Keep Strategy")
                .font(WalkmanFont.captionBold)
                .foregroundStyle(WalkmanTheme.silverMuted)

            PlaylistKeepStrategySegmentedBar(
                strategy: $strategy,
                namespace: strategyNamespace
            )

            Spacer(minLength: 8)

            let recommended = analysis.extraCopyIndices(strategy: strategy)
            if selectedRemovalIndices != recommended {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedRemovalIndices = recommended
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Reset")
                            .font(WalkmanFont.captionBold)
                    }
                    .foregroundStyle(WalkmanTheme.hiResGold)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .subtle, cornerRadius: 15))
                .help("Reset selection to \(strategy.rawValue)")
            }
        }
    }

    // MARK: - Duplicate Groups List

    private var groupsScrollSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(analysis.groups) { group in
                    duplicateGroupCard(group)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func duplicateGroupCard(_ group: PlaylistDuplicateGroup) -> some View {
        let recommendedKeepIndex = group.keptIndex(for: strategy)
        let removalCountInGroup = group.entries.filter { selectedRemovalIndices.contains($0.index) }.count
        let keptCountInGroup = group.entries.count - removalCountInGroup

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayTitle)
                        .font(WalkmanFont.calloutBold)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)

                    if !group.displayArtist.isEmpty {
                        Text(group.displayArtist)
                            .font(WalkmanFont.caption)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                matchTypeBadge(group.matchType)

                if group.hasQualityDifference {
                    Text("Quality Diff")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WalkmanTheme.hiResGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WalkmanTheme.gold.opacity(0.16))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(WalkmanTheme.gold.opacity(0.35), lineWidth: 0.7))
                }

                Text(keptCountInGroup == 0 ? "All Removed" : "\(keptCountInGroup) kept • \(removalCountInGroup) remove")
                    .font(WalkmanFont.captionBold)
                    .foregroundStyle(keptCountInGroup == 0 ? Color.red.opacity(0.95) : WalkmanTheme.silverMuted)
            }

            VStack(spacing: 5) {
                ForEach(group.entries) { entry in
                    duplicateEntryRow(
                        entry: entry,
                        isRecommendedKeep: entry.index == recommendedKeepIndex
                    )
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.85)
        )
    }

    private func duplicateEntryRow(entry: PlaylistDuplicateEntry, isRecommendedKeep: Bool) -> some View {
        let isMarkedForRemoval = selectedRemovalIndices.contains(entry.index)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.14)) {
                if isMarkedForRemoval {
                    selectedRemovalIndices.remove(entry.index)
                } else {
                    selectedRemovalIndices.insert(entry.index)
                }
            }
        }) {
            HStack(spacing: 10) {
                Text("#\(entry.sequenceNumber)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 34, alignment: .leading)

                statusBadge(isMarkedForRemoval: isMarkedForRemoval)

                Text(entry.formatSummary)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(entry.qualityScore >= 5000 ? WalkmanTheme.hiResGold : WalkmanTheme.silverLight.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(entry.qualityScore >= 5000 ? WalkmanTheme.gold.opacity(0.14) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(entry.path)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isMarkedForRemoval ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
                    .strikethrough(isMarkedForRemoval, color: WalkmanTheme.silverMuted.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                if isRecommendedKeep {
                    Text(strategy == .keepHighestQuality ? "Best Quality" : "First")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WalkmanTheme.silverLight.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isMarkedForRemoval
                    ? Color(red: 225 / 255, green: 85 / 255, blue: 70 / 255).opacity(0.08)
                    : Color(red: 70 / 255, green: 195 / 255, blue: 130 / 255).opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isMarkedForRemoval
                            ? Color(red: 235 / 255, green: 100 / 255, blue: 85 / 255).opacity(0.28)
                            : Color(red: 85 / 255, green: 210 / 255, blue: 145 / 255).opacity(0.28),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(isMarkedForRemoval: Bool) -> some View {
        let color = isMarkedForRemoval
            ? Color(red: 245 / 255, green: 115 / 255, blue: 95 / 255)
            : Color(red: 95 / 255, green: 215 / 255, blue: 150 / 255)

        return HStack(spacing: 4) {
            Image(systemName: isMarkedForRemoval ? "minus.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10.5, weight: .bold))
            Text(isMarkedForRemoval ? "REMOVE" : "KEEP")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(color)
        .frame(width: 72, alignment: .leading)
    }

    private func matchTypeBadge(_ matchType: PlaylistDuplicateMatchType) -> some View {
        let isSameSong = matchType == .sameSong
        let tint: Color = isSameSong
            ? Color(red: 110 / 255, green: 195 / 255, blue: 255 / 255)
            : Color(red: 245 / 255, green: 178 / 255, blue: 64 / 255)

        return Text(matchType.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.7))
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 12) {
            if selectedRemovalIndices.isEmpty {
                Text("Select at least one REMOVE entry to clean up the playlist.")
                    .font(WalkmanFont.caption)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            } else {
                let count = selectedRemovalIndices.count
                Text("\(count) duplicate \(count == 1 ? "entry" : "entries") marked for playlist removal")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
            }

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Text("Cancel")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19))
            .keyboardShortcut(.cancelAction)

            Button(action: {
                onRemoveIndices(selectedRemovalIndices)
            }) {
                let count = selectedRemovalIndices.count
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .bold))
                    Text("Remove \(count) \(count == 1 ? "Duplicate" : "Duplicates")")
                        .font(WalkmanFont.calloutBold)
                }
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                .padding(.horizontal, 20)
                .frame(height: 38)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19))
            .keyboardShortcut(.defaultAction)
            .disabled(selectedRemovalIndices.isEmpty)
        }
    }

    // MARK: - Surface Styling

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

/// Liquid Glass segmented control bar for switching playlist deduplication keep strategies.
private struct PlaylistKeepStrategySegmentedBar: View {
    @Binding var strategy: PlaylistDedupeKeepStrategy
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PlaylistDedupeKeepStrategy.allCases) { option in
                PlaylistKeepStrategyPillButton(
                    option: option,
                    isSelected: strategy == option,
                    namespace: namespace,
                    onSelect: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            strategy = option
                        }
                    }
                )
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.85)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PlaylistKeepStrategyPillButton: View {
    let option: PlaylistDedupeKeepStrategy
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: option == .keepHighestQuality ? "sparkles" : "list.number")
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                Text(option.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(
                isSelected
                    ? Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255)
                    : (isHovered ? Color.white : WalkmanTheme.silverLight.opacity(0.82))
            )
            .background(
                ZStack {
                    if isSelected {
                        ZStack {
                            WalkmanTheme.hiResGoldGradient
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.42), location: 0.0),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 10)
                                Spacer(minLength: 0)
                            }
                        }
                        .clipShape(Capsule())
                        .shadow(color: WalkmanTheme.gold.opacity(0.32), radius: 5, x: 0, y: 2)
                        .matchedGeometryEffect(id: "activeKeepStrategyPill", in: namespace)
                    } else if isHovered {
                        Color.white.opacity(0.08)
                            .clipShape(Capsule())
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                isHovered = false
                NSCursor.pop()
            }
        }
    }
}
