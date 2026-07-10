<script setup>
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import { NText, NCheckboxGroup, NCheckbox, NSwitch, NInputNumber, NButton, NSpace, NAlert, NDivider } from 'naive-ui'
import { fetchApps, runBackup } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import EventLog from '../components/EventLog.vue'

const route = useRoute()
const apps = ref([])
const loading = ref(false)
const selectedApps = ref([])
const enableUpload = ref(false)
const keepCount = ref(0)
const error = ref('')
const taskId = ref('')
const sseUrl = ref('')

// 预选从 Dashboard 传来的 app
const preSelect = computed(() => route.query.app ? [route.query.app] : [])

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

    <!-- 表单区 -->
    <n-checkbox-group v-model:value="selectedApps">
      <n-space vertical>
        <n-checkbox v-for="app in apps" :key="app.name" :value="app.name">
          <n-text strong>{{ app.name }}</n-text>
          <n-text depth="3"> &mdash; {{ app.description }}</n-text>
        </n-checkbox>
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

    <!-- 事件日志 -->
    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
