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
    
    private func saveCurrentPlaylist() {
        guard let drive = activeDrive, let playlist = selectedPlaylist else { return }
        let musicURL = URL(fileURLWithPath: drive.musicDir)
        do {
            _ = try WalkmanEngine.shared.writePlaylist(
                musicDir: musicURL,
                name: playlist.name,
                relativeTracks: playlistTracks
            )
            withAnimation {
                messageBanner = "Saved \(playlist.name).m3u8 with CRLF endings"
            }
            loadPlaylists()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { messageBanner = nil }
            }
        } catch {
            withAnimation {
                messageBanner = "Error: \(error.localizedDescription)"
            }
        }
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Walkman .M3U8 Playlists")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("CRLF / Relative POSIX")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(Capsule())
                    }
                    
                    Text("Playlists stored in \(activeDrive?.name ?? "Drive")/MUSIC/ for instant hardware discovery")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let banner = messageBanner {
                    Text(banner)
                        .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    
                    if isCreating {
                        HStack(spacing: 6) {
                            TextField("Playlist Name...", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(6)
                                .background(WalkmanTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onSubmit { createPlaylist() }
                            
                            Button("Save") { createPlaylist() }
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WalkmanTheme.silverLight)
                            
                            Button("Cancel") { isCreating = false }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .liquidGlass(cornerRadius: 8)
                    }
                    
                    if playlists.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "music.note.list")
                                .font(.system(size: 26))
                                .foregroundStyle(.tertiary)
                            Text("No Playlists Found")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Create one to organize your tracks")
                                .font(.system(size: 9))
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
                                            .font(.system(size: 11))
                                            .foregroundStyle(isSel ? WalkmanTheme.silverLight : .secondary)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pl.name)
                                                .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                                                .foregroundStyle(isSel ? .white : .primary)
                                            
                                            Text("\(pl.trackCount) tracks")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: { deletePlaylist(pl) }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10))
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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text("\(playlistTracks.count) tracks in sequence")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAddTrackSheet = true }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle")
                                    Text("Add From Library")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(WalkmanTheme.card)
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { saveCurrentPlaylist() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save Changes")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
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
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text("This playlist is empty")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Click 'Add From Library' to populate this playlist")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(playlistTracks.enumerated()), id: \.offset) { index, trackPath in
                                        HStack(spacing: 12) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundStyle(WalkmanTheme.silverLight)
                                                .frame(width: 24, alignment: .trailing)
                                            
                                            Image(systemName: "music.note")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                            
                                            Text(trackPath)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            
                                            Spacer()
                                            
                                            // Move Up
                                            Button(action: {
                                                if index > 0 {
                                                    playlistTracks.swapAt(index, index - 1)
                                                }
                                            }) {
                                                Image(systemName: "chevron.up")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == 0)
                                            
                                            // Move Down
                                            Button(action: {
                                                if index < playlistTracks.count - 1 {
                                                    playlistTracks.swapAt(index, index + 1)
                                                }
                                            }) {
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == playlistTracks.count - 1)
                                            
                                            // Remove
                                            Button(action: {
                                                playlistTracks.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(WalkmanTheme.card.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                tracks: libraryTracks,
                onAdd: { addedRelativePaths in
                    playlistTracks.append(contentsOf: addedRelativePaths)
                    showAddTrackSheet = false
                },
                onDismiss: { showAddTrackSheet = false }
            )
        }
    }
}

private struct AddTracksModal: View {
    let tracks: [Track]
    let onAdd: ([String]) -> Void
    let onDismiss: () -> Void
    
    @State private var search: String = ""
    @State private var selectedTrackPaths: Set<String> = []
    
    private var filtered: [Track] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(tracks.prefix(150)) }
        return Array(tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }.prefix(150))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Add Tracks to Playlist")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button("Done") {
                    onAdd(Array(selectedTrackPaths))
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(WalkmanTheme.silverGradient)
                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search library tracks...", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(8)
            .liquidGlass(cornerRadius: 8)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filtered) { tr in
                        let isSel = selectedTrackPaths.contains(tr.relativePath)
                        HStack(spacing: 10) {
                            Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSel ? WalkmanTheme.silverLight : .secondary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                Text("\(tr.artist) — \(tr.album)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(tr.format)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSel ? WalkmanTheme.cardHover : WalkmanTheme.card.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSel {
                                selectedTrackPaths.remove(tr.relativePath)
                            } else {
                                selectedTrackPaths.insert(tr.relativePath)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 520, height: 480)
        .background(WalkmanTheme.background)
    }
}
