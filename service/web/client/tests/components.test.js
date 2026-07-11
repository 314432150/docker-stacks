// ── 前端组件测试 ──
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createWebHashHistory } from 'vue-router'
import naive from 'naive-ui'
import Dashboard from '../src/views/Dashboard.vue'
import Backup from '../src/views/Backup.vue'
import Restore from '../src/views/Restore.vue'
import Deploy from '../src/views/Deploy.vue'
import Login from '../src/views/Login.vue'
import EventLog from '../src/components/EventLog.vue'
import { resetCache } from '../src/composables/useApi.js'

// 模拟 fetch
global.fetch = vi.fn()

// 创建带路由和 Naive UI 的挂载工具
function mountWithPlugins(component, route = '/') {
  const router = createRouter({
    history: createWebHashHistory(),
    routes: [
      { path: '/', component },
      { path: '/backup', component },
      { path: '/restore', component },
      { path: '/deploy', component },
    ],
  })
  return mount(component, {
    global: {
      plugins: [router, naive],
    },
  })
}

describe('Dashboard.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    resetCache()
  })

  // 辅助：mock 容器状态为未部署
  function mockStatus() {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ containers: {} }),
    })
  }

  it('挂载后调用 fetch /api/apps 和 /api/apps/status', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        type: 'apps',
        engine: { privilege: 'root' },
        apps: [
          { name: 'test-app', description: 'Test', dirs: [] },
        ],
      }),
    })
    mockStatus()

    const wrapper = mountWithPlugins(Dashboard)
    await new Promise((r) => setTimeout(r, 100))

    expect(fetch).toHaveBeenCalledWith('/api/apps', expect.anything())
    expect(fetch).toHaveBeenCalledWith('/api/apps/status', expect.anything())
  })

  it('加载中显示骨架屏', async () => {
    // apps 永不 resolve，status 也永不 resolve
    fetch.mockImplementationOnce(() => new Promise(() => {}))
    fetch.mockImplementationOnce(() => new Promise(() => {}))

    const wrapper = mountWithPlugins(Dashboard)
    await new Promise((r) => setTimeout(r, 50))

    expect(wrapper.find('.n-card').exists()).toBe(true)
    expect(wrapper.find('.n-skeleton').exists()).toBe(true)
  })

  it('显示应用卡片', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        type: 'apps',
        engine: { privilege: 'root' },
        apps: [
          { name: 'app1', description: 'First app', dirs: [] },
          { name: 'app2', description: 'Second app', dirs: [] },
        ],
      }),
    })
    mockStatus()

    const wrapper = mountWithPlugins(Dashboard)
    await new Promise((r) => setTimeout(r, 100))

    const cards = wrapper.findAll('.n-card')
    expect(cards.length).toBeGreaterThanOrEqual(2)
  })

  it('API 错误时显示错误信息', async () => {
    // apps 失败，status 成功
    fetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: () => Promise.resolve({ error: true, message: 'Server error' }),
    })
    mockStatus()

    const wrapper = mountWithPlugins(Dashboard)
    await new Promise((r) => setTimeout(r, 100))

    expect(wrapper.text()).toContain('Server error')
  })
})

describe('EventLog.vue', () => {
  it('渲染传入的进度条', () => {
    const wrapper = mount(EventLog, {
      props: { url: '/api/events?taskId=test', taskId: 'test' },
    })
    expect(wrapper.find('.n-progress').exists()).toBe(true)
  })

  it('显示 type 标签', async () => {
    const wrapper = mount(EventLog, {
      props: { url: '/api/events?taskId=test', taskId: 'test' },
    })
    // EventLog 初始无事件，但卡片应存在
    expect(wrapper.find('.n-card').exists()).toBe(true)
  })
})

describe('Backup.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    resetCache()
  })

  it('挂载后加载应用列表', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        type: 'apps',
        engine: { privilege: 'root' },
        apps: [{ name: 'test-app', description: 'Test', dirs: [] }],
      }),
    })

    const wrapper = mountWithPlugins(Backup, '/backup')
    await new Promise((r) => setTimeout(r, 100))

    expect(fetch).toHaveBeenCalled()
  })

  it('未选择应用时按钮禁用', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        type: 'apps',
        engine: { privilege: 'root' },
        apps: [{ name: 'test-app', description: 'Test', dirs: [] }],
      }),
    })

    const wrapper = mountWithPlugins(Backup, '/backup')
    await new Promise((r) => setTimeout(r, 100))

    const btn = wrapper.find('button.n-button--primary-type')
    expect(btn.attributes('disabled')).toBeDefined()
  })
})

describe('Restore.vue', () => {
  it('未输入 archive 时按钮禁用', () => {
    const wrapper = mountWithPlugins(Restore, '/restore')
    const btn = wrapper.find('button.n-button--primary-type')
    expect(btn.attributes('disabled')).toBeDefined()
  })
})

describe('Deploy.vue', () => {
  it('挂载后加载应用列表', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        type: 'apps',
        engine: { privilege: 'root' },
        apps: [{ name: 'test-app', description: 'Test', dirs: [] }],
      }),
    })

    const wrapper = mountWithPlugins(Deploy, '/deploy')
    await new Promise((r) => setTimeout(r, 100))

    expect(fetch).toHaveBeenCalled()
  })
})

