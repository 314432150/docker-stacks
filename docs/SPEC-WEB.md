# Web API Specification — 输入/输出契约

## 1. 通用约定

- **Base URL**：`http://localhost:3001`（开发）或 `http://localhost:3001`（生产）
- **Content-Type**：请求 `application/json`，响应 `application/json`（SSE 除外）
- **错误格式**：
  ```json
  {"error": true, "code": "BAD_REQUEST", "message": "..."}
  ```
- **HTTP 状态码**：200/201/202/400/404/500
- **SSE**：`Content-Type: text/event-stream`

## 2. 参数校验规则

| 参数 | 类型 | 规则 |
|------|------|------|
| `apps[]` | string[] | 每个元素 `/^[a-zA-Z0-9][-a-zA-Z0-9_]*$/`，至少 1 个 |
| `archive` | string | 仅文件名或相对路径，不允许 `..` 或绝对路径 |
| `upload` | boolean | 可选，默认 false |
| `keep` | int | 可选，≥0，默认 0（不清理） |

防注入策略：
- app 名 → 正则校验，不通过返回 400
- archive → 禁止 `..` 和 `/` 开头，拼接时使用 `path.resolve(BACKUP_ROOT, archive)` 并验证结果以 `BACKUP_ROOT` 开头

---

## 3. API 端点

### 3.1 `GET /api/apps`

**请求**：无参数

**响应** `200 OK`：
```json
{
  "type": "apps",
  "engine": { "privilege": "root" },
  "apps": [
    {
      "name": "qbittorrent",
      "description": "BitTorrent 下载器",
      "dirs": [
        {"path": "data/config", "recommended": true, "exists": true},
        {"path": "data/downloads", "recommended": false, "exists": true}
      ]
    }
  ]
}
```

**错误**：
```json
// 500 — 引擎执行失败
{"error": true, "code": "ENGINE_ERROR", "message": "引擎 discover 执行失败"}
```

**行为**：直接透传 `entry.sh discover` 的 stdout JSON。

---

### 3.2 `POST /api/backup`

**请求体**：
```json
{
  "apps": ["qbittorrent"],
  "upload": true,
  "keep": 5
}
```

**请求校验**：
- `apps` 必填，非空数组
- `upload` 可选，必须为 boolean
- `keep` 可选，必须为 ≥0 整数

**成功响应** `202 Accepted`：
```json
{
  "taskId": "backup-a1b2c3d4",
  "status": "pending"
}
```

**错误响应** `400 Bad Request`：
```json
{"error": true, "code": "VALIDATION_ERROR", "message": "apps 不能为空"}
```

**任务锁冲突** `409 Conflict`：
```json
{"error": true, "code": "LOCK_BUSY", "message": "已有任务运行中"}
```

**行为**：
1. 生成 taskId
2. 注册 task 到内存状态
3. 异步启动 `entry.sh backup`（可选 `--upload`, `--keep N`）
4. 每个 JSONL 事件 → 存入 task.history + emit 到该 task 的 EventEmitter
5. 引擎退出 → 设置 task.status，启动 5 分钟清理定时器

---

### 3.3 `POST /api/restore`

**请求体**：
```json
{
  "archive": "20260711-0230_qbittorrent.tar.gz",
  "apps": ["qbittorrent"]
}
```

**请求校验**：
- `archive` 必填，字符串，不含 `..`，不以 `/` 开头
- `apps` 必填，非空数组

**成功响应** `202 Accepted`：
```json
{
  "taskId": "restore-e5f6g7h8",
  "status": "pending"
}
```

**错误响应**：
```json
// 400 — 参数错误
{"error":true,"code":"VALIDATION_ERROR","message":"archive 不能为空"}

// 404 — 备份文件不存在
{"error":true,"code":"FILE_NOT_FOUND","message":"备份文件不存在: /srv/docker-stacks/instance/backups/xxx.tar.gz"}
```

---

### 3.4 `POST /api/deploy`

**请求体**：
```json
{
  "apps": ["qbittorrent", "openclaw"]
}
```

**请求校验**：
- `apps` 必填，非空数组

**成功响应** `202 Accepted`：
```json
{
  "taskId": "deploy-i9j0k1l2",
  "status": "pending"
}
```

---

### 3.5 `GET /api/events?taskId=<id>`

**查询参数**：
- `taskId`（必填）：任务 ID

**响应** `200 OK` + SSE stream：

```
data: {"type":"start","op":"backup","file":"20260711-0230_qbittorrent.tar.gz","apps":["qbittorrent"]}

data: {"type":"progress","step":"打包 3 个目录","current":1,"total":1}

data: {"type":"done","file":"...","size":"12M","path":"...","success":1,"fail":0}

event: close
data: {"type":"closed","taskId":"backup-a1b2c3d4"}
```

**错误**：
```
// taskId 不存在 → 404
// taskId 缺失 → 400
// 非 SSE 事件 → 错误 JSON 行（不推荐，建议直接返回 404）
```

**行为**：
1. 从 task registry 查找 taskId
2. 不存在 → 404
3. 推送所有已收集的历史事件（如果 task 已结束则推送完后关闭）
4. 订阅 task 的 EventEmitter
5. 新事件到达 → `data: <json>\n\n`
6. 客户端断开或 task 完成 → 关闭连接

