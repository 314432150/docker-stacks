# Engine Specification — 输入/输出契约

## 1. 通用约定

- **入口**：`scripts/engine/engine.sh <subcommand> [args...]`
- **输出**：stdout = JSONL（每行合法 JSON），stderr = 日志/警告（含启动时权限级别报告）
- **退出码**：0=成功, 1=参数错误, 2=锁冲突, 3=前置条件不满足
- **任务锁**：写入操作（backup/restore/deploy）受 lock 保护，优先 `$ROOT/.cache/engine.lock`，不可写时回退 `/tmp/docker-stacks-engine/engine.lock`
- **ROOT**：engine.sh 向上两级目录（`scripts/engine/../..`）
- **权限**：无 sudo 依赖，完全由调用方 EUID 决定。以 root 启动 → 完整权限；以普通用户启动 → 仅操作用户可读写文件

---

## 2. discover — 应用发现

### 调用
```bash
./engine.sh discover
```

### 输入
无

### 输出（stdout，单行 JSON）
```json
{
  "type": "apps",
  "engine": {
    "privilege": "user"
  },
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

`engine.privilege` 枚举：
- `"root"` — 以 root 身份运行（EUID=0）
- `"user"` — 普通用户

### 退出码
- `0`：成功

### 边界情况
- 无 compose.yml 应用 → `{"type":"apps","apps":[]}`
- 目录不存在 → `"exists": false`
- 空描述 → `"description": ""`

---

## 3. backup — 备份

### 调用
```bash
./engine.sh backup [--upload] [--keep N] <app1> [app2 app3 ...]
```

### 输入
- `--upload`：可选，备份后自动上传到 WebDAV（需配置 WEBDAV_*）
- `--keep N`：可选，保留最近 N 个本地备份，删除更旧的
- 位置参数：应用名列表（至少 1 个）
- 来自 lib/discover.sh：`get_backup_dirs <app>` 获取每个 app 的可备份目录
- 来自 lib/state.sh：`select_all_recommended` 自动勾选推荐目录
- 环境变量：`BACKUP_ROOT`（默认 `$ROOT/backups`）

### 输出（stdout，逐行 JSONL）

**正常流程**：
```jsonl
{"type":"start","op":"backup","file":"20260711-0230_qbittorrent.tar.gz","apps":["qbittorrent"]}
{"type":"progress","step":"收集 qbittorrent/data"}
{"type":"progress","step":"打包 3 个目录","current":1,"total":1}
{"type":"done","file":"20260711-0230_qbittorrent.tar.gz","size":"12M","path":"/srv/docker-stacks/backups/20260711-0230_qbittorrent.tar.gz"}
```

**有目录不存在**：
```jsonl
{"type":"start","op":"backup","file":"...","apps":["app1"]}
{"type":"skip","app":"app1","dir":"stacks/app1/missing","reason":"目录不存在"}
{"type":"progress","step":"打包 2 个目录","current":1,"total":1}
{"type":"done","file":"...","size":"5M","path":"..."}
```

**tar 打包失败**：
```jsonl
{"type":"start","op":"backup","file":"...","apps":["app1"]}
{"type":"progress","step":"打包 N 个目录","current":1,"total":1}
{"type":"error","msg":"打包失败: ..."}
```
→ 退出码 1

**任务锁冲突**：
```jsonl
{"type":"busy","msg":"已有任务运行中: 12345 backup"}
```
→ 退出码 2

### 退出码
- `0`：成功打包
- `1`：tar 失败 / 参数错误 / 无可备份目录
- `2`：锁冲突

### 文件名规则
```
{BACKUP_ROOT}/{timestamp}_{app1}_{app2}.tar.gz
timestamp = date +%Y%m%d-%H%M%S
```

### --upload 事件
```jsonl
{"type":"start","op":"backup","file":"...","apps":["app1"]}
{"type":"progress","step":"打包 3 个目录","current":1,"total":1}
{"type":"ok","app":"..."}
{"type":"progress","step":"上传 ... 到 WebDAV"}
{"type":"progress","step":"WebDAV 上传成功"}
{"type":"done","file":"...","size":"...","path":"..."}
```

WebDAV 上传失败时：
```jsonl
{"type":"error","msg":"WebDAV 上传失败"}
{"type":"done",...}
```
→ 退出码仍为 0（备份本地已成功）

### --keep N 事件
```jsonl
{"type":"progress","step":"清理旧备份: old_file.tar.gz"}
```

### 边界情况
- 指定 app 无 compose.yml → skip 事件
- 所有 app 都无推荐目录 → 退出码 1
- 目录存在但为空 → 仍然打包（tar 支持空目录）
- 6 个以上 app → 文件名按原逻辑截断

---

## 4. restore — 还原

### 调用
```bash
./engine.sh restore <archive_path> <app1> [app2 ...]
```

### 输入
- `archive_path`：tar.gz 备份文件绝对路径
- 位置参数：要还原的应用名列表（至少 1 个）

### 输出（stdout，逐行 JSONL）

**正常流程**：
```jsonl
{"type":"start","op":"restore","file":"20260711-0230_qbittorrent.tar.gz","apps":["qbittorrent"]}
{"type":"progress","step":"停止 qbittorrent","current":1,"total":5}
{"type":"progress","step":"安全备份 qbittorrent","current":2,"total":5}
{"type":"progress","step":"解压 qbittorrent","current":3,"total":5}
{"type":"ok","app":"qbittorrent"}
{"type":"progress","step":"启动 qbittorrent","current":4,"total":5}
{"type":"done","success":1,"fail":0}
```

**容器停止失败（不阻断）**：
```jsonl
{"type":"start","op":"restore","file":"...","apps":["app1"]}
{"type":"error","app":"app1","msg":"容器停止失败"}
{"type":"progress","step":"解压 app1"}
{"type":"ok","app":"app1"}
{"type":"done","success":1,"fail":0}
```

**archive 不存在**：
```jsonl
{"type":"error","msg":"备份文件不存在: /path/to/missing.tar.gz"}
```
→ 退出码 1

### 退出码
- `0`：全部还原成功
- `1`：参数错误 / archive 不存在
- `2`：锁冲突

### 安全备份规则
- 还原前检查目标目录是否有内容
- 有内容 → 自动创建 `$BACKUP_ROOT/pre_restore_{timestamp}/{dirs}.tar.gz`
- 安全备份失败 → emit error 但不阻断还原

### 容器生命周期
- 还原前：对每个 app，如有运行中容器 → `docker compose down`
- 还原后：对每个 app，如有 compose.yml → `docker compose up -d`(timeout 60s)
- compose 不可用 → emit error，跳过容器管理

### 边界情况
- app 在备份中不存在 → skip 事件
- compose down/up 失败 → error 事件，continue
- 目标目录为空 → 跳过安全备份
- 空 app 列表 → 退出码 1

---

## 5. deploy — 部署

### 调用
```bash
./engine.sh deploy <app1> [app2 ...]
```

### 输入
- 位置参数：应用名列表（至少 1 个）

### 输出（stdout，逐行 JSONL）

**正常流程**：
```jsonl
{"type":"start","op":"deploy","apps":["qbittorrent","openclaw"]}
{"type":"progress","step":"qbittorrent .env 已就绪"}
{"type":"progress","step":"部署 qbittorrent","current":1,"total":2}
{"type":"ok","app":"qbittorrent"}
{"type":"progress","step":"部署 openclaw","current":2,"total":2}
{"type":"ok","app":"openclaw"}
{"type":"done","success":2,"fail":0}
```

**docker compose 不可用**：
```jsonl
{"type":"error","msg":"docker compose 不可用"}
```
→ 退出码 3

### 退出码
- `0`：全部部署成功
- `1`：参数错误
- `2`：锁冲突
- `3`：docker compose 不可用

### .env 符号链接
- global.env 存在 → 自动为每个 app 创建 `stacks/<app>/.env → ../../global.env`
- global.env 不存在 → 跳过，emit progress

### 容器生命周期
- 部署前先 `docker compose down`（如果有运行中的）
- 然后 `docker compose up -d`

### 边界情况
- app 无 compose.yml → skip 事件
- compose up 失败 → error 事件，continue 下一个
- 空 app 列表 → 退出码 1

---

## 6. engine.sh 入口行为

### 无参数
```jsonl
{"type":"error","msg":"未指定子命令，用法: engine.sh {discover|backup|restore|deploy} [...]"}
```
→ 退出码 1

### 未知子命令
```jsonl
{"type":"error","msg":"未知子命令: xxx"}
```
→ 退出码 1

### --help / -h
```
输出: usage 文本到 stdout
退出码: 0
```
