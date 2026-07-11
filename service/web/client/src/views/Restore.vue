<script setup>
import { ref, computed, watch, onActivated } from 'vue'
import {
  NText, NCheckbox, NButton, NSpace, NAlert, NDivider,
  NCard, NGrid, NGi, NIcon, NEmpty, NPopconfirm,
} from 'naive-ui'
import { CheckmarkCircle, TrashOutline } from '@vicons/ionicons5'
import { fetchApps, fetchBackups, deleteBackup, runRestore } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import AppCardGrid from '../components/AppCardGrid.vue'
import SkeletonCards from '../components/SkeletonCards.vue'
import EventLog from '../components/EventLog.vue'

const apps = ref([])
const backups = ref([])
const pageLoading = ref(true)
const loading = ref(false)
const deleting = ref('')
const archive = ref('')
const selectedApps = ref([])
const error = ref('')
const taskId = ref('')
const sseUrl = ref('')

// ── 选中备份文件中包含的 app 列表 ──
const backupApps = computed(() => {
  const found = backups.value.find(b => b.name === archive.value)
  return found ? found.apps : []
})

// 卡片网格所用的数据格式
const backupAppsForGrid = computed(() =>
  backupApps.value.map(name => {
    const app = apps.value.find(a => a.name === name)
    return { name, description: app?.description || '' }
  })
)

// ── 全选 ──
const allSelected = computed(() =>
  backupApps.value.length > 0 && selectedApps.value.length === backupApps.value.length
)
const allIndeterminate = computed(() =>
  selectedApps.value.length > 0 && selectedApps.value.length < backupApps.value.length
)

function toggleSelectAll() {
  if (allSelected.value) {
    selectedApps.value = []
  } else {
    selectedApps.value = [...backupApps.value]
  }
}

watch(archive, () => {
  const found = backups.value.find(b => b.name === archive.value)
  if (found) {
    selectedApps.value = [...found.apps]
  } else {
    selectedApps.value = []
  }
})

// ── 加载数据 ──
async function loadData() {
  try {
    const [backupData, appData] = await Promise.all([
      fetchBackups(),
      fetchApps(),
    ])
    backups.value = backupData.files || []
    apps.value = appData.apps || []
  } catch (e) {
    error.value = e.message
  } finally {
    pageLoading.value = false
  }
}
onActivated(loadData)

// ── 格式化文件大小 ──
function fmtSize(bytes) {
  if (bytes == null) return '-'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB'
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB'
}

function fmtTime(iso) {
  if (!iso) return '-'
  const d = new Date(iso)
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

// ── 执行还原 ──
async function doRestore() {
  if (!archive.value) {
    error.value = '请选择一个备份文件'
    return
  }
  if (selectedApps.value.length === 0) {
    error.value = '请选择至少一个应用'
    return
  }
  loading.value = true
  error.value = ''
  try {
    const res = await runRestore(archive.value, selectedApps.value)
    taskId.value = res.taskId
    sseUrl.value = getSSEUrl(res.taskId)
  } catch (e) {
    error.value = e.message
    loading.value = false
  }
}

function onDone() {
  loading.value = false
}

// ── 删除备份 ──
async function doDelete(name) {
  deleting.value = name
  error.value = ''
  try {
    await deleteBackup(name)
    if (archive.value === name) {
      archive.value = ''
    }
    await loadData()
  } catch (e) {
    error.value = e.message
  } finally {
    deleting.value = ''
  }
}
</script>

<template>
  <div>
    <n-text tag="h2" style="margin: 0 0 20px 0">还原</n-text>
    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>

    <!-- 加载骨架 -->
    <template v-if="pageLoading">
      <n-skeleton text style="width: 260px; margin-bottom: 8px" />
      <SkeletonCards :count="6" />
    </template>

    <!-- 真实内容 -->
    <template v-else>
      <n-text depth="3" style="margin-bottom: 8px; display: block">
        步骤一：选择备份文件（共 {{ backups.length }} 个）
      </n-text>

      <n-empty v-if="backups.length === 0" description="暂无备份文件" style="margin-bottom: 16px" />

      <n-grid v-else :cols="3" :x-gap="12" :y-gap="12" responsive="screen" style="grid-auto-rows: 1fr">
        <n-gi
          v-for="b in backups"
          :key="b.name"
          style="display: flex; flex-direction: column"
        >
          <n-card
            :class="['backup-card', { 'backup-card--selected': archive === b.name }]"
            size="small"
            hoverable
            @click="archive = b.name"
          >
            <template v-if="archive === b.name" #header-extra>
              <n-icon size="20" color="#18a058" :component="CheckmarkCircle" />
            </template>

            <template #header>
              <n-text strong>{{ fmtTime(b.mtime) }}</n-text>
            </template>

            <n-text depth="3" style="font-size: 13px">
              {{ (b.apps || []).join(', ') || '无应用' }}
            </n-text>

            <template #footer>
              <n-space justify="space-between" align="center">
                <n-text depth="3" style="font-size: 12px">{{ fmtSize(b.size) }}</n-text>
                <n-popconfirm
                  positive-text="删除"
                  negative-text="取消"
                  @positive-click="doDelete(b.name)"
                >
                  <template #trigger>
                    <n-button
                      text
                      size="small"
                      type="error"
                      :loading="deleting === b.name"
                      @click.stop
                    >
                      <template #icon>
                        <n-icon size="18" :component="TrashOutline" />
                      </template>
                    </n-button>
                  </template>
                  确认删除此备份文件？
                </n-popconfirm>
              </n-space>
            </template>
          </n-card>
        </n-gi>
      </n-grid>

      <template v-if="archive">
        <n-divider />

        <n-text depth="3" style="margin-bottom: 8px; display: block">
          步骤二：选择要还原的应用
        </n-text>

        <n-space align="center" style="margin-bottom: 12px">
          <n-checkbox
            :checked="allSelected"
            :indeterminate="allIndeterminate"
            @update:checked="toggleSelectAll"
          >
            <n-text strong>全选</n-text>
          </n-checkbox>
          <n-text depth="3">已选 {{ selectedApps.length }}/{{ backupApps.length }} 个应用</n-text>
          <n-tag size="small" type="info">{{ archive }}</n-tag>
        </n-space>

        <AppCardGrid
          v-model:selected="selectedApps"
          :apps="backupAppsForGrid"
          empty-text="备份中无应用数据"
        />

        <n-divider />
      </template>
    </template>

    <n-button
      type="primary"
      :loading="loading"
      :disabled="!archive || selectedApps.length === 0"
      @click="doRestore"
    >
      开始还原
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>

<style scoped>
.backup-card {
  cursor: pointer;
  transition: border-color 0.2s, box-shadow 0.2s;
  border: 2px solid transparent;
  height: 100%;
}
.backup-card:hover {
  border-color: var(--n-border-hover-color, #ccc);
}
.backup-card--selected {
  border-color: #18a058 !important;
  box-shadow: 0 0 0 1px rgba(24, 160, 88, 0.15);
  background-color: rgba(24, 160, 88, 0.04);
}
</style>
