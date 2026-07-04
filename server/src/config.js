const fs = require('fs')
const os = require('os')
const path = require('path')
const crypto = require('crypto')

const dataDir =
  process.env.FOLIA_DATA_DIR ||
  path.join(os.homedir(), 'Library', 'Application Support', 'folia-server')

fs.mkdirSync(dataDir, { recursive: true })

const tokenPath = path.join(dataDir, 'token')
if (!fs.existsSync(tokenPath)) {
  fs.writeFileSync(tokenPath, crypto.randomBytes(24).toString('hex'), {
    mode: 0o600,
  })
}

module.exports = {
  dataDir,
  port: Number(process.env.FOLIA_PORT || 3766),
  host: process.env.FOLIA_HOST || '0.0.0.0',
  token: fs.readFileSync(tokenPath, 'utf-8').trim(),
  tokenPath,
  cookiePath: path.join(dataDir, 'cookie.json'),
  statePath: path.join(dataDir, 'state.json'),
}
