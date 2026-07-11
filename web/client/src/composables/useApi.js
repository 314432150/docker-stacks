import { fetchWithError } from './useSSE.js'

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

export async function fetchApps() {
  const res = await fetchWithError('/api/apps')
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `获取应用列表失败 (${res.status})`)
  }
  return await res.json()
}

export async function fetchBackups() {
  const res = await fetchWithError('/api/backups')
  if (!res.ok) {
    const err = await res.json().catch(() => ({}))
    throw new Error(err.message || `获取备份列表失败 (${res.status})`)
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
