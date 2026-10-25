import SwiftUI
import UniformTypeIdentifiers

private enum RenameLocation {
    case row
    case header
}

public struct PlaylistsView: View {
    let activeDrive: WalkmanDrive?
    let libraryTracks: [Track]
    
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: Playlist?
    @State private var playlistTracks: [String] = []
    @State private var resolvedPlaylistTracks: [(path: String, track: Track?)] = []
    @State private var editingPlaylistId: String? = nil
    @State private var editingPlaylistName: String = ""
    @State private var renameLocation: RenameLocation = .row
    @FocusState private var isRowRenameFocused: Bool
    @FocusState private var isHeaderRenameFocused: Bool
    @State private var showAddTrackSheet: Bool = false
    @State private var searchTrackQuery: String = ""
    @State private var messageBanner: String?
    @State private var isSaving: Bool = false
    @State private var cachedTrackLookup: [String: Track] = [:]
    
    // Drag & Drop Reordering & Transfer State
    @State private var draggedTrackIndex: Int? = nil
    @State private var draggedTrackPath: String? = nil
    @State private var dropTargetIndex: Int? = nil
    
    public init(activeDrive: WalkmanDrive?, libraryTracks: [Track]) {
        self.activeDrive = activeDrive
        self.libraryTracks = libraryTracks
        _cachedTrackLookup = State(initialValue: PlaylistsView.buildLookupTable(tracks: libraryTracks))
    }
    
    private func updateResolvedTracks() {
        resolvedPlaylistTracks = playlistTracks.map { path in
            (path: path, track: resolvedTrack(for: path))
        }
    }
    
    private func loadPlaylists() {
        cancelRename()
        guard let drive = activeDrive else {
            playlists = []
            selectedPlaylist = nil
            playlistTracks = []
            return
        }
        
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        let learningURL = URL(fileURLWithPath: drive.learningDir)
        var searchDirs = [musicURL]
        if FileManager.default.fileExists(atPath: learningURL.path) {
            searchDirs.append(learningURL)
        }
        
        var list: [Playlist] = []
        for dir in searchDirs {
            if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for fileURL in contents where fileURL.pathExtension.lowercased() == "m3u8" || fileURL.pathExtension.lowercased() == "m3u" {
                    let tracks = WalkmanEngine.shared.readPlaylist(at: fileURL)
                    let p = Playlist(
                        name: fileURL.deletingPathExtension().lastPathComponent,
                        filename: fileURL.lastPathComponent,
                        trackCount: tracks.count,
                        tracks: tracks,
                        fullPath: fileURL.path
                    )
                    list.append(p)
                }
            }
        }
        
        let sortedList = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.playlists = sortedList
        
