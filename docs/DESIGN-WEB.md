# docker-stacks Web Design

## 1. 架构概览

```
Browser                         Server
┌─────────────────┐    HTTP/SSE  ┌──────────────────────────────┐
│ Vue 3 + Naive UI │ ◄────────── │ Fastify (Node.js)            │
│ (Vite dev/build) │             │                              │
│                  │  GET /api   │  /api/apps → engine discover │
│  ┌─────────────┐ │  POST       │  /api/backup → engine backup │
│  │ 应用列表     │ │  /api/...   │  /api/restore→ engine restore│
│  │ 备份面板     │ │             │  /api/deploy → engine deploy │
│  │ 还原面板     │ │  SSE        │  /api/events → SSE 事件转发  │
│  │ 部署面板     │ │  stream     │                              │
│  └─────────────┘ │             │  child_process.spawn(...)    │
└─────────────────┘             │              │               │
                                │              ▼               │
                                │  ┌──────────────────────┐    │
                                │  │ service/engine/cmd/*  │    │
                                │  └──────────────────────┘    │
                                └──────────────────────────────┘
```

**原则**：
- 后端是薄桥接层：不实现业务逻辑，只负责 `spawn` 引擎 → 解析 JSONL → 推给前端
- 前端是纯展示层：不操作文件系统，所有操作通过 API → 后端 → 引擎
- SSE 单向推送实时进度，无需 WebSocket
- 前后端分离：Vite 开发代理到 Fastify，生产构建的静态文件由 Fastify 托管

## 2. 目录结构

```
service/web/
├── server/                      # 后端 (Node.js + Fastify)
│   ├── package.json
│   ├── src/
│   │   ├── app.js               # Fastify 应用初始化 + 路由注册
│   │   ├── routes/
│   │   │   ├── apps.js          # GET /api/apps
│   │   │   ├── backup.js        # POST /api/backup
│   │   │   ├── restore.js       # POST /api/restore
│   │   │   ├── deploy.js        # POST /api/deploy
│   │   │   └── events.js        # GET /api/events (SSE)
│   │   ├── engine.js            # 引擎桥接层：spawn + JSONL 解析
│   │   └── config.js            # ROOT/BACKUP_ROOT/ENGINE 路径解析
│   └── tests/
│       ├── engine.test.js        # 引擎桥接层测试
│       ├── routes.test.js        #  API 路由测试
│       └── fixtures/
│           └── mock-engine.sh    # 模拟引擎输出
│
├── client/                       # 前端 (Vue 3 + Vite + Naive UI)
│
├── client/                       # 前端 (Vue 3 + Vite + Naive UI)
│   ├── package.json
│   ├── vite.config.js
│   ├── index.html
│   ├── src/
│   │   ├── main.js              # Vue 入口
│   │   ├── App.vue              # 根组件（布局 + 路由）
│   │   ├── views/
│   │   │   ├── Dashboard.vue    # 仪表盘/应用列表
│   │   │   ├── Backup.vue       # 备份操作页
│   │   │   ├── Restore.vue      # 还原操作页
│   │   │   └── Deploy.vue       # 部署操作页
│   │   ├── components/
│   │   │   ├── AppCard.vue      # 应用卡片
│   │   │   ├── EventLog.vue     # 事件日志/进度展示
│   │   │   ├── AppSelector.vue  # 应用多选器
│   │   │   └── NavHeader.vue    # 导航栏
│   │   ├── composables/
│   │   │   ├── useApi.js        # API 请求封装
│   │   │   └── useSSE.js        # SSE 连接管理
│   │   └── style.css            # 全局样式
│   └── tests/
│       └── components.test.js   # 组件测试
```

## 3. 模块职责

### 3.1 引擎桥接层 `service/web/server/src/engine.js`

