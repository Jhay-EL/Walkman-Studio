import Foundation
import AppKit

public final class AudioTagger: @unchecked Sendable {
    public static let shared = AudioTagger()
    private init() {}

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
        content.append(0x01) // Encoding: 1 = UTF-16
        content.append("image/jpeg\0".data(using: .ascii)!) // MIME
        content.append(0x03) // Picture type: 3 = Front cover
        content.append(contentsOf: [0x00, 0x00]) // Description: empty UTF-16 string
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

        // 1. Check companion .lrc or .txt file (Sony NW-A55 native standard)
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
