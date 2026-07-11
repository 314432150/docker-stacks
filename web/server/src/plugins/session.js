// ── 会话管理器（内存存储） ──
// 基于 @fastify/cookie 签名 Cookie
// 单实例部署场景，重启后所有会话失效（可接受）

import { randomBytes, timingSafeEqual } from 'node:crypto'

const SESSION_TTL = 24 * 60 * 60 * 1000     // 24 小时（默认）
const SESSION_TTL_REMEMBER = 7 * 24 * 60 * 60 * 1000  // 7 天（保持登录）
const COOKIE_NAME = 'ds-sid'
const COOKIE_OPTS = {
  path: '/',
  httpOnly: true,
  sameSite: 'lax',
  secure: false,           // 自托管内网环境，非 HTTPS
  maxAge: SESSION_TTL / 1000,
}

// 内存存储：Map<sessionId, { user, createdAt }>
const store = new Map()

/** 生成加密安全的会话 ID */
function generateId() {
  return randomBytes(32).toString('hex')
}

/** 创建会话，通过 reply 设置 Cookie。remember 为 true 时会话有效期延长至 7 天 */
export function createSession(user, reply, remember = false) {
  const id = generateId()
  const ttl = remember ? SESSION_TTL_REMEMBER : SESSION_TTL
  store.set(id, { user, createdAt: Date.now(), ttl })
  reply.setCookie(COOKIE_NAME, id, {
    ...COOKIE_OPTS,
    maxAge: ttl / 1000,
  })
}

/** 从 request 获取当前会话，无有效会话返回 null */
export function getSession(request) {
  const id = request.cookies[COOKIE_NAME]
  if (!id) return null
  const session = store.get(id)
  if (!session) return null
  // 过期检查（使用会话自身的 TTL）
  const ttl = session.ttl || SESSION_TTL
  if (Date.now() - session.createdAt > ttl) {
    store.delete(id)
    return null
  }
  return session
}

/** 销毁会话，清除 Cookie */
export function destroySession(request, reply) {
  const id = request.cookies[COOKIE_NAME]
  if (id) store.delete(id)
  reply.clearCookie(COOKIE_NAME, { path: '/' })
}
