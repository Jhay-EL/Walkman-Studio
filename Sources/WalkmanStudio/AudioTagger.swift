import Foundation
import AppKit
import CoreGraphics
import ImageIO
import AVFoundation

public final class AudioTagger: @unchecked Sendable {
    public static let shared = AudioTagger()
    private init() {}

    // -----------------------------------------------------------------------
    // Unified Hardware Metadata Writer (FLAC Vorbis & MP3 ID3v2.3)
    // -----------------------------------------------------------------------
    public func writeMetadata(
        fileURL: URL,
        title: String?,
        artist: String?,
        album: String?,
        trackNumber: String?,
        year: String?,
        genre: String?,
        coverArtData: Data?,
        lyrics: String? = nil
    ) throws {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "flac" {
            try writeFLACMetadata(
                fileURL: fileURL,
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                year: year,
                genre: genre,
                coverArtData: coverArtData,
                lyrics: lyrics
            )
        } else if ext == "mp3" {
            try writeMP3Metadata(
                fileURL: fileURL,
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                year: year,
                genre: genre,
                coverArtData: coverArtData,
                lyrics: lyrics
            )
        } else if ext == "m4a" || ext == "m4b" || ext == "alac" || ext == "aac" || ext == "mp4" {
            try writeM4AMetadata(
                fileURL: fileURL,
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                year: year,
                genre: genre,
                coverArtData: coverArtData,
                lyrics: lyrics
            )
        } else {
            throw NSError(domain: "WalkmanStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format for metadata tagging: .\(ext)"])
        }

