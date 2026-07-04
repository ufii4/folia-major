import Foundation

/// WebSocket client for the folia-server state hub. Owns reconnection;
/// emits `ServerMessage`s through an AsyncStream. Re-sends `hello` on every
/// (re)connect — the server replies with a full `sync`, so reconnect is
/// self-healing by design.
public actor HubClient {
    public enum Event: Sendable {
        case connected
        case disconnected
        case message(ServerMessage)
    }

    private let url: URL
    private let device: HubDevice
    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<Event>.Continuation?
    private var reconnectDelay: TimeInterval = 1
    private var closed = false
    private let session: URLSession

    public init(serverURL: URL, token: String?, device: HubDevice) {
        var comps = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.path = "/ws"
        if let token { comps.queryItems = [URLQueryItem(name: "token", value: token)] }
        self.url = comps.url!
        self.device = device
        self.session = URLSession(configuration: .default)
    }

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            self.continuation = continuation
            Task { await self.connect() }
        }
    }

    public func send(_ message: ClientMessage) async {
        guard let task else { return }
        guard let data = try? message.encode(),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await task.send(.string(text))
    }

    public func close() {
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        continuation?.finish()
    }

    private func connect() async {
        guard !closed else { return }
        let t = session.webSocketTask(with: url)
        // Default cap is 1 MiB; a large queue in a state frame must not
        // kill the socket (hard-won lesson from craft-agents-ios).
        t.maximumMessageSize = 64 * 1024 * 1024
        task = t
        t.resume()
        await send(.hello(device))
        continuation?.yield(.connected)
        reconnectDelay = 1
        await receiveLoop(t)
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while !closed {
            do {
                let msg = try await t.receive()
                let data: Data
                switch msg {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                if let decoded = (try? ServerMessage.decode(data)) ?? nil {
                    continuation?.yield(.message(decoded))
                }
            } catch {
                break
            }
        }
        continuation?.yield(.disconnected)
        guard !closed else { return }
        try? await Task.sleep(for: .seconds(reconnectDelay))
        reconnectDelay = min(reconnectDelay * 2, 15)
        await connect()
    }
}
