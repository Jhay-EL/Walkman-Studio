import SwiftUI
import AppKit

public struct AlbumMetadataEditorSheet: View {
    let album: AlbumItem
    let onSaved: () -> Void
    let onDismiss: () -> Void
    
    public struct EditableTrackRow: Identifiable {
        public var id: String { track.id }
        public let track: Track
        public var trackNum: String
        public var title: String
        public var artist: String
    }
    
    // Album-wide tags
    @State private var albumName: String = ""
    @State private var albumArtist: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    @State private var applyArtistToAll: Bool = false
    
    // Artwork state
    @State private var coverImage: NSImage? = nil
    @State private var coverData: Data? = nil
    @State private var originalCoverData: Data? = nil
    @State private var isCoverArtModified: Bool = false
    @State private var validationStatus: (valid: Bool, message: String)? = nil
    @State private var isTargeted: Bool = false
    @State private var isFetchingOnlineArt: Bool = false
    
    // Tracklist
    @State private var trackRows: [EditableTrackRow] = []
    
    // Saving state
    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0.0
    @State private var saveStatus: String = ""
    @State private var errorMessage: String? = nil
    @State private var isFetchingOnlineInfo: Bool = false
    
    public init(album: AlbumItem, onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.album = album
        self.onSaved = onSaved
        self.onDismiss = onDismiss
    }
    
