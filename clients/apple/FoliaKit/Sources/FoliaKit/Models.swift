import Foundation

// Queue items are opaque to the server (hub.js) — this is the shape all
// clients agree to put in them. Keys are part of the wire contract.
public struct Track: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let artist: String
    public let album: String?
    public let artUrl: String?
    /// duration in milliseconds
    public let dt: Int?

    public init(id: Int, name: String, artist: String, album: String? = nil,
                artUrl: String? = nil, dt: Int? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.artUrl = artUrl
        self.dt = dt
    }

    // Queue items come from whichever client wrote them — decode leniently
    // so a sparse item never poisons a whole state frame.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        artist = (try? c.decode(String.self, forKey: .artist)) ?? ""
        album = try? c.decode(String.self, forKey: .album)
        artUrl = try? c.decode(String.self, forKey: .artUrl)
        dt = try? c.decode(Int.self, forKey: .dt)
    }
}

public struct HubPosition: Codable, Equatable, Sendable {
    public var pos: Double
    /// server epoch millis at which `pos` was reported
    public var ts: Double

    public init(pos: Double, ts: Double) {
        self.pos = pos
        self.ts = ts
    }

    /// Mirror clock: where playback is *now*, given the last heartbeat.
    public func interpolated(playing: Bool, now: Date = Date()) -> Double {
        guard playing, ts > 0 else { return pos }
        return pos + max(0, now.timeIntervalSince1970 - ts / 1000)
    }
}

public struct HubState: Codable, Equatable, Sendable {
    public var rev: Int
    public var queue: [Track]
    public var index: Int
    public var playing: Bool
    public var position: HubPosition
    public var ownerId: String?

    public var current: Track? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    public static let empty = HubState(
        rev: 0, queue: [], index: -1, playing: false,
        position: HubPosition(pos: 0, ts: 0), ownerId: nil
    )
}

public struct HubDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let outputs: [String]?

    public init(id: String, name: String, platform: String, outputs: [String]? = nil) {
        self.id = id
        self.name = name
        self.platform = platform
        self.outputs = outputs
    }
}

// MARK: - Server → client

public enum ServerMessage: Sendable {
    case sync(you: String, state: HubState, devices: [HubDevice])
    case state(HubState, devices: [HubDevice])
    case position(HubPosition)
    case devices([HubDevice])
    case pong

    public static func decode(_ data: Data) throws -> ServerMessage? {
        struct Raw: Decodable {
            let type: String
            let you: String?
            let state: HubState?
            let devices: [HubDevice]?
            let position: HubPosition?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        switch raw.type {
        case "sync":
            guard let you = raw.you, let state = raw.state else { return nil }
            return .sync(you: you, state: state, devices: raw.devices ?? [])
        case "state":
            guard let state = raw.state else { return nil }
            return .state(state, devices: raw.devices ?? [])
        case "position":
            guard let position = raw.position else { return nil }
            return .position(position)
        case "devices":
            return .devices(raw.devices ?? [])
        case "pong":
            return .pong
        default:
            return nil
        }
    }
}

// MARK: - Client → server

public enum ClientMessage: Sendable {
    case hello(HubDevice)
    case setQueue([Track], index: Int, play: Bool)
    case play, pause, next, prev
    case seek(Double)
    case transfer(to: String)
    case position(Double)
    case ping

    public func encode() throws -> Data {
        var obj: [String: Any] = [:]
        switch self {
        case .hello(let d):
            obj = ["type": "hello", "device": [
                "id": d.id, "name": d.name, "platform": d.platform,
                "outputs": d.outputs ?? [],
            ]]
        case .setQueue(let queue, let index, let play):
            let items = try queue.map { t -> Any in
                let data = try JSONEncoder().encode(t)
                return try JSONSerialization.jsonObject(with: data)
            }
            obj = ["type": "cmd", "action": "setQueue",
                   "queue": items, "index": index, "play": play]
        case .play: obj = ["type": "cmd", "action": "play"]
        case .pause: obj = ["type": "cmd", "action": "pause"]
        case .next: obj = ["type": "cmd", "action": "next"]
        case .prev: obj = ["type": "cmd", "action": "prev"]
        case .seek(let pos): obj = ["type": "cmd", "action": "seek", "pos": pos]
        case .transfer(let to): obj = ["type": "cmd", "action": "transfer", "to": to]
        case .position(let pos): obj = ["type": "position", "pos": pos]
        case .ping: obj = ["type": "ping"]
        }
        return try JSONSerialization.data(withJSONObject: obj)
    }
}
