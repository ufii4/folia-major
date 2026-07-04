// folia-server: single-user music service kernel.
//
// - Embeds api-enhanced in-process (mounted at /api) — no second HTTP server.
// - Owns the NetEase session: injects the stored cookie jar into every
//   upstream call, absorbs Set-Cookie from login flows, never forwards
//   NetEase cookies to clients.
// - /ws: shared playback-state hub for macOS/iOS/web clients.
const path = require('path')
const http = require('http')
const express = require('express')

const config = require('./config')
const jar = require('./jar')
const { wss } = require('./hub')
const api = require(path.join(__dirname, '..', 'api-enhanced', 'main.js'))
const { constructServer } = require(
  path.join(__dirname, '..', 'api-enhanced', 'server.js'),
)

const app = express()
app.set('trust proxy', 'loopback')

const LOOPBACK = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1'])
function authorized(req) {
  const presented =
    req.headers['x-folia-token'] ||
    (req.headers.authorization || '').replace(/^Bearer\s+/i, '') ||
    req.query.token
  if (presented === config.token) return true
  // Local processes (interim web client dev server, curl on this Mac) get a pass.
  return LOOPBACK.has(req.socket.remoteAddress)
}

app.get('/health', (_req, res) =>
  res.json({ ok: true, loggedIn: jar.isLoggedIn() }),
)

// One-glance client onboarding: open http://localhost:3766/pair on the Mac,
// scan with the iOS app. Loopback-only — the QR embeds the token.
app.get('/pair', async (req, res) => {
  if (!LOOPBACK.has(req.socket.remoteAddress)) {
    return res.status(403).send('pairing page is loopback-only')
  }
  const os = require('os')
  const host = os.hostname().replace(/\.local$/, '')
  const setupURL =
    `folia://setup?url=${encodeURIComponent(`http://${host}.local:${config.port}`)}` +
    `&token=${config.token}`
  const qrcode = require('qrcode')
  const img = await qrcode.toDataURL(setupURL, { width: 380, margin: 2 })
  res.send(`<!doctype html><meta charset="utf-8">
<title>Pair a Folia client</title>
<body style="font-family:-apple-system,sans-serif;display:flex;flex-direction:column;
align-items:center;justify-content:center;min-height:90vh;background:#0f1420;color:#e8ecf4">
<h2 style="font-weight:600">Pair a Folia client</h2>
<img src="${img}" style="border-radius:12px">
<p style="color:#93a0b4">Open Folia on the phone → Settings → Scan Setup Code</p>
<p style="color:#93a0b4;font-size:12px">server: http://${host}.local:${config.port}</p>
</body>`)
})

app.use((req, res, next) => {
  if (!authorized(req)) return res.status(401).json({ error: 'bad token' })
  next()
})

app.get('/session', async (_req, res) => {
  if (!jar.isLoggedIn()) return res.json({ loggedIn: false })
  try {
    const r = await api.user_account({ cookie: jar.toHeader() })
    const p = r.body && r.body.profile
    res.json({
      loggedIn: Boolean(p),
      nickname: p ? p.nickname : null,
      userId: p ? p.userId : null,
      vipType: p ? p.vipType : null,
    })
  } catch (e) {
    res.json({ loggedIn: jar.isLoggedIn(), error: 'profile fetch failed' })
  }
})

app.post('/session/logout', (_req, res) => {
  jar.clear()
  res.json({ ok: true })
})

async function main() {
  const ncmApp = await constructServer()

  // Server-side session: the stored jar wins over anything a client sends.
  // Login responses are absorbed into the jar and stripped — NetEase
  // credentials never leave this process.
  app.use(
    '/api',
    (req, res, next) => {
      const stored = jar.toHeader()
      if (stored) {
        req.headers.cookie = req.headers.cookie
          ? `${req.headers.cookie}; ${stored}`
          : stored
      }
      const append = res.append.bind(res)
      res.append = (field, value) => {
        if (String(field).toLowerCase() === 'set-cookie') {
          jar.absorb(value)
          return res
        }
        return append(field, value)
      }
      next()
    },
    ncmApp,
  )

  const server = http.createServer(app)
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://x')
    const tokenOk =
      url.pathname === '/ws' &&
      (url.searchParams.get('token') === config.token ||
        LOOPBACK.has(socket.remoteAddress))
    if (!tokenOk) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
      socket.destroy()
      return
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws))
  })

  server.listen(config.port, config.host, () => {
    console.log(
      `folia-server listening on ${config.host}:${config.port} ` +
        `(loggedIn=${jar.isLoggedIn()}, data=${config.dataDir})`,
    )
  })
}

main().catch((e) => {
  console.error('fatal:', e)
  process.exit(1)
})
