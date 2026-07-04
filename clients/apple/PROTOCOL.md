# Apple clients — protocol contract

One SwiftPM codebase, two targets (macOS, iOS). SwiftUI + AVPlayer. Clients
are thin: the server owns session and shared state; NetEase CDN serves audio.

## Roles

At any moment at most one device is the **owner** (renders audio). Everyone
else is a **mirror** (lyrics, remote control, queue browsing). Any device may
send commands; the server applies them and broadcasts. This is the
Spotify-Connect model: playing on the Mac, the iPhone connects and instantly
has the current track + position for its lyrics view.

## REST (all with `X-Folia-Token`)

- Catalog/search/playlists/lyrics: any api-enhanced route under `/api`.
  Key ones: `/api/search`, `/api/playlist/detail`, `/api/lyric/new?id=`,
  `/api/song/detail?ids=`.
- **Audio**: `GET /api/song/url/v1?id=<id>&level=lossless&timestamp=<now>`
  → time-limited CDN URL. Stream it directly with AVPlayer; do not proxy
  audio through the server. Refetch on 403/expiry or before natural track end.
  Pass `randomCNIP=true` — much of the catalog is IP-gated to mainland CN.
- **Unavailable tracks**: treat BOTH `200` with `data[0].url == null` AND
  `404` with `data == null` as "no playable URL" (the latter occurs when the
  server's grey-track unblock fallback finds nothing). Skip forward with a
  UI hint; do not error.

## WebSocket `/ws?token=`

Client → server:

```jsonc
{ "type": "hello", "device": { "id": "mac-studio", "name": "Mac", "platform": "macos", "outputs": ["Speakers", "HomePod"] } }
{ "type": "cmd", "action": "setQueue", "queue": [ { "id": 186016, "name": "Creep", "artist": "Radiohead", "dt": 238640 } ], "index": 0, "play": true }
{ "type": "cmd", "action": "play" | "pause" | "next" | "prev" }
{ "type": "cmd", "action": "seek", "pos": 42.5 }
{ "type": "cmd", "action": "transfer", "to": "iphone" }
{ "type": "position", "pos": 42.5 }        // owner only, ~1 Hz while playing
{ "type": "ping" }
```

Server → client:

```jsonc
{ "type": "sync", "you": "iphone", "state": { ... }, "devices": [ ... ] }  // on hello
{ "type": "state", "state": { "rev": 7, "queue": [...], "index": 0, "playing": true, "position": { "pos": 12.3, "ts": 1783190000000 }, "ownerId": "mac-studio" }, "devices": [...] }
{ "type": "position", "position": { "pos": 42.5, "ts": ... } }
{ "type": "devices", "devices": [...] }
```

Queue items are opaque to the server — put whatever the UI needs (id, name,
artist, album art URL, duration) so mirrors render without extra fetches.

## Rules the client must implement

- **Ownership**: `play`/`setQueue` when `ownerId == null` makes the sender the
  owner. On `state` where `ownerId == you`: start/continue audio at
  `position`. Where `ownerId != you`: silence audio, mirror state.
- **Transfer**: new owner seeks to `position.pos + (now - position.ts)/1000`
  (if playing) and starts; old owner stops on the same `state` message.
- **Mirror clock**: displayed position = `position.pos + (now - position.ts)/1000`
  while `playing`, frozen otherwise. Owner heartbeats at ~1 Hz keep drift
  under a lyric line.
- **Owner drop**: server sets `playing=false, ownerId=null` if the owner's
  socket dies. Mirrors freeze; any device can resume and claim.

## Platform notes

- **macOS output device selection**: `AVPlayer.audioOutputDeviceUniqueID`
  (enumerate via CoreAudio `kAudioHardwarePropertyDevices`). Report device
  names in `hello.outputs`.
- **iOS routing**: the system owns routing — expose `AVRoutePickerView`
  (AirPlay/Bluetooth) instead of a device list. Configure
  `AVAudioSession` category `.playback` for background audio; feed
  `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` even when mirroring
  (lock-screen shows the shared now-playing, commands go over the WS).
- **Formats**: `level=lossless` returns FLAC — AVPlayer handles it on
  macOS 10.13+/iOS 11+. `exhigh` (320k mp3) as fallback.
- **Reconnect**: on WS drop, retry with backoff; `hello` re-syncs everything.
