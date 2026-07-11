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

// ── 全局认证守卫：未登录 → 跳转登录页；未初始化 → 初始化页 ──
let authChecked = false
let isAuthenticated = false
let setupNeeded = false

router.beforeEach(async (to) => {
  // 登录页免检（含初始化模式）
  if (to.meta.guest) return true

  // 首次导航时检查认证状态
  if (!authChecked) {
    try {
      const res = await fetch('/api/auth/status')
      const data = await res.json()
      isAuthenticated = data.authenticated
      setupNeeded = data.needsSetup || false
    } catch {
      isAuthenticated = false
      setupNeeded = false
    }
    authChecked = true
  }

  if (setupNeeded) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }

  if (!isAuthenticated) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  return true
})

const app = createApp(App)
app.use(naive)
app.use(router)
app.mount('#app')
