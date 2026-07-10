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
  return res
}

export function getSSEUrl(taskId) {
  return `/api/events?taskId=${encodeURIComponent(taskId)}`
}
