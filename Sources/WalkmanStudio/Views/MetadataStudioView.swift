import SwiftUI
import AppKit

public struct MetadataStudioView: View {
    let track: Track?
    let onSaved: () -> Void
    
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var trackNumber: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    
    @State private var coverImage: NSImage?
    @State private var coverData: Data?
    @State private var validationStatus: (valid: Bool, message: String)?
    @State private var isSaving: Bool = false
    @State private var showSuccess: Bool = false
    @State private var isTargeted: Bool = false
    
    // Lyrics State
    @State private var lyrics: String? = nil
    @State private var isEditingLyrics: Bool = false
    @State private var lyricsDraft: String = ""
    @State private var lyricsStatusMessage: String? = nil
    @State private var isFetchingLyrics: Bool = false
    
    public init(track: Track?, onSaved: @escaping () -> Void) {
        self.track = track
        self.onSaved = onSaved
    }
    
    private func loadTrack() {
        guard let tr = track else { return }
        title = tr.title
        artist = tr.artist
        album = tr.album
        trackNumber = tr.trackNum
        year = tr.year
        genre = tr.genre
        isEditingLyrics = false
        lyricsStatusMessage = nil
        
        let url = URL(fileURLWithPath: tr.fullPath)
        
        // Fast asynchronous loading of artwork and lyrics to eliminate selection lag
        DispatchQueue.global(qos: .userInitiated).async {
            let art = AudioTagger.shared.extractCoverArt(fileURL: url)
            let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
            let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
            let img = art != nil ? NSImage(data: art!) : nil
            
            DispatchQueue.main.async {
                guard self.track?.id == tr.id else { return }
                self.coverData = art
                self.coverImage = img
                self.validationStatus = val
                self.lyrics = lyr
                self.lyricsDraft = lyr ?? ""
            }
        }
    }
    
