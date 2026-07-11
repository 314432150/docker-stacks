// ── GET /api/tasks/history ──
// 返回最近 N 条已完成操作的历史记录

import { getHistory } from '../tasks.js'

export default async function historyRoutes(fastify) {
  fastify.get('/api/tasks/history', async (request) => {
    const limit = Math.min(
      Math.max(parseInt(request.query.limit, 10) || 50, 1),
      500
    )
    return {
      entries: getHistory(limit),
      total: getHistory(9999).length,
    }
  })
}
