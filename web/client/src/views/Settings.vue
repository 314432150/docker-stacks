<script setup>
import { ref, onMounted } from 'vue'
import {
  NText, NCard, NInput, NButton, NSpace, NAlert, NSpin, NDivider, NTag,
} from 'naive-ui'
import { fetchWebdavSettings, saveWebdavSettings } from '../composables/useApi.js'

const loading = ref(true)
const saving = ref(false)
const error = ref('')
const success = ref('')
const configured = ref(false)

const url = ref('')
const user = ref('')
const pass = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await fetchWebdavSettings()
    configured.value = data.configured
    url.value = data.url || ''
    user.value = data.user || ''
    pass.value = '' // 密码不回显
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  error.value = ''
  success.value = ''
  try {
    await saveWebdavSettings({
      url: url.value.trim(),
      user: user.value.trim(),
      pass: pass.value.trim(),
    })
    configured.value = true
    success.value = 'WebDAV 设置已保存'
    pass.value = ''
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <n-text tag="h2" style="margin: 0 0 20px 0">设置</n-text>

    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>
    <n-alert v-if="success" type="success" style="margin-bottom: 16px">{{ success }}</n-alert>

    <n-card title="WebDAV 远程备份" size="small" style="max-width: 600px">
      <template #header-extra>
        <n-tag :type="configured ? 'success' : 'warning'" size="small">
          {{ configured ? '已配置' : '未配置' }}
        </n-tag>
      </template>

      <n-spin :show="loading">
        <n-space vertical>
          <n-text depth="3">
            配置后可自动将备份文件上传到远程 WebDAV 服务器（如坚果云、Nextcloud、群晖等）。
          </n-text>

          <n-space vertical>
            <n-text>WebDAV 地址</n-text>
            <n-input v-model:value="url" placeholder="https://dav.jianguoyun.com/dav/docker-stacks" />
          </n-space>

          <n-space vertical>
            <n-text>用户名</n-text>
            <n-input v-model:value="user" placeholder="WebDAV 账号" />
          </n-space>

          <n-space vertical>
            <n-text>密码</n-text>
            <n-input
              v-model:value="pass"
              type="password"
              :placeholder="configured ? '留空则不修改密码' : 'WebDAV 密码'"
              show-password-on="click"
            />
          </n-space>

          <n-button type="primary" :loading="saving" @click="save">
            保存
          </n-button>
        </n-space>
      </n-spin>
    </n-card>
  </div>
</template>