        // Only retain selectedPlaylist if it belongs to the current drive and exists in the updated playlist list
        if let current = selectedPlaylist,
           current.fullPath.hasPrefix(drive.mountPoint),
           let updated = sortedList.first(where: { $0.id == current.id }) {
            self.selectedPlaylist = updated
            self.playlistTracks = updated.tracks
        } else {
            self.selectedPlaylist = sortedList.first
            self.playlistTracks = sortedList.first?.tracks ?? []
        }
        self.updateResolvedTracks()
    }
    
    private static let trimChars = CharacterSet(charactersIn: "/ \t\r\n")
    private static let slashChars = CharacterSet(charactersIn: "/")
    
    public static func normalizeKey(_ path: String) -> String {
        var s = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: trimChars)
            .lowercased()
        while s.hasPrefix("./") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: slashChars)
        }
        if s.hasPrefix("music/") {
            s = String(s.dropFirst(6)).trimmingCharacters(in: slashChars)
        } else if s.hasPrefix("learning/") {
            s = String(s.dropFirst(9)).trimmingCharacters(in: slashChars)
        }
        return s
    }
    
    public static func buildLookupTable(tracks: [Track]) -> [String: Track] {
        var dict: [String: Track] = [:]
        dict.reserveCapacity(tracks.count * 2)
        for track in tracks {
            let key = normalizeKey(track.relativePath)
            dict[key] = track
            let fn = (track.filename as NSString).lastPathComponent.lowercased()
            if dict[fn] == nil {
                dict[fn] = track
            }
        }
        return dict
    }
    
    private func resolvedTrack(for path: String) -> Track? {
        let key = PlaylistsView.normalizeKey(path)
        if let tr = cachedTrackLookup[key] {
            return tr
        }
        let fn = (path as NSString).lastPathComponent.lowercased()
        return cachedTrackLookup[fn]
    }
    
    private func persistPlaylistChanges(newTracks: [String], isManualSave: Bool = false) {
        guard let drive = activeDrive, let playlist = selectedPlaylist else { return }
        guard playlist.fullPath.isEmpty || playlist.fullPath.hasPrefix(drive.mountPoint) else { return }
        self.playlistTracks = newTracks
        self.updateResolvedTracks()
        self.isSaving = true
        
        // Write back to the exact directory where the playlist lives (e.g. /Volumes/SD_CARD/MUSIC/)
        let musicURL: URL
        if !playlist.fullPath.isEmpty {
            musicURL = URL(fileURLWithPath: playlist.fullPath).deletingLastPathComponent()
        } else {
            musicURL = URL(fileURLWithPath: drive.musicDir)
        }
        
        let filenameToSave = playlist.filename.isEmpty ? playlist.name : playlist.filename
        
        // Build metadata lookup table mapping normalized relative path and filename to (duration, title, artist)
        var metaLookup: [String: (duration: Int, title: String, artist: String)] = [:]
        for (key, t) in cachedTrackLookup {
            metaLookup[key] = (duration: Int(t.durationSeconds), title: t.title, artist: t.artist)
        }
        
        do {
            let savedURL = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: filenameToSave,
                relativeTracks: newTracks,
                trackMetadataLookup: metaLookup
            )
            self.isSaving = false
            if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                let updated = Playlist(
                    name: playlist.name,
                    filename: savedURL.lastPathComponent,
                    trackCount: newTracks.count,
                    tracks: newTracks,
                    fullPath: savedURL.path
                )
                playlists[idx] = updated
                selectedPlaylist = updated
            }
            withAnimation {
                if isManualSave {
                    messageBanner = "✓ Saved '\(filenameToSave)' to Walkman (\(newTracks.count) \(newTracks.count == 1 ? "track" : "tracks"))"
                } else {
                    messageBanner = "Saved to Walkman (\(newTracks.count) \(newTracks.count == 1 ? "track" : "tracks"))"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (isManualSave ? 4 : 3)) {
                if self.messageBanner?.contains("Saved") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
        } catch {
            self.isSaving = false
            withAnimation {
                messageBanner = "Save error: \(error.localizedDescription)"
            }
        }
    }
    
    private func sortTracksByTitle(ascending: Bool) {
        let items: [(path: String, title: String)] = playlistTracks.map { path in
            let tr = resolvedTrack(for: path)
            let t = tr?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (t?.isEmpty == false ? t! : (path as NSString).lastPathComponent)
            return (path: path, title: name)
        }
        let sorted = items.sorted {
            let cmp = $0.title.localizedStandardCompare($1.title)
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }.map(\.path)
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func sortTracksByArtist(ascending: Bool) {
        let items: [(path: String, artist: String, title: String)] = playlistTracks.map { path in
            let tr = resolvedTrack(for: path)
            let a = tr?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let t = tr?.title ?? (path as NSString).lastPathComponent
            return (path: path, artist: a, title: t)
        }
        let sorted = items.sorted {
            let cmp = $0.artist.localizedStandardCompare($1.artist)
            if cmp == .orderedSame {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }.map(\.path)
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func sortTracksByAlbum() {
        let items: [(path: String, album: String, trackNum: Int, title: String)] = playlistTracks.map { path in
            let tr = resolvedTrack(for: path)
            let alb = tr?.album.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let n = Int(tr?.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            let t = tr?.title ?? (path as NSString).lastPathComponent
            return (path: path, album: alb, trackNum: n, title: t)
        }
        let sorted = items.sorted {
            let cmp = $0.album.localizedStandardCompare($1.album)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            if $0.trackNum != $1.trackNum {
                return $0.trackNum < $1.trackNum
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }.map(\.path)
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func sortTracksByFilename(ascending: Bool) {
        let sorted = playlistTracks.sorted { p1, p2 in
            let f1 = (p1 as NSString).lastPathComponent
            let f2 = (p2 as NSString).lastPathComponent
            let cmp = f1.localizedStandardCompare(f2)
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func reverseTrackOrder() {
        persistPlaylistChanges(newTracks: Array(playlistTracks.reversed()))
    }
    
    private func shuffleTracks() {
        persistPlaylistChanges(newTracks: playlistTracks.shuffled())
    }
    
    // MARK: - Drag & Drop Organization & Transfer
    
    private func reorderTrack(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex >= 0, fromIndex < playlistTracks.count,
              toIndex >= 0, toIndex < playlistTracks.count,
              fromIndex != toIndex else { return }
        
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            var updated = playlistTracks
            let item = updated.remove(at: fromIndex)
            updated.insert(item, at: toIndex)
            persistPlaylistChanges(newTracks: updated)
        }
    }
    
    private func addTrackToPlaylist(_ rawTrackPath: String, playlist: Playlist) {
        guard let drive = activeDrive else {
            withAnimation {
                messageBanner = "No active Walkman drive detected."
            }
            return
        }
        guard playlist.fullPath.isEmpty || playlist.fullPath.hasPrefix(drive.mountPoint) else { return }
        
        // Resolve canonical clean relative path if track exists in library
        let trackPath: String
        if let matched = libraryTracks.first(where: { $0.fullPath == rawTrackPath || $0.relativePath == rawTrackPath }) {
            trackPath = matched.relativePath
        } else {
            trackPath = rawTrackPath
        }
        
        let trackTitle = resolvedTrack(for: trackPath)?.title ?? (trackPath as NSString).lastPathComponent
        
        // If dropping on current playlist and it's already there
        if playlist.id == selectedPlaylist?.id {
            withAnimation {
                messageBanner = "'\(trackTitle)' is already in '\(playlist.name)'"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.messageBanner?.contains("already in") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
            return
        }
        
        var updatedTracks = playlist.tracks
        let isDuplicate = updatedTracks.contains(trackPath)
        updatedTracks.append(trackPath)
        
        let musicURL: URL
        if !playlist.fullPath.isEmpty {
            musicURL = URL(fileURLWithPath: playlist.fullPath).deletingLastPathComponent()
        } else {
            musicURL = URL(fileURLWithPath: drive.musicDir)
        }
        let filenameToSave = playlist.filename.isEmpty ? playlist.name : playlist.filename
        
        var metaLookup: [String: (duration: Int, title: String, artist: String)] = [:]
        for (key, t) in cachedTrackLookup {
            metaLookup[key] = (duration: Int(t.durationSeconds), title: t.title, artist: t.artist)
        }
        
        do {
            let savedURL = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: filenameToSave,
                relativeTracks: updatedTracks,
                trackMetadataLookup: metaLookup
            )
            
            let updatedPl = Playlist(
                name: playlist.name,
                filename: savedURL.lastPathComponent,
                trackCount: updatedTracks.count,
                tracks: updatedTracks,
                fullPath: savedURL.path
            )
            
            if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                playlists[idx] = updatedPl
            }
            
            withAnimation {
                if isDuplicate {
                    messageBanner = "✓ Added another copy of '\(trackTitle)' to '\(playlist.name)' (\(updatedTracks.count) tracks)"
                } else {
                    messageBanner = "✓ Added '\(trackTitle)' to '\(playlist.name)' (\(updatedTracks.count) tracks)"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                if self.messageBanner?.contains("Added") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
        } catch {
            withAnimation {
                messageBanner = "Failed to add to '\(playlist.name)': \(error.localizedDescription)"
            }
        }
    }
    
    private func createNewPlaylist() {
        guard let drive = activeDrive else {
            withAnimation {
                messageBanner = "No active Walkman drive detected."
            }
            return
        }
        
        // Commit any pending rename before creating a new playlist
        if let currentEditId = editingPlaylistId, let currentEditingPl = playlists.first(where: { $0.id == currentEditId }) {
            commitRename(for: currentEditingPl)
        }
        
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        try? FileManager.default.createDirectory(at: musicURL, withIntermediateDirectories: true)
        
        // Find next unique default name: "New Playlist", "New Playlist 2", etc.
        var candidate = "New Playlist"
        var counter = 2
        while playlists.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "New Playlist \(counter)"
            counter += 1
        }
        
        do {
            let savedURL = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: candidate,
                relativeTracks: []
            )
            
            let newPl = Playlist(
                name: candidate,
                filename: savedURL.lastPathComponent,
                trackCount: 0,
                tracks: [],
                fullPath: savedURL.path
            )
            
            playlists.append(newPl)
            playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
            selectedPlaylist = newPl
            playlistTracks = []
            
            // Automatically enter inline rename mode on the row so the user only has to enter the playlist name!
            startRenaming(newPl, location: .row)
            
            withAnimation {
                messageBanner = "Added to Walkman: enter playlist name and press Return."
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                if self.messageBanner?.contains("enter playlist name") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
        } catch {
            withAnimation {
                messageBanner = "Failed to create: \(error.localizedDescription)"
            }
        }
    }
    
    private func startRenaming(_ playlist: Playlist, location: RenameLocation = .row) {
        if let currentEditId = editingPlaylistId, currentEditId != playlist.id, let currentEditingPl = playlists.first(where: { $0.id == currentEditId }) {
            commitRename(for: currentEditingPl)
        }
        
        editingPlaylistId = playlist.id
        editingPlaylistName = playlist.name
        renameLocation = location
        
        DispatchQueue.main.async {
            if location == .row {
                isRowRenameFocused = true
            } else {
                isHeaderRenameFocused = true
            }
        }
    }
    
    private func cancelRename() {
        editingPlaylistId = nil
        editingPlaylistName = ""
        isRowRenameFocused = false
        isHeaderRenameFocused = false
    }
    
    private func commitRename(for playlist: Playlist) {
        guard editingPlaylistId == playlist.id else { return }
        
        let trimmed = editingPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = WalkmanEngine.shared.sanitizeFilename(trimmed)
        
        // If empty or identical to current name, just exit rename mode
        if clean.isEmpty || clean == playlist.name {
            cancelRename()
            return
        }
        
        // Check if another playlist already has this name
        if playlists.contains(where: { $0.id != playlist.id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            withAnimation {
                messageBanner = "A playlist named '\(clean)' already exists."
            }
            cancelRename()
            return
        }
        
        let oldURL = URL(fileURLWithPath: playlist.fullPath)
        do {
            let newURL = try WalkmanEngine.shared.renamePlaylist(at: oldURL, newName: clean)
            let updatedPl = Playlist(
                name: clean,
                filename: newURL.lastPathComponent,
                trackCount: playlist.trackCount,
                tracks: playlist.tracks,
                fullPath: newURL.path
            )
            
            if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                playlists[idx] = updatedPl
                playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            
            if selectedPlaylist?.id == playlist.id {
                selectedPlaylist = updatedPl
            }
            
            cancelRename()
            
            withAnimation {
                messageBanner = "Renamed playlist to '\(clean)' on Walkman"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.messageBanner?.hasPrefix("Renamed playlist") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
        } catch {
            cancelRename()
            withAnimation {
                messageBanner = "Rename error: \(error.localizedDescription)"
            }
        }
    }
    
    private func deletePlaylist(_ playlist: Playlist) {
        guard let drive = activeDrive, playlist.fullPath.hasPrefix(drive.mountPoint) else { return }
        if editingPlaylistId == playlist.id {
            cancelRename()
        }
        try? FileManager.default.removeItem(atPath: playlist.fullPath)
        let dotPath = (playlist.fullPath as NSString).deletingLastPathComponent + "/._" + (playlist.fullPath as NSString).lastPathComponent
        try? FileManager.default.removeItem(atPath: dotPath)
        sync()
        if selectedPlaylist?.id == playlist.id {
            selectedPlaylist = nil
            playlistTracks = []
        }
        loadPlaylists()
    }
    
    public var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let isCompact = totalWidth < 760
            let isNarrow = totalWidth < 620
            let sidebarWidth: CGFloat = isNarrow ? 180 : (isCompact ? 200 : 235)
            let colSpacing: CGFloat = isCompact ? 10 : 14
            
            VStack(spacing: 0) {
                // Transparent Top Navigation Header
                topHeaderView(isNarrow: isNarrow)
                    .padding(.bottom, 12)
                
                // Symmetrical Hairline Separator Line (0.8pt)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.8)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                
                // Main 2-Column Studio Console Layout
                HStack(spacing: colSpacing) {
                    // Left Column: Playlist List
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("PLAYLISTS (\(playlists.count))")
                                .font(WalkmanFont.sectionHeader)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        
                        if playlists.isEmpty {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 28))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Text("No Playlists Found")
                                    .font(WalkmanFont.calloutMedium)
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                Text("Create one to organize your tracks")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                
                                Button(action: createNewPlaylist) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("New Playlist")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                }
                                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 14))
                                .disabled(activeDrive == nil)
                                .opacity(activeDrive == nil ? 0.5 : 1.0)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    ForEach(playlists) { pl in
                                        let isSel = selectedPlaylist?.id == pl.id
                                        let isEditingRow = (editingPlaylistId == pl.id && renameLocation == .row)
                                        
                                        PlaylistListRowView(
                                            playlist: pl,
                                            isSelected: isSel,
                                            isEditingRow: isEditingRow,
                                            editingPlaylistName: $editingPlaylistName,
                                            isRowRenameFocused: $isRowRenameFocused,
                                            onSelect: {
                                                if let editId = editingPlaylistId, let curPl = playlists.first(where: { $0.id == editId }) {
                                                    commitRename(for: curPl)
                                                }
                                                selectedPlaylist = pl
                                                playlistTracks = pl.tracks
                                                updateResolvedTracks()
                                            },
                                            onStartRename: {
                                                startRenaming(pl, location: .row)
                                            },
                                            onCommitRename: {
                                                commitRename(for: pl)
                                            },
                                            onCancelRename: {
                                                cancelRename()
                                            },
                                            onDelete: {
                                                deletePlaylist(pl)
                                            },
                                            onDropTrack: { droppedPath in
                                                let pathToUse = droppedPath.isEmpty ? (draggedTrackPath ?? "") : droppedPath
                                                if !pathToUse.isEmpty {
                                                    addTrackToPlaylist(pathToUse, playlist: pl)
                                                }
                                                draggedTrackIndex = nil
                                                draggedTrackPath = nil
                                                dropTargetIndex = nil
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(isCompact ? 10 : 12)
                    .frame(width: sidebarWidth)
                    .background(WalkmanTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)
                    
                    // Right Column: Playlist Content / Editor
                    VStack(alignment: .leading, spacing: isCompact ? 10 : 12) {
                        if let pl = selectedPlaylist {
                            playlistDetailHeader(pl: pl)
                            
                            // Tracks List
                            if playlistTracks.isEmpty {
                                VStack(spacing: 12) {
                                    Spacer()
                                    Image(systemName: "tray")
                                        .font(.system(size: 32))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("This playlist is empty")
                                        .font(WalkmanFont.bodyMedium)
                                        .foregroundStyle(WalkmanTheme.silverLight)
                                    Text("Click 'Add From Library' to populate this playlist")
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    
                                    Button(action: { showAddTrackSheet = true }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("Add From Library")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    }
                                    .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 14))
                                    .padding(.top, 4)
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 3) {
                                        ForEach(Array(resolvedPlaylistTracks.enumerated()), id: \.offset) { index, pair in
                                            let trackPath = pair.path
                                            let matchedTrack = pair.track
                                            let isPlayingThis = (AudioPlayerService.shared.currentTrack?.relativePath == trackPath || AudioPlayerService.shared.currentTrack?.fullPath == matchedTrack?.fullPath) && AudioPlayerService.shared.isPlaying
                                            let isDragSource = draggedTrackIndex == index
                                            let isDropTarget = dropTargetIndex == index && draggedTrackIndex != nil && draggedTrackIndex != index
                                            let showLineAbove = isDropTarget && (draggedTrackIndex ?? 0) > index
                                            let showLineBelow = isDropTarget && (draggedTrackIndex ?? 0) < index
                                            let otherPlaylists = playlists.filter { $0.id != selectedPlaylist?.id }
                                            
                                            VStack(spacing: 0) {
                                                if showLineAbove {
                                                    DropInsertionLine()
                                                }
                                                
                                                PlaylistTrackRow(
                                                    index: index,
                                                    totalCount: resolvedPlaylistTracks.count,
                                                    trackPath: trackPath,
                                                    matchedTrack: matchedTrack,
                                                    isPlayingThis: isPlayingThis,
                                                    isDragSource: isDragSource,
                                                    otherPlaylists: otherPlaylists,
                                                    onPlay: {
                                                        if let tr = matchedTrack {
                                                            if isPlayingThis {
                                                                AudioPlayerService.shared.pause()
                                                            } else {
                                                                AudioPlayerService.shared.play(track: tr, in: libraryTracks)
                                                            }
                                                        }
                                                    },
                                                    onStartDrag: {
                                                        draggedTrackIndex = index
                                                        draggedTrackPath = trackPath
                                                    },
                                                    onMoveUp: {
                                                        if index > 0 {
                                                            var updated = playlistTracks
                                                            updated.swapAt(index, index - 1)
                                                            persistPlaylistChanges(newTracks: updated)
                                                        }
                                                    },
                                                    onMoveDown: {
                                                        if index < playlistTracks.count - 1 {
                                                            var updated = playlistTracks
                                                            updated.swapAt(index, index + 1)
                                                            persistPlaylistChanges(newTracks: updated)
                                                        }
                                                    },
                                                    onMoveToTop: {
                                                        if index > 0 {
                                                            var updated = playlistTracks
                                                            let item = updated.remove(at: index)
                                                            updated.insert(item, at: 0)
                                                            persistPlaylistChanges(newTracks: updated)
                                                        }
                                                    },
                                                    onMoveToBottom: {
                                                        if index < playlistTracks.count - 1 {
                                                            var updated = playlistTracks
                                                            let item = updated.remove(at: index)
                                                            updated.append(item)
                                                            persistPlaylistChanges(newTracks: updated)
                                                        }
                                                    },
                                                    onRemove: {
                                                        var updated = playlistTracks
                                                        updated.remove(at: index)
                                                        persistPlaylistChanges(newTracks: updated)
                                                    },
                                                    onAddToPlaylist: { targetPl in
                                                        addTrackToPlaylist(trackPath, playlist: targetPl)
                                                    }
                                                )
                                                .opacity(isDragSource ? 0.35 : 1.0)
                                                .onDrop(of: [.plainText, .text], delegate: TrackDropDelegate(
                                                    targetIndex: index,
                                                    trackPath: trackPath,
                                                    draggedIndex: $draggedTrackIndex,
                                                    draggedPath: $draggedTrackPath,
                                                    dropTargetIndex: $dropTargetIndex,
                                                    onMove: { from, to in
                                                        reorderTrack(from: from, to: to)
                                                    }
                                                ))
                                                
                                                if showLineBelow {
                                                    DropInsertionLine()
                                                }
                                            }
                                        }
                                        
                                        // Bottom drop target area to move track to the end of the playlist
                                        Color.clear
                                            .frame(height: 88)
                                            .onDrop(of: [.plainText, .text], isTargeted: nil) { providers in
                                                if let from = draggedTrackIndex {
                                                    let to = playlistTracks.count - 1
                                                    if from != to {
                                                        reorderTrack(from: from, to: to)
                                                    }
                                                    draggedTrackIndex = nil
                                                    draggedTrackPath = nil
                                                    dropTargetIndex = nil
                                                    return true
                                                }
                                                return false
                                            }
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 20))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Text("Select or create a playlist from the left")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WalkmanTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)
                }
            }
        }
        .onAppear {
            if cachedTrackLookup.isEmpty && !libraryTracks.isEmpty {
                cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
            }
            loadPlaylists()
            updateResolvedTracks()
        }
        .onChange(of: libraryTracks) {
            cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
            updateResolvedTracks()
        }
        .onChange(of: activeDrive?.mountPoint) {
            cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
            loadPlaylists()
            updateResolvedTracks()
        }
        .sheet(isPresented: $showAddTrackSheet) {
            AddTracksModal(
                playlistName: selectedPlaylist?.name ?? "Playlist",
                tracks: libraryTracks,
                existingPlaylistPaths: Set(playlistTracks),
                onAddTracks: { addedRelativePaths, shouldDismiss in
                    let newTracks = playlistTracks + addedRelativePaths
                    persistPlaylistChanges(newTracks: newTracks)
                    if shouldDismiss {
                        showAddTrackSheet = false
                    }
                },
                onDismiss: { showAddTrackSheet = false }
            )
        }
    }
    
    // MARK: - Top Navigation Header
    
    @ViewBuilder
    private func topHeaderView(isNarrow: Bool) -> some View {
        HStack(spacing: 12) {
            // Left: Header Title
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WalkmanTheme.silverLight)
                
                Text("Playlists")
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)
            }
            
            // Middle: Status Message Banner if present
            if let banner = messageBanner {
                HStack(spacing: 5) {
                    Image(systemName: banner.contains("error") || banner.contains("Failed") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(banner.contains("error") || banner.contains("Failed") ? Color.red : WalkmanTheme.silverLight)
                    Text(banner)
                        .font(WalkmanFont.subheadlineMedium)
                        .foregroundStyle(banner.contains("error") || banner.contains("Failed") ? Color.red : WalkmanTheme.silverLight)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
            }
            
            Spacer()
            
            // Right: New Playlist Action Button
            Button(action: createNewPlaylist) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(isNarrow ? "New" : "New Playlist")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 16))
            .disabled(activeDrive == nil)
            .opacity(activeDrive == nil ? 0.5 : 1.0)
            .help("Create new .m3u8 playlist on Walkman")
        }
        .padding(.horizontal, 4)
        .background(Color.clear)
    }
    
    // MARK: - Responsive Detail Header Subviews
    
    @ViewBuilder
    private func playlistDetailHeader(pl: Playlist) -> some View {
        ViewThatFits(in: .horizontal) {
            // Layout 1: Wide single row with full labels
            HStack(alignment: .center, spacing: 10) {
                if editingPlaylistId == pl.id && renameLocation == .header {
                    headerRenameView(pl: pl)
                } else {
                    playlistTitleSection(pl: pl, showSubtitle: true)
                }
                
                Spacer(minLength: 8)
                
                sortMenuButton
                addFromLibraryButton(compact: false)
            }
            .padding(.horizontal, 4)
            
            // Layout 2: Medium single row with compact labels
            HStack(alignment: .center, spacing: 8) {
                if editingPlaylistId == pl.id && renameLocation == .header {
                    headerRenameView(pl: pl)
                } else {
                    playlistTitleSection(pl: pl, showSubtitle: true)
                }
                
                Spacer(minLength: 6)
                
                sortMenuButton
                addFromLibraryButton(compact: true)
            }
            .padding(.horizontal, 4)
            
            // Layout 3: Compact 2 rows (prevents squishing on small window size)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if editingPlaylistId == pl.id && renameLocation == .header {
                        headerRenameView(pl: pl)
                    } else {
                        HStack(spacing: 8) {
                            Text(pl.name)
                                .font(WalkmanFont.title3)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Button(action: { startRenaming(pl, location: .header) }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                            .buttonStyle(.plain)
                            .help("Rename Playlist on Walkman")
                        }
                    }
                    
                    Spacer(minLength: 8)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Text("\(playlistTracks.count) \(playlistTracks.count == 1 ? "track" : "tracks") in sequence")
                        .font(WalkmanFont.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 8)
                    
                    sortMenuButton
                    addFromLibraryButton(compact: false)
                }
            }
            .padding(.horizontal, 4)
            
            // Layout 4: Ultra-compact 2 rows with compact button labels
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    if editingPlaylistId == pl.id && renameLocation == .header {
                        headerRenameView(pl: pl)
                    } else {
                        HStack(spacing: 6) {
                            Text(pl.name)
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Button(action: { startRenaming(pl, location: .header) }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Spacer(minLength: 6)
                }
                
                HStack(alignment: .center, spacing: 6) {
                    Text("\(playlistTracks.count) tracks")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 6)
                    
                    sortMenuButton
                    addFromLibraryButton(compact: true)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    @ViewBuilder
    private func headerRenameView(pl: Playlist) -> some View {
        HStack(spacing: 8) {
            TextField("Playlist Name", text: $editingPlaylistName)
                .textFieldStyle(.plain)
                .font(WalkmanFont.title3)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WalkmanTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
                )
                .focused($isHeaderRenameFocused)
                .onSubmit { commitRename(for: pl) }
                .onExitCommand { cancelRename() }
                .frame(maxWidth: 240)
            
            Button(action: { commitRename(for: pl) }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 8))
            .fixedSize(horizontal: true, vertical: false)
            
            Button(action: cancelRename) {
                Text("Cancel")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 8))
            .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    @ViewBuilder
    private func playlistTitleSection(pl: Playlist, showSubtitle: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(pl.name)
                    .font(WalkmanFont.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Button(action: { startRenaming(pl, location: .header) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(.plain)
                .help("Rename Playlist on Walkman")
            }
            
            if showSubtitle {
                Text("\(playlistTracks.count) \(playlistTracks.count == 1 ? "track" : "tracks") in sequence")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    

    @ViewBuilder
    private var sortMenuButton: some View {
        PlaylistSortMenuButton(
            isDisabled: playlistTracks.isEmpty,
            onSortTitleAsc: { sortTracksByTitle(ascending: true) },
            onSortTitleDesc: { sortTracksByTitle(ascending: false) },
            onSortArtistAsc: { sortTracksByArtist(ascending: true) },
            onSortAlbum: { sortTracksByAlbum() },
            onSortFilenameAsc: { sortTracksByFilename(ascending: true) },
            onReverseOrder: { reverseTrackOrder() },
            onShuffleOrder: { shuffleTracks() }
        )
    }
    
    @ViewBuilder
    private func addFromLibraryButton(compact: Bool = false) -> some View {
        Button(action: { showAddTrackSheet = true }) {
            HStack(spacing: 5.5) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(compact ? "Add" : "Add From Library")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
        }
        .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 16))
        .fixedSize(horizontal: true, vertical: false)
    }
}

// -----------------------------------------------------------------------------
// PLAYLIST LIST ROW VIEW (TACTILE HOVER & LIQUID GLASS SELECTION + DROP TARGET)
// -----------------------------------------------------------------------------
private struct PlaylistListRowView: View {
    let playlist: Playlist
    let isSelected: Bool
    let isEditingRow: Bool
    @Binding var editingPlaylistName: String
    var isRowRenameFocused: FocusState<Bool>.Binding
    let onSelect: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void
    var onDropTrack: ((String) -> Void)? = nil
    
    @State private var isHovered = false
    @State private var isDropTargeted = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: isDropTargeted ? "plus.circle.fill" : "music.note.list")
                    .font(.system(size: 13, weight: (isSelected || isDropTargeted) ? .semibold : .regular))
                    .foregroundStyle(
                        isDropTargeted ?
                            WalkmanTheme.hiResGold :
                            (isSelected ? WalkmanTheme.silverLight : (isHovered ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted))
                    )
                    .frame(width: 16)
                
                if isEditingRow {
                    TextField("Playlist Name", text: $editingPlaylistName)
                        .textFieldStyle(.plain)
                        .font(WalkmanFont.calloutMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(WalkmanTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .focused(isRowRenameFocused)
                        .onSubmit { onCommitRename() }
                        .onExitCommand { onCancelRename() }
                    
                    Button(action: onCommitRename) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .padding(4)
                            .background(WalkmanTheme.silverGradient)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onCancelRename) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(WalkmanTheme.silverMuted)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(playlist.name)
                        .font(isSelected ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(
                            isDropTargeted ?
                                WalkmanTheme.hiResGoldLight :
                                (isSelected ? Color.white : (isHovered ? Color.white : WalkmanTheme.silverLight))
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    if isDropTargeted {
                        Text("+ Add")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WalkmanTheme.hiResGold)
                            .clipShape(Capsule())
                    } else {
                        Text("\(playlist.trackCount)")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(isSelected ? WalkmanTheme.silverLight.opacity(0.9) : WalkmanTheme.silverMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isDropTargeted {
                        WalkmanTheme.hiResGold.opacity(0.15)
                    } else if isSelected {
                        Color.white.opacity(0.12)
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.24), location: 0.0),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 5.5)
                            Spacer(minLength: 0)
                        }
                    } else if isHovered {
                        Color.white.opacity(0.05)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isDropTargeted ?
                            WalkmanTheme.hiResGold.opacity(0.85) :
                            (isSelected ?
                                Color.white.opacity(0.24) :
                                (isHovered ? Color.white.opacity(0.08) : Color.clear)),
                        lineWidth: isDropTargeted ? 1.2 : 0.8
                    )
            )
            .scaleEffect(isDropTargeted ? 1.03 : (isHovered && !isSelected ? 1.015 : 1.0))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onDrop(of: [.plainText, .text], isTargeted: $isDropTargeted) { providers in
            guard let onDropTrack = onDropTrack else { return false }
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    if let path = string as? String {
                        DispatchQueue.main.async {
                            onDropTrack(path)
                        }
                    }
                }
                return true
            }
            return false
        }
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
        .contextMenu {
            Button("Rename Playlist") {
                onStartRename()
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    }
}

private enum AddBrowsingMode: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case recentlyAdded = "Recently Added"
    case albums = "By Album"
    case artists = "By Artist"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .songs: return "music.note"
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        }
    }
}

