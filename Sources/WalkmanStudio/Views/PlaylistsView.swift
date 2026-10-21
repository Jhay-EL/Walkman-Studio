import SwiftUI

public struct PlaylistsView: View {
    let activeDrive: WalkmanDrive?
    let libraryTracks: [Track]
    
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: Playlist?
    @State private var playlistTracks: [String] = []
    @State private var newPlaylistName: String = ""
    @State private var isCreating: Bool = false
    @State private var showAddTrackSheet: Bool = false
    @State private var searchTrackQuery: String = ""
    @State private var messageBanner: String?
    @State private var isSaving: Bool = false
    
    public init(activeDrive: WalkmanDrive?, libraryTracks: [Track]) {
        self.activeDrive = activeDrive
        self.libraryTracks = libraryTracks
    }
    
    private func loadPlaylists() {
        guard let drive = activeDrive else {
            playlists = []
            selectedPlaylist = nil
            playlistTracks = []
            return
        }
        
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: musicURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            playlists = []
            return
        }
        
        var list: [Playlist] = []
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
        
        self.playlists = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let current = selectedPlaylist, let updated = playlists.first(where: { $0.id == current.id }) {
            self.selectedPlaylist = updated
            self.playlistTracks = updated.tracks
        } else if selectedPlaylist == nil {
            self.selectedPlaylist = playlists.first
            self.playlistTracks = playlists.first?.tracks ?? []
        }
    }
    
    private var normalizedTrackLookup: [String: Track] {
        var dict: [String: Track] = [:]
        for track in libraryTracks {
            let key = track.relativePath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            dict[key] = track
        }
        return dict
    }
    
    private func resolvedTrack(for path: String) -> Track? {
        let key = path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedTrackLookup[key]
    }
    
    private func persistPlaylistChanges(newTracks: [String]) {
        guard let drive = activeDrive, let playlist = selectedPlaylist else { return }
        self.playlistTracks = newTracks
        self.isSaving = true
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        let filenameToSave = playlist.filename.isEmpty ? playlist.name : playlist.filename
        do {
            let savedURL = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: filenameToSave,
                relativeTracks: newTracks
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
                messageBanner = "Saved to Walkman (\(newTracks.count) \(newTracks.count == 1 ? "track" : "tracks"))"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.messageBanner?.hasPrefix("Saved to Walkman") == true {
                    withAnimation { self.messageBanner = nil }
                }
            }
        } catch {
            self.isSaving = false
            withAnimation {
                messageBanner = "Auto-save error: \(error.localizedDescription)"
            }
        }
    }
    
    private func sortTracksByTitle(ascending: Bool) {
        let lookup = normalizedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = p1.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let k2 = p2.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
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
        let lookup = normalizedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = p1.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let k2 = p2.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
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
        let lookup = normalizedTrackLookup
        let sorted = playlistTracks.sorted { p1, p2 in
            let k1 = p1.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let k2 = p2.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
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
    
    private func createPlaylist() {
        guard let drive = activeDrive else { return }
        let clean = WalkmanEngine.shared.sanitizeFilename(newPlaylistName)
        guard !clean.isEmpty else { return }
        
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        do {
            _ = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: clean,
                relativeTracks: []
            )
            newPlaylistName = ""
            isCreating = false
            loadPlaylists()
            if let created = playlists.first(where: { $0.name == clean }) {
                selectedPlaylist = created
                playlistTracks = []
            }
        } catch {
            messageBanner = "Failed to create: \(error.localizedDescription)"
        }
    }
    
    private func deletePlaylist(_ playlist: Playlist) {
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
        VStack(spacing: 16) {
            // Header / Status Banner
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Walkman .M3U8 Playlists")
                            .font(WalkmanFont.title3)
                            .foregroundStyle(.white)
                        
                        Text("CRLF / Relative POSIX")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Capsule())
                    }
                    
                    Text("Playlists stored in \(activeDrive?.name ?? "Drive")/MUSIC/ for instant hardware discovery")
                        .font(WalkmanFont.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let banner = messageBanner {
                    Text(banner)
                        .font(WalkmanFont.subheadlineMedium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(Capsule())
                }
                
                Button(action: { isCreating = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Playlist")
                    }
                    .font(WalkmanFont.calloutBold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            // Main 2-Column Layout
            HStack(spacing: 14) {
                // Left Column: Playlist List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("PLAYLISTS (\(playlists.count))")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    
                    if isCreating {
                        HStack(spacing: 6) {
                            TextField("Playlist Name...", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .padding(6)
                                .background(WalkmanTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onSubmit { createPlaylist() }
                            
                            Button("Save") { createPlaylist() }
                                .font(WalkmanFont.calloutBold)
                                .foregroundStyle(WalkmanTheme.silverLight)
                            
                            Button("Cancel") { isCreating = false }
                                .font(WalkmanFont.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .liquidGlass(cornerRadius: 8)
                    }
                    
                    if playlists.isEmpty {
                        VStack(spacing: 8) {
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
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(playlists) { pl in
                                    let isSel = selectedPlaylist?.id == pl.id
                                    HStack(spacing: 10) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 12))
                                            .foregroundStyle(isSel ? WalkmanTheme.silverLight : .secondary)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pl.name)
                                                .font(isSel ? WalkmanFont.bodyBold : WalkmanFont.bodyMedium)
                                                .foregroundStyle(isSel ? .white : .primary)
                                            
                                            Text("\(pl.trackCount) tracks")
                                                .font(WalkmanFont.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: { deletePlaylist(pl) }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
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
                                        selectedPlaylist = pl
                                        playlistTracks = pl.tracks
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(width: 250)
                .liquidGlass(cornerRadius: 12)
                
                // Right Column: Playlist Content / Editor
                VStack(alignment: .leading, spacing: 12) {
                    if let pl = selectedPlaylist {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pl.name)
                                    .font(WalkmanFont.title3)
                                    .foregroundStyle(.white)
                                
                                Text("\(playlistTracks.count) \(playlistTracks.count == 1 ? "track" : "tracks") in sequence")
                                    .font(WalkmanFont.callout)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Auto-saved Status Indicator
                            HStack(spacing: 5) {
                                if isSaving {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Saving...")
                                        .font(WalkmanFont.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.green)
                                    Text("Auto-saved to Walkman")
                                        .font(WalkmanFont.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            
                            // Sort Menu
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
                                }
                                .font(WalkmanFont.calloutMedium)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(WalkmanTheme.card)
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(playlistTracks.isEmpty)
                            
                            // Add From Library Button
                            Button(action: { showAddTrackSheet = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle")
                                    Text("Add From Library")
                                }
                                .font(WalkmanFont.calloutMedium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(WalkmanTheme.silverGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                        
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
                                        
                                        HStack(spacing: 12) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(WalkmanFont.mono)
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                                .frame(width: 26, alignment: .trailing)
                                            
                                            // Play / Note button
                                            Button(action: {
                                                if let tr = matchedTrack {
                                                    if isPlayingThis {
                                                        AudioPlayerService.shared.pause()
                                                    } else {
                                                        AudioPlayerService.shared.play(track: tr, in: libraryTracks)
                                                    }
                                                }
                                            }) {
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
                                                    
                                                    HStack(spacing: 6) {
                                                        if !tr.artist.isEmpty {
                                                            Text(tr.artist)
                                                                .font(WalkmanFont.subheadline)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                            
                                                            Text("•")
                                                                .font(.system(size: 8))
                                                                .foregroundStyle(.tertiary)
                                                        }
                                                        Text(trackPath)
                                                            .font(WalkmanFont.monoSmall)
                                                            .foregroundStyle(.tertiary)
                                                            .lineLimit(1)
                                                    }
                                                } else {
                                                    Text(trackPath)
                                                        .font(WalkmanFont.mono)
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            // Move Up
                                            Button(action: {
                                                if index > 0 {
                                                    var updated = playlistTracks
                                                    updated.swapAt(index, index - 1)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Image(systemName: "chevron.up")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == 0)
                                            .help("Move Up")
                                            
                                            // Move Down
                                            Button(action: {
                                                if index < playlistTracks.count - 1 {
                                                    var updated = playlistTracks
                                                    updated.swapAt(index, index + 1)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == playlistTracks.count - 1)
                                            .help("Move Down")
                                            
                                            // Remove
                                            Button(action: {
                                                var updated = playlistTracks
                                                updated.remove(at: index)
                                                persistPlaylistChanges(newTracks: updated)
                                            }) {
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
                                            if let tr = matchedTrack {
                                                AudioPlayerService.shared.play(track: tr, in: libraryTracks)
                                            }
                                        }
                                        .contextMenu {
                                            if let tr = matchedTrack {
                                                Button(action: {
                                                    AudioPlayerService.shared.play(track: tr, in: libraryTracks)
                                                }) {
                                                    Label("Play Now", systemImage: "play.fill")
                                                }
                                                Divider()
                                            }
                                            
                                            Button(action: {
                                                if index > 0 {
                                                    var updated = playlistTracks
                                                    let item = updated.remove(at: index)
                                                    updated.insert(item, at: 0)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Label("Move to Top", systemImage: "arrow.up.to.line")
                                            }
                                            .disabled(index == 0)
                                            
                                            Button(action: {
                                                if index > 0 {
                                                    var updated = playlistTracks
                                                    updated.swapAt(index, index - 1)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Label("Move Up", systemImage: "chevron.up")
                                            }
                                            .disabled(index == 0)
                                            
                                            Button(action: {
                                                if index < playlistTracks.count - 1 {
                                                    var updated = playlistTracks
                                                    updated.swapAt(index, index + 1)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Label("Move Down", systemImage: "chevron.down")
                                            }
                                            .disabled(index == playlistTracks.count - 1)
                                            
                                            Button(action: {
                                                if index < playlistTracks.count - 1 {
                                                    var updated = playlistTracks
                                                    let item = updated.remove(at: index)
                                                    updated.append(item)
                                                    persistPlaylistChanges(newTracks: updated)
                                                }
                                            }) {
                                                Label("Move to Bottom", systemImage: "arrow.down.to.line")
                                            }
                                            .disabled(index == playlistTracks.count - 1)
                                            
                                            Divider()
                                            
                                            Button(role: .destructive, action: {
                                                var updated = playlistTracks
                                                updated.remove(at: index)
                                                persistPlaylistChanges(newTracks: updated)
                                            }) {
                                                Label("Remove from Playlist", systemImage: "trash")
                                            }
                                        }
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
            loadPlaylists()
        }
        .onChange(of: activeDrive?.mountPoint) {
            loadPlaylists()
        }
        .sheet(isPresented: $showAddTrackSheet) {
            AddTracksModal(
                playlistName: selectedPlaylist?.name ?? "Playlist",
                tracks: libraryTracks,
                existingPlaylistPaths: Set(playlistTracks),
                onAdd: { addedRelativePaths in
                    let newTracks = playlistTracks + addedRelativePaths
                    persistPlaylistChanges(newTracks: newTracks)
                    showAddTrackSheet = false
                },
                onDismiss: { showAddTrackSheet = false }
            )
        }
    }
}

private enum AddBrowsingMode: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "By Album"
    case artists = "By Artist"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "person.2"
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
    let onAdd: ([String]) -> Void
    let onDismiss: () -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var mode: AddBrowsingMode = .songs
    @State private var search: String = ""
    @State private var formatFilter: String = "ALL"
    @State private var hideExisting: Bool = false
    @State private var selectedTrackPaths: Set<String> = []
    
    @State private var cachedAlbums: [ModalAlbumItem] = []
    @State private var cachedArtists: [ModalArtistItem] = []
    
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
    
    private var filteredTracks: [Track] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tracks.filter { tr in
            if hideExisting && existingPlaylistPaths.contains(tr.relativePath) {
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
                if hideExisting && existingPlaylistPaths.contains(tr.relativePath) {
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
                if hideExisting && existingPlaylistPaths.contains(tr.relativePath) {
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
        case .albums:
            return "\(filteredAlbums.count.formatted()) albums"
        case .artists:
            return "\(filteredArtists.count.formatted()) artists"
        }
    }
    
    private var visibleSelectablePaths: [String] {
        switch mode {
        case .songs:
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
                    // Mode Picker (Songs / By Album / By Artist)
                    Picker("", selection: $mode) {
                        ForEach(AddBrowsingMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    
                    // Search Field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        TextField(
                            mode == .songs ? "Search songs by title, artist, album..." :
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
                case .songs:
                    if filteredTracks.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "music.note")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No matching tracks")
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
                                    let isInPlaylist = existingPlaylistPaths.contains(tr.relativePath)
                                    let isCurrent = player.currentTrack?.relativePath == tr.relativePath
                                    let isPlayingThis = isCurrent && player.isPlaying
                                    
                                    ModalTrackRow(
                                        track: tr,
                                        isSelected: isSel,
                                        isInPlaylist: isInPlaylist,
                                        isPlaying: isPlayingThis,
                                        onToggleSelect: {
                                            if isSel {
                                                selectedTrackPaths.remove(tr.relativePath)
                                            } else {
                                                selectedTrackPaths.insert(tr.relativePath)
                                            }
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
                                    let isAllSel = !albumPaths.isEmpty && albumPaths.allSatisfy { selectedTrackPaths.contains($0) }
                                    let selCount = albumPaths.filter { selectedTrackPaths.contains($0) }.count
                                    
                                    ModalAlbumRow(
                                        album: alb,
                                        isAllSelected: isAllSel,
                                        selectedCount: selCount,
                                        onToggleSelect: {
                                            if isAllSel {
                                                for p in albumPaths { selectedTrackPaths.remove(p) }
                                            } else {
                                                selectedTrackPaths.formUnion(albumPaths)
                                            }
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
                                    let isAllSel = !artistPaths.isEmpty && artistPaths.allSatisfy { selectedTrackPaths.contains($0) }
                                    let selCount = artistPaths.filter { selectedTrackPaths.contains($0) }.count
                                    
                                    ModalArtistRow(
                                        artist: art,
                                        isAllSelected: isAllSel,
                                        selectedCount: selCount,
                                        onToggleSelect: {
                                            if isAllSel {
                                                for p in artistPaths { selectedTrackPaths.remove(p) }
                                            } else {
                                                selectedTrackPaths.formUnion(artistPaths)
                                            }
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
                        Text("No tracks selected")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
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
                
                // Right: Cancel & Redesigned Add / Done Button
                Button("Cancel") {
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
                
                Button(action: {
                    var ordered = tracks.filter { selectedTrackPaths.contains($0.relativePath) }.map(\.relativePath)
                    let addedSet = Set(ordered)
                    for p in selectedTrackPaths where !addedSet.contains(p) {
                        ordered.append(p)
                    }
                    onAdd(ordered)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(selectedTrackPaths.isEmpty
                             ? "Add to Playlist"
                             : "Add \(selectedTrackPaths.count) \(selectedTrackPaths.count == 1 ? "Track" : "Tracks")")
                            .font(WalkmanFont.calloutBold)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(selectedTrackPaths.isEmpty ? AnyShapeStyle(Color.white.opacity(0.10)) : AnyShapeStyle(WalkmanTheme.silverGradient))
                    .foregroundStyle(selectedTrackPaths.isEmpty ? Color.white.opacity(0.3) : Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(selectedTrackPaths.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(red: 16/255, green: 16/255, blue: 18/255))
        }
        .frame(width: 780, height: 600)
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
    let onToggleSelect: () -> Void
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
                    
                    if isInPlaylist {
                        Text("In Playlist")
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                Text("\(track.artist) — \(track.album)")
                    .font(WalkmanFont.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
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
    let isAllSelected: Bool
    let selectedCount: Int
    let onToggleSelect: () -> Void
    
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
                    
                    if selectedCount > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(selectedCount) / \(album.trackCount) selected")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onToggleSelect) {
                HStack(spacing: 5) {
                    Image(systemName: isAllSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isAllSelected
                         ? "Selected (\(album.trackCount))"
                         : selectedCount > 0
                            ? "Add Remaining (\(remainingCount))"
                            : "Add Album (\(album.trackCount))")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isAllSelected ? WalkmanTheme.silver.opacity(0.2) : Color.white.opacity(0.08))
                .foregroundStyle(isAllSelected ? WalkmanTheme.silverLight : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
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
    let isAllSelected: Bool
    let selectedCount: Int
    let onToggleSelect: () -> Void
    
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
                    
                    if selectedCount > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(selectedCount) / \(artist.trackCount) selected")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(WalkmanTheme.silverLight)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onToggleSelect) {
                HStack(spacing: 5) {
                    Image(systemName: isAllSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isAllSelected
                         ? "Selected (\(artist.trackCount))"
                         : selectedCount > 0
                            ? "Add Remaining (\(remainingCount))"
                            : "Add All Songs (\(artist.trackCount))")
                        .font(WalkmanFont.calloutMedium)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isAllSelected ? WalkmanTheme.silver.opacity(0.2) : Color.white.opacity(0.08))
                .foregroundStyle(isAllSelected ? WalkmanTheme.silverLight : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isAllSelected ? WalkmanTheme.silver.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
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
