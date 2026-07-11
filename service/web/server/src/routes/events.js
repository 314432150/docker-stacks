// ── GET /api/events?taskId=<id> ──
// SSE 事件流订阅

import { getTask } from '../tasks.js'

export default async function eventsRoutes(fastify) {
  fastify.get('/api/events', async (request, reply) => {
    const { taskId } = request.query

    if (!taskId) {
      return reply.code(400).send({
        error: true,
        code: 'VALIDATION_ERROR',
        message: '缺少 taskId 参数',
      })
    }

    const task = getTask(taskId)
    if (!task) {
      return reply.code(404).send({
        error: true,
        code: 'TASK_NOT_FOUND',
        message: `任务不存在: ${taskId}`,
      })
    }

    // ── 设置 SSE 头 ──
    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no', // 禁用 nginx 缓冲
    })

    /**
     * 向客户端发送 SSE 消息
     * @param {object} data
     * @param {string} [eventName]
     */
    const sendSSE = (data, eventName) => {
      if (reply.raw.destroyed) return
      const msg = `data: ${JSON.stringify(data)}\n\n`
      if (eventName) {
        reply.raw.write(`event: ${eventName}\n${msg}`)
      } else {
        reply.raw.write(msg)
      }
    }

    // ── 推送历史事件 ──
    for (const event of task.history) {
      sendSSE(event)
    }

    // ── 如果任务已结束，发送关闭事件并结束流 ──
    if (task.status === 'success' || task.status === 'failed') {
      sendSSE({ type: 'closed', taskId }, 'close')
      reply.raw.end()
      return
    }

    // ── 订阅新事件 ──
    const onEvent = (event) => {
      if (event.type === 'closed') {
        sendSSE(event, 'close')
        reply.raw.end()
        return
      }
      sendSSE(event)
    }

    task.emitter.on('event', onEvent)

    // ── 客户端断开时清理 ──
    request.raw.on('close', () => {
      task.emitter.off('event', onEvent)
    })

    // 保持 Fastify 不要自动关闭
    reply.hijack()
  })
}
