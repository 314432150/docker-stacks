# docker-stacks Engine Design

## 1. 架构分层

```
┌────────────────────────────┐
│  Web Backend (Node.js)     │  ← 消费 JSONL 事件流
│  child_process.spawn(...)  │
└──────────┬─────────────────┘
           │ call: engine.sh <subcommand> --json [...args]
           ▼
┌────────────────────┐  ┌─────────────────────┐
│ engine/engine.sh   │  │ engine/*.sh          │  ← 核心操作层（事实来源）
│ （入口 + 路由）     │  │ discover/backup/     │     JSONL stdout
└────────┬───────────┘  │ restore/deploy/      │     stderr 日志
         │              │ _lib.sh              │
         │ source       └────────┬────────────┘
         ▼                       │ source
┌────────────────────┐          │
│ lib/               │ ←───────┘
│ common.sh          │   纯工具库（零 TUI）
│ discover.sh        │
│ state.sh           │
│ webdav.sh          │
└────────────────────┘
```

**原则**：
- `lib/` = 纯函数库，无任何终端交互（无 `read`/`clear`/`printf '\033...'`）
- `engine/` = 核心业务逻辑，接收参数 → 输出 JSONL 事件流
- 引擎只有一个调用方（Web 后端），不提供人机交互
- 所有函数输出到 stdout 的必须是合法 JSON 行，日志/调试走 stderr

## 2. 目录结构

```
scripts/
├── engine/                    # 引擎层（可执行 + 可被 source）
│   ├── engine.sh              # 入口：路径解析 → source lib → 路由
│   ├── _lib.sh                # 引擎共享：_emit, _acquire_lock, _release_lock
│   ├── discover.sh            # cmd_discover
│   ├── backup.sh              # cmd_backup
│   ├── restore.sh             # cmd_restore
│   └── deploy.sh              # cmd_deploy
├── lib/                       # 纯库（引擎引用）
│   ├── common.sh              # 颜色 + 工具
│   ├── discover.sh            # 应用扫描 + 卷解析
│   ├── state.sh               # 备份选中状态文件管理
│   └── webdav.sh              # WebDAV 纯函数（上传/下载/列表/连接测试）
```

## 3. 模块职责

### 3.1 `engine/engine.sh` — 入口

```
职责：
  - 解析自身路径 → ROOT / LIB_DIR / BACKUP_ROOT
  - 加载 global.env
  - 按依赖顺序 source lib/ → engine/_lib.sh → engine/discover → engine/backup → engine/restore → engine/deploy
  - 解析 $1 子命令，路由到对应 cmd_* 函数

子命令：
  engine.sh discover
  engine.sh backup <app1> [app2 ...]
  engine.sh restore <archive_path> <app1> [app2 ...]
  engine.sh deploy <app1> [app2 ...]

退出码：
  0 = 成功
  1 = 参数错误
  2 = 任务锁冲突（已有操作进行中）
  3 = 前置条件不满足（docker 不可用、目录不存在等）
```

### 3.2 `engine/_lib.sh` — 引擎共享基础设施

```
函数：
  _emit <json_string>              — 输出一行 JSON 到 stdout
  _acquire_lock <op_name>           — 获取任务锁，返回 0/1
  _release_lock                      — 释放任务锁
  _emit_startup_info                 — 启动时输出权限级别信息（stderr）

锁目录策略：
  优先 $ROOT/.cache，本用户不可写时回退 /tmp/docker-stacks-engine

JSON 事件类型规范：
  {"type":"start","op":"backup|restore|deploy","file":"...","apps":[...]}
  {"type":"progress","step":"...","current":N,"total":N}
  {"type":"ok","app":"name"}
  {"type":"skip","app":"name","dir":"...","reason":"..."}
  {"type":"error","msg":"...","app":"..."}
  {"type":"busy","msg":"..."}
  {"type":"done","success":N,"fail":N,[file:,size:,path:]}
```

### 3.3 `engine/discover.sh` — 应用发现

```
函数：
  cmd_discover
    输出：单行 JSON {"type":"apps","apps":[{...}]}

依赖：
  lib/discover.sh: discover_apps, get_backup_dirs, get_description
```

### 3.4 `engine/backup.sh` — 备份

```
函数：
  cmd_backup [选项] <app1> [app2 ...]

选项：
  --upload    备份后自动上传到 WebDAV（需配置 WEBDAV_*）
  --keep N    保留最近 N 个本地备份文件，删除更旧的

流程：
  1. 获取任务锁
  2. 遍历 app 列表，通过 get_backup_dirs 收集所有推荐目录
  3. 跳过不存在的目录，emit skip 事件
  4. 构建 tar 相对路径列表
  5. tar -czf → emit progress → emit done/error
  6. (可选) webdav_upload → emit progress
  7. (可选) _cleanup_old_backups → emit progress
  8. 释放锁

输出事件：
  start → progress → ok/skip → (upload progress) → (cleanup progress) → done

错误处理：
  - 不存在目录 → skip 事件，继续
  - tar 失败 → error 事件，返回 1
  - WebDAV 上传失败 → error 事件，不阻断 done 输出
```

### 3.5 `engine/restore.sh` — 还原

```
函数：
  cmd_restore <archive_path> <app1> [app2 ...]

流程：
  1. 校验 archive 存在
  2. 获取任务锁
  3. 对每个 app：
     a. 停止运行中的容器（docker compose down）
     b. 创建迁移前安全备份（pre_restore_*.tar.gz）
     c. tar -xzf 解压
     d. 重新启动容器（docker compose up -d）
  4. 释放锁

输出事件：
  start → progress(停止容器) → progress(安全备份) → progress(解压) → progress(启动) → done

错误处理：
  - archive 不存在 → error，返回 1
  - compose down 失败 → continue（不阻断）
  - tar 解压失败 → error，continue
  - compose up 超时 → error，continue
```

