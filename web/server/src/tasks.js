// ── 任务注册中心 ──
// 内存中管理 task 状态、事件历史和 SSE 广播
// 完成后自动写入 backups/.history.jsonl 持久化

import { EventEmitter } from 'node:events'
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { TASK_TTL_MS, BACKUP_ROOT } from './config.js'

const HISTORY_FILE = join(BACKUP_ROOT, '.history.jsonl')

/** @type {Map<string, Task>} */
const tasks = new Map()

/**
 * 创建任务
 * @param {string} type — backup | restore | deploy
 * @returns {Task}
 */
export function createTask(type) {
  const taskId = `${type}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
  const task = {
    taskId,
    type,
    status: 'pending',
    history: [],
    emitter: new EventEmitter(),
    createdAt: new Date(),
    cleanupTimer: null,
  }

  // 设置最大事件监听数（一个任务可能有多个 SSE 订阅）
  task.emitter.setMaxListeners(100)

  tasks.set(taskId, task)
  return task
}

/**
 * 向任务追加事件
 * @param {string} taskId
 * @param {object} event
 */
export function pushEvent(taskId, event) {
  const task = tasks.get(taskId)
  if (!task) return

  task.history.push(event)
  task.emitter.emit('event', event)
}

/**
 * 标记任务为指定状态，启动清理定时器
 * @param {string} taskId
 * @param {'running'|'success'|'failed'} status
 */
/**
 * 将已完成的任务追加写入历史文件
 */
function persistHistory(task) {
  try {
    if (!existsSync(BACKUP_ROOT)) {
      mkdirSync(BACKUP_ROOT, { recursive: true })
    }
    const entry = {
      taskId: task.taskId,
      type: task.type,
      status: task.status,
      createdAt: task.createdAt.toISOString(),
      completedAt: new Date().toISOString(),
      eventCount: task.history.length,
      summary: task.history.length > 0 ? task.history[0].msg || task.history[0].type : null,
    }
    appendFileSync(HISTORY_FILE, JSON.stringify(entry) + '\n', 'utf-8')
  } catch {
    // 历史记录写入失败不影响主流程
  }
}

export function setTaskStatus(taskId, status) {
  const task = tasks.get(taskId)
  if (!task) return

  task.status = status

  if (status === 'success' || status === 'failed') {
    // 持久化历史记录
    persistHistory(task)
    // 发送关闭事件
    task.emitter.emit('event', { type: 'closed', taskId })
    // 5 分钟后清理内存中的任务
    task.cleanupTimer = setTimeout(() => {
      cleanupTask(taskId)
    }, TASK_TTL_MS)
  }
}

/**
 * 获取任务
 * @param {string} taskId
 * @returns {Task|undefined}
 */
export function getTask(taskId) {
  return tasks.get(taskId)
}

/**
 * 清理任务
 * @param {string} taskId
 */
export function cleanupTask(taskId) {
  const task = tasks.get(taskId)
  if (!task) return

  if (task.cleanupTimer) clearTimeout(task.cleanupTimer)
  task.emitter.removeAllListeners()
  tasks.delete(taskId)
}

/**
 * 检查是否有运行中的任务
 * @returns {boolean}
 */
export function hasRunningTask() {
  for (const [, task] of tasks) {
    if (task.status === 'running' || task.status === 'pending') return true
  }
  return false
}

/**
 * 读取最近 N 条历史记录
 * @param {number} limit — 默认 50
 * @returns {object[]}
 */
export function getHistory(limit = 50) {
  try {
    if (!existsSync(HISTORY_FILE)) return []
    const content = readFileSync(HISTORY_FILE, 'utf-8')
    const lines = content.trim().split('\n').filter(Boolean)
    return lines.slice(-limit).map(line => {
      try { return JSON.parse(line) } catch { return null }
    }).filter(Boolean).reverse()
  } catch {
    return []
  }
}

export { tasks }
