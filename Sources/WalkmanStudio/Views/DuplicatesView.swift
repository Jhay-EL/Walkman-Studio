import SwiftUI
import AppKit

public enum DuplicateSortOption: String, CaseIterable, Identifiable {
    case recoverableSpace = "Space Recoverable"
    case titleAZ = "Song Title (A-Z)"
    case artistAZ = "Artist (A-Z)"
    case copyCount = "Most Copies"

    public var id: String { rawValue }
}

public struct DuplicatesView: View {
    let drives: [WalkmanDrive]
    var onEditTrack: ((Track) -> Void)? = nil
    var onLibraryChanged: (() -> Void)? = nil

    @ObservedObject private var finder = DuplicateFinderService.shared
    @ObservedObject private var player = AudioPlayerService.shared

    @State private var selectedFilter: DuplicateFilter = .sameDrive
    @State private var sortOption: DuplicateSortOption = .recoverableSpace

    // Active modal action sheet state
    @State private var activeModalAction: DuplicateModalAction? = nil
    @State private var isProcessing: Bool = false

    public init(
        drives: [WalkmanDrive],
        onEditTrack: ((Track) -> Void)? = nil,
        onLibraryChanged: (() -> Void)? = nil
    ) {
        self.drives = drives
        self.onEditTrack = onEditTrack
        self.onLibraryChanged = onLibraryChanged
    }

    private var filteredGroups: [DuplicateGroup] {
        var list = finder.duplicateGroups.filter { group in
            switch selectedFilter {
            case .sameDrive:
                return true
            case .qualityDifference:
                return group.hasQualityDifference
            }
        }

        // Sort
        switch sortOption {
        case .recoverableSpace:
            list.sort { $0.recoverableBytes > $1.recoverableBytes }
        case .titleAZ:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artistAZ:
            list.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .copyCount:
            list.sort { $0.items.count > $1.items.count }
        }

        return list
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            let gb = Double(bytes) / Double(1024 * 1024 * 1024)
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / Double(1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
    }

    private func reasonColor(_ reason: DuplicateMatchReason) -> Color {
        switch reason {
        case .exactFile:
            return Color.green
        case .bitExactAudio:
            return Color.teal
        case .isrcMatch:
            return WalkmanTheme.hiResGold
        case .sameAlbum:
            return Color.blue
        case .strayCopy:
            return Color.purple
        case .crossDrive:
            return WalkmanTheme.hiResGold
        case .crossAlbum:
            return Color.orange
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Header Bar
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.8)

            // Subheader: Filters, Search & Sorting
            controlsBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.clear)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.8)