        // Clean macOS metadata shadow file and xattrs
        let cPath = (fileURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        let dotfileURL = fileURL.deletingLastPathComponent().appendingPathComponent("._" + fileURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint 3: Native FLAC Vorbis Comments & Baseline JPEG Cover Art
    // -----------------------------------------------------------------------
    public func writeFLACMetadata(
        fileURL: URL,
        title: String?,
        artist: String?,
        album: String?,
        trackNumber: String?,
        year: String?,
        genre: String?,
        coverArtData: Data?,
        lyrics: String? = nil
    ) throws {
        // Snapshot existing file timestamps to preserve original "Date Added"
        let origAttr = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let origCreation = origAttr?[.creationDate] as? Date
        let origMod = origAttr?[.modificationDate] as? Date

        let fileData = try Data(contentsOf: fileURL)
        guard fileData.count >= 4 && fileData.starts(with: [0x66, 0x4C, 0x61, 0x43]) else {
            throw NSError(domain: "WalkmanStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a valid FLAC audio file"])
        }

        var offset = 4
        var isLast = false

        var streamInfoBlock: Data? = nil
        var otherBlocks: [(type: Int, data: Data)] = []
        var existingComments: [String: String] = [:]
        var existingOtherComments: [(key: String, val: String)] = []
        var vendorString = "reference libFLAC 1.4.3 20230623"
        var existingPictureBlock: Data? = nil

        while !isLast && offset + 4 <= fileData.count {
            let b0 = fileData[offset]
            isLast = (b0 & 0x80) != 0
            let bType = Int(b0 & 0x7F)
            let bLen = (Int(fileData[offset+1]) << 16) | (Int(fileData[offset+2]) << 8) | Int(fileData[offset+3])
            offset += 4
            guard offset + bLen <= fileData.count else {
                throw NSError(domain: "WalkmanStudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Corrupted FLAC metadata block"])
            }
            let bData = fileData.subdata(in: offset..<offset+bLen)
            offset += bLen

            if bType == 0 { // STREAMINFO
                streamInfoBlock = bData
            } else if bType == 4 { // VORBIS_COMMENT
                var pos = 0
                if pos + 4 <= bData.count {
                    let vLen = Int(bData[pos]) | (Int(bData[pos+1]) << 8) | (Int(bData[pos+2]) << 16) | (Int(bData[pos+3]) << 24)
                    pos += 4
                    if pos + vLen <= bData.count, let vStr = String(data: bData.subdata(in: pos..<pos+vLen), encoding: .utf8) {
                        vendorString = vStr
                    }
                    pos += vLen
                    if pos + 4 <= bData.count {
                        let commentCount = Int(bData[pos]) | (Int(bData[pos+1]) << 8) | (Int(bData[pos+2]) << 16) | (Int(bData[pos+3]) << 24)
                        pos += 4
                        for _ in 0..<commentCount {
                            guard pos + 4 <= bData.count else { break }
                            let cLen = Int(bData[pos]) | (Int(bData[pos+1]) << 8) | (Int(bData[pos+2]) << 16) | (Int(bData[pos+3]) << 24)
                            pos += 4
                            guard pos + cLen <= bData.count else { break }
                            if let cStr = String(data: bData.subdata(in: pos..<pos+cLen), encoding: .utf8) {
                                let parts = cStr.components(separatedBy: "=")
                                if parts.count >= 2 {
                                    let k = parts[0].uppercased()
                                    let v = parts[1...].joined(separator: "=")
                                    let standardKeys: Set<String> = ["TITLE", "ARTIST", "ALBUM", "TRACKNUMBER", "TRACK", "DATE", "YEAR", "GENRE", "LYRICS", "UNSYNCEDLYRICS"]
                                    if standardKeys.contains(k) {
                                        existingComments[k] = v
                                    } else {
                                        existingOtherComments.append((parts[0], v))
                                    }
                                }
                            }
                            pos += cLen
                        }
                    }
                }
            } else if bType == 6 { // PICTURE
                if existingPictureBlock == nil {
                    existingPictureBlock = bData
                }
            } else if bType == 1 { // PADDING
                // Skip old padding, fresh padding is added at the end
            } else {
                otherBlocks.append((bType, bData))
            }
        }

        guard let streamInfo = streamInfoBlock else {
            throw NSError(domain: "WalkmanStudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "FLAC missing STREAMINFO block"])
        }

        let audioFrames = fileData.subdata(in: offset..<fileData.count)

        // Construct updated Vorbis Comments
        var newComments: [(String, String)] = []

        let rawCleanTitle = title.map { WalkmanEngine.sanitizeWalkmanText($0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTitleValid = rawCleanTitle != nil && !rawCleanTitle!.isEmpty && rawCleanTitle!.lowercased() != "unknown" && rawCleanTitle!.lowercased() != "unknown track" && rawCleanTitle!.lowercased() != "unknown title"
        let finTitle = isTitleValid ? rawCleanTitle : (existingComments["TITLE"].map { WalkmanEngine.sanitizeWalkmanText($0) })
        if let t = finTitle, !t.isEmpty, t.lowercased() != "unknown" { newComments.append(("TITLE", t)) }

        let rawCleanArtist = artist.map { WalkmanEngine.sanitizeWalkmanText($0, stripExplicitMarkers: false) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingArtist = existingComments["ARTIST"] ?? existingComments["ALBUMARTIST"] ?? existingComments["ALBUM_ARTIST"]
        let isArtistValid = rawCleanArtist != nil && !rawCleanArtist!.isEmpty && rawCleanArtist!.lowercased() != "unknown artist" && rawCleanArtist!.lowercased() != "unknown"
        let finArtist = isArtistValid ? rawCleanArtist : (existingArtist.map { WalkmanEngine.sanitizeWalkmanText($0, stripExplicitMarkers: false) })
        if let a = finArtist, !a.isEmpty { newComments.append(("ARTIST", a)) }

        let rawCleanAlbum = album.map { WalkmanEngine.sanitizeWalkmanText($0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAlbumValid = rawCleanAlbum != nil && !rawCleanAlbum!.isEmpty && rawCleanAlbum!.lowercased() != "unknown album" && rawCleanAlbum!.lowercased() != "unknown"
        let finAlbum = isAlbumValid ? rawCleanAlbum : (existingComments["ALBUM"].map { WalkmanEngine.sanitizeWalkmanText($0) })
        if let al = finAlbum, !al.isEmpty { newComments.append(("ALBUM", al)) }

        let cleanTrack = trackNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finTrack = (cleanTrack != nil && !cleanTrack!.isEmpty) ? cleanTrack : (existingComments["TRACKNUMBER"] ?? existingComments["TRACK"])
        if let tr = finTrack, !tr.isEmpty { newComments.append(("TRACKNUMBER", tr)) }

        let cleanYear = year?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finYear: String? = (cleanYear != nil && !cleanYear!.isEmpty) ? cleanYear : (existingComments["DATE"] ?? existingComments["YEAR"])
        if let y = finYear, !y.isEmpty {
            newComments.append(("DATE", y))
            newComments.append(("YEAR", y))
        }

        let cleanGenre = genre?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finGenre: String? = (cleanGenre != nil && !cleanGenre!.isEmpty) ? cleanGenre : existingComments["GENRE"]
        if let g = finGenre, !g.isEmpty {
            newComments.append(("GENRE", g))
        }

        let cleanLyrics = lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finLyrics = (cleanLyrics != nil && !cleanLyrics!.isEmpty) ? cleanLyrics : (existingComments["LYRICS"] ?? existingComments["UNSYNCEDLYRICS"])
        if let lyr = finLyrics, !lyr.isEmpty {
            newComments.append(("LYRICS", lyr))
        }

        for (k, v) in existingOtherComments {
            let cleanVal = WalkmanEngine.sanitizeWalkmanText(v, stripExplicitMarkers: false)
            if !cleanVal.isEmpty {
                newComments.append((k, cleanVal))
            }
        }

        var vorbisData = Data()
        let vendorData = vendorString.data(using: .utf8) ?? Data("WalkmanStudio".utf8)
        let vLen = UInt32(vendorData.count)
        vorbisData.append(contentsOf: [
            UInt8(vLen & 0xFF), UInt8((vLen >> 8) & 0xFF), UInt8((vLen >> 16) & 0xFF), UInt8((vLen >> 24) & 0xFF)
        ])
        vorbisData.append(vendorData)

        let cCount = UInt32(newComments.count)
        vorbisData.append(contentsOf: [
            UInt8(cCount & 0xFF), UInt8((cCount >> 8) & 0xFF), UInt8((cCount >> 16) & 0xFF), UInt8((cCount >> 24) & 0xFF)
        ])

        for (k, v) in newComments {
            let entry = "\(k)=\(v)"
            let entryData = entry.data(using: .utf8) ?? Data()
            let eLen = UInt32(entryData.count)
            vorbisData.append(contentsOf: [
                UInt8(eLen & 0xFF), UInt8((eLen >> 8) & 0xFF), UInt8((eLen >> 16) & 0xFF), UInt8((eLen >> 24) & 0xFF)
            ])
            vorbisData.append(entryData)
        }

        // Construct updated Picture block
        var pictureBlockData: Data? = nil
        if let rawArt = coverArtData {
            if let baselineJPEG = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: rawArt) {
                var pic = Data()
                // Picture type: 3 = Front cover (4 bytes BE)
                pic.append(contentsOf: [0x00, 0x00, 0x00, 0x03])
                // MIME: "image/jpeg"
                let mime = "image/jpeg".data(using: .ascii)!
                let mimeLen = UInt32(mime.count)
                pic.append(contentsOf: [
                    UInt8((mimeLen >> 24) & 0xFF), UInt8((mimeLen >> 16) & 0xFF), UInt8((mimeLen >> 8) & 0xFF), UInt8(mimeLen & 0xFF)
                ])
                pic.append(mime)
                // Description: empty (0 length)
                pic.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
                // Width & Height
                var w: UInt32 = 800
                var h: UInt32 = 800
                if let src = CGImageSourceCreateWithData(baselineJPEG as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                    w = UInt32(props[kCGImagePropertyPixelWidth] as? Int ?? 800)
                    h = UInt32(props[kCGImagePropertyPixelHeight] as? Int ?? 800)
                }
                pic.append(contentsOf: [
                    UInt8((w >> 24) & 0xFF), UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF),
                    UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF), UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF)
                ])
                // Color depth: 24, colors: 0
                pic.append(contentsOf: [0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00])
                // Image data length
                let dataLen = UInt32(baselineJPEG.count)
                pic.append(contentsOf: [
                    UInt8((dataLen >> 24) & 0xFF), UInt8((dataLen >> 16) & 0xFF), UInt8((dataLen >> 8) & 0xFF), UInt8(dataLen & 0xFF)
                ])
                pic.append(baselineJPEG)
                pictureBlockData = pic
            }
        } else if let existingPic = existingPictureBlock {
            pictureBlockData = existingPic
        }

        // Assemble all blocks in canonical order
        var allBlocks: [(type: Int, data: Data)] = []
        allBlocks.append((0, streamInfo))
        for ob in otherBlocks {
            allBlocks.append(ob)
        }
        allBlocks.append((4, vorbisData))
        if let pic = pictureBlockData {
            allBlocks.append((6, pic))
        }
        // 4KB Padding
        allBlocks.append((1, Data(repeating: 0, count: 4096)))

        var output = Data([0x66, 0x4C, 0x61, 0x43])
        for (idx, block) in allBlocks.enumerated() {
            let isBlockLast = (idx == allBlocks.count - 1)
            let typeByte = UInt8((isBlockLast ? 0x80 : 0x00) | (block.type & 0x7F))
            let len = block.data.count
            output.append(typeByte)
            output.append(UInt8((len >> 16) & 0xFF))
            output.append(UInt8((len >> 8) & 0xFF))
            output.append(UInt8(len & 0xFF))
            output.append(block.data)
        }
        output.append(audioFrames)

        do {
            try output.write(to: fileURL, options: .atomic)
        } catch {
            try output.write(to: fileURL, options: [])
        }

        // Restore original timestamps so tag/artwork edits never reset Date Added
        AudioTagger.restoreTimestamps(fileURL: fileURL, creationDate: origCreation, modificationDate: origMod)
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint 2: Strict ID3v2.3 UTF-16 MP3 Tagging
    // -----------------------------------------------------------------------
    public func writeMP3Metadata(
        fileURL: URL,
        title: String?,
        artist: String?,
        album: String?,
        trackNumber: String?,
        year: String?,
        genre: String?,
        coverArtData: Data?,
        lyrics: String? = nil
    ) throws {
        // Snapshot existing file timestamps to preserve original "Date Added"
        let origAttr = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let origCreation = origAttr?[.creationDate] as? Date
        let origMod = origAttr?[.modificationDate] as? Date

        let fileData = try Data(contentsOf: fileURL)

        // 1. Locate audio stream offset (skip existing ID3v2 tag if present)
        var audioOffset = 0
        if fileData.count >= 10 && fileData.starts(with: [0x49, 0x44, 0x33]) { // "ID3"
            let b6 = Int(fileData[6])
            let b7 = Int(fileData[7])
            let b8 = Int(fileData[8])
            let b9 = Int(fileData[9])
            let tagSize = (b6 << 21) | (b7 << 14) | (b8 << 7) | b9
            audioOffset = 10 + tagSize
        }

        let audioStream = fileData.subdata(in: audioOffset..<fileData.count)

        // Extract existing GEOB, PRIV, and USLT frames to preserve
        var preservedFrames: [Data] = []
        if audioOffset > 10 && fileData.count >= 10 && fileData.starts(with: [0x49, 0x44, 0x33]) {
            let version = fileData[3]
            let flags = fileData[5]
            var offset = 10
            let tagLimit = min(audioOffset, fileData.count)

            // Skip extended header if present
            if (flags & 0x40) != 0 && offset + 4 <= tagLimit {
                if version == 4 {
                    let extSize = (Int(fileData[offset]) << 21) | (Int(fileData[offset+1]) << 14) | (Int(fileData[offset+2]) << 7) | Int(fileData[offset+3])
                    offset += max(4, extSize)
                } else if version == 3 {
                    let extSize = (Int(fileData[offset]) << 24) | (Int(fileData[offset+1]) << 16) | (Int(fileData[offset+2]) << 8) | Int(fileData[offset+3])
                    offset += max(4, extSize + 4)
                }
            }

            if version == 3 || version == 4 {
                while offset + 10 <= tagLimit {
                    let idData = fileData.subdata(in: offset..<offset+4)
                    guard idData[0] != 0, let frameID = String(data: idData, encoding: .ascii),
                          frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                        break
                    }
                    let fSize: Int
                    if version == 4 {
                        fSize = (Int(fileData[offset+4]) << 21) | (Int(fileData[offset+5]) << 14) | (Int(fileData[offset+6]) << 7) | Int(fileData[offset+7])
                    } else {
                        fSize = (Int(fileData[offset+4]) << 24) | (Int(fileData[offset+5]) << 16) | (Int(fileData[offset+6]) << 8) | Int(fileData[offset+7])
                    }
                    offset += 10
                    guard offset + fSize <= tagLimit else { break }
                    let frameContent = fileData.subdata(in: offset..<offset+fSize)
                    offset += fSize

                    if frameID == "GEOB" || frameID == "PRIV" {
                        var rawFrame = Data()
                        rawFrame.append(idData)
                        let uSize = UInt32(fSize)
                        rawFrame.append(contentsOf: [
                            UInt8((uSize >> 24) & 0xFF), UInt8((uSize >> 16) & 0xFF), UInt8((uSize >> 8) & 0xFF), UInt8(uSize & 0xFF)
                        ])
                        rawFrame.append(contentsOf: [0x00, 0x00])
                        rawFrame.append(frameContent)
                        preservedFrames.append(rawFrame)
                    } else if (frameID == "USLT" || frameID == "SYLT") && (lyrics == nil || lyrics!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        var rawFrame = Data()
                        rawFrame.append("USLT".data(using: .ascii)!)
                        let uSize = UInt32(fSize)
                        rawFrame.append(contentsOf: [
                            UInt8((uSize >> 24) & 0xFF), UInt8((uSize >> 16) & 0xFF), UInt8((uSize >> 8) & 0xFF), UInt8(uSize & 0xFF)
                        ])
                        rawFrame.append(contentsOf: [0x00, 0x00])
                        rawFrame.append(frameContent)
                        preservedFrames.append(rawFrame)
                    }
                }
            }
        }

        // 2. Read existing tags to prevent wiping out data if nil/empty passed
        let existingMeta = readMP3Metadata(fileURL: fileURL)
        let rawCleanTitle = title.map { WalkmanEngine.sanitizeWalkmanText($0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTitleValid = rawCleanTitle != nil && !rawCleanTitle!.isEmpty && rawCleanTitle!.lowercased() != "unknown" && rawCleanTitle!.lowercased() != "unknown track" && rawCleanTitle!.lowercased() != "unknown title"
        let finTitle = isTitleValid ? rawCleanTitle : existingMeta.map { WalkmanEngine.sanitizeWalkmanText($0.title) }

        let rawCleanArtist = artist.map { WalkmanEngine.sanitizeWalkmanText($0, stripExplicitMarkers: false) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isArtistValid = rawCleanArtist != nil && !rawCleanArtist!.isEmpty && rawCleanArtist!.lowercased() != "unknown artist" && rawCleanArtist!.lowercased() != "unknown"
        let finArtist = isArtistValid ? rawCleanArtist : existingMeta.map { WalkmanEngine.sanitizeWalkmanText($0.artist, stripExplicitMarkers: false) }

        let rawCleanAlbum = album.map { WalkmanEngine.sanitizeWalkmanText($0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAlbumValid = rawCleanAlbum != nil && !rawCleanAlbum!.isEmpty && rawCleanAlbum!.lowercased() != "unknown album" && rawCleanAlbum!.lowercased() != "unknown"
        let finAlbum = isAlbumValid ? rawCleanAlbum : existingMeta.map { WalkmanEngine.sanitizeWalkmanText($0.album) }

        let cleanTrack = trackNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finTrack = (cleanTrack != nil && !cleanTrack!.isEmpty) ? cleanTrack : existingMeta?.trackNumber

        let cleanYear = year?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finYear = (cleanYear != nil && !cleanYear!.isEmpty) ? cleanYear : existingMeta?.year

        let cleanGenre = genre?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finGenre = (cleanGenre != nil && !cleanGenre!.isEmpty) ? cleanGenre : existingMeta?.genre

        // 3. Build ID3v2.3 frames (UTF-16 encoding = 1)
        var framesData = Data()

        if let t = finTitle, !t.isEmpty, t.lowercased() != "unknown" {
            framesData.append(makeID3v23TextFrame(id: "TIT2", text: t))
        }
        if let a = finArtist, !a.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TPE1", text: a))
        }
        if let al = finAlbum, !al.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TALB", text: al))
        }
        if let tr = finTrack, !tr.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TRCK", text: tr))
        }
        if let y = finYear, !y.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TYER", text: y))
            framesData.append(makeID3v23TextFrame(id: "TDRC", text: y))
        }
        if let g = finGenre, !g.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TCON", text: g))
        }

        // Add USLT (Lyrics) frame if provided
        if let l = lyrics, !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            framesData.append(makeID3v23UsltFrame(lyrics: l))
        }

        // Add preserved frames (GEOB, PRIV, prior USLT)
        for pFrame in preservedFrames {
            framesData.append(pFrame)
        }

        // 4. Embed Baseline RGB JPEG APIC frame
        var effectiveArtData = coverArtData
        if effectiveArtData == nil {
            effectiveArtData = extractCoverArt(fileURL: fileURL)
        }
        if let rawArt = effectiveArtData, let baselineJPEG = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: rawArt) {
            framesData.append(makeID3v23ApicFrame(imageData: baselineJPEG))
        }

        // 4. Construct ID3v2.3 10-byte header
        var header = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) // ID3v2.3, no flags
        let synchsafe = AudioTagger.synchsafeBytes(framesData.count)
        header.append(contentsOf: synchsafe)