```
职责：
  - 封装 spawn(entry.sh, [...args])
  - 逐行读取 stdout → JSON.parse → 对每行触发回调 (事件驱动)
  - stderr 合并输出到服务器日志
  - 进程退出时 resolve/reject Promise

接口：
  executeEngine(subCommand, args, onEvent) → Promise<{exitCode, stderr}>
    subCommand: "discover" | "backup" | "restore" | "deploy"
    args:       位置参数列表 (如 ["--upload", "--keep", "3", "app1"])
    onEvent:    回调 (eventObj) => void，每个 JSONL 事件触发一次
    返回:       {exitCode: number, stderr: string}

实现细节：
  - spawn(ENGINE, [subCommand, ...args], { env: { PATH, ... }, cwd: ROOT })
  - stdout 按行分割用 readline (Node.js 内置)
  - 每行 try { JSON.parse(line); onEvent(event); } catch { /* 忽略非法行 */ }
  - 进程退出时 resolve，同时捕获 process error
```

### 3.2 REST API 路由

| 方法 | 路径 | 行为 | 响应 |
|------|------|------|------|
| `GET` | `/api/apps` | 调用 engine discover | `{ apps, engine }` JSON |
| `POST` | `/api/backup` | 调用 engine backup，通过 SSE 推送进度 | `202 Accepted` + SSE stream |
| `POST` | `/api/restore` | 调用 engine restore，SSE 推送进度 | `202 Accepted` + SSE stream |
| `POST` | `/api/deploy` | 调用 engine deploy，SSE 推送进度 | `202 Accepted` + SSE stream |

**POST /api/backup 请求体**：
```json
{
  "apps": ["qbittorrent", "openclaw"],
  "upload": false,
  "keep": 5
}
```

**POST /api/restore 请求体**：
```json
{
  "archive": "20260711-0230_qbittorrent.tar.gz",
  "apps": ["qbittorrent"]
}
```

**POST /api/deploy 请求体**：
```json
{
  "apps": ["qbittorrent", "openclaw"]
}
```

### 3.3 SSE 事件流 `GET /api/events`

```
职责：
  - 读取 ?taskId 查询参数，订阅指定任务的实时事件
  - 如果 task 不存在 → 404
  - 如果 task 结束 → 返回历史事件然后关闭流
  - 如果 task 运行中 → 保持连接，事件到达时推送

SSE 格式：
  data: {"type":"progress","step":"打包 3 个目录","current":1,"total":1}

  data: {"type":"done","success":1,"fail":0}

  event: close
  data: {"type":"closed","taskId":"xxx"}

连接管理：
  - 每个 SSE 连接对应一个 EventEmitter 监听器
  - 客户端断开时自动清理监听器 (req.on('close'))
  - 后端重启时 SSE 连接断裂，前端自动重连
```

### 3.4 前端路由

```
/                 → Dashboard（应用列表 + 快捷操作入口）
/backup           → Backup（选择应用 → 备份设置 → 实时进度）
/restore          → Restore（选择备份文件 → 选择应用 → 实时进度）
/deploy           → Deploy（选择应用 → 实时进度）
```

### 3.5 前端组件树

```
App.vue
├── NavHeader.vue          # 导航栏：docker-stacks 标题 + 路由链接
├── Dashboard.vue          # /
│   ├── AppCard.vue × N    # 每个应用的卡片：名称、描述、状态、操作按钮
│   └── EventLog.vue       # 最近的全局事件日志
├── Backup.vue             # /backup
│   ├── AppSelector.vue    # 多选应用
│   ├── 选项：--upload 开关、--keep N
│   ├── 操作按钮：开始备份
│   └── EventLog.vue       # 实时备份进度
├── Restore.vue            # /restore
│   ├── 备份文件选择器
│   ├── AppSelector.vue    # 多选要还原的应用
│   ├── 操作按钮：开始还原
│   └── EventLog.vue       # 实时还原进度
└── Deploy.vue             # /deploy
    ├── AppSelector.vue    # 多选应用
    ├── 操作按钮：开始部署
    └── EventLog.vue       # 实时部署进度
```

## 4. 数据流

### 4.1 应用发现流程

```
前端 Dashboard mount → GET /api/apps
  → server: executeEngine("discover", [], callback)
    → spawn entry.sh discover
    → 单行 JSON parse → resolve
  → 返回 { apps, engine } JSON
  → 前端渲染 AppCard 列表
```

