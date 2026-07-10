// ── 引擎桥接层 ──
// 封装 spawn engine.sh，逐行解析 JSONL 事件流

import { spawn } from 'node:child_process'
import { createInterface } from 'node:readline'
import { ENGINE, ROOT } from './config.js'

/**
 * 执行引擎子命令
 * @param {string} subCommand — discover | backup | restore | deploy
 * @param {string[]} args — 位置参数
 * @param {(event: object) => void} [onEvent] — 每个 JSONL 事件的回调
 * @returns {Promise<{exitCode: number, stderr: string}>}
 */
export function executeEngine(subCommand, args = [], onEvent) {
  return new Promise((resolve, reject) => {
    const cmdArgs = [subCommand, ...args]
    const child = spawn(ENGINE, cmdArgs, {
      cwd: ROOT,
      env: { ...process.env },
      stdio: ['ignore', 'pipe', 'pipe'],
    })

    let stderr = ''

    // ── stderr 收集 ──
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString()
    })

    // ── stdout JSONL 逐行解析 ──
    const rl = createInterface({ input: child.stdout })
    rl.on('line', (line) => {
      try {
        const event = JSON.parse(line.trim())
        if (onEvent) onEvent(event)
      } catch {
        // 忽略非法 JSON 行
      }
    })

    // ── 进程退出 ──
    child.on('close', (code) => {
      resolve({ exitCode: code, stderr })
    })

    // ── 进程错误 ──
    child.on('error', (err) => {
      reject(err)
    })
  })
}