            // Main Content Area
            if finder.detectionScope == .crossAlbum && !finder.duplicateGroups.isEmpty && !finder.isScanning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 13))
                    Text("Cross-Album Mode: Tracks appearing across different releases (Studio Albums, Singles, Greatest Hits, Compilations) are displayed. Deleting tracks may result in incomplete albums.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(WalkmanTheme.silver)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            if finder.isScanning {
                scanningView
            } else if finder.duplicateGroups.isEmpty {
                emptyLibraryView
            } else if filteredGroups.isEmpty {
                emptyFilteredView
            } else {
                duplicatesListView
            }
        }
        .background(WalkmanTheme.background)
        .task {
            if finder.duplicateGroups.isEmpty && !finder.isScanning {
                _ = await finder.scanForDuplicates(drives: drives)
            }
        }
        .sheet(item: $activeModalAction) { action in
            DuplicateResolutionSheet(
                action: action,
                onConfirm: {
                    switch action {
                    case .deleteSingle(let item):
                        deleteItem(item)
                    case .keepSingle(let item, let group):
                        keepItem(item, in: group)
                    case .batchQualityResolve(let groups):
                        resolveBatchQuality(groups: groups)
                    }
                    activeModalAction = nil
                },
                onCancel: {
                    activeModalAction = nil
                }
            )
        }
    }

    // MARK: - Header
    private var headerView: some View {
        ViewThatFits(in: .horizontal) {
            // Wide layout: title on left, metrics + rescan on right
            HStack(alignment: .center, spacing: 18) {
                headerTitleGroup

                Spacer(minLength: 16)

                headerMetricsGroup
            }

            // Compact layout for narrow windows: title stacked above metrics
            VStack(alignment: .leading, spacing: 12) {
                headerTitleGroup

                HStack {
                    headerMetricsGroup
                    Spacer()
                }
            }
        }
    }

    private var headerTitleGroup: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)

                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WalkmanTheme.silver)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Duplicate Tracks")
                        .font(WalkmanFont.title1)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !finder.duplicateGroups.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Text(finder.duplicateGroups.count == 1 ? "1 Group" : "\(finder.duplicateGroups.count) Groups")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            ZStack {
                                Color.white.opacity(0.06)
                                VStack(spacing: 0) {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.12), location: 0.0),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 5)
                                    Spacer(minLength: 0)
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                }

                Text("Detect and clean redundant duplicate tracks on the same storage.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var headerMetricsGroup: some View {
        HStack(spacing: 10) {
            // Recoverable space metric
            MetricPill(
                icon: "internaldrive.badge.arrow.down",
                label: "Recoverable",
                value: formatBytes(finder.totalRecoverableBytes),
                accentColor: finder.totalRecoverableBytes > 0 ? Color.green : WalkmanTheme.silverMuted
            )

            // Rescan Button
            Button(action: {
                Task {
                    _ = await finder.scanForDuplicates(drives: drives)
                }
            }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(finder.isScanning ? 360 : 0))
                        .animation(finder.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: finder.isScanning)
                    Text(finder.isScanning ? "Scanning..." : "Rescan")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(height: 38)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .gold, cornerRadius: 19))
            .disabled(finder.isScanning)
            .opacity(finder.isScanning ? 0.6 : 1.0)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Controls Components
    private var filterItems: [DuplicateFilterItem] {
        [
            DuplicateFilterItem(
                filter: .sameDrive,
                title: "Same Storage",
                count: finder.duplicateGroups.count,
                tint: nil
            ),
            DuplicateFilterItem(
                filter: .qualityDifference,
                title: "Quality Diff",
                count: finder.qualityDifferenceCount,
                tint: Color.cyan
            )
        ]
    }

    private var scopeSegmentedBar: some View {
        DuplicateScopeSegmentedBarView(
            selectedScope: $finder.detectionScope,
            onSelectScope: { scope in
                finder.detectionScope = scope
            }
        )
    }

    private var filterSegmentedBar: some View {
        DuplicateFilterSegmentedBarView(
            items: filterItems,
            selectedFilter: $selectedFilter,
            onSelectFilter: { filter in
                selectedFilter = filter
            }
        )
    }

    private var sortMenu: some View {
        DuplicateSortMenuButton(
            sortOption: $sortOption
        )
    }

    @ViewBuilder
    private var autoResolveQualityButton: some View {
        let qualityGroups = finder.duplicateGroups.filter { $0.hasQualityDifference }
        if !qualityGroups.isEmpty {
            DuplicateAutoResolveButton(
                action: {
                    activeModalAction = .batchQualityResolve(groups: qualityGroups)
                }
            )
        }
    }

    // MARK: - Controls Bar (Liquid Glass Segmented Controls, Sort, Action)
    private var controlsBar: some View {
        ViewThatFits(in: .horizontal) {
            // Wide single-row layout
            HStack(spacing: 10) {
                scopeSegmentedBar

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 22)

                filterSegmentedBar

                Spacer(minLength: 8)

                sortMenu

                autoResolveQualityButton
            }

            // Responsive two-row layout for narrower windows
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Scopes & Filter Segmented Bars
                HStack(spacing: 10) {
                    scopeSegmentedBar

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 22)

                    ScrollView(.horizontal, showsIndicators: false) {
                        filterSegmentedBar
                    }

                    Spacer(minLength: 0)
                }

                // Row 2: Sort Menu + Auto-Resolve Quality Action
                HStack(spacing: 10) {
                    Spacer()

                    sortMenu

                    autoResolveQualityButton
                }
            }
        }
    }

    // MARK: - Duplicates List View
    private var duplicatesListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredGroups) { group in
                    DuplicateGroupCard(
                        group: group,
                        onPreview: { item in
                            if player.currentTrack?.fullPath == item.track.fullPath && player.isPlaying {
                                player.pause()
                            } else {
                                player.play(track: item.track, in: [item.track])
                            }
                        },
                        onKeepOnly: { item in
                            activeModalAction = .keepSingle(item: item, group: group)
                        },
                        onDeleteSingle: { item in
                            activeModalAction = .deleteSingle(item: item)
                        },
                        onRevealInFinder: { item in
                            NSWorkspace.shared.selectFile(item.track.fullPath, inFileViewerRootedAtPath: "")
                        },
                        onEditMetadata: { item in
                            onEditTrack?(item.track)
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 88)
        }
    }

    // MARK: - Empty & Loading States
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
                .tint(WalkmanTheme.silver)

            VStack(spacing: 6) {
                Text("Analyzing Library for Duplicates")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)

                Text("Comparing audio tags, duration, and file sizes across Internal Flash and MicroSD expansion...")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: 6) {
                Text("No Duplicates Found")
                    .font(WalkmanFont.title2)
                    .foregroundStyle(.white)

                Text("Your Sony Walkman library is completely clean. No duplicate tracks detected across Internal Storage and MicroSD expansion.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilteredView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Duplicates Match Current Filter")
                .font(WalkmanFont.title3)
                .foregroundStyle(.white)

            Text("Try selecting a different filter tab above.")
                .font(WalkmanFont.callout)
                .foregroundStyle(.secondary)

            Button("Reset Filters") {
                selectedFilter = .all
            }
            .font(WalkmanFont.calloutMedium)
            .foregroundStyle(WalkmanTheme.silverLight)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func deleteItem(_ item: DuplicateTrackItem) {
        Task {
            _ = await finder.deleteDuplicateItem(item)
            onLibraryChanged?()
        }
    }

    private func keepItem(_ item: DuplicateTrackItem, in group: DuplicateGroup) {
        Task {
            await finder.keepOnly(item: item, in: group)
            onLibraryChanged?()
        }
    }

    private func resolveAllQualityMismatches() {
        let qualityGroups = finder.duplicateGroups.filter { $0.hasQualityDifference }
        resolveBatchQuality(groups: qualityGroups)
    }

    private func resolveBatchQuality(groups: [DuplicateGroup]) {
        Task {
            for group in groups {
                if let best = group.suggestedItemToKeep {
                    await finder.keepOnly(item: best, in: group)
                }
            }
            onLibraryChanged?()
        }
    }
}

