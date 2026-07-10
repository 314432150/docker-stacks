import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import naive from 'naive-ui'
import App from './App.vue'
import Dashboard from './views/Dashboard.vue'
import Backup from './views/Backup.vue'
import Restore from './views/Restore.vue'
import Deploy from './views/Deploy.vue'

const routes = [
  { path: '/', component: Dashboard },
  { path: '/backup', component: Backup },
  { path: '/restore', component: Restore },
  { path: '/deploy', component: Deploy },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

const app = createApp(App)
app.use(naive)
app.use(router)
app.mount('#app')
