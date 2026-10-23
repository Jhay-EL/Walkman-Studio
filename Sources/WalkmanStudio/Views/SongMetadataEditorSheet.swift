import SwiftUI
import AppKit

public struct SongMetadataEditorSheet: View {
    let track: Track
    let onSaved: () -> Void
    let onDismiss: () -> Void
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    public enum EditorTab: String, CaseIterable, Identifiable {
        case tags = "Tags & Specs"
        case artwork = "Album Artwork"
        case lyrics = "Lyrics (.LRC)"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .tags: return "tag.fill"
            case .artwork: return "photo.fill"
            case .lyrics: return "quote.bubble.fill"
            }
        }
    }
    
    @State private var selectedTab: EditorTab = .tags
    
    // Tag fields
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var trackNumber: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    
    // Artwork state
    @State private var coverImage: NSImage?
    @State private var coverData: Data?
    @State private var originalCoverData: Data?
    @State private var isCoverArtModified: Bool = false
    @State private var validationStatus: (valid: Bool, message: String)?
    @State private var isTargeted: Bool = false
    @State private var isFetchingOnlineArt: Bool = false
    
    // Lyrics state
    @State private var lyrics: String? = nil
    @State private var originalLyrics: String? = nil
    @State private var lyricsDraft: String = ""
    @State private var isLyricsModified: Bool = false
    @State private var isFetchingLyrics: Bool = false
    @State private var lyricsStatusMessage: String? = nil
    @State private var lyricsErrorMessage: String? = nil
    
    // Save state
    @State private var isSaving: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isError: Bool = false
    @State private var isFetchingOnlineInfo: Bool = false
    
    public init(track: Track, onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.track = track
        self.onSaved = onSaved
        self.onDismiss = onDismiss
    }
    
    private func loadInitialData() {
        title = track.title
        artist = track.artist
        album = track.album
        trackNumber = track.trackNum
        year = track.year
        genre = track.genre
        
        let url = URL(fileURLWithPath: track.fullPath)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let art = AudioTagger.shared.extractCoverArt(fileURL: url)
            let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
            let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
            let img = art != nil ? NSImage(data: art!) : nil
            let meta = AudioTagger.shared.readMetadata(fileURL: url)
            
            DispatchQueue.main.async {
                self.originalCoverData = art
                self.coverData = art
                self.coverImage = img
                self.validationStatus = val
                
                self.originalLyrics = lyr
                self.lyrics = lyr
                self.lyricsDraft = lyr ?? ""
                
                if let m = meta {
                    if self.year.isEmpty && !m.year.isEmpty {
                        self.year = m.year
                    }
                    if self.genre.isEmpty && !m.genre.isEmpty {
                        self.genre = m.genre
                    }
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
        panel.prompt = "Choose Artwork"
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
    
    private func exportArtworkToMac() {
        let cleanArtist = artist.isEmpty ? track.artist : artist
        let cleanAlbum = album.isEmpty ? track.album : album
        let defaultName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        ArtworkExportService.exportCustomArtwork(data: coverData, image: coverImage, suggestedFilename: defaultName)
    }
    
    private func fetchOnlineArtwork() {
        guard !isFetchingOnlineArt else { return }
        isFetchingOnlineArt = true
        let searchTitle = title.isEmpty ? track.title : title
        let searchArtist = artist.isEmpty ? track.artist : artist
        let searchAlbum = album.isEmpty ? track.album : album
        
        Task {
            if let artData = await OnlineMetadataService.shared.fetchArtworkOnly(title: searchTitle, artist: searchArtist, album: searchAlbum) {
                await MainActor.run {
                    self.handleNewImageData(artData)
                    self.isFetchingOnlineArt = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineArt = false
                    self.statusMessage = "No online artwork found"
                    self.isError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage == "No online artwork found" { self.statusMessage = nil }
                    }
                }
            }
        }
    }
    
    private func fetchOnlineMetadataInfo() {
        guard !isFetchingOnlineInfo else { return }
        isFetchingOnlineInfo = true
        
        let searchTitle = title.isEmpty ? track.title : title
        let searchArtist = artist.isEmpty ? track.artist : artist
        let searchAlbum = album.isEmpty ? track.album : album
        let filename = track.filename
        
        Task {
            if let meta = await OnlineMetadataService.shared.fetchMetadata(
                filename: filename,
                currentTitle: searchTitle,
                currentArtist: searchArtist,
                currentAlbum: searchAlbum
            ) {
                await MainActor.run {
                    if !meta.title.isEmpty { self.title = meta.title }
                    if !meta.artist.isEmpty { self.artist = meta.artist }
                    if !meta.album.isEmpty { self.album = meta.album }
                    if !meta.trackNumber.isEmpty && self.trackNumber.isEmpty { self.trackNumber = meta.trackNumber }
                    if !meta.year.isEmpty { self.year = meta.year }
                    if !meta.genre.isEmpty { self.genre = meta.genre }
                    if let artData = meta.artworkData, self.coverData == nil || self.coverData?.isEmpty == true {
                        self.handleNewImageData(artData)
                    }
                    self.isFetchingOnlineInfo = false
                    self.statusMessage = "Metadata matched from \(meta.source)"
                    self.isError = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if self.statusMessage?.contains("matched from") == true { self.statusMessage = nil }
                    }
                }
            } else {
                await MainActor.run {
                    self.isFetchingOnlineInfo = false
                    self.statusMessage = "No online metadata found"
                    self.isError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusMessage == "No online metadata found" { self.statusMessage = nil }
                    }
                }
            }
        }
    }
    
    private func fetchLyricsOnline() {
        guard !isFetchingLyrics else { return }
        isFetchingLyrics = true
        lyricsErrorMessage = nil
        lyricsStatusMessage = nil
        
        let trackTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.title : self.title
        let trackArtist = self.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.artist : self.artist
        let trackAlbum = self.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.album : self.album
        let duration = track.durationSeconds
        
        Task {
            do {
                let result = try await LyricsService.shared.fetchLyrics(
                    title: trackTitle,
                    artist: trackArtist,
                    album: trackAlbum,
                    durationSeconds: duration
                )
                
                await MainActor.run {
                    self.lyricsDraft = result.lyrics
                    self.lyrics = result.lyrics
                    self.isLyricsModified = true
                    self.isFetchingLyrics = false
                    self.lyricsStatusMessage = result.synced ? "Synced .LRC found!" : "Lyrics found!"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.lyricsStatusMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFetchingLyrics = false
                    self.lyricsErrorMessage = "No lyrics found online"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        self.lyricsErrorMessage = nil
                    }
                }
            }
        }
    }
    
    private func saveAllChanges() {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = "Saving tags & artwork to Walkman..."
        isError = false
        
        let saveTitle = self.title
        let saveArtist = self.artist
        let saveAlbum = self.album
        let saveTrackNum = self.trackNumber
        let saveYear = self.year
        let saveGenre = self.genre
        let saveCover = self.isCoverArtModified ? self.coverData : nil
        let saveLyricsText = self.lyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let didLyricsChange = (lyricsDraft != (originalLyrics ?? ""))
        
        Task {
            let url = URL(fileURLWithPath: track.fullPath)
            do {
                // 1. Write tags and embedded artwork
                try AudioTagger.shared.writeMetadata(
                    fileURL: url,
                    title: saveTitle,
                    artist: saveArtist,
                    album: saveAlbum,
                    trackNumber: saveTrackNum,
                    year: saveYear,
                    genre: saveGenre,
                    coverArtData: saveCover
                )
                
                // 2. Handle lyrics if changed
                if didLyricsChange {
                    if saveLyricsText.isEmpty {
                        try? AudioTagger.shared.deleteLyrics(fileURL: url)
                    } else {
                        try? AudioTagger.shared.saveLyrics(fileURL: url, lyrics: saveLyricsText)
                    }
                }
                
                // 3. Invalidate caches
                AudioTagger.shared.invalidateCaches(fileURL: url)
                CoverArtCache.shared.invalidate(forFullPath: track.fullPath, artist: track.primaryArtist, album: track.album)
                LibraryScanner.shared.invalidate(fullPath: track.fullPath)
                
                await MainActor.run {
                    self.isSaving = false
                    self.statusMessage = "Saved successfully!"
                    self.isError = false
                    self.onSaved()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.onDismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.statusMessage = "Error saving: \(error.localizedDescription)"
                    self.isError = true
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
    
    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    private var isHiRes: Bool {
        track.bitsPerSample > 16 || track.sampleRate > 48000
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WalkmanTheme.silverGradient)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Song Metadata Editor")
                        .font(WalkmanFont.title3)
                        .foregroundStyle(.white)
                    
                    Text(track.filename)
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
            
            // Top Hero Summary Card
            HStack(spacing: 16) {
                // Artwork thumbnail
                ZStack {
                    if let img = coverImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        TrackCoverThumbnail(track: track, size: 64)
                    }
                }
                .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title.isEmpty ? track.filename : title)
                            .font(WalkmanFont.title3)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if isHiRes {
                            Text("Hi-Res")
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(WalkmanTheme.hiResGoldGradient)
                                .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        }
                    }
                    
                    let dispArtist = artist.isEmpty ? track.artist : artist
                    let dispAlbum = album.isEmpty ? track.album : album
                    Text("\(dispArtist) — \(dispAlbum)")
                        .font(WalkmanFont.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 7) {
                        Text(track.format)
                            .font(WalkmanFont.badge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        
                        Text(formatDuration(track.durationSeconds))
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.tertiary)
                        
                        Text("•")
                            .foregroundStyle(.tertiary)
                        
                        Text(track.bitrateKbps > 0 ? "\(track.bitrateKbps) kbps" : "Lossless")
                            .font(WalkmanFont.monoSmall)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Play / Pause preview button
                let isThisPlaying = (player.currentTrack?.id == track.id && player.isPlaying)
                Button(action: {
                    if isThisPlaying {
                        player.pause()
                    } else {
                        player.play(track: track)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isThisPlaying ? "Playing" : "Preview")
                            .font(WalkmanFont.calloutMedium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isThisPlaying ? WalkmanTheme.silverGradient : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    .foregroundStyle(isThisPlaying ? Color(red: 20/255, green: 20/255, blue: 24/255) : .white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.025))
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            // Segmented Picker
            Picker("", selection: $selectedTab) {
                ForEach(EditorTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .tags:
                        tagsAndSpecsTab
                    case .artwork:
                        artworkTab
                    case .lyrics:
                        lyricsTab
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Footer Bar
            HStack(spacing: 12) {
                // Status message
                if let msg = statusMessage {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(isError ? Color.orange : Color.green)
                        }
                        Text(msg)
                            .font(WalkmanFont.calloutMedium)
                            .foregroundStyle(isError ? Color.orange : (isSaving ? WalkmanTheme.silverLight : Color.green))
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
                
                Button(action: saveAllChanges) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                            Text("Saving...")
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Save Metadata")
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(WalkmanTheme.background)
        }
        .frame(minWidth: 960, idealWidth: 1050, maxWidth: 1180, minHeight: 820, idealHeight: 880, maxHeight: 1020)
        .background(WalkmanTheme.background.ignoresSafeArea())
        .onAppear {
            loadInitialData()
        }
    }
    
    // MARK: - Tags & Specs Tab
    private var tagsAndSpecsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Action to fetch online info
            HStack {
                Text("SONG TAGS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button(action: fetchOnlineMetadataInfo) {
                    HStack(spacing: 5) {
                        if isFetchingOnlineInfo {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                            Text("Matching...")
                                .font(WalkmanFont.subheadlineMedium)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Auto-Fill Online Info")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isFetchingOnlineInfo)
                .help("Query iTunes and Deezer databases to auto-populate title, artist, album, year, and genre")
            }
            
            // Input Fields Grid
            VStack(spacing: 12) {
                EditorField(label: "Title", text: $title)
                
                HStack(spacing: 14) {
                    EditorField(label: "Artist", text: $artist)
                    EditorField(label: "Album", text: $album)
                }
                
                HStack(spacing: 14) {
                    EditorField(label: "Track #", text: $trackNumber)
                    EditorField(label: "Year", text: $year)
                    EditorField(label: "Genre", text: $genre)
                }
            }
            
            // Audio Specs Card
            VStack(alignment: .leading, spacing: 10) {
                Text("AUDIO PROPERTIES & HARDWARE TAGS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 7) {
                            specLine(label: "Audio Format", value: "\(track.format) (\(track.bitsPerSample)-bit / \(track.sampleRate) Hz)")
                            specLine(label: "Bitrate", value: track.bitrateKbps > 0 ? "\(track.bitrateKbps) kbps" : "Lossless")
                            specLine(label: "Duration", value: formatDuration(track.durationSeconds))
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 7) {
                            specLine(label: "File Size", value: formatSize(track.sizeBytes))
                            specLine(label: "Hardware Tags", value: track.format == "MP3" ? "Strict ID3v2.3 (UTF-16)" : "Vorbis Comments")
                            specLine(label: "File Path", value: track.fullPath, canCopy: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 8)
            }
        }
    }
    
    // MARK: - Artwork Tab
    private var artworkTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ALBUM ARTWORK")
                .font(WalkmanFont.sectionHeader)
                .foregroundStyle(.tertiary)
            
            HStack(alignment: .top, spacing: 28) {
                // Artwork display with drag & drop
                VStack(spacing: 10) {
                    ZStack {
                        if let img = coverImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 320, height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                                )
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                    .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.25))
                                    .frame(width: 320, height: 320)
                                    .background(Color.white.opacity(0.02))
                                
                                VStack(spacing: 10) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 38))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("Drop Artwork Here")
                                        .font(WalkmanFont.calloutMedium)
                                        .foregroundStyle(.secondary)
                                    Text("Or click to select image")
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
                    .help("Click or drag-and-drop to choose album cover art")
                    .contextMenu {
                        if coverImage != nil || coverData != nil {
                            Button(action: exportArtworkToMac) {
                                Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                            }
                            Divider()
                        }
                        Button(action: selectArtworkFile) {
                            Label("Choose Image File...", systemImage: "folder")
                        }
                        Button(action: fetchOnlineArtwork) {
                            Label("Fetch Online Cover Art", systemImage: "arrow.down.circle")
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
                        HStack(spacing: 5) {
                            Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(st.valid ? Color.green : Color.orange)
                            Text(st.message)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Artwork Actions & Information
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Walkman Hardware Artwork Engine")
                            .font(WalkmanFont.bodyBold)
                            .foregroundStyle(.white)
                        
                        Text("Sony Walkman display chips require Baseline RGB JPEG format with a maximum resolution of 800×800. Progressive JPEGs and CMYK color profiles freeze the Walkman screen. Walkman Studio automatically converts imported artwork into strict Baseline RGB JPEG.")
                            .font(WalkmanFont.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 8)
                    
                    // Buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: selectArtworkFile) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                Text("Choose Image File...")
                                    .font(WalkmanFont.calloutMedium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: fetchOnlineArtwork) {
                            HStack(spacing: 6) {
                                if isFetchingOnlineArt {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                    Text("Searching Online...")
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 11))
                                    Text("Fetch Online Cover Art")
                                }
                            }
                            .font(WalkmanFont.calloutMedium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(WalkmanTheme.silverLight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isFetchingOnlineArt)
                        
                        if coverImage != nil || coverData != nil {
                            Button(action: exportArtworkToMac) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 11))
                                    Text("Export Cover Art to Mac...")
                                }
                                .font(WalkmanFont.calloutMedium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Export and save this cover art image file to your Mac")
                        }
                        
                        if coverImage != nil {
                            Button(action: removeArtwork) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                    Text("Remove Artwork")
                                }
                                .font(WalkmanFont.calloutMedium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(Color(red: 255/255, green: 110/255, blue: 100/255))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if isCoverArtModified {
                            Button(action: revertArtwork) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 11))
                                    Text("Revert to Original")
                                }
                                .font(WalkmanFont.callout)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Lyrics Tab
    private var lyricsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SONY WALKMAN .LRC LYRICS")
                    .font(WalkmanFont.sectionHeader)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if let msg = lyricsStatusMessage {
                    Text(msg)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.green)
                } else if let err = lyricsErrorMessage {
                    Text(err)
                        .font(WalkmanFont.monoSmall)
                        .foregroundStyle(Color.orange)
                } else if !lyricsDraft.isEmpty {
                    Text(lyricsDraft.contains("[") ? "Synced .LRC" : "Plain Lyrics")
                        .font(WalkmanFont.badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(WalkmanTheme.silverLight)
                        .clipShape(Capsule())
                }
                
                Button(action: fetchLyricsOnline) {
                    HStack(spacing: 5) {
                        if isFetchingLyrics {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                            Text("Fetching...")
                                .font(WalkmanFont.subheadlineMedium)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                            Text("Fetch Online Lyrics")
                                .font(WalkmanFont.subheadlineMedium)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(WalkmanTheme.silverLight)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isFetchingLyrics)
                
                if !lyricsDraft.isEmpty {
                    Button(action: {
                        lyricsDraft = ""
                        isLyricsModified = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear lyrics")
                }
            }
            
            TextEditor(text: $lyricsDraft)
                .font(WalkmanFont.mono)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 400, maxHeight: 540)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .onChange(of: lyricsDraft) { _, _ in
                    isLyricsModified = true
                }
            
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Walkman non-Android OS reads synchronized [mm:ss.xx] lines from .LRC files next to the music file.")
                    .font(WalkmanFont.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private func specLine(label: String, value: String, canCopy: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            
            Text(value)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            if canCopy {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(WalkmanTheme.silverLight)
                }
                .buttonStyle(.plain)
                .help("Copy full file path")
            }
        }
    }
}

private struct EditorField: View {
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
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}