// MARK: - Duplicate Group Card
private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let onPreview: (DuplicateTrackItem) -> Void
    let onKeepOnly: (DuplicateTrackItem) -> Void
    let onDeleteSingle: (DuplicateTrackItem) -> Void
    let onRevealInFinder: (DuplicateTrackItem) -> Void
    let onEditMetadata: (DuplicateTrackItem) -> Void

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            let gb = Double(bytes) / Double(1024 * 1024 * 1024)
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / Double(1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
    }

    private func reasonColor(_ reason: DuplicateMatchReason) -> Color {
        switch reason {
        case .exactFile:
            return Color(red: 120/255, green: 230/255, blue: 150/255)
        case .bitExactAudio:
            return Color(red: 100/255, green: 230/255, blue: 220/255)
        case .isrcMatch:
            return WalkmanTheme.hiResGold
        case .sameAlbum:
            return Color(red: 130/255, green: 200/255, blue: 255/255)
        case .strayCopy:
            return Color(red: 205/255, green: 165/255, blue: 255/255)
        case .crossDrive:
            return WalkmanTheme.hiResGold
        case .crossAlbum:
            return Color(red: 255/255, green: 180/255, blue: 100/255)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card Header (Responsive Wide & Compact layouts)
            ViewThatFits(in: .horizontal) {
                // Wide single-row layout
                HStack(spacing: 12) {
                    groupThumbnailAndTitle
                    Spacer(minLength: 8)
                    groupTagsAndAction
                }

                // Compact two-row layout
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        groupThumbnailAndTitle
                        Spacer(minLength: 8)
                        groupCopyCountView
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        groupBadgesAndAction
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Color.white.opacity(0.025)
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.14), location: 0.0),
                                .init(color: Color.white.opacity(0.02), location: 0.5),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 8)
                        Spacer(minLength: 0)
                    }
                }
            )

            Divider()
                .overlay(Color.white.opacity(0.07))

            // Card Items Table
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    DuplicateTrackRow(
                        item: item,
                        isSuggested: item.id == group.suggestedItemToKeep?.id,
                        groupCount: group.items.count,
                        onPreview: { onPreview(item) },
                        onKeepThis: { onKeepOnly(item) },
                        onDelete: { onDeleteSingle(item) },
                        onRevealInFinder: { onRevealInFinder(item) },
                        onEditMetadata: { onEditMetadata(item) }
                    )

                    if index < group.items.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.04))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.85)
                    .background(.ultraThinMaterial)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0.0),
                            .init(color: Color.white.opacity(0.03), location: 0.5),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.24), location: 0.0),
                            .init(color: Color.white.opacity(0.10), location: 0.5),
                            .init(color: Color.white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
    }

    private var groupThumbnailAndTitle: some View {
        HStack(spacing: 12) {
            if let firstTrack = group.items.first?.track {
                TrackCoverThumbnail(track: firstTrack, size: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1.5)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(WalkmanFont.headline)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .lineLimit(1)

                    if group.items.contains(where: { $0.isHiRes }) {
                        HiResBadge()
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(group.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
        }
    }

    private var groupCopyCountView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(group.items.count) copies")
                .font(WalkmanFont.pillCounter)
                .foregroundStyle(WalkmanTheme.silverLight)
                .lineLimit(1)
            if group.recoverableBytes > 0 {
                Text("+\(formatBytes(group.recoverableBytes)) freeable")
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(Color.green.opacity(0.95))
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var groupBadgesAndAction: some View {
        HStack(spacing: 8) {
            // Match Reason Badge
            reasonBadge(reason: group.matchReason)

            if group.isCrossDrive && group.matchReason != .crossDrive {
                crossDriveBadge
            }

            if group.hasQualityDifference {
                qualityMismatchBadge
            }

            // Quick Header Action: "Keep Best Quality" or "Keep SD Card Copy"
            if let best = group.suggestedItemToKeep {
                Button(action: { onKeepOnly(best) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        if group.hasQualityDifference {
                            Text("Keep Best Quality")
                        } else if group.isCrossDrive {
                            Text("Keep on SD Card")
                        } else {
                            Text("Keep Best Copy")
                        }
                    }
                    .font(WalkmanFont.calloutBold)
                    .lineLimit(1)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 8))
                .help("Keeps this recommended copy and deletes all other duplicate copies in this group")
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func reasonBadge(reason: DuplicateMatchReason) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: reason.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(reason.rawValue)
                .font(WalkmanFont.badge)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            ZStack {
                reasonColor(reason).opacity(0.14)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.22), location: 0.0),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5.5)
                    Spacer(minLength: 0)
                }
            }
        )
        .foregroundStyle(reasonColor(reason))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: reasonColor(reason).opacity(0.40), location: 0.0),
                            .init(color: reasonColor(reason).opacity(0.15), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var crossDriveBadge: some View {
        HStack(spacing: 4.5) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
            Text("Cross-Drive")
                .font(WalkmanFont.badge)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            ZStack {
                WalkmanTheme.hiResGold.opacity(0.14)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.22), location: 0.0),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5.5)
                    Spacer(minLength: 0)
                }
            }
        )
        .foregroundStyle(WalkmanTheme.hiResGold)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: WalkmanTheme.hiResGold.opacity(0.40), location: 0.0),
                            .init(color: WalkmanTheme.hiResGold.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var qualityMismatchBadge: some View {
        HStack(spacing: 4.5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text("Quality Mismatch")
                .font(WalkmanFont.badge)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            ZStack {
                Color.cyan.opacity(0.14)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.22), location: 0.0),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5.5)
                    Spacer(minLength: 0)
                }
            }
        )
        .foregroundStyle(Color.cyan)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.cyan.opacity(0.40), location: 0.0),
                            .init(color: Color.cyan.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var groupTagsAndAction: some View {
        HStack(spacing: 8) {
            groupBadgesAndAction
            groupCopyCountView
                .padding(.leading, 4)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Duplicate Track Row
private struct DuplicateTrackRow: View {
    let item: DuplicateTrackItem
    let isSuggested: Bool
    let groupCount: Int
    let onPreview: () -> Void
    let onKeepThis: () -> Void
    let onDelete: () -> Void
    let onRevealInFinder: () -> Void
    let onEditMetadata: () -> Void

    @ObservedObject private var player = AudioPlayerService.shared
    @State private var isHovered: Bool = false

    private var isPlayingThis: Bool {
        player.currentTrack?.fullPath == item.track.fullPath && player.isPlaying
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / Double(1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play Preview Button (28×28 Liquid Glass Circle)
            Button(action: onPreview) {
                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGold : (isHovered ? .white : WalkmanTheme.silverLight.opacity(0.85)))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
            .help(isPlayingThis ? "Pause preview" : "Preview playback")

            // Storage Drive Badge (24pt Liquid Glass Capsule)
            storageBadge

            // Specs (Format, Bitrate, Resolution)
            HStack(spacing: 6) {
                Text(item.track.format.uppercased())
                    .font(WalkmanFont.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )

                if item.isHiRes {
                    Text("\(item.track.bitsPerSample)b/\(item.track.sampleRate / 1000)kHz")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.hiResGold)
                } else if item.track.bitrateKbps > 0 {
                    Text("\(item.track.bitrateKbps) kbps")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }

                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.20))

                Text(formatBytes(item.track.sizeBytes))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.20))

                Text(formatDuration(item.track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .fixedSize(horizontal: true, vertical: false)

            // Track Title & Relative Path
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title.isEmpty ? (item.track.album.isEmpty ? "Unknown Track" : item.track.album) : item.track.title)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .lineLimit(1)

                Text(item.track.relativePath)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Recommended Tag (24pt Liquid Glass Capsule)
            if isSuggested {
                HStack(spacing: 4.5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Recommended")
                        .font(WalkmanFont.badge)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    ZStack {
                        Color.green.opacity(0.14)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.20), location: 0.0),
                                    .init(color: Color.clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5.5)
                            Spacer(minLength: 0)
                        }
                    }
                )
                .foregroundStyle(Color.green)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.green.opacity(0.40), location: 0.0),
                                    .init(color: Color.green.opacity(0.15), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            // Action Buttons
            HStack(spacing: 6) {
                // Keep This Copy Button
                Button(action: onKeepThis) {
                    HStack(spacing: 4.5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("Keep This")
                            .font(WalkmanFont.calloutBold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                .help("Keep this file and delete all other copies in this group")

                // Reveal in Finder
                Button(action: onRevealInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverLight.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                .help("Reveal file in Finder")

                // Edit Metadata
                Button(action: onEditMetadata) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(WalkmanTheme.silverLight.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
                .help("Edit tags for this copy")

                // Delete Single Copy
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.90))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .destructive, cornerRadius: 8))
                .help("Delete this copy from device")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.75)) {
                isHovered = h
            }
        }
    }

    private var storageBadge: some View {
        Group {
            if item.isInternal {
                driveBadgePill(
                    icon: "internaldrive.fill",
                    text: "Internal",
                    color: Color(red: 200/255, green: 160/255, blue: 255/255)
                )
            } else if item.isMicroSD {
                driveBadgePill(
                    icon: "sdcard.fill",
                    text: "MicroSD",
                    color: Color(red: 130/255, green: 200/255, blue: 255/255)
                )
            } else {
                driveBadgePill(
                    icon: "folder.fill",
                    text: item.driveName.isEmpty ? "Local" : item.driveName,
                    color: Color(red: 120/255, green: 230/255, blue: 210/255)
                )
            }
        }
    }

    private func driveBadgePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(WalkmanFont.badge)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            ZStack {
                color.opacity(0.14)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.20), location: 0.0),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 5.5)
                    Spacer(minLength: 0)
                }
            }
        )
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: color.opacity(0.40), location: 0.0),
                            .init(color: color.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Metric Pill (38pt Liquid Glass)
private struct MetricPill: View {
    let icon: String
    let label: String
    let value: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(value)
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 38)
        .background(
            ZStack {
                Color.white.opacity(0.04)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.35), location: 0.0),
                            .init(color: Color.white.opacity(0.15), location: 0.5),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Duplicate Scope Segmented Bar View (Liquid Glass Matched Geometry)
private struct DuplicateScopeSegmentedBarView: View {
    @Binding var selectedScope: DuplicateDetectionScope
    let onSelectScope: (DuplicateDetectionScope) -> Void

    @Namespace private var scopeNamespace
    @State private var activeScopeId: String = DuplicateDetectionScope.exactSameAlbum.id

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DuplicateDetectionScope.allCases) { scope in
                DuplicateScopeTabPillView(
                    scope: scope,
                    isSelected: activeScopeId == scope.id,
                    namespace: scopeNamespace,
                    onSelect: {
                        guard selectedScope != scope else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeScopeId = scope.id
                        }
                        onSelectScope(scope)
                    }
                )
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeScopeId = selectedScope.id
        }
        .onChange(of: selectedScope) { _, newScope in
            if activeScopeId != newScope.id {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeScopeId = newScope.id
                }
            }
        }
    }
}

