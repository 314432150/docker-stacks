// ═══════════════════════════════════════════════════════════════
// E2E 共享认证辅助：通过后端 API 登录，获取 session cookie
// ═══════════════════════════════════════════════════════════════
const API_URL = 'http://127.0.0.1:3001'

export async function loginViaApi(request) {
  const res = await request.post(`${API_URL}/api/auth/login`, {
    data: { user: 'fishme', pass: 'Wxl196819!d' },
  })
  if (!res.ok()) {
    throw new Error(`Login failed: ${res.status()} ${await res.text()}`)
  }
  // 返回 cookies 数组，用于 page.context().addCookies()
  const cookies = res.headers()['set-cookie']
  if (!cookies) throw new Error('No set-cookie header in login response')
  const dsSidCookie = cookies.split(';')[0]  // "ds-sid=xxx" 部分
  const value = dsSidCookie.split('=')[1]
  return [{
    name: 'ds-sid',
    value,
    domain: 'localhost',
    path: '/',
    httpOnly: true,
    sameSite: 'Lax',
  }]
}

/** 在测试前完成登录，注入 cookie */
export async function authenticatePage(page, request) {
  const cookies = await loginViaApi(request)
  await page.context().addCookies(cookies)
}
