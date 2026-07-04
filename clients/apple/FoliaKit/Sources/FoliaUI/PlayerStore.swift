import Foundation
import FoliaKit
import SwiftUI

/// The client brain. Applies hub state to the local engine when this device
/// owns audio; mirrors it otherwise. All intents go through the server —
/// local UI never mutates playback state directly (single source of truth).
@MainActor
public final class PlayerStore: ObservableObject {
    @Published public private(set) var state: HubState = .empty
    @Published public private(set) var devices: [HubDevice] = []
    @Published public private(set) var you: String = ""
    @Published public private(set) var connected = false
    @Published public private(set) var lyrics: LyricDoc?
    @Published public private(set) var unavailableTrackId: Int?
    @Published public var searchResults: [Track] = []

    public let config: FoliaConfig
    public let api: FoliaAPI
    public let engine = PlayerEngine()

    private let hub: HubClient
    private var heartbeat: Task<Void, Never>?
    private var lyricsTrackId: Int?
    private var loadGeneration = 0

    public var isOwner: Bool { !you.isEmpty && state.ownerId == you }
    public var currentTrack: Track? { state.current }

    public init(config: FoliaConfig = .load()) {
        self.config = config
        self.api = FoliaAPI(baseURL: config.serverURL, token: config.token)
        var outputs: [String] = []
        #if os(macOS)
        outputs = AudioOutputs.list().map(\.name)
        #endif
        self.hub = HubClient(
            serverURL: config.serverURL,
            token: config.token,
            device: HubDevice(
                id: config.deviceId, name: config.deviceName,
                platform: config.platform, outputs: outputs
            )
        )
        engine.onEnd = { [weak self] in
            guard let self, self.isOwner else { return }
            Task { await self.hub.send(.next) }
        }
        Task { await run() }
        startHeartbeat()
    }

    private func run() async {
        for await event in await hub.events() {
            switch event {
            case .connected:
                connected = true
            case .disconnected:
                connected = false
            case .message(let msg):
                handle(msg)
            }
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
                    if state.queue.count > 1 { await hub.send(.next) }
                    return
                }
                guard gen == loadGeneration, isOwner else { return }
                unavailableTrackId = nil
                engine.load(trackId: track.id, url: url, at: position, playing: playing)
            } catch {
                guard gen == loadGeneration else { return }
                unavailableTrackId = track.id
            }
        }
    }

    private func refreshLyricsIfNeeded() {
        guard let track = state.current, track.id != lyricsTrackId else { return }
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
                    await self.hub.send(.position(self.engine.currentTime))
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

    public func playPause() {
        Task { await hub.send(state.playing ? .pause : .play) }
    }
    public func next() { Task { await hub.send(.next) } }
    public func prev() { Task { await hub.send(.prev) } }
    public func seek(to pos: Double) {
        if isOwner { engine.seek(to: pos) }
        Task { await hub.send(.seek(pos)) }
    }
    public func transfer(to deviceId: String) {
        Task { await hub.send(.transfer(to: deviceId)) }
    }
    public func playNow(_ tracks: [Track], index: Int) {
        Task { await hub.send(.setQueue(tracks, index: index, play: true)) }
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