private struct DuplicateScopeTabPillView: View {
    let scope: DuplicateDetectionScope
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5.5) {
                Image(systemName: scope == .exactSameAlbum ? "checkmark.shield.fill" : "square.stack.3d.down.right.fill")
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                Text(scope.label)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    Color.white :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        ActiveDuplicatePillBackground(isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeDuplicateScopeHighlight", in: namespace)
                    } else if isHovered {
                        HoverDuplicatePillBackground()
                    } else {
                        Color.white.opacity(0.001)
                    }
                }
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help(scope.description)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
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
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
    }
}

// MARK: - Duplicate Filter Segmented Bar View (Liquid Glass with Counts)
private struct DuplicateFilterItem: Identifiable {
    let filter: DuplicateFilter
    let title: String
    let count: Int
    let tint: Color?

    var id: String { filter.rawValue }
}

private struct DuplicateFilterSegmentedBarView: View {
    let items: [DuplicateFilterItem]
    @Binding var selectedFilter: DuplicateFilter
    let onSelectFilter: (DuplicateFilter) -> Void

    @Namespace private var filterNamespace
    @State private var activeFilterId: String = DuplicateFilter.sameDrive.rawValue

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                DuplicateFilterTabPillView(
                    item: item,
                    isSelected: activeFilterId == item.id,
                    namespace: filterNamespace,
                    onSelect: {
                        guard selectedFilter != item.filter else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeFilterId = item.id
                        }
                        onSelectFilter(item.filter)
                    }
                )
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeFilterId = selectedFilter.rawValue
        }
        .onChange(of: selectedFilter) { _, newFilter in
            if activeFilterId != newFilter.rawValue {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeFilterId = newFilter.rawValue
                }
            }
        }
    }
}

