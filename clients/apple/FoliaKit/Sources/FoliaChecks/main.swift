import Foundation
import FoliaKit

// Live checks against a running folia-server. Every check hits the real
// service (which hits real NetEase) — no mocks, no self-grading.
// Usage: swift run folia-checks [serverURL]

let serverURL = URL(string: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "http://127.0.0.1:3766")!
let api = FoliaAPI(baseURL: serverURL, token: ProcessInfo.processInfo.environment["FOLIA_TOKEN"])

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures += 1 }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        // 1. health + logged-in session
        let health = try await api.health()
        check("health", health.ok)
        check("server-held login", health.loggedIn)

        // 2. search (real NetEase catalog)
        let tracks = try await api.search("海阔天空 Beyond", limit: 5)
        check("cloudsearch", !tracks.isEmpty, "\(tracks.count) results, first: \(tracks.first?.name ?? "-")")
        let beyond = tracks.first { $0.name.contains("海阔天空") } ?? tracks[0]

        // 3. lossless URL for a licensed track
        let url = try await api.songURL(id: beyond.id)
        check("lossless url", url != nil, url.map { $0.host ?? "" } ?? "nil")
        check("https upgrade", url?.scheme == "https")

        // 4. grey-track contract: known-unlicensed id resolves to nil, not a throw
        let grey = try await api.songURL(id: 186016)
        check("grey track → nil", grey == nil)

        // 5. real lyrics, parsed
        let lp = try await api.lyrics(id: beyond.id)
        let doc = LyricDoc.parse(lrc: lp.lrc ?? "", translation: lp.translation)
        check("lyrics parsed", doc.lines.count > 10, "\(doc.lines.count) lines")
        if let mid = doc.lines[safe: doc.lines.count / 2] {
            let idx = doc.activeIndex(at: mid.time + 0.1)
            check("activeIndex", idx == doc.lines.count / 2)
        }

        // 6. WS: mac claims playback, phone (late join) must sync it
        let macHub = HubClient(
            serverURL: serverURL, token: nil,
            device: HubDevice(id: "check-mac", name: "check-mac", platform: "macos"))
        var macEvents = await macHub.events().makeAsyncIterator()

        func nextMessage(_ it: inout AsyncStream<HubClient.Event>.AsyncIterator) async -> ServerMessage? {
            while let ev = await it.next() {
                if case .message(let m) = ev { return m }
            }
            return nil
        }

        guard case .sync = await nextMessage(&macEvents) else {
            check("ws sync on hello", false); throw ExitNow()
        }
        check("ws sync on hello", true)

        await macHub.send(.setQueue([beyond], index: 0, play: true))
        guard case .state(let st, _) = await nextMessage(&macEvents) else {
            check("ws state after setQueue", false); throw ExitNow()
        }
        check("ws state after setQueue", st.ownerId == "check-mac" && st.playing,
              "owner=\(st.ownerId ?? "-")")

        let phoneHub = HubClient(
            serverURL: serverURL, token: nil,
            device: HubDevice(id: "check-phone", name: "check-phone", platform: "ios"))
        var phoneEvents = await phoneHub.events().makeAsyncIterator()
        guard case .sync(_, let phoneState, _) = await nextMessage(&phoneEvents) else {
            check("late-join sync", false); throw ExitNow()
        }
        check("late-join sync sees track", phoneState.current?.id == beyond.id,
              phoneState.current?.name ?? "-")

        await macHub.send(.position(42.5))
        guard case .position(let p) = await nextMessage(&phoneEvents) else {
            check("position relay", false); throw ExitNow()
        }
        check("position relay", p.pos == 42.5)
        check("mirror clock", abs(p.interpolated(playing: true) - 42.5) < 2.0)

        await macHub.close()
        // owner drop → phone must see playback stop
        var stopped = false
        for _ in 0..<3 {
            if case .state(let s2, _) = await nextMessage(&phoneEvents),
               s2.ownerId == nil, !s2.playing { stopped = true; break }
        }
        check("owner drop stops playback", stopped)
        await phoneHub.close()
    } catch is ExitNow {
        // checks already recorded the failure
    } catch {
        check("unexpected error", false, "\(error)")
    }
    sem.signal()
}

struct ExitNow: Error {}
extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

sem.wait()
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
