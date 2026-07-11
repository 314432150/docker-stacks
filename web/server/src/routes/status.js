// ── GET /api/apps/status ──
// 通过 docker ps 查询各应用容器运行状态

import { spawn } from 'node:child_process'

/**
 * 执行 docker ps 并解析为容器名 → 状态映射
 */
function dockerPs() {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', [
      'ps', '-a',
      '--format', '{{.Names}}\t{{.State}}\t{{.Status}}',
    ], { timeout: 5000 })

    let stdout = ''
    child.stdout.on('data', d => { stdout += d })
    child.on('error', reject)
    child.on('close', code => {
      if (code !== 0 && code !== null) {
        return reject(new Error(`docker ps 退出码 ${code}`))
      }
      const map = {}
      for (const line of stdout.trim().split('\n').filter(Boolean)) {
        const [name, state, status] = line.split('\t')
        if (name) {
          map[name] = { state, status: status || '' }
        }
      }
      resolve(map)
    })
  })
}

export default async function statusRoutes(fastify) {
  fastify.get('/api/apps/status', async (_request, reply) => {
    try {
      const containers = await dockerPs()
      return { containers }
    } catch (err) {
      fastify.log.error({ err }, 'docker ps 执行失败')
      return reply.code(503).send({
        error: true,
        code: 'DOCKER_ERROR',
        message: '无法查询容器状态',
      })
    }
  })
}
