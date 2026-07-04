// Server-held NetEase cookie jar. The whole point of this service: login state
// lives here, never on a client. Clients authenticate to us with the local
// token; we authenticate to NetEase with this jar.
const fs = require('fs')
const config = require('./config')

let cookies = {}
try {
  cookies = JSON.parse(fs.readFileSync(config.cookiePath, 'utf-8'))
} catch {
  cookies = {}
}

function save() {
  fs.writeFileSync(config.cookiePath, JSON.stringify(cookies, null, 2), {
    mode: 0o600,
  })
}

function toHeader() {
  return Object.entries(cookies)
    .map(([k, v]) => `${k}=${v}`)
    .join('; ')
}

// Absorb Set-Cookie header value(s) coming back from api-enhanced module
// responses. Only the leading k=v pair matters; attributes are dropped.
// An empty value or immediate expiry means deletion.
function absorb(setCookie) {
  const list = Array.isArray(setCookie) ? setCookie : [setCookie]
  let changed = false
  for (const line of list) {
    if (typeof line !== 'string' || !line.includes('=')) continue
    const [pair, ...attrs] = line.split(';')
    const eq = pair.indexOf('=')
    const key = pair.slice(0, eq).trim()
    const value = pair.slice(eq + 1).trim()
    if (!key) continue
    const expired = attrs.some((a) => /max-age\s*=\s*0/i.test(a))
    if (!value || expired) {
      if (key in cookies) {
        delete cookies[key]
        changed = true
      }
    } else if (cookies[key] !== value) {
      cookies[key] = value
      changed = true
    }
  }
  if (changed) save()
  return changed
}

function isLoggedIn() {
  return Boolean(cookies.MUSIC_U)
}

function clear() {
  cookies = {}
  save()
}

module.exports = { toHeader, absorb, isLoggedIn, clear }
