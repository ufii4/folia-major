import Foundation
import FoliaKit
import SwiftUI

public enum ConnectionState: Equatable {
    case connecting
    case connected
    case failed(String)
}

/// The client brain. Applies hub state to the local engine when this device
/// owns audio; mirrors it otherwise. All intents go through the server —
/// local UI never mutates playback state directly (single source of truth).
@MainActor
public final class PlayerStore: ObservableObject {
    @Published public private(set) var state: HubState = .empty
    @Published public private(set) var devices: [HubDevice] = []
    @Published public private(set) var you: String = ""
    @Published public private(set) var connection: ConnectionState = .connecting
    @Published public private(set) var serverNickname: String?
    @Published public private(set) var lyrics: LyricDoc?
    @Published public private(set) var unavailableTrackId: Int?
    @Published public var searchResults: [Track] = []
    @Published public private(set) var config: FoliaConfig

    public private(set) var api: FoliaAPI
    public let engine = PlayerEngine()

    private var hub: HubClient
    private var runTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lyricsTrackId: Int?
    private var loadGeneration = 0
    private let nowPlaying = NowPlayingBridge()

    public var isOwner: Bool { !you.isEmpty && state.ownerId == you }
    public var currentTrack: Track? { state.current }
    public var connected: Bool { connection == .connected }

    public init(config: FoliaConfig = .load()) {
        self.config = config
        self.api = FoliaAPI(baseURL: config.serverURL, token: config.token)
        self.hub = Self.makeHub(config)
        engine.onEnd = { [weak self] in
            guard let self, self.isOwner else { return }
            self.next()
        }
        nowPlaying.wire(self)
        startHeartbeat()
        start()
    }

    private static func makeHub(_ config: FoliaConfig) -> HubClient {
        var outputs: [String] = []
        #if os(macOS)
        outputs = AudioOutputs.list().map(\.name)
        #endif
        return HubClient(
            serverURL: config.serverURL,
            token: config.token,
            device: HubDevice(
                id: config.deviceId, name: config.deviceName,
                platform: config.platform, outputs: outputs
            )
        )
    }

    /// Apply new connection settings NOW — no relaunch. Old hub is torn
    /// down, playback stops locally, and the new connection self-syncs.
    public func reconfigure(_ newConfig: FoliaConfig) {
        newConfig.save()
        config = newConfig
        api = FoliaAPI(baseURL: newConfig.serverURL, token: newConfig.token)

        runTask?.cancel()
        let oldHub = hub
        Task { await oldHub.close() }
        engine.stop()
        state = .empty
        devices = []
        you = ""
        serverNickname = nil
        lyrics = nil
        lyricsTrackId = nil

        hub = Self.makeHub(newConfig)
        start()
    }

