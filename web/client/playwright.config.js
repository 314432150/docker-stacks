import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  timeout: 30000,
  retries: 0,
  use: {
    baseURL: 'http://localhost:5173',
    headless: true,
    screenshot: 'only-on-failure',
  },
  webServer: [
    {
      command: 'node --watch src/app.js',
      cwd: '../server',
      port: 3001,
      reuseExistingServer: true,
      timeout: 10000,
    },
    {
      command: 'npx vite --host 0.0.0.0',
      cwd: '../client',
      port: 5173,
      reuseExistingServer: true,
      timeout: 10000,
    },
  ],
})
