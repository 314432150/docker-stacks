// ── service/web/server/data/settings.json 读写模块 ──
// 零依赖，原子写入（write+rename），文件不存在时返回空默认值

import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { randomUUID } from 'node:crypto'

const DATA_DIR = join(import.meta.dirname, '../../data')
const FILE = join(DATA_DIR, 'settings.json')

// ── 内部：原子写入 ──
function atomicWrite(data) {
  mkdirSync(DATA_DIR, { recursive: true })
  const tmp = join(tmpdir(), `settings-${randomUUID()}.json`)
  writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', 'utf-8')
  renameSync(tmp, FILE)
}

// ── 内部：读取原始数据 ──
function read() {
  try {
    return JSON.parse(readFileSync(FILE, 'utf-8'))
  } catch {
    // 文件不存在或格式损坏 → 返回空结构
    return {}
  }
}

// ── 迁移：首次启动时从旧 web.env 导入数据 ──
function migrateFromEnv(oldEnvPath) {
  if (existsSync(FILE)) return // settings.json 已存在，跳过
  if (!existsSync(oldEnvPath)) return

  const env = {}
  const content = readFileSync(oldEnvPath, 'utf-8')
  for (const line of content.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq === -1) continue
    env[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim()
  }

  const webdav = {}
  if (env.WEBDAV_URL) webdav.url = env.WEBDAV_URL
  if (env.WEBDAV_USER) webdav.user = env.WEBDAV_USER
  if (env.WEBDAV_PASS) webdav.pass = env.WEBDAV_PASS

  if (Object.keys(webdav).length > 0) {
    atomicWrite({ webdav })
  }
}

// ── 公开 API ──

/** 获取 WebDAV 配置 */
export function getWebdavSettings() {
  const data = read()
  const w = data.webdav || {}
  return {
    url: w.url || '',
    user: w.user || '',
    pass: w.pass || '',
  }
}

/** 写入 WebDAV 配置 */
export function setWebdavSettings({ url, user, pass }) {
  const data = read()
  data.webdav = { url, user, pass }
  atomicWrite(data)
}

/** 初始化：迁移旧配置 → 注入 process.env */
export function initSettings(oldEnvPath) {
  migrateFromEnv(oldEnvPath)

  const { url, user, pass } = getWebdavSettings()
  if (url && !process.env.WEBDAV_URL) process.env.WEBDAV_URL = url
  if (user && !process.env.WEBDAV_USER) process.env.WEBDAV_USER = user
  if (pass && !process.env.WEBDAV_PASS) process.env.WEBDAV_PASS = pass
}

/** 获取 settings.json 文件路径（供 shell 脚本参考） */
export const SETTINGS_FILE = FILE
