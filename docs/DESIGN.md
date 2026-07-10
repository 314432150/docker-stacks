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
├── lib/                       # 纯库（被 engine 和旧 dsctl 共同引用）
│   ├── common.sh              # 颜色 + 工具（header/section/confirm 等 TUI 函数保留给 dsctl）
│   ├── discover.sh            # 应用扫描 + 卷解析
│   ├── state.sh               # 备份选中状态文件管理
│   └── webdav.sh              # WebDAV 纯函数（上传/下载/列表/连接测试）
└── tests/
    └── test_engine.sh         # Engine 集成测试套件
```

## 3. 模块职责

### 3.1 `engine/engine.sh` — 入口

```
职责：
  - 解析自身路径 → ROOT / LIB_DIR / BACKUP_ROOT
  - 加载 global.env
  - 按依赖顺序 source lib/ → engine/_lib.sh → engine/discover → engine/backup → engine/restore → engine/deploy
  - 预解析 --no-sudo 标志（在 _SUDO 检测后强制禁用 sudo）
  - 解析 $1 子命令，路由到对应 cmd_* 函数

选项：
  --no-sudo        禁用 sudo 提权（即使免密可用）

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

### 3.2 `engine/_lib.sh` — 引擎共享基础设施 + 权限管理

```
函数：
  _emit <json_string>              — 输出一行 JSON 到 stdout
  _acquire_lock <op_name>           — 获取任务锁，返回 0/1
  _release_lock                      — 释放任务锁
  _sudo_tar_czf <archive> <paths>    — 打包（sudo 安全包装）
  _sudo_tar_xzf <archive> <paths>    — 解压 --same-owner（sudo 安全包装）
  _sudo_tar_tzf <archive>            — 列出 tar 内容（sudo 安全包装）
  _sudo_mkdir <dir>                  — 创建目录（sudo 安全包装）
  _sudo_rm <file>                    — 删除文件（sudo 安全包装）
  _sudo_chown <user:group> <file>   — 变更所有者（sudo 安全包装）
  _emit_startup_info                 — 启动时输出权限级别信息（stderr）

常量：
  _SUDO  = "sudo" | ""              — 权限提升前缀
  LOCK_FILE = $ROOT/.cache/engine.lock（优先）或 /tmp/docker-stacks-engine/engine.lock（回退）

权限提升检测（_SUDO）：
  1. EUID==0                   → _SUDO=""（已是 root）
  2. sudo -n true 成功         → _SUDO="sudo"（免密可用）
  3. 以上均不满足               → _SUDO=""（普通用户，无特权）

锁目录三级策略：
  1. _SUDO 可用 → sudo mkdir -p $ROOT/.cache → LOCK_FILE="$ROOT/.cache/engine.lock"
  2. $ROOT/.cache 目录本用户可写 → 直接使用
  3. 均不可用 → LOCK_FILE="/tmp/docker-stacks-engine/engine.lock"

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
  cmd_backup <app1> [app2 ...]

流程：
  1. 获取任务锁
  2. 遍历 app 列表，通过 get_backup_dirs 收集所有推荐目录
  3. 跳过不存在的目录，emit skip 事件
  4. 构建 tar 相对路径列表
  5. tar -czf → emit progress → emit done/error
  6. 释放锁

输出事件：
  start → progress → ok/skip → done

错误处理：
  - 不存在目录 → skip 事件，继续
  - tar 失败 → error 事件，返回 1
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
| install.sh | — | — | 全部（全局命令安装不再需要） |
| dsctl | — | — | 全部（主菜单 + 路由不再需要） |

## 7. WebDAV 集成

暂不将 WebDAV 上传嵌入 `cmd_backup`（保持独立调用）。原因：
- WebDAV 上传是异步耗时操作，应独立调用
- 备份成功但 WebDAV 失败不应标记整体失败
- Web 后端可先调 backup，再调 webdav_upload 函数

后续可加 `cmd_backup --upload` 选项。

## 8. 权限模型

### 8.1 问题

Docker 容器通过 bind mount 写入的数据文件通常属于 root（容器内进程以 root 运行）。例如 `homeassistant/data/config/.storage/auth` 属于 root。普通用户无法读取这些文件，导致：

- **备份时**：`tar` 无法读取 root 拥有的文件 → Permission denied
- **还原时**：`tar -xzf` 无法恢复原始文件所有者 → 文件变为当前用户，权限丢失

### 8.2 方案：引擎自检测 + _SUDO 包装

```
engine.sh 启动 → 检测 sudo -n 是否可用
                  ↓
         _SUDO="sudo"（免密可用） 或 _SUDO=""（不可用）
                  ↓
    所有特权操作通过 _sudo_* 包装函数执行：
    
    _sudo_tar_czf   → $_SUDO tar -czf     # 备份打包（保留权限）
    _sudo_tar_xzf   → $_SUDO tar --same-owner -xzf  # 还原解压（恢复所有者）
    _sudo_tar_tzf   → $_SUDO tar -tzf     # 列出归档内容
    _sudo_mkdir     → $_SUDO mkdir -p     # 创建锁目录
    _sudo_rm        → $_SUDO rm -f        # 清理锁文件
    _sudo_chown     → $_SUDO chown        # 修正归档文件所有者
```

### 8.3 Web 调用如何提权

Web 后端通过 `child_process.spawn('engine.sh', [...])` 调用引擎，**无需 CLI 层**。

提权方式：确保运行 Web 后端的用户具有 `sudo NOPASSWD` 权限：

```sudoers
# /etc/sudoers.d/docker-stacks-engine
<web-user> ALL=(ALL) NOPASSWD: /usr/bin/tar, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/docker, /usr/bin/tee
```

或者更简单：让 Web 后端以已配置免密的用户身份运行（如 systemd `User=fishme`）：

```ini
# /etc/systemd/system/ds-web.service
[Service]
User=fishme
ExecStart=/usr/bin/node /srv/docker-stacks/web/server.js
```

### 8.4 权限级别枚举

`discover` 输出包含 `engine.privilege` 字段：

| privilege | 含义 | _SUDO | 能备份 root 文件 |
|-----------|------|-------|-----------------|
| `root` | EUID=0 | `""` | ✓ |
| `sudo` | 免密 sudo 可用 | `"sudo"` | ✓ |
| `user` | 普通用户 | `""` | ✗ |

### 8.5 降级行为

当 `_SUDO=""` 且遇到 root 文件时：
- `_sudo_tar_czf` → 以普通用户身份运行 tar → root 文件 Permission denied → error 事件
- `_sudo_tar_tzf` → 同样降级
- `_sudo_tar_xzf` → 先尝试 `tar --same-owner -xzf`，失败则回退 `tar -xzf`（不保留所有者）
- 锁文件自动从 `/srv/docker-stacks/.cache/` 回退到 `/tmp/`

### 8.6 --no-sudo 标志

即使 sudo 免密可用，也可以通过 `--no-sudo` 强制以降级模式运行：

```bash
./engine.sh --no-sudo backup openclaw
```
