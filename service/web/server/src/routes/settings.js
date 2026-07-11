// ── GET/PUT/POST /api/settings/webdav ──
// 读写 service/web/server/data/settings.json（不再逐行解析 service/web.env）

import { spawn } from 'node:child_process'
import { getWebdavSettings, setWebdavSettings } from '../db/settings.js'

export default async function settingsRoutes(fastify) {
  // ── GET: 返回当前 WebDAV 配置（密码脱敏） ──
  fastify.get('/api/settings/webdav', async (_request, reply) => {
    try {
      const { url, user, pass } = getWebdavSettings()
      const configured = !!(url && user && pass)
      return { configured, url, user, hasPassword: !!pass }
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
      setWebdavSettings({ url, user, pass })
      // 同步到 process.env（引擎子进程继承 env）
      process.env.WEBDAV_URL = url
      process.env.WEBDAV_USER = user
      process.env.WEBDAV_PASS = pass
      return { success: true, message: 'WebDAV 设置已保存' }
    } catch (err) {
      fastify.log.error({ err }, '写入 WebDAV 设置失败')
      return reply.code(500).send({
        error: true, code: 'SETTINGS_ERROR', message: `写入配置失败: ${err.message}`,
      })
    }
  })

  // ── POST: 测试 WebDAV 连接 ──
  fastify.post('/api/settings/webdav/test', async (request, reply) => {
    let settings
    try {
      settings = getWebdavSettings()
    } catch (err) {
      return reply.code(500).send({
        error: true, code: 'SETTINGS_ERROR',
        message: `读取配置失败: ${err.message}`,
      })
    }

    // 请求体参数优先级高于已存储配置（支持未保存前测试）
    const bodyUrl = (request.body?.url || '').trim()
    const bodyUser = (request.body?.user || '').trim()
    const bodyPass = (request.body?.pass || '').trim()

    const url = bodyUrl || settings.url || ''
    const user = bodyUser || settings.user || ''
    const pass = bodyPass || settings.pass || ''

    if (!url || !user || !pass) {
      return reply.code(400).send({
        error: true, code: 'NOT_CONFIGURED',
        message: 'WebDAV 尚未完整配置（需要 URL、用户名、密码）',
      })
    }

    // 使用 curl PROPFIND 测试连接（与 webdav_connection_test 逻辑一致）
    const testUrl = url.replace(/\/$/, '')
    try {
      const result = await new Promise((resolve, reject) => {
        const child = spawn('curl', [
          '-s', '-o', '/dev/null', '-w', '%{http_code}',
          '--max-time', '10',
          '-u', `${user}:${pass}`,
          '-X', 'PROPFIND',
          '-H', 'Depth: 0',
          `${testUrl}/`,
        ], { timeout: 15000 })

        let stdout = ''
        let stderr = ''
        child.stdout.on('data', d => { stdout += d })
        child.stderr.on('data', d => { stderr += d })
        child.on('error', reject)
        child.on('close', code => resolve({ code, stdout: stdout.trim(), stderr }))
      })

      const httpCode = parseInt(result.stdout, 10)
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
