// Shared playback state hub — the Spotify-Connect part of the service.
// The server is the source of truth for now-playing; exactly one device
// ("owner") renders audio, every other connected device mirrors state
// (lyrics view, remote control). Queue items are opaque to the server.
const fs = require('fs')
const { WebSocketServer } = require('ws')
const config = require('./config')

const emptyState = () => ({
  rev: 0,
  queue: [],
  index: -1,
  playing: false,
  position: { pos: 0, ts: 0 },
  ownerId: null,
})

let state = emptyState()
try {
  const saved = JSON.parse(fs.readFileSync(config.statePath, 'utf-8'))
  state = { ...emptyState(), ...saved, playing: false, ownerId: null }
} catch {
  /* first boot */
}

let saveTimer = null
function persist() {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    const { rev, queue, index, position } = state
    fs.writeFileSync(
      config.statePath,
      JSON.stringify({ rev, queue, index, position }),
    )
  }, 1000)
}

const wss = new WebSocketServer({ noServer: true })
const devices = new Map() // ws -> {id, name, platform, outputs}

function deviceList() {
  return [...devices.values()]
}

function broadcast(msg, except) {
  const data = JSON.stringify(msg)
  for (const ws of devices.keys()) {
    if (ws !== except && ws.readyState === ws.OPEN) ws.send(data)
  }
}

function broadcastState() {
  state.rev++
  persist()
  broadcast({ type: 'state', state, devices: deviceList() })
}

function applyCmd(ws, msg) {
  const dev = devices.get(ws)
  if (!dev) return
  switch (msg.action) {
    case 'setQueue':
      state.queue = Array.isArray(msg.queue) ? msg.queue : []
      state.index = Number.isInteger(msg.index) ? msg.index : 0
      state.position = { pos: 0, ts: Date.now() }
      if (msg.play !== false) {
        state.playing = true
        if (!state.ownerId) state.ownerId = dev.id
      }
      break
    case 'play':
      state.playing = true
      if (!state.ownerId) state.ownerId = dev.id
      break
    case 'pause':
      state.playing = false
      break
    case 'seek':
      state.position = { pos: Number(msg.pos) || 0, ts: Date.now() }
      break
    case 'next':
    case 'prev': {
      const step = msg.action === 'next' ? 1 : -1
      if (state.queue.length === 0) return
      state.index =
        (state.index + step + state.queue.length) % state.queue.length
      state.position = { pos: 0, ts: Date.now() }
      break
    }
    case 'transfer':
      if (deviceList().some((d) => d.id === msg.to)) state.ownerId = msg.to
      break
    default:
      return
  }
  broadcastState()
}

wss.on('connection', (ws) => {
  ws.on('message', (raw) => {
    let msg
    try {
      msg = JSON.parse(raw)
    } catch {
      return
    }
    switch (msg.type) {
      case 'hello': {
        const d = msg.device || {}
        devices.set(ws, {
          id: String(d.id || `dev-${Math.random().toString(36).slice(2, 8)}`),
          name: String(d.name || 'unknown'),
          platform: String(d.platform || 'unknown'),
          outputs: Array.isArray(d.outputs) ? d.outputs : [],
        })
        ws.send(
          JSON.stringify({
            type: 'sync',
            you: devices.get(ws).id,
            state,
            devices: deviceList(),
          }),
        )
        broadcast({ type: 'devices', devices: deviceList() }, ws)
        break
      }
      case 'cmd':
        applyCmd(ws, msg)
        break
      case 'position': {
        const dev = devices.get(ws)
        if (!dev || dev.id !== state.ownerId) return
        state.position = { pos: Number(msg.pos) || 0, ts: Date.now() }
        persist()
        broadcast({ type: 'position', position: state.position }, ws)
        break
      }
      case 'ping':
        ws.send(JSON.stringify({ type: 'pong' }))
        break
    }
  })

  ws.on('close', () => {
    const dev = devices.get(ws)
    devices.delete(ws)
    if (!dev) return
    if (dev.id === state.ownerId) {
      state.ownerId = null
      state.playing = false
      broadcastState()
    } else {
      broadcast({ type: 'devices', devices: deviceList() })
    }
  })
})

module.exports = { wss, getState: () => state, deviceList }
