import Foundation

/// Time-synced lyrics for the current song from LRCLIB (lrclib.net), a free, open
/// lyrics library that needs no account.
@MainActor
final class LyricsMonitor: ObservableObject {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    enum State: Equatable {
        case idle
        case loading
        case synced([Line])
        case plain(String)
        case instrumental
        case notFound
        case failed
    }

    @Published private(set) var state: State = .idle
    private var currentKey: String?
    private var task: Task<Void, Never>?
    private var cache: [String: State] = [:]

    /// Loads lyrics for a track, once per track.
    func load(title: String, artist: String, album: String, duration: Double) {
        let key = "\(title)|\(artist)"
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()
        if let cached = cache[key] {
            state = cached
            return
        }
        state = .loading
        task = Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.currentKey == key else { return }
            if result != .failed { self.cache[key] = result }
            self.state = result
        }
    }

    func retry() {
        currentKey = nil
    }

    /// The index of the line being sung at `position`.
    static func index(in lines: [Line], at position: Double) -> Int? {
        var found: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= position + 0.25 { found = index } else { break }
        }
        return found
    }

    // MARK: Fetching

    private struct Record: Decodable {
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
        let duration: Double?
    }

    private nonisolated static func fetch(title: String, artist: String, album: String, duration: Double) async -> State {
        // Streaming apps add "(feat. …)" or " - Remastered"; the library usually doesn't.
        let cleanTitle = title.replacingOccurrences(of: #"\s*[\(\[](feat|ft|with|from)[^\)\]]*[\)\]]"#, with: "",
                                                    options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+-\s+.*(remaster|version|edit|mix).*$"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
        let firstArtist = artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .trimmingCharacters(in: .whitespaces) ?? artist

        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [URLQueryItem(name: "track_name", value: cleanTitle),
                            URLQueryItem(name: "artist_name", value: firstArtist)]
        if duration > 0 { exact.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: cleanTitle),
                             URLQueryItem(name: "artist_name", value: firstArtist)]

        var sawNetworkError = false
        if let url = exact.url {
            switch await request(url, as: Record.self) {
            case let .success(record): return state(for: record)
            case .missing: break
            case .error: sawNetworkError = true
            }
        }
        if let url = search.url {
            switch await request(url, as: [Record].self) {
            case let .success(records):
                // Prefer synced lyrics whose length matches the song.
                let ranked = records.sorted { lhs, rhs in
                    let left = (lhs.syncedLyrics != nil ? 0 : 1000) + abs((lhs.duration ?? 0) - duration)
                    let right = (rhs.syncedLyrics != nil ? 0 : 1000) + abs((rhs.duration ?? 0) - duration)
                    return left < right
                }
                if let best = ranked.first { return state(for: best) }
                return .notFound
            case .missing: return .notFound
            case .error: sawNetworkError = true
            }
        }
        return sawNetworkError ? .failed : .notFound
    }

    private enum Response<T> {
        case success(T)
        case missing
        case error
    }

    private nonisolated static func request<T: Decodable>(_ url: URL, as type: T.Type) async -> Response<T> {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Halo (Dynamic Island for Mac)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 404 { return .missing }
                if status == 503 || status == 429 {
                    // LRCLIB is sometimes busy for a moment.
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 800_000_000)
                    continue
                }
                guard status == 200 else { return .error }
                guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { return .missing }
                return .success(decoded)
            } catch {
                if Task.isCancelled { return .error }
            }
        }
        return .error
    }

    private nonisolated static func state(for record: Record) -> State {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, case let lines = parse(synced), !lines.isEmpty { return .synced(lines) }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty { return .plain(plain) }
        return .notFound
    }

    /// Parses LRC lines like "[01:23.45] words".
    nonisolated static func parse(_ lrc: String) -> [Line] {
        var lines: [Line] = []
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = pattern.matches(in: raw, range: range)
            guard let last = matches.last, let textRange = Range(NSRange(location: last.range.upperBound, length: range.length - last.range.upperBound), in: raw) else { continue }
            let text = raw[textRange].trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: raw).flatMap({ Double(raw[$0]) }),
                      let seconds = Range(match.range(at: 2), in: raw).flatMap({ Double(raw[$0]) }) else { continue }
                lines.append(Line(time: minutes * 60 + seconds, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
