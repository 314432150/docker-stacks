// ── POST /api/restore ──
// 异步启动引擎还原，返回 taskId

import { resolve } from 'node:path'
import { executeEngine } from '../engine.js'
import { createTask, pushEvent, setTaskStatus } from '../tasks.js'
import { validateApps, validateArchive } from '../validate.js'
import { BACKUP_ROOT } from '../config.js'

export default async function restoreRoutes(fastify) {
  fastify.post('/api/restore', async (request, reply) => {
    const { archive, apps } = request.body || {}

    // ── 校验 ──
    const archiveErr = validateArchive(archive)
    if (archiveErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: archiveErr })
    }
    const appsErr = validateApps(apps)
    if (appsErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: appsErr })
    }

    // ── 路径安全校验 ──
    const archivePath = resolve(BACKUP_ROOT, archive)
    if (!archivePath.startsWith(BACKUP_ROOT)) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: 'archive 路径非法' })
    }

    // ── 检查文件存在 ──
    const { stat } = await import('node:fs/promises')
    try {
      const st = await stat(archivePath)
      if (!st.isFile()) throw new Error('不是文件')
    } catch {
      return reply.code(404).send({
        error: true,
        code: 'FILE_NOT_FOUND',
        message: `备份文件不存在: ${archivePath}`,
      })
    }

    // ── 创建任务 ──
    const task = createTask('restore')

    // ── 异步启动引擎 ──
    setImmediate(async () => {
      try {
        let isFirstEvent = true

        await executeEngine('restore', [archivePath, ...apps], (event) => {
          if (isFirstEvent) {
            setTaskStatus(task.taskId, 'running')
            isFirstEvent = false
          }
          pushEvent(task.taskId, event)
        })

        if (task.status === 'running') {
          setTaskStatus(task.taskId, 'success')
        }
      } catch (err) {
        fastify.log.error({ err, taskId: task.taskId }, 'restore engine error')
        pushEvent(task.taskId, { type: 'error', msg: `引擎启动失败: ${err.message}` })
        setTaskStatus(task.taskId, 'failed')
      }
    })

    return reply.code(202).send({
      taskId: task.taskId,
      status: task.status,
    })
  })
}
