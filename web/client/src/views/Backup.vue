<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  NText, NCheckbox, NSwitch, NInputNumber,
  NButton, NSpace, NAlert, NDivider,
} from 'naive-ui'
import { fetchApps, runBackup } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import AppCardGrid from '../components/AppCardGrid.vue'
import EventLog from '../components/EventLog.vue'

const route = useRoute()
const apps = ref([])
const loading = ref(false)
const selectedApps = ref([])
const selectedDirs = ref({})
const enableUpload = ref(false)
const keepCount = ref(7)
const error = ref('')
const taskId = ref('')
const sseUrl = ref('')

const preSelect = computed(() => route.query.app ? [route.query.app] : [])

// ── 全选 ──
const allAppNames = computed(() => apps.value.map(a => a.name))
const allSelected = computed(() =>
  apps.value.length > 0 && selectedApps.value.length === apps.value.length
)
const allIndeterminate = computed(() =>
  selectedApps.value.length > 0 && selectedApps.value.length < apps.value.length
)

function toggleSelectAll() {
  if (allSelected.value) {
    selectedApps.value = []
  } else {
    selectedApps.value = [...allAppNames.value]
  }
}

// ── 加载应用列表 ──
async function loadApps() {
  try {
    const data = await fetchApps()
    apps.value = data.apps
    if (preSelect.value.length) {
      selectedApps.value = preSelect.value
    }
  } catch (e) {
    error.value = e.message
  }
}
loadApps()

// ── 选中 app 时自动勾选该 app 的推荐目录；取消时清除 ──
watch(selectedApps, (newVal, oldVal) => {
  const added = newVal.filter(a => !oldVal.includes(a))
  const removed = oldVal.filter(a => !newVal.includes(a))

  for (const name of added) {
    const app = apps.value.find(a => a.name === name)
    if (app && !selectedDirs.value[name]) {
      selectedDirs.value[name] = app.dirs.filter(d => d.recommended).map(d => d.path)
    }
  }
  for (const name of removed) {
    delete selectedDirs.value[name]
  }
}, { deep: false })

// ── 构建提交用的 dirs map ──
function buildDirsPayload() {
  const payload = {}
  for (const name of selectedApps.value) {
    const dirs = selectedDirs.value[name]
    if (dirs && dirs.length > 0) {
      payload[name] = dirs
    }
  }
  return Object.keys(payload).length > 0 ? payload : null
}

// ── 执行备份 ──
async function doBackup() {
  if (selectedApps.value.length === 0) {
    error.value = '请选择至少一个应用'
    return
  }
  loading.value = true
  error.value = ''
  try {
    const res = await runBackup(selectedApps.value, {
      upload: enableUpload.value,
      keep: keepCount.value,
      dirs: buildDirsPayload(),
    })
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
</script>

<template>
  <div>
    <n-text tag="h2" style="margin: 0 0 20px 0">备份</n-text>
    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>

    <!-- 选择栏 -->
    <n-space align="center" style="margin-bottom: 12px">
      <n-checkbox
        :checked="allSelected"
        :indeterminate="allIndeterminate"
        @update:checked="toggleSelectAll"
      >
        <n-text strong>全选</n-text>
      </n-checkbox>
      <n-text depth="3">已选 {{ selectedApps.length }}/{{ apps.length }} 个应用 &mdash; 点击卡片选择</n-text>
    </n-space>

    <!-- 应用卡片网格 -->
    <AppCardGrid
      v-model:selected="selectedApps"
      v-model:selected-dirs="selectedDirs"
      :apps="apps"
      :show-dirs="true"
      empty-text="暂无可备份应用，请先部署"
    />

    <n-divider />

    <!-- 操作选项 & 按钮 -->
    <n-space align="center" style="margin-bottom: 16px">
      <n-text>上传到 WebDAV</n-text>
      <n-switch v-model:value="enableUpload" />
    </n-space>
    <n-space align="center" style="margin-bottom: 16px">
      <n-text>本地最多保留</n-text>
      <n-input-number v-model:value="keepCount" :min="0" :max="100" style="width: 100px" />
      <n-text depth="3">份（0 = 不限）</n-text>
    </n-space>

    <n-button type="primary" :loading="loading" :disabled="selectedApps.length === 0" @click="doBackup">
      开始备份
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
