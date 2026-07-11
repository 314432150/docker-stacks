<script setup>
import { h, ref, onMounted, onUnmounted, computed, watchEffect, KeepAlive } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import {
  NLayout, NLayoutHeader, NLayoutContent, NMenu, NText, NSpace,
  NConfigProvider, NButton, NIcon, darkTheme,
} from 'naive-ui'
import { CubeOutline, SunnyOutline, MoonOutline, SettingsOutline } from '@vicons/ionicons5'

const THEME_KEY = 'ds-web-theme'

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
  mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  onSystemChange = () => {
    if (userPreference.value === null) {
      systemTick.value++
    }
  }
  mediaQuery.addEventListener('change', onSystemChange)
})

onUnmounted(() => {
  if (mediaQuery && onSystemChange) {
    mediaQuery.removeEventListener('change', onSystemChange)
  }
})

// ── 同步 document 根元素 class，控制 body 层级背景色 ──
watchEffect(() => {
  document.documentElement.classList.toggle('dark', isDark.value)
})

const menuItems = [
  { label: () => h(RouterLink, { to: '/' }, { default: () => '概览' }), key: '/' },
  { label: () => h(RouterLink, { to: '/backup' }, { default: () => '备份' }), key: '/backup' },
  { label: () => h(RouterLink, { to: '/restore' }, { default: () => '还原' }), key: '/restore' },
  { label: () => h(RouterLink, { to: '/deploy' }, { default: () => '部署' }), key: '/deploy' },
  { label: () => h(RouterLink, { to: '/settings' }, { default: () => '设置' }), key: '/settings' },
]
</script>

<template>
  <n-config-provider :theme="isDark ? darkTheme : null">
    <n-layout style="min-height: 100vh">
      <n-layout-header bordered>
        <n-space align="center" justify="space-between" style="padding: 0 24px; height: 56px">
          <n-space align="center">
            <n-icon size="24" :component="CubeOutline" />
            <n-text strong style="font-size: 18px">docker-stacks</n-text>
          </n-space>
          <n-space align="center">
            <n-menu mode="horizontal" :options="menuItems" :default-value="'/'" />
            <n-button quaternary circle size="small" @click="toggleTheme" :title="themeLabel">
              <template #icon>
                <n-icon :component="isDark ? SunnyOutline : MoonOutline" />
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
  </n-config-provider>
</template>

<style>
/* ── 暗色模式全局背景 ── */
html.dark body {
  background-color: #101014;
}
</style>
