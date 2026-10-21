import Foundation
import AppKit
import CoreGraphics
import ImageIO

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
        coverArtData: Data?
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
                coverArtData: coverArtData
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
                coverArtData: coverArtData
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
        coverArtData: Data?
    ) throws {
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
                                    let standardKeys: Set<String> = ["TITLE", "ARTIST", "ALBUM", "TRACKNUMBER", "TRACK", "DATE", "YEAR", "GENRE"]
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

        let finTitle = title ?? existingComments["TITLE"]
        if let t = finTitle, !t.isEmpty { newComments.append(("TITLE", t)) }

        let finArtist = artist ?? existingComments["ARTIST"]
        if let a = finArtist, !a.isEmpty { newComments.append(("ARTIST", a)) }

        let finAlbum = album ?? existingComments["ALBUM"]
        if let al = finAlbum, !al.isEmpty { newComments.append(("ALBUM", al)) }

        let finTrack = trackNumber ?? (existingComments["TRACKNUMBER"] ?? existingComments["TRACK"])
        if let tr = finTrack, !tr.isEmpty { newComments.append(("TRACKNUMBER", tr)) }

        let finYear = year ?? (existingComments["DATE"] ?? existingComments["YEAR"])
        if let y = finYear, !y.isEmpty { newComments.append(("DATE", y)) }

        let finGenre = genre ?? existingComments["GENRE"]
        if let g = finGenre, !g.isEmpty { newComments.append(("GENRE", g)) }

        for (k, v) in existingOtherComments {
            newComments.append((k, v))
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

        try output.write(to: fileURL, options: .atomic)
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
        coverArtData: Data?
    ) throws {
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

        // 2. Build ID3v2.3 frames (UTF-16 encoding = 1)
        var framesData = Data()

        if let t = title, !t.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TIT2", text: t))
        }
        if let a = artist, !a.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TPE1", text: a))
        }
        if let al = album, !al.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TALB", text: al))
        }
        if let tr = trackNumber, !tr.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TRCK", text: tr))
        }
        if let y = year, !y.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TYER", text: y))
        }
        if let g = genre, !g.isEmpty {
            framesData.append(makeID3v23TextFrame(id: "TCON", text: g))
        }

        // 3. Embed Baseline RGB JPEG APIC frame
        if let rawArt = coverArtData, let baselineJPEG = WalkmanEngine.shared.encodeBaselineRGBJPEG(data: rawArt) {
            framesData.append(makeID3v23ApicFrame(imageData: baselineJPEG))
        }

        // 4. Construct ID3v2.3 10-byte header
        var header = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]) // ID3v2.3, no flags
        let synchsafe = synchsafeBytes(framesData.count)
        header.append(contentsOf: synchsafe)

        // 5. Assemble complete file
        var output = Data()
        output.append(header)
        output.append(framesData)
        output.append(audioStream)

        try output.write(to: fileURL, options: .atomic)
    }

    private func makeID3v23TextFrame(id: String, text: String) -> Data {
        var frame = Data()
        frame.append(id.data(using: .ascii)!)

        var content = Data([0x01]) // 1 = UTF-16 with BOM
        content.append(contentsOf: [0xFF, 0xFE]) // UTF-16LE BOM
        content.append(text.data(using: .utf16LittleEndian)!)

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

    private func synchsafeBytes(_ size: Int) -> [UInt8] {
        return [
            UInt8((size >> 21) & 0x7F),
            UInt8((size >> 14) & 0x7F),
            UInt8((size >> 7) & 0x7F),
            UInt8(size & 0x7F)
        ]
    }

    public func invalidateCaches(fileURL: URL) {
        artCache.removeObject(forKey: fileURL as NSURL)
        lyricsCache.removeObject(forKey: fileURL as NSURL)
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

        // 1. Check companion .lrc or .txt file (Sony Walkman native standard)
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        if let lrc = try? String(contentsOf: lrcURL, encoding: .utf8), !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyricsCache.setObject(lrc as NSString, forKey: fileURL as NSURL)
            return lrc
        }

        let txtURL = fileURL.deletingPathExtension().appendingPathExtension("txt")
        if let txt = try? String(contentsOf: txtURL, encoding: .utf8), !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyricsCache.setObject(txt as NSString, forKey: fileURL as NSURL)
            return txt
        }

        // 2. Check embedded MP3 USLT frame
        let ext = fileURL.pathExtension.lowercased()
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

        return nil
    }

    public func saveLyrics(fileURL: URL, lyrics: String) throws {
        let lrcURL = fileURL.deletingPathExtension().appendingPathExtension("lrc")
        try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        lyricsCache.setObject(lyrics as NSString, forKey: fileURL as NSURL)
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

            if frameID == "USLT" || frameID == "SYLT" {
                let frameContent = data.subdata(in: idx+10..<min(data.count, idx+10+rawSize))
                if frameContent.count > 4 {
                    // Try decoding as utf8 or utf16
                    if let str = String(data: frameContent.subdata(in: 4..<frameContent.count), encoding: .utf8) {
                        return str
                    }
                    if let str = String(data: frameContent.subdata(in: 4..<frameContent.count), encoding: .utf16) {
                        return str
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
