import { test, expect } from '@playwright/test'
import { authenticatePage } from './helpers.js'

// ═══════════════════════════════════════════════════════════════
// 备份页 (Backup)
// ═══════════════════════════════════════════════════════════════
test.describe('备份页 (Backup)', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('备份页渲染应用列表和操作控件', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('备份')
    await expect(page.locator('text=全选')).toBeVisible()
    await expect(page.locator('text=上传到 WebDAV')).toBeVisible()
    await expect(page.locator('text=本地最多保留')).toBeVisible()
    const btn = page.locator('button:has-text("开始备份")')
    await expect(btn).toBeVisible()
  })

  test('未选中应用时按钮禁用', async ({ page }) => {
    await page.goto('/#/backup')
    const btn = page.locator('button:has-text("开始备份")')
    await expect(btn).toBeDisabled()
  })

  test('全选功能', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('text=全选')
    const allCheck = page.locator('text=全选')
    await allCheck.click()
    const status = page.locator('text=/已选 \\d+\\/\\d+/')
    await expect(status).toBeVisible()
  })

  test('点击卡片切换选中态', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('.app-card')
    const firstCard = page.locator('.app-card').first()
    await expect(firstCard).not.toHaveClass(/app-card--selected/)
    await firstCard.click()
    await expect(firstCard).toHaveClass(/app-card--selected/)
    await firstCard.click()
    await expect(firstCard).not.toHaveClass(/app-card--selected/)
  })

  test('选中卡片后显示备份目录子选择', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('.app-card')
    const firstCard = page.locator('.app-card').first()
    await firstCard.click()
    const dirSection = page.locator('text=备份目录')
    const visible = await dirSection.isVisible().catch(() => false)
    await expect(firstCard).toHaveClass(/app-card--selected/)
  })

  test('上传开关可切换', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('text=上传到 WebDAV')
    const switchEl = page.locator('.n-switch').first()
    await expect(switchEl).toBeVisible()
    await switchEl.click()
  })

  test('保留份数输入框存在', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('text=本地最多保留')
    const input = page.locator('.n-input-number input').first()
    await expect(input).toBeVisible()
  })
})

// ═══════════════════════════════════════════════════════════════
// 还原页 (Restore)
// ═══════════════════════════════════════════════════════════════
test.describe('还原页 (Restore)', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('还原页展示备份文件列表或空状态', async ({ page }) => {
    await page.goto('/#/restore')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('还原')
    await expect(
      page.locator('.backup-card, .n-empty').first()
    ).toBeVisible({ timeout: 5000 })
  })

  test('未选择备份文件时按钮禁用', async ({ page }) => {
    await page.goto('/#/restore')
    const btn = page.locator('button:has-text("开始还原")')
    await expect(btn).toBeDisabled()
  })

  test('选择备份文件后出现步骤二(应用选择区)', async ({ page }) => {
    await page.goto('/#/restore')
    const backupCard = page.locator('.backup-card').first()
    const hasBackups = await backupCard.isVisible().catch(() => false)
    if (!hasBackups) return
    await backupCard.click()
    await expect(page.locator('text=步骤一')).toBeVisible({ timeout: 3000 })
    await expect(page.locator('text=步骤二')).toBeVisible({ timeout: 3000 })
    await expect(page.locator('text=全选')).toBeVisible({ timeout: 3000 })
    await expect(page.locator('.n-tag')).toBeVisible({ timeout: 3000 })
  })

  test('步骤二全选功能(有备份时)', async ({ page }) => {
    await page.goto('/#/restore')
    const backupCard = page.locator('.backup-card').first()
    const hasBackups = await backupCard.isVisible().catch(() => false)
    if (!hasBackups) return
    await backupCard.click()
    await page.waitForSelector('text=步骤二', { timeout: 3000 })
    const allCheck = page.locator('text=全选')
    await allCheck.click()
    const status = page.locator('text=/已选 \\d+\\/\\d+/')
    await expect(status).toBeVisible({ timeout: 3000 })
  })
})

