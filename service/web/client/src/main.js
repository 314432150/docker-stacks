import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import naive from 'naive-ui'
import App from './App.vue'
import Dashboard from './views/Dashboard.vue'
import Backup from './views/Backup.vue'
import Restore from './views/Restore.vue'
import Deploy from './views/Deploy.vue'
import Settings from './views/Settings.vue'
import Login from './views/Login.vue'
import { authStore, checkAuth } from './composables/useAuth.js'

const routes = [
  { path: '/login', component: Login, meta: { guest: true } },
  { path: '/', component: Dashboard },
  { path: '/backup', component: Backup },
  { path: '/restore', component: Restore },
  { path: '/deploy', component: Deploy },
  { path: '/settings', component: Settings },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

// ── 同步路由守卫（鉴权已预初始化，仅读 authStore）──
router.beforeEach(async (to) => {
  if (to.meta.guest) {
    // 进入登录/初始化页：标记为未检查，让 Login.vue 主动重检
    // （仅在用户从已登录态登出时需要刷新状态，普通进入 /login 不必重检）
    if (authStore.isAuthenticated) {
      authStore.checked = false
    }
    return true
  }

  // 离开登录页：异步重检一次（鉴权状态可能已变化）
  if (!authStore.checked) {
    await checkAuth()
  }

  if (authStore.setupNeeded) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }

  if (!authStore.isAuthenticated) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  return true
})

// ── 启动：预初始化鉴权 → 创建 app → 挂载 ──
;(async () => {
  await checkAuth()

  const app = createApp(App)
  app.use(naive)
  app.use(router)
  await router.isReady()
  app.mount('#app')
})()
