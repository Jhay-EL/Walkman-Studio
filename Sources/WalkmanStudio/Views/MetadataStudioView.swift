import SwiftUI
import AppKit

public struct MetadataStudioView: View {
    let track: Track?
    let onSaved: (() -> Void)?
    let onEdit: (() -> Void)?
    
    @ObservedObject private var player = AudioPlayerService.shared
    
    @State private var currentTrackId: String? = nil
    @State private var coverImage: NSImage? = nil
    @State private var coverData: Data? = nil
    @State private var validationStatus: (valid: Bool, message: String)? = nil
    @State private var lyrics: String? = nil
    @State private var verifiedMetadata: AudioFileMetadata? = nil
    @State private var isLyricsCopied: Bool = false
    @State private var isPathCopied: Bool = false
    
    public init(
        track: Track?,
        onSaved: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.track = track
        self.onSaved = onSaved
        self.onEdit = onEdit
    }
    
    private var displayTitle: String {
        if let t = track?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        if let t = verifiedMetadata?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return track?.filename ?? "Unknown Track"
    }

    private var displayArtist: String {
        if let a = track?.artist, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return a
        }
        if let a = verifiedMetadata?.artist, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return a
        }
        return "Unknown Artist"
    }

    private var displayAlbum: String {
        if let al = track?.album, !al.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return al
        }
        if let al = verifiedMetadata?.album, !al.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return al
        }
        return "Unknown Album"
    }

    private var displayYear: String {
        if let y = track?.year, !y.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return y
        }
        return verifiedMetadata?.year ?? ""
    }

    private var displayGenre: String {
        if let g = track?.genre, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return g
        }
        return verifiedMetadata?.genre ?? ""
    }

    private var displayTrackNum: String {
        if let tn = track?.trackNum, !tn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tn
        }
        return verifiedMetadata?.trackNumber ?? ""
    }

    private var isHiRes: Bool {
        guard let tr = track else { return false }
        return tr.bitsPerSample > 16 || tr.sampleRate > 48000
    }
    
    private var activeLyrics: String? {
        if let lyr = lyrics, !lyr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lyr
        }
        if let lyr = verifiedMetadata?.lyrics, !lyr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lyr
        }
        return nil
    }

    private var hasLyricsOnWalkman: Bool {
        activeLyrics != nil
    }

    private struct ParsedLyricLine: Identifiable, Hashable {
        let id: Int
        let timestamp: String?
        let text: String
    }

    private var parsedLyricLines: [ParsedLyricLine] {
        guard let raw = activeLyrics else { return [] }
        let rawLines = raw.components(separatedBy: .newlines)
        var result: [ParsedLyricLine] = []
        
        let pattern = #"^\[(\d{1,2}:\d{2}(?:[.:]\d{1,3})?)\](.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        var lineIndex = 0
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[ti:") || trimmed.hasPrefix("[ar:") ||
               trimmed.hasPrefix("[al:") || trimmed.hasPrefix("[by:") ||
               trimmed.hasPrefix("[offset:") || trimmed.hasPrefix("[length:") {
                continue
            }
            
            let nsLine = trimmed as NSString
            if let match = regex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsLine.length)) {
                let timeRange = match.range(at: 1)
                let textRange = match.range(at: 2)
                let timeStr = nsLine.substring(with: timeRange)
                let textStr = nsLine.substring(with: textRange).trimmingCharacters(in: .whitespaces)
                result.append(ParsedLyricLine(id: lineIndex, timestamp: timeStr, text: textStr))
            } else {
                result.append(ParsedLyricLine(id: lineIndex, timestamp: nil, text: trimmed))
            }
            lineIndex += 1
        }
        return result
    }

    private var isSyncedLyrics: Bool {
        guard let lyr = activeLyrics else { return false }
        return lyr.contains("[") && lyr.contains("]") && parsedLyricLines.contains(where: { $0.timestamp != nil })
    }

    private func formatSampleRate(_ hz: Int) -> String {
        if hz <= 0 { return "" }
        if hz % 1000 == 0 {
            return "\(hz / 1000) kHz"
        } else {
            let khz = Double(hz) / 1000.0
            return String(format: "%.1f kHz", locale: Locale(identifier: "en_US_POSIX"), khz)
        }
    }
    
    private func formatQuality(_ tr: Track) -> String {
        let bits = tr.bitsPerSample > 0 ? "\(tr.bitsPerSample)-bit" : ""
        let rate = formatSampleRate(tr.sampleRate)
        if !bits.isEmpty && !rate.isEmpty {
            return "\(bits) / \(rate)"
        } else if !bits.isEmpty {
            return bits
        } else if !rate.isEmpty {
            return rate
        }
        return tr.format
    }

    private func artworkStatusShortLabel(_ st: (valid: Bool, message: String)) -> String {
        if st.valid {
            if let img = coverImage {
                let w = Int(img.size.width)
                let h = Int(img.size.height)
                if w > 0 && h > 0 {
                    return "\(w)×\(h) • Walkman Ready"
                }
            }
            return "Walkman Ready (Baseline)"
        } else {
            if let img = coverImage {
                let w = Int(img.size.width)
                let h = Int(img.size.height)
                if w > 800 || h > 800 {
                    return "\(w)×\(h) • Exceeds 800px"
                }
            }
            if st.message.contains("Progressive") {
                return "Progressive JPEG (Advisory)"
            }
            if st.message.contains("Color mode") || st.message.contains("RGB") {
                return "Non-RGB Color Mode"
            }
            return st.message
        }
    }

    private func loadTrack() {
        guard let tr = track else {
            currentTrackId = nil
            coverImage = nil
            coverData = nil
            validationStatus = nil
            lyrics = nil
            verifiedMetadata = nil
            return
        }
        
        let isDifferentTrack = (currentTrackId != tr.id)
        currentTrackId = tr.id
        
        if isDifferentTrack {
            coverImage = nil
            coverData = nil
            validationStatus = nil
            lyrics = nil
            verifiedMetadata = nil
            isLyricsCopied = false
            isPathCopied = false
            
            let url = URL(fileURLWithPath: tr.fullPath)
            
            // Asynchronous extraction of artwork, lyrics, and metadata
            DispatchQueue.global(qos: .userInitiated).async {
                let art = AudioTagger.shared.extractCoverArt(fileURL: url)
                let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
                let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
                let img = art != nil ? NSImage(data: art!) : nil
                let meta = AudioTagger.shared.readMetadata(fileURL: url)
                
                DispatchQueue.main.async {
                    guard self.track?.id == tr.id else { return }
                    self.coverData = art
                    self.coverImage = img
                    self.validationStatus = val
                    self.lyrics = lyr ?? meta?.lyrics
                    self.verifiedMetadata = meta
                }
            }
        }
    }
    
    private func exportArtworkToMac() {
        guard let tr = track else { return }
        let cleanArtist = WalkmanEngine.shared.sanitizeFilename(displayArtist.isEmpty ? (tr.artist.isEmpty ? "Unknown Artist" : tr.artist) : displayArtist)
        let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(displayAlbum.isEmpty ? (tr.album.isEmpty ? tr.title : tr.album) : displayAlbum)
        let suggestedName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        ArtworkExportService.exportCustomArtwork(data: coverData, image: coverImage, suggestedFilename: suggestedName)
    }

    private func revealInFinder() {
        guard let tr = track else { return }
        let url = URL(fileURLWithPath: tr.fullPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyLyricsToClipboard() {
        guard let lyr = lyrics, !lyr.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lyr, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isLyricsCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isLyricsCopied = false
            }
        }
    }

    private func copyPathToClipboard() {
        guard let tr = track else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tr.fullPath, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isPathCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isPathCopied = false
            }
        }
    }

    private func togglePlayback() {
        guard let tr = track else { return }
        if player.currentTrack?.id == tr.id && player.isPlaying {
            player.pause()
        } else {
            player.play(track: tr)
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let tr = track {
                    // 1. HERO HEADER: Track Title, Badges & Playback Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayTitle)
                                    .font(WalkmanFont.title3)
                                    .foregroundStyle(.white)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                                
                                Text(displayArtist)
                                    .font(WalkmanFont.calloutMedium)
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                
                                Text("\(displayAlbum)\(displayYear.isEmpty ? "" : " (\(displayYear))")")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            
                            Spacer(minLength: 8)
                            
                            // Audio Preview Play / Pause
                            let isThisPlaying = (player.currentTrack?.id == tr.id && player.isPlaying)
                            Button(action: togglePlayback) {
                                HStack(spacing: 4.5) {
                                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(isThisPlaying ? "Playing" : "Preview")
                                        .font(WalkmanFont.badge)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Group {
                                        if isThisPlaying {
                                            WalkmanTheme.silverGradient
                                        } else {
                                            Color.white.opacity(0.12)
                                        }
                                    }
                                )
                                .foregroundStyle(isThisPlaying ? Color(red: 20/255, green: 20/255, blue: 24/255) : .white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(WalkmanSideActionButtonStyle(cornerRadius: 12))
                            .help(isThisPlaying ? "Pause audio preview" : "Play preview on audio player")
                        }
                        
                        // Audio Badges Row
                        HStack(spacing: 6) {
                            if isHiRes {
                                Text("Hi-Res")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(WalkmanTheme.hiResGoldGradient)
                                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            }
                            
                            Text(tr.format)
                                .font(WalkmanFont.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            
                            let qualityStr = formatQuality(tr)
                            if !qualityStr.isEmpty {
                                Text(qualityStr)
                                    .font(WalkmanFont.monoSmall)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.06))
                                    .foregroundStyle(.secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            }

                            if hasLyricsOnWalkman {
                                HStack(spacing: 3) {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.system(size: 8))
                                    Text(isSyncedLyrics ? "LRC" : "Lyrics")
                                        .font(WalkmanFont.badge)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            }
                        }
                    }
                    
                    // 2. ALBUM ARTWORK CARD (View Only with Export)
                    VStack(spacing: 8) {
                        if let img = coverImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity)
                                .contextMenu {
                                    Button(action: exportArtworkToMac) {
                                        Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                                    }
                                    Button(action: revealInFinder) {
                                        Label("Reveal Audio File in Finder", systemImage: "folder")
                                    }
                                }
                            
                            // Artwork Compliance & Export
                            HStack(alignment: .center, spacing: 6) {
                                if let st = validationStatus {
                                    HStack(spacing: 4.5) {
                                        Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(st.valid ? Color.green : Color.orange)
                                        Text(artworkStatusShortLabel(st))
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(st.valid ? .secondary : Color.orange)
                                            .lineLimit(1)
                                    }
                                    .help(st.message)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 10))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                        Text("Embedded Cover Art")
                                            .font(WalkmanFont.monoSmall)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer(minLength: 4)
                                
                                Button(action: exportArtworkToMac) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.system(size: 10))
                                        Text("Export")
                                            .font(WalkmanFont.monoSmall)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }
                                .buttonStyle(WalkmanSideActionButtonStyle(cornerRadius: 5))
                                .help("Export artwork to Mac...")
                            }
                        } else {
                            // Non-editable Minimal Artwork Placeholder
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    .frame(height: 140)
                                
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.05))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "opticaldisc.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(WalkmanTheme.silverMuted)
                                    }
                                    Text("No Embedded Artwork")
                                        .font(WalkmanFont.calloutMedium)
                                        .foregroundStyle(.secondary)
                                    Text("Walkman shows default disc animation")
                                        .font(WalkmanFont.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    
                    // 3. QUICK STATS 2x2 GRID (Optimized layout, no clipped labels)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        StatTile(
                            icon: "clock",
                            label: "DURATION",
                            value: formatDuration(tr.durationSeconds)
                        )
                        StatTile(
                            icon: "speedometer",
                            label: "BITRATE",
                            value: tr.bitrateKbps > 0 ? "\(tr.bitrateKbps) kbps" : "Lossless"
                        )
                        StatTile(
                            icon: "waveform",
                            label: "QUALITY",
                            value: formatQuality(tr),
                            highlight: isHiRes
                        )
                        StatTile(
                            icon: "internaldrive",
                            label: "FILE SIZE",
                            value: formatSize(tr.sizeBytes)
                        )
                    }

                    // 4. LYRICS VIEWER (ONLY IF WALKMAN HAS LYRICS INSIDE)
                    if hasLyricsOnWalkman {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("LYRICS", systemImage: "quote.bubble.fill")
                                    .font(WalkmanFont.sectionHeader)
                                    .foregroundStyle(.tertiary)
                                
                                Spacer()
                                
                                Text(isSyncedLyrics ? "Synced .LRC" : "Walkman Lyrics")
                                    .font(WalkmanFont.badge)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                                
                                Button(action: copyLyricsToClipboard) {
                                    HStack(spacing: 3) {
                                        Image(systemName: isLyricsCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 9))
                                        Text(isLyricsCopied ? "Copied" : "Copy")
                                            .font(WalkmanFont.monoSmall)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(isLyricsCopied ? Color.green : WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Copy full lyrics to clipboard")
                            }
                            
                            // Scrollable Lyric Reader
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(parsedLyricLines, id: \.id) { line in
                                        if let ts = line.timestamp {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(ts)
                                                    .font(WalkmanFont.monoSmall)
                                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                                    .frame(width: 44, alignment: .leading)
                                                
                                                Text(line.text.isEmpty ? "• • •" : line.text)
                                                    .font(WalkmanFont.calloutMedium)
                                                    .foregroundStyle(line.text.isEmpty ? Color.secondary : Color.white)
                                                    .textSelection(.enabled)
                                                
                                                Spacer()
                                            }
                                        } else {
                                            Text(line.text.isEmpty ? " " : line.text)
                                                .font(WalkmanFont.callout)
                                                .foregroundStyle(line.text.isEmpty ? Color.secondary : Color.white)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                .padding(10)
                            }
                            .frame(maxHeight: 200)
                            .liquidGlass(cornerRadius: 8)
                        }
                    }

                    // 5. TAGS & METADATA (VIEW ONLY)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("TAGS & METADATA", systemImage: "tag.fill")
                                .font(WalkmanFont.sectionHeader)
                                .foregroundStyle(.tertiary)
                            
                            Spacer()
                            
                            if let editAction = onEdit {
                                Button(action: editAction) {
                                    HStack(spacing: 3.5) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Edit in Studio")
                                            .font(WalkmanFont.badge)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundStyle(WalkmanTheme.silverLight)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Open song metadata in full editor sheet")
                            }
                        }
                        
                        VStack(spacing: 0) {
                            ReadOnlyDetailRow(label: "Title", value: displayTitle)
                            Divider().overlay(Color.white.opacity(0.06))
                            ReadOnlyDetailRow(label: "Artist", value: displayArtist)
                            Divider().overlay(Color.white.opacity(0.06))
                            ReadOnlyDetailRow(label: "Album", value: displayAlbum)
                            Divider().overlay(Color.white.opacity(0.06))
                            ReadOnlyDetailRow(label: "Track #", value: displayTrackNum.isEmpty ? "—" : "#\(displayTrackNum)", isMonospace: true)
                            Divider().overlay(Color.white.opacity(0.06))
                            ReadOnlyDetailRow(label: "Year", value: displayYear.isEmpty ? "—" : displayYear, isMonospace: true)
                            Divider().overlay(Color.white.opacity(0.06))
                            ReadOnlyDetailRow(label: "Genre", value: displayGenre.isEmpty ? "—" : displayGenre)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlass(cornerRadius: 8)
                    }

                    // 6. AUDIO PROPERTIES & SPECIFICATIONS (VIEW ONLY)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("AUDIO PROPERTIES", systemImage: "waveform")
                            .font(WalkmanFont.sectionHeader)
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 0) {
                            AudioSpecRow(label: "Format", value: tr.format, systemImage: "doc.fill")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(label: "Duration", value: formatDuration(tr.durationSeconds), systemImage: "clock")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(label: "Bitrate", value: tr.bitrateKbps > 0 ? "\(tr.bitrateKbps) kbps" : "Lossless", systemImage: "speedometer")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(label: "Audio Quality", value: formatQuality(tr), systemImage: "waveform.path")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(label: "File Size", value: formatSize(tr.sizeBytes), systemImage: "internaldrive")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(
                                label: "Hardware Tags",
                                value: tr.format == "MP3" ? "Strict ID3v2.3 (UTF-16)" : (tr.format == "FLAC" ? "Vorbis Comments" : "MP4 iTunes Tags"),
                                systemImage: "cpu"
                            )
                            if hasLyricsOnWalkman {
                                Divider().overlay(Color.white.opacity(0.06))
                                AudioSpecRow(
                                    label: "Lyrics",
                                    value: isSyncedLyrics ? "Synchronized .LRC" : "Embedded Text",
                                    systemImage: "quote.bubble.fill",
                                    isSuccess: true
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlass(cornerRadius: 8)
                    }
                    
                    // 7. FILE LOCATION & REVEAL IN FINDER
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("FILE LOCATION")
                                .font(WalkmanFont.sectionHeader)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button(action: copyPathToClipboard) {
                                HStack(spacing: 3) {
                                    Image(systemName: isPathCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                    Text(isPathCopied ? "Copied" : "Copy Path")
                                        .font(WalkmanFont.monoSmall)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.white.opacity(0.06))
                                .foregroundStyle(isPathCopied ? Color.green : WalkmanTheme.silverMuted)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Copy full file path to clipboard")
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr.relativePath.isEmpty ? tr.filename : tr.relativePath)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            
                            Button(action: revealInFinder) {
                                HStack(spacing: 5) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10))
                                    Text("Reveal in Finder")
                                        .font(WalkmanFont.calloutMedium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.07))
                                .foregroundStyle(WalkmanTheme.silverLight)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(WalkmanSideActionButtonStyle(isFullWidth: true, cornerRadius: 6))
                            .help("Show audio file in macOS Finder")
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 8)
                    }

                } else {
                    // Empty State
                    VStack(spacing: 12) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 56, height: 56)
                            Image(systemName: "sidebar.trailing")
                                .font(.system(size: 24))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        Text("Track Details")
                            .font(WalkmanFont.headline)
                            .foregroundStyle(.white)
                        Text("Select a song from the library to inspect its audio properties, hardware tags, cover artwork, and lyrics.")
                            .font(WalkmanFont.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.all, edges: .top)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [
                    WalkmanTheme.background,
                    WalkmanTheme.background.opacity(0.85),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 48)
            .allowsHitTesting(false)
            .ignoresSafeArea(.all, edges: .top)
        }
        .onAppear { loadTrack() }
        .onChange(of: track) { loadTrack() }
    }
}

// MARK: - Subcomponents

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4.5) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                Text(label)
                    .font(WalkmanFont.badge)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(WalkmanFont.monoSmall)
                .fontWeight(.semibold)
                .foregroundStyle(highlight ? WalkmanTheme.hiResGold : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ReadOnlyDetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(WalkmanFont.subheadlineMedium)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            if value.isEmpty {
                Text("—")
                    .font(isMonospace ? WalkmanFont.monoSmall : WalkmanFont.subheadlineMedium)
                    .foregroundStyle(.tertiary)
            } else {
                Text(value)
                    .font(isMonospace ? WalkmanFont.monoSmall : WalkmanFont.subheadlineMedium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3.5)
    }
}

private struct AudioSpecRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var isSuccess: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(size: 10))
                    .foregroundStyle(WalkmanTheme.silverMuted)
                    .frame(width: 14)
            }
            Text(label)
                .font(WalkmanFont.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            if isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            
            Text(value)
                .font(WalkmanFont.monoSmall)
                .foregroundStyle(isSuccess ? WalkmanTheme.silverLight : .white)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
