// ── GET /api/apps ──
// 调用 engine.sh discover，透传结果

import { executeEngine } from '../engine.js'

export default async function appsRoutes(fastify) {
  fastify.get('/api/apps', async (_request, reply) => {
    let result
    try {
      let output = ''
      await executeEngine('discover', [], (event) => {
        // discover 输出单行 JSON，收集最后一次解析结果
        output = event
      })
      // 如果 onEvent 没触发（引擎没输出），尝试从原始 stdout 获取
      if (!output || !output.type) {
        return reply.code(500).send({
          error: true,
          code: 'ENGINE_ERROR',
          message: '引擎 discover 未返回有效数据',
        })
      }
      result = output
    } catch (err) {
      fastify.log.error(err)
      return reply.code(500).send({
        error: true,
        code: 'ENGINE_ERROR',
        message: `引擎 discover 执行失败: ${err.message}`,
      })
    }
    return result
  })
}
