// ── 路径解析 ──
// web/server/src/config.js → web/server → web → ROOT

import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// web/server/src → web/server → web → ROOT
export const ROOT = resolve(__dirname, '../../..')
export const ENGINE = join(ROOT, 'scripts/engine/engine.sh')
export const BACKUP_ROOT = join(ROOT, 'backups')

// ── 服务配置 ──
export const PORT = parseInt(process.env.PORT, 10) || 3001
export const HOST = process.env.HOST || '0.0.0.0'

// ── 静态文件目录（生产模式） ──
export const STATIC_DIR = resolve(__dirname, '../static')

// ── 任务 TTL（完成后的保留秒数） ──
export const TASK_TTL_MS = 5 * 60 * 1000
