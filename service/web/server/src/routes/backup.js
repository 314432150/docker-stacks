// ── POST /api/backup ──
// 异步启动引擎备份，返回 taskId

import { executeEngine } from '../engine.js'
import { createTask, pushEvent, setTaskStatus } from '../tasks.js'
import { validateApps, validateBoolean, validateNonNegativeInt, validateDirs } from '../validate.js'

export default async function backupRoutes(fastify) {
  fastify.post('/api/backup', async (request, reply) => {
    const { apps, upload, keep, dirs } = request.body || {}

    // ── 校验 ──
    const appsErr = validateApps(apps)
    if (appsErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: appsErr })
    }
    const uploadErr = validateBoolean(upload)
    if (uploadErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: `upload ${uploadErr}` })
    }
    const keepErr = validateNonNegativeInt(keep)
    if (keepErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: `keep ${keepErr}` })
    }
    const dirsErr = validateDirs(dirs)
    if (dirsErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: dirsErr })
    }

    // ── 构建引擎参数：app 名或 app:dir1,dir2 格式 ──
    const engineArgs = []
    if (upload) engineArgs.push('--upload')
    if (keep && keep > 0) engineArgs.push('--keep', String(keep))
    for (const app of apps) {
      const appDirs = dirs?.[app]
      if (appDirs && appDirs.length > 0) {
        engineArgs.push(`${app}:${appDirs.join(',')}`)
      } else {
        engineArgs.push(app)
      }
    }

    // ── 创建任务 ──
    const task = createTask('backup')

    // ── 异步启动引擎 ──
    setImmediate(async () => {
      try {
        // 检查锁冲突（引擎输出 busy 事件）
        let isFirstEvent = true

        await executeEngine('backup', engineArgs, (event) => {
          if (isFirstEvent) {
            setTaskStatus(task.taskId, 'running')
            isFirstEvent = false
          }
          pushEvent(task.taskId, event)

          // 检测锁冲突
          if (event.type === 'busy') {
            setTaskStatus(task.taskId, 'failed')
          }
        })

        // 成功退出
        if (task.status === 'running') {
          setTaskStatus(task.taskId, 'success')
        }
      } catch (err) {
        fastify.log.error({ err, taskId: task.taskId }, 'backup engine error')
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
