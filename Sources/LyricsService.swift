import Foundation

struct LrcEntry: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

struct LyricsPayload {
    let lines: [LyricLine]
    let synced: Bool
    let matchedTitle: String
    let matchedDuration: Double
}

enum LyricsService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    static func search(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        completion: @escaping (Result<LyricsPayload, Error>) -> Void
    ) -> URLSessionDataTask? {
        request(title: title, artist: artist, duration: duration, fallback: false) { result in
            switch result {
            case .success(let payload):
                completion(.success(payload))
            case .failure(let error):
                // Second attempt with a cleaned-up title (feat/remaster/ao vivo noise)
                let cleaned = clean(title)
                if cleaned != title {
                    _ = request(title: cleaned, artist: artist, duration: duration, fallback: true) { retry in
                        switch retry {
                        case .success(let payload): completion(.success(payload))
                        case .failure: completion(.failure(error))
                        }
                    }
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    @discardableResult
    private static func request(
        title: String,
        artist: String,
        duration: Double,
        fallback: Bool,
        completion: @escaping (Result<LyricsPayload, Error>) -> Void
    ) -> URLSessionDataTask? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components.url else {
            completion(.failure(LyricsError.badURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("SpotifyLyricsPiP/0.1 (https://github.com/arrezende)", forHTTPHeaderField: "User-Agent")
        request.setValue("SpotifyLyricsPiP/0.1", forHTTPHeaderField: "Lrclib-Client")

        let task = session.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(LyricsError.empty)) }
                return
            }
            do {
                let entries = try JSONDecoder().decode([LrcEntry].self, from: data)
                if ProcessInfo.processInfo.environment["LYRICS_DEBUG"] != nil {
                    print("     [debug] status-bytes=\(data.count) entries=\(entries.count) url=\(url.absoluteString)")
                }
                let payload = best(from: entries, title: title, artist: artist, duration: duration)
                DispatchQueue.main.async { completion(.success(payload)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
        return task
    }

    // MARK: - Matching

    private static func best(from entries: [LrcEntry], title: String, artist: String, duration: Double) -> LyricsPayload {
        var scored: [(LrcEntry, Double)] = []
        for entry in entries {
            var score = 0.0
            if let d = entry.duration {
                let diff = abs(d - duration)
                score -= min(diff, 120) * 2.5
                if diff <= 3 { score += 40 }
            }
            if entry.syncedLyrics != nil { score += 60 }
            let nt = norm(entry.trackName ?? "")
            let nq = norm(title)
            if nt == nq { score += 35 }
            else if !nt.isEmpty && (nt.contains(nq) || nq.contains(nt)) { score += 12 }
            let na = norm(entry.artistName ?? "")
            let nqa = norm(artist)
            if !na.isEmpty && !nqa.isEmpty && (na.contains(nqa) || nqa.contains(na)) { score += 25 }
            scored.append((entry, score))
        }
        guard let winner = scored.max(by: { $0.1 < $1.1 })?.0 else {
            return LyricsPayload(lines: [], synced: false, matchedTitle: "", matchedDuration: 0)
        }
        let matchedTitle = winner.trackName ?? ""
        let matchedDuration = winner.duration ?? 0
        if let synced = winner.syncedLyrics, !synced.isEmpty {
            return LyricsPayload(lines: parseLRC(synced), synced: true, matchedTitle: matchedTitle, matchedDuration: matchedDuration)
        }
        if let plain = winner.plainLyrics, !plain.isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { LyricLine(id: $0.offset, time: 0, text: $0.element) }
            return LyricsPayload(lines: lines, synced: false, matchedTitle: matchedTitle, matchedDuration: matchedDuration)
        }
        return LyricsPayload(lines: [], synced: false, matchedTitle: matchedTitle, matchedDuration: matchedDuration)
    }

    private static func norm(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9 ]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func clean(_ title: String) -> String {
        var t = title
        for pattern in [
            #"\s*[\(\[][^\)\]]*(remaster|remastered|ao vivo|acustico|acoustic|deluxe|edicao|edition|version|feat|ft\.)[^\)\]]*[\)\]]"#,
            #"\s*-\s*(remaster(ed)?|ao vivo|acustico|acoustic|single version|radio edit).*$"#
        ] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - LRC parsing

    static func parseLRC(_ raw: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#) else {
            return []
        }
        var entries: [(time: Double, text: String)] = []

        for rawLine in raw.components(separatedBy: CharacterSet.newlines) {
            let line = rawLine.replacingOccurrences(
                of: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#,
                with: "",
                options: .regularExpression
            )
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: line, options: [], range: range)
            guard !matches.isEmpty else { continue }

            let text = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)

            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = ns.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                entries.append((minutes * 60 + seconds + fraction, text))
            }
        }

        entries.sort { $0.time < $1.time }
        return entries.enumerated().map { index, item in
            LyricLine(id: index, time: item.time, text: item.text.isEmpty ? "♪" : item.text)
        }
    }
}

enum LyricsError: Error {
    case badURL
    case empty
}
