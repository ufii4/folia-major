# folia-server

Single-user music service kernel. Runs on one always-on machine (launchd), owns
the NetEase session, and coordinates playback across all clients (macOS, iOS,
interim web). Clients are peers; this process is the source of truth.

## Design

```
clients (Swift macOS / Swift iOS / web)
        │  REST /api/*  (catalog, urls, lyrics — proxied to NetEase)
        │  WS   /ws     (shared now-playing state, Spotify-Connect model)
        ▼
folia-server (this process, Node)
  ├─ api-enhanced        ← git subtree, mounted in-process at /api
  ├─ cookie jar          ← NetEase login lives HERE, never on a client
  └─ state hub           ← queue / owner device / position heartbeats
        │
        ▼
NetEase (API + CDN; audio streams go client → CDN directly, not through us)
```

Three deliberate choices:

1. **api-enhanced stays Node, embedded as a library.** It tracks NetEase's
   shifting crypto/endpoints upstream; reimplementing it in Rust/Swift forks us
   off that maintenance stream. Update with:
   `git subtree pull --prefix server/api-enhanced https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced main --squash`
   Two local divergences, both in `server/api-enhanced/server.js` and both
   upstream-PR-worthy — re-apply if a subtree pull conflicts:
   - exports `constructServer` (so we mount the express app in-process
     instead of running a second HTTP server)
   - grey-track unblock gate checks `req.path` instead of `req.baseUrl`
     (baseUrl is the mount point — empty standalone, `/api` embedded — so the
     upstream check never matches). Unblock itself is opt-in via
     `ENABLE_GENERAL_UNBLOCK=true`, set in the launchd plist. Note: from a
     non-CN IP the mirror sources are often geo-gated too; expect occasional
     rescues, not guarantees.
2. **Login state is server-held.** Middleware injects the stored cookie jar
   into every `/api` call and absorbs `Set-Cookie` from login responses.
   NetEase credentials never reach a client — clients authenticate to us with
   a local token instead. Single user, many devices.
3. **The performance rewrite happens in the clients, not here.** This kernel is
   a thin proxy + state bus; Node is not the bottleneck. Native Swift clients
   (see `clients/apple/PROTOCOL.md`) replace the Electron/web UI.

## Endpoints

| Route | What |
|---|---|
| `GET /health` | liveness + login flag (no auth) |
| `GET /session` | profile of the logged-in NetEase account |
| `POST /session/logout` | wipe the cookie jar |
| `ALL /api/*` | full api-enhanced surface (402 endpoints) with server-side session |
| `WS /ws?token=` | playback state hub — protocol in `clients/apple/PROTOCOL.md` |

Auth: `X-Folia-Token` header, `Authorization: Bearer`, or `?token=`. Loopback
requests skip auth. Token lives at
`~/Library/Application Support/folia-server/token`.

Append `&timestamp=<now>` to `/api` GETs that must not be cached (QR-check
polling, song URLs) — api-enhanced caches GETs for 2 minutes.

## Login (QR, once)

```
GET /api/login/qr/key?timestamp=..            → unikey
GET /api/login/qr/create?key=<unikey>&qrimg=1 → QR png (scan with NetEase app)
GET /api/login/qr/check?key=<unikey>&timestamp=..  (poll; 803 = done)
```

On 803 the server absorbs the cookie; every device is logged in from then on.

## Service

```
deploy/install.sh          # bootstraps launchd job com.ufii.folia-server
~/Library/Logs/folia-server.log
FOLIA_PORT (3766) / FOLIA_HOST / FOLIA_DATA_DIR to override
```

For iPhone off-LAN, put the machine on Tailscale; do not port-forward this.

## Interim web client

The existing folia UI works against this server unchanged:
`VITE_NETEASE_API_BASE=http://localhost:3766/api npm run dev`