    private func start() {
        connection = .connecting
        let hub = self.hub
        runTask = Task { [weak self] in
            for await event in await hub.events() {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .connected:
                    self.connection = .connected
                    self.probeServer()
                case .disconnected:
                    self.classifyFailure()
                case .message(let msg):
                    self.handle(msg)
                }
            }
        }
    }

    private func probeServer() {
        Task {
            if let info = try? await api.sessionInfo() {
                serverNickname = info.nickname
            }
        }
    }

    /// A dropped socket alone says nothing useful. Probe /health to tell
    /// "server down" apart from "bad token" so Settings can say which.
    private func classifyFailure() {
        let api = self.api
        let host = config.serverURL.host ?? "server"
        Task { [weak self] in
            let reason: String
            do {
                _ = try await api.health()
                reason = "Server reachable, but the connection was rejected — check the token."
            } catch {
                reason = "Can't reach \(host) — same network? Server running?"
            }
            guard let self, !Task.isCancelled else { return }
            if self.connection != .connected { self.connection = .failed(reason) }
        }
    }

    private func handle(_ msg: ServerMessage) {
        switch msg {
        case .sync(let you, let state, let devices):
            self.you = you
            self.devices = devices
            apply(state)
        case .state(let state, let devices):
            self.devices = devices
            apply(state)
        case .position(let p):
            state.position = p
            nowPlaying.update()
        case .devices(let devices):
            self.devices = devices
        case .pong:
            break
        }
    }

    private func apply(_ newState: HubState) {
        let old = state
        state = newState
        refreshLyricsIfNeeded()
        defer { nowPlaying.update() }

        guard isOwner else {
            engine.stop()
            return
        }

        let pos = newState.position.interpolated(playing: newState.playing)
        guard let track = newState.current else {
            engine.stop()
            return
        }

        if engine.loadedTrackId != track.id {
            loadAndPlay(track, at: newState.position.pos, playing: newState.playing)
            return
        }
        // Same track: reconcile play/pause and remote seeks. A >2s gap between
        // hub position and engine clock means someone seeked elsewhere.
        if newState.playing, !engine.isPlaying { engine.play() }
        if !newState.playing, engine.isPlaying { engine.pause() }
        if old.rev != newState.rev, abs(engine.currentTime - pos) > 2 {
            engine.seek(to: newState.position.pos)
        }
    }

    private func loadAndPlay(_ track: Track, at position: Double, playing: Bool) {
        loadGeneration += 1
        let gen = loadGeneration
        Task {
            do {
                guard let url = try await api.songURL(id: track.id) else {
                    guard gen == loadGeneration else { return }
                    unavailableTrackId = track.id
                    // Grey track: skip forward rather than sit in silence,
                    // unless it's the only thing queued.
                    if state.queue.count > 1 { next() }
                    return
                }
                guard gen == loadGeneration, isOwner else { return }
                unavailableTrackId = nil
                engine.load(trackId: track.id, url: url, at: position, playing: playing)
                nowPlaying.update()
            } catch {
                guard gen == loadGeneration else { return }
                unavailableTrackId = track.id
            }
        }
    }

    private func refreshLyricsIfNeeded() {
        guard let track = state.current else { return }
        guard track.id != lyricsTrackId else { return }
        lyricsTrackId = track.id
        lyrics = nil
        Task {
            guard let payload = try? await api.lyrics(id: track.id),
                  let lrc = payload.lrc, !lrc.isEmpty,
                  lyricsTrackId == track.id else { return }
            lyrics = LyricDoc.parse(lrc: lrc, translation: payload.translation)
        }
    }

    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.isOwner, self.state.playing, self.engine.loadedTrackId != nil {
                    let hub = self.hub
                    let pos = self.engine.currentTime
                    await hub.send(.position(pos))
                    self.nowPlaying.update()
                }
            }
        }
    }

    /// Position to render (progress bar, lyric line): the engine clock when
    /// we own audio, the interpolated hub clock when mirroring.
    public func displayedPosition(now: Date = Date()) -> Double {
        if isOwner, engine.loadedTrackId != nil { return engine.currentTime }
        return state.position.interpolated(playing: state.playing, now: now)
    }

    // MARK: - Intents (all server-routed)

    private func send(_ msg: ClientMessage) {
        let hub = self.hub
        Task { await hub.send(msg) }
    }

    public func playPause() { send(state.playing ? .pause : .play) }
    public func play() { send(.play) }
    public func pause() { send(.pause) }
    public func next() { send(.next) }
    public func prev() { send(.prev) }
    public func seek(to pos: Double) {
        if isOwner { engine.seek(to: pos) }
        send(.seek(pos))
    }
    public func transfer(to deviceId: String) { send(.transfer(to: deviceId)) }
    public func playNow(_ tracks: [Track], index: Int) {
        send(.setQueue(tracks, index: index, play: true))
    }

    public func search(_ keywords: String) {
        Task {
            searchResults = (try? await api.search(keywords)) ?? []
        }
    }

    #if os(macOS)
    public func setOutputDevice(uid: String?) {
        engine.outputDeviceUID = uid
    }
    #endif
}