private struct PlaylistTrackRow: View {
    let index: Int
    let totalCount: Int
    let trackPath: String
    let matchedTrack: Track?
    let isPlayingThis: Bool
    var isDragSource: Bool = false
    let otherPlaylists: [Playlist]
    let onPlay: () -> Void
    let onStartDrag: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToTop: () -> Void
    let onMoveToBottom: () -> Void
    let onRemove: () -> Void
    var onAddToPlaylist: ((Playlist) -> Void)? = nil
    
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(WalkmanFont.mono)
                .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : WalkmanTheme.silverMuted)
                .frame(width: 26, alignment: .trailing)
            
            // Play / Note button
            Button(action: onPlay) {
                Image(systemName: isPlayingThis ? "speaker.wave.2.fill" : (matchedTrack != nil ? "play.circle.fill" : "music.note"))
                    .font(.system(size: 14))
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : (matchedTrack != nil ? WalkmanTheme.silverLight.opacity(isHovered ? 0.95 : 0.65) : WalkmanTheme.silverMuted.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(matchedTrack == nil)
            
            // Track Details or Path
            VStack(alignment: .leading, spacing: 2) {
                if let tr = matchedTrack, !tr.title.isEmpty {
                    Text(tr.title)
                        .font(isPlayingThis ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : (isHovered ? Color.white : WalkmanTheme.silverLight))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 6) {
                        if !tr.artist.isEmpty {
                            Text(tr.artist)
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if !tr.album.isEmpty {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))
                            Text(tr.album)
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(WalkmanTheme.silverMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.6))
                            Text(trackPath)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(WalkmanTheme.silverMuted.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Text(trackPath)
                        .font(WalkmanFont.mono)
                        .foregroundStyle(isHovered ? Color.white : WalkmanTheme.silverLight)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            Spacer()
            
            // Action buttons on row: draggable handle button + remove button
            HStack(spacing: 6) {
                // Draggable Handle Button (hold & drag to reorder or transfer to another playlist)
                TrackDragHandleButton(
                    trackPath: trackPath,
                    isRowHovered: isHovered,
                    onStartDrag: onStartDrag
                )
                
                // Remove
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(isHovered ? 0.9 : 0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Remove from Playlist")
            }
            .opacity(isHovered || isPlayingThis || isDragSource ? 1.0 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isPlayingThis {
                    WalkmanTheme.cardHover
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.12), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 5.5)
                        Spacer(minLength: 0)
                    }
                } else if isHovered {
                    Color.white.opacity(0.045)
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.10), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 5)
                        Spacer(minLength: 0)
                    }
                } else {
                    WalkmanTheme.card.opacity(0.40)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isPlayingThis ?
                        Color.white.opacity(0.20) :
                        (isHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.03)),
                    lineWidth: 0.85
                )
        )
        .scaleEffect(isHovered && !isPlayingThis ? 1.008 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .onTapGesture(count: 2) {
            onPlay()
        }
        .contextMenu {
            if matchedTrack != nil {
                Button(action: onPlay) {
                    Label("Play Now", systemImage: "play.fill")
                }
                Divider()
            }
            
            if !otherPlaylists.isEmpty {
                Menu {
                    ForEach(otherPlaylists) { pl in
                        Button(pl.name) {
                            onAddToPlaylist?(pl)
                        }
                    }
                } label: {
                    Label("Add to Another Playlist", systemImage: "text.badge.plus")
                }
                Divider()
            }
            
            Button(action: onMoveToTop) {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            .disabled(index == 0)
            
            Button(action: onMoveUp) {
                Label("Move Up", systemImage: "chevron.up")
            }
            .disabled(index == 0)
            
            Button(action: onMoveDown) {
                Label("Move Down", systemImage: "chevron.down")
            }
            .disabled(index == totalCount - 1)
            
            Button(action: onMoveToBottom) {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            .disabled(index == totalCount - 1)
            
            Divider()
            
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Playlist", systemImage: "trash")
            }
        }
    }
}

