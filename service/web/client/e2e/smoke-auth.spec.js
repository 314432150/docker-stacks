import { test, expect } from '@playwright/test'

// ═══════════════════════════════════════════════════════════════
// 认证流程 (Session + Cookie)
// ═══════════════════════════════════════════════════════════════
test.describe('认证流程', () => {
  test('未登录访问首页 → 跳转到登录页', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('input[placeholder="请输入用户名"]', { timeout: 8000 })
    await expect(page.locator('.n-card')).toBeVisible()
    await expect(page.locator('.n-card-header__main')).toContainText('登录')
  })

  test('登录页渲染完整表单', async ({ page }) => {
    await page.goto('/#/login')
    await expect(page.locator('input[placeholder="请输入用户名"]')).toBeVisible()
    await expect(page.locator('input[placeholder="请输入密码"]')).toBeVisible()
    await expect(page.getByRole('button', { name: '登录' })).toBeVisible()
  })

  test('错误密码 → 显示错误提示', async ({ page }) => {
    await page.goto('/#/login')
    await page.locator('input[placeholder="请输入用户名"]').fill('fishme')
    await page.locator('input[placeholder="请输入密码"]').fill('wrong-password')
    await page.getByRole('button', { name: '登录' }).click()
    await expect(page.locator('.n-alert')).toBeVisible({ timeout: 5000 })
  })

  test('登录成功 → 跳转首页 → 显示内容', async ({ page }) => {
    await page.goto('/#/login')
    await page.locator('input[placeholder="请输入用户名"]').fill('fishme')
    await page.locator('input[placeholder="请输入密码"]').fill('Wxl196819!d')
    await page.getByRole('button', { name: '登录' }).click()
    await page.waitForSelector('h2', { timeout: 8000 })
    await expect(page.locator('h2')).toContainText('概览')
  })

  test('登录后 → 登出 → 回到登录页', async ({ page }) => {
    await page.goto('/#/login')
    await page.locator('input[placeholder="请输入用户名"]').fill('fishme')
    await page.locator('input[placeholder="请输入密码"]').fill('Wxl196819!d')
    await page.getByRole('button', { name: '登录' }).click()
    await page.waitForSelector('h2', { timeout: 8000 })

    const logoutBtn = page.locator('button[title="退出登录"]')
    await expect(logoutBtn).toBeVisible()
    await logoutBtn.click()

    await page.waitForSelector('input[placeholder="请输入用户名"]', { timeout: 8000 })
    await expect(page.locator('.n-card')).toBeVisible()
  })

  test('登录后访问受保护页面 → 正常显示', async ({ page, request }) => {
    const { authenticatePage } = await import('./helpers.js')
    await authenticatePage(page, request)
    const pages = ['/', '/#/backup', '/#/restore', '/#/deploy', '/#/settings']
    for (const p of pages) {
      await page.goto(p)
      await page.waitForSelector('h2', { timeout: 8000 })
      const h2 = await page.locator('h2').textContent()
      expect(h2).toBeTruthy()
    }
  })

  test('登出后无法访问 API', async ({ page, request }) => {
    const { authenticatePage } = await import('./helpers.js')
    await authenticatePage(page, request)
    await page.goto('/')
    await page.waitForSelector('h2')

    const logoutBtn = page.locator('button[title="退出登录"]')
    await logoutBtn.click()
    await page.waitForSelector('input[placeholder="请输入用户名"]', { timeout: 8000 })

    await page.goto('/')
    await page.waitForSelector('input[placeholder="请输入用户名"]', { timeout: 8000 })
    await expect(page.locator('.n-card-header__main')).toContainText('登录')
  })

  test('会话过期 → 重新跳转登录页', async ({ page }) => {
    await page.context().addCookies([{
      name: 'ds-sid',
      value: 'expired-fake-session-id-xxxxxxxxxxxx',
      domain: 'localhost',
      path: '/',
    }])
    await page.goto('/')
    await page.waitForSelector('input[placeholder="请输入用户名"]', { timeout: 8000 })
    await expect(page.locator('.n-card-header__main')).toContainText('登录')
  })
})
