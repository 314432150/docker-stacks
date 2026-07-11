// ── 认证路由：登录 / 登出 / 状态 / 初始化 / 修改凭据 ──

import { createSession, destroySession, getSession } from '../plugins/session.js'
import { isAuthEnabled, needsSetup, checkCredentials, getStoredUser } from '../plugins/auth.js'
import { validateLoginInput } from '../validate.js'
import { setAuthCredentials } from '../db/settings.js'

export default async function authRoutes(fastify) {
  // POST /api/auth/login — 登录
  fastify.post('/api/auth/login', async (request, reply) => {
    if (!isAuthEnabled()) {
      return { ok: true, user: null, message: '认证未启用', needsSetup: true }
    }

    const { user, pass, remember } = request.body || {}

    const validation = validateLoginInput(user, pass)
    if (!validation.valid) {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: validation.message }
    }

    const result = await checkCredentials(user.trim(), pass)

    if (!result.valid) {
      reply.code(401)
      return { error: true, code: 'AUTH_FAILED', message: '用户名或密码错误' }
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
    const setupNeeded = needsSetup()

    if (setupNeeded) {
      return { ok: true, authenticated: false, authEnabled: false, needsSetup: true }
    }

    const session = getSession(request)
    if (session && session.user === getStoredUser()) {
      return { ok: true, authenticated: true, user: session.user, authEnabled: true, needsSetup: false }
    }

    return { ok: true, authenticated: false, authEnabled: true, needsSetup: false }
  })

  // POST /api/auth/setup — 初始化管理员账户
  fastify.post('/api/auth/setup', async (request, reply) => {
    // 仅在未初始化时允许
    if (!needsSetup()) {
      reply.code(409)
      return { error: true, code: 'ALREADY_SETUP', message: '管理员账户已存在' }
    }

    const { user, pass, remember } = request.body || {}

    const validation = validateLoginInput(user, pass)
    if (!validation.valid) {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: validation.message }
    }

    try {
      await setAuthCredentials(user.trim(), pass)
    } catch (e) {
      reply.code(500)
      return { error: true, code: 'INTERNAL_ERROR', message: `初始化失败: ${e.message}` }
    }

    // 初始化后自动签发 session
    reply.code(201)
    createSession(user.trim(), reply, remember !== false)
    return { ok: true, user: user.trim() }
  })

  // PUT /api/auth/credentials — 修改管理员凭据（需已登录）
  fastify.put('/api/auth/credentials', async (request, reply) => {
    const { oldPass, newUser, newPass } = request.body || {}

    // 需要认证：此路由位于 /api/auth/ 下，被全局钩子豁免，手动校验
    const session = getSession(request)
    if (!session) {
      reply.code(401)
      return { error: true, code: 'UNAUTHORIZED', message: '未登录或会话已过期' }
    }
    if (!oldPass || typeof oldPass !== 'string') {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: '请输入旧密码' }
    }
    if (!newPass || typeof newPass !== 'string') {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: '请输入新密码' }
    }
    if (newPass.length > 128) {
      reply.code(400)
      return { error: true, code: 'INVALID_INPUT', message: '新密码长度不能超过 128 个字符' }
    }

    // 验证旧密码
    const storedUser = newUser?.trim() || getStoredUser()
    const result = await checkCredentials(storedUser, oldPass)
    if (!result.valid) {
      reply.code(401)
      return { error: true, code: 'AUTH_FAILED', message: '旧密码错误' }
    }

    try {
      await setAuthCredentials(storedUser, newPass)
    } catch (e) {
      reply.code(500)
      return { error: true, code: 'INTERNAL_ERROR', message: `修改密码失败: ${e.message}` }
    }

    // 销毁旧 session，用户需重新登录
    destroySession(request, reply)
    return { ok: true, message: '密码已修改，请重新登录' }
  })
}