// -----------------------------------------------------------------------------
// PLAYLIST SORT MENU BUTTON (CIRCULAR LIQUID GLASS BUTTON)
// -----------------------------------------------------------------------------
private struct PlaylistSortMenuButton: View {
    let isDisabled: Bool
    let onSortTitleAsc: () -> Void
    let onSortTitleDesc: () -> Void
    let onSortArtistAsc: () -> Void
    let onSortAlbum: () -> Void
    let onSortFilenameAsc: () -> Void
    let onReverseOrder: () -> Void
    let onShuffleOrder: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Menu {
            Button(action: onSortTitleAsc) {
                Label("Title (A → Z)", systemImage: "textformat")
            }
            Button(action: onSortTitleDesc) {
                Label("Title (Z → A)", systemImage: "textformat")
            }
            Button(action: onSortArtistAsc) {
                Label("Artist (A → Z)", systemImage: "person")
            }
            Button(action: onSortAlbum) {
                Label("Album & Track Number", systemImage: "square.stack")
            }
            Button(action: onSortFilenameAsc) {
                Label("Filename (A → Z)", systemImage: "doc.text")
            }
            Divider()
            Button(action: onReverseOrder) {
                Label("Reverse Current Order", systemImage: "arrow.up.arrow.down")
            }
            Button(action: onShuffleOrder) {
                Label("Shuffle Order", systemImage: "shuffle")
            }
        } label: {
            ZStack {
                // Circular glass body
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.05))
                
