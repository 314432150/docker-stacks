import { fetchWithError } from './useSSE.js'

// ── 简易内存缓存：30 秒 TTL + 请求去重 ──
const CACHE_TTL = 30_000
const _cache = new Map()

/**
 * 带缓存的请求包装器
 * - 缓存命中时直接返回已有 promise（相同的 inflight 请求也会复用）
 * - 缓存过期后自动重取
 * - force=true 跳过缓存强制刷新
 */
function withCache(key, fetcher, { ttl = CACHE_TTL, force = false } = {}) {
  if (!force) {
    const entry = _cache.get(key)
    if (entry && Date.now() - entry.time < ttl) {
      return entry.promise
    }
  }
  const promise = fetcher()
    .then(data => {
      const e = _cache.get(key)
      if (e && e.promise === promise) e.time = Date.now()
      return data
    })
    .catch(err => {
      _cache.delete(key)
      throw err
    })
  _cache.set(key, { promise, time: Date.now() })
  return promise
}

/**
 * 清除指定 key 的缓存（操作类接口调用后可用于主动失效）
 */
export function invalidateCache(key) {
  _cache.delete(key)
}

/**
 * 清空全部缓存（主要用于测试环境重置）
 */
export function resetCache() {
  _cache.clear()
}

export async function runBackup(apps, { upload = false, keep = 0, dirs = null } = {}) {
  const body = { apps, upload, keep }
  if (dirs) body.dirs = dirs
  const res = await fetchWithError('/api/backup', {
    method: 'POST',
    body,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `备份请求失败 (${res.status})`)
  }
  return await res.json()
}

export async function runRestore(archive, apps) {
  const res = await fetchWithError('/api/restore', {
    method: 'POST',
    body: { archive, apps },
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `还原请求失败 (${res.status})`)
  }
  return await res.json()
}

export async function runDeploy(apps) {
  const res = await fetchWithError('/api/deploy', {
    method: 'POST',
    body: { apps },
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `部署请求失败 (${res.status})`)
  }
  return await res.json()
}

export async function fetchApps({ force = false } = {}) {
  return withCache('apps', async () => {
    const res = await fetchWithError('/api/apps')
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.message || `获取应用列表失败 (${res.status})`)
    }
    return await res.json()
  }, { force })
}

export async function fetchBackups() {
  const res = await fetchWithError('/api/backups')
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `获取备份列表失败 (${res.status})`)
  }
  return await res.json()
}

export async function deleteBackup(name) {
  const res = await fetchWithError(`/api/backups/${encodeURIComponent(name)}`, {
    method: 'DELETE',
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `删除备份失败 (${res.status})`)
  }
  return await res.json()
}

export async function fetchWebdavSettings() {
  const res = await fetchWithError('/api/settings/webdav')
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `获取 WebDAV 设置失败 (${res.status})`)
  }
  return await res.json()
}

export async function saveWebdavSettings({ url, user, pass }) {
  const res = await fetchWithError('/api/settings/webdav', {
    method: 'PUT',
    body: { url, user, pass },
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `保存 WebDAV 设置失败 (${res.status})`)
  }
  return await res.json()
}

export async function testWebdavConnection({ url, user, pass } = {}) {
  const body = {}
  if (url) body.url = url
  if (user) body.user = user
  if (pass) body.pass = pass
  const res = await fetchWithError('/api/settings/webdav/test', {
    method: 'POST',
    ...(Object.keys(body).length > 0 ? { body } : {}),
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `WebDAV 连接测试失败 (${res.status})`)
  }
  return await res.json()
}

export async function fetchContainerStatus() {
  const res = await fetchWithError('/api/apps/status')
  if (!res.ok) {
    // 静默失败：容器状态查询是辅助功能
    return { containers: {} }
  }
  return await res.json()
}
