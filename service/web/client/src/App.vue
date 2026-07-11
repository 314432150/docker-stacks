<script setup>
import { ref, onMounted, onUnmounted, computed, watchEffect, KeepAlive } from 'vue'
import { RouterView, useRouter, useRoute } from 'vue-router'
import {
  NLayout, NLayoutHeader, NLayoutContent, NMenu, NText, NSpace,
  NConfigProvider, NButton, NIcon, darkTheme, NMessageProvider, NDialogProvider,
} from 'naive-ui'
import { CubeOutline, SunnyOutline, MoonOutline, LogOutOutline } from '@vicons/ionicons5'
import { authStore } from './composables/useAuth.js'

const router = useRouter()
const route = useRoute()

const THEME_KEY = 'ds-web-theme'

// ── 认证状态（来自 router guard，避免重复请求 /api/auth/status）──
const isLoginPage = computed(() => route.path === '/login')

// ── 菜单当前激活项（跟随当前路由）──
const activeMenuKey = computed(() => route.path)

// ── 主题状态：null=跟随系统, 'light'=明亮, 'dark'=暗黑 ──
const userPreference = ref(localStorage.getItem(THEME_KEY) || null)

function getSystemDark() {
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

// 计数器：用于在系统偏好切换时强制重新计算 isDark
const systemTick = ref(0)

// 实际当前是否为暗色
const isDark = computed(() => {
  void systemTick.value  // 依赖此项，系统切换时强制重新求值
  if (userPreference.value === 'dark') return true
  if (userPreference.value === 'light') return false
  return getSystemDark()
})

// 切换：明亮 → 暗黑 → 跟随系统 → 明亮
function toggleTheme() {
  const current = userPreference.value
  if (current === null || current === 'light') {
    userPreference.value = 'dark'
  } else if (current === 'dark') {
    userPreference.value = 'light'
  }
  localStorage.setItem(THEME_KEY, userPreference.value)
}

// 切换按钮文本
const themeLabel = computed(() => {
  if (userPreference.value === null) return '跟随系统'
  return userPreference.value === 'dark' ? '暗黑' : '明亮'
})

let mediaQuery
let onSystemChange

onMounted(() => {
  // 监听系统主题变化
  mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  onSystemChange = () => {
    if (userPreference.value === null) {
      systemTick.value++
    }
  }
  mediaQuery.addEventListener('change', onSystemChange)
})

// ── 登出 ──
async function logout() {
  try {
    await fetch('/api/auth/logout', { method: 'POST' })
  } catch { /* ignore */ }
  authStore.currentUser = ''
  authStore.isAuthenticated = false
  authStore.checked = false
  router.push('/login')
}

onUnmounted(() => {
  if (mediaQuery && onSystemChange) {
    mediaQuery.removeEventListener('change', onSystemChange)
  }
})

// ── 同步 document 根元素 class，控制 body 层级背景色 ──
watchEffect(() => {
  document.documentElement.classList.toggle('dark', isDark.value)
})

/** 菜单点击处理：编程式导航，避免 RouterLink + NMenu 的重复导航问题 */
function handleMenuUpdate(key) {
  if (key !== route.path) {
    router.push(key)
  }
}

const menuItems = [
  { label: '概览', key: '/' },
  { label: '备份', key: '/backup' },
  { label: '还原', key: '/restore' },
  { label: '部署', key: '/deploy' },
  { label: '设置', key: '/settings' },
]
</script>

<template>
  <n-config-provider :theme="isDark ? darkTheme : null">
    <n-message-provider>
      <n-dialog-provider>
      <!-- 登录页：无导航栏 -->
      <n-layout v-if="isLoginPage" style="min-height: 100vh">
        <n-layout-content content-style="padding: 24px; max-width: 1200px; margin: 0 auto">
          <RouterView />
        </n-layout-content>
      </n-layout>

      <!-- 正常页面：带导航栏 -->
      <n-layout v-else style="min-height: 100vh">
        <n-layout-header bordered>
          <n-space align="center" justify="space-between" style="padding: 0 24px; height: 56px">
            <n-space align="center">
              <n-icon size="24" :component="CubeOutline" />
              <n-text strong style="font-size: 18px">docker-stacks</n-text>
            </n-space>
            <n-space align="center">
              <n-menu mode="horizontal" :options="menuItems" :value="activeMenuKey" @update:value="handleMenuUpdate" />
              <n-text v-if="authStore.currentUser" depth="3" style="font-size:13px">{{ authStore.currentUser }}</n-text>
              <n-button quaternary circle size="small" @click="toggleTheme" :title="themeLabel">
                <template #icon>
                  <n-icon :component="isDark ? SunnyOutline : MoonOutline" />
                </template>
              </n-button>
              <n-button quaternary circle size="small" @click="logout" title="退出登录">
                <template #icon>
                  <n-icon :component="LogOutOutline" />
                </template>
              </n-button>
            </n-space>
          </n-space>
        </n-layout-header>
        <n-layout-content content-style="padding: 24px; max-width: 1200px; margin: 0 auto">
          <RouterView v-slot="{ Component }">
            <KeepAlive>
              <component :is="Component" />
            </KeepAlive>
          </RouterView>
        </n-layout-content>
      </n-layout>
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>

<style>
/* ── 暗色模式全局背景 ── */
html.dark body {
  background-color: #101014;
}

/* ── 移动端响应式 ── */
@media (max-width: 640px) {
  .n-layout-header .n-space {
    padding: 0 12px !important;
  }
  .n-layout-content {
    --n-content-padding: 12px !important;
  }
  /* 水平菜单在小屏幕上隐藏部分项（Naive UI 自动处理），减小字体 */
  .n-menu.n-menu--horizontal {
    font-size: 13px;
  }
}
</style>
