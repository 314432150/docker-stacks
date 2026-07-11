// ── Session 认证钩子 ──
// 凭据存储在 settings.json（webUser + webPassHash）
// 首次运行时无凭据 → needsSetup 模式，setup 接口免认证
// 已配置凭据 → 所有 /api/* 请求需有效 session

import { timingSafeEqual } from 'node:crypto'
import { getSession } from './session.js'
import { getAuthCredentials, verifyPassword } from '../db/settings.js'

const SKIP_PREFIXES = ['/api/events', '/api/auth/']

function isExempt(url) {
  if (!url.startsWith('/api/')) return true
  return SKIP_PREFIXES.some(p => url.startsWith(p))
}

/** 检查是否已配置管理员凭据 */
export function isAuthEnabled() {
  const { user, passHash } = getAuthCredentials()
  return !!(user && passHash)
}

/** 检查是否需要初始化（无凭据） */
export function needsSetup() {
  return !isAuthEnabled()
}

/**
 * 校验用户名密码
 * @returns {Promise<{ valid: boolean, reason?: string }>}
 */
export async function checkCredentials(candidateUser, candidatePass) {
  const { user, passHash } = getAuthCredentials()
  if (!user || !passHash) return { valid: false, reason: 'not_configured' }
  if (!candidateUser || !candidatePass) return { valid: false, reason: 'missing' }

  const expectedUser = Buffer.from(user)
  const givenUser = Buffer.from(candidateUser)
  if (expectedUser.length !== givenUser.length || !timingSafeEqual(expectedUser, givenUser)) {
    return { valid: false, reason: 'mismatch' }
  }

  const passOk = await verifyPassword(candidatePass, passHash)
  if (!passOk) return { valid: false, reason: 'mismatch' }
  return { valid: true }
}

/** 获取当前存储的用户名（供 session 校验） */
export function getStoredUser() {
  return getAuthCredentials().user
}

export function addAuthHook(fastify) {
  if (isAuthEnabled()) {
    fastify.log.info(`认证已启用（用户: ${getAuthCredentials().user}）`)
  } else {
    fastify.log.info('认证已禁用（等待初始化管理员账户）')
  }

  fastify.addHook('onRequest', async (request, reply) => {
    if (!isAuthEnabled()) return
    if (isExempt(request.url)) return

    const session = getSession(request)
    if (!session || session.user !== getStoredUser()) {
      reply.code(401).send({
        error: true,
        code: 'UNAUTHORIZED',
        message: '未登录或会话已过期',
      })
    }
  })
}