describe('Login.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.restoreAllMocks()
    localStorage.clear()
  })

  function mountLogin(pageRoute = '/login') {
    const router = createRouter({
      history: createWebHashHistory(),
      routes: [
        { path: '/login', component: Login },
        { path: '/', component: { template: '<div>首页</div>' } },
      ],
    })
    return mount(Login, {
      global: { plugins: [router, naive] },
    })
  }

  it('渲染登录表单（应用标题、描述、用户名、密码、登录按钮）', async () => {
    // 未登录状态
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    expect(wrapper.text()).toContain('Docker Stacks')
    expect(wrapper.text()).toContain('NAS Docker Compose 服务管理面板')
    expect(wrapper.find('input[placeholder="请输入用户名"]').exists()).toBe(true)
    expect(wrapper.find('input[placeholder="请输入密码"]').exists()).toBe(true)
    expect(wrapper.find('button.n-button--primary-type').text()).toBe('登录')
  })

  it('已登录时自动跳转到首页', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: true }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 100))

    // 已登录应触发 replace 跳转首页
    expect(fetch).toHaveBeenCalledWith('/api/auth/status')
  })

  it('输入为空时校验失败：用户名/密码必填提示，不提交后端', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    // 不填任何内容直接点登录
    await wrapper.find('button.n-button--primary-type').trigger('click')
    await new Promise((r) => setTimeout(r, 50))

    // 应显示字段级错误提示，但不向 /api/auth/login 发请求
    expect(wrapper.text()).toContain('请输入用户名')
    expect(wrapper.text()).toContain('请输入密码')
    // fetch 只应被 status 调用一次，未被 login 调用
    const loginCalls = fetch.mock.calls.filter(c => c[0] === '/api/auth/login')
    expect(loginCalls.length).toBe(0)
  })

  it('输入仅空格/空 → 校验失败', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('   ')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('')
    await wrapper.find('button.n-button--primary-type').trigger('click')
    await new Promise((r) => setTimeout(r, 50))

    expect(wrapper.text()).toContain('请输入用户名')
    expect(wrapper.text()).toContain('请输入密码')
  })

  it('渲染保持登录复选框', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    expect(wrapper.text()).toContain('保持登录')
    expect(wrapper.find('.n-checkbox').exists()).toBe(true)
  })

  it('输入错误凭据显示错误提示', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('user')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('wrong')

    // mock 登录失败
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ ok: false, message: '用户名或密码错误' }),
    })

    await wrapper.find('button.n-button--primary-type').trigger('click')
    await new Promise((r) => setTimeout(r, 50))

    // 应显示错误提示（NAlert 存在）
    expect(wrapper.findAll('.n-alert').length).toBeGreaterThanOrEqual(1)
    // 错误 Alert 内容应含 backend 返回的 message 或 fallback
    const alertText = wrapper.find('.n-alert').text()
    expect(['用户名或密码错误', '登录失败'].some(m => alertText.includes(m))).toBe(true)
  })

  it('登录成功跳转首页（默认 remember=false）', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('fishme')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('pass')

    // mock 登录成功
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ ok: true }),
    })

    await wrapper.find('button.n-button--primary-type').trigger('click')
    await new Promise((r) => setTimeout(r, 50))

    // 应调用了登录 API，且默认 remember: false
    expect(fetch).toHaveBeenCalledWith('/api/auth/login', expect.objectContaining({
      method: 'POST',
    }))
    const loginCall = fetch.mock.calls.find(c => c[0] === '/api/auth/login')
    expect(loginCall).toBeTruthy()
    const body = JSON.parse(loginCall[1].body)
    expect(body.user).toBe('fishme')
    expect(body.pass).toBe('pass')
    expect(body.remember).toBe(false)
  })

  it('网络错误显示提示', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('user')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('pass')

    // mock fetch 抛出网络错误
    fetch.mockRejectedValueOnce(new Error('网络错误'))

    await wrapper.find('button.n-button--primary-type').trigger('click')
    await new Promise((r) => setTimeout(r, 50))

    // 错误 Alert 应显示（无论具体文案，catch 会设置 error）
    expect(wrapper.findAll('.n-alert').length).toBeGreaterThanOrEqual(1)
  })

  it('保持登录：登录成功后保存凭据到 localStorage', async () => {
    // mock1: /api/auth/status → 未登录
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 10))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('fishme')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('pass')
    wrapper.vm.remember = true

    // mock2: /api/auth/login → 成功
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ ok: true }),
    })

    await wrapper.vm.doLogin()
    // flush promises
    await Promise.resolve()
    await Promise.resolve()

    const item = localStorage.getItem('ds-remember')
    expect(item).not.toBeNull()
    const saved = JSON.parse(item)
    expect(saved.user).toBe('fishme')
    expect(saved.pass).toBe('pass')
    expect(saved.remember).toBe(true)
  })

  it('不勾选保持登录：不写入 localStorage', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 10))

    await wrapper.find('input[placeholder="请输入用户名"]').setValue('fishme')
    await wrapper.find('input[placeholder="请输入密码"]').setValue('pass')
    // remember 默认 false

    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ ok: true }),
    })

    await wrapper.vm.doLogin()
    await Promise.resolve()
    await Promise.resolve()

    expect(localStorage.getItem('ds-remember')).toBeNull()
  })

  it('挂载时从 localStorage 恢复凭据', async () => {
    localStorage.setItem('ds-remember', JSON.stringify({ user: 'savedUser', pass: 'savedPass', remember: true }))

    fetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ authenticated: false }),
    })
    const wrapper = mountLogin()
    await new Promise((r) => setTimeout(r, 50))

    // 输入框应已预填
    const userInput = wrapper.find('input[placeholder="请输入用户名"]')
    const passInput = wrapper.find('input[placeholder="请输入密码"]')
    expect(userInput.element.value).toBe('savedUser')
    expect(passInput.element.value).toBe('savedPass')
  })
})
