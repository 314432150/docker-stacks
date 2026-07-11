import { reactive } from 'vue'

/**
 * 全局鉴权状态（单例）
 *
 * 独立文件以避免 main.js ↔ App.vue 循环引用导致的 authStore 不一致问题。
 * - main.js 的 router.beforeEach 写入 checked / isAuthenticated / setupNeeded / currentUser
 * - App.vue 及其他组件读取 currentUser 用于显示
 */

export const authStore = reactive({
  checked: false,
  isAuthenticated: false,
  setupNeeded: false,
  currentUser: '',
})

let checkAuthPromise = null

/**
 * 拉取鉴权状态（Promise 去重：同一时刻多次调用只发一次请求）
 */
export async function checkAuth() {
  if (checkAuthPromise) return checkAuthPromise
  if (authStore.checked) return

  checkAuthPromise = (async () => {
    try {
      const res = await fetch('/api/auth/status')
      const data = await res.json()
      authStore.isAuthenticated = data.authenticated
      authStore.setupNeeded = data.needsSetup || false
      authStore.currentUser = data.authenticated ? (data.user || '') : ''
    } catch {
      authStore.isAuthenticated = false
      authStore.setupNeeded = false
      authStore.currentUser = ''
    }
    authStore.checked = true
  })()

  await checkAuthPromise
  checkAuthPromise = null
}
