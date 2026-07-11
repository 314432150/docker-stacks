import { test, expect } from '@playwright/test'
import { execSync } from 'node:child_process'
import { existsSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join, dirname } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '../../..')
const BACKUP_DIR = join(ROOT, 'backups')

test.describe('概览页 (Dashboard)', () => {
  test('导航到首页显示应用列表', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('h2')
    const heading = page.locator('h2')
    await expect(heading).toContainText('概览')
  })

  test('导航栏四个 Tab 都存在', async ({ page }) => {
    await page.goto('/')
    // 概览 / 备份 / 还原 / 部署 / 设置
    await expect(page.getByRole('link', { name: '概览' })).toBeVisible()
    await expect(page.getByRole('link', { name: '备份' })).toBeVisible()
    await expect(page.getByRole('link', { name: '还原' })).toBeVisible()
    await expect(page.getByRole('link', { name: '部署' })).toBeVisible()
    await expect(page.getByRole('link', { name: '设置' })).toBeVisible()
  })
})

test.describe('备份页 (Backup)', () => {
  test('备份页渲染应用列表和操作控件', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('备份')

    // 全选复选框
    await expect(page.locator('text=全选')).toBeVisible()

    // 上传 / 保留开关
    await expect(page.locator('text=上传到 WebDAV')).toBeVisible()
    await expect(page.locator('text=本地最多保留')).toBeVisible()

    // 开始备份按钮
    const btn = page.locator('button:has-text("开始备份")')
    await expect(btn).toBeVisible()
  })

  test('未选中应用时按钮禁用', async ({ page }) => {
    await page.goto('/#/backup')
    // 默认 7 份且未选 app，按钮应禁用
    const btn = page.locator('button:has-text("开始备份")')
    await expect(btn).toBeDisabled()
  })

  test('全选功能', async ({ page }) => {
    await page.goto('/#/backup')
    await page.waitForSelector('text=全选')

    // 点击全选
    const allCheck = page.locator('text=全选')
    await allCheck.click()

    // 应显示 "已选 N/N" 且 N > 0
    const status = page.locator('text=/已选 \\d+\\/\\d+/')
    await expect(status).toBeVisible()
  })
})

test.describe('还原页 (Restore)', () => {
  test('还原页展示备份文件列表或空状态', async ({ page }) => {
    await page.goto('/#/restore')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('还原')

    // 应该有表格或空状态
    await expect(
      page.locator('.n-data-table, .n-empty')
    ).toBeVisible({ timeout: 5000 })
  })

  test('未选择备份文件时按钮禁用', async ({ page }) => {
    await page.goto('/#/restore')
    const btn = page.locator('button:has-text("开始还原")')
    await expect(btn).toBeDisabled()
  })
})

test.describe('部署页 (Deploy)', () => {
  test('部署页渲染应用列表', async ({ page }) => {
    await page.goto('/#/deploy')
    await page.waitForSelector('h2')
    await expect(page.locator('h2')).toContainText('部署')

    await expect(page.locator('text=全选')).toBeVisible()
    const btn = page.locator('button:has-text("开始部署")')
    await expect(btn).toBeVisible()
  })
})

test.describe('主题切换', () => {
  test('默认在导航栏显示主题切换按钮', async ({ page }) => {
    await page.goto('/')
    // 主题切换按钮（太阳/月亮图标）
    const themes = page.locator('.n-button').last()
    await expect(themes).toBeVisible()
  })
})
