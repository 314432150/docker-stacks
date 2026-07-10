<script setup>
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import { NText, NCheckboxGroup, NCheckbox, NButton, NSpace, NAlert, NDivider } from 'naive-ui'
import { fetchApps, runDeploy } from '../composables/useApi.js'
import { getSSEUrl } from '../composables/useSSE.js'
import EventLog from '../components/EventLog.vue'

const route = useRoute()
const apps = ref([])
const loading = ref(false)
const selectedApps = ref([])
const error = ref('')
const taskId = ref('')
const sseUrl = ref('')

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

    <n-checkbox-group v-model:value="selectedApps">
      <n-space vertical>
        <n-checkbox v-for="app in apps" :key="app.name" :value="app.name">
          <n-text strong>{{ app.name }}</n-text>
          <n-text depth="3"> &mdash; {{ app.description }}</n-text>
        </n-checkbox>
      </n-space>
    </n-checkbox-group>

    <n-divider />

    <n-button type="primary" :loading="loading" :disabled="selectedApps.length === 0" @click="doDeploy">
      开始部署
    </n-button>

    <EventLog v-if="sseUrl" :url="sseUrl" :task-id="taskId" @done="onDone" />
  </div>
</template>
