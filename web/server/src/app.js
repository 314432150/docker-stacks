// ── Fastify 应用入口 ──
// 注册路由、静态文件托管、启动服务

import Fastify from 'fastify'
import fastifyCookie from '@fastify/cookie'
import fastifyStatic from '@fastify/static'
import { PORT, HOST, STATIC_DIR } from './config.js'
import { addAuthHook } from './plugins/auth.js'
import appsRoutes from './routes/apps.js'
import backupRoutes from './routes/backup.js'
import restoreRoutes from './routes/restore.js'
import deployRoutes from './routes/deploy.js'
import eventsRoutes from './routes/events.js'
import settingsRoutes from './routes/settings.js'
import backupsRoutes from './routes/backups.js'
import historyRoutes from './routes/history.js'
import authRoutes from './routes/auth.js'
import statusRoutes from './routes/status.js'

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
      await import('node:fs/promises').then(fs =>
        fs.stat(`${STATIC_DIR}/index.html`)
      )
      await fastify.register(fastifyStatic, {
        root: STATIC_DIR,
        prefix: '/',
        index: false,
        wildcard: false,
      })
      // SPA 回退：非 API 路径返回 index.html
      fastify.setNotFoundHandler((req, reply) => {
        if (req.url.startsWith('/api/')) {
          return reply.code(404).send({ error: true, code: 'NOT_FOUND', message: '接口不存在' })
        }
        return reply.sendFile('index.html', STATIC_DIR)
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

  // ── Cookie 解析（Session 依赖） ──
  await fastify.register(fastifyCookie, {
    secret: process.env.COOKIE_SECRET || 'ds-cookie-secret-change-me',
  })

  // ── 认证钩子（根作用域，覆盖全部路由） ──
  addAuthHook(fastify)

  // ── 注册路由 ──
  await fastify.register(authRoutes)
  await fastify.register(appsRoutes)
  await fastify.register(backupRoutes)
  await fastify.register(restoreRoutes)
  await fastify.register(deployRoutes)
  await fastify.register(eventsRoutes)
  await fastify.register(settingsRoutes)
  await fastify.register(backupsRoutes)
  await fastify.register(historyRoutes)
  await fastify.register(statusRoutes)

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