---

## 4. 引擎桥接层规范 `engine.js`

### `executeEngine(subCommand, args, onEvent)`

**参数**：
```
subCommand: "discover" | "backup" | "restore" | "deploy"
args:       string[] — 传递给引擎的位置参数
onEvent:    (event: EngineEvent) => void — 可选，按行回调
```

**返回**：`Promise<{ exitCode: number, stderr: string }>`

**DISCOVER 特殊行为**：
- `subCommand === "discover"` 时，自动收集单行 JSON 作为输出
- 同时支持 `onEvent` 回调（兼容性）

**路径解析**：
```
ROOT         = path.resolve(scriptDir, "../../../..")  // web/server/src → ROOT
ENGINE       = path.join(ROOT, "service/engine/cmd/entry.sh")
BACKUP_ROOT  = path.join(ROOT, "backups")
```

**引擎环境变量**：
```
PATH  — 继承当前 PATH
HOME  — 继承当前 HOME
```

---

## 5. Task 状态机

```
pending → running → success | failed
```

| 状态 | 含义 | 可订阅 SSE |
|------|------|-----------|
| `pending` | 引擎还未启动 | ✓（推送时为 running 状态） |
| `running` | 引擎正在执行 | ✓ |
| `success` | 引擎正常退出（code 0） | ✓（推送历史事件后关流） |
| `failed` | 引擎异常退出（code ≠ 0） | ✓（推送历史事件后关流） |

**Task 对象结构**：
```js
{
  taskId: "backup-abc123",       // 唯一 ID
  type: "backup",                 // backup | restore | deploy
  status: "running",              // pending | running | success | failed
  history: [...events],           // 已收集的所有事件
  emitter: EventEmitter,          // SSE 广播用
  createdAt: Date,
  cleanupTimer: Timeout|null      // 5 分钟后清理
}
```

---

## 6. 事件类型透传

Web 层不修改引擎事件，完全透传：

| type | 前端行为 |
|------|---------|
| `start` | EventLog 显示操作开始行 |
| `progress` | 进度条更新或状态文字 |
| `ok` | 绿色对勾，app 操作成功 |
| `skip` | 黄色提示，跳过原因 |
| `error` | 红色错误文字 |
| `busy` | 橙色警告（锁冲突） |
| `done` | 操作完成汇总 + 进度条 100% |

---

## 7. 测试契约

### 后端测试

| 测试 | 验证点 |
|------|--------|
| `engine.js` spawn 正常 | discover 输出解析为有效 JSON |
| `engine.js` 逐行回调 | JSONL 多行每行触发 onEvent |
| `engine.js` 错误退出 | exitCode ≠ 0 时 reject |
| `GET /api/apps` | 返回 200 + 有效 apps 结构 |
| `POST /api/backup` | 202 + taskId，SSE 可订阅 |
| `POST /api/backup` 参数校验 | apps 为空 → 400 |
| `POST /api/restore` archive 不存在 | 404 |
| `POST /api/restore` archive 含 `..` | 400 |
| `GET /api/events` taskId 不存在 | 404 |
| `GET /api/events` 已结束 task | 返回历史事件后关流 |
| 并发锁 | 同时发起两个 backup → 第二个返回 409 |

### 前端测试

| 测试 | 验证点 |
|------|--------|
| Dashboard 挂载 | AppCard 渲染出 discover 返回的 app 列表 |
| AppCard 组件 | 显示 name, description, 权限标识 |
| Backup 页 form | 选择 app → 设置选项 → 提交按钮启用 |
| EventLog 组件 | SSE 收到 progress 事件 → 显示 step 文字 |
| EventLog done | SSE close 事件 → 进度条 100% |
| 导航 | 点击不同 Tab → 切换到对应 View |

### 模拟引擎

测试用 `mock-engine.sh`：
```bash
#!/bin/sh
# 用法: mock-engine.sh <subcommand> [args...]
case "$1" in
  discover)
    cat <<'EOF'
{"type":"apps","engine":{"privilege":"root"},"apps":[{"name":"test-app","description":"Test app","dirs":[{"path":"data/config","recommended":true,"exists":true}]}]}
EOF
    ;;
  backup)
    echo '{"type":"start","op":"backup","file":"test.tar.gz","apps":["test-app"]}'
    echo '{"type":"progress","step":"打包 1 个目录","current":1,"total":1}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","file":"test.tar.gz","size":"1M","path":"/tmp/test.tar.gz","success":1,"fail":0}'
    ;;
  restore)
    echo '{"type":"start","op":"restore","file":"test.tar.gz","apps":["test-app"]}'
    echo '{"type":"progress","step":"解压 test-app","current":1,"total":3}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","success":1,"fail":0}'
    ;;
  deploy)
    echo '{"type":"start","op":"deploy","apps":["test-app"]}'
    echo '{"type":"progress","step":"部署 test-app","current":1,"total":1}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","success":1,"fail":0}'
    ;;
  *)
    echo '{"type":"error","msg":"未知子命令: '$1'"}'
    exit 1
    ;;
esac
exit 0
```
