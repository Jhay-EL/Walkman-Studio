import Foundation
import AppKit

public struct SenseMeInfo: Sendable, Codable, Equatable {
    public let isAnalyzed: Bool
    public let bpm: Double
    public let rawBpm: Double
    public let valence: Double
    public let arousal: Double
    public let moodScores: [Int]
    public let channels: [String]
    public let highlightSec: Double

    public static let notAnalyzed = SenseMeInfo(
        isAnalyzed: false,
        bpm: 0,
        rawBpm: 0,
        valence: 0,
        arousal: 0,
        moodScores: Array(repeating: 0, count: 10),
        channels: [],
        highlightSec: 0
    )
}

public final class SenseMeEngine: @unchecked Sendable {
    public static let shared = SenseMeEngine()

    private static let base64Template = "U01GTUdCUE1TVEFFTU1MVwEAgAAAAAAEQif+d1NUQkZTVEFFTU1MVwEAgAAAAAAkECkRRT4+TTpEIx85LS6UKScpKSkoHjQyLDQ3W/8CRkA1Nw88U1RTQVNUQUVNTUxXAQCAAAAAAAgAAC00AAAtNFNUTU9TVEFFTU1MVwEAgAAAAACgAQAAOQEAATkBAAI5AQADOQEBADIBAQEyAQECMgEBAzIBAgBLAQIBSwECAksBAgNLAQMAOQEDATkBAwI5AQMDOQEEABIBBAESAQQCEgEEAxIBBQA8AQUBPAEFAjwBBQM8AQYAAAEGAQABBgIAAQYDAAEHAC0BBwEtAQcCLQEHAy0BCABCAQgBQgEIAkIBCANCAQkANAEJATQBCQI0AQkDNFNUSEZTVEFFTU1MVwEAgAAAAACgCAAUAAgBPAAIAjkACANBAAgEMwAIBSEACAZJAAgHLgAICEsACAlTAAgKTgAICx8ACAwiAAgNIwAIDiEACA8oAAgQKAAIEToACBIzAAgTMgAIFEAACBVBAAgWQQAIF1AACBg/AAgZHwAIGiUACBs+AAgcYAAIHSAACB5OAAgfHQAIIBwACCEdAAgiLgAIIy4ACCQqAAglLQAIJh8ACCccAFNUTU1TVEFFTU1MVwEAgAAAAAraAAAAdgACAAAAAAAAAAAAtP////////////////////9CJ/53BAQABACLAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAtAAACh7/////////////////////Qif+dwQEACkAhgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAApcAAAALAAArEQAopAGAAAAAACikAUCEAAE/////wAAAQQBAACqCQAAThAAAAMvAAAJAAAKKAARL4AAAQAAGLIAES+AABAAABiyABEvgAWCAAAYsgARL4AUgwAAGLIAES+AAAQAABiyABEQgACAAAAYsgARCQAEWAAAGLIAEQEgAP8AABiyABIBAAD/AAEOzAATCQAElgACBOYAEwEAAP8AAgTmABQBAAD/AAL7AAAhCQAElAAD8RsAIQEgAP8AA/EbACIBAAD/AATnNQAjCQAETAAF3U8AIwEAAP8ABd1PACQBAAD/AAbTaQAxL4AAgQAHyYQAMS+AAwIAB8mEADEJAASEAAfJhAAxASAA/wAHyYQAMRCABAAAB8mEADIBAAD/AAi/ngAzCQAEkAAJtbgAMwEAAP8ACbW4ADQBAAD/AAqr0gBBCQAEhAALoe0AQQEgAP8AC6HtAEIBAAD/AAyYBwBDCQAEWAANjiEAQwEAAP8ADY4hAEQBAAD/AA6EOwBRCQAEhAAPelYAUQEgAP8AD3pWAFIBAAD/ABBwcABTCQAEkAARZooAUwEAAP8AEWaKAFQBAAD/ABJcpABhCQAEhAATUr8AYQEgAP8AE1K/AGIBAAD/ABRI2QBjCQAEiAAVPvMAYwEAAP8AFT7zAGQBAAD/ABY1DQBxCQAEkAAXKycAcQEgAP8AFysnAHIBAAD/ABghQgBzCQAESAAZF1wAcwEAAP8AGRdcAHQBAAD/ABoNdgCBCQAEhAAbA5EAgQEgAP8AGwORAIIBAAD/ABv5qwCDCQAEWAAc78UAgwEAAP8AHO/FAIQBAAD/AB3l3wCRCQAEkAAe2/oAkQEgAP8AHtv6AJIBAAD/AB/SFACTAQAA/wAgyC4AlAEAAP8AIb5IAKEJAASEACK0YgChASAA/wAitGIAogEAAP8AI6p9AKMJAARYACSglwCjAQAA/wAkoJcApAEAAP8AJZaxALEJAASUACaMzACxASAA/wAmjMwAsgEAAP8AJ4LmALMJAASQACh5AACzAQAA/wAoeQAAtAEAAP8AKW8aAMEJAASEACplNQDBASAA/wAqZTUAwgEAAP8AK1tPAMMJAARYACxRaQDDAQAA/wAsUWkAxAEAAP8ALUeDANEJAASUAC49ngDRASAA/wAuPZ4A0gEAAP8ALzO4ANMJAASQADAp0gDTAQAA/wAwKdIA1AEAAP8AMR/sAOEJAASEADIWBgDhASAA/wAyFgYA4gEAAP8AMwwhAOMJAARYADQCOwDjAQAA/wA0AjsA5AEAAP8ANPhVAPEJAASUADXucADxASAA/wA17nAA8gEAAP8ANuSKAPMJAASQADfapADzAQAA/wA32qQA9AEAAP8AONC+AQEJAASEADnG2QEBASAA/wA5xtkBAgEAAP8AOrzzAQMJAARYADuzDQEDAQAA/wA7sw0BBAEAAP8APKknAREJAASUAD2fQQERASAA/wA9n0EBEgEAAP8APpVcARMJAASQAD+LdgETAQAA/wA/i3YBFAEAAP8AQIGQASEJAASEAEF3qwEhASAA/wBBd6sBIgEAAP8AQm3FASMJAARYAENj3wEjAQAA/wBDY98BJAEAAP8ARFn5ATEJAASQAEVQFAExASAA/wBFUBQBMgEAAP8ARkYuATMBAAD/AEc8SAE0AQAA/wBIMmIBQQkABJQASSh8AUEBIAD/AEkofAFCAQAA/wBKHpcBQwkABFgASxSxAUMBAAD/AEsUsQFEAQAA/wBMCssBUQkABJAATQDmAVEBIAD/AE0A5gFSAQAA/wBN9wABUwEAAP8ATu0aAVQBAAD/AE/jNAFhCQAEhABQ2U8BYQEgAP8AUNlPAWIBAAD/AFHPaQFjCQAEWABSxYMBYwEAAP8AUsWDAWQBAAD/AFO7nQFxCQAElABUsbcBcQEgAP8AVLG3AXEQgA+AAFSxtwFyAQAA/wBVp9IBcwkABJAAVp3sAXMBAAD/AFad7AF0AQAA/wBXlAYBgQkABIQAWIogAYEBIAD/AFiKIAGCAQAA/wBZgDsBgwkABFgAWnZVAYMBAAD/AFp2VQGEAQAA/wBbbG8BkQkABJQAXGKKAZEBIAD/AFxiigGSAQAA/wBdWKQBkwkABJAAXk6+AZMBAAD/AF5OvgGUAQAA/wBfRNgBoQkABIQAYDryAaEBIAD/AGA68gGiAQAA/wBhMQ0BowkABFgAYicnAaMBAAD/AGInJwGkAQAA/wBjHUIBsQkABJQAZBNbAbEBIAD/AGQTWwGyAQAA/wBlCXYBswkABJAAZf+QAbMBAAD/AGX/kAG0AQAA/wBm9aoBwQkABIQAZ+vFAcEBIAD/AGfrxQHCAQAA/wBo4d8BwwkABFgAadf5AcMBAAD/AGnX+QHEAQAA/wBqzhMB0QkABJQAa8QtAdEBIAD/AGvELQHSAQAA/wBsukgB0wkABIQAbbBiAdMBAAD/AG2wYgHUAQAA/wBupn0B4QkABJQAb5yWAeEBIAD/AG+clgHiAQAA/wBwkrEB4wkABFgAcYjLAeMBAAD/AHGIywHkAQAA/wByfuUB8QkABJAAc3UAAfEBIAD/AHN1AAHyAQAA/wB0axoB8wEAAP8AdWE0AfQBAAD/AHZXTgIBCQAEhAB3TWgCAQEgAP8Ad01oAgIBAAD/AHhDgwIDCQAEWAB5OZ0CAwEAAP8AeTmdAgQBAAD/AHovuAIRCQAEkAB7JdECEQEgAP8AeyXRAhIBAAD/AHwb7AITAQAA/wB9EgYCFAEAAP8AfgggAiEJAASEAH7+OwIhASAA/wB+/jsCIgEAAP8Af/RVAiMJAARYAIDqbwIjAQAA/wCA6m8CJAEAAP8AgeCJAjEJAASEAILWpAIxASAA/wCC1qQCMgEAAP8Ag8y+AjMJAASQAITC2AIzAQAA/wCEwtgCNAEAAP8AhbjzAkEJAASEAIavDAJBASAA/wCGrwwCQgEAAP8Ah6UnAkMJAARYAIibQQJDAQAA/wCIm0ECRAEAAP8AiZFbAlEJAASUAIqHdgJRASAA/wCKh3YCUgEAAP8Ai32QAlMJAASQAIxzqgJTAQAA/wCMc6oCVAEAAP8AjWnEAmEJAASEAI5f3wJhASAA/wCOX98CYgEAAP8Aj1X5AmMJAARYAJBMEwJjAQAA/wCQTBMCZAEAAP8AkUIuAnEJAASUAJI4RwJxASAA/wCSOEcCcgEAAP8Aky5iAnMJAASQAJQkfAJzAQAA/wCUJHwCdAEAAP8AlRqWAoEJAASEAJYQsQKBASAA/wCWELECggEAAP8AlwbLAoMJAARYAJf85QKDAQAA/wCX/OUChAEAAP8AmPL/ApEJAASUAJnpGgKRASAA/wCZ6RoCkgEAAP8Amt80ApMJAASQAJvVTgKTAQAA/wCb1U4ClAEAAP8AnMtpAqEJAASEAJ3BggKhASAA/wCdwYICogEAAP8AnredAqMBAAD/AJ+ttwKkAQAA/wCgo9ECsQEgAP8AoZnsArIBAAD/AKKQBgKyLwAAEQCikAYCsi9//4EAopAG"

