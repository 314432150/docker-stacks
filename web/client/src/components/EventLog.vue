<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import {
  NCard, NTag, NText, NScrollbar, NProgress, NSpace,
} from 'naive-ui'
import {
  CheckmarkCircle, CloseCircle, AlertCircle,
  InformationCircle, CloudUpload, Sync,
} from '@vicons/ionicons5'

const props = defineProps({
  url: { type: String, required: true },
  taskId: { type: String, default: '' },
})

const emit = defineEmits(['done'])

const events = ref([])
const progress = ref(0)
const eventSource = ref(null)

const typeConfig = {
  start:    { color: '#2080f0', icon: Sync,          label: '开始' },
  progress: { color: '#2080f0', icon: CloudUpload,   label: '进度' },
  ok:       { color: '#18a058', icon: CheckmarkCircle, label: '成功' },
  skip:     { color: '#f0a020', icon: AlertCircle,   label: '跳过' },
  error:    { color: '#d03050', icon: CloseCircle,   label: '错误' },
  busy:     { color: '#f0a020', icon: AlertCircle,   label: '繁忙' },
  done:     { color: '#18a058', icon: CheckmarkCircle, label: '完成' },
  closed:   { color: '#999',    icon: InformationCircle, label: '关闭' },
}

function connect() {
  const es = new EventSource(props.url)
  eventSource.value = es

  es.onmessage = (e) => {
    try {
      const data = JSON.parse(e.data)
      events.value.push(data)

      // 进度计算
      if (data.type === 'progress' && data.current && data.total) {
        progress.value = Math.round((data.current / data.total) * 100)
      }
      if (data.type === 'done') {
        progress.value = 100
      }
    } catch { /* skip */ }
  }

  es.addEventListener('close', () => {
    es.close()
    emit('done')
  })

  es.onerror = () => {
    es.close()
    emit('done')
  }
}

onMounted(connect)
onUnmounted(() => {
  if (eventSource.value) {
    eventSource.value.close()
  }
})

function getLabel(event) {
  const cfg = typeConfig[event.type]
  if (!cfg) return event.type

  if (event.type === 'progress') return event.step || 'progress'
  if (event.type === 'ok') return event.app || 'ok'
  if (event.type === 'error') return event.msg || 'error'
  if (event.type === 'done') return `成功 ${event.success}, 失败 ${event.fail}`
  if (event.type === 'start') return `应用: ${(event.apps || []).join(', ')}`
  return cfg.label
}
</script>

<template>
  <n-card title="操作日志" size="small" style="margin-top: 20px">
    <n-progress
      :percentage="progress"
      :status="progress === 100 ? 'success' : 'default'"
      style="margin-bottom: 12px"
    />
    <n-scrollbar style="max-height: 300px">
      <n-space vertical size="small">
        <n-space v-for="(event, i) in events" :key="i" align="center" size="small">
          <n-tag
            size="small"
            :color="{ color: typeConfig[event.type]?.color, textColor: '#fff' }"
            round
          >
            {{ typeConfig[event.type]?.label || event.type }}
          </n-tag>
          <n-text>{{ getLabel(event) }}</n-text>
        </n-space>
      </n-space>
    </n-scrollbar>
  </n-card>
</template>
