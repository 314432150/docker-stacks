// ── Session 认证钩子 ──
// 当 WEB_USER / WEB_PASS 被设置时，校验所有 API 请求的会话凭据
// 未设置凭据时，钩子无操作（向后兼容）

import { timingSafeEqual } from 'node:crypto'
import { getSession } from './session.js'

const SKIP_PREFIXES = ['/api/events', '/api/auth/']

function isExempt(url) {
  // 静态文件免认证（SPA 需要先加载才能看到登录页）
  if (!url.startsWith('/api/')) return true
  // API 认证例外：登录/登出/状态/SSE
  return SKIP_PREFIXES.some(p => url.startsWith(p))
}

export function isAuthEnabled() {
  return !!(process.env.WEB_USER && process.env.WEB_PASS)
}

/** 校验用户名密码（定时攻击安全比较） */
export function checkCredentials(candidateUser, candidatePass) {
  const user = process.env.WEB_USER
  const pass = process.env.WEB_PASS
  if (!user || !pass) return { valid: false }
  if (!candidateUser || !candidatePass) return { valid: false, reason: 'missing' }

  const expectedUser = Buffer.from(user)
  const givenUser = Buffer.from(candidateUser)
  const expectedPass = Buffer.from(pass)
  const givenPass = Buffer.from(candidatePass)

  if (expectedUser.length !== givenUser.length || expectedPass.length !== givenPass.length) {
    return { valid: false, reason: 'mismatch' }
  }
  if (!timingSafeEqual(expectedUser, givenUser) || !timingSafeEqual(expectedPass, givenPass)) {
    return { valid: false, reason: 'mismatch' }
  }
  return { valid: true }
}

export function addAuthHook(fastify) {
  if (isAuthEnabled()) {
    fastify.log.info(`认证已启用（用户: ${process.env.WEB_USER}）`)
  } else {
    fastify.log.info('认证已禁用（未设置 WEB_USER / WEB_PASS）')
  }

  fastify.addHook('onRequest', async (request, reply) => {
    if (!isAuthEnabled()) return
    if (isExempt(request.url)) return

    const session = getSession(request)
    if (!session || session.user !== process.env.WEB_USER) {
      reply.code(401).send({
        error: true,
        code: 'UNAUTHORIZED',
        message: '未登录或会话已过期',
      })
    }
  })
}
