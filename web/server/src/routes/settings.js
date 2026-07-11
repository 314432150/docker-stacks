// ── GET/PUT /api/settings/webdav ──
// 读取/写入 global.env 中的 WEBDAV_* 配置

import { readFile, writeFile } from 'node:fs/promises'
import { spawn } from 'node:child_process'
import { ROOT } from '../config.js'
import { join } from 'node:path'

const ENV_FILE = join(ROOT, 'global.env')

async function parseWebdavSettings() {
  const content = await readFile(ENV_FILE, 'utf-8')
  const settings = {}
  for (const line of content.split('\n')) {
    const match = line.match(/^(WEBDAV_URL|WEBDAV_USER|WEBDAV_PASS)\s*=\s*(.+)/)
    if (match) {
      settings[match[1]] = match[2]
    }
  }
  return settings
}

async function writeWebdavSettings(url, user, pass) {
  const content = await readFile(ENV_FILE, 'utf-8')
  const lines = content.split('\n')
  const seen = { WEBDAV_URL: false, WEBDAV_USER: false, WEBDAV_PASS: false }

  const newLines = lines.map(line => {
    const trimmed = line.trim()
    for (const key of ['WEBDAV_URL', 'WEBDAV_USER', 'WEBDAV_PASS']) {
      if (trimmed.startsWith(`${key}=`) || trimmed.startsWith(`${key} =`)) {
        seen[key] = true
        if (key === 'WEBDAV_URL') return `WEBDAV_URL=${url}`
        if (key === 'WEBDAV_USER') return `WEBDAV_USER=${user}`
        if (key === 'WEBDAV_PASS') return `WEBDAV_PASS=${pass}`
      }
    }
    return line
  })

  // 追加不存在的配置项
  if (!seen.WEBDAV_URL) newLines.push(`WEBDAV_URL=${url}`)
  if (!seen.WEBDAV_USER) newLines.push(`WEBDAV_USER=${user}`)
  if (!seen.WEBDAV_PASS) newLines.push(`WEBDAV_PASS=${pass}`)

  await writeFile(ENV_FILE, newLines.join('\n'), 'utf-8')
}

export default async function settingsRoutes(fastify) {
  // ── GET: 返回当前 WebDAV 配置（密码脱敏） ──
  fastify.get('/api/settings/webdav', async (_request, reply) => {
    try {
      const settings = await parseWebdavSettings()
      const configured = !!(settings.WEBDAV_URL && settings.WEBDAV_USER && settings.WEBDAV_PASS)
      return {
        configured,
        url: settings.WEBDAV_URL || '',
        user: settings.WEBDAV_USER || '',
        // 密码仅返回是否已设置（不返回原文）
        hasPassword: !!settings.WEBDAV_PASS,
      }
    } catch (err) {
      fastify.log.error({ err }, '读取 WebDAV 设置失败')
      return reply.code(500).send({
        error: true, code: 'SETTINGS_ERROR', message: `读取配置失败: ${err.message}`,
      })
    }
  })

  // ── PUT: 写入 WebDAV 配置 ──
  fastify.put('/api/settings/webdav', async (request, reply) => {
    const { url, user, pass } = request.body || {}

    if (typeof url !== 'string' || !url) {
      return reply.code(400).send({
        error: true, code: 'VALIDATION_ERROR', message: 'url 不能为空',
      })
    }
    if (typeof user !== 'string' || !user) {
      return reply.code(400).send({
        error: true, code: 'VALIDATION_ERROR', message: 'user 不能为空',
      })
    }
    if (typeof pass !== 'string' || !pass) {
      return reply.code(400).send({
        error: true, code: 'VALIDATION_ERROR', message: 'pass 不能为空',
      })
    }

    try {
      await writeWebdavSettings(url, user, pass)
      return { success: true, message: 'WebDAV 设置已保存' }
    } catch (err) {
      fastify.log.error({ err }, '写入 WebDAV 设置失败')
      return reply.code(500).send({
        error: true, code: 'SETTINGS_ERROR', message: `写入配置失败: ${err.message}`,
      })
    }
  })

  // ── POST: 测试 WebDAV 连接 ──
  fastify.post('/api/settings/webdav/test', async (_request, reply) => {
    let settings
    try {
      settings = await parseWebdavSettings()
    } catch (err) {
      return reply.code(500).send({
        error: true, code: 'SETTINGS_ERROR',
        message: `读取配置失败: ${err.message}`,
      })
    }

    const { WEBDAV_URL, WEBDAV_USER, WEBDAV_PASS } = settings
    if (!WEBDAV_URL || !WEBDAV_USER || !WEBDAV_PASS) {
      return reply.code(400).send({
        error: true, code: 'NOT_CONFIGURED',
        message: 'WebDAV 尚未完整配置（需要 URL、用户名、密码）',
      })
    }

    // 使用 curl PROPFIND 测试连接（与 webdav_connection_test 逻辑一致）
    const url = WEBDAV_URL.replace(/\/$/, '')
    try {
      const result = await new Promise((resolve, reject) => {
        const child = spawn('curl', [
          '-s', '-o', '/dev/null', '-w', '%{http_code}',
          '--max-time', '10',
          '-u', `${WEBDAV_USER}:${WEBDAV_PASS}`,
          '-X', 'PROPFIND',
          '-H', 'Depth: 0',
          `${url}/`,
        ], { timeout: 15000 })

        let stdout = ''
        let stderr = ''
        child.stdout.on('data', d => { stdout += d })
        child.stderr.on('data', d => { stderr += d })
        child.on('error', reject)
        child.on('close', code => resolve({ code, stdout: stdout.trim(), stderr }))
      })

      const httpCode = parseInt(result.stdout, 10)
      // 2xx 和 207 (Multi-Status) 都表示成功
      const success = httpCode >= 200 && httpCode < 400

      if (success) {
        return { success: true, message: `连接成功（HTTP ${httpCode}）`, httpCode }
      } else {
        return { success: false, message: `连接失败（HTTP ${httpCode}）`, httpCode }
      }
    } catch (err) {
      fastify.log.error({ err }, 'WebDAV 连接测试执行失败')
      return { success: false, message: `连接测试失败: ${err.message}` }
    }
  })
}
