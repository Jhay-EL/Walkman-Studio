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
    
    var onClose: (() -> Void)? = nil
    
    public init(track: Track?, onSaved: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.track = track
        self.onSaved = onSaved
        self.onClose = onClose
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
    
    private func saveLyrics() {
        guard let tr = track else { return }
        let url = URL(fileURLWithPath: tr.fullPath)
        do {
            try AudioTagger.shared.saveLyrics(fileURL: url, lyrics: lyricsDraft)
            self.lyrics = lyricsDraft
            self.isEditingLyrics = false
            self.lyricsStatusMessage = "Saved .lrc file (Walkman NW-A55 native)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.lyricsStatusMessage = nil
            }
        } catch {
            self.lyricsStatusMessage = "Error: \(error.localizedDescription)"
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
                if tr.format == "MP3" {
                    try AudioTagger.shared.writeMP3Metadata(
                        fileURL: url,
                        title: title,
                        artist: artist,
                        album: album,
                        trackNumber: trackNumber,
                        year: year,
                        genre: genre,
                        coverArtData: coverData
                    )
                }
                
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
        VStack(spacing: 0) {
            // Header Bar aligned to mid page navigation bar
            HStack {
                Spacer()
                
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Preview Pane (Cmd+I)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 36)
            
            Divider()
                .overlay(Color.white.opacity(0.06))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let tr = track {
                        // Track Title & Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(tr.title.isEmpty ? tr.filename : tr.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    
                                    if isHiRes(tr) {
                                        Text("Hi-Res")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.white.opacity(0.16))
                                            .foregroundStyle(WalkmanTheme.silverLight)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                                
                                Text("\(tr.artist) — \(tr.album)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                    
                    // Album Artwork Card (Drop Zone)
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WalkmanTheme.card)
                                .frame(height: 180)
                            
                            if let img = coverImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 28))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("Drop Album Artwork Here")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("Auto-encoded to Baseline RGB JPEG (max 800×800)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isTargeted ? WalkmanTheme.silver : Color.white.opacity(0.1), lineWidth: isTargeted ? 2 : 1)
                        )
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
                        
                        // Artwork Compliance Status
                        if let st = validationStatus {
                            HStack(spacing: 6) {
                                Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(st.valid ? Color.green : Color.orange)
                                Text(st.message)
                                    .font(.system(size: 9, design: .monospaced))
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
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if let msg = lyricsStatusMessage {
                                Text(msg)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                            } else if lyrics != nil {
                                Text("Synced / .LRC")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                            }
                            
                            Button(action: {
                                isEditingLyrics.toggle()
                                if isEditingLyrics {
                                    lyricsDraft = lyrics ?? ""
                                }
                            }) {
                                Image(systemName: isEditingLyrics ? "xmark" : (lyrics != nil ? "pencil" : "plus"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(WalkmanTheme.silver)
                            }
                            .buttonStyle(.plain)
                            .help(isEditingLyrics ? "Cancel editing" : (lyrics != nil ? "Edit lyrics" : "Add lyrics (.lrc)"))
                        }
                        
                        if isEditingLyrics {
                            VStack(alignment: .trailing, spacing: 6) {
                                TextEditor(text: $lyricsDraft)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 120, maxHeight: 180)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                HStack {
                                    Button("Save as .LRC") {
                                        saveLyrics()
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(WalkmanTheme.silverGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if let lyr = lyrics, !lyr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ScrollView {
                                Text(lyr)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
                            )
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "music.mic")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                                
                                Text("No lyrics available for this song")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Button("Add .LRC") {
                                    isEditingLyrics = true
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WalkmanTheme.silver)
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .liquidGlass(cornerRadius: 8)
                        }
                    }
                    
                    // Technical Specifications (Compact Grid)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AUDIO PROPERTIES")
                            .font(.system(size: 9, weight: .bold))
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
                    
                    // Reveal in Finder Button
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tr.fullPath)])
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("Reveal in Finder")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    // Metadata Input Form
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TAGS & METADATA")
                            .font(.system(size: 9, weight: .bold))
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
                        .font(.system(size: 11, weight: .semibold))
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
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear { loadTrack() }
        .onChange(of: track?.id) { loadTrack() }
    }
    }
}

private struct SpecRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

private struct FormInput: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
