// ── 路径解析 ──
// service/web/server/src/config.js → service/web/server → service/web → service → ROOT

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'
import { readFileSync } from 'node:fs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// service/web/server/src → service/web/server → service/web → service → ROOT
export const ROOT = resolve(__dirname, '../../../..')
export const ENGINE = join(ROOT, 'service/engine/cmd/entry.sh')
export const BACKUP_ROOT = join(ROOT, 'backups')

// ── 加载 global.env 和 web.env（若存在）到 process.env ──
// 优先级：已有环境变量 > .env 文件中的值（不覆盖显式传入的 env）
const envFiles = [
  ['global.env', join(ROOT, 'global.env')],
  ['web.env', join(ROOT, 'service/web.env')],
]
for (const [, envPath] of envFiles) {
  try {
    const content = readFileSync(envPath, 'utf-8')
    for (const line of content.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const eq = trimmed.indexOf('=')
      if (eq === -1) continue
      const key = trimmed.slice(0, eq).trim()
      const val = trimmed.slice(eq + 1).trim()
      if (key && !(key in process.env)) {
        process.env[key] = val
      }
    }
  } catch {
    // .env 文件不存在时静默忽略
  }
}

// ── 服务配置 ──
export const PORT = parseInt(process.env.PORT, 10) || 3001
export const HOST = process.env.HOST || '0.0.0.0'

// ── 静态文件目录（生产模式） ──
export const STATIC_DIR = resolve(__dirname, '../static')

// ── 任务 TTL（完成后的保留秒数） ──
export const TASK_TTL_MS = 5 * 60 * 1000