    private func loadInitialData() {
        self.albumName = album.name
        self.albumArtist = album.artist
        self.year = album.year
        
        let existingGenre = album.tracks.first(where: { !$0.genre.isEmpty })?.genre ?? ""
        self.genre = existingGenre
        
        // Single artist albums default to true, compilations/soundtracks default to false
        let isVarious = album.artist.lowercased().contains("various") || album.artist.lowercased().contains("soundtrack")
        let uniqueArtists = Set(album.tracks.map { $0.primaryArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        self.applyArtistToAll = (!isVarious && uniqueArtists.count <= 1)
        
        // Populate track rows sorted by current track number
        self.trackRows = album.tracks.map { tr in
            EditableTrackRow(
                track: tr,
                trackNum: tr.trackNum,
                title: tr.title,
                artist: tr.artist
            )
        }
        
        // Load artwork asynchronously from representative track
        if let rep = album.representativeTrack {
            let url = URL(fileURLWithPath: rep.fullPath)
            DispatchQueue.global(qos: .userInitiated).async {
                let art = AudioTagger.shared.extractCoverArt(fileURL: url)
                let img = art != nil ? NSImage(data: art!) : nil
                let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
                
                DispatchQueue.main.async {
                    self.originalCoverData = art
                    self.coverData = art
                    self.coverImage = img
                    self.validationStatus = val
                }
            }
        }
    }
    
    private func handleNewImageData(_ data: Data) {
        if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data) {
            self.coverData = baseline
            self.coverImage = NSImage(data: baseline)
            self.validationStatus = WalkmanEngine.shared.isBaselineRGBJPEG(data: baseline)
            self.isCoverArtModified = true
        }
    }
    
    private func selectArtworkFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.prompt = "Choose Album Artwork"
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            handleNewImageData(data)
        }
    }
    
    private func removeArtwork() {
        self.coverData = Data() // Empty data signals artwork removal
        self.coverImage = nil
        self.validationStatus = nil
        self.isCoverArtModified = true
    }
    
    private func revertArtwork() {
        self.coverData = originalCoverData
        self.coverImage = originalCoverData != nil ? NSImage(data: originalCoverData!) : nil
        self.validationStatus = originalCoverData != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: originalCoverData!) : nil
        self.isCoverArtModified = false
    }
    
    private func fetchOnlineArtwork() {
        guard !isFetchingOnlineArt else { return }
        isFetchingOnlineArt = true
        let searchTitle = albumName.isEmpty ? album.name : albumName
        let searchArtist = albumArtist.isEmpty ? album.artist : albumArtist
        
        Task {
            if let artData = await OnlineMetadataService.shared.fetchArtworkOnly(title: searchTitle, artist: searchArtist, album: searchTitle) {
                await MainActor.run {
                    self.handleNewImageData(artData)
                    self.isFetchingOnlineArt = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineArt = false
                    self.errorMessage = "No online artwork found for this album"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }
    
    private func fetchOnlineAlbumMetadata() {
        guard !isFetchingOnlineInfo else { return }
        isFetchingOnlineInfo = true
        errorMessage = nil
        
        let searchTitle = albumName.isEmpty ? album.name : albumName
        let searchArtist = albumArtist.isEmpty ? album.artist : albumArtist
        let repFile = album.representativeTrack?.filename ?? "01.flac"
        
        Task {
            if let meta = await OnlineMetadataService.shared.fetchMetadata(
                filename: repFile,
                currentTitle: searchTitle,
                currentArtist: searchArtist,
                currentAlbum: searchTitle
            ) {
                await MainActor.run {
                    if !meta.album.isEmpty && meta.album.lowercased() != "unknown album" {
                        self.albumName = meta.album
                    }
                    if !meta.artist.isEmpty && meta.artist.lowercased() != "unknown artist" {
                        self.albumArtist = meta.artist
                    }
                    if !meta.year.isEmpty {
                        self.year = meta.year
                    }
                    if !meta.genre.isEmpty {
                        self.genre = meta.genre
                    }
                    if let artData = meta.artworkData, self.coverData == nil || self.coverData?.isEmpty == true {
                        self.handleNewImageData(artData)
                    }
                    self.isFetchingOnlineInfo = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineInfo = false
                    self.errorMessage = "No online album metadata found"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }
    
    // Quick Tracklist Actions
    private func autoNumberTracks() {
        for i in 0..<trackRows.count {
            trackRows[i].trackNum = "\(i + 1)"
        }
    }
    
    private func padTrackNumbers() {
        for i in 0..<trackRows.count {
            trackRows[i].trackNum = String(format: "%02d", i + 1)
        }
    }
    
    private func sortTracksByTrackNum() {
        trackRows.sort { a, b in
            let nA = Int(a.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            let nB = Int(b.trackNum.components(separatedBy: "/").first ?? "0") ?? 0
            if nA != nB && nA > 0 && nB > 0 {
                return nA < nB
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
    
    private func sortTracksByTitle() {
        trackRows.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    
    private func moveTrack(from index: Int, up: Bool) {
        let targetIndex = up ? index - 1 : index + 1
        guard targetIndex >= 0 && targetIndex < trackRows.count else { return }
        trackRows.swapAt(index, targetIndex)
    }
    
    private func saveAlbumChanges() {
        guard !isSaving else { return }
        isSaving = true
        saveProgress = 0.0
        saveStatus = "Preparing album metadata..."
        errorMessage = nil
        
        let newAlbumName = self.albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAlbumName = newAlbumName.isEmpty ? album.name : newAlbumName
        let finalAlbumArtist = self.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalYear = self.year.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGenre = self.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApplyArtist = self.applyArtistToAll
        
        let rows = self.trackRows
        let artModified = self.isCoverArtModified
        let artDataToSave = self.coverData
        
        Task.detached(priority: .userInitiated) {
            let total = rows.count
            
            // Encode artwork once if modified
            var encodedArtwork: Data? = nil
            if artModified {
                if let raw = artDataToSave, !raw.isEmpty {
                    encodedArtwork = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: raw, maxDimension: 800)
                } else if artDataToSave?.isEmpty == true {
                    encodedArtwork = Data() // Empty data signals artwork removal
                }
            }
            
            for (index, row) in rows.enumerated() {
                await MainActor.run {
                    self.saveProgress = Double(index) / Double(max(1, total))
                    self.saveStatus = "Updating track \(index + 1) of \(total): \(row.title)..."
                }
                
                let trackURL = URL(fileURLWithPath: row.track.fullPath)
                let trackTitle = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackArtist = shouldApplyArtist ? finalAlbumArtist : row.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                let trackNum = row.trackNum.trimmingCharacters(in: .whitespacesAndNewlines)
                
                do {
                    try AudioTagger.shared.writeMetadata(
                        fileURL: trackURL,
                        title: trackTitle.isEmpty ? row.track.title : trackTitle,
                        artist: trackArtist.isEmpty ? row.track.artist : trackArtist,
                        album: finalAlbumName,
                        trackNumber: trackNum.isEmpty ? row.track.trackNum : trackNum,
                        year: finalYear,
                        genre: finalGenre,
                        coverArtData: artModified ? encodedArtwork : nil
                    )
                    
                    // Invalidate caches
                    AudioTagger.shared.invalidateCaches(fileURL: trackURL)
                    CoverArtCache.shared.invalidate(forFullPath: row.track.fullPath, artist: row.track.primaryArtist, album: row.track.album)
                    LibraryScanner.shared.invalidate(fullPath: row.track.fullPath)
                } catch {
                    print("[AlbumMetadataEditor] Error saving track \(row.track.filename): \(error.localizedDescription)")
                }
            }
            
            // Update folder.jpg and cover.jpg in album folders if artwork was modified
            if artModified {
                let albumDirs = Set(rows.map { URL(fileURLWithPath: $0.track.fullPath).deletingLastPathComponent() })
                for dir in albumDirs {
                    if let baseline = encodedArtwork, !baseline.isEmpty {
                        try? WalkmanEngine.shared.writeAlbumFolderArtwork(albumDirectoryURL: dir, artworkData: baseline)
                    } else if encodedArtwork?.isEmpty == true {
                        // Removed artwork
                        for cand in ["cover.jpg", "folder.jpg", "Cover.jpg", "Folder.jpg"] {
                            let f = dir.appendingPathComponent(cand)
                            try? FileManager.default.removeItem(at: f)
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.saveProgress = 1.0
                self.saveStatus = "Saved album successfully!"
                self.isSaving = false
                self.onSaved()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.onDismiss()
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds <= 0 { return "—" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WalkmanTheme.silverGradient)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Album Metadata Editor")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    
                    Text("\(album.name) • \(album.trackCount) tracks • \(album.primaryFormat)")
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Main Content Area
            ScrollView {
                VStack(spacing: 18) {
                    // Top Section: Album Artwork + Album-Wide Tags
                    HStack(alignment: .top, spacing: 22) {
                        // Artwork Column
                        artworkColumn
                            .frame(width: 280)
                        
                        // Album Tags Column
                        albumTagsColumn
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 12)
                    
                    // Middle Section: Tracklist & Track Numbers
                    tracklistSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Footer Bar
            footerBar
        }
        .frame(minWidth: 1050, idealWidth: 1180, maxWidth: 1350, minHeight: 820, idealHeight: 880, maxHeight: 1020)
        .background(WalkmanTheme.background.ignoresSafeArea())
        .onAppear {
            loadInitialData()
        }
    }
    
    // MARK: - Artwork Column
    private var artworkColumn: some View {
        VStack(spacing: 10) {
            ZStack {
                if let img = coverImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.25))
                            .frame(width: 240, height: 240)
                            .background(Color.white.opacity(0.02))
                        
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 38))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                            Text("Drop Artwork")
                                .font(WalkmanFont.calloutMedium)
                                .foregroundStyle(.secondary)
                            Text("Auto Baseline RGB")
                                .font(WalkmanFont.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectArtworkFile()
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    if let d = data {
                        DispatchQueue.main.async {
                            self.handleNewImageData(d)
                        }
                    }
                }
                return true
            }
            .help("Click or drag-and-drop to update album artwork across all tracks")
            .contextMenu {
                Button(action: selectArtworkFile) {
                    Label("Choose Artwork...", systemImage: "photo")
                }
                Button(action: fetchOnlineArtwork) {
                    Label("Fetch Online Artwork", systemImage: "arrow.down.circle")
                }
                if coverImage != nil {
                    Divider()
                    Button(role: .destructive, action: removeArtwork) {
                        Label("Remove Artwork", systemImage: "trash")
                    }
                }
            }
            
            // Compliance status pill
            if let st = validationStatus {
                HStack(spacing: 4) {
                    Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(st.valid ? Color.green : Color.orange)
                    Text(st.message)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Artwork Actions
            HStack(spacing: 7) {
                Button(action: selectArtworkFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text("Choose...")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button(action: fetchOnlineArtwork) {
                    if isFetchingOnlineArt {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(WalkmanTheme.silverLight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
                .disabled(isFetchingOnlineArt)
                .help("Search and fetch album artwork online")
                
                if coverImage != nil {
                    Button(action: removeArtwork) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.12))
                    .foregroundStyle(Color(red: 255/255, green: 110/255, blue: 100/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .help("Remove artwork from all album tracks")
                }
                
                if isCoverArtModified {
                    Button(action: revertArtwork) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .help("Revert to original album artwork")
                }
            }
            
            Text("Updates embedded artwork in all \(album.trackCount) tracks & writes folder.jpg / cover.jpg")
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
    
    // MARK: - Album Tags Column
    private var albumTagsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ALBUM PROPERTIES (APPLIED TO ALL TRACKS)")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button(action: fetchOnlineAlbumMetadata) {
                    HStack(spacing: 4) {
                        if isFetchingOnlineInfo {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                            Text("Matching...")
                                .font(WalkmanFont.subheadlineMedium)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Auto-Fill Album Info")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isFetchingOnlineInfo)
                .help("Query iTunes and Deezer databases to match album title, artist, year, and genre")
            }
            
            AlbumInputField(label: "Album Title", text: $albumName)
            
            VStack(alignment: .leading, spacing: 4) {
                AlbumInputField(label: "Album Artist", text: $albumArtist)
                
                Toggle("Apply this artist to all track tags", isOn: $applyArtistToAll)
                    .font(WalkmanFont.subheadline)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            
            HStack(spacing: 12) {
                AlbumInputField(label: "Release Year", text: $year)
                AlbumInputField(label: "Genre", text: $genre)
            }
        }
    }
    
    // MARK: - Tracklist Section
    private var tracklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tracklist Header & Quick Actions
            HStack {
                HStack(spacing: 6) {
                    Text("TRACKLIST & TRACK NUMBERS")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                    
                    Text("(\(trackRows.count))")
                        .font(WalkmanFont.badge)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Quick Action Buttons
                HStack(spacing: 6) {
                    Button(action: autoNumberTracks) {
                        HStack(spacing: 4) {
                            Image(systemName: "list.number")
                                .font(.system(size: 11))
                            Text("Auto-Number (1..N)")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Automatically renumbers all tracks from 1 to \(trackRows.count)")
                    
                    Button(action: padTrackNumbers) {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 11))
                            Text("Pad (01..N)")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Formats track numbers with leading zero (01, 02...) for optimal Walkman alphabetical folder sorting")
                    
                    Button(action: sortTracksByTrackNum) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .buttonStyle(.plain)
                    .help("Sort list by track number")
                    
                    Button(action: sortTracksByTitle) {
                        Image(systemName: "textformat.abc")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .buttonStyle(.plain)
                    .help("Sort list by track title")
                }
            }
            
            // Tracklist Table
            VStack(spacing: 0) {
                // Table Column Header
                HStack(spacing: 12) {
                    Text("#")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .center)
                    
                    Text("Order")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .center)
                    
                    Text("Track Title")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !applyArtistToAll {
                        Text("Track Artist")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                            .frame(width: 240, alignment: .leading)
                    }
                    
                    Text("Format")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 65, alignment: .center)
                    
                    Text("Duration")
                        .font(WalkmanFont.sectionHeader)
                        .foregroundStyle(.tertiary)
                        .frame(width: 65, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
                
                Divider()
                    .overlay(Color.white.opacity(0.06))
                
                // Track Rows
                VStack(spacing: 1) {
                    ForEach(Array(trackRows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            // Track Number TextField
                            TextField("", text: $trackRows[index].trackNum)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.mono)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .frame(width: 48)
                            
                            // Reorder Up/Down buttons
                            HStack(spacing: 2) {
                                Button(action: { moveTrack(from: index, up: true) }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 18, height: 18)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                
                                Button(action: { moveTrack(from: index, up: false) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 18, height: 18)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 3.5))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == trackRows.count - 1)
                            }
                            .frame(width: 44)
                            
                            // Title TextField
                            TextField("", text: $trackRows[index].title)
                                .textFieldStyle(.plain)
                                .font(WalkmanFont.bodyMedium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .frame(maxWidth: .infinity)
                            
                            // Artist TextField (if not applied to all)
                            if !applyArtistToAll {
                                TextField("", text: $trackRows[index].artist)
                                    .textFieldStyle(.plain)
                                    .font(WalkmanFont.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .frame(width: 240)
                            }
                            
                            // Format
                            Text(row.track.format)
                                .font(WalkmanFont.badge)
                                .foregroundStyle(.secondary)
                                .frame(width: 65, alignment: .center)
                            
                            // Duration
                            Text(formatDuration(row.track.durationSeconds))
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                        .background(index % 2 == 1 ? Color.white.opacity(0.015) : Color.clear)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Footer Bar
    private var footerBar: some View {
        VStack(spacing: 8) {
            // Progress Bar (during batch save)
            if isSaving {
                VStack(spacing: 4) {
                    HStack {
                        ProgressView(value: saveProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(WalkmanTheme.silver)
                    }
                    
                    HStack {
                        Text(saveStatus)
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(WalkmanTheme.silverLight)
                        Spacer()
                        Text("\(Int(saveProgress * 100))%")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            
            HStack(spacing: 12) {
                if let err = errorMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.orange)
                    }
                } else if !isSaving && !saveStatus.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                        Text(saveStatus)
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(Color.green)
                    }
                }
                
                Spacer()
                
                Button("Cancel") {
                    onDismiss()
                }
                .font(WalkmanFont.calloutMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
                .disabled(isSaving)
                
                Button(action: saveAlbumChanges) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                            Text("Saving Album...")
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Save Album (\(trackRows.count) Tracks)")
                        }
                    }
                    .font(WalkmanFont.calloutBold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(WalkmanTheme.silverGradient)
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(WalkmanTheme.background)
    }
}

private struct AlbumInputField: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(.secondary)
            
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(WalkmanFont.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}
