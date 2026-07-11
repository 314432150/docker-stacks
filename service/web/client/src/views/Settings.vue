<script setup>
import { ref, onMounted } from 'vue'
import {
  NText, NCard, NInput, NButton, NSpace, NAlert, NSpin, NDivider, NTag,
} from 'naive-ui'
import { fetchWebdavSettings, saveWebdavSettings, testWebdavConnection } from '../composables/useApi.js'

// ── WebDAV ──
const loading = ref(true)
const saving = ref(false)
const testing = ref(false)
const error = ref('')
const success = ref('')
const testResult = ref(null)
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
    pass.value = ''
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
  testResult.value = null
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

async function testConnection() {
  testing.value = true
  error.value = ''
  success.value = ''
  testResult.value = null
  try {
    testResult.value = await testWebdavConnection()
  } catch (e) {
    testResult.value = { success: false, message: e.message }
  } finally {
    testing.value = false
  }
}

// ── 修改管理员密码 ──
const changingPwd = ref(false)
const oldPass = ref('')
const newPass = ref('')
const pwdError = ref('')
const pwdSuccess = ref('')

async function changePassword() {
  if (changingPwd.value) return
  pwdError.value = ''
  pwdSuccess.value = ''

  if (!oldPass.value) {
    pwdError.value = '请输入旧密码'
    return
  }
  if (!newPass.value) {
    pwdError.value = '请输入新密码'
    return
  }
  if (newPass.value.length > 128) {
    pwdError.value = '新密码长度不能超过 128 个字符'
    return
  }

  changingPwd.value = true
  try {
    const res = await fetch('/api/auth/credentials', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        oldPass: oldPass.value,
        newPass: newPass.value,
      }),
    })
    const data = await res.json()
    if (!data.ok) {
      pwdError.value = data.message || '修改密码失败'
      return
    }
    pwdSuccess.value = data.message || '密码已修改'
    oldPass.value = ''
    newPass.value = ''
    // 修改密码后 session 已销毁，3 秒后跳转登录页
    setTimeout(() => {
      window.location.hash = '#/login'
    }, 3000)
  } catch (e) {
    pwdError.value = e.message || '网络错误'
  } finally {
    changingPwd.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <n-text tag="h2" style="margin: 0 0 20px 0">设置</n-text>

    <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>
    <n-alert v-if="success" type="success" style="margin-bottom: 16px">{{ success }}</n-alert>
    <n-alert v-if="testResult" :type="testResult.success ? 'success' : 'warning'" style="margin-bottom: 16px">
      {{ testResult.message }}
    </n-alert>

    <!-- ── WebDAV 远程备份 ── -->
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

          <n-space>
            <n-button type="primary" :loading="saving" @click="save">
              保存
            </n-button>
            <n-button :loading="testing" :disabled="!url || !user || !pass" @click="testConnection">
              测试连接
            </n-button>
          </n-space>
        </n-space>
      </n-spin>
    </n-card>

    <n-divider />

    <!-- ── 修改管理员密码 ── -->
    <n-card title="管理员凭据" size="small" style="max-width: 600px">
      <n-spin :show="false">
        <n-space vertical>
          <n-text depth="3">
            修改管理员登录密码。修改后需重新登录。
          </n-text>

          <n-alert v-if="pwdError" type="error">{{ pwdError }}</n-alert>
          <n-alert v-if="pwdSuccess" type="success">{{ pwdSuccess }}</n-alert>

          <n-space vertical>
            <n-text>旧密码</n-text>
            <n-input
              v-model:value="oldPass"
              type="password"
              placeholder="输入当前密码"
              show-password-on="click"
              :disabled="changingPwd"
            />
          </n-space>

          <n-space vertical>
            <n-text>新密码</n-text>
            <n-input
              v-model:value="newPass"
              type="password"
              placeholder="输入新密码"
              show-password-on="click"
              :disabled="changingPwd"
            />
          </n-space>

          <n-button type="primary" :loading="changingPwd" @click="changePassword">
            修改密码
          </n-button>
        </n-space>
      </n-spin>
    </n-card>
  </div>
</template>
