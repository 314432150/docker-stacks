export async function fetchWithError(url, options = {}) {
  const { body, ...rest } = options
  const fetchOptions = {
    ...rest,
    headers: { 'Content-Type': 'application/json', ...options.headers },
  }
  if (body) {
    fetchOptions.body = JSON.stringify(body)
  }
  const res = await fetch(url, fetchOptions)

  // 401 未认证 → 跳转登录页
  if (res.status === 401) {
    const isAuthEndpoint = url.startsWith('/api/auth/')
    if (!isAuthEndpoint) {
      // 避免重复跳转（仅在非 auth 端点且当前不在登录页时重定向）
      if (!window.location.hash.startsWith('#/login')) {
        window.location.hash = '#/login'
      }
    }
  }

  return res
}

export function getSSEUrl(taskId) {
  return `/api/events?taskId=${encodeURIComponent(taskId)}`
}
