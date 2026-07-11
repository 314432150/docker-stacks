<script setup>
import { ref, onMounted, onActivated, h } from 'vue'
import { useRouter } from 'vue-router'
import { NCard, NButton, NTag, NSpace, NGrid, NGi, NText, NAlert } from 'naive-ui'
import { fetchApps, fetchContainerStatus } from '../composables/useApi.js'
import SkeletonCards from '../components/SkeletonCards.vue'

const router = useRouter()
const apps = ref([])
const privilege = ref('')
const loading = ref(true)
const error = ref('')
const containerStatus = ref({})

async function load(force = false) {
  loading.value = true
  error.value = ''
  try {
    const [data, statusData] = await Promise.all([
      fetchApps({ force }),
      fetchContainerStatus(),
    ])
    apps.value = data.apps
    privilege.value = data.engine?.privilege || 'unknown'
    containerStatus.value = statusData.containers || {}
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

/** 获取容器状态标签类型 */
function statusTagType(appName) {
  const s = containerStatus.value[appName]
  if (!s) return 'default'
  if (s.state === 'running') return 'success'
  if (s.state === 'exited') return 'warning'
  return 'default'
}

/** 获取容器状态文字 */
function statusText(appName) {
  const s = containerStatus.value[appName]
  if (!s) return '未部署'
  if (s.state === 'running') return '运行中'
  if (s.state === 'exited') return '已停止'
  return s.state
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
              <n-space :size="4">
                <n-tag size="small" :type="statusTagType(app.name)">
                  {{ statusText(app.name) }}
                </n-tag>
                <n-tag size="small" type="info">{{ app.dirs.length }} 个目录</n-tag>
              </n-space>
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
