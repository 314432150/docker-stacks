<script setup>
import { ref, onMounted, onActivated, h } from 'vue'
import { useRouter } from 'vue-router'
import { NCard, NButton, NTag, NSpace, NGrid, NGi, NText, NAlert } from 'naive-ui'
import { fetchApps } from '../composables/useApi.js'
import SkeletonCards from '../components/SkeletonCards.vue'

const router = useRouter()
const apps = ref([])
const privilege = ref('')
const loading = ref(true)
const error = ref('')

async function load(force = false) {
  loading.value = true
  error.value = ''
  try {
    const data = await fetchApps({ force })
    apps.value = data.apps
    privilege.value = data.engine?.privilege || 'unknown'
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(() => load())
// KeepAlive 激活时静默刷新（缓存命中，瞬时返回）
onActivated(() => load())

function goBackup(app) {
  router.push({ path: '/backup', query: { app: app.name } })
}
function goDeploy(app) {
  router.push({ path: '/deploy', query: { app: app.name } })
}
</script>

<template>
  <div>
    <n-space align="center" justify="space-between" style="margin-bottom: 20px">
      <n-text tag="h2" style="margin: 0">应用概览</n-text>
      <n-space>
        <n-tag :type="privilege === 'root' ? 'success' : 'warning'">
          {{ privilege === 'root' ? '管理员权限' : '普通用户' }}
        </n-tag>
        <n-button size="small" @click="load(true)">刷新</n-button>
      </n-space>
    </n-space>

    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>

    <!-- 加载骨架 -->
    <SkeletonCards v-if="loading" :count="6" />

    <!-- 真实内容 -->
    <template v-else>
      <n-grid :cols="3" :x-gap="12" :y-gap="12" responsive="screen">
        <n-gi v-for="app in apps" :key="app.name">
          <n-card :title="app.name" size="small" hoverable>
            <template #header-extra>
              <n-tag size="small" type="info">{{ app.dirs.length }} 个目录</n-tag>
            </template>
            <n-text depth="3">{{ app.description || '无描述' }}</n-text>
            <template #footer>
              <n-space justify="end">
                <n-button size="small" @click="goBackup(app)">备份</n-button>
                <n-button size="small" type="primary" @click="goDeploy(app)">部署</n-button>
              </n-space>
            </template>
          </n-card>
        </n-gi>
      </n-grid>
      <n-text v-if="apps.length === 0" depth="3">暂无应用</n-text>
    </template>
  </div>
</template>