### 3.6 `engine/deploy.sh` — 部署

```
函数：
  cmd_deploy <app1> [app2 ...]

流程：
  1. 校验 docker compose 可用
  2. 获取任务锁
  3. 对每个 app：
     a. 确保 global.env → .env 符号链接
     b. 停止已运行的容器（docker compose down）
     c. docker compose up -d
  4. 释放锁

输出事件：
  start → progress(env) → progress(停止) → progress(部署) → ok/error → done
```

## 4. 依赖关系图

```
engine/engine.sh
  ├── lib/common.sh          (颜色 + 工具)
  ├── lib/discover.sh        (discover_apps, get_backup_dirs, parse_volumes, get_description)
  ├── lib/state.sh           (状态文件管理 — 供 backup 阶段使用)
  ├── lib/webdav.sh          (WebDAV 纯函数)
  ├── engine/_lib.sh         (_emit, _acquire_lock, _release_lock)
  ├── engine/discover.sh
  ├── engine/backup.sh       → lib/discover, lib/state
  ├── engine/restore.sh      → lib/discover, lib/webdav(可选)
  └── engine/deploy.sh       → lib/discover
```

## 5. JSON 事件流契约

每个事件是 `stdout` 上的一行合法 JSON。调用方（Web 后端）逐行 `JSON.parse`。

### 事件类型

| type | 必含字段 | 可选字段 | 说明 |
|------|---------|---------|------|
| `start` | op, apps | file | 操作开始 |
| `progress` | step | current, total, app | 进度更新 |
| `ok` | app | | 单个 app 操作成功 |
| `skip` | app, reason | dir | 跳过某项 |
| `error` | msg | app, dir | 错误（操作可能继续） |
| `busy` | msg | | 任务锁冲突，操作拒绝 |
| `done` | success, fail | file, size, path | 操作完成汇总 |

## 6. 从原始代码提取的"做事"逻辑映射

| 原始文件 | 保留（lib 纯函数） | 提取到 engine | 丢弃（TUI） |
|---------|-------------------|--------------|------------|
| common.sh | 颜色变量 | — | header/section/confirm/press_enter/check_mark/tui_fits |
| discover.sh | 全部保留 | — | — |
| state.sh | 全部保留 | — | — |
| webdav.sh | webdav_configured/connection_test/upload/download/list/backup_file_size | — | webdav_menu/webdav_management/webdav_upload_local/webdav_setup_wizard |
| backup.sh | — | tar 打包逻辑 | customize_app + 全部 TUI 渲染 |
| restore.sh | list_apps_in_backup/backup_size_mb/app_archive_paths | tar 解压 + docker 启停 | 全部 TUI |
| deploy.sh | — | .env 符号链接 + docker compose 管理 | 全部 TUI |
| install.sh | — | — | 已删除（dsctl 已移除） |
| dsctl | — | — | 已删除（引擎取代） |

## 7. WebDAV 集成

备份后可通过 `--upload` 标志自动上传到 WebDAV：

```bash
sudo engine.sh backup --upload homeassistant
```

也可独立调用 lib/webdav.sh 函数：

```bash
source scripts/lib/webdav.sh
webdav_upload backups/file.tar.gz file.tar.gz
webdav_list
webdav_download file.tar.gz backups/file.tar.gz
```

设计原则：
- WebDAV 上传是异步耗时操作，但 `--upload` 标志将其内联到备份流程末尾
- 备份成功但 WebDAV 上传失败 → 不标记整体失败，emit error 后仍然输出 done
- `--keep N` 可配合 `--upload` 使用：本地 + 远程双副本，本地自动轮转

## 8. 权限模型

### 8.1 问题

Docker 容器通过 bind mount 写入的数据文件通常属于 root（容器内进程以 root 运行）。普通用户无法读取这些文件，导致：

- **备份时**：`tar` 无法读取 root 拥有的文件 → Permission denied
- **还原时**：`tar -xzf` 无法恢复原始文件所有者 → 文件变为当前用户，权限丢失

### 8.2 方案：以 root 运行引擎

引擎不依赖 sudo 提权，而是依赖调用方以 root 身份运行：

```
EUID=0（root）  → tar 可读任何文件，tar --same-owner 可恢复权限
EUID≠0（用户）  → tar 只能操作用户可读写的文件
```

**Web 后端启动方式**：

```bash
sudo node server.js
```

或通过 systemd：

```ini
# /etc/systemd/system/ds-web.service
[Service]
User=root
ExecStart=/usr/bin/node /srv/docker-stacks/web/server.js
```

### 8.3 权限级别枚举

`discover` 输出包含 `engine.privilege` 字段：

| privilege | 含义 | 能备份 root 文件 |
|-----------|------|-----------------|
| `root` | EUID=0 | ✓ |
| `user` | 普通用户 | ✗ |

### 8.4 降级行为

以普通用户运行时：
- `tar` root 属主文件 → Permission denied → error 事件
- `tar --same-owner` → chown 操作静默忽略，文件属主变为当前用户
- 锁文件自动从 `$ROOT/.cache/` 回退到 `/tmp/`

### 8.5 约束

- 引擎代码不包含任何 `sudo` 调用
- 权限完全由调用方的 EUID 决定
- 没有 `--no-sudo` 等运行时标志
