<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { NForm, NFormItem, NInput, NButton, NCard, NCheckbox, NAlert } from 'naive-ui'
import { PersonOutline, LockClosedOutline } from '@vicons/ionicons5'

const REMEMBER_KEY = 'ds-remember'

const router = useRouter()
const route = useRoute()
const user = ref('')
const pass = ref('')
const remember = ref(false)
const error = ref('')
const loading = ref(false)
const userError = ref('')
const passError = ref('')
const isSetup = ref(false)

const redirect = route.query.redirect || '/'

const cardTitle = computed(() => isSetup.value ? '初始化管理员账户' : '登录')
const buttonText = computed(() => isSetup.value ? '创建管理员' : '登录')
const endpoint = computed(() => isSetup.value ? '/api/auth/setup' : '/api/auth/login')

/** 从 localStorage 恢复上次保存的凭据 */
function restoreSavedCredentials() {
  if (isSetup.value) return
  try {
    const raw = localStorage.getItem(REMEMBER_KEY)
    if (!raw) return
    const saved = JSON.parse(raw)
    if (saved.user) user.value = saved.user
    if (saved.pass) pass.value = saved.pass
    if (saved.remember) remember.value = true
  } catch { /* ignore */ }
}

onMounted(async () => {
  try {
    const res = await fetch('/api/auth/status')
    const data = await res.json()
    if (data.needsSetup) {
      isSetup.value = true
      remember.value = true // 初始化默认保持登录
      return
    }
    if (data.authenticated) {
      router.replace(redirect)
      return
    }
  } catch { /* ignore */ }

  isSetup.value = false
  restoreSavedCredentials()
})

/** 前端输入校验 */
function validateInput() {
  let valid = true
  userError.value = ''
  passError.value = ''
  error.value = ''

  const u = (user.value || '').trim()
  const p = (pass.value || '')

  if (!u) {
    userError.value = '请输入用户名'
    valid = false
  } else if (u.length > 128) {
    userError.value = '用户名长度不能超过 128 个字符'
    valid = false
  }

  if (!p) {
    passError.value = '请输入密码'
    valid = false
  } else if (p.length > 128) {
    passError.value = '密码长度不能超过 128 个字符'
    valid = false
  }

  return valid
}

async function doSubmit() {
  if (loading.value) return
  if (!validateInput()) return

  loading.value = true
  try {
    const u = (user.value || '').trim()
    const res = await fetch(endpoint.value, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user: u,
        pass: pass.value,
        remember: remember.value,
      }),
    })
    const data = await res.json()
    if (!data.ok) {
      error.value = data.message || '操作失败'
      return
    }

    // 保持登录
    if (remember.value) {
      localStorage.setItem(REMEMBER_KEY, JSON.stringify({ user: u, pass: pass.value, remember: true }))
    } else {
      localStorage.removeItem(REMEMBER_KEY)
    }

    router.replace(redirect)
  } catch (e) {
    error.value = e.message || '网络错误'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div style="display: flex; flex-direction: column; justify-content: center; align-items: center; min-height: 60vh">
    <div style="text-align: center; margin-bottom: 48px">
      <h1 style="margin: 0 0 8px 0; font-size: 28px; font-weight: 600; color: var(--n-title-text-color, #333)">
        Docker Stacks
      </h1>
      <p style="margin: 0; font-size: 14px; color: var(--n-text-color-3, #999); line-height: 1.6">
        NAS Docker Compose 服务管理面板
      </p>
      <p style="margin: 4px 0 0 0; font-size: 12px; color: var(--n-text-color-3, #bbb)">
        应用发现 · 备份还原 · 一键部署
      </p>
    </div>

    <n-card :title="cardTitle" style="width: 360px; max-width: 90vw" size="small">
      <n-alert v-if="isSetup && !error" type="info" style="margin-bottom: 16px">
        首次使用，请创建管理员账户
      </n-alert>
      <n-alert v-if="error" type="error" style="margin-bottom: 16px">{{ error }}</n-alert>
      <n-form>
        <n-form-item label="用户名" :feedback="userError" :validation-status="userError ? 'error' : undefined">
          <n-input
            v-model:value="user"
            placeholder="请输入用户名"
            :disabled="loading"
            clearable
            @keydown.enter="doSubmit"
          >
            <template #prefix><n-icon :component="PersonOutline" /></template>
          </n-input>
        </n-form-item>
        <n-form-item label="密码" :feedback="passError" :validation-status="passError ? 'error' : undefined">
          <n-input
            v-model:value="pass"
            type="password"
            show-password-on="click"
            placeholder="请输入密码"
            :disabled="loading"
            @keydown.enter="doSubmit"
          >
            <template #prefix><n-icon :component="LockClosedOutline" /></template>
          </n-input>
        </n-form-item>
        <n-form-item label=" " :show-feedback="false" style="margin-top: -20px">
          <n-checkbox v-model:checked="remember" :disabled="loading">
            保持登录
          </n-checkbox>
        </n-form-item>
        <n-form-item>
          <n-button type="primary" block :loading="loading" attr-type="button" @click="doSubmit">
            {{ buttonText }}
          </n-button>
        </n-form-item>
      </n-form>
    </n-card>
  </div>
</template>