private struct DuplicateFilterTabPillView: View {
    let item: DuplicateFilterItem
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                // Count pill inside the tab
                Text("\(item.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        isSelected ?
                            (item.tint?.opacity(0.28) ?? Color.white.opacity(0.20)) :
                            (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    )
                    .foregroundStyle(
                        isSelected ?
                            (item.tint ?? Color.white) :
                            (isHovered ? Color.white : WalkmanTheme.silverMuted)
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    (item.tint ?? Color.white) :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        ActiveDuplicatePillBackground(tint: item.tint, isHovered: isHovered)
                            .matchedGeometryEffect(id: "activeDuplicateFilterHighlight", in: namespace)
                    } else if isHovered {
                        HoverDuplicatePillBackground()
                    } else {
                        Color.white.opacity(0.001)
                    }
                }
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
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
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
    }
}

// MARK: - Active & Hover Pill Backgrounds (Liquid Glass Sliding Lens)
private struct ActiveDuplicatePillBackground: View {
    var tint: Color? = nil
    var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Liquid Glass Translucent Body Fill
            if let tint = tint {
                tint.opacity(isHovered ? 0.20 : 0.14)
            } else {
                Color.white.opacity(0.16)
            }

            // Top specular refraction sheen
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    tint != nil ?
                        tint!.opacity(isHovered ? 0.65 : 0.50) :
                        Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.30 : 0.22),
            radius: isHovered ? 4 : 2.5,
            x: 0,
            y: 1
        )
    }
}

private struct HoverDuplicatePillBackground: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.09)
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.20), location: 0.0),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5.5)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Duplicate Sort Menu Button (38x38 Circular Liquid Glass)
private struct DuplicateSortMenuButton: View {
    @Binding var sortOption: DuplicateSortOption

