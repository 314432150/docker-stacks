// ── POST /api/deploy ──
// 异步启动引擎部署，返回 taskId

import { executeEngine } from '../engine.js'
import { createTask, pushEvent, setTaskStatus } from '../tasks.js'
import { validateApps } from '../validate.js'

export default async function deployRoutes(fastify) {
  fastify.post('/api/deploy', async (request, reply) => {
    const { apps } = request.body || {}

    // ── 校验 ──
    const appsErr = validateApps(apps)
    if (appsErr) {
      return reply.code(400).send({ error: true, code: 'VALIDATION_ERROR', message: appsErr })
    }

    // ── 创建任务 ──
    const task = createTask('deploy')

    // ── 异步启动引擎 ──
    setImmediate(async () => {
      try {
        let isFirstEvent = true

        await executeEngine('deploy', [...apps], (event) => {
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
        fastify.log.error({ err, taskId: task.taskId }, 'deploy engine error')
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
