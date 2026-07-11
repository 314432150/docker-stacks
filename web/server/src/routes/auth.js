// ── 认证路由：登录 / 登出 / 状态 ──

import { createSession, destroySession, getSession } from '../plugins/session.js'
import { isAuthEnabled, checkCredentials } from '../plugins/auth.js'
import { validateLoginInput } from '../validate.js'

export default async function authRoutes(fastify) {
  // POST /api/auth/login — 登录
  fastify.post('/api/auth/login', async (request, reply) => {
    if (!isAuthEnabled()) {
      return { ok: true, user: null, message: '认证未启用' }
    }

    const { user, pass, remember } = request.body || {}

    // 后端输入校验：拒绝空值 / 超长 / 非字符串
    const validation = validateLoginInput(user, pass)
    if (!validation.valid) {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: validation.message }
    }

    const result = checkCredentials(user.trim(), pass)

    if (!result.valid) {
      reply.code(401)
      return {
        error: true,
        code: 'AUTH_FAILED',
        message: result.reason === 'mismatch' ? '用户名或密码错误' : '用户名或密码错误',
      }
    }

    createSession(user.trim(), reply, !!remember)
    return { ok: true, user: user.trim() }
  })

  // POST /api/auth/logout — 登出
  fastify.post('/api/auth/logout', async (request, reply) => {
    destroySession(request, reply)
    return { ok: true }
  })

  // GET /api/auth/status — 检查登录状态
  fastify.get('/api/auth/status', async (request) => {
    if (!isAuthEnabled()) {
      return { ok: true, authenticated: false, authEnabled: false }
    }

    const session = getSession(request)
    if (session && session.user === process.env.WEB_USER) {
      return { ok: true, authenticated: true, user: session.user }
    }

    return { ok: true, authenticated: false }
  })
}