    public static let templateData: Data = {
        return Data(base64Encoded: base64Template) ?? Data()
    }()

    private init() {}

    // -----------------------------------------------------------------------
    // 1. Fast Header Inspection (Pure Swift)
    // -----------------------------------------------------------------------
    public func inspect(fileURL: URL) -> SenseMeInfo {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "flac" {
            return inspectFLAC(fileURL: fileURL)
        } else if ext == "mp3" {
            return inspectMP3(fileURL: fileURL)
        } else if ext == "m4a" || ext == "m4b" || ext == "alac" || ext == "aac" || ext == "mp4" {
            return inspectM4A(fileURL: fileURL)
        }
        return .notAnalyzed
    }

    public func inspectFLAC(fileURL: URL) -> SenseMeInfo {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return .notAnalyzed }
        defer { try? handle.close() }

        guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else {
            return .notAnalyzed
        }

        var isLast = false
        while !isLast {
            guard let hdr = try? handle.read(upToCount: 4), hdr.count == 4 else { break }
            let b0 = hdr[0]
            isLast = (b0 & 0x80) != 0
            let bType = Int(b0 & 0x7F)
            let bLen = (Int(hdr[1]) << 16) | (Int(hdr[2]) << 8) | Int(hdr[3])

            if bType == 2 { // APPLICATION block
                guard let data = try? handle.read(upToCount: bLen), data.count == bLen else { break }
                if data.starts(with: [0x53, 0x4D, 0x46, 0x4D]) { // "SMFM"
                    if let parsed = parseSMFMPayload(data: data) {
                        return parsed
                    }
                }
            } else {
                // Skip block
                guard let curPos = try? handle.offset() else { break }
                try? handle.seek(toOffset: curPos + UInt64(bLen))
            }
        }