                // Top specular refraction sheen (Liquid Glass)
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(isHovered ? 0.32 : 0.14), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                    Spacer(minLength: 0)
                }
                .clipShape(Circle())
                
                // Sort icon only
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.white : WalkmanTheme.silverLight)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        Color.white.opacity(isHovered ? 0.24 : 0.10),
                        lineWidth: 0.85
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.20 : 0.08), radius: isHovered ? 3.5 : 2, x: 0, y: 1)
            .scaleEffect(isHovered && !isDisabled ? 1.03 : 1.0)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.40 : 1.0)
        .help("Sort playlist tracks")
        .onHover { hovering in
            guard !isDisabled else { return }
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

// -----------------------------------------------------------------------------
// TRACK DRAG HANDLE BUTTON (HOLD & DRAG TO ORGANIZE OR DRAG TO ANOTHER PLAYLIST)
// -----------------------------------------------------------------------------
private struct TrackDragHandleButton: View {
    let trackPath: String
    let isRowHovered: Bool
    let onStartDrag: () -> Void
    
    @State private var isButtonHovered: Bool = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    isButtonHovered ?
                        Color.white.opacity(0.15) :
                        (isRowHovered ? Color.white.opacity(0.06) : Color.clear)
                )
            
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    isButtonHovered ?
                        Color.white :
                        (isRowHovered ? WalkmanTheme.silverLight.opacity(0.85) : WalkmanTheme.silverMuted.opacity(0.55))
                )
        }
        .frame(width: 24, height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(
                    isButtonHovered ?
                        Color.white.opacity(0.28) :
                        (isRowHovered ? Color.white.opacity(0.12) : Color.clear),
                    lineWidth: 0.8
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isButtonHovered = hovering
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isButtonHovered {
                isButtonHovered = false
                NSCursor.pop()
            }
        }
        .onDrag {
            onStartDrag()
            return NSItemProvider(object: trackPath as NSString)
        }
        .help("Hold and drag to reorder within playlist, or drop onto another playlist")
    }
}

// -----------------------------------------------------------------------------
// DROP INSERTION LINE (GOLD SONY REFRACTION BEACON)
// -----------------------------------------------------------------------------
private struct DropInsertionLine: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(WalkmanTheme.hiResGold)
                .frame(width: 5, height: 5)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            WalkmanTheme.hiResGold,
                            WalkmanTheme.hiResGold.opacity(0.5),
                            WalkmanTheme.hiResGold.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1.5)
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// -----------------------------------------------------------------------------
// TRACK DROP DELEGATE (REORDERING WITHIN PLAYLIST)
// -----------------------------------------------------------------------------
private struct TrackDropDelegate: DropDelegate {
    let targetIndex: Int
    let trackPath: String
    @Binding var draggedIndex: Int?
    @Binding var draggedPath: String?
    @Binding var dropTargetIndex: Int?
    let onMove: (Int, Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex, from != targetIndex else { return }
        dropTargetIndex = targetIndex
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let from = draggedIndex else {
            draggedIndex = nil
            draggedPath = nil
            dropTargetIndex = nil
            return false
        }
        
        let to = targetIndex
        draggedIndex = nil
        draggedPath = nil
        dropTargetIndex = nil
        
        if from != to {
            onMove(from, to)
        }
        return true
    }
    
    func dropExited(info: DropInfo) {
        if dropTargetIndex == targetIndex {
            dropTargetIndex = nil
        }
    }
}

private struct ModalFilterOption: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isHiRes: Bool
}

private let modalFormatOptions: [ModalFilterOption] = [
    ModalFilterOption(id: "ALL", title: "All Formats", icon: nil, isHiRes: false),
    ModalFilterOption(id: "FLAC", title: "FLAC", icon: nil, isHiRes: false),
    ModalFilterOption(id: "MP3", title: "MP3", icon: nil, isHiRes: false),
    ModalFilterOption(id: "HI-RES", title: "Hi-Res", icon: "waveform", isHiRes: true)
]

