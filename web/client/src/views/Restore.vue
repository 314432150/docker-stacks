<script setup>
import { ref, computed } from 'vue'
import { NText, NCheckboxGroup, NCheckbox, NInput, NButton, NSpace, NAlert, NDivider } from 'naive-ui'
import { fetchApps, runRestore } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import EventLog from '../components/EventLog.vue'

const apps = ref([])
const loading = ref(false)
const archive = ref('')
const selectedApps = ref([])
const error = ref('')
const taskId = ref('')
const sseUrl = ref('')

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

async function loadApps() {
  try {
    const data = await fetchApps()
    apps.value = data.apps
  } catch (e) {
    error.value = e.message
  }
}
loadApps()

async function doRestore() {
  if (!archive.value) {
    error.value = '请输入备份文件名'
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
</script>

<template>
  <div>
    <n-text tag="h2" style="margin: 0 0 20px 0">还原</n-text>
    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>

    <n-space vertical style="max-width: 500px; margin-bottom: 16px">
      <n-text>备份文件名</n-text>
      <n-input v-model:value="archive" placeholder="如 20260711-0230_openclaw.tar.gz" />
    </n-space>

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
        <n-checkbox v-for="app in apps" :key="app.name" :value="app.name">
          <n-text strong>{{ app.name }}</n-text>
        </n-checkbox>
      </n-space>
    </n-checkbox-group>

    <n-divider />

    <n-button type="primary" :loading="loading" :disabled="!archive || selectedApps.length === 0" @click="doRestore">
      开始还原
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