    private func handleDroppedImage(data: Data) {
        if let baseline = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: data) {
            self.coverData = baseline
            self.coverImage = NSImage(data: baseline)
            self.validationStatus = WalkmanEngine.shared.isBaselineRGBJPEG(data: baseline)
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
            handleDroppedImage(data: data)
        }
    }
    
    private func saveLyrics() {
        guard let tr = track else { return }
        let url = URL(fileURLWithPath: tr.fullPath)
        let trimmed = lyricsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try AudioTagger.shared.deleteLyrics(fileURL: url)
                self.lyrics = nil
                self.isEditingLyrics = false
                self.lyricsStatusMessage = "Removed .LRC from Walkman"
            } else {
                try AudioTagger.shared.saveLyrics(fileURL: url, lyrics: trimmed)
                self.lyrics = trimmed
                self.isEditingLyrics = false
                self.lyricsStatusMessage = "Saved .lrc file (Sony Walkman native)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.lyricsStatusMessage = nil
            }
        } catch {
            self.lyricsStatusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func grabLyrics() {
        guard let tr = track else { return }
        
        withAnimation(.easeInOut(duration: 0.12)) {
            isFetchingLyrics = true
            lyricsStatusMessage = "Fetching .LRC online..."
        }

        let trackTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tr.title : self.title
        let trackArtist = self.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tr.artist : self.artist
        let trackAlbum = self.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tr.album : self.album
        let duration = tr.durationSeconds
        let fileURL = URL(fileURLWithPath: tr.fullPath)

        Task {
            do {
                let result = try await LyricsService.shared.fetchLyrics(
                    title: trackTitle,
                    artist: trackArtist,
                    album: trackAlbum,
                    durationSeconds: duration
                )

                // Write paired .lrc file to Walkman alongside music file
                try AudioTagger.shared.saveLyrics(fileURL: fileURL, lyrics: result.lyrics)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.lyrics = result.lyrics
                        self.lyricsDraft = result.lyrics
                        self.isEditingLyrics = false
                        self.isFetchingLyrics = false
                        self.lyricsStatusMessage = result.synced ? "Synced .LRC added!" : "Added .LRC to Walkman!"
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if self.lyricsStatusMessage?.contains("added") == true || self.lyricsStatusMessage?.contains("Added") == true {
                            withAnimation {
                                self.lyricsStatusMessage = nil
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isFetchingLyrics = false
                        self.lyricsStatusMessage = "No lyrics found online"
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        if self.lyricsStatusMessage == "No lyrics found online" {
                            withAnimation {
                                self.lyricsStatusMessage = nil
                            }
                        }
                    }
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
    
    private func isHiRes(_ tr: Track) -> Bool {
        tr.bitsPerSample > 16 || tr.sampleRate > 48000
    }
    
    private func saveMetadata() {
        guard let tr = track else { return }
        isSaving = true
        
        Task {
            let url = URL(fileURLWithPath: tr.fullPath)
            do {
                try AudioTagger.shared.writeMetadata(
                    fileURL: url,
                    title: title,
                    artist: artist,
                    album: album,
                    trackNumber: trackNumber,
                    year: year,
                    genre: genre,
                    coverArtData: coverData
                )
                
                // Invalidate all layers of artwork and scanner cache
                AudioTagger.shared.invalidateCaches(fileURL: url)
                CoverArtCache.shared.invalidate(forFullPath: tr.fullPath, artist: tr.primaryArtist, album: tr.album)
                LibraryScanner.shared.invalidate(fullPath: tr.fullPath)
                
                await MainActor.run {
                    self.isSaving = false
                    self.showSuccess = true
                    self.onSaved()
                }
                
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    self.showSuccess = false
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                }
            }
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let tr = track {
                        // Track Title & Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(tr.title.isEmpty ? tr.filename : tr.title)
                                        .font(WalkmanFont.title3)
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    
                                    if isHiRes(tr) {
                                        Text("Hi-Res")
                                            .font(WalkmanFont.badge)
                                            .padding(.horizontal, 4.5)
                                            .padding(.vertical, 1.5)
                                            .background(WalkmanTheme.hiResGoldGradient)
                                            .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    }
                                }
                                
                                Text("\(tr.artist) — \(tr.album)")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                    
                    // Album Artwork (Direct Image, No Background Container)
                    VStack(spacing: 8) {
                        Group {
                            if let img = coverImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
                                    )
                                    .frame(maxWidth: .infinity)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                        .foregroundStyle(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.2))
                                        .frame(height: 160)
                                    
                                    VStack(spacing: 6) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 28))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                        Text("Drop Album Artwork Here")
                                            .font(WalkmanFont.calloutMedium)
                                            .foregroundStyle(.secondary)
                                        Text("Auto-encoded to Baseline RGB JPEG (max 800×800)")
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
                                        handleDroppedImage(data: d)
                                    }
                                }
                            }
                            return true
                        }
                        .help("Click or drag-and-drop to choose album cover art")
                        
                        // Artwork Compliance Status
                        if let st = validationStatus {
                            HStack(spacing: 6) {
                                Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(st.valid ? Color.green : Color.orange)
                                Text(st.message)
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    // -------------------------------------------------------------
                    // LYRICS SECTION (Replaced Play Preview per User Request)
                    // -------------------------------------------------------------
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("LYRICS", systemImage: "quote.bubble.fill")
                                .font(WalkmanFont.sectionHeader)
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if isFetchingLyrics {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            }
                            
                            if let msg = lyricsStatusMessage {
                                Text(msg)
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            } else if let lyr = lyrics {
                                Text(lyr.contains("[") ? "Synced .LRC" : ".LRC File")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                            }
                            
                            if lyrics != nil && !isEditingLyrics {
                                Button(action: { grabLyrics() }) {
                                    if isFetchingLyrics {
                                        ProgressView()
                                            .scaleEffect(0.55)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11))
                                            .foregroundStyle(WalkmanTheme.silver)
                                            .frame(width: 22, height: 22)
                                            .contentShape(Rectangle())
                                    }
                                }
                                .buttonStyle(WalkmanPressableButtonStyle())
                                .disabled(isFetchingLyrics)
                                .help("Re-fetch / update .LRC from internet")
                            }
                            
                            if lyrics != nil {
                                Button(action: {
                                    isEditingLyrics.toggle()
                                    if isEditingLyrics {
                                        lyricsDraft = lyrics ?? ""
                                    }
                                }) {
                                    Image(systemName: isEditingLyrics ? "xmark" : "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(WalkmanTheme.silver)
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(WalkmanPressableButtonStyle())
                                .help(isEditingLyrics ? "Cancel editing" : "Edit lyrics manually")
                            }
                        }
                        
                        if isEditingLyrics {
                            VStack(alignment: .trailing, spacing: 6) {
                                TextEditor(text: $lyricsDraft)
                                    .font(WalkmanFont.mono)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 120, maxHeight: 180)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                HStack(spacing: 8) {
                                    Button(action: { grabLyrics() }) {
                                        HStack(spacing: 4) {
                                            if isFetchingLyrics {
                                                ProgressView()
                                                    .scaleEffect(0.55)
                                                    .frame(width: 12, height: 12)
                                                Text("Fetching...")
                                                    .font(WalkmanFont.subheadlineMedium)
                                            } else {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.system(size: 11))
                                                Text("Grab Online")
                                                    .font(WalkmanFont.subheadlineMedium)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4.5)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(WalkmanPressableButtonStyle())
                                    .disabled(isFetchingLyrics)
                                    .help("Fetch synced .LRC from internet")
                                    
                                    Spacer()
                                    
                                    Button("Save as .LRC") {
                                        saveLyrics()
                                    }
                                    .font(WalkmanFont.subheadlineMedium)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .contentShape(Rectangle())
                                    .buttonStyle(WalkmanPressableButtonStyle())
                                }
                            }
                        } else if let lyr = lyrics, !lyr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 6) {
                                if isFetchingLyrics {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                        Text("Fetching updated lyrics from internet...")
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                ScrollView {
                                    Text(lyr)
                                        .font(WalkmanFont.body)
                                        .lineSpacing(4)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(maxHeight: 160)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                        .allowsHitTesting(false)
                                )
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "music.mic")
                                    .font(.system(size: 15))
                                    .foregroundStyle(isFetchingLyrics ? WalkmanTheme.silverLight : Color.secondary)
                                
                                if isFetchingLyrics {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.65)
                                            .frame(width: 14, height: 14)
                                        Text("Fetching lyrics from internet...")
                                            .font(WalkmanFont.calloutMedium)
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                    }
                                } else {
                                    Text("No lyrics on Walkman")
                                        .font(WalkmanFont.callout)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Grab .LRC online from internet
                                Button(action: {
                                    grabLyrics()
                                }) {
                                    HStack(spacing: 6) {
                                        if isFetchingLyrics {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .frame(width: 12, height: 12)
                                            Text("Fetching...")
                                                .font(WalkmanFont.calloutBold)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("Add .LRC")
                                                .font(WalkmanFont.calloutBold)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Group {
                                            if isFetchingLyrics {
                                                Color.white.opacity(0.12)
                                            } else {
                                                WalkmanTheme.silverGradient
                                            }
                                        }
                                    )
                                    .foregroundStyle(isFetchingLyrics ? WalkmanTheme.silverLight : Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isFetchingLyrics)
                                .help(isFetchingLyrics ? "Fetching lyrics from internet in progress..." : "Automatically grab synced lyrics from internet and add .lrc to Walkman")
                            }
                            .padding(10)
                            .liquidGlass(cornerRadius: 8)
                        }
                    }
                    
                    // Technical Specifications (Compact Grid)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AUDIO PROPERTIES")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 4) {
                            SpecRow(label: "Format", value: tr.format)
                            SpecRow(label: "Duration", value: formatDuration(tr.durationSeconds))
                            SpecRow(label: "Bitrate", value: tr.bitrateKbps > 0 ? "\(tr.bitrateKbps) kbps" : "Lossless")
                            SpecRow(label: "Audio Quality", value: "\(tr.bitsPerSample)-bit / \(tr.sampleRate) Hz")
                            SpecRow(label: "File Size", value: formatSize(tr.sizeBytes))
                            SpecRow(label: "Hardware Tags", value: tr.format == "MP3" ? "Strict ID3v2.3 (UTF-16)" : "Vorbis Comments")
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 8)
                    }
                    
                    // Metadata Input Form
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAGS & METADATA")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 8) {
                            FormInput(label: "Title", text: $title)
                            FormInput(label: "Artist", text: $artist)
                            FormInput(label: "Album", text: $album)
                            HStack(spacing: 8) {
                                FormInput(label: "Track #", text: $trackNumber)
                                FormInput(label: "Year", text: $year)
                            }
                            FormInput(label: "Genre", text: $genre)
                        }
                    }
                    
                    // Save Button
                    Button(action: saveMetadata) {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if showSuccess {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text(showSuccess ? "Saved (ID3v2.3 / Baseline Art)" : (isSaving ? "Saving..." : "Save Tags & Artwork"))
                        }
                        .font(WalkmanFont.calloutBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if showSuccess {
                                    Color.green.opacity(0.85)
                                } else {
                                    WalkmanTheme.silverGradient
                                }
                            }
                        )
                        .foregroundStyle(showSuccess ? .white : Color(red: 20/255, green: 20/255, blue: 24/255))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No Track Selected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Select a song from the library to inspect audio specs, view lyrics, and edit Baseline RGB artwork.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, -38)
            .padding(.bottom, 24)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .onAppear { loadTrack() }
        .onChange(of: track) { loadTrack() }
    }
}

private struct SpecRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(WalkmanFont.mono)
                .foregroundStyle(.white)
        }
    }
}

private struct FormInput: View {
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
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
