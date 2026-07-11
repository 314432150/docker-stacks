<script setup>
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import {
  NText, NCheckbox, NButton, NSpace, NAlert, NDivider,
} from 'naive-ui'
import { fetchApps, runDeploy } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import AppCardGrid from '../components/AppCardGrid.vue'
import EventLog from '../components/EventLog.vue'

const route = useRoute()
const apps = ref([])
const loading = ref(false)
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

async function doDeploy() {
  if (selectedApps.value.length === 0) {
    error.value = '请选择至少一个应用'
    return
  }
  loading.value = true
  error.value = ''
  try {
    const res = await runDeploy(selectedApps.value)
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
    <n-text tag="h2" style="margin: 0 0 20px 0">部署</n-text>
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
      :apps="apps"
      empty-text="暂无可部署应用"
    />

    <n-divider />

    <n-button type="primary" :loading="loading" :disabled="selectedApps.length === 0" @click="doDeploy">
      开始部署
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