// -----------------------------------------------------------------------------
// MODAL BROWSING MODE SEGMENTED BAR (LIQUID GLASS SLIDING PILL)
// -----------------------------------------------------------------------------
private struct ModalBrowsingModeSegmentedBarView: View {
    @Binding var selectedMode: AddBrowsingMode
    let onSelectMode: (AddBrowsingMode) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = AddBrowsingMode.songs.rawValue
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AddBrowsingMode.allCases) { m in
                ModalBrowsingModeTabPillView(
                    mode: m,
                    isSelected: activeHighlightId == m.rawValue,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard selectedMode != m else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeHighlightId = m.rawValue
                        }
                        onSelectMode(m)
                    }
                )
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeHighlightId = selectedMode.rawValue
        }
        .onChange(of: selectedMode) { _, newMode in
            if activeHighlightId != newMode.rawValue {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeHighlightId = newMode.rawValue
                }
            }
        }
    }
}

private struct ModalBrowsingModeTabPillView: View {
    let mode: AddBrowsingMode
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .frame(minHeight: 30)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ? Color.white : (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        ModalActivePillBackground(isHiRes: false, isHovered: isHovered)
                            .matchedGeometryEffect(id: "modalBrowsingTabHighlight", in: namespace)
                    } else if isHovered {
                        ModalHoverPillBackground()
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

// -----------------------------------------------------------------------------
// MODAL FORMAT SEGMENTED BAR (LIQUID GLASS SLIDING PILL)
// -----------------------------------------------------------------------------
private struct ModalFormatSegmentedBarView: View {
    let options: [ModalFilterOption]
    @Binding var selectedFormat: String
    let onSelectFormat: (String) -> Void
    
    @Namespace private var highlightNamespace
    @State private var activeHighlightId: String = "ALL"
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                ModalFormatTabPillView(
                    option: opt,
                    isSelected: activeHighlightId == opt.id,
                    namespace: highlightNamespace,
                    onSelect: {
                        guard selectedFormat != opt.id else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            activeHighlightId = opt.id
                        }
                        onSelectFormat(opt.id)
                    }
                )
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            activeHighlightId = selectedFormat
        }
        .onChange(of: selectedFormat) { _, newFormat in
            if activeHighlightId != newFormat {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    activeHighlightId = newFormat
                }
            }
        }
    }
}

