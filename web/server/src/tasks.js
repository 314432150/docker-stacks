// ── 任务注册中心 ──
// 内存中管理 task 状态、事件历史和 SSE 广播

import { EventEmitter } from 'node:events'
import { TASK_TTL_MS } from './config.js'

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
export function setTaskStatus(taskId, status) {
  const task = tasks.get(taskId)
  if (!task) return

  task.status = status

  if (status === 'success' || status === 'failed') {
    // 发送关闭事件
    task.emitter.emit('event', { type: 'closed', taskId })
    // 5 分钟后清理
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

export { tasks }
