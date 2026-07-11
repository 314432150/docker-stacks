// ── 路径解析 ──
// service/web/server/src/config.js → service/web/server → service/web → service → ROOT

import { join, resolve } from 'node:path'
import { initSettings } from './db/settings.js'

// service/web/server/src → service/web/server → service/web → service → ROOT
export const ROOT = resolve(import.meta.dirname, '../../../..')
export const ENGINE = join(ROOT, 'service/engine/cmd/entry.sh')
export const BACKUP_ROOT = join(ROOT, 'instance/backups')

// ── 加载 settings（JSON） → process.env ──
// 首次启动时自动从旧 web.env 迁移；之后所有读写走 settings.json
initSettings(join(ROOT, 'service/web.env'))

// ── 服务配置 ──
export const PORT = parseInt(process.env.PORT, 10) || 3001
export const HOST = process.env.HOST || '0.0.0.0'

// ── 静态文件目录（生产模式） ──
export const STATIC_DIR = resolve(import.meta.dirname, '../static')

// ── 任务 TTL（完成后的保留秒数） ──
export const TASK_TTL_MS = 5 * 60 * 1000
