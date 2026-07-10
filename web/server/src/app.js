// ── Fastify 应用入口 ──
// 注册路由、静态文件托管、启动服务

import Fastify from 'fastify'
import { PORT, HOST, STATIC_DIR } from './config.js'
import appsRoutes from './routes/apps.js'
import backupRoutes from './routes/backup.js'
import restoreRoutes from './routes/restore.js'
import deployRoutes from './routes/deploy.js'
import eventsRoutes from './routes/events.js'
import settingsRoutes from './routes/settings.js'

export async function buildApp(opts = {}) {
  const fastify = Fastify({
    logger: opts.logger !== undefined ? opts.logger : {
      level: process.env.LOG_LEVEL || 'info',
    },
  })

  // ── 静态文件托管（生产模式，如果存在） ──
  try {
    const { stat } = await import('node:fs/promises')
    const st = await stat(STATIC_DIR)
    if (st.isDirectory()) {
      // 尝试读取 index.html 确认有构建产物
      await import('node:fs/promises').then(fs =>
        fs.stat(`${STATIC_DIR}/index.html`)
      )
      // 静态文件路由放在最后（避免覆盖 API）
      fastify.get('/', (_req, reply) => {
        return reply.sendFile('index.html')
      })
      fastify.get('/assets/*', (req, reply) => {
        return reply.sendFile(req.url.slice(1))
      })
      fastify.log.info(`静态文件目录: ${STATIC_DIR}`)
    }
  } catch {
    fastify.log.info('无静态文件目录，仅提供 API')
  }

  // ── JSON 内容类型 ──
  fastify.addContentTypeParser('application/json', { parseAs: 'string' }, (_req, body, done) => {
    try {
      done(null, JSON.parse(body))
    } catch (err) {
      done(err, undefined)
    }
  })

  // ── 注册路由 ──
  await fastify.register(appsRoutes)
  await fastify.register(backupRoutes)
  await fastify.register(restoreRoutes)
  await fastify.register(deployRoutes)
  await fastify.register(eventsRoutes)
  await fastify.register(settingsRoutes)

  return fastify
}

// ── 直接启动 ──
const isMain = process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/^\.\//, ''))
if (isMain) {
  const app = await buildApp()
  try {
    await app.listen({ port: PORT, host: HOST })
    app.log.info(`Server listening on http://${HOST}:${PORT}`)
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}
