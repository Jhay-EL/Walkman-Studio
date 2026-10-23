import SwiftUI

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
    
    public init(activeDrive: WalkmanDrive?, libraryTracks: [Track]) {
        self.activeDrive = activeDrive
        self.libraryTracks = libraryTracks
        _cachedTrackLookup = State(initialValue: PlaylistsView.buildLookupTable(tracks: libraryTracks))
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
        let lookup = cachedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = PlaylistsView.normalizeKey(p1)
            let k2 = PlaylistsView.normalizeKey(p2)
            let t1 = lookup[k1]?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let t2 = lookup[k2]?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name1 = (t1?.isEmpty == false ? t1! : (p1 as NSString).lastPathComponent)
            let name2 = (t2?.isEmpty == false ? t2! : (p2 as NSString).lastPathComponent)
            let cmp = name1.localizedStandardCompare(name2)
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func sortTracksByArtist(ascending: Bool) {
        let lookup = cachedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = PlaylistsView.normalizeKey(p1)
            let k2 = PlaylistsView.normalizeKey(p2)
            let a1 = lookup[k1]?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let a2 = lookup[k2]?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cmp = a1.localizedStandardCompare(a2)
            if cmp == .orderedSame {
                let t1 = lookup[k1]?.title ?? (p1 as NSString).lastPathComponent
                let t2 = lookup[k2]?.title ?? (p2 as NSString).lastPathComponent
                return t1.localizedStandardCompare(t2) == .orderedAscending
            }
            return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
        persistPlaylistChanges(newTracks: sorted)
    }
    
    private func sortTracksByAlbum() {
        let lookup = cachedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = PlaylistsView.normalizeKey(p1)
            let k2 = PlaylistsView.normalizeKey(p2)
            let alb1 = lookup[k1]?.album.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let alb2 = lookup[k2]?.album.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cmpAlb = alb1.localizedStandardCompare(alb2)
            if cmpAlb != .orderedSame {
                return cmpAlb == .orderedAscending
            }
            let n1 = Int(lookup[k1]?.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            let n2 = Int(lookup[k2]?.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            if n1 != n2 {
                return n1 < n2
            }
            let t1 = lookup[k1]?.title ?? (p1 as NSString).lastPathComponent
            let t2 = lookup[k2]?.title ?? (p2 as NSString).lastPathComponent
            return t1.localizedStandardCompare(t2) == .orderedAscending
        }
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
            
            VStack(spacing: isCompact ? 10 : 14) {
                // Header / Status Banner
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Walkman .M3U8 Playlists")
                                .font(WalkmanFont.title3)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            if !isNarrow {
                                Text("CRLF / Relative POSIX")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text("Playlists stored in \(activeDrive?.name ?? "Drive")/MUSIC/ and /LEARNING/ for instant hardware discovery")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    Spacer(minLength: 8)
                    
                    if let banner = messageBanner {
                        Text(banner)
                            .font(WalkmanFont.subheadlineMedium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Capsule())
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    Button(action: createNewPlaylist) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text(isNarrow ? "New" : "New Playlist")
                                .lineLimit(1)
                        }
                        .font(WalkmanFont.calloutBold)
                        .padding(.horizontal, isNarrow ? 10 : 14)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(activeDrive == nil)
                    .opacity(activeDrive == nil ? 0.5 : 1.0)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(activeDrive == nil ? "Connect a Walkman to create playlists" : "Create a new playlist on the Walkman")
                }
                .padding(.horizontal, 4)
                
                // Main 2-Column Layout
                HStack(spacing: colSpacing) {
                    // Left Column: Playlist List
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("PLAYLISTS (\(playlists.count))")
                                .font(WalkmanFont.sectionHeader)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer()
                    }
                    .padding(.horizontal, 8)
                    
                    if playlists.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "music.note.list")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("No Playlists Found")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(.secondary)
                            Text("Create one to organize your tracks")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.tertiary)
                            
                            Button(action: createNewPlaylist) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                    Text("New Playlist")
                                }
                                .font(WalkmanFont.calloutBold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(WalkmanTheme.silverGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(activeDrive == nil)
                            .opacity(activeDrive == nil ? 0.5 : 1.0)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(playlists) { pl in
                                    let isSel = selectedPlaylist?.id == pl.id
                                    let isEditingRow = (editingPlaylistId == pl.id && renameLocation == .row)
                                    
                                    if isEditingRow {
                                        HStack(spacing: 6) {
                                            Image(systemName: "list.bullet")
                                                .font(.system(size: 12))
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                            
                                            TextField("Playlist Name", text: $editingPlaylistName)
                                                .textFieldStyle(.plain)
                                                .font(WalkmanFont.bodyMedium)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(WalkmanTheme.surface)
                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .stroke(WalkmanTheme.silverLight.opacity(0.8), lineWidth: 1)
                                                )
                                                .focused($isRowRenameFocused)
                                                .onSubmit {
                                                    commitRename(for: pl)
                                                }
                                                .onExitCommand {
                                                    cancelRename()
                                                }
                                            
                                            Button(action: { commitRename(for: pl) }) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.green)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Save Name (Return)")
                                            
                                            Button(action: cancelRename) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Cancel (Esc)")
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(WalkmanTheme.cardHover)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(WalkmanTheme.silverLight.opacity(0.6), lineWidth: 1)
                                        )
                                    } else {
                                        HStack(spacing: 10) {
                                            Image(systemName: pl.isLanguageStudy ? "character.book.closed.fill" : "list.bullet")
                                                .font(.system(size: 12))
                                                .foregroundStyle(isSel ? WalkmanTheme.silverLight : (pl.isLanguageStudy ? WalkmanTheme.silverMuted : .secondary))
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(pl.name)
                                                        .font(isSel ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                                        .foregroundStyle(isSel ? .white : .primary)
                                                        .lineLimit(1)
                                                    
                                                    if pl.isLanguageStudy {
                                                        Text("LEARNING")
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundStyle(WalkmanTheme.silverLight)
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 1)
                                                            .background(WalkmanTheme.cardHover)
                                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                                    }
                                                }
                                                
                                                Text("\(pl.trackCount) tracks")
                                                    .font(WalkmanFont.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 6) {
                                                Button(action: { startRenaming(pl, location: .row) }) {
                                                    Image(systemName: "pencil")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(WalkmanTheme.silverLight)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Rename Playlist")
                                                
                                                Button(action: { deletePlaylist(pl) }) {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Delete Playlist")
                                            }
                                            .opacity(isSel ? 1 : 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(isSel ? WalkmanTheme.cardHover : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(isSel ? WalkmanTheme.silver.opacity(0.4) : Color.clear, lineWidth: 1)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let editId = editingPlaylistId, let curPl = playlists.first(where: { $0.id == editId }) {
                                                commitRename(for: curPl)
                                            }
                                            selectedPlaylist = pl
                                            playlistTracks = pl.tracks
                                        }
                                        .contextMenu {
                                            Button(action: { startRenaming(pl, location: .row) }) {
                                                Label("Rename Playlist", systemImage: "pencil")
                                            }
                                            Divider()
                                            Button(role: .destructive, action: { deletePlaylist(pl) }) {
                                                Label("Delete Playlist", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(isCompact ? 10 : 12)
                .frame(width: sidebarWidth)
                .liquidGlass(cornerRadius: 12)
                
                // Right Column: Playlist Content / Editor
                VStack(alignment: .leading, spacing: isCompact ? 10 : 12) {
                    if let pl = selectedPlaylist {
                        playlistDetailHeader(pl: pl)
                        
                        // Tracks List
                        if playlistTracks.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "tray")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.tertiary)
                                Text("This playlist is empty")
                                    .font(WalkmanFont.bodyMedium)
                                    .foregroundStyle(.secondary)
                                Text("Click 'Add From Library' to populate this playlist")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(playlistTracks.enumerated()), id: \.offset) { index, trackPath in
                                        let matchedTrack = resolvedTrack(for: trackPath)
                                        let isPlayingThis = (AudioPlayerService.shared.currentTrack?.relativePath == trackPath || AudioPlayerService.shared.currentTrack?.fullPath == matchedTrack?.fullPath) && AudioPlayerService.shared.isPlaying
                                        
                                        PlaylistTrackRow(
                                            index: index,
                                            totalCount: playlistTracks.count,
                                            trackPath: trackPath,
                                            matchedTrack: matchedTrack,
                                            isPlayingThis: isPlayingThis,
                                            onPlay: {
                                                if let tr = matchedTrack {
                                                    if isPlayingThis {
                                                        AudioPlayerService.shared.pause()
                                                    } else {
                                                        AudioPlayerService.shared.play(track: tr, in: libraryTracks)
                                                    }
                                                }
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
                                            }
                                        )
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlass(cornerRadius: 12)
            }
        }
        .onAppear {
            if cachedTrackLookup.isEmpty && !libraryTracks.isEmpty {
                cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
            }
            loadPlaylists()
        }
        .onChange(of: libraryTracks) {
            cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
        }
        .onChange(of: activeDrive?.mountPoint) {
            cachedTrackLookup = PlaylistsView.buildLookupTable(tracks: libraryTracks)
            loadPlaylists()
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
                
                autoSavedBadge(compact: false)
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
                
                autoSavedBadge(compact: true)
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
                    
                    autoSavedBadge(compact: false)
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
                    
                    autoSavedBadge(compact: true)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WalkmanTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(WalkmanTheme.silverLight.opacity(0.8), lineWidth: 1)
                )
                .focused($isHeaderRenameFocused)
                .onSubmit { commitRename(for: pl) }
                .onExitCommand { cancelRename() }
                .frame(maxWidth: 240)
            
            Button(action: { commitRename(for: pl) }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Save")
                        .lineLimit(1)
                }
                .font(WalkmanFont.calloutBold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WalkmanTheme.silverGradient)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            
            Button(action: cancelRename) {
                Text("Cancel")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
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
    private func autoSavedBadge(compact: Bool = false) -> some View {
        HStack(spacing: 5) {
            if isSaving {
                ProgressView()
                    .controlSize(.mini)
                Text(compact ? "Saving" : "Saving...")
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                Text(compact ? "Auto-saved" : "Auto-saved to Walkman")
                    .lineLimit(1)
            }
        }
        .font(WalkmanFont.subheadlineMedium)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(Color.white.opacity(0.06))
        .foregroundStyle(WalkmanTheme.silverLight)
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
    
    @ViewBuilder
    private var sortMenuButton: some View {
        Menu {
            Button(action: { sortTracksByTitle(ascending: true) }) {
                Label("Title (A → Z)", systemImage: "textformat")
            }
            Button(action: { sortTracksByTitle(ascending: false) }) {
                Label("Title (Z → A)", systemImage: "textformat")
            }
            Button(action: { sortTracksByArtist(ascending: true) }) {
                Label("Artist (A → Z)", systemImage: "person")
            }
            Button(action: { sortTracksByAlbum() }) {
                Label("Album & Track Number", systemImage: "square.stack")
            }
            Button(action: { sortTracksByFilename(ascending: true) }) {
                Label("Filename (A → Z)", systemImage: "doc.text")
            }
            Divider()
            Button(action: { reverseTrackOrder() }) {
                Label("Reverse Current Order", systemImage: "arrow.up.arrow.down")
            }
            Button(action: { shuffleTracks() }) {
                Label("Shuffle Order", systemImage: "shuffle")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort")
                    .lineLimit(1)
            }
            .font(WalkmanFont.calloutMedium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(WalkmanTheme.card)
            .foregroundStyle(WalkmanTheme.silverLight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: true, vertical: false)
        }
        .menuStyle(.borderlessButton)
        .disabled(playlistTracks.isEmpty)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    @ViewBuilder
    private func addFromLibraryButton(compact: Bool = false) -> some View {
        Button(action: { showAddTrackSheet = true }) {
            HStack(spacing: 5) {
                Image(systemName: "plus.circle")
                Text(compact ? "Add" : "Add From Library")
                    .lineLimit(1)
            }
            .font(WalkmanFont.calloutMedium)
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, 6)
            .background(WalkmanTheme.card)
            .foregroundStyle(WalkmanTheme.silverLight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
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
    let onPlay: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToTop: () -> Void
    let onMoveToBottom: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(WalkmanFont.mono)
                .foregroundStyle(WalkmanTheme.silverLight)
                .frame(width: 26, alignment: .trailing)
            
            // Play / Note button
            Button(action: onPlay) {
                Image(systemName: isPlayingThis ? "speaker.wave.2.fill" : (matchedTrack != nil ? "play.circle" : "music.note"))
                    .font(.system(size: 13))
                    .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(matchedTrack == nil)
            
            // Track Details or Path
            VStack(alignment: .leading, spacing: 2) {
                if let tr = matchedTrack, !tr.title.isEmpty {
                    Text(tr.title)
                        .font(WalkmanFont.bodyMedium)
                        .foregroundStyle(isPlayingThis ? WalkmanTheme.silverLight : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 6) {
                        if !tr.artist.isEmpty {
                            Text(tr.artist)
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if !tr.album.isEmpty {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(tr.album)
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(trackPath)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Text(trackPath)
                        .font(WalkmanFont.mono)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            Spacer()
            
            // Move Up
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("Move Up")
            
            // Move Down
            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(index == totalCount - 1)
            .help("Move Down")
            
            // Remove
            Button(action: onRemove) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove from Playlist")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isPlayingThis ? WalkmanTheme.cardHover : WalkmanTheme.card.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
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
                    Picker("", selection: $mode) {
                        ForEach(AddBrowsingMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 440)
                    
                    // Search Field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        TextField(
                            (mode == .songs || mode == .recentlyAdded) ? "Search songs by title, artist, album..." :
                            mode == .albums ? "Search albums by title or artist..." :
                            "Search artists...",
                            text: $search
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        
                        if !search.isEmpty {
                            Button(action: { search = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Secondary Filter Controls: Format Picker & Toggle
                HStack(spacing: 14) {
                    Picker("", selection: $formatFilter) {
                        Text("All Formats").tag("ALL")
                        Text("FLAC").tag("FLAC")
                        Text("MP3").tag("MP3")
                        Text("Hi-Res").tag("HI-RES")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    
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
                        .foregroundStyle(.secondary)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.06))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .buttonStyle(.plain)
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
                .background(Color.white.opacity(0.08))
                .foregroundStyle(.white.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
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
                        .background(WalkmanTheme.silverGradient)
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
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
                        .background(addedInSessionPaths.isEmpty ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(WalkmanTheme.silverGradient))
                        .foregroundStyle(addedInSessionPaths.isEmpty ? .white : Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(red: 16/255, green: 16/255, blue: 18/255))
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
                        .foregroundStyle(isSelected ? .white : .primary)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .help("Add track instantly to playlist on Walkman")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? WalkmanTheme.cardHover : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? WalkmanTheme.silver.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
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
                        .foregroundStyle(.white)
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
                    .foregroundStyle(.secondary)
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
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Add all unadded tracks of this album directly to playlist")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isAllSelected ? WalkmanTheme.cardHover : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
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
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text("\(artist.albumCount) albums • \(artist.trackCount) songs")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                    
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
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Add all unadded songs by this artist directly to playlist")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isAllSelected ? WalkmanTheme.cardHover : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleSelect()
        }
    }
}