        // 5. Assemble complete file
        var output = Data()
        output.append(header)
        output.append(framesData)
        output.append(audioStream)

        do {
            try output.write(to: fileURL, options: .atomic)
        } catch {
            try output.write(to: fileURL, options: [])
        }

        // Restore original timestamps so tag/artwork edits never reset Date Added
        AudioTagger.restoreTimestamps(fileURL: fileURL, creationDate: origCreation, modificationDate: origMod)
    }

    private func makeID3v23TextFrame(id: String, text: String) -> Data {
        let cleanText = WalkmanEngine.sanitizeWalkmanText(text, stripExplicitMarkers: false)
        var frame = Data()
        frame.append(id.data(using: .ascii)!)

        var content = Data([0x01]) // 1 = UTF-16 with BOM
        content.append(contentsOf: [0xFF, 0xFE]) // UTF-16LE BOM
        content.append(cleanText.data(using: .utf16LittleEndian)!)

        let size = UInt32(content.count)
        frame.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])
        frame.append(contentsOf: [0x00, 0x00]) // Flags
        frame.append(content)
        return frame
    }

    private func makeID3v23UsltFrame(lyrics: String) -> Data {
        let cleanLyrics = WalkmanEngine.sanitizeWalkmanText(lyrics, stripExplicitMarkers: false)
        var frame = Data()
        frame.append("USLT".data(using: .ascii)!)

        var content = Data()
        content.append(0x01) // 1 = UTF-16 with BOM
        content.append(contentsOf: [UInt8]("eng".utf8))
        // Content descriptor: empty UTF-16 with BOM + terminator
        content.append(contentsOf: [0xFF, 0xFE, 0x00, 0x00])
        // Lyrics text in UTF-16LE (BOM already established above)
        if let lData = cleanLyrics.data(using: .utf16LittleEndian) {
            content.append(lData)
        }

        let size = UInt32(content.count)
        frame.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])
        frame.append(contentsOf: [0x00, 0x00]) // Flags
        frame.append(content)
        return frame
    }

    private func makeID3v23ApicFrame(imageData: Data) -> Data {
        var frame = Data()
        frame.append("APIC".data(using: .ascii)!)

        var content = Data()
        content.append(0x00) // 0 = ISO-8859-1 for empty description
        content.append("image/jpeg\0".data(using: .isoLatin1)!) // MIME
        content.append(0x03) // Picture type: 3 = Front cover
        content.append(0x00) // Description: single null terminator
        content.append(imageData)

        let size = UInt32(content.count)
        frame.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])
        frame.append(contentsOf: [0x00, 0x00]) // Flags
        frame.append(content)
        return frame
    }

    public static func synchsafeBytes(_ size: Int) -> [UInt8] {
        return [
            UInt8((size >> 21) & 0x7F),
            UInt8((size >> 14) & 0x7F),
            UInt8((size >> 7) & 0x7F),
            UInt8(size & 0x7F)
        ]
    }

    public static func restoreTimestamps(fileURL: URL, creationDate: Date?, modificationDate: Date?) {
        if let cd = creationDate {
            var attr: [FileAttributeKey: Any] = [.creationDate: cd]
            if let md = modificationDate {
                attr[.modificationDate] = md
            }
            try? FileManager.default.setAttributes(attr, ofItemAtPath: fileURL.path)
        }
        if let md = modificationDate {
            var times = [
                timeval(tv_sec: Int(md.timeIntervalSince1970), tv_usec: 0),
                timeval(tv_sec: Int(md.timeIntervalSince1970), tv_usec: 0)
            ]
            utimes((fileURL.path as NSString).fileSystemRepresentation, &times)
        }
    }

    public func invalidateCaches(fileURL: URL) {
        artCache.removeObject(forKey: fileURL as NSURL)
        lyricsCache.removeObject(forKey: fileURL as NSURL)
    }

    public static let id3v1Genres: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop",
        "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
        "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack",
        "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance",
        "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop",
        "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic",
        "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk",
        "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock", "Folk",
        "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebob", "Latin", "Revival",
        "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock",
        "Symphonic Rock", "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic",
        "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony",
        "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam", "Club", "Tango",
        "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
        "Duet", "Punk Rock", "Drum Solo", "A capella", "Euro-House", "Dance Hall"
    ]

    public static func normalizeGenre(_ genre: String) -> String {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "(255)" || trimmed == "255" || trimmed.lowercased() == "none" {
            return ""
        }
        if trimmed.hasPrefix("(") {
            if let closeParen = trimmed.firstIndex(of: ")") {
                let inside = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeParen])
                let remainder = String(trimmed[trimmed.index(after: closeParen)...]).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty {
                    return remainder
                }
                if let num = Int(inside), num >= 0 && num < id3v1Genres.count {
                    return id3v1Genres[num]
                }
            }
        } else if let num = Int(trimmed), num >= 0 && num < id3v1Genres.count {
            return id3v1Genres[num]
        }
        return trimmed
    }

    public static func extractYearString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.range(of: #"\b(19\d\d|20\d\d)\b"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        let digits = trimmed.filter { $0.isNumber }
        if digits.count >= 4 {
            return String(digits.prefix(4))
        }
        return trimmed
    }

    // -----------------------------------------------------------------------
    // Path & Filename Heuristic Extractor
    // -----------------------------------------------------------------------
    public static func extractFromPath(url: URL) -> (artist: String, album: String, title: String) {
        let stem = url.deletingPathExtension().lastPathComponent
        var title = stem

        if let regex = try? NSRegularExpression(pattern: #"^(\d+[-_])?\d+[\.\s\-_]+(.*)$"#, options: []),
           let match = regex.firstMatch(in: stem, range: NSRange(location: 0, length: stem.utf16.count)) {
            if let r2 = Range(match.range(at: 2), in: stem) {
                let stripped = String(stem[r2]).trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty {
                    title = stripped
                }
            }
        }

        var candidateArtist = ""
        if title.contains(" - ") {
            let parts = title.components(separatedBy: " - ")
            if parts.count >= 2 {
                let p0 = parts[0].trimmingCharacters(in: .whitespaces)
                let p1 = parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                let isP0Unknown = p0.isEmpty || p0.lowercased() == "unknown" || p0.lowercased() == "unknown artist"
                let isP1Unknown = p1.isEmpty || p1.lowercased() == "unknown" || p1.lowercased() == "unknown track" || p1.lowercased() == "unknown title"

                if !isP1Unknown && !isP0Unknown {
                    candidateArtist = p0
                    title = p1
                } else if !isP1Unknown {
                    title = p1
                } else if !isP0Unknown {
                    title = p0
                }
            }
        }

        let pathParts = url.deletingLastPathComponent().pathComponents
        var dirArtist = ""
        var dirAlbum = ""
        let ignored: Set<String> = ["music", "downloads", "desktop", "documents", "media", "media.localized", "volumes", "users", "audio", "tmp"]

        if pathParts.count >= 1 {
            let cand = pathParts[pathParts.count - 1]
            if !ignored.contains(cand.lowercased()) && cand.lowercased() != "unknown" && cand.lowercased() != "unknown album" {
                dirAlbum = cand
            }
        }
        if pathParts.count >= 2 {
            let cand = pathParts[pathParts.count - 2]
            if !ignored.contains(cand.lowercased()) && cand.lowercased() != "unknown" && cand.lowercased() != "unknown artist" {
                dirArtist = cand
            }
        }

        let finalArtist = !candidateArtist.isEmpty ? candidateArtist : dirArtist
        return (
            WalkmanEngine.sanitizeWalkmanText(finalArtist, stripExplicitMarkers: false),
            WalkmanEngine.sanitizeWalkmanText(dirAlbum),
            WalkmanEngine.sanitizeWalkmanText(title)
        )
    }

    // -----------------------------------------------------------------------
    // Hardware Constraint: M4A / AAC / ALAC iTunes MPEG-4 Tagging
    // -----------------------------------------------------------------------
    public func writeM4AMetadata(
        fileURL: URL,
        title: String?,
        artist: String?,
        album: String?,
        trackNumber: String?,
        year: String?,
        genre: String?,
        coverArtData: Data?,
        lyrics: String? = nil
    ) throws {
        let ffmpegPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") ? "/opt/homebrew/bin/ffmpeg" : "/usr/local/bin/ffmpeg"
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw NSError(domain: "AudioTagger", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg binary not found for M4A tagging"])
        }

        let tempOutputDir = fileURL.deletingLastPathComponent()
        let tempOutputFile = tempOutputDir.appendingPathComponent(".tmp_tag_\(UUID().uuidString).m4a")
        var tempCoverURL: URL? = nil

        var args = ["-y", "-i", fileURL.path]

        if let art = coverArtData, !art.isEmpty {
            let coverFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cover_\(UUID().uuidString).jpg")
            try art.write(to: coverFile)
            tempCoverURL = coverFile
            args.append(contentsOf: ["-i", coverFile.path, "-map", "0:a", "-map", "1:v", "-c:a", "copy", "-c:v", "copy", "-disposition:v:0", "attached_pic"])
        } else {
            args.append(contentsOf: ["-map", "0:a", "-c:a", "copy"])
        }

        if let t = title, !t.isEmpty {
            args.append(contentsOf: ["-metadata", "title=\(t)"])
        }
        if let a = artist, !a.isEmpty {
            args.append(contentsOf: ["-metadata", "artist=\(a)", "-metadata", "album_artist=\(a)"])
        }
        if let alb = album, !alb.isEmpty {
            args.append(contentsOf: ["-metadata", "album=\(alb)"])
        }
        if let trk = trackNumber, !trk.isEmpty {
            args.append(contentsOf: ["-metadata", "track=\(trk)"])
        }
        if let y = year, !y.isEmpty {
            args.append(contentsOf: ["-metadata", "date=\(y)"])
        }
        if let g = genre, !g.isEmpty {
            args.append(contentsOf: ["-metadata", "genre=\(g)"])
        }
        if let l = lyrics, !l.isEmpty {
            args.append(contentsOf: ["-metadata", "lyrics=\(l)"])
        }

        args.append(tempOutputFile.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if let cURL = tempCoverURL {
            try? FileManager.default.removeItem(at: cURL)
        }

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: tempOutputFile)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? "Unknown FFmpeg error"
            throw NSError(domain: "AudioTagger", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to write M4A metadata: \(err)"])
        }

        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempOutputFile, to: fileURL)
    }

    // -----------------------------------------------------------------------
    // Universal Multi-Tiered Metadata Reader
    // -----------------------------------------------------------------------
    public func readMetadata(fileURL: URL) -> AudioFileMetadata? {
        let ext = fileURL.pathExtension.lowercased()
        var res: AudioFileMetadata? = nil

        if ext == "flac" {
            res = readFLACMetadata(fileURL: fileURL)
        } else if ext == "mp3" {
            res = readMP3Metadata(fileURL: fileURL)
        }

        var m = res ?? AudioFileMetadata()

        // Tier 2: AVFoundation parser (M4A, ALAC, AAC, WAV, and any missed FLAC/MP3)
        if m.title.isEmpty || m.title.lowercased() == "unknown" || m.artist.isEmpty || m.artist.lowercased() == "unknown artist" || m.album.isEmpty || m.album.lowercased() == "unknown album" || (ext != "flac" && ext != "mp3") {
            if let avMeta = readAVFoundationMetadata(fileURL: fileURL) {
                if (m.title.isEmpty || m.title.lowercased() == "unknown") && !avMeta.title.isEmpty && avMeta.title.lowercased() != "unknown" { m.title = avMeta.title }
                if (m.artist.isEmpty || m.artist.lowercased() == "unknown artist") && !avMeta.artist.isEmpty && avMeta.artist.lowercased() != "unknown artist" { m.artist = avMeta.artist }
                if (m.album.isEmpty || m.album.lowercased() == "unknown album") && !avMeta.album.isEmpty && avMeta.album.lowercased() != "unknown album" { m.album = avMeta.album }
                if m.trackNumber.isEmpty && !avMeta.trackNumber.isEmpty { m.trackNumber = avMeta.trackNumber }
                if m.year.isEmpty && !avMeta.year.isEmpty { m.year = avMeta.year }
                if m.genre.isEmpty && !avMeta.genre.isEmpty { m.genre = avMeta.genre }
                if m.durationSeconds <= 0 { m.durationSeconds = avMeta.durationSeconds }
                if !m.hasArtwork && avMeta.hasArtwork { m.hasArtwork = true }
                if m.lyrics == nil && avMeta.lyrics != nil { m.lyrics = avMeta.lyrics }
            }
        }

        // Tier 3: ffprobe parser (all missed fields including title)
        if m.title.isEmpty || m.title.lowercased() == "unknown" || m.artist.isEmpty || m.artist.lowercased() == "unknown artist" || m.album.isEmpty || m.album.lowercased() == "unknown album" {
            if let ffMeta = readFFprobeMetadata(fileURL: fileURL) {
                if (m.title.isEmpty || m.title.lowercased() == "unknown") && !ffMeta.title.isEmpty && ffMeta.title.lowercased() != "unknown" { m.title = ffMeta.title }
                if (m.artist.isEmpty || m.artist.lowercased() == "unknown artist") && !ffMeta.artist.isEmpty && ffMeta.artist.lowercased() != "unknown artist" { m.artist = ffMeta.artist }
                if (m.album.isEmpty || m.album.lowercased() == "unknown album") && !ffMeta.album.isEmpty && ffMeta.album.lowercased() != "unknown album" { m.album = ffMeta.album }
                if m.trackNumber.isEmpty && !ffMeta.trackNumber.isEmpty { m.trackNumber = ffMeta.trackNumber }
                if m.year.isEmpty && !ffMeta.year.isEmpty { m.year = ffMeta.year }
                if m.genre.isEmpty && !ffMeta.genre.isEmpty { m.genre = ffMeta.genre }
                if m.durationSeconds <= 0 { m.durationSeconds = ffMeta.durationSeconds }
                if m.bitrateKbps <= 0 { m.bitrateKbps = ffMeta.bitrateKbps }
            }
        }

        // Tier 4: Directory & Filename Heuristics
        if m.artist.isEmpty || m.artist.lowercased() == "unknown artist" || m.album.isEmpty || m.album.lowercased() == "unknown album" || m.title.isEmpty || m.title.lowercased() == "unknown" {
            let heur = Self.extractFromPath(url: fileURL)
            if (m.artist.isEmpty || m.artist.lowercased() == "unknown artist") && !heur.artist.isEmpty && heur.artist.lowercased() != "unknown artist" { m.artist = heur.artist }
            if (m.album.isEmpty || m.album.lowercased() == "unknown album") && !heur.album.isEmpty && heur.album.lowercased() != "unknown album" { m.album = heur.album }
            if (m.title.isEmpty || m.title.lowercased() == "unknown") && !heur.title.isEmpty && heur.title.lowercased() != "unknown" { m.title = heur.title }
        }

        m.title = WalkmanEngine.sanitizeWalkmanText(m.title)
        m.artist = WalkmanEngine.sanitizeWalkmanText(m.artist, stripExplicitMarkers: false)
        m.album = WalkmanEngine.sanitizeWalkmanText(m.album)

        return m
    }

    public func readAVFoundationMetadata(fileURL: URL) -> AudioFileMetadata? {
        let asset = AVURLAsset(url: fileURL)
        var res = AudioFileMetadata()

        let sem = DispatchSemaphore(value: 0)
        Task {
            if let duration = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(duration)
                if !sec.isNaN && !sec.isInfinite {
                    res.durationSeconds = sec
                }
            }

            let common = try? await asset.load(.commonMetadata)
            for item in common ?? [] {
                if let k = item.commonKey {
                    switch k {
                    case .commonKeyTitle:
                        res.title = (try? await item.load(.stringValue)) ?? res.title
                    case .commonKeyArtist:
                        res.artist = (try? await item.load(.stringValue)) ?? res.artist
                    case .commonKeyAlbumName:
                        res.album = (try? await item.load(.stringValue)) ?? res.album
                    case .commonKeyArtwork:
                        res.hasArtwork = true
                    case .commonKeyCreationDate:
                        let d = (try? await item.load(.stringValue)) ?? ""
                        if d.count >= 4 && res.year.isEmpty { res.year = String(d.prefix(4)) }
                    case .commonKeyType:
                        res.genre = (try? await item.load(.stringValue)) ?? res.genre
                    default:
                        break
                    }
                }
            }

            if let formats = try? await asset.load(.availableMetadataFormats) {
                for fmt in formats {
                    if let items = try? await asset.loadMetadata(for: fmt) {
                        for item in items {
                            let k = ((item.commonKey?.rawValue) ?? (item.key as? String) ?? "").lowercased()
                            let val = ((try? await item.load(.stringValue)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !val.isEmpty else { continue }

                            if res.title.isEmpty && (k.contains("title") || k.contains("tit2") || k == "©nam") {
                                res.title = val
                            }
                            if res.artist.isEmpty && (k.contains("artist") || k.contains("tpe1") || k.contains("tpe2") || k == "©art" || k == "aart") {
                                res.artist = val
                            }
                            if res.album.isEmpty && (k.contains("album") || k.contains("talb") || k == "©alb") {
                                res.album = val
                            }
                            if res.trackNumber.isEmpty && (k.contains("track") || k.contains("trck") || k == "trkn") {
                                res.trackNumber = val
                            }
                            if res.year.isEmpty && (k.contains("date") || k.contains("year") || k.contains("tyer") || k.contains("tdrc") || k == "©day") {
                                let digits = val.filter { $0.isNumber }
                                if digits.count >= 4 { res.year = String(digits.prefix(4)) }
                            }
                            if res.genre.isEmpty && (k.contains("genre") || k.contains("tcon") || k == "©gen") {
                                res.genre = val
                            }
                            if res.lyrics == nil && (k.contains("lyric") || k == "©lyr" || k.contains("uslt")) {
                                res.lyrics = val
                            }
                            if !res.hasArtwork && (k.contains("art") || k.contains("apic") || k == "covr") {
                                res.hasArtwork = true
                            }
                        }
                    }
                }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 2.0)
        return res
    }

    public func readFFprobeMetadata(fileURL: URL) -> AudioFileMetadata? {
        let ffprobePath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffprobe") ? "/opt/homebrew/bin/ffprobe" : "/usr/local/bin/ffprobe"
        guard FileManager.default.fileExists(atPath: ffprobePath) else { return nil }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffprobePath)
        p.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", fileURL.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let tags = format["tags"] as? [String: Any] else {
            return nil
        }

        var res = AudioFileMetadata()
        var lowerTags: [String: String] = [:]
        for (k, v) in tags {
            if let str = v as? String {
                lowerTags[k.lowercased()] = str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        res.title = lowerTags["title"] ?? ""
        res.artist = lowerTags["artist"] ?? (lowerTags["album_artist"] ?? (lowerTags["albumartist"] ?? ""))
        res.album = lowerTags["album"] ?? ""
        res.trackNumber = lowerTags["track"] ?? (lowerTags["tracknumber"] ?? "")
        let rawDate = lowerTags["date"] ?? (lowerTags["year"] ?? "")
        let digits = rawDate.filter { $0.isNumber }
        if digits.count >= 4 { res.year = String(digits.prefix(4)) }
        res.genre = lowerTags["genre"] ?? ""

        if let durStr = format["duration"] as? String, let d = Double(durStr) {
            res.durationSeconds = d
        }
        if let brStr = format["bit_rate"] as? String, let br = Int(brStr) {
            res.bitrateKbps = br / 1000
        }

        return res
    }

    public func readFLACMetadata(fileURL: URL) -> AudioFileMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        var res = AudioFileMetadata()
        var isLast = false

        while !isLast {
            guard let bh = try? handle.read(upToCount: 4), bh.count == 4 else { break }
            isLast = (bh[0] & 0x80) != 0
            let type = Int(bh[0] & 0x7F)
            let len = (Int(bh[1]) << 16) | (Int(bh[2]) << 8) | Int(bh[3])

            if type == 0 && len >= 34 { // STREAMINFO
                guard let d = try? handle.read(upToCount: len), d.count >= 34 else { break }
                let b10_17 = d.subdata(in: 10..<18)
                let raw = b10_17.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let sr = Int((raw >> 44) & 0xFFFFF)
                let bps = Int(((raw >> 36) & 0x1F) + 1)
                let samples = Int64(raw & 0xFFFFFFFFF)
                res.sampleRate = sr
                res.bitsPerSample = bps
                if sr > 0 {
                    res.durationSeconds = Double(samples) / Double(sr)
                    if res.durationSeconds > 0 && fileSize > 0 {
                        res.bitrateKbps = Int((Double(fileSize) * 8.0) / (res.durationSeconds * 1000.0))
                    }
                }
            } else if type == 4 { // VORBIS_COMMENT
                guard let d = try? handle.read(upToCount: len), d.count == len else { break }
                var offset = 0
                if offset + 4 <= d.count {
                    let vLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                    offset += 4 + vLen
                    if offset + 4 <= d.count {
                        let count = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                        offset += 4
                        for _ in 0..<count {
                            guard offset + 4 <= d.count else { break }
                            let cLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                            offset += 4
                            guard offset + cLen <= d.count else { break }
                            if let s = String(data: d.subdata(in: offset..<offset+cLen), encoding: .utf8) {
                                let parts = s.components(separatedBy: "=")
                                if parts.count >= 2 {
                                    let k = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
                                    let v = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                                    if k == "TITLE" {
                                        res.title = v
                                    } else if k == "ARTIST" {
                                        if res.artist.isEmpty {
                                            res.artist = v
                                        } else if !res.artist.contains(v) {
                                            res.artist += "; \(v)"
                                        }
                                    } else if (k == "ALBUMARTIST" || k == "ALBUM_ARTIST") && res.artist.isEmpty {
                                        res.artist = v
                                    } else if k == "ALBUM" {
                                        res.album = v
                                    } else if k == "TRACKNUMBER" || k == "TRACK" {
                                        res.trackNumber = v
                                    } else if (k == "DATE" || k == "YEAR" || k == "ORIGINALDATE" || k == "ORIGINALYEAR" || k == "ORIGINAL_DATE" || k == "RELEASEDATE" || k == "RELEASE_DATE") && res.year.isEmpty {
                                        res.year = AudioTagger.extractYearString(v)
                                    } else if k == "GENRE" {
                                        let normalized = AudioTagger.normalizeGenre(v)
                                        if !normalized.isEmpty {
                                            if res.genre.isEmpty {
                                                res.genre = normalized
                                            } else if !res.genre.contains(normalized) {
                                                res.genre += ", \(normalized)"
                                            }
                                        }
                                    } else if (k == "LYRICS" || k == "UNSYNCEDLYRICS" || k == "UNSYNCED LYRICS" || k == "SYNCEDLYRICS" || k == "SYNCED LYRICS") && res.lyrics == nil {
                                        res.lyrics = v
                                    }
                                }
                            }
                            offset += cLen
                        }
                    }
                }
            } else if type == 6 { // PICTURE
                res.hasArtwork = true
                try? handle.seek(toOffset: handle.offsetInFile + UInt64(len))
            } else {
                try? handle.seek(toOffset: handle.offsetInFile + UInt64(len))
            }
        }
        return res
    }

    public func readMP3Metadata(fileURL: URL) -> AudioFileMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 10), header.count == 10 else { return nil }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0

        var res = AudioFileMetadata()
        var audioOffset = 0

        if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
            let version = header[3]
            let flags = header[5]
            let tagSize = (Int(header[6]) << 21) | (Int(header[7]) << 14) | (Int(header[8]) << 7) | Int(header[9])
            audioOffset = 10 + tagSize

            if let tagData = try? handle.read(upToCount: tagSize) {
                var offset = 0

                // Skip extended header if present (bit 6 of flags = 0x40)
                if (flags & 0x40) != 0 && tagData.count >= 4 {
                    if version == 4 {
                        let extSize = (Int(tagData[0]) << 21) | (Int(tagData[1]) << 14) | (Int(tagData[2]) << 7) | Int(tagData[3])
                        offset = max(4, extSize)
                    } else if version == 3 {
                        let extSize = (Int(tagData[0]) << 24) | (Int(tagData[1]) << 16) | (Int(tagData[2]) << 8) | Int(tagData[3])
                        offset = max(4, extSize + 4)
                    }
                }

                if version == 2 {
                    // ID3v2.2 (3-byte ID, 3-byte size, 6-byte header)
                    while offset + 6 <= tagData.count {
                        let idData = tagData.subdata(in: offset..<offset+3)
                        guard let frameID = String(data: idData, encoding: .ascii), frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                            break
                        }
                        let fSize = (Int(tagData[offset+3]) << 16) | (Int(tagData[offset+4]) << 8) | Int(tagData[offset+5])
                        offset += 6
                        guard offset + fSize <= tagData.count else { break }
                        let frameContent = tagData.subdata(in: offset..<offset+fSize)
                        offset += fSize

                        if frameID == "PIC" {
                            res.hasArtwork = true
                        } else if frameID.hasPrefix("T") && frameContent.count > 1 {
                            let enc = frameContent[0]
                            let payload = frameContent.subdata(in: 1..<frameContent.count)
                            let text: String?
                            if enc == 0 { text = String(data: payload, encoding: .isoLatin1) }
                            else if enc == 1 { text = String(data: payload, encoding: .utf16) }
                            else if enc == 2 { text = String(data: payload, encoding: .utf16BigEndian) }
                            else { text = String(data: payload, encoding: .utf8) }

                            let val = (text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\n\r"))
                            if !val.isEmpty {
                                if frameID == "TT2" { res.title = val }
                                else if frameID == "TP1" { res.artist = val }
                                else if frameID == "TP2" && res.artist.isEmpty { res.artist = val }
                                else if frameID == "TAL" { res.album = val }
                                else if frameID == "TRK" { res.trackNumber = val }
                                else if frameID == "TYE" && res.year.isEmpty { res.year = AudioTagger.extractYearString(val) }
                                else if frameID == "TCO" && res.genre.isEmpty { res.genre = AudioTagger.normalizeGenre(val) }
                            }
                        }
                    }
                } else {
                    // ID3v2.3 / ID3v2.4 (4-byte ID, 4-byte size, 10-byte header)
                    while offset + 10 <= tagData.count {
                        let idData = tagData.subdata(in: offset..<offset+4)
                        guard let frameID = String(data: idData, encoding: .ascii), frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                            break
                        }
                        let fSize: Int
                        if version == 4 {
                            fSize = (Int(tagData[offset+4]) << 21) | (Int(tagData[offset+5]) << 14) | (Int(tagData[offset+6]) << 7) | Int(tagData[offset+7])
                        } else {
                            fSize = (Int(tagData[offset+4]) << 24) | (Int(tagData[offset+5]) << 16) | (Int(tagData[offset+6]) << 8) | Int(tagData[offset+7])
                        }
                        offset += 10
                        guard offset + fSize <= tagData.count else { break }
                        let frameContent = tagData.subdata(in: offset..<offset+fSize)
                        offset += fSize

                        if frameID == "APIC" || frameID == "PIC" {
                            res.hasArtwork = true
                        } else if frameID.hasPrefix("T") && frameContent.count > 1 {
                            let enc = frameContent[0]
                            let payload = frameContent.subdata(in: 1..<frameContent.count)
                            let text: String?
                            if enc == 0 { text = String(data: payload, encoding: .isoLatin1) }
                            else if enc == 1 { text = String(data: payload, encoding: .utf16) }
                            else if enc == 2 { text = String(data: payload, encoding: .utf16BigEndian) }
                            else { text = String(data: payload, encoding: .utf8) }

                            let val = (text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\n\r"))
                            if !val.isEmpty {
                                if frameID == "TIT2" || frameID == "TT2" { res.title = val }
                                else if frameID == "TPE1" || frameID == "TP1" { res.artist = val }
                                else if frameID == "TPE2" && res.artist.isEmpty { res.artist = val }
                                else if frameID == "TALB" || frameID == "TAL" { res.album = val }
                                else if frameID == "TRCK" || frameID == "TRK" { res.trackNumber = val }
                                else if (frameID == "TYER" || frameID == "TYE" || frameID == "TDRC") && res.year.isEmpty {
                                    res.year = AudioTagger.extractYearString(val)
                                } else if (frameID == "TCON" || frameID == "TCO") && res.genre.isEmpty {
                                    res.genre = AudioTagger.normalizeGenre(val)
                                }
                            }
                        } else if (frameID == "USLT" || frameID == "SYLT" || frameID == "ULT") && res.lyrics == nil && frameContent.count > 4 {
                            let enc = frameContent[0]
                            let payload = frameContent.subdata(in: 4..<frameContent.count)
                            let text: String?
                            if enc == 0 { text = String(data: payload, encoding: .isoLatin1) ?? String(data: payload, encoding: .windowsCP1252) }
                            else if enc == 1 { text = String(data: payload, encoding: .utf16) }
                            else if enc == 2 { text = String(data: payload, encoding: .utf16BigEndian) }
                            else { text = String(data: payload, encoding: .utf8) }
                            if let full = text {
                                let parts = full.components(separatedBy: "\0")
                                let lyric = (parts.last ?? full).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}\0")))
                                if !lyric.isEmpty { res.lyrics = lyric }
                            }
                        }
                    }
                }
            }
        }

        // ID3v1 Fallback at EOF (last 128 bytes)
        if (res.title.isEmpty || res.artist.isEmpty || res.album.isEmpty) && fileSize >= 128 {
            try? handle.seek(toOffset: UInt64(fileSize - 128))
            if let id3v1 = try? handle.read(upToCount: 128), id3v1.count == 128,
               id3v1[0] == 0x54 && id3v1[1] == 0x41 && id3v1[2] == 0x47 {
                let v1Title = String(data: id3v1.subdata(in: 3..<33), encoding: .isoLatin1)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
                let v1Artist = String(data: id3v1.subdata(in: 33..<63), encoding: .isoLatin1)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
                let v1Album = String(data: id3v1.subdata(in: 63..<93), encoding: .isoLatin1)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""
                let v1Year = String(data: id3v1.subdata(in: 93..<97), encoding: .isoLatin1)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? ""

                if res.title.isEmpty && !v1Title.isEmpty { res.title = v1Title }
                if res.artist.isEmpty && !v1Artist.isEmpty { res.artist = v1Artist }
                if res.album.isEmpty && !v1Album.isEmpty { res.album = v1Album }
                if res.year.isEmpty && !v1Year.isEmpty { res.year = v1Year }
            }
        }

        // Try reading MPEG frame for bitrate/sample rate/duration
        if audioOffset > 0 && audioOffset < fileSize {
            try? handle.seek(toOffset: UInt64(audioOffset))
            if let frameBytes = try? handle.read(upToCount: 4), frameBytes.count == 4 {
                if frameBytes[0] == 0xFF && (frameBytes[1] & 0xE0) == 0xE0 {
                    let bitrateIndex = Int((frameBytes[2] >> 4) & 0x0F)
                    let sampleRateIndex = Int((frameBytes[2] >> 2) & 0x03)
                    let mpeg1Layer3Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
                    let sampleRates = [44100, 48000, 32000]
                    let br = (bitrateIndex < mpeg1Layer3Bitrates.count) ? mpeg1Layer3Bitrates[bitrateIndex] : 128
                    let sr = (sampleRateIndex < sampleRates.count) ? sampleRates[sampleRateIndex] : 44100
                    res.bitrateKbps = br
                    res.sampleRate = sr
                    if br > 0 {
                        res.durationSeconds = Double((fileSize - Int64(audioOffset)) * 8) / Double(br * 1000)
                    }
                }
            }
        }

        return res
    }

    // -----------------------------------------------------------------------
    // Cover Art & Lyrics Extractor
    // -----------------------------------------------------------------------
    private let artCache = NSCache<NSURL, NSData>()
    private let lyricsCache = NSCache<NSURL, NSString>()

    public func extractCoverArt(fileURL: URL) -> Data? {
        if let cached = artCache.object(forKey: fileURL as NSURL) {
            return cached as Data
        }

        let ext = fileURL.pathExtension.lowercased()
        var artData: Data? = nil

        if ext == "flac" {
            artData = extractFLACPicture(fileURL: fileURL)
        } else if ext == "mp3" {
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                defer { try? handle.close() }
                if let header = try? handle.read(upToCount: 10), header.starts(with: [0x49, 0x44, 0x33]) {
                    let b6 = Int(header[6]); let b7 = Int(header[7]); let b8 = Int(header[8]); let b9 = Int(header[9])
                    let tagSize = (b6 << 21) | (b7 << 14) | (b8 << 7) | b9
                    if tagSize > 0, let tagData = try? handle.read(upToCount: tagSize) {
                        var fullTag = header
                        fullTag.append(tagData)
                        artData = extractMP3Apic(data: fullTag)
                    }
                }
            }
        }

        // Fallback to AVURLAsset artwork (M4A, ALAC, WAV, MP4, MP3 fallback)
        if artData == nil {
            let asset = AVURLAsset(url: fileURL)
            let metadata = asset.metadata
            for item in metadata {
                if item.commonKey == .commonKeyArtwork, let data = item.dataValue {
                    artData = data
                    break
                }
            }
        }

        // Fallback to album folder art
        if artData == nil {
            let parent = fileURL.deletingLastPathComponent()
            for cand in ["folder.jpg", "cover.jpg", "front.jpg", "Folder.jpg", "Cover.jpg", "folder.png", "cover.png", "album.jpg"] {
                let candURL = parent.appendingPathComponent(cand)
                if let d = try? Data(contentsOf: candURL) {
                    artData = d
                    break
                }
            }
        }

        if let art = artData {
            artCache.setObject(art as NSData, forKey: fileURL as NSURL)
        }
        return artData
    }

    public func extractLyrics(fileURL: URL) -> String? {
        if let cached = lyricsCache.object(forKey: fileURL as NSURL) {
            return cached as String
        }

        let baseURL = fileURL.deletingPathExtension()

        // 1. Check companion .lrc or .txt file (Sony Walkman native standard, case-insensitive)
        let candidateURLs = [
            baseURL.appendingPathExtension("lrc"),
            baseURL.appendingPathExtension("LRC"),
            baseURL.appendingPathExtension("txt"),
            baseURL.appendingPathExtension("TXT")
        ]

        for cand in candidateURLs {
            if let lrc = readCompanionFile(url: cand) {
                lyricsCache.setObject(lrc as NSString, forKey: fileURL as NSURL)
                return lrc
            }
        }

        // 2. Check embedded FLAC Vorbis comments (LYRICS, UNSYNCEDLYRICS, SYNCEDLYRICS)
        let ext = fileURL.pathExtension.lowercased()
        if ext == "flac" {
            if let flacLyrics = extractFLACLyrics(fileURL: fileURL) {
                lyricsCache.setObject(flacLyrics as NSString, forKey: fileURL as NSURL)
                return flacLyrics
            }
        }

        // 3. Check embedded MP3 USLT / SYLT / ULT frame
        if ext == "mp3" {
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                defer { try? handle.close() }
                if let header = try? handle.read(upToCount: 10), header.starts(with: [0x49, 0x44, 0x33]) {
                    let b6 = Int(header[6]); let b7 = Int(header[7]); let b8 = Int(header[8]); let b9 = Int(header[9])
                    let tagSize = (b6 << 21) | (b7 << 14) | (b8 << 7) | b9
                    if tagSize > 0, let tagData = try? handle.read(upToCount: tagSize) {
                        var fullTag = header
                        fullTag.append(tagData)
                        if let lyrics = extractMP3Lyrics(data: fullTag) {
                            lyricsCache.setObject(lyrics as NSString, forKey: fileURL as NSURL)
                            return lyrics
                        }
                    }
                }
            }
        }

        // 4. Check embedded M4A / MP4 / ALAC / AAC QuickTime lyrics atom (©lyr)
        if ext == "m4a" || ext == "mp4" || ext == "alac" || ext == "aac" {
            if let mp4Lyrics = extractMP4Lyrics(fileURL: fileURL) {
                lyricsCache.setObject(mp4Lyrics as NSString, forKey: fileURL as NSURL)
                return mp4Lyrics
            }
        }

        return nil
    }

    private func readCompanionFile(url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if let str = String(data: data, encoding: .utf8) ??
                     String(data: data, encoding: .windowsCP1252) ??
                     String(data: data, encoding: .isoLatin1) ??
                     String(data: data, encoding: .utf16) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func extractFLACLyrics(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        var isLast = false
        while !isLast {
            guard let bh = try? handle.read(upToCount: 4), bh.count == 4 else { break }
            isLast = (bh[0] & 0x80) != 0
            let type = Int(bh[0] & 0x7F)
            let len = (Int(bh[1]) << 16) | (Int(bh[2]) << 8) | Int(bh[3])

            if type == 4 { // VORBIS_COMMENT
                guard let d = try? handle.read(upToCount: len), d.count == len else { break }
                var offset = 0
                if offset + 4 <= d.count {
                    let vLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                    offset += 4 + vLen
                    if offset + 4 <= d.count {
                        let count = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                        offset += 4
                        for _ in 0..<count {
                            guard offset + 4 <= d.count else { break }
                            let cLen = Int(d[offset]) | (Int(d[offset+1]) << 8) | (Int(d[offset+2]) << 16) | (Int(d[offset+3]) << 24)
                            offset += 4
                            guard offset + cLen <= d.count else { break }
                            let commentData = d.subdata(in: offset..<offset+cLen)
                            if let s = String(data: commentData, encoding: .utf8) ?? String(data: commentData, encoding: .isoLatin1) {
                                let parts = s.components(separatedBy: "=")
                                if parts.count >= 2 {
                                    let k = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
                                    if k == "LYRICS" || k == "UNSYNCEDLYRICS" || k == "UNSYNCED LYRICS" || k == "SYNCEDLYRICS" || k == "SYNCED LYRICS" {
                                        let v = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !v.isEmpty {
                                            return v
                                        }
                                    }
                                }
                            }
                            offset += cLen
                        }
                    }
                }
                return nil
            } else {
                guard (try? handle.seek(toOffset: (try? handle.offset())! + UInt64(len))) != nil else { break }
            }
        }
        return nil
    }

    private func extractMP4Lyrics(fileURL: URL) -> String? {
        let asset = AVURLAsset(url: fileURL)
        let sem = DispatchSemaphore(value: 0)
        var lyricsResult: String? = nil
        Task {
            if let formats = try? await asset.load(.availableMetadataFormats) {
                for fmt in formats {
                    if let items = try? await asset.loadMetadata(for: fmt) {
                        for item in items {
                            if let key = item.key as? String, key == "©lyr" || key.lowercased() == "lyrics" {
                                if let str = try? await item.load(.stringValue), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    lyricsResult = str
                                    break
                                }
                            }
                        }
                    }
                    if lyricsResult != nil { break }
                }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.5)
        return lyricsResult
    }

    public func saveLyrics(fileURL: URL, lyrics: String) throws {
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        do {
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        } catch {
            // Non-atomic fallback for external FAT32/exFAT Walkman volumes
            try lyrics.write(to: lrcURL, atomically: false, encoding: .utf8)
        }

        // Clean macOS metadata shadow file and xattrs on external storage
        let cPath = (lrcURL.path as NSString).fileSystemRepresentation
        removexattr(cPath, "com.apple.TextEncoding", 0)
        let dotfileURL = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()

        lyricsCache.setObject(lyrics as NSString, forKey: fileURL as NSURL)
    }

    public func deleteLyrics(fileURL: URL) throws {
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            try FileManager.default.removeItem(at: lrcURL)
        }
        let upperLrc = fileURL.deletingPathExtension().appendingPathExtension("LRC")
        if FileManager.default.fileExists(atPath: upperLrc.path) {
            try FileManager.default.removeItem(at: upperLrc)
        }
        let dotfileURL = lrcURL.deletingLastPathComponent().appendingPathComponent("._" + lrcURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dotfileURL)
        sync()

        lyricsCache.removeObject(forKey: fileURL as NSURL)
    }

    private func extractMP3Lyrics(data: Data) -> String? {
        guard data.count > 10, data.starts(with: [0x49, 0x44, 0x33]) else { return nil }
        let isV24 = data[3] == 4
        let b6 = Int(data[6]); let b7 = Int(data[7]); let b8 = Int(data[8]); let b9 = Int(data[9])
        let tagSize = min(data.count - 10, (b6 << 21) | (b7 << 14) | (b8 << 7) | b9)

        var idx = 10
        while idx + 10 < tagSize + 10 {
            let frameID = String(data: data.subdata(in: idx..<idx+4), encoding: .ascii) ?? ""
            let rawSize: Int
            if isV24 {
                rawSize = (Int(data[idx+4]) << 21) | (Int(data[idx+5]) << 14) | (Int(data[idx+6]) << 7) | Int(data[idx+7])
            } else {
                rawSize = (Int(data[idx+4]) << 24) | (Int(data[idx+5]) << 16) | (Int(data[idx+6]) << 8) | Int(data[idx+7])
            }

            if frameID == "USLT" || frameID == "SYLT" || frameID == "ULT" {
                let frameContent = data.subdata(in: idx+10..<min(data.count, idx+10+rawSize))
                if frameContent.count > 4 {
                    let enc = frameContent[0]
                    let payload = frameContent.subdata(in: 4..<frameContent.count)
                    var text: String? = nil
                    if enc == 0 {
                        text = String(data: payload, encoding: .isoLatin1) ?? String(data: payload, encoding: .windowsCP1252)
                    } else if enc == 1 {
                        text = String(data: payload, encoding: .utf16)
                    } else if enc == 2 {
                        text = String(data: payload, encoding: .utf16BigEndian)
                    } else {
                        text = String(data: payload, encoding: .utf8)
                    }
                    if text == nil {
                        text = String(data: payload, encoding: .utf8) ?? String(data: payload, encoding: .utf16)
                    }
                    if let full = text {
                        let parts = full.components(separatedBy: "\0")
                        let lyric = (parts.last ?? full).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}\0")))
                        if !lyric.isEmpty {
                            return lyric
                        }
                    }
                }
            }
            if rawSize <= 0 { break }
            idx += 10 + rawSize
        }
        return nil
    }

    private func extractFLACPicture(fileURL: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else { return nil }

        var isLast = false
        while !isLast {
            guard let bh = try? handle.read(upToCount: 4), bh.count == 4 else { break }
            isLast = (bh[0] & 0x80) != 0
            let blockType = Int(bh[0] & 0x7F)
            let blockLen = (Int(bh[1]) << 16) | (Int(bh[2]) << 8) | Int(bh[3])

            if blockType == 6 { // PICTURE block
                guard let d = try? handle.read(upToCount: blockLen), d.count >= 32 else { break }
                var pos = 4 // skip picture type
                guard pos + 4 <= d.count else { break }
                let mimeLen = (Int(d[pos]) << 24) | (Int(d[pos+1]) << 16) | (Int(d[pos+2]) << 8) | Int(d[pos+3])
                pos += 4 + mimeLen
                guard pos + 4 <= d.count else { break }
                let descLen = (Int(d[pos]) << 24) | (Int(d[pos+1]) << 16) | (Int(d[pos+2]) << 8) | Int(d[pos+3])
                pos += 4 + descLen + 16 // skip description, width, height, depth, colors
                guard pos + 4 <= d.count else { break }
                let dataLen = (Int(d[pos]) << 24) | (Int(d[pos+1]) << 16) | (Int(d[pos+2]) << 8) | Int(d[pos+3])
                pos += 4
                if pos + dataLen <= d.count {
                    return d.subdata(in: pos..<pos+dataLen)
                }
            } else {
                try? handle.seek(toOffset: handle.offsetInFile + UInt64(blockLen))
            }
        }
        return nil
    }

    private func extractMP3Apic(data: Data) -> Data? {
        guard data.count > 10, data.starts(with: [0x49, 0x44, 0x33]) else { return nil }
        let isV24 = data[3] == 4
        let b6 = Int(data[6])
        let b7 = Int(data[7])
        let b8 = Int(data[8])
        let b9 = Int(data[9])
        let tagSize = min(data.count - 10, (b6 << 21) | (b7 << 14) | (b8 << 7) | b9)

        var idx = 10
        while idx + 10 < tagSize + 10 {
            let frameID = String(data: data.subdata(in: idx..<idx+4), encoding: .ascii) ?? ""
            let rawSize: Int
            if isV24 {
                rawSize = (Int(data[idx+4]) << 21) | (Int(data[idx+5]) << 14) | (Int(data[idx+6]) << 7) | Int(data[idx+7])
            } else {
                rawSize = (Int(data[idx+4]) << 24) | (Int(data[idx+5]) << 16) | (Int(data[idx+6]) << 8) | Int(data[idx+7])
            }

            if frameID == "APIC" {
                let frameContent = data.subdata(in: idx+10..<min(data.count, idx+10+rawSize))
                // Search for JPEG SOI (0xFF 0xD8) or PNG SOI (0x89 0x50 0x4E 0x47)
                for j in 0..<(frameContent.count - 3) {
                    if frameContent[j] == 0xFF && frameContent[j+1] == 0xD8 {
                        return frameContent.subdata(in: j..<frameContent.count)
                    }
                    if frameContent[j] == 0x89 && frameContent[j+1] == 0x50 && frameContent[j+2] == 0x4E && frameContent[j+3] == 0x47 {
                        return frameContent.subdata(in: j..<frameContent.count)
                    }
                }
            }
            if rawSize <= 0 { break }
            idx += 10 + rawSize
        }
        return nil
    }
}