    @State private var isHovered = false

    private var isSortActive: Bool {
        sortOption != .recoverableSpace
    }

    var body: some View {
        Menu {
            Picker("Sort Options", selection: $sortOption) {
                ForEach(DuplicateSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ZStack {
                // Circular glass body
                Circle()
                    .fill(
                        isSortActive ?
                            Color.white.opacity(isHovered ? 0.16 : 0.12) :
                            Color.white.opacity(isHovered ? 0.10 : 0.05)
                    )

                // Top specular refraction sheen (Liquid Glass)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.32 : (isSortActive ? 0.24 : 0.12)), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())

                // Sort icon
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isSortActive ?
                            Color.white :
                            (isHovered ? Color.white : WalkmanTheme.silverLight)
                    )

                // Active beacon indicator (subtle 5pt dot at top right when non-default sort is active)
                if isSortActive {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        isSortActive ?
                            Color.white.opacity(0.32) :
                            Color.white.opacity(isHovered ? 0.22 : 0.10),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.20 : 0.10), radius: isHovered ? 3.5 : 2, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.03 : 1.0)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help("Sort duplicates (\(sortOption.rawValue))")
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
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
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
    }
}

// MARK: - Duplicate Auto-Resolve Button (38pt Liquid Glass Cyan)
private struct DuplicateAutoResolveButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("Auto-Resolve Quality")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(height: 38)
            .background(
                ZStack {
                    Color.cyan.opacity(isHovered ? 0.22 : 0.15)
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHovered ? 0.35 : 0.22), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 7)
                        Spacer(minLength: 0)
                    }
                }
            )
            .foregroundStyle(Color.cyan)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.cyan.opacity(isHovered ? 0.65 : 0.45), location: 0.0),
                                .init(color: Color.cyan.opacity(0.20), location: 0.7),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
            .scaleEffect(isHovered ? 1.025 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
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
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .fixedSize(horizontal: true, vertical: false)
    }
}



// MARK: - Duplicate Modal Action
public enum DuplicateModalAction: Identifiable {
    case keepSingle(item: DuplicateTrackItem, group: DuplicateGroup)
    case deleteSingle(item: DuplicateTrackItem)
    case batchQualityResolve(groups: [DuplicateGroup])

    public var id: String {
        switch self {
        case .keepSingle(let item, let group):
            return "keep-\(group.id)-\(item.id)"
        case .deleteSingle(let item):
            return "delete-\(item.id)"
        case .batchQualityResolve:
            return "batch-quality"
        }
    }
}

