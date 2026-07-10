<script setup>
import { h } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import { NLayout, NLayoutHeader, NLayoutContent, NMenu, NText, NSpace } from 'naive-ui'
import { CubeOutline } from '@vicons/ionicons5'

const menuItems = [
  { label: () => h(RouterLink, { to: '/' }, { default: () => '概览' }), key: '/' },
  { label: () => h(RouterLink, { to: '/backup' }, { default: () => '备份' }), key: '/backup' },
  { label: () => h(RouterLink, { to: '/restore' }, { default: () => '还原' }), key: '/restore' },
  { label: () => h(RouterLink, { to: '/deploy' }, { default: () => '部署' }), key: '/deploy' },
]
</script>

<template>
  <n-layout style="min-height: 100vh">
    <n-layout-header bordered>
      <n-space align="center" justify="space-between" style="padding: 0 24px; height: 56px">
        <n-space align="center">
          <n-icon size="24" :component="CubeOutline" />
          <n-text strong style="font-size: 18px">docker-stacks</n-text>
        </n-space>
        <n-menu mode="horizontal" :options="menuItems" :default-value="'/'"/>
      </n-space>
    </n-layout-header>
    <n-layout-content content-style="padding: 24px; max-width: 1200px; margin: 0 auto">
      <RouterView />
    </n-layout-content>
  </n-layout>
</template>
