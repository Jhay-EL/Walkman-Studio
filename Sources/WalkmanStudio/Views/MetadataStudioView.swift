import SwiftUI
import AppKit

public struct MetadataStudioView: View {
    let track: Track?
    let onSaved: (() -> Void)?
    let onEdit: (() -> Void)?
    
    @State private var currentTrackId: String? = nil
    @State private var coverImage: NSImage? = nil
    @State private var coverData: Data? = nil
    @State private var validationStatus: (valid: Bool, message: String)? = nil
    @State private var lyrics: String? = nil
    @State private var verifiedMetadata: AudioFileMetadata? = nil
    @State private var cachedLyricLines: [ParsedLyricLine] = []
    @State private var isLyricsCopied: Bool = false
    @State private var senseMeInfo: SenseMeInfo? = nil
    
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
        if let t = verifiedMetadata?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        if let t = track?.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return track?.filename ?? "Unknown Track"
    }

    private var displayArtist: String {
        if let a = verifiedMetadata?.artist, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return a
        }
        if let a = track?.artist, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return a
        }
        return "Unknown Artist"
    }

    private var displayAlbum: String {
        if let al = verifiedMetadata?.album, !al.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return al
        }
        if let al = track?.album, !al.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return al
        }
        return "Unknown Album"
    }

    private var displayYear: String {
        if let y = verifiedMetadata?.year, !y.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return y
        }
        if let y = track?.year, !y.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return y
        }
        return ""
    }

    private var displayGenre: String {
        if let g = verifiedMetadata?.genre, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return g
        }
        if let g = track?.genre, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return g
        }
        return ""
    }

    private var displayTrackNum: String {
        if let tn = verifiedMetadata?.trackNumber, !tn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tn
        }
        if let tn = track?.trackNum, !tn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tn
        }
        return ""
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
        !cachedLyricLines.isEmpty
    }

    private var isSyncedLyrics: Bool {
        cachedLyricLines.contains(where: { $0.timeInSeconds != nil })
    }

    public struct ParsedLyricLine: Identifiable, Hashable, Equatable, Sendable {
        public let id: Int
        public let timestamp: String?
        public let formattedTimestamp: String?
        public let timeInSeconds: Double?
        public let text: String
    }

    public nonisolated static func parseTimeStr(_ timeStr: String) -> Double? {
        let cleaned = timeStr.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        guard let mins = Double(parts[0]) else { return nil }
        let secString = parts[1...].joined(separator: ".").replacingOccurrences(of: ":", with: ".")
        guard let secs = Double(secString) else { return nil }
        return mins * 60.0 + secs
    }

    private nonisolated static let lyricTimestampRegex: NSRegularExpression? = {
        let pattern = #"\[(\d{1,2}:\d{2}(?:[.:]\d{1,3})?)\]"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    public nonisolated static func parseLyrics(_ raw: String?) -> [ParsedLyricLine] {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let rawLines = raw.components(separatedBy: .newlines)
        
        // 1. Extract any global LRC offset in milliseconds: [offset:+/-500]
        var offsetSeconds = 0.0
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("[offset:") {
                let inside = trimmed.dropFirst(8).replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                if let ms = Double(inside) {
                    offsetSeconds = ms / 1000.0
                }
            }
        }
        
        var result: [ParsedLyricLine] = []
        let regex = lyricTimestampRegex
        
        var lineIndex = 0
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[ti:") || trimmed.hasPrefix("[ar:") ||
               trimmed.hasPrefix("[al:") || trimmed.hasPrefix("[by:") ||
               trimmed.hasPrefix("[offset:") || trimmed.hasPrefix("[length:") {
                continue
            }
            
            let nsLine = trimmed as NSString
            let matches = regex?.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length)) ?? []
            
            if !matches.isEmpty {
                let textStr = regex?.stringByReplacingMatches(
                    in: trimmed,
                    range: NSRange(location: 0, length: nsLine.length),
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespaces) ?? ""
                
                for match in matches {
                    let timeRange = match.range(at: 1)
                    let timeStr = nsLine.substring(with: timeRange)
                    if let rawSec = parseTimeStr(timeStr) {
                        let finalSec = max(0.0, rawSec + offsetSeconds)
                        let m = Int(finalSec) / 60
                        let s = Int(finalSec) % 60
                        let formatted = String(format: "%02d:%02d", m, s)
                        result.append(ParsedLyricLine(
                            id: lineIndex,
                            timestamp: timeStr,
                            formattedTimestamp: formatted,
                            timeInSeconds: finalSec,
                            text: textStr
                        ))
                        lineIndex += 1
                    }
                }
            } else {
                result.append(ParsedLyricLine(
                    id: lineIndex,
                    timestamp: nil,
                    formattedTimestamp: nil,
                    timeInSeconds: nil,
                    text: trimmed
                ))
                lineIndex += 1
            }
        }
        
        let hasSynced = result.contains(where: { $0.timeInSeconds != nil })
        if hasSynced {
            result.sort { (a, b) -> Bool in
                let tA = a.timeInSeconds ?? Double.greatestFiniteMagnitude
                let tB = b.timeInSeconds ?? Double.greatestFiniteMagnitude
                if tA == tB {
                    return a.id < b.id
                }
                return tA < tB
            }
        }
        
        return result
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WalkmanTheme.silverMuted)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.85))
                .textCase(nil)
        }
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

    private var coverPixelSize: (width: Int, height: Int)? {
        guard let img = coverImage else { return nil }
        for rep in img.representations {
            if rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                return (rep.pixelsWide, rep.pixelsHigh)
            }
        }
        let w = Int(img.size.width)
        let h = Int(img.size.height)
        if w > 0 && h > 0 {
            return (w, h)
        }
        return nil
    }

    private func artworkStatusShortLabel(_ st: (valid: Bool, message: String)) -> String {
        let size = coverPixelSize
        if st.valid {
            if let (w, h) = size {
                return "\(w)×\(h) • Walkman Ready"
            }
            return "Walkman Ready (Baseline)"
        } else {
            if let (w, h) = size, (w > 800 || h > 800) {
                return "\(w)×\(h) • Exceeds 800px"
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

    private struct LoadedTrackDetails: Sendable {
        let art: Data?
        let validation: (valid: Bool, message: String)?
        let rawLyrics: String?
        let parsedLines: [ParsedLyricLine]
        let meta: AudioFileMetadata?
        let senseMe: SenseMeInfo?
    }

    private func loadTrackData(force: Bool = false) async {
        guard let tr = track else {
            currentTrackId = nil
            coverImage = nil
            coverData = nil
            validationStatus = nil
            lyrics = nil
            verifiedMetadata = nil
            cachedLyricLines = []
            senseMeInfo = nil
            return
        }
        
        let isDifferentTrack = (currentTrackId != tr.id)
        currentTrackId = tr.id
        
        if isDifferentTrack || force {
            if isDifferentTrack {
                // Pre-fill immediately from high-speed memory/SSD cache to eliminate blank flash
                coverImage = CoverArtCache.shared.thumbnail(for: tr)
                coverData = nil
                validationStatus = nil
                lyrics = nil
                verifiedMetadata = nil
                cachedLyricLines = []
                senseMeInfo = nil
            }
            
            let url = URL(fileURLWithPath: tr.fullPath)
            
            let details = await Task.detached(priority: .userInitiated) { () -> LoadedTrackDetails? in
                if Task.isCancelled { return nil }
                let art = AudioTagger.shared.extractCoverArt(fileURL: url)
                if Task.isCancelled { return nil }
                let lyr = AudioTagger.shared.extractLyrics(fileURL: url)
                if Task.isCancelled { return nil }
                let val = art != nil ? WalkmanEngine.shared.isBaselineRGBJPEG(data: art!) : nil
                let meta = AudioTagger.shared.readMetadata(fileURL: url)
                if Task.isCancelled { return nil }
                let rawLyrics = lyr ?? meta?.lyrics
                let parsedLines = Self.parseLyrics(rawLyrics)
                let senseMe = SenseMeEngine.shared.inspect(fileURL: url)
                if Task.isCancelled { return nil }
                if senseMe.isAnalyzed && !tr.isSenseMeAnalyzed {
                    LibraryScanner.shared.updateCachedSenseMe(fullPath: tr.fullPath, info: senseMe)
                }
                return LoadedTrackDetails(
                    art: art,
                    validation: val,
                    rawLyrics: rawLyrics,
                    parsedLines: parsedLines,
                    meta: meta,
                    senseMe: senseMe
                )
            }.value
            
            guard !Task.isCancelled, self.currentTrackId == tr.id, let details = details else { return }
            self.coverData = details.art
            if let art = details.art, let loadedImg = NSImage(data: art) {
                self.coverImage = loadedImg
            } else if self.coverImage == nil {
                self.coverImage = CoverArtCache.shared.thumbnail(for: tr)
            }
            self.validationStatus = details.validation
            self.lyrics = details.rawLyrics
            self.verifiedMetadata = details.meta
            self.cachedLyricLines = details.parsedLines
            self.senseMeInfo = details.senseMe
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
                    // 1. HERO HEADER: Track Title & Badges
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3.5) {
                            Text(displayTitle)
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            
                            Text(displayArtist)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                                .textSelection(.enabled)
                            
                            Text("\(displayAlbum)\(displayYear.isEmpty ? "" : " (\(displayYear))")")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
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
                        }
                    }
                    
                    // 2. ALBUM ARTWORK CARD (View Only with Export)
                    VStack(spacing: 8) {
                        if let img = coverImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: .white.opacity(0.24), location: 0.0),
                                                    .init(color: .white.opacity(0.08), location: 0.5),
                                                    .init(color: .white.opacity(0.02), location: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.85
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.38), radius: 12, x: 0, y: 6)
                                .frame(maxWidth: .infinity)
                                .contextMenu {
                                    Button(action: exportArtworkToMac) {
                                        Label("Export Cover Art to Mac...", systemImage: "square.and.arrow.down")
                                    }
                                    Button(action: revealInFinder) {
                                        Label("Reveal Audio File in Finder", systemImage: "folder")
                                    }
                                }
                            
                            // Artwork Compliance Status
                            HStack(alignment: .center, spacing: 4.5) {
                                if let st = validationStatus {
                                    Image(systemName: st.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(st.valid ? Color.green : Color.orange)
                                    Text(artworkStatusShortLabel(st))
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(st.valid ? Color.secondary : Color.orange)
                                        .lineLimit(1)
                                        .help(st.message)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 10))
                                        .foregroundStyle(WalkmanTheme.silverMuted)
                                    Text("Embedded Cover Art")
                                        .font(WalkmanFont.monoSmall)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 2)
                        } else {
                            // Non-editable Minimal Artwork Placeholder
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.85)
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
                                        .foregroundStyle(Color.secondary)
                                    Text("Walkman shows default disc animation")
                                        .font(WalkmanFont.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    
                    // 3. LYRICS CONTAINER
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "Lyrics", icon: "quote.bubble.fill")
                        
                        if hasLyricsOnWalkman {
                            // Isolated Live Lyrics Reader with Throttled Auto-Scrolling
                            LiveLyricsReader(
                                lines: cachedLyricLines,
                                trackId: tr.id,
                                isHiRes: isHiRes,
                                onCopy: copyLyricsToClipboard
                            )
                        } else {
                            // Empty state indicating no lyrics inside the Lyrics container
                            HStack(spacing: 8) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                                Text("No lyrics found on device")
                                    .font(WalkmanFont.monoSmall)
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .liquidGlass(cornerRadius: 10)
                            .contextMenu {
                                if let onEdit = onEdit {
                                    Button(action: onEdit) {
                                        Label("Edit Metadata & Fetch Lyrics...", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }

                    // 4. SONY 12 TONE / SENSEME (Simple Status Only)
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "Sony 12 Tone / SenseMe", icon: "waveform.path.ecg")

                        HStack(spacing: 10) {
                            let isAnalyzed = (senseMeInfo?.isAnalyzed == true) || tr.isSenseMeAnalyzed

                            ZStack {
                                Circle()
                                    .fill(isAnalyzed ? Color(red: 255/255, green: 145/255, blue: 0/255).opacity(0.18) : Color.white.opacity(0.04))
                                    .frame(width: 28, height: 28)
                                Image(systemName: isAnalyzed ? "checkmark.circle.fill" : "circle.dashed")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isAnalyzed ? Color(red: 255/255, green: 185/255, blue: 50/255) : Color.white.opacity(0.3))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(isAnalyzed ? "SenseMe Analyzed" : "Not Analyzed")
                                    .font(WalkmanFont.bodyBold)
                                    .foregroundStyle(isAnalyzed ? Color.white : Color.secondary)
                                    .lineLimit(1)
                                Text(isAnalyzed ? "12 Tone acoustic metadata is embedded in file" : "No 12 Tone metadata embedded in file")
                                    .font(WalkmanFont.subheadline)
                                    .foregroundStyle(isAnalyzed ? WalkmanTheme.silverMuted : Color.white.opacity(0.35))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(cornerRadius: 12)
                    }

                    // 5. TAGS & METADATA
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "Tags & Metadata", icon: "tag.fill")
                        
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .liquidGlass(cornerRadius: 12)
                        .contextMenu {
                            if let editAction = onEdit {
                                Button(action: editAction) {
                                    Label("Edit Metadata in Studio...", systemImage: "pencil")
                                }
                            }
                        }
                    }

                    // 6. AUDIO SPECIFICATIONS
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "Audio Specifications", icon: "waveform")
                        
                        VStack(spacing: 0) {
                            AudioSpecRow(label: "Format", value: tr.format, systemImage: "doc.fill")
                            Divider().overlay(Color.white.opacity(0.06))
                            let sampleRateStr = formatSampleRate(tr.sampleRate)
                            AudioSpecRow(label: "Sample Rate", value: sampleRateStr.isEmpty ? "Standard" : sampleRateStr, systemImage: "waveform.badge.magnifyingglass")
                            Divider().overlay(Color.white.opacity(0.06))
                            let bitsStr = tr.bitsPerSample > 0 ? "\(tr.bitsPerSample)-bit" : "16-bit Standard"
                            AudioSpecRow(label: "Bit Depth", value: bitsStr, systemImage: "slider.horizontal.3")
                            Divider().overlay(Color.white.opacity(0.06))
                            AudioSpecRow(
                                label: "Hardware Tags",
                                value: tr.format == "MP3" ? "Strict ID3v2.3 (UTF-16)" : (tr.format == "FLAC" ? "Vorbis Comments (SMFM Block 2)" : "MP4 iTunes Metadata"),
                                systemImage: "cpu"
                            )
                            Divider().overlay(Color.white.opacity(0.06))
                            let isMicroSD = tr.fullPath.lowercased().contains("microsd") || tr.fullPath.lowercased().contains("sd_card") || tr.fullPath.lowercased().contains("sdcard")
                            AudioSpecRow(
                                label: "Storage",
                                value: isMicroSD ? "MicroSD Card" : "Internal Memory",
                                systemImage: isMicroSD ? "sdcard.fill" : "internaldrive.fill"
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .liquidGlass(cornerRadius: 12)
                    }

                    // 7. QUICK STATS 2x2 GRID (under Audio Properties)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        StatTile(
                            icon: "clock",
                            label: "Duration",
                            value: formatDuration(tr.durationSeconds)
                        )
                        StatTile(
                            icon: "speedometer",
                            label: "Bitrate",
                            value: tr.bitrateKbps > 0 ? "\(tr.bitrateKbps) kbps" : "Lossless"
                        )
                        StatTile(
                            icon: "waveform",
                            label: "Quality",
                            value: formatQuality(tr),
                            highlight: isHiRes
                        )
                        StatTile(
                            icon: "internaldrive",
                            label: "File Size",
                            value: formatSize(tr.sizeBytes)
                        )
                    }
                    
                    // 8. FILE LOCATION
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            sectionHeader(title: "File Location", icon: "folder.fill")
                            Spacer()
                            Button(action: copyPathToClipboard) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                            .buttonStyle(.plain)
                            .help("Copy File Path")

                            Button(action: revealInFinder) {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WalkmanTheme.silverMuted)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal Audio File in Finder")
                        }
                        
                        // Exact File Location Container
                        let exactPath = tr.fullPath.isEmpty ? (tr.relativePath.isEmpty ? tr.filename : tr.relativePath) : tr.fullPath
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exactPath)
                                .font(WalkmanFont.monoSmall)
                                .foregroundStyle(Color.white.opacity(0.88))
                                .lineSpacing(2.5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .liquidGlass(cornerRadius: 12)
                        .contextMenu {
                            Button(action: revealInFinder) {
                                Label("Reveal Audio File in Finder", systemImage: "folder")
                            }
                            Button(action: copyPathToClipboard) {
                                Label("Copy File Path", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    .padding(.bottom, 8)

                } else {
                    // Empty State
                    VStack(spacing: 14) {
                        Spacer(minLength: 20)
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            Image(systemName: "sidebar.trailing")
                                .font(.system(size: 26))
                                .foregroundStyle(WalkmanTheme.silverMuted)
                        }
                        Text("Track Details")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Select a song from the library to inspect its audio properties, hardware tags, cover artwork, and lyrics.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            .padding(.bottom, 24)
        }
        .metadataScrollContentMargins()
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: WalkmanTheme.background, location: 0.0),
                    .init(color: WalkmanTheme.background, location: 0.65),
                    .init(color: WalkmanTheme.background.opacity(0.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
        }
        .task(id: track?.id) {
            await loadTrackData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackMetadataDidUpdate)) { notif in
            if let updatedId = notif.userInfo?["trackId"] as? String {
                if updatedId == track?.id {
                    Task { @MainActor in
                        await loadTrackData(force: true)
                    }
                }
            } else {
                Task { @MainActor in
                    await loadTrackData(force: true)
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var highlight: Bool = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(highlight ? WalkmanTheme.hiResGold : WalkmanTheme.silverMuted)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(highlight ? WalkmanTheme.hiResGoldLight.opacity(0.9) : Color.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(highlight ? WalkmanTheme.hiResGoldLight : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(
            ZStack {
                if highlight {
                    Color.white.opacity(0.06)
                    WalkmanTheme.hiResGold.opacity(0.06)
                } else {
                    Color.white.opacity(isHovered ? 0.07 : 0.035)
                }
                
                // Top specular gloss
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(highlight ? 0.25 : 0.12), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    Spacer(minLength: 0)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: (highlight ? WalkmanTheme.hiResGold : Color.white).opacity(isHovered ? 0.45 : 0.20), location: 0.0),
                            .init(color: Color.white.opacity(isHovered ? 0.18 : 0.08), location: 0.5),
                            .init(color: Color.white.opacity(0.02), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
        )
        .shadow(
            color: Color.black.opacity(isHovered ? 0.22 : 0.10),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: 1
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct ReadOnlyDetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.secondary)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            if value.isEmpty {
                Text("—")
                    .font(isMonospace ? WalkmanFont.monoSmall : .system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
            } else {
                Text(value)
                    .font(isMonospace ? WalkmanFont.monoSmall : .system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
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
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            if isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isSuccess ? WalkmanTheme.silverLight : Color.white)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.vertical, 3.5)
    }
}


// MARK: - Isolated Live Components

private struct LiveLyricsReader: View {
    let lines: [MetadataStudioView.ParsedLyricLine]
    let trackId: String
    let isHiRes: Bool
    let onCopy: () -> Void
    
    @ObservedObject private var progress = AudioPlayerService.shared.progress
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var activeLineId: Int? = nil
    
    /// Lead time (0.3s / 300ms) to ensure lyric highlighting anticipates vocal onset with zero lag.
    private let lyricLeadTimeSeconds: Double = 0.3
    
    private func updateActiveLine(proxy: ScrollViewProxy) {
        let isPlayingThis = (player.currentTrack?.id == trackId && player.isPlaying)
        guard isPlayingThis else {
            if activeLineId != nil {
                activeLineId = nil
            }
            return
        }
        
        let now = progress.currentTime + lyricLeadTimeSeconds
        var newId: Int? = nil
        for line in lines {
            guard let t = line.timeInSeconds else { continue }
            if now >= t {
                newId = line.id
            } else {
                break
            }
        }
        
        if newId != activeLineId {
            activeLineId = newId
            if let targetId = newId {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(targetId, anchor: .center)
                }
            }
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.id) { line in
                        let active = (activeLineId == line.id)
                        lyricRow(line: line, active: active)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 280)
            .liquidGlass(cornerRadius: 10)
            .contextMenu {
                Button(action: onCopy) {
                    Label("Copy Lyrics to Clipboard", systemImage: "doc.on.doc")
                }
            }
            .onAppear {
                updateActiveLine(proxy: proxy)
            }
            .onChange(of: progress.currentTime) {
                updateActiveLine(proxy: proxy)
            }
            .onChange(of: player.isPlaying) {
                updateActiveLine(proxy: proxy)
            }
            .onChange(of: trackId) {
                activeLineId = nil
                updateActiveLine(proxy: proxy)
            }
        }
    }
    
    @ViewBuilder
    private func lyricRow(line: MetadataStudioView.ParsedLyricLine, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let formatted = line.formattedTimestamp {
                Text(formatted)
                    .font(.system(size: 10, weight: active ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(active ? WalkmanTheme.hiResGold : Color.white.opacity(0.35))
                    .frame(width: 38, alignment: .leading)
                    .lineLimit(1)
            }
            
            Text(line.text.isEmpty ? "• • •" : line.text)
                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                .foregroundStyle(
                    active ? (isHiRes ? WalkmanTheme.hiResGoldLight : Color.white) :
                    (line.text.isEmpty ? Color.secondary.opacity(0.5) : Color.white.opacity(0.68))
                )
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            active ?
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WalkmanTheme.hiResGold.opacity(0.25), lineWidth: 0.8)
                ) : nil
        )
    }
}

private extension View {
    @ViewBuilder
    func metadataScrollContentMargins() -> some View {
        if #available(macOS 14.0, *) {
            self.contentMargins(.top, 0, for: .scrollContent)
        } else {
            self
        }
    }
}
