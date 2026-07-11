// ═══════════════════════════════════════════════════════════════
// Dashboard 容器状态自动轮询
// ═══════════════════════════════════════════════════════════════
import { test, expect } from '@playwright/test'
import { authenticatePage } from './helpers.js'

test.describe('Dashboard 容器状态轮询', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })

  test('停留 Dashboard 时 /api/apps/status 被多次调用', async ({ page }) => {
    // 拦截 /api/apps/status 并计数
    let statusCallCount = 0
    await page.route('**/api/apps/status', async (route) => {
      statusCallCount++
      await route.continue()
    })

    await page.goto('/')
    await page.waitForSelector('h2', { timeout: 8000 })
    await page.waitForSelector('.n-card', { timeout: 8000 })

    // 初始一次（load() 中调用）
    const initialCount = statusCallCount
    expect(initialCount).toBeGreaterThanOrEqual(1)

    // 等待 18s（轮询间隔 15s + buffer），应该至少再调用 1 次
    await page.waitForTimeout(18000)

    expect(
      statusCallCount,
      `18s 内应触发至少 1 次轮询（初始 ${initialCount} 次，现在 ${statusCallCount} 次）`
    ).toBeGreaterThan(initialCount)
  })

  test('切到其他页面后轮询停止', async ({ page }) => {
    let statusCallCount = 0
    await page.route('**/api/apps/status', async (route) => {
      statusCallCount++
      await route.continue()
    })

    await page.goto('/')
    await page.waitForSelector('h2')
    await page.waitForSelector('.n-card')

    // 切换到备份页（KeepAlive 切走，Dashboard 进入 deactivated）
    await page.getByRole('menuitem', { name: '备份' }).click()
    await page.waitForURL(/#\/backup/)
    await page.waitForSelector('text=全选')

    // 记录切走时的请求数
    const countAfterSwitch = statusCallCount

    // 等待 18s，轮询应已停止，请求数不应增长
    await page.waitForTimeout(18000)

    // 允许 1 次边界误差（切走瞬间可能刚好有 in-flight 请求）
    expect(
      statusCallCount,
      `切走后 18s 内不应有新请求（切走时 ${countAfterSwitch}，现在 ${statusCallCount}）`
    ).toBeLessThanOrEqual(countAfterSwitch + 1)
  })

  test('切回 Dashboard 后轮询重新启动', async ({ page }) => {
    let statusCallCount = 0
    await page.route('**/api/apps/status', async (route) => {
      statusCallCount++
      await route.continue()
    })

    await page.goto('/')
    await page.waitForSelector('h2')
    await page.waitForSelector('.n-card')

    // 切走
    await page.getByRole('menuitem', { name: '备份' }).click()
    await page.waitForURL(/#\/backup/)
    await page.waitForTimeout(500)
    const countAfterLeave = statusCallCount

    // 切回
    await page.getByRole('menuitem', { name: '概览' }).click()
    await page.waitForURL(/#\/$|#\/$/)
    await page.waitForSelector('.n-card')

    // 切回时立即触发一次（onActivated 中 load()）
    expect(statusCallCount).toBeGreaterThan(countAfterLeave)

    // 等待 18s，应至少再轮询 1 次
    const countAfterReentry = statusCallCount
    await page.waitForTimeout(18000)
    expect(
      statusCallCount,
      `切回后 18s 内应再轮询（切回时 ${countAfterReentry}，现在 ${statusCallCount}）`
    ).toBeGreaterThan(countAfterReentry)
  })
})
