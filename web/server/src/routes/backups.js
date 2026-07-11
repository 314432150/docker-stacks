// ── GET /api/backups ──
// 返回 backups/ 下所有 *.tar.gz 文件列表
// 优先读取同名的 .json 索引文件（备份时自动生成），无索引时回退到 tar -tzf

import { resolve } from 'node:path'
import { readdir, stat, readFile } from 'node:fs/promises'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { BACKUP_ROOT } from '../config.js'

const execFileP = promisify(execFile)

/** 从 tar 内容中解析顶级 app 名（回退方案） */
function parseAppNames(stdout) {
  const names = new Set()
  for (const line of stdout.split('\n')) {
    const m = line.match(/^stacks\/([^/]+)\//)
    if (m) names.add(m[1])
  }
  return [...names].sort()
}

/** 读取 .tar.gz.json 索引文件 */
async function readIndex(fullPath) {
  try {
    const raw = await readFile(fullPath + '.json', 'utf-8')
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/** 回退：tar -tzf 解析 app 列表 */
async function readAppsFromTar(fullPath) {
  try {
    const { stdout } = await execFileP('tar', ['-tzf', fullPath], {
      timeout: 10000,
      maxBuffer: 1024 * 1024,
    })
    return parseAppNames(stdout)
  } catch {
    return []
  }
}

export default async function backupsRoutes(fastify) {
  fastify.get('/api/backups', async (_request, reply) => {
    try {
      const entries = await readdir(BACKUP_ROOT)
      const tarFiles = entries.filter(f => f.endsWith('.tar.gz'))

      const files = []
      for (const name of tarFiles) {
        const fullPath = resolve(BACKUP_ROOT, name)
        try {
          // 优先读索引文件（备份时自动生成，速度快）
          const idx = await readIndex(fullPath)
          if (idx && Array.isArray(idx.apps)) {
            files.push({
              name: idx.name || name,
              size: idx.size,
              mtime: idx.mtime,
              apps: idx.apps,
            })
            continue
          }

          // 回退：无索引文件时 stat + tar 解析
          const st = await stat(fullPath)
          const apps = await readAppsFromTar(fullPath)
          files.push({
            name,
            size: st.size,
            mtime: st.mtime.toISOString(),
            apps,
          })
        } catch {
          // 跳过无法读取的文件
        }
      }

      // 按时间降序
      files.sort((a, b) => b.mtime.localeCompare(a.mtime))

      return { files }
    } catch (err) {
      fastify.log.error({ err }, 'failed to list backups')
      return reply.code(500).send({
        error: true,
        code: 'INTERNAL_ERROR',
        message: `无法列出备份文件: ${err.message}`,
      })
    }
  })
}
