<script setup>
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  NText, NCheckboxGroup, NCheckbox, NSwitch, NInputNumber,
  NButton, NSpace, NAlert, NDivider, NCollapse, NCollapseItem, NTag,
} from 'naive-ui'
import { fetchApps, runBackup } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import EventLog from '../components/EventLog.vue'

const route = useRoute()
const apps = ref([])
const loading = ref(false)
const selectedApps = ref([])
const selectedDirs = ref({})          // { appName: [dirPath, ...] }
const enableUpload = ref(false)
const keepCount = ref(0)
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
    // 初始化目录选择：默认选中所有 recommended 目录
    const initDirs = {}
    for (const app of data.apps) {
      initDirs[app.name] = app.dirs.filter(d => d.recommended).map(d => d.path)
    }
    selectedDirs.value = initDirs
  } catch (e) {
    error.value = e.message
  }
}
loadApps()

// ── 当 app 被取消选中时，清除其目录选择 ──
function isAppDirSelected(appName, dirPath) {
  return (selectedDirs.value[appName] || []).includes(dirPath)
}

function toggleAppDir(appName, dirPath) {
  const current = selectedDirs.value[appName] || []
  if (current.includes(dirPath)) {
    selectedDirs.value[appName] = current.filter(d => d !== dirPath)
  } else {
    selectedDirs.value[appName] = [...current, dirPath]
  }
}

// ── 构建提交用的 dirs map（仅保留已选应用 + 非空 dirs） ──
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

    <!-- 应用选择 -->
    <n-space align="center" style="margin-bottom: 8px">
      <n-checkbox
        :checked="allSelected"
        :indeterminate="allIndeterminate"
        @update:checked="toggleSelectAll"
      >
        <n-text strong>全选</n-text>
      </n-checkbox>
      <n-text depth="3">已选 {{ selectedApps.length }}/{{ apps.length }} 个应用</n-text>
    </n-space>

    <n-checkbox-group v-model:value="selectedApps">
      <n-space vertical>
        <div v-for="app in apps" :key="app.name">
          <n-checkbox :value="app.name">
            <n-text strong>{{ app.name }}</n-text>
            <n-text depth="3"> &mdash; {{ app.description }}</n-text>
          </n-checkbox>
          <!-- 目录选择（仅选中时展示） -->
          <div v-if="selectedApps.includes(app.name) && app.dirs.length > 0"
               style="margin-left: 32px; margin-top: 4px">
            <n-space vertical size="small">
              <n-text depth="3" style="font-size: 12px">备份目录:</n-text>
              <n-checkbox
                v-for="dir in app.dirs"
                :key="dir.path"
                :checked="isAppDirSelected(app.name, dir.path)"
                @update:checked="toggleAppDir(app.name, dir.path)"
                size="small"
              >
                <n-text depth="2" style="font-size: 13px">{{ dir.path }}</n-text>
                <n-tag v-if="dir.recommended" size="tiny" type="success" style="margin-left: 4px">推荐</n-tag>
                <n-tag v-if="!dir.exists" size="tiny" type="warning" style="margin-left: 4px">不存在</n-tag>
              </n-checkbox>
            </n-space>
          </div>
        </div>
      </n-space>
    </n-checkbox-group>

    <n-divider />

    <n-space align="center" style="margin-bottom: 16px">
      <n-text>上传到 WebDAV</n-text>
      <n-switch v-model:value="enableUpload" />
    </n-space>
    <n-space align="center" style="margin-bottom: 16px">
      <n-text>保留本地备份数</n-text>
      <n-input-number v-model:value="keepCount" :min="0" :max="100" style="width: 100px" />
    </n-space>

    <n-button type="primary" :loading="loading" :disabled="selectedApps.length === 0" @click="doBackup">
      开始备份
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
