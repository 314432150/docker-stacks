// ── HTTP Basic Auth 钩子 ──
// 当环境变量 WEB_USER / WEB_PASS 被设置时，校验所有 API 请求的 Basic Auth 凭据
// 未设置凭据时，钩子无操作（向后兼容，第一阶段可无认证运行）
//
// SSE 端点 (/api/events) 免认证：浏览器 EventSource API 不支持自定义请求头，
// 且 SSE 连接本身依赖不可猜测的 taskId 作为能力令牌。
//
// 注意：直接 addHook 到根实例而非通过 register 封装，
// 确保钩子覆盖所有路由（跨 Fastify 注册作用域）。

import { timingSafeEqual } from 'node:crypto'

const SKIP_PREFIXES = ['/api/events']

function isExempt(url) {
  return SKIP_PREFIXES.some(p => url.startsWith(p))
}

/** 检测认证是否启用 */
export function isAuthEnabled() {
  return !!(process.env.WEB_USER && process.env.WEB_PASS)
}

/** 校验凭据 */
function checkCredentials(authHeader) {
  const user = process.env.WEB_USER
  const pass = process.env.WEB_PASS
  const expected = Buffer.from(`${user}:${pass}`)

  if (!authHeader || !authHeader.startsWith('Basic ')) {
    return { valid: false, reason: 'missing' }
  }

  const encoded = authHeader.slice(6)
  const buf = Buffer.from(encoded, 'base64')

  // 长度不同 → 必定不匹配（timingSafeEqual 强制等长，此处已泄露长度差）
  if (buf.length !== expected.length) {
    return { valid: false, reason: 'mismatch' }
  }

  if (!timingSafeEqual(buf, expected)) {
    return { valid: false, reason: 'mismatch' }
  }

  return { valid: true }
}

/**
 * 向 Fastify 实例添加认证 onRequest 钩子
 * 必须在路由注册之前调用
 */
export function addAuthHook(fastify) {
  if (isAuthEnabled()) {
    fastify.log.info(`认证已启用（用户: ${process.env.WEB_USER}）`)
  } else {
    fastify.log.info('认证已禁用（未设置 WEB_USER / WEB_PASS）')
  }

  fastify.addHook('onRequest', async (request, reply) => {
    if (!isAuthEnabled()) return
    if (isExempt(request.url)) return

    const result = checkCredentials(request.headers.authorization)
    if (!result.valid) {
      reply.header('WWW-Authenticate', 'Basic realm="docker-stacks"')
      reply.code(401).send({
        error: true,
        code: 'UNAUTHORIZED',
        message: result.reason === 'missing' ? '需要认证' : '认证失败',
      })
    }
  })
}