### 4.2 备份流程

```
前端 Backup 页 → 用户选择 app + 设置选项 → 点击"开始备份"
  → POST /api/backup { apps, upload, keep }
  → server: 生成 taskId, 创建 EventEmitter
  → executeEngine("backup", ["--upload","--keep","5","app1"], onEvent)
    onEvent: 事件存入 eventHistory[] + 广播 EventEmitter
  → 返回 202 { taskId }
  → 前端: new EventSource(/api/events?taskId=xxx)
    → SSE 逐条推送 → EventLog 实时显示
    → "done" 事件 → 自动关闭 SSE 连接
```

### 4.3 还原/部署流程

与备份流程相同，分别 POST `/api/restore` 和 `/api/deploy`。

## 5. Task 生命周期模型

```
Task 状态机：
  pending  → 已创建但引擎未启动
  running  → 引擎运行中，SSE 可订阅
  success  → 引擎成功退出 (code=0)
  failed   → 引擎异常退出 (code≠0)

Task 清理：
  - 成功/失败后保留 5 分钟（让前端有时间通过 SSE 拿到最后的事件）
  - 5 分钟后自动清理 eventHistory + EventEmitter
  - 同时最多 1 个 running task（由引擎层锁保证）
```

## 6. 错误处理

| 场景 | 后端行为 | 前端表现 |
|------|---------|---------|
| 引擎 spawn 失败 | 500 + error 事件 | 红色错误提示 |
| 引擎 exit code ≠ 0 | SSE 推送 error → closed | EventLog 显示错误 |
| SSE 连接断开 | 客户端 `EventSource` 自动重连 | 短暂"重连中"提示 |
| 引擎锁冲突 (exit 2) | SSE 推送 busy 事件 | 黄色提示"任务进行中" |
| 请求参数缺失 | 400 JSON validation error | 表单红色提示 |
| docker 不可用 (deploy) | SSE 推送 error (code 3) | 红色提示"docker 不可用" |

## 7. 依赖

### 后端 (server/package.json)

```
runtime:
  - fastify           # Web 框架
  - @fastify/static   # 托管前端静态文件（生产模式）
  - @fastify/cors     # 跨域（开发时 Vite 代理不需要，但直接访问需要）

dev:
  - tap / vitest      # 测试框架
```

### 前端 (client/package.json)

```
runtime:
  - vue               # 3.x
  - vue-router        # 路由
  - naive-ui          # UI 组件库
  - @vicons/ionicons5 # 图标

dev:
  - vite
  - @vitejs/plugin-vue
  - vitest            # 测试框架
  - @vue/test-utils   # Vue 测试工具
  - jsdom             # 测试 DOM 环境
```

## 8. 部署

### 开发模式

```bash
# 终端 1: 启动后端（端口 3001）
cd service/web/server && npm run dev

# 终端 2: 启动前端（端口 5173, 代理 API 到 3001）
cd service/web/client && npm run dev
```

前端 Vite 配置代理：
```js
// vite.config.js
export default defineConfig({
  server: {
    proxy: {
      '/api': 'http://localhost:3001'
    }
  }
})
```

### 生产模式

```bash
# 构建前端
cd service/web/client && npm run build   # 输出 → service/web/server/static/

# 启动后端（Fastify 托管前端静态文件 + API）
cd service/web/server && node src/app.js
```

访问 `http://localhost:3001` → 完整 Web 应用。

### Docker 部署（后续阶段）

`service/docker/compose.yml` + `Dockerfile`，将 service/web/ 挂载到容器，后端以 root 运行（spawn entry.sh 需要 root 权限操作容器数据文件）。

## 9. 安全考虑

- 无身份认证（第一阶段）：内网部署，假设受信任网络环境
- 引擎 spawn 参数校验：app 名只允许字母数字连字符下划线，防命令注入
- 备份文件路径校验：只允许 `${BACKUP_ROOT}/` 下文件，防路径遍历
- 后期可加基础 auth 中间件或 nginx basic auth