private struct ModalFormatTabPillView: View {
    let option: ModalFilterOption
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                }
                Text(option.title)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                isSelected ?
                    (option.isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) :
                    (isHovered ? Color.white : Color.white.opacity(0.70))
            )
            .background(
                ZStack {
                    if isSelected {
                        ModalActivePillBackground(isHiRes: option.isHiRes, isHovered: isHovered)
                            .matchedGeometryEffect(id: "modalFormatTabHighlight", in: namespace)
                    } else if isHovered {
                        ModalHoverPillBackground()
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

private struct ModalActivePillBackground: View {
    let isHiRes: Bool
    let isHovered: Bool
    
    var body: some View {
        ZStack {
            Color.white.opacity(isHiRes ? 0.13 : 0.16)
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isHovered ? 0.42 : 0.35), location: 0.0),
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
                .stroke(
                    isHiRes ? WalkmanTheme.hiResGold.opacity(0.55) : Color.white.opacity(isHovered ? 0.45 : 0.34),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(0.25),
            radius: 3,
            x: 0,
            y: 1
        )
    }
}

private struct ModalHoverPillBackground: View {
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
                .frame(height: 5)
                Spacer(minLength: 0)
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.85)
        )
        .shadow(
            color: Color.black.opacity(0.15),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

private struct ModalAlbumItem: Identifiable {
    let id: String
    let name: String
    let artist: String
    let year: String
    let tracks: [Track]
    var trackCount: Int { tracks.count }
    var representativeTrack: Track? { tracks.first }
    var isHiRes: Bool { tracks.contains { $0.bitsPerSample > 16 || $0.sampleRate > 48000 } }
}

private struct ModalArtistItem: Identifiable {
    let id: String
    let name: String
    let tracks: [Track]
    let albumCount: Int
    var trackCount: Int { tracks.count }
    var representativeTrack: Track? { tracks.first }
}

private struct AddTracksModal: View {
    let playlistName: String
    let tracks: [Track]
    let existingPlaylistPaths: Set<String>
    let onAddTracks: ([String], Bool) -> Void
    let onDismiss: () -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var mode: AddBrowsingMode = .songs
    @State private var search: String = ""
    @State private var formatFilter: String = "ALL"
    @State private var hideExisting: Bool = false
    @State private var selectedTrackPaths: Set<String> = []
    @State private var addedInSessionPaths: Set<String> = []
    
    @State private var cachedAlbums: [ModalAlbumItem] = []
    @State private var cachedArtists: [ModalArtistItem] = []
    
    private func normalizeTrackKey(_ path: String) -> String {
        var s = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\r\n"))
            .lowercased()
        while s.hasPrefix("./") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if s.hasPrefix("music/") {
            s = String(s.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return s
    }
    
    private var normalizedExistingSet: Set<String> {
        var set = Set(existingPlaylistPaths.map { normalizeTrackKey($0) })
        for p in addedInSessionPaths {
            set.insert(normalizeTrackKey(p))
        }
        return set
    }
    
    private func isPathInPlaylist(_ path: String) -> Bool {
        normalizedExistingSet.contains(normalizeTrackKey(path))
    }
    
    private func isTrackInPlaylist(_ track: Track) -> Bool {
        isPathInPlaylist(track.relativePath)
    }
    
    private func addTrackInstantly(_ track: Track) {
        let key = track.relativePath
        guard !isTrackInPlaylist(track) else { return }
        addedInSessionPaths.insert(key)
        selectedTrackPaths.remove(key)
        onAddTracks([key], false)
    }
    
    private func addTracksInstantly(_ paths: [String]) {
        let unadded = paths.filter { !isPathInPlaylist($0) }
        guard !unadded.isEmpty else { return }
        for p in unadded {
            addedInSessionPaths.insert(p)
            selectedTrackPaths.remove(p)
        }
        onAddTracks(unadded, false)
    }
    
    private func isHiRes(_ track: Track) -> Bool {
        return track.bitsPerSample > 16 || track.sampleRate > 48000
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private static func buildAlbums(from tracks: [Track]) -> [ModalAlbumItem] {
        var grouped: [String: [Track]] = [:]
        var displayNames: [String: String] = [:]
        for t in tracks {
            let alb = t.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = alb.isEmpty ? "Unknown Album" : alb
            let key = name.lowercased()
            if displayNames[key] == nil { displayNames[key] = name }
            grouped[key, default: []].append(t)
        }
        var items: [ModalAlbumItem] = []
        for (key, trs) in grouped {
            let name = displayNames[key] ?? key
            let art = trs.first?.primaryArtist.isEmpty == false ? trs.first!.primaryArtist : (trs.first?.artist ?? "Unknown Artist")
            let yr = trs.first(where: { !$0.year.isEmpty })?.year ?? ""
            let sorted = trs.sorted {
                let n0 = Int($0.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                let n1 = Int($1.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
                return n0 < n1
            }
            items.append(ModalAlbumItem(id: key, name: name, artist: art, year: yr, tracks: sorted))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private static func buildArtists(from tracks: [Track]) -> [ModalArtistItem] {
        var grouped: [String: [Track]] = [:]
        for t in tracks {
            let art = t.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = art.isEmpty ? "Unknown Artist" : art
            grouped[name, default: []].append(t)
        }
        var items: [ModalArtistItem] = []
        for (name, trs) in grouped {
            let albumsSet = Set(trs.map { $0.album.lowercased() })
            items.append(ModalArtistItem(id: name, name: name, tracks: trs, albumCount: albumsSet.count))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    private func friendlyDateString(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
    }
    
    private var filteredTracks: [Track] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceList: [Track]
        if mode == .recentlyAdded {
            sourceList = tracks.sorted { $0.dateAdded > $1.dateAdded }
        } else {
            sourceList = tracks
        }
        return sourceList.filter { tr in
            if hideExisting && isTrackInPlaylist(tr) {
                return false
            }
            if formatFilter == "HI-RES" {
                if tr.bitsPerSample <= 16 && tr.sampleRate <= 48000 { return false }
            } else if formatFilter != "ALL" {
                if tr.format != formatFilter { return false }
            }
            if !q.isEmpty {
                let match = tr.title.lowercased().contains(q)
                    || tr.artist.lowercased().contains(q)
                    || tr.album.lowercased().contains(q)
                    || tr.filename.lowercased().contains(q)
                if !match { return false }
            }
            return true
        }
    }
    
    private var filteredAlbums: [ModalAlbumItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cachedAlbums.compactMap { alb in
            let matchingTracks = alb.tracks.filter { tr in
                if hideExisting && isTrackInPlaylist(tr) {
                    return false
                }
                if formatFilter == "HI-RES" {
                    if tr.bitsPerSample <= 16 && tr.sampleRate <= 48000 { return false }
                } else if formatFilter != "ALL" {
                    if tr.format != formatFilter { return false }
                }
                return true
            }
            if matchingTracks.isEmpty { return nil }
            
            if !q.isEmpty {
                let match = alb.name.lowercased().contains(q)
                    || alb.artist.lowercased().contains(q)
                    || matchingTracks.contains(where: { $0.title.lowercased().contains(q) })
                if !match { return nil }
            }
            return ModalAlbumItem(id: alb.id, name: alb.name, artist: alb.artist, year: alb.year, tracks: matchingTracks)
        }
    }
    
    private var filteredArtists: [ModalArtistItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cachedArtists.compactMap { art in
            let matchingTracks = art.tracks.filter { tr in
                if hideExisting && isTrackInPlaylist(tr) {
                    return false
                }
                if formatFilter == "HI-RES" {
                    if tr.bitsPerSample <= 16 && tr.sampleRate <= 48000 { return false }
                } else if formatFilter != "ALL" {
                    if tr.format != formatFilter { return false }
                }
                return true
            }
            if matchingTracks.isEmpty { return nil }
            
            if !q.isEmpty {
                let match = art.name.lowercased().contains(q)
                    || matchingTracks.contains(where: { $0.title.lowercased().contains(q) || $0.album.lowercased().contains(q) })
                if !match { return nil }
            }
            return ModalArtistItem(id: art.id, name: art.name, tracks: matchingTracks, albumCount: art.albumCount)
        }
    }
    
    private var resultsCountLabel: String {
        switch mode {
        case .songs:
            return "\(filteredTracks.count.formatted()) songs"
        case .recentlyAdded:
            return "\(filteredTracks.count.formatted()) recent songs"
        case .albums:
            return "\(filteredAlbums.count.formatted()) albums"
        case .artists:
            return "\(filteredArtists.count.formatted()) artists"
        }
    }
    
    private var visibleSelectablePaths: [String] {
        switch mode {
        case .songs, .recentlyAdded:
            return filteredTracks.map(\.relativePath)
        case .albums:
            return filteredAlbums.flatMap { $0.tracks.map(\.relativePath) }
        case .artists:
            return filteredArtists.flatMap { $0.tracks.map(\.relativePath) }
        }
    }
    
    private var visibleUnselectedCount: Int {
        let set = selectedTrackPaths
        return visibleSelectablePaths.filter { !set.contains($0) }.count
    }
    
    private func selectAllVisible() {
        selectedTrackPaths.formUnion(visibleSelectablePaths)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WalkmanTheme.card)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Tracks to Playlist")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 6) {
                        Text("Target Playlist:")
                            .foregroundStyle(.secondary)
                        Text(playlistName)
                            .font(WalkmanFont.subheadlineBold)
                            .foregroundStyle(.white)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(existingPlaylistPaths.count) tracks currently in playlist")
                            .foregroundStyle(.secondary)
                    }
                    .font(WalkmanFont.subheadline)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel & Close (Esc)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            
            // Search & Navigation Toolbar
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Mode Picker (Songs / Recently Added / By Album / By Artist)
                    ModalBrowsingModeSegmentedBarView(
                        selectedMode: $mode,
                        onSelectMode: { newMode in
                            mode = newMode
                        }
                    )
                    
                    // Search Field (Liquid Glass Capsule)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(search.isEmpty ? WalkmanTheme.silverMuted : WalkmanTheme.silverLight)
                        
                        TextField(
                            (mode == .songs || mode == .recentlyAdded) ? "Search songs by title, artist, album..." :
                            mode == .albums ? "Search albums by title or artist..." :
                            "Search artists...",
                            text: $search
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        
                        if !search.isEmpty {
                            Button(action: { search = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .background(
                        ZStack {
                            Color.white.opacity(0.06)
                            VStack(spacing: 0) {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.14), location: 0.0),
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
                        Capsule().stroke(search.isEmpty ? Color.white.opacity(0.12) : Color.white.opacity(0.30), lineWidth: 0.85)
                    )
                }
                
                // Secondary Filter Controls: Format Picker & Toggle
                HStack(spacing: 14) {
                    ModalFormatSegmentedBarView(
                        options: modalFormatOptions,
                        selectedFormat: $formatFilter,
                        onSelectFormat: { newFmt in
                            formatFilter = newFmt
                        }
                    )
                    
                    Toggle(isOn: $hideExisting) {
                        HStack(spacing: 5) {
                            Image(systemName: hideExisting ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                            Text("Hide songs already in playlist")
                                .font(WalkmanFont.subheadline)
                        }
                    }
                    .toggleStyle(.checkbox)
                    
                    Spacer()
                    
                    Text(resultsCountLabel)
                        .font(WalkmanFont.mono)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Content Body
            ZStack {
                Color.black.opacity(0.18)
                
                switch mode {
                case .songs, .recentlyAdded:
                    if filteredTracks.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: mode == .recentlyAdded ? "clock.arrow.circlepath" : "music.note")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text(mode == .recentlyAdded ? "No recently added tracks" : "No matching tracks")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.secondary)
                            Text(hideExisting
                                 ? "All matching tracks may already be in the playlist. Try unchecking 'Hide songs already in playlist'."
                                 : "Try clearing your search query or choosing 'All Formats'.")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 380)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filteredTracks) { tr in
                                    let isSel = selectedTrackPaths.contains(tr.relativePath)
                                    let isInPlaylist = isTrackInPlaylist(tr)
                                    let isCurrent = player.currentTrack?.relativePath == tr.relativePath
                                    let isPlayingThis = isCurrent && player.isPlaying
                                    let dateText = (mode == .recentlyAdded) ? friendlyDateString(for: tr.dateAdded) : nil
                                    
                                    ModalTrackRow(
                                        track: tr,
                                        isSelected: isSel,
                                        isInPlaylist: isInPlaylist,
                                        isPlaying: isPlayingThis,
                                        dateAddedText: dateText,
                                        onToggleSelect: {
                                            if isSel {
                                                selectedTrackPaths.remove(tr.relativePath)
                                            } else {
                                                selectedTrackPaths.insert(tr.relativePath)
                                            }
                                        },
                                        onInstantAdd: {
                                            addTrackInstantly(tr)
                                        },
                                        onTogglePlay: {
                                            if isPlayingThis {
                                                player.pause()
                                            } else {
                                                player.play(track: tr, in: filteredTracks)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    
                case .albums:
                    if filteredAlbums.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "square.stack")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No matching albums")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredAlbums) { alb in
                                    let albumPaths = alb.tracks.map(\.relativePath)
                                    let isAllInPlaylist = !albumPaths.isEmpty && albumPaths.allSatisfy { isPathInPlaylist($0) }
                                    let unaddedCount = albumPaths.filter { !isPathInPlaylist($0) }.count
                                    let isAllSel = !albumPaths.isEmpty && albumPaths.allSatisfy { selectedTrackPaths.contains($0) }
                                    let selCount = albumPaths.filter { selectedTrackPaths.contains($0) }.count
                                    
                                    ModalAlbumRow(
                                        album: alb,
                                        isAllInPlaylist: isAllInPlaylist,
                                        unaddedCount: unaddedCount,
                                        isAllSelected: isAllSel,
                                        selectedCount: selCount,
                                        onToggleSelect: {
                                            if isAllSel {
                                                for p in albumPaths { selectedTrackPaths.remove(p) }
                                            } else {
                                                selectedTrackPaths.formUnion(albumPaths)
                                            }
                                        },
                                        onInstantAdd: {
                                            addTracksInstantly(albumPaths)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    
                case .artists:
                    if filteredArtists.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "person.2")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No matching artists")
                                .font(WalkmanFont.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredArtists) { art in
                                    let artistPaths = art.tracks.map(\.relativePath)
                                    let isAllInPlaylist = !artistPaths.isEmpty && artistPaths.allSatisfy { isPathInPlaylist($0) }
                                    let unaddedCount = artistPaths.filter { !isPathInPlaylist($0) }.count
                                    let isAllSel = !artistPaths.isEmpty && artistPaths.allSatisfy { selectedTrackPaths.contains($0) }
                                    let selCount = artistPaths.filter { selectedTrackPaths.contains($0) }.count
                                    
                                    ModalArtistRow(
                                        artist: art,
                                        isAllInPlaylist: isAllInPlaylist,
                                        unaddedCount: unaddedCount,
                                        isAllSelected: isAllSel,
                                        selectedCount: selCount,
                                        onToggleSelect: {
                                            if isAllSel {
                                                for p in artistPaths { selectedTrackPaths.remove(p) }
                                            } else {
                                                selectedTrackPaths.formUnion(artistPaths)
                                            }
                                        },
                                        onInstantAdd: {
                                            addTracksInstantly(artistPaths)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom Action Footer Bar
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            HStack(spacing: 14) {
                // Left: Selection Counter & Bulk Controls
                HStack(spacing: 10) {
                    if selectedTrackPaths.isEmpty {
                        Text(addedInSessionPaths.isEmpty ? "No tracks selected" : "\(addedInSessionPaths.count) added to Walkman")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(addedInSessionPaths.isEmpty ? .secondary : WalkmanTheme.silverLight)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(WalkmanTheme.silverLight)
                            Text("\(selectedTrackPaths.count) \(selectedTrackPaths.count == 1 ? "track" : "tracks") selected")
                                .font(WalkmanFont.calloutBold)
                                .foregroundStyle(.white)
                        }
                        
                        Button("Clear") {
                            selectedTrackPaths.removeAll()
                        }
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    }
                    
                    if visibleUnselectedCount > 0 {
                        Button("Select All Visible (\(visibleUnselectedCount))") {
                            selectAllVisible()
                        }
                        .font(WalkmanFont.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .buttonStyle(LiquidGlassButtonStyle(variant: .subtle, cornerRadius: 8))
                    }
                }
                
                Spacer()
                
                // Right: Close / Add / Done Button
                Button("Close") {
                    onDismiss()
                }
                .font(WalkmanFont.calloutMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(WalkmanTheme.silverLight)
                .buttonStyle(LiquidGlassButtonStyle(variant: .glass, cornerRadius: 14))
                .keyboardShortcut(.cancelAction)
                
                if !selectedTrackPaths.isEmpty {
                    Button(action: {
                        var ordered = tracks.filter { selectedTrackPaths.contains($0.relativePath) }.map(\.relativePath)
                        let addedSet = Set(ordered)
                        for p in selectedTrackPaths where !addedSet.contains(p) {
                            ordered.append(p)
                        }
                        onAddTracks(ordered, true)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add \(selectedTrackPaths.count) \(selectedTrackPaths.count == 1 ? "Track" : "Tracks")")
                                .font(WalkmanFont.calloutBold)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 14))
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: onDismiss) {
                        HStack(spacing: 5) {
                            if !addedInSessionPaths.isEmpty {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text("Done")
                                .font(WalkmanFont.calloutBold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .foregroundStyle(addedInSessionPaths.isEmpty ? WalkmanTheme.silverLight : Color(red: 20/255, green: 20/255, blue: 24/255))
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: addedInSessionPaths.isEmpty ? .glass : .prominent, cornerRadius: 14))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(WalkmanTheme.card)
        }
        .frame(minWidth: 720, idealWidth: 920, maxWidth: 1180, minHeight: 560, idealHeight: 700, maxHeight: 900)
        .background(WalkmanTheme.background)
        .onAppear {
            cachedAlbums = Self.buildAlbums(from: tracks)
            cachedArtists = Self.buildArtists(from: tracks)
        }
    }
}

// MARK: - Subviews for AddTracksModal

private struct ModalTrackRow: View {
    let track: Track
    let isSelected: Bool
    let isInPlaylist: Bool
    let isPlaying: Bool
    var dateAddedText: String? = nil
    let onToggleSelect: () -> Void
    let onInstantAdd: () -> Void
    let onTogglePlay: () -> Void
    
    @State private var isHovered = false
    
    private var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }
    
    private var formattedDuration: String {
        if track.durationSeconds <= 0 { return "—" }
        let mins = Int(track.durationSeconds) / 60
        let secs = Int(track.durationSeconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? WalkmanTheme.silverLight : Color.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            
            Button(action: onTogglePlay) {
                TrackCoverThumbnail(track: track, size: 36, isPlaying: isPlaying)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause preview" : "Play preview")
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(isSelected ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                        .foregroundStyle(isSelected ? .white : (isHovered ? .white : .primary))
                        .lineLimit(1)
                    
                    if isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    }
                }
                
                Text("\(track.artist) — \(track.album)")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let dt = dateAddedText {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(dt)
                }
                .font(WalkmanFont.badge)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            
            Text(track.format)
                .font(WalkmanFont.badge)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .foregroundStyle(WalkmanTheme.silverMuted)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            
            Text(formattedDuration)
                .font(WalkmanFont.mono)
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
            
            if isInPlaylist {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("In Playlist")
                        .font(WalkmanFont.badge)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button(action: onInstantAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 6))
                .fixedSize(horizontal: true, vertical: false)
                .help("Add track instantly to playlist on Walkman")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? WalkmanTheme.cardHover : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.015)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? WalkmanTheme.silver.opacity(0.35) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04)), lineWidth: 1)
        )
        .scaleEffect(isHovered && !isSelected ? 1.01 : 1.0)
        .contentShape(Rectangle())
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
        .onTapGesture {
            onToggleSelect()
        }
    }
}

private struct ModalAlbumRow: View {
    let album: ModalAlbumItem
    let isAllInPlaylist: Bool
    let unaddedCount: Int
    let isAllSelected: Bool
    let selectedCount: Int
    let onToggleSelect: () -> Void
    let onInstantAdd: () -> Void
    
    @State private var isHovered = false
    
    private var remainingCount: Int {
        album.trackCount - selectedCount
    }
    
    var body: some View {
        HStack(spacing: 14) {
            if let rep = album.representativeTrack {
                TrackCoverThumbnail(track: rep, size: 44)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(album.name)
                        .font(WalkmanFont.bodyBold)
                        .foregroundStyle(isHovered ? Color.white : .white)
                        .lineLimit(1)
                    
                    if album.isHiRes {
                        Text("Hi-Res")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(WalkmanTheme.hiResGoldGradient)
                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                            .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    }
                }
                
                Text(album.artist)
                    .font(WalkmanFont.callout)
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(album.trackCount) songs")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.tertiary)
                    
                    if !album.year.isEmpty {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(album.year)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if isAllInPlaylist {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("All in playlist")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    } else if selectedCount > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(selectedCount) / \(album.trackCount) selected")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
            }
            
            Spacer()
            
            if isAllInPlaylist {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("In Playlist")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(Capsule())
            } else {
                Button(action: onInstantAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(unaddedCount < album.trackCount
                             ? "Add Remaining (\(unaddedCount))"
                             : "Add Album (\(album.trackCount))")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 6))
                .help("Add all unadded tracks of this album directly to playlist")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isAllSelected ? WalkmanTheme.cardHover : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.35) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04)), lineWidth: 1)
        )
        .scaleEffect(isHovered && !isAllSelected ? 1.01 : 1.0)
        .contentShape(Rectangle())
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
        .onTapGesture {
            onToggleSelect()
        }
    }
}

private struct ModalArtistRow: View {
    let artist: ModalArtistItem
    let isAllInPlaylist: Bool
    let unaddedCount: Int
    let isAllSelected: Bool
    let selectedCount: Int
    let onToggleSelect: () -> Void
    let onInstantAdd: () -> Void
    
    @State private var isHovered = false
    
    private var remainingCount: Int {
        artist.trackCount - selectedCount
    }
    
    var body: some View {
        HStack(spacing: 14) {
            ArtistAvatarView(
                artistName: artist.name,
                representativeTrack: artist.representativeTrack,
                size: 40,
                isSelected: isAllSelected
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(WalkmanFont.bodyBold)
                    .foregroundStyle(isHovered ? Color.white : .white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text("\(artist.albumCount) albums • \(artist.trackCount) songs")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(WalkmanTheme.silverMuted)
                    
                    if isAllInPlaylist {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("All in playlist")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    } else if selectedCount > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(selectedCount) / \(artist.trackCount) selected")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
            }
            
            Spacer()
            
            if isAllInPlaylist {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("In Playlist")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(Capsule())
            } else {
                Button(action: onInstantAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(unaddedCount < artist.trackCount
                             ? "Add Remaining (\(unaddedCount))"
                             : "Add All Songs (\(artist.trackCount))")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 6))
                .help("Add all unadded songs by this artist directly to playlist")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isAllSelected ? WalkmanTheme.cardHover : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.35) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04)), lineWidth: 1)
        )
        .scaleEffect(isHovered && !isAllSelected ? 1.01 : 1.0)
        .contentShape(Rectangle())
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
        .onTapGesture {
            onToggleSelect()
        }
    }
}