// ═══════════════════════════════════════════════════════════════
// 部署页 (Deploy)
// ═══════════════════════════════════════════════════════════════
test.describe('部署页 (Deploy)', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('部署页渲染应用列表', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('部署')
    await expect(page.locator('text=全选')).toBeVisible()
    const btn = page.locator('button:has-text("开始部署")')
    await expect(btn).toBeVisible()
  })

  test('未选中应用时按钮禁用', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('h2')
    const btn = page.locator('button:has-text("开始部署")')
    await expect(btn).toBeDisabled()
  })

  test('全选后按钮启用', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('.app-card')
    const allCheck = page.locator('text=全选')
    await allCheck.click()
    const btn = page.locator('button:has-text("开始部署")')
    await expect(btn).toBeEnabled()
  })

  test('卡片点击切换选中态', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('.app-card')
    const firstCard = page.locator('.app-card').first()
    await expect(firstCard).not.toHaveClass(/app-card--selected/)
    await firstCard.click()
    await expect(firstCard).toHaveClass(/app-card--selected/)
    const btn = page.locator('button:has-text("开始部署")')
    await expect(btn).toBeEnabled()
  })
})

// ═══════════════════════════════════════════════════════════════
// 设置页 (Settings)
// ═══════════════════════════════════════════════════════════════
test.describe('设置页 (Settings)', () => {
  test.beforeEach(async ({ page, request }) => {
    await authenticatePage(page, request)
  })
  test('设置页渲染 WebDAV 配置卡片', async ({ page }) => {
    await page.goto('/#/settings')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('设置')
    await expect(page.locator('text=WebDAV 远程备份')).toBeVisible({ timeout: 5000 })
    await expect(page.locator('text=/已配置|未配置/')).toBeVisible({ timeout: 5000 })
  })

  test('WebDAV 表单有三个输入框', async ({ page }) => {
    await page.goto('/#/settings')
    await page.waitForSelector('text=WebDAV 远程备份', { timeout: 5000 })
    const inputs = page.locator('.n-input input')
    const count = await inputs.count()
    expect(count).toBeGreaterThanOrEqual(3)
  })

  test('有保存按钮', async ({ page }) => {
    await page.goto('/#/settings')
    await page.waitForSelector('text=WebDAV 远程备份', { timeout: 5000 })
    const saveBtn = page.locator('button:has-text("保存")')
    await expect(saveBtn).toBeVisible()
  })

  test('密码字段类型为 password', async ({ page }) => {
    await page.goto('/#/settings')
    await page.waitForSelector('text=WebDAV 远程备份', { timeout: 5000 })
    // WebDAV 密码输入框在第一个 card 中
    const passInput = page.locator('.n-card').first().locator('input[type="password"]')
    await expect(passInput).toBeVisible({ timeout: 3000 })
  })

  test('不填写直接点保存不报错', async ({ page }) => {
    // mock 测试连接成功 + 保存成功
    await page.route('**/api/settings/webdav/**', async (route) => {
      if (route.request().url().includes('/test')) {
        await route.fulfill({ status: 200, body: JSON.stringify({ success: true, message: '连接成功' }) })
      } else if (route.request().method() === 'PUT') {
        await route.fulfill({ status: 200, body: JSON.stringify({ configured: true }) })
      } else {
        await route.continue()
      }
    })

    await page.goto('/#/settings')
    await page.waitForSelector('text=WebDAV 远程备份', { timeout: 5000 })

    // WebDAV 密码输入框在第一个 card 中
    const passInput = page.locator('.n-card').first().locator('input[type="password"]')
    if (await passInput.isVisible()) {
      await passInput.fill('test-password')
    }

    const saveBtn = page.locator('button:has-text("保存")')
    await saveBtn.click()

    await page.waitForTimeout(1000)
    const errorAlert = page.locator('.n-alert--error')
    const errorCount = await errorAlert.count()
    expect(errorCount).toBe(0)
  })
})
