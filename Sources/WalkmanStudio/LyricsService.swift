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

    private static let allowedQueryChars: CharacterSet = {
        var c = CharacterSet.urlQueryAllowed
        c.remove(charactersIn: "+&?/#%")
        return c
    }()

    private init() {}

    /// Checks whether an artist name is a generic placeholder like "Unknown Artist" or "Various Artists"
    public static func isPlaceholderArtist(_ artist: String) -> Bool {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let placeholders: Set<String> = [
            "unknown", "unknown artist", "various artists", "various", "va",
            "artiest onbekend", "desconhecido", "unbekannt", "inconnu", "artista desconocido"
        ]
        return placeholders.contains(trimmed)
    }

    /// Infers artist and title if artist is placeholder and title is formatted like "Artist - Title"
    public static func inferArtistAndTitle(title: String, artist: String) -> (artist: String, title: String) {
        let cleanArt = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isPlaceholderArtist(cleanArt) {
            return (cleanArt, title)
        }
        for sep in [" - ", " – ", " — "] {
            if title.contains(sep) {
                let parts = title.components(separatedBy: sep)
                if parts.count >= 2 {
                    let inferredArt = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let inferredTitle = parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inferredArt.isEmpty && !inferredTitle.isEmpty && !isPlaceholderArtist(inferredArt) {
                        return (inferredArt, inferredTitle)
                    }
                }
            }
        }
        return ("", title)
    }

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

        // 3. Strip artist prefix if repeated in the title (e.g. "Bruno Mars - It Will Rain")
        if let art = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !art.isEmpty {
            let primary = Track.parsePrimaryAndFeaturedArtist(from: art).primary.trimmingCharacters(in: .whitespacesAndNewlines)
            let artParts = art.components(separatedBy: CharacterSet(charactersIn: ";,")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var candidates = [art, primary] + artParts
            candidates = candidates.filter { !$0.isEmpty }
            for c in candidates {
                let cLower = c.lowercased()
                let tLower = t.lowercased()
                for sep in [" - ", " – ", " — ", " : ", ": "] {
                    let prefix = cLower + sep
                    if tLower.hasPrefix(prefix) {
                        t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }

        // 4. Remove feat / ft
        t = t.replacingOccurrences(
            of: #"\s*[\(\[].*?(feat\.|ft\.|featuring).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 5. Remove video / audio / visualizer / lyric video
        t = t.replacingOccurrences(
            of: #"\s*[\(\[].*?(official|music video|video|audio|lyrics? video|visualizer|hd|4k|hq).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 6. Remove remaster / deluxe / version / edit
        t = t.replacingOccurrences(
            of: #"\s*[\(\[].*?(remaster|remastered|deluxe|bonus|anniversary|version|edit|mono|stereo|radio edit).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 7. Remove live / acoustic / remix / session / festival / tour / explicit
        t = t.replacingOccurrences(
            of: #"\s*[\(\[].*?(live|acoustic|piano|remix|mix|session|unplugged|orchestral|festival|tour|explicit).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // 8. Strip surrounding quotes if any
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fetches lyrics (preferring synchronized .LRC with timestamps) for a track concurrently in under 2 seconds.
    public func fetchLyrics(
        title: String,
        artist: String,
        album: String = "",
        durationSeconds: Double = 0
    ) async throws -> LyricsResult {
        let (inferredArtist, rawTitle) = Self.inferArtistAndTitle(title: title, artist: artist)
        let cleanTitle = Self.cleanTrackTitle(rawTitle, artist: inferredArtist)
        let primaryArtist = inferredArtist.isEmpty ? "" : Track.parsePrimaryAndFeaturedArtist(from: inferredArtist).primary
        let allowed = Self.allowedQueryChars

        // 1. Direct indexed match via LRCLIB /api/get (ultra-fast, indexed B-tree, avoids /api/search 503 limits)
        if !primaryArtist.isEmpty && !cleanTitle.isEmpty {
            if let getRes = await queryLrclibGet(title: cleanTitle, artist: primaryArtist, album: album, duration: durationSeconds), getRes.synced {
                return getRes
            }
            if let looseRes = await queryLrclibGetLoose(title: cleanTitle, artist: primaryArtist), looseRes.synced {
                return looseRes
            }
        }

        // 2. Concurrently query LRCLIB fuzzy search and Lyrics.ovh fallback
        async let lrclibTask = queryLrclibSearch(
            title: cleanTitle,
            artist: primaryArtist,
            duration: durationSeconds,
            allowedChars: allowed
        )
        async let ovhTask = queryLyricsOvh(
            title: cleanTitle,
            artist: primaryArtist,
            allowedChars: allowed
        )

        // Prioritize synced lyrics from LRCLIB if available
        let lrcResult = await lrclibTask
        if let res = lrcResult, res.synced {
            return res
        }

        // If cleanTitle didn't yield synced lyrics, check raw title in case it has a specific synced entry
        if cleanTitle != title && !primaryArtist.isEmpty {
            if let rawLoose = await queryLrclibGetLoose(title: title, artist: primaryArtist), rawLoose.synced {
                return rawLoose
            }
            if let rawResult = await queryLrclibSearch(
                title: title,
                artist: primaryArtist,
                duration: durationSeconds,
                allowedChars: allowed
            ), rawResult.synced {
                return rawResult
            }
        }

        // Direct match plain lyrics from /api/get loose
        if !primaryArtist.isEmpty && !cleanTitle.isEmpty {
            if let looseRes = await queryLrclibGetLoose(title: cleanTitle, artist: primaryArtist), !looseRes.lyrics.isEmpty {
                return looseRes
            }
        }

        // Plain lyrics from LRCLIB search
        if let res = lrcResult, !res.lyrics.isEmpty {
            return res
        }

        // Fast plain fallback: Lyrics.ovh
        if let ovhResult = await ovhTask {
            return ovhResult
        }

        // Fallback with raw title if cleaned title differed
        if cleanTitle != title && !primaryArtist.isEmpty {
            if let rawGet = await queryLrclibGetLoose(title: title, artist: primaryArtist) {
                return rawGet
            }
            if let rawResult = await queryLrclibSearch(
                title: title,
                artist: primaryArtist,
                duration: durationSeconds,
                allowedChars: allowed
            ) {
                return rawResult
            }
        }

        // 4. Fallback: try title-only query if artist was missing, placeholder, or mismatched
        if let titleOnlyRes = await queryLrclibSearch(
            title: cleanTitle,
            artist: "",
            duration: durationSeconds,
            allowedChars: allowed
        ) {
            return titleOnlyRes
        }

        throw LyricsError.notFound
    }

    // MARK: - Safe Network Execution with HTTP 429 Rate-Limit Retry
    private func executeRequest(_ request: URLRequest, retryOnRateLimit: Bool = true) async -> (Data, HTTPURLResponse)? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 429 && retryOnRateLimit {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return await executeRequest(request, retryOnRateLimit: false)
            }
            guard http.statusCode == 200 else { return nil }
            return (data, http)
        } catch {
            return nil
        }
    }

    // MARK: - LRCLIB Direct Indexed Get Query
    private func queryLrclibGet(
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) async -> LyricsResult? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 10 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0 (https://github.com/Jhay-EL/Walkman-Studio)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = await executeRequest(request),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractFromLrclibDict(dict)
    }

    private func queryLrclibGetLoose(
        title: String,
        artist: String
    ) async -> LyricsResult? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        comps?.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        guard let url = comps?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0 (https://github.com/Jhay-EL/Walkman-Studio)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = await executeRequest(request),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractFromLrclibDict(dict)
    }

    // MARK: - LRCLIB Search Query
    private func queryLrclibSearch(
        title: String,
        artist: String,
        duration: Double,
        allowedChars: CharacterSet
    ) async -> LyricsResult? {
        let searchQuery = artist.isEmpty ? title : "\(artist) \(title)"
        guard let encQ = searchQuery.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encQ)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0 (https://github.com/Jhay-EL/Walkman-Studio)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = await executeRequest(request),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty else {
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

    private func extractFromLrclibDict(_ dict: [String: Any]) -> LyricsResult? {
        if let synced = dict["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(synced: true, lyrics: synced, source: "LRCLIB (Synced)")
        }
        if let isInstrumental = dict["instrumental"] as? Bool, isInstrumental {
            return LyricsResult(synced: true, lyrics: "[00:00.00]♪ Instrumental ♪\r\n", source: "LRCLIB (Instrumental)")
        }
        if let plain = dict["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(synced: false, lyrics: plain, source: "LRCLIB (Plain)")
        }
        return nil
    }

    // MARK: - Lyrics.ovh Fallback
    private func queryLyricsOvh(
        title: String,
        artist: String,
        allowedChars: CharacterSet
    ) async -> LyricsResult? {
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        guard let encArtist = artist.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let encTitle = title.addingPercentEncoding(withAllowedCharacters: allowedChars),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encArtist)/\(encTitle)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = await executeRequest(request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["lyrics"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return LyricsResult(synced: false, lyrics: text.trimmingCharacters(in: .whitespacesAndNewlines), source: "Lyrics.ovh")
    }
}