        return .notAnalyzed
    }

    public func inspectMP3(fileURL: URL) -> SenseMeInfo {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return .notAnalyzed }
        defer { try? handle.close() }

        guard let id3Hdr = try? handle.read(upToCount: 10), id3Hdr.count == 10,
              id3Hdr.starts(with: [0x49, 0x44, 0x33]) else {
            return .notAnalyzed
        }

        let tagSize = (Int(id3Hdr[6] & 0x7F) << 21) |
                      (Int(id3Hdr[7] & 0x7F) << 14) |
                      (Int(id3Hdr[8] & 0x7F) << 7)  |
                      Int(id3Hdr[9] & 0x7F)

        guard let tagData = try? handle.read(upToCount: tagSize), tagData.count == tagSize else {
            return .notAnalyzed
        }

        var offset = 0
        while offset + 10 <= tagData.count {
            let frameID = tagData.subdata(in: offset..<offset+4)
            guard let frameIDStr = String(data: frameID, encoding: .ascii), !frameIDStr.isEmpty else { break }
            if frameID[0] == 0 { break }

            let frameLen = (Int(tagData[offset+4]) << 24) |
                           (Int(tagData[offset+5]) << 16) |
                           (Int(tagData[offset+6]) << 8)  |
                           Int(tagData[offset+7])
            offset += 10
            guard offset + frameLen <= tagData.count else { break }
            let frameData = tagData.subdata(in: offset..<offset+frameLen)
            offset += frameLen

            if frameIDStr == "GEOB" || frameIDStr == "PRIV" {
                // Check if frameData contains SMFM payload
                if let smfmRange = frameData.range(of: Data([0x53, 0x4D, 0x46, 0x4D])) {
                    let payload = frameData.subdata(in: smfmRange.lowerBound..<frameData.count)
                    if let parsed = parseSMFMPayload(data: payload) {
                        return parsed
                    }
                }
            }
        }

        return .notAnalyzed
    }

    public func inspectM4A(fileURL: URL) -> SenseMeInfo {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return .notAnalyzed }
        if let smfmRange = data.range(of: Data([0x53, 0x4D, 0x46, 0x4D])) {
            let sub = data.subdata(in: smfmRange.lowerBound..<min(smfmRange.lowerBound + 3270, data.count))
            if let parsed = parseSMFMPayload(data: sub) {
                return parsed
            }
        }
        return .notAnalyzed
    }

    public func extractPayload(fileURL: URL) -> Data? {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "flac" {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
            defer { try? handle.close() }

            guard let magic = try? handle.read(upToCount: 4), magic == Data([0x66, 0x4C, 0x61, 0x43]) else {
                return nil
            }

            var isLast = false
            while !isLast {
                guard let hdr = try? handle.read(upToCount: 4), hdr.count == 4 else { break }
                let b0 = hdr[0]
                isLast = (b0 & 0x80) != 0
                let bType = Int(b0 & 0x7F)
                let bLen = (Int(hdr[1]) << 16) | (Int(hdr[2]) << 8) | Int(hdr[3])

                if bType == 2 { // APPLICATION block
                    guard let data = try? handle.read(upToCount: bLen), data.count == bLen else { break }
                    if data.starts(with: [0x53, 0x4D, 0x46, 0x4D]) { // "SMFM"
                        return data
                    }
                } else {
                    guard let curPos = try? handle.offset() else { break }
                    try? handle.seek(toOffset: curPos + UInt64(bLen))
                }
            }
        }
        return nil
    }

    // -----------------------------------------------------------------------
    // 2. Binary Payload Parser (Pure Swift)
    // -----------------------------------------------------------------------
    public func parseSMFMPayload(data: Data) -> SenseMeInfo? {
        guard data.count >= 24 else { return nil }
        var payload = data
        if payload.starts(with: [0x53, 0x4D, 0x46, 0x4D]) {
            payload = payload.subdata(in: 4..<payload.count)
        }

        var chunks: [String: Data] = [:]
        var offset = 0
        while offset + 20 <= payload.count {
            let header = payload.subdata(in: offset..<offset+20)
            guard let tag = String(data: header.subdata(in: 0..<4), encoding: .ascii) else { break }
            let len = (Int(header[16]) << 24) | (Int(header[17]) << 16) | (Int(header[18]) << 8) | Int(header[19])
            offset += 20
            guard offset + len <= payload.count else { break }
            chunks[tag] = payload.subdata(in: offset..<offset+len)
            offset += len
        }

        guard let gbpmData = chunks["GBPM"], gbpmData.count >= 4,
              let stmoData = chunks["STMO"], stmoData.count >= 160 else {
            return nil
        }

        // GBPM: Big-Endian Float
        let rawBpmBits = UInt32(bigEndian: gbpmData.withUnsafeBytes { $0.load(as: UInt32.self) })
        let rawBpm = Double(Float(bitPattern: rawBpmBits))
        let bpm = rawBpm < 58.0 ? (rawBpm * 2.0).rounded(toPlaces: 1) : rawBpm.rounded(toPlaces: 1)

        // STSA: Highlight
        var highlightSec: Double = 0.0
        if let stsaData = chunks["STSA"], stsaData.count >= 8 {
            let msBits = UInt32(bigEndian: stsaData.withUnsafeBytes { $0.load(as: UInt32.self) })
            highlightSec = Double(msBits) / 1000.0
        }

        // STMO: 10 moods x 4 quartiles
        var moodScores: [Int] = []
        for m in 0..<10 {
            let entryOffset = m * 16 + 3
            if entryOffset < stmoData.count {
                moodScores.append(Int(stmoData[entryOffset]))
            } else {
                moodScores.append(50)
            }
        }

        // Derived Valence & Arousal
        let posArousal = Double(moodScores[0] + moodScores[6] + moodScores[7]) / 300.0
        let negArousal = Double(moodScores[1] + moodScores[3]) / 200.0
        let arousal = max(-1.0, min(1.0, (posArousal - negArousal) * 2.0)).rounded(toPlaces: 2)

        let posValence = (Double(moodScores[2]) * 1.5 + Double(moodScores[1]) + Double(moodScores[5])) / 350.0
        let negValence = (Double(moodScores[4]) * 1.5 + Double(moodScores[7]) * 0.5) / 200.0
        let valence = max(-1.0, min(1.0, (posValence - negValence) * 1.8)).rounded(toPlaces: 2)

        // Channels
        var channels: [String] = []
        if arousal >= 0.35 && valence >= 0.15 && bpm >= 115 {
            channels.append("Energetic")
        }
        if arousal <= -0.15 && valence >= -0.30 && bpm <= 105 {
            channels.append("Relax")
        }
        if valence >= 0.20 && arousal >= -0.10 && arousal <= 0.65 {
            channels.append("Upbeat")
        }
        if arousal >= -0.75 && arousal <= 0.0 && valence >= -0.35 && valence <= 0.45 {
            channels.append("Mellow")
        }
        if moodScores[4] >= 45 || (valence <= -0.10 && arousal >= -0.55 && arousal <= 0.40) {
            channels.append("Emotional")
        }
        if arousal >= 0.65 || moodScores[7] >= 65 {
            channels.append("Extreme")
        }
        if moodScores[6] >= 50 || (bpm >= 108 && bpm <= 138 && arousal >= 0.25) {
            channels.append("Dance")
        }
        if moodScores[5] >= 50 || (bpm >= 80 && bpm <= 118 && arousal >= -0.40 && arousal <= 0.30) {
            channels.append("Lounge")
        }
        if moodScores[8] >= 55 {
            channels.append("Acoustic")
        }
        if moodScores[9] >= 60 {
            channels.append("Electronic")
        }

        // Time of Day
        if channels.contains("Upbeat") || channels.contains("Relax") || valence > 0.1 {
            channels.append("Daytime")
        }
        if channels.contains("Mellow") || channels.contains("Relax") || channels.contains("Lounge") {
            channels.append("Evening")
        }
        if channels.contains("Relax") || channels.contains("Mellow") || arousal <= -0.10 {
            channels.append("Midnight")
        }
        if channels.contains("Upbeat") || channels.contains("Acoustic") || channels.contains("Relax") {
            channels.append("Morning")
        }

        var uniqueChannels: [String] = []
        for c in channels {
            if !uniqueChannels.contains(c) { uniqueChannels.append(c) }
        }

        return SenseMeInfo(
            isAnalyzed: true,
            bpm: bpm,
            rawBpm: rawBpm,
            valence: valence,
            arousal: arousal,
            moodScores: moodScores,
            channels: uniqueChannels,
            highlightSec: highlightSec
        )
    }

    // -----------------------------------------------------------------------
    // 3. Binary Payload Builder (Pure Swift)
    // -----------------------------------------------------------------------
    public func buildSMFMPayload(
        bpm: Double,
        moodScores: [Int],
        highlightMs: Int,
        template: Data = SenseMeEngine.templateData
    ) -> Data {
        guard moodScores.count == 10, template.count >= 3270 else {
            return Data()
        }

        var payload = Data()
        payload.append(contentsOf: [0x53, 0x4D, 0x46, 0x4D]) // "SMFM"

        func makeHeader(tag: String, length: Int) -> Data {
            var h = Data(tag.utf8)
            h.append(contentsOf: [0x53, 0x54, 0x41, 0x45]) // STAE
            h.append(contentsOf: [0x4D, 0x4D, 0x4C, 0x57]) // MMLW
            h.append(contentsOf: [0x01, 0x00, 0x80, 0x00]) // Flags
            let uLen = UInt32(length)
            h.append(contentsOf: [
                UInt8((uLen >> 24) & 0xFF), UInt8((uLen >> 16) & 0xFF), UInt8((uLen >> 8) & 0xFF), UInt8(uLen & 0xFF)
            ])
            return h
        }

        // 1. GBPM (4 bytes)
        let bpmFloat = Float(bpm > 75.0 ? bpm / 2.0 : bpm)
        var bpmBits = bpmFloat.bitPattern.bigEndian
        let gbpmData = Data(bytes: &bpmBits, count: 4)
        payload.append(makeHeader(tag: "GBPM", length: 4))
        payload.append(gbpmData)

        // 2. STBF (36 bytes from template)
        let stbfStart = 4 + 20 + 4 + 20
        let stbfData = template.subdata(in: stbfStart..<stbfStart + 36)
        payload.append(makeHeader(tag: "STBF", length: 36))
        payload.append(stbfData)

        // 3. STSA (8 bytes: 2 x UInt32 ms)
        var msVal = UInt32(highlightMs).bigEndian
        var stsaData = Data()
        stsaData.append(Data(bytes: &msVal, count: 4))
        stsaData.append(Data(bytes: &msVal, count: 4))
        payload.append(makeHeader(tag: "STSA", length: 8))
        payload.append(stsaData)

        // 4. STMO (160 bytes: 10 moods x 4 quartiles)
        var stmoData = Data()
        for m in 0..<10 {
            let score = UInt8(max(0, min(100, moodScores[m])))
            for q in 0..<4 {
                stmoData.append(contentsOf: [0x01, UInt8(m), UInt8(q), score])
            }
        }
        payload.append(makeHeader(tag: "STMO", length: 160))
        payload.append(stmoData)

        // 5. STHF (160 bytes from template)
        let sthfStart = 4 + 20 + 4 + 20 + 36 + 20 + 8 + 20 + 160 + 20
        let sthfData = template.subdata(in: sthfStart..<sthfStart + 160)
        payload.append(makeHeader(tag: "STHF", length: 160))
        payload.append(sthfData)

        // 6. STMM (2778 bytes from template with updated BPM)
        let stmmStart = 4 + 20 + 4 + 20 + 36 + 20 + 8 + 20 + 160 + 20 + 160 + 20
        var stmmData = template.subdata(in: stmmStart..<stmmStart + 2778)
        stmmData.replaceSubrange(32..<36, with: gbpmData)
        stmmData.replaceSubrange(90..<94, with: gbpmData)
        payload.append(makeHeader(tag: "STMM", length: 2778))
        payload.append(stmmData)

        return payload
    }

    // -----------------------------------------------------------------------
    // 4. Non-Destructive Injection (Pure Swift)
    // -----------------------------------------------------------------------
    public func injectFLAC(fileURL: URL, payload: Data) throws {
        let fileData = try Data(contentsOf: fileURL)
        guard fileData.count >= 4 && fileData.starts(with: [0x66, 0x4C, 0x61, 0x43]) else {
            throw NSError(domain: "SenseMeEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a valid FLAC file"])
        }

        var offset = 4
        var isLast = false
        var blocks: [(type: Int, data: Data)] = []

        while !isLast && offset + 4 <= fileData.count {
            let b0 = fileData[offset]
            isLast = (b0 & 0x80) != 0
            let bType = Int(b0 & 0x7F)
            let bLen = (Int(fileData[offset+1]) << 16) | (Int(fileData[offset+2]) << 8) | Int(fileData[offset+3])
            offset += 4
            guard offset + bLen <= fileData.count else { break }
            let bData = fileData.subdata(in: offset..<offset+bLen)
            offset += bLen
            blocks.append((bType, bData))
        }

        let audioFrames = fileData.subdata(in: offset..<fileData.count)

        // Filter out existing SMFM application block
        var newBlocks: [(type: Int, data: Data)] = []
        var inserted = false

        for (bType, bData) in blocks {
            if bType == 2 && bData.starts(with: [0x53, 0x4D, 0x46, 0x4D]) {
                continue
            }
            if bType == 1 && !inserted { // PADDING
                newBlocks.append((2, payload))
                inserted = true
            }
            newBlocks.append((bType, bData))
        }

        if !inserted {
            newBlocks.append((2, payload))
        }

        var outData = Data([0x66, 0x4C, 0x61, 0x43])
        for i in 0..<newBlocks.count {
            let isFinal = (i == newBlocks.count - 1)
            let bType = newBlocks[i].type
            let bData = newBlocks[i].data
            let b0 = (isFinal ? 0x80 : 0x00) | UInt8(bType & 0x7F)
            let bLen = bData.count
            outData.append(contentsOf: [
                b0, UInt8((bLen >> 16) & 0xFF), UInt8((bLen >> 8) & 0xFF), UInt8(bLen & 0xFF)
            ])
            outData.append(bData)
        }
        outData.append(audioFrames)

        let tmpURL = fileURL.appendingPathExtension("tmp")
        try outData.write(to: tmpURL, options: .atomic)
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tmpURL, to: fileURL)
    }

    // -----------------------------------------------------------------------
    // 5. High-Level DSP Analysis & Injection Execution
    // -----------------------------------------------------------------------
    public func analyzeAndInject(fileURL: URL) async throws -> SenseMeInfo {
        let currentDir = FileManager.default.currentDirectoryPath
        let possiblePythons = [
            currentDir + "/venv/bin/python3",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.walkman_venv/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        var pythonBin: String? = nil
        for p in possiblePythons {
            if FileManager.default.fileExists(atPath: p) {
                pythonBin = p
                break
            }
        }

        guard let py = pythonBin else {
            throw NSError(domain: "SenseMeEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Python 3 environment not found for 12 Tone DSP analysis"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: py)
                proc.currentDirectoryURL = URL(fileURLWithPath: currentDir)
                proc.arguments = [
                    "-m", "backend.senseme_engine",
                    "analyze", fileURL.path,
                    "--inject"
                ]

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    if proc.terminationStatus != 0 {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NSError(domain: "SenseMeEngine", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "DSP Analysis failed: \(errStr)"]))
                        return
                    }

                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(SenseMeInfo.self, from: outData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

fileprivate extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
