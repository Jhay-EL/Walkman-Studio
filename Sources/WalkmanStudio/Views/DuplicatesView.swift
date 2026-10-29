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

    @State private var searchQuery: String = ""
    @State private var selectedFilter: DuplicateFilter = .all
    @State private var sortOption: DuplicateSortOption = .recoverableSpace

    // Active modal action sheet state
    @State private var activeModalAction: DuplicateModalAction? = nil
    @State private var isProcessing: Bool = false
    @State private var isHoveringRescan: Bool = false

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
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var list = finder.duplicateGroups.filter { group in
            // Filter by category
            switch selectedFilter {
            case .all:
                break
            case .crossDrive:
                if !group.isCrossDrive { return false }
            case .qualityDifference:
                if !group.hasQualityDifference { return false }
            case .sameDrive:
                if group.isCrossDrive { return false }
            }

            // Filter by search text
            if !q.isEmpty {
                let matchesTitle = group.title.lowercased().contains(q)
                let matchesArtist = group.artist.lowercased().contains(q)
                let matchesPath = group.items.contains { $0.track.fullPath.lowercased().contains(q) || $0.track.album.lowercased().contains(q) }
                if !matchesTitle && !matchesArtist && !matchesPath {
                    return false
                }
            }

            return true
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

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Subheader: Filters, Search & Sorting
            controlsBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(WalkmanTheme.card.opacity(0.4))

            Divider()
                .overlay(Color.white.opacity(0.06))

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
                        Text("\(finder.duplicateGroups.count) Groups")
                            .font(WalkmanFont.pillCounter)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(WalkmanTheme.silver)
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                }

                Text("Detect and clean redundant songs comparing Internal Flash storage and MicroSD expansion.")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var headerMetricsGroup: some View {
        HStack(spacing: 10) {
            // Cross-Drive metric
            MetricPill(
                icon: "arrow.triangle.2.circlepath",
                label: "Cross-Drive",
                value: "\(finder.crossDriveCount)",
                accentColor: finder.crossDriveCount > 0 ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted
            )

            // Quality metric
            MetricPill(
                icon: "sparkles",
                label: "Quality Diff",
                value: "\(finder.qualityDifferenceCount)",
                accentColor: finder.qualityDifferenceCount > 0 ? Color.cyan : WalkmanTheme.silverMuted
            )

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
                .padding(.vertical, 8)
                .frame(minHeight: 38)
                .background(
                    finder.isScanning
                        ? LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                        : WalkmanTheme.hiResGoldGradient
                )
                .foregroundStyle(
                    finder.isScanning
                        ? WalkmanTheme.hiResGold
                        : Color(red: 20/255, green: 20/255, blue: 24/255)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.black.opacity(finder.isScanning ? 0.0 : 0.22), radius: 3, x: 0, y: 1.5)
                .scaleEffect(isHoveringRescan && !finder.isScanning ? 1.02 : 1.0)
                .brightness(isHoveringRescan && !finder.isScanning ? 0.04 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: isHoveringRescan)
            }
            .buttonStyle(.plain)
            .disabled(finder.isScanning)
            .onHover { isHoveringRescan = $0 }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Controls Components
    private var scopeSelector: some View {
        HStack(spacing: 2) {
            ForEach(DuplicateDetectionScope.allCases) { scope in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        finder.detectionScope = scope
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: scope == .exactSameAlbum ? "checkmark.shield.fill" : "square.stack.3d.down.right.fill")
                            .font(.system(size: 10))
                        Text(scope.label)
                            .font(WalkmanFont.calloutMedium)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(finder.detectionScope == scope ? WalkmanTheme.cardHover : Color.clear)
                    .foregroundStyle(finder.detectionScope == scope ? Color.white : WalkmanTheme.silverMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(scope.description)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var filterChipsGroup: some View {
        HStack(spacing: 6) {
            filterChip(
                title: "All",
                count: finder.duplicateGroups.count,
                filter: .all
            )
            filterChip(
                title: "Cross-Drive",
                count: finder.crossDriveCount,
                filter: .crossDrive,
                tint: WalkmanTheme.hiResGold
            )
            filterChip(
                title: "Quality Diff",
                count: finder.qualityDifferenceCount,
                filter: .qualityDifference,
                tint: Color.cyan
            )
            filterChip(
                title: "Same Storage",
                count: finder.duplicateGroups.count - finder.crossDriveCount,
                filter: .sameDrive
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search duplicates by title, artist, album...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(WalkmanFont.callout)
                .foregroundStyle(.white)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(minWidth: 100, idealWidth: 240, maxWidth: 360)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(DuplicateSortOption.allCases) { opt in
                Button(action: { sortOption = opt }) {
                    HStack {
                        Text(opt.rawValue)
                        if sortOption == opt {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                Text(sortOption.rawValue)
                    .font(WalkmanFont.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .foregroundStyle(WalkmanTheme.silver)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var autoResolveQualityButton: some View {
        let qualityGroups = finder.duplicateGroups.filter { $0.hasQualityDifference }
        if !qualityGroups.isEmpty {
            Button(action: {
                activeModalAction = .batchQualityResolve(groups: qualityGroups)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text("Auto-Resolve Quality")
                        .lineLimit(1)
                }
                .font(WalkmanFont.calloutMedium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.18))
                .foregroundStyle(Color.cyan)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 0.85)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Controls Bar (Filters, Search, Sort)
    private var controlsBar: some View {
        ViewThatFits(in: .horizontal) {
            // Wide single-row layout
            HStack(spacing: 12) {
                scopeSelector

                Divider()
                    .frame(height: 18)
                    .overlay(Color.white.opacity(0.1))

                filterChipsGroup

                Spacer(minLength: 12)

                searchBar

                sortMenu

                autoResolveQualityButton
            }

            // Responsive two-row layout for narrower windows
            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Scopes & Filter Chips
                HStack(spacing: 12) {
                    scopeSelector

                    Divider()
                        .frame(height: 18)
                        .overlay(Color.white.opacity(0.1))

                    ScrollView(.horizontal, showsIndicators: false) {
                        filterChipsGroup
                    }

                    Spacer(minLength: 0)
                }

                // Row 2: Search Bar + Sort Menu + Auto-Resolve Quality Action
                HStack(spacing: 10) {
                    searchBar
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    sortMenu

                    autoResolveQualityButton
                }
            }

            // Ultra-compact 3-row layout for very narrow center pane
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    searchBar
                        .frame(maxWidth: .infinity)
                    sortMenu
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        scopeSelector
                        Divider().frame(height: 18).overlay(Color.white.opacity(0.1))
                        filterChipsGroup
                    }
                }

                autoResolveQualityButton
            }
        }
    }

    private func filterChip(title: String, count: Int, filter: DuplicateFilter, tint: Color? = nil) -> some View {
        let isSelected = selectedFilter == filter
        return Button(action: { selectedFilter = filter }) {
            HStack(spacing: 5) {
                Text(title)
                    .font(WalkmanFont.calloutMedium)
                    .lineLimit(1)
                Text("\(count)")
                    .font(WalkmanFont.pillCounter)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? (tint?.opacity(0.25) ?? Color.white.opacity(0.15)) : Color.white.opacity(0.04))
            .foregroundStyle(isSelected ? (tint ?? .white) : WalkmanTheme.silverMuted)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? (tint?.opacity(0.5) ?? Color.white.opacity(0.3)) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
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

            Text("Try clearing the search query or selecting a different filter tab above.")
                .font(WalkmanFont.callout)
                .foregroundStyle(.secondary)

            Button("Reset Filters") {
                searchQuery = ""
                selectedFilter = .all
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(WalkmanTheme.silver)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
            .background(WalkmanTheme.cardHover.opacity(0.6))

            Divider()
                .overlay(Color.white.opacity(0.06))

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
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .background(WalkmanTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(group.isCrossDrive ? WalkmanTheme.hiResGold.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var groupThumbnailAndTitle: some View {
        HStack(spacing: 12) {
            if let firstTrack = group.items.first?.track {
                TrackCoverThumbnail(track: firstTrack, size: 42)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(WalkmanFont.headline)
                        .foregroundStyle(.white)
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
                .foregroundStyle(WalkmanTheme.silver)
                .lineLimit(1)
            if group.recoverableBytes > 0 {
                Text("+\(formatBytes(group.recoverableBytes)) freeable")
                    .font(WalkmanFont.badge)
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var groupBadgesAndAction: some View {
        HStack(spacing: 8) {
            // Match Reason Badge
            HStack(spacing: 4) {
                Image(systemName: group.matchReason.icon)
                Text(group.matchReason.rawValue)
            }
            .font(WalkmanFont.badge)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(reasonColor(group.matchReason).opacity(0.18))
            .foregroundStyle(reasonColor(group.matchReason))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)

            if group.isCrossDrive && group.matchReason != .crossDrive {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Cross-Drive")
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(WalkmanTheme.hiResGold.opacity(0.18))
                .foregroundStyle(WalkmanTheme.hiResGold)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }

            if group.hasQualityDifference {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("Quality Mismatch")
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.cyan.opacity(0.18))
                .foregroundStyle(Color.cyan)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }

            // Quick Header Action: "Keep Best Quality" or "Keep SD Card Copy"
            if let best = group.suggestedItemToKeep {
                Button(action: { onKeepOnly(best) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        if group.hasQualityDifference {
                            Text("Keep Best Quality")
                        } else if group.isCrossDrive {
                            Text("Keep on SD Card")
                        } else {
                            Text("Keep Best Copy")
                        }
                    }
                    .font(WalkmanFont.calloutMedium)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Keeps this recommended copy and deletes all other duplicate copies in this group")
                .fixedSize(horizontal: true, vertical: false)
            }
        }
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
            // Play Preview Button
            Button(action: onPreview) {
                Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.hiResGold : (isHovered ? .white : WalkmanTheme.silverMuted))
            }
            .buttonStyle(.plain)
            .help(isPlayingThis ? "Pause preview" : "Preview playback")

            // Storage Drive Badge
            if item.isInternal {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive.fill")
                    Text("Internal")
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.purple.opacity(0.2))
                .foregroundStyle(Color(red: 200/255, green: 160/255, blue: 255/255))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            } else if item.isMicroSD {
                HStack(spacing: 4) {
                    Image(systemName: "sdcard.fill")
                    Text("MicroSD")
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.blue.opacity(0.2))
                .foregroundStyle(Color(red: 130/255, green: 200/255, blue: 255/255))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                    Text(item.driveName.isEmpty ? "Local" : item.driveName)
                        .lineLimit(1)
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.teal.opacity(0.2))
                .foregroundStyle(Color(red: 120/255, green: 230/255, blue: 210/255))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }

            // Specs (Format, Bitrate, Resolution)
            HStack(spacing: 6) {
                Text(item.track.format.uppercased())
                    .font(WalkmanFont.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

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
                    .foregroundStyle(.secondary)

                Text(formatBytes(item.track.sizeBytes))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)

                Text("•")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Text(formatDuration(item.track.durationSeconds))
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverMuted)
            }
            .fixedSize(horizontal: true, vertical: false)

            // Path / Album
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.album.isEmpty ? "Unknown Album" : item.track.album)
                    .font(WalkmanFont.calloutMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.track.relativePath)
                    .font(WalkmanFont.monoSmall)
                    .foregroundStyle(WalkmanTheme.silverDark)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Recommended Tag
            if isSuggested {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                    Text("Recommended")
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.18))
                .foregroundStyle(Color.green)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }

            // Action Buttons
            HStack(spacing: 6) {
                // Keep This Copy Button
                Button(action: onKeepThis) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Keep This")
                            .lineLimit(1)
                    }
                    .font(WalkmanFont.calloutMedium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Keep this file and delete all other copies in this group")

                // Reveal in Finder
                Button(action: onRevealInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Reveal file in Finder")

                // Edit Metadata
                Button(action: onEditMetadata) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(WalkmanTheme.silverMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Edit tags for this copy")

                // Delete Single Copy
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Delete this copy from device")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isHovered ? Color.white.opacity(0.03) : Color.clear)
        .onHover { h in isHovered = h }
    }
}

// MARK: - Metric Pill
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

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(WalkmanFont.badge)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(value)
                    .font(WalkmanFont.calloutBold)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 38)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Hi-Res Badge
private struct HiResBadge: View {
    var body: some View {
        Text("HR")
            .font(.system(size: 8.5, weight: .black, design: .serif))
            .foregroundStyle(.black)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(WalkmanTheme.hiResGoldGradient)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
