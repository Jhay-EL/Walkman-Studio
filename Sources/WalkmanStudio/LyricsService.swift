import Foundation

public struct LyricsResult: Sendable {
    public let synced: Bool
    public let lyrics: String
    public let source: String
}

public enum LyricsError: LocalizedError {
    case notFound
    case invalidResponse
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No lyrics found online for this song."
        case .invalidResponse:
            return "Invalid lyrics data received."
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

/// Service to automatically search and fetch synchronized (.LRC) and plain lyrics from public music databases.
public final class LyricsService: @unchecked Sendable {
    public static let shared = LyricsService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Cleans fluff from track titles such as leading track numbers ("01. "), "(feat. X)", "(Official Video)", "[Remastered]", etc.
    public static func cleanTrackTitle(_ title: String, artist: String? = nil) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Strip audio file extensions if present in title
        t = t.replacingOccurrences(
            of: #"\.(flac|mp3|m4a|wav|aac|ogg|wma|aiff?)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 2. Strip leading disc/track numbers (e.g. "01. ", "02 - ", "1-03 ", "01 ")
        t = t.replacingOccurrences(
            of: #"^(\d+[-_])?\d+[\s\.\-_]+"#,
            with: "",
            options: .regularExpression
        )

        // 3. Strip artist prefix if repeated in the title (e.g. "Harry Styles - Sign of the Times")
        if let art = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !art.isEmpty {
            let artLower = art.lowercased()
            let tLower = t.lowercased()
            for sep in [" - ", " – ", " — ", " : ", ": "] {
                let prefix = artLower + sep
                if tLower.hasPrefix(prefix) {
                    t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // 4. Remove feat / ft
        t = t.replacingOccurrences(
            of: #"\s*[\(\[](feat\.|ft\.|featuring).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 5. Remove video / audio / visualizer / lyric video
        t = t.replacingOccurrences(
            of: #"\s*[\(\[](official|music video|video|audio|lyrics? video|visualizer|hd|4k|hq).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 6. Remove remaster / deluxe / version / edit
        t = t.replacingOccurrences(
            of: #"\s*[\(\[](remaster|remastered|deluxe|bonus|anniversary|version|edit|mono|stereo|radio edit).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 7. Strip surrounding quotes if any
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetches lyrics (preferring synchronized .LRC with timestamps) for a track.
    public func fetchLyrics(
        title: String,
        artist: String,
        album: String = "",
        durationSeconds: Double = 0
    ) async throws -> LyricsResult {
        let cleanTitle = Self.cleanTrackTitle(title, artist: artist)
        let primaryArtist = Track.parsePrimaryAndFeaturedArtist(from: artist).primary

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&?/#%")

        // 1. Try LRCLIB exact match with clean title and primary artist (no strict album to prevent 503)
        if let result = await queryLrclibExact(
            title: cleanTitle,
            artist: primaryArtist,
            allowedChars: allowed
        ) {
            return result
        }

        // 2. Try LRCLIB search (fuzzy matching across synced lyrics)
        if let result = await queryLrclibSearch(
            title: cleanTitle,
            artist: primaryArtist,
            duration: durationSeconds,
            allowedChars: allowed
        ) {
            return result
        }

        // 3. Try LRCLIB search with original raw title if cleanTitle was different
        if cleanTitle != title {
            if let result = await queryLrclibSearch(
                title: title,
                artist: primaryArtist,
                duration: durationSeconds,
                allowedChars: allowed
            ) {
                return result
            }
        }

        // 4. Fallback to Lyrics.ovh for plain text lyrics
        if let result = await queryLyricsOvh(
            title: cleanTitle,
            artist: primaryArtist,
            allowedChars: allowed
        ) {
            return result
        }

        throw LyricsError.notFound
    }

    // MARK: - LRCLIB Exact Query
    private func queryLrclibExact(
        title: String,
        artist: String,
        allowedChars: CharacterSet
    ) async -> LyricsResult? {
        guard let encTitle = title.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let encArtist = artist.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let url = URL(string: "https://lrclib.net/api/get?track_name=\(encTitle)&artist_name=\(encArtist)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0 (https://github.com/Jhay-EL/Walkman-Studio)", forHTTPHeaderField: "User-Agent")

        // First attempt
        if let res = await executeLrclibRequest(request) {
            return res
        }

        // Brief retry on 503 / transient error
        try? await Task.sleep(nanoseconds: 350_000_000)
        return await executeLrclibRequest(request)
    }

    private func executeLrclibRequest(_ request: URLRequest) async -> LyricsResult? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractFromLrclibDict(json)
    }

    // MARK: - LRCLIB Search Query
    private func queryLrclibSearch(
        title: String,
        artist: String,
        duration: Double,
        allowedChars: CharacterSet
    ) async -> LyricsResult? {
        let searchQuery = "\(artist) \(title)"
        guard let encQ = searchQuery.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encQ)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0 (https://github.com/Jhay-EL/Walkman-Studio)", forHTTPHeaderField: "User-Agent")

        var list = await executeLrclibSearchRequest(request)
        if list == nil {
            try? await Task.sleep(nanoseconds: 350_000_000)
            list = await executeLrclibSearchRequest(request)
        }

        guard let results = list, !results.isEmpty else {
            return nil
        }

        // Prioritize candidates with syncedLyrics and close duration
        let sorted = results.sorted { a, b in
            let aSynced = (a["syncedLyrics"] as? String)?.isEmpty == false
            let bSynced = (b["syncedLyrics"] as? String)?.isEmpty == false
            if aSynced != bSynced {
                return aSynced && !bSynced
            }
            if duration > 10 {
                let aDur = a["duration"] as? Double ?? 0
                let bDur = b["duration"] as? Double ?? 0
                return abs(aDur - duration) < abs(bDur - duration)
            }
            return false
        }

        for item in sorted {
            if let res = extractFromLrclibDict(item) {
                return res
            }
        }

        return nil
    }

    private func executeLrclibSearchRequest(_ request: URLRequest) async -> [[String: Any]]? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return list
    }

    private func extractFromLrclibDict(_ dict: [String: Any]) -> LyricsResult? {
        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(synced: true, lyrics: synced, source: "LRCLIB (Synced)")
        }
        if let plain = dict["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(synced: false, lyrics: plain, source: "LRCLIB (Plain)")
        }
        if let isInstrumental = dict["instrumental"] as? Bool, isInstrumental {
            return LyricsResult(synced: false, lyrics: "[00:00.00] (Instrumental)", source: "LRCLIB (Instrumental)")
        }
        return nil
    }

    // MARK: - Lyrics.ovh Fallback
    private func queryLyricsOvh(
        title: String,
        artist: String,
        allowedChars: CharacterSet
    ) async -> LyricsResult? {
        guard let encArtist = artist.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let encTitle = title.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encArtist)/\(encTitle)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["lyrics"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return LyricsResult(synced: false, lyrics: text.trimmingCharacters(in: .whitespacesAndNewlines), source: "Lyrics.ovh")
    }
}
