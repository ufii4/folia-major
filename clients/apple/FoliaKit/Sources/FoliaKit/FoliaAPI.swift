import Foundation

/// REST client for folia-server. The server owns the NetEase session;
/// we only present the local folia token (loopback connections skip it).
public struct FoliaAPI: Sendable {
    public var baseURL: URL
    public var token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: cfg)
    }

    public enum APIError: Error {
        case badStatus(Int)
        case badShape(String)
    }

    private func get(_ path: String, _ query: [String: String] = [:],
                     cacheBust: Bool = true) async throws -> Data {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if cacheBust {
            // api-enhanced caches GETs for 2 min; timestamp opts out.
            items.append(URLQueryItem(
                name: "timestamp",
                value: String(Int(Date().timeIntervalSince1970 * 1000))
            ))
        }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        if let token { req.setValue(token, forHTTPHeaderField: "X-Folia-Token") }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 404 on song/url/v1 means "grey track, unblock found nothing" — the
        // caller decides; every other non-2xx is a real failure.
        guard (200..<300).contains(code) || code == 404 else {
            throw APIError.badStatus(code)
        }
        return data
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.badShape("not an object")
        }
        return obj
    }

    // MARK: - Endpoints

    public struct Health: Sendable { public let ok: Bool; public let loggedIn: Bool }

    public func health() async throws -> Health {
        let obj = try json(try await get("health", cacheBust: false))
        return Health(ok: obj["ok"] as? Bool ?? false,
                      loggedIn: obj["loggedIn"] as? Bool ?? false)
    }

    public struct SessionInfo: Sendable {
        public let loggedIn: Bool
        public let nickname: String?
    }

    public func sessionInfo() async throws -> SessionInfo {
        let obj = try json(try await get("session", cacheBust: false))
        return SessionInfo(loggedIn: obj["loggedIn"] as? Bool ?? false,
                           nickname: obj["nickname"] as? String)
    }

    public func search(_ keywords: String, limit: Int = 30) async throws -> [Track] {
        let obj = try json(try await get("api/cloudsearch", [
            "keywords": keywords, "limit": String(limit), "type": "1",
        ]))
        guard let result = obj["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else { return [] }
        return songs.compactMap { s in
            guard let id = s["id"] as? Int, let name = s["name"] as? String else { return nil }
            let artists = (s["ar"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            let al = s["al"] as? [String: Any]
            return Track(
                id: id, name: name,
                artist: artists.joined(separator: " / "),
                album: al?["name"] as? String,
                artUrl: (al?["picUrl"] as? String).map(Self.https),
                dt: s["dt"] as? Int
            )
        }
    }

    /// Time-limited CDN URL, or nil for an unavailable (grey) track.
    /// Contract: 200 with url:null and 404 with data:null both mean nil.
    public func songURL(id: Int, level: String = "lossless") async throws -> URL? {
        let obj = try json(try await get("api/song/url/v1", [
            "id": String(id), "level": level, "randomCNIP": "true",
        ]))
        guard let dataArr = obj["data"] as? [[String: Any]],
              let first = dataArr.first,
              let url = first["url"] as? String, !url.isEmpty else { return nil }
        return URL(string: Self.https(url))
    }

    /// Raw LRC text (original + translation if present).
    public struct LyricPayload: Sendable {
        public let lrc: String?
        public let translation: String?
    }

    public func lyrics(id: Int) async throws -> LyricPayload {
        let obj = try json(try await get("api/lyric", ["id": String(id)]))
        let lrc = (obj["lrc"] as? [String: Any])?["lyric"] as? String
        let tl = (obj["tlyric"] as? [String: Any])?["lyric"] as? String
        return LyricPayload(lrc: lrc, translation: tl)
    }

    /// NetEase CDN hosts support TLS; upgrade so ATS stays happy.
    static func https(_ url: String) -> String {
        url.hasPrefix("http://") ? "https://" + url.dropFirst(7) : url
    }
}
