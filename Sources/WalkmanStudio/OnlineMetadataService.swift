import Foundation
import CoreGraphics
import ImageIO
import AppKit

public struct OnlineTrackMetadata: Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let trackNumber: String
    public let year: String
    public let genre: String
    public let artworkData: Data?
    public let artworkURL: URL?
    public let source: String

    public init(
        title: String,
        artist: String,
        album: String,
        trackNumber: String = "",
        year: String = "",
        genre: String = "",
        artworkData: Data? = nil,
        artworkURL: URL? = nil,
        source: String = "iTunes"
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.year = year
        self.genre = genre
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.source = source
    }
}

/// Service to query public music databases (Apple iTunes Search API & Deezer API)
/// to fetch track metadata (Title, Artist, Album, Track #, Year, Genre) and high-resolution album artwork.
public final class OnlineMetadataService: @unchecked Sendable {
    public static let shared = OnlineMetadataService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 12.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Cleans a raw filename or title string into clean search terms
    public static func cleanSearchTerms(filename: String, title: String? = nil, artist: String? = nil) -> (title: String, artist: String, query: String) {
        let cleanTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanTitle.isEmpty && cleanTitle.lowercased() != "unknown" && cleanTitle.lowercased() != "unknown title" && cleanTitle.lowercased() != "unknown track" {
            let sanitizedT = WalkmanEngine.sanitizeWalkmanText(cleanTitle)
            let art = (cleanArtist.isEmpty || cleanArtist.lowercased() == "unknown artist" || cleanArtist.lowercased() == "unknown") ? "" : WalkmanEngine.sanitizeWalkmanText(cleanArtist, stripExplicitMarkers: false)
            let q = art.isEmpty ? sanitizedT : "\(sanitizedT) \(art)"
            return (sanitizedT, art, q)
        }

        // Clean filename
        var stem = filename
        stem = stem.replacingOccurrences(
            of: #"\.(flac|mp3|m4a|wav|aac|ogg|wma|aiff?|dsf|dff)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip leading track numbers like "01. ", "02 - ", "1-03 ", "01 "
        stem = stem.replacingOccurrences(
            of: #"^(\d+[-_])?\d+[\s\.\-_]+"#,
            with: "",
            options: .regularExpression
        )

        // Strip web / video junk like [Official Video], (Lyrics), (Audio), [Remastered 2021], etc., as well as explicit badges
        stem = stem.replacingOccurrences(
            of: #"\s*[\(\[](official\s*(music\s*)?video|video|audio|lyrics?(\s*video)?|visualizer|hd|4k|hq|remaster(ed)?|deluxe|bonus|anniversary|edit|radio\s*edit|explicit(\s*content)?|e).*?[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        stem = WalkmanEngine.sanitizeWalkmanText(stem)

        // If stem contains " - ", it's usually "Artist - Title" or "Title - Artist"
        if stem.contains(" - ") {
            let parts = stem.components(separatedBy: " - ")
            if parts.count >= 2 {
                let p0 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let p1 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let isP0Unknown = p0.isEmpty || p0.lowercased() == "unknown" || p0.lowercased() == "unknown artist"
                let isP1Unknown = p1.isEmpty || p1.lowercased() == "unknown" || p1.lowercased() == "unknown track" || p1.lowercased() == "unknown title"

                if !isP1Unknown && !isP0Unknown {
                    return (p1, p0, "\(p0) \(p1)")
                } else if !isP1Unknown {
                    return (p1, "", p1)
                } else if !isP0Unknown {
                    return (p0, "", p0)
                }
            }
        }

        let q = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.lowercased() == "unknown" || q.lowercased() == "unknown track" || q.lowercased() == "unknown title" || q.lowercased() == "unknown artist" {
            return ("", "", "")
        }
        return (q, "", q)
    }

    /// Fetches metadata and artwork online for a track.
    public func fetchMetadata(
        filename: String,
        currentTitle: String? = nil,
        currentArtist: String? = nil,
        currentAlbum: String? = nil
    ) async -> OnlineTrackMetadata? {
        let terms = Self.cleanSearchTerms(filename: filename, title: currentTitle, artist: currentArtist)
        let query = terms.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        // 1. Try iTunes Search API
        if let itunesResult = await queryiTunes(query: query, expectedTitle: terms.title, expectedArtist: terms.artist) {
            return itunesResult
        }

        // 2. Try Deezer API Fallback
        if let deezerResult = await queryDeezer(query: query, expectedTitle: terms.title, expectedArtist: terms.artist) {
            return deezerResult
        }

        // 3. Fallback: try title-only query if we had an artist attached that might have missed
        if !terms.artist.isEmpty && !terms.title.isEmpty && terms.title != query {
            if let looseResult = await queryiTunes(query: terms.title, expectedTitle: terms.title, expectedArtist: "") {
                return looseResult
            }
        }

        return nil
    }

    /// Fetches high-res cover art specifically for given track info
    public func fetchArtworkOnly(title: String, artist: String, album: String = "") async -> Data? {
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        if let itunes = await queryiTunes(query: query, expectedTitle: title, expectedArtist: artist), let data = itunes.artworkData {
            return data
        }
        if let deezer = await queryDeezer(query: query, expectedTitle: title, expectedArtist: artist), let data = deezer.artworkData {
            return data
        }
        return nil
    }

    // MARK: - iTunes Search API
    private func queryiTunes(query: String, expectedTitle: String, expectedArtist: String) async -> OnlineTrackMetadata? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&?/#%")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=5") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6.0

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty else {
            return nil
        }

        // Find the best match or take first
        let best = pickBestMatch(results: results, expectedTitle: expectedTitle, expectedArtist: expectedArtist) ?? results[0]

        let rawTitle = (best["trackName"] as? String) ?? (best["collectionName"] as? String) ?? ""
        let cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTitleBogus = cleanTitle.isEmpty || cleanTitle.lowercased() == "unknown" || cleanTitle.lowercased() == "unknown track" || cleanTitle.lowercased() == "unknown title"

        let resolvedTitle: String
        if !isTitleBogus {
            resolvedTitle = cleanTitle
        } else if !expectedTitle.isEmpty && expectedTitle.lowercased() != "unknown" && expectedTitle.lowercased() != "unknown track" && expectedTitle.lowercased() != "unknown title" {
            resolvedTitle = expectedTitle
        } else {
            resolvedTitle = ""
        }

        let artist = (best["artistName"] as? String) ?? ""
        let album = (best["collectionName"] as? String) ?? ""
        let trackNum = (best["trackNumber"] as? Int).map { String($0) } ?? "1"
        let genre = (best["primaryGenreName"] as? String) ?? ""
        
        var year = ""
        if let releaseDate = best["releaseDate"] as? String, releaseDate.count >= 4 {
            year = String(releaseDate.prefix(4))
        }

        // High resolution artwork: replace 100x100bb.jpg with 800x800bb.jpg
        var artworkData: Data? = nil
        var artworkURL: URL? = nil

        if let art100 = best["artworkUrl100"] as? String {
            let highResStr = art100
                .replacingOccurrences(of: "100x100bb.jpg", with: "800x800bb.jpg")
                .replacingOccurrences(of: "100x100bb.png", with: "800x800bb.jpg")
                .replacingOccurrences(of: "60x60bb.jpg", with: "800x800bb.jpg")
            
            if let artURL = URL(string: highResStr) {
                artworkURL = artURL
                artworkData = await downloadImage(from: artURL)
            }
        }

        return OnlineTrackMetadata(
            title: WalkmanEngine.sanitizeWalkmanText(resolvedTitle),
            artist: WalkmanEngine.sanitizeWalkmanText(artist.isEmpty ? "Unknown Artist" : artist, stripExplicitMarkers: false),
            album: WalkmanEngine.sanitizeWalkmanText(album.isEmpty ? "Unknown Album" : album),
            trackNumber: trackNum,
            year: year,
            genre: genre,
            artworkData: artworkData,
            artworkURL: artworkURL,
            source: "iTunes"
        )
    }

    // MARK: - Deezer Search API
    private func queryDeezer(query: String, expectedTitle: String, expectedArtist: String) async -> OnlineTrackMetadata? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&?/#%")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=5") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("WalkmanStudio/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6.0

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]], !list.isEmpty else {
            return nil
        }

        let first = list[0]
        let rawTitle = (first["title"] as? String) ?? ""
        let cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTitleBogus = cleanTitle.isEmpty || cleanTitle.lowercased() == "unknown" || cleanTitle.lowercased() == "unknown track" || cleanTitle.lowercased() == "unknown title"

        let resolvedTitle: String
        if !isTitleBogus {
            resolvedTitle = cleanTitle
        } else if !expectedTitle.isEmpty && expectedTitle.lowercased() != "unknown" && expectedTitle.lowercased() != "unknown track" && expectedTitle.lowercased() != "unknown title" {
            resolvedTitle = expectedTitle
        } else {
            resolvedTitle = ""
        }

        let artistObj = first["artist"] as? [String: Any]
        let artist = (artistObj?["name"] as? String) ?? ""
        let albumObj = first["album"] as? [String: Any]
        let album = (albumObj?["title"] as? String) ?? ""
        
        var artworkData: Data? = nil
        var artworkURL: URL? = nil

        let coverStr = (albumObj?["cover_xl"] as? String)
            ?? (albumObj?["cover_big"] as? String)
            ?? (albumObj?["cover_medium"] as? String)

        if let cStr = coverStr, let cURL = URL(string: cStr) {
            artworkURL = cURL
            artworkData = await downloadImage(from: cURL)
        }

        return OnlineTrackMetadata(
            title: WalkmanEngine.sanitizeWalkmanText(resolvedTitle),
            artist: WalkmanEngine.sanitizeWalkmanText(artist.isEmpty ? "Unknown Artist" : artist, stripExplicitMarkers: false),
            album: WalkmanEngine.sanitizeWalkmanText(album.isEmpty ? "Unknown Album" : album),
            trackNumber: "1",
            year: "",
            genre: "",
            artworkData: artworkData,
            artworkURL: artworkURL,
            source: "Deezer"
        )
    }

    private func pickBestMatch(results: [[String: Any]], expectedTitle: String, expectedArtist: String) -> [String: Any]? {
        let tLow = WalkmanEngine.sanitizeWalkmanText(expectedTitle).lowercased()
        let aLow = WalkmanEngine.sanitizeWalkmanText(expectedArtist, stripExplicitMarkers: false).lowercased()
        guard !tLow.isEmpty || !aLow.isEmpty else { return results.first }

        for item in results {
            let itemT = WalkmanEngine.sanitizeWalkmanText(item["trackName"] as? String ?? "").lowercased()
            let itemA = WalkmanEngine.sanitizeWalkmanText(item["artistName"] as? String ?? "", stripExplicitMarkers: false).lowercased()

            if !tLow.isEmpty && !aLow.isEmpty {
                if (itemT == tLow || itemT.contains(tLow) || tLow.contains(itemT)) && (itemA == aLow || itemA.contains(aLow) || aLow.contains(itemA)) {
                    return item
                }
            } else if !tLow.isEmpty {
                if itemT == tLow || itemT.contains(tLow) || tLow.contains(itemT) {
                    return item
                }
            } else if !aLow.isEmpty {
                if itemA == aLow || itemA.contains(aLow) || aLow.contains(itemA) {
                    return item
                }
            }
        }
        return results.first
    }

    private func downloadImage(from url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 7.0
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              data.count > 1024 else {
            return nil
        }
        return data
    }
}
