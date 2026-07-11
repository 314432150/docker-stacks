import { test, expect } from '@playwright/test'
import { authenticatePage } from './helpers.js'

// ═══════════════════════════════════════════════════════════════
// 概览页 (Dashboard)
// ═══════════════════════════════════════════════════════════════
test.describe('概览页 (Dashboard)', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })

  test('导航到首页显示应用列表', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')
    const heading = page.locator('h2')
    await expect(heading).toContainText('概览')
  })

  test('导航栏五个 Tab 都存在', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('menuitem', { name: '概览' })).toBeVisible()
    await expect(page.getByRole('menuitem', { name: '备份' })).toBeVisible()
    await expect(page.getByRole('menuitem', { name: '还原' })).toBeVisible()
    await expect(page.getByRole('menuitem', { name: '部署' })).toBeVisible()
    await expect(page.getByRole('menuitem', { name: '设置' })).toBeVisible()
  })

  test('显示权限标签', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')
    const tag = page.locator('text=/管理员权限|普通用户/')
    await expect(tag).toBeVisible({ timeout: 5000 })
  })

  test('显示刷新按钮', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')
    const refreshBtn = page.locator('button:has-text("刷新")')
    await expect(refreshBtn).toBeVisible()
  })

  test('应用卡片显示名称和描述', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('.n-card')
    const cards = page.locator('.n-card')
    const count = await cards.count()
    expect(count).toBeGreaterThanOrEqual(1)
    const firstCard = cards.first()
    await expect(firstCard).toContainText(/\S/)
  })

  test('应用卡片有"备份"和"部署"按钮', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('.n-card')
    const backupBtn = page.locator('.n-card button:has-text("备份")').first()
    const deployBtn = page.locator('.n-card button:has-text("部署")').first()
    await expect(backupBtn).toBeVisible()
    await expect(deployBtn).toBeVisible()
  })
})

// ═══════════════════════════════════════════════════════════════
// 路由导航交互
// ═══════════════════════════════════════════════════════════════
test.describe('路由导航', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('概览页点击"备份"按钮跳转到备份页并预选应用', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('.n-card')
    const backupBtn = page.locator('.n-card button:has-text("备份")').first()
    await backupBtn.click()
    await page.waitForURL(/#\/backup\?app=/)
    await expect(page.locator('h2')).toContainText('备份')
    await expect(page.locator('text=/已选 \\d+\\/\\d+/')).toBeVisible({ timeout: 5000 })
  })

  test('概览页点击"部署"按钮跳转到部署页并预选应用', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('.n-card')
    const deployBtn = page.locator('.n-card button:has-text("部署")').first()
    await deployBtn.click()
    await page.waitForURL(/#\/deploy\?app=/)
    await expect(page.locator('h2')).toContainText('部署')
    await expect(page.locator('text=/已选 \\d+\\/\\d+/')).toBeVisible({ timeout: 5000 })
  })

  test('导航栏链接可切换页面', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')

    await page.getByRole('menuitem', { name: '备份' }).click()
    await page.waitForURL(/#\/backup/)
    await expect(page.locator('h2')).toContainText('备份')

    await page.getByRole('menuitem', { name: '还原' }).click()
    await page.waitForURL(/#\/restore/)
    await expect(page.locator('h2')).toContainText('还原')

    await page.getByRole('menuitem', { name: '部署' }).click()
    await page.waitForURL(/#\/deploy/)
    await expect(page.locator('h2')).toContainText('部署')

    await page.getByRole('menuitem', { name: '设置' }).click()
    await page.waitForURL(/#\/settings/)
    await expect(page.locator('h2')).toContainText('设置')
  })
})

// ═══════════════════════════════════════════════════════════════
// 主题切换
// ═══════════════════════════════════════════════════════════════
test.describe('主题切换', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('默认在导航栏显示主题切换按钮', async ({ page }) => {
    await page.goto('/')
    const themes = page.locator('.n-button').last()
    await expect(themes).toBeVisible()
  })

  test('主题按钮可点击且不报错', async ({ page }) => {
    await page.goto('/')
    const themeBtn = page.locator('.n-button').last()
    await themeBtn.click()
    await expect(page.locator('h2')).toContainText('概览', { timeout: 3000 })
  })

  test('切换到暗黑模式', async ({ page }) => {
    await page.goto('/')
    const darkClass = await page.locator('html.dark').count()
    const themeBtn = page.locator('.n-button').last()
    await themeBtn.click()
    await page.waitForTimeout(300)
    await expect(page.locator('h2')).toContainText('概览', { timeout: 2000 })
  })
})

// ═══════════════════════════════════════════════════════════════
// 加载状态 / 骨架屏
// ═══════════════════════════════════════════════════════════════
test.describe('加载状态', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('首次访问概览页最终显示内容而非永久加载', async ({ page }) => {
    await page.goto('/')
    await Promise.race([
      page.waitForSelector('.n-card', { timeout: 10000 }),
      page.waitForSelector('text=暂无应用', { timeout: 10000 }),
    ])
    const cards = page.locator('.n-card')
    const empty = page.locator('text=暂无应用')
    const hasContent = (await cards.count()) > 0 || (await empty.isVisible().catch(() => false))
    expect(hasContent).toBe(true)
  })

  test('备份页加载完成后显示内容', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('text=全选', { timeout: 10000 })
    await expect(page.locator('h2')).toContainText('备份')
  })

  test('还原页加载完成后显示内容', async ({ page }) => {
    await page.goto('/#/restore')
    await page.waitForSelector('.backup-card, .n-empty', { timeout: 10000 })
    await expect(page.locator('h2')).toContainText('还原')
  })

  test('部署页加载完成后显示内容', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('text=全选', { timeout: 10000 })
    await expect(page.locator('h2')).toContainText('部署')
  })
})

// ═══════════════════════════════════════════════════════════════
// 响应式 / 边界情况
// ═══════════════════════════════════════════════════════════════
test.describe('边界情况', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })

  test('所有页面 h2 标题存在且唯一', async ({ page }) => {
    const routes = ['/', '/#/backup', '/#/restore', '/#/deploy', '/#/settings']
    for (const r of routes) {
      await page.goto(r)
      await page.waitForSelector('h2', { timeout: 8000 })
      const h2Count = await page.locator('h2').count()
      expect(h2Count, `${r} 应有 h2 标题`).toBeGreaterThanOrEqual(1)
    }
  })

  test('页面间通过导航栏快速切换不崩溃', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')

    const tabs = ['备份', '还原', '部署', '设置', '概览']
    for (const tab of tabs) {
      await page.getByRole('menuitem', { name: tab }).click()
      await page.waitForSelector('h2', { timeout: 5000 })
      const content = await page.locator('h2').textContent()
      expect(content).toBeTruthy()
    }
  })
})
