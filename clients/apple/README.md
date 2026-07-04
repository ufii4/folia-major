# Folia Apple clients

Native SwiftUI clients for [folia-server](../../server). One SwiftPM package
(`FoliaKit`) shared by two thin app targets (macOS, iOS) generated with
XcodeGen. The server owns the NetEase session and shared playback state; these
clients are peers that render it.

## Layout

```
FoliaKit/                     SwiftPM package (the real code)
  Sources/FoliaKit/           transport + models, no UI
    Models.swift              wire types + ServerMessage/ClientMessage codecs
    FoliaAPI.swift            REST client (search, song url, lyrics)
    HubClient.swift           WS actor, self-healing reconnect
    Lyrics.swift              LRC parser + binary-search active-line lookup
  Sources/FoliaUI/            SwiftUI + AVFoundation (shared views)
    PlayerStore.swift         the brain: applies hub state to the engine
    PlayerEngine.swift        AVPlayer wrapper (streams NetEase CDN direct)
    AudioOutputs.swift        CoreAudio device enumeration (macOS output picker)
    Views.swift, LyricsView.swift
  Sources/FoliaChecks/        live integration checks (executable)
App/                          XcodeGen project.yml → Folia-macOS + Folia-iOS
  scripts/deploy-device.sh    build+sign+install on a real iPhone via signing runner
```

## Model

The **PlayerStore** is the whole client-side design in one file:

- Every intent (play, seek, transfer, setQueue) goes to the **server**, never
  to the local engine directly. The server broadcasts new state; the store
  reacts. Single source of truth, so all devices stay coherent.
- When `state.ownerId == you`, the store drives `PlayerEngine` (resolves a CDN
  URL, loads AVPlayer, heartbeats position at ~1 Hz).
- Otherwise it's a **mirror**: engine stopped, lyrics + progress driven by the
  interpolated hub clock. This is the "Mac plays, iPhone shows lyrics" case.
- Grey tracks (`songURL` → nil) auto-skip forward with a UI hint.

## Build & run

```bash
# shared package + live checks (needs folia-server running on :3766)
cd FoliaKit && swift run folia-checks

# apps
cd App && xcodegen generate
xcodebuild -project Folia.xcodeproj -scheme Folia-macOS build      # macOS
open build/.../Folia.app
scripts/deploy-device.sh UFIPhone                                  # real iPhone
```

Point a client at the server via Settings (URL + token), or seed with
`FOLIA_SERVER_URL` / `FOLIA_TOKEN` env vars (simulator:
`SIMCTL_CHILD_FOLIA_SERVER_URL=…`). Off-LAN, use the Tailscale name.

Requires Xcode 26 / Swift 6 toolchain. Under Command Line Tools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Status

Verified 2026-07-04: `folia-checks` all green against live NetEase; macOS app
plays real lossless audio (AVPlayer clock advancing, driven remotely via the
hub); iPhone simulator mirrors playback with synced scrolling lyrics.

Not yet done: `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` (lock-screen
+ remote-control wiring), `AVRoutePickerView` for iOS AirPlay, QR-login UI in
the client (login is currently done server-side via curl). See
`PROTOCOL.md` for the full contract.
