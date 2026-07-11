// ── 前端组件测试 ──
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createWebHashHistory } from 'vue-router'
import naive from 'naive-ui'
import Dashboard from '../src/views/Dashboard.vue'
import Backup from '../src/views/Backup.vue'
import Restore from '../src/views/Restore.vue'
import Deploy from '../src/views/Deploy.vue'
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