// MARK: - Duplicate Resolution Sheet (Liquid Glass)
public struct DuplicateResolutionSheet: View {
    let action: DuplicateModalAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmHovered: Bool = false
    @State private var isCancelHovered: Bool = false

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            let gb = Double(bytes) / Double(1024 * 1024 * 1024)
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / Double(1024 * 1024)
            return String(format: "%.1f MB", mb)
        }
    }

    private var sheetWidth: CGFloat {
        680
    }

    private var sheetHeight: CGFloat {
        switch action {
        case .keepSingle:
            return 570
        case .batchQualityResolve:
            return 620
        case .deleteSingle:
            return 480
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dismiss button on top right
            HStack {
                Spacer()
                SheetCloseButton(action: onCancel)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            // Header Section
            headerSection
                .padding(.top, -10)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            // Content Preview Section
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 12)

            // Footer Action Bar
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .background(
            ZStack {
                WalkmanTheme.card.opacity(0.88)
                    .background(.ultraThinMaterial)

                // Top specular sheen (Apple Liquid Glass optical refraction)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.20), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.18), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.05), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }

    // MARK: - Header
    @ViewBuilder
    private var headerSection: some View {
        switch action {
        case .keepSingle(let item, let group):
            let otherCount = group.items.count - 1
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.green.opacity(0.30), lineWidth: 0.85)
                        )
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Keep This Copy")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.primary)

                        Text("Safe Resolution")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.green.opacity(0.25), lineWidth: 0.8)
                            )
                    }

                    Text("Retain selected copy on \(item.driveName) and delete \(otherCount) duplicate copy(ies) to reclaim storage.")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

        case .batchQualityResolve(let groups):
            let totalSaved = groups.reduce(0) { $0 + $1.recoverableBytes }
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.cyan.opacity(0.16))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.cyan.opacity(0.35), lineWidth: 0.85)
                        )
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Auto-Resolve Quality Discrepancies")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.primary)

                        Text("\(groups.count) Songs")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(Color.cyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.cyan.opacity(0.25), lineWidth: 0.8)
                            )
                    }

                    Text("Automatically keep highest resolution copies (FLAC/Hi-Res) and remove lower quality encodes, recovering ~\(formatBytes(totalSaved)).")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

        case .deleteSingle(let item):
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.red.opacity(0.30), lineWidth: 0.85)
                        )
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.red)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Delete Duplicate Copy")
                            .font(WalkmanFont.title1)
                            .foregroundStyle(.primary)

                        Text("Permanent Delete")
                            .font(WalkmanFont.badge)
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                            )
                    }

                    Text("Are you sure you want to delete this specific duplicate copy from \(item.driveName)?")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    // MARK: - Previews
    @ViewBuilder
    private var contentPreview: some View {
        switch action {
        case .keepSingle(let item, let group):
            keepSinglePreview(item: item, group: group)
        case .batchQualityResolve(let groups):
            batchQualityPreview(groups: groups)
        case .deleteSingle(let item):
            deleteSinglePreview(item: item)
        }
    }

    private func keepSinglePreview(item: DuplicateTrackItem, group: DuplicateGroup) -> some View {
        let otherItems = group.items.filter { $0.id != item.id }
        let savedBytes = group.totalSizeBytes - item.track.sizeBytes

        return VStack(spacing: 12) {
            // Metrics summary strip
            HStack(spacing: 10) {
                MetricChip(
                    icon: "internaldrive.badge.arrow.down",
                    label: "Space Freeable",
                    value: "+\(formatBytes(savedBytes))",
                    accentColor: .green
                )
                MetricChip(
                    icon: "trash",
                    label: "Copies Removed",
                    value: "\(otherItems.count)",
                    accentColor: WalkmanTheme.silverMuted
                )
                MetricChip(
                    icon: item.isMicroSD ? "sdcard" : "internaldrive",
                    label: "Keep Drive",
                    value: item.driveName,
                    accentColor: item.isMicroSD ? Color.blue : WalkmanTheme.silverLight
                )
            }

            // Section 1: Copy to Keep
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("COPY TO KEEP")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(Color.green)
                }

                HStack(spacing: 12) {
                    TrackCoverThumbnail(track: item.track, size: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.track.title.isEmpty ? item.track.filename : item.track.title)
                                .font(WalkmanFont.bodyBold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if item.isHiRes {
                                HiResBadge()
                            }
                        }

                        Text(item.track.artist.isEmpty ? "Unknown Artist" : item.track.artist)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(item.track.relativePath)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            DriveBadgeView(isMicroSD: item.isMicroSD, driveName: item.driveName)
                            FormatPill(track: item.track)
                        }

                        Text(formatBytes(item.track.sizeBytes))
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.30), lineWidth: 0.85)
                )
            }

            // Section 2: Copies to Delete
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("COPIES TO DELETE (\(otherItems.count))")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(otherItems) { other in
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.red.opacity(0.8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(other.track.filename)
                                        .font(WalkmanFont.subheadlineMedium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(other.track.relativePath)
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                DriveBadgeView(isMicroSD: other.isMicroSD, driveName: other.driveName)
                                FormatPill(track: other.track)

                                Text(formatBytes(other.track.sizeBytes))
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                            )
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private func batchQualityPreview(groups: [DuplicateGroup]) -> some View {
        let totalSaved = groups.reduce(0) { $0 + $1.recoverableBytes }

        return VStack(spacing: 12) {
            // Metrics strip
            HStack(spacing: 10) {
                MetricChip(
                    icon: "sparkles",
                    label: "Songs Upgraded",
                    value: "\(groups.count)",
                    accentColor: .cyan
                )
                MetricChip(
                    icon: "internaldrive.badge.arrow.down",
                    label: "Recoverable Storage",
                    value: "+\(formatBytes(totalSaved))",
                    accentColor: .green
                )
                MetricChip(
                    icon: "waveform.badge.magnifyingglass",
                    label: "Engine Standard",
                    value: "FLAC / Hi-Res Priority",
                    accentColor: WalkmanTheme.hiResGold
                )
            }

            // Preview list of affected groups
            VStack(alignment: .leading, spacing: 6) {
                Text("DISCREPANCIES TO BE RESOLVED (\(groups.count))")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(groups) { grp in
                            if let best = grp.suggestedItemToKeep {
                                let discarded = grp.items.filter { $0.id != best.id }
                                HStack(spacing: 12) {
                                    TrackCoverThumbnail(track: best.track, size: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(grp.title)
                                            .font(WalkmanFont.bodyMedium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(grp.artist)
                                            .font(WalkmanFont.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    // Quality comparison
                                    HStack(spacing: 6) {
                                        // Keep Pill
                                        HStack(spacing: 4) {
                                            Text("Keep:")
                                                .font(WalkmanFont.monoSmall)
                                                .foregroundStyle(Color.green)
                                            FormatPill(track: best.track)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)

                                        // Discard Pill
                                        if let firstDiscard = discarded.first {
                                            HStack(spacing: 4) {
                                                Text("Remove:")
                                                    .font(WalkmanFont.monoSmall)
                                                    .foregroundStyle(Color.red.opacity(0.8))
                                                FormatPill(track: firstDiscard.track)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.red.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        }
                                    }

                                    if grp.recoverableBytes > 0 {
                                        Text("+\(formatBytes(grp.recoverableBytes))")
                                            .font(WalkmanFont.badge)
                                            .foregroundStyle(Color.green)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }

            // Notice card
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.cyan)
                Text("Safe Operation: Walkman Studio preserves the highest-fidelity copy of each track. Companion lyrics (.lrc) and AppleDouble ghost files for deleted copies are removed cleanly.")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color.cyan.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 0.85)
            )
        }
    }

    private func deleteSinglePreview(item: DuplicateTrackItem) -> some View {
        VStack(spacing: 14) {
            // Track Card
            HStack(spacing: 14) {
                TrackCoverThumbnail(track: item.track, size: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.track.title.isEmpty ? item.track.filename : item.track.title)
                            .font(WalkmanFont.title3)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if item.isHiRes {
                            HiResBadge()
                        }
                    }

                    Text(item.track.artist.isEmpty ? "Unknown Artist" : item.track.artist)
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(item.track.album.isEmpty ? "Unknown Album" : item.track.album)
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    DriveBadgeView(isMicroSD: item.isMicroSD, driveName: item.driveName)
                    FormatPill(track: item.track)
                    Text(formatBytes(item.track.sizeBytes))
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.85)
            )

            // Path card
            VStack(alignment: .leading, spacing: 4) {
                Text("FILE LOCATION ON DEVICE")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                Text(item.track.fullPath)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
            )

            // Warning notice
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red)
                Text("This action permanently removes this duplicate audio file and its matching .lrc lyrics file from your Walkman. Other copies of this track in your library will remain intact.")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color.red.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.20), lineWidth: 0.85)
            )
        }
    }

    // MARK: - Footer
    private var footerBar: some View {
        HStack(alignment: .center) {
            Text("Changes are written directly to your Sony Walkman storage.")
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            // Cancel Button
            Button(action: onCancel) {
                Text("Cancel")
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(isCancelHovered ? 0.12 : 0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isCancelHovered ? 0.25 : 0.12), lineWidth: 0.85)
                    )
                    .scaleEffect(isCancelHovered ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .onHover { h in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    isCancelHovered = h
                }
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Confirm Button
            confirmButton
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch action {
        case .keepSingle:
            Button(action: onConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Keep & Delete Others")
                        .font(WalkmanFont.calloutBold)
                }
                .foregroundStyle(Color(red: 20 / 255, green: 20 / 255, blue: 24 / 255))
                .padding(.horizontal, 22)
                .padding(.vertical, 8.5)
                .background(WalkmanTheme.silverGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.20), radius: isConfirmHovered ? 6 : 3, y: isConfirmHovered ? 2 : 1)
                .scaleEffect(isConfirmHovered ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .onHover { h in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    isConfirmHovered = h
                }
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

        case .batchQualityResolve:
            Button(action: onConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("Auto-Resolve All")
                        .font(WalkmanFont.calloutBold)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8.5)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0/255, green: 170/255, blue: 200/255),
                            Color(red: 0/255, green: 120/255, blue: 170/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.cyan.opacity(0.50), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.20), radius: isConfirmHovered ? 6 : 3, y: isConfirmHovered ? 2 : 1)
                .scaleEffect(isConfirmHovered ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .onHover { h in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    isConfirmHovered = h
                }
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

        case .deleteSingle:
            Button(action: onConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Delete Copy")
                        .font(WalkmanFont.calloutBold)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8.5)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 220/255, green: 50/255, blue: 50/255),
                            Color(red: 170/255, green: 30/255, blue: 30/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.red.opacity(0.40), lineWidth: 0.85)
                )
                .shadow(color: Color.black.opacity(isConfirmHovered ? 0.35 : 0.20), radius: isConfirmHovered ? 6 : 3, y: isConfirmHovered ? 2 : 1)
                .scaleEffect(isConfirmHovered ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .onHover { h in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
                    isConfirmHovered = h
                }
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

// MARK: - Metric Chip
private struct MetricChip: View {
    let icon: String
    let label: String
    let value: String
    var accentColor: Color = WalkmanTheme.silverLight

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(WalkmanFont.badge)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(WalkmanFont.subheadlineMedium)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }
}

// MARK: - Drive Badge View
private struct DriveBadgeView: View {
    let isMicroSD: Bool
    let driveName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isMicroSD ? "sdcard" : "internaldrive")
                .font(.system(size: 10))
            Text(isMicroSD ? "MicroSD" : driveName)
                .font(WalkmanFont.badge)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(isMicroSD ? Color.blue.opacity(0.18) : Color.white.opacity(0.10))
        .foregroundStyle(isMicroSD ? Color.blue : WalkmanTheme.silverLight)
        .clipShape(Capsule())
    }
}

// MARK: - Format Pill
private struct FormatPill: View {
    let track: Track

    var body: some View {
        HStack(spacing: 4) {
            Text(track.format.uppercased())
                .font(WalkmanFont.badge)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silver)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            if track.bitsPerSample > 16 || track.sampleRate > 48000 {
                Text("\(track.bitsPerSample)b/\(track.sampleRate / 1000)kHz")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.hiResGold)
            } else if track.bitrateKbps > 0 {
                Text("\(track.bitrateKbps) kbps")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
        }
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
        .help("Close")
        .onHover { h in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.70)) {
                isHovered = h
            }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
