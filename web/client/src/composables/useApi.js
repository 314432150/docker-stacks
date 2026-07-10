import { fetchWithError } from './useSSE.js'

export async function runBackup(apps, { upload = false, keep = 0 } = {}) {
  const res = await fetchWithError('/api/backup', {
    method: 'POST',
    body: { apps, upload, keep },
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
