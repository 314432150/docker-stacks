# Docker Stacks

NAS 上运行的 Docker Compose 服务编排仓库，通过飞牛 NAS (fnOS) 自带 Docker 工具管理。

## 目录结构

```text
docker-stacks/
  global.env           # 共用变量（唯一源文件）
  stacks/              # 各应用 compose + 运行时数据
  scripts/             # 备份、恢复脚本
```

应用目录：

```text
stacks/<应用名>/
  compose.yml
  .env -> ../../global.env # 符号链接，指向根 global.env，所有 stack 共享同一份
  data/                # 运行时持久化数据
```

## 快速开始

```bash
# 1. 克隆到 NAS
git clone https://github.com/314432150/docker-stacks.git /opt/docker-stacks
cd /opt/docker-stacks

# 2. 修改 global.env（NAS_IP、MEDIA_ROOT 等），所有 stack 通过 symlink 自动共享
vim global.env

# 3. 在飞牛 NAS Docker 管理界面中导入 stacks/ 下的 compose 文件并启动
```

## 入口说明

| 方式 | 命令 | 适用场景 |
|------|------|----------|
| fnOS Docker | 飞牛 NAS 管理界面 | **主要方式**：可视化管理所有 compose 栈、容器详情 |
| 命令行 | `cd stacks/jellyfin && docker compose up -d` | 命令行调试单个服务 |

> 修改根 `global.env` 后所有 stack 自动生效（符号链接）。



## 备份与恢复

零依赖，纯 Bash 实现。

### 交互式工具

```bash
# 主菜单（备份 / 还原）
bash scripts/backup.sh

# 直接进入备份模式
bash scripts/backup.sh backup

# 非交互式一键备份全部推荐项
bash scripts/backup.sh backup -y

# 直接进入还原模式
bash scripts/backup.sh restore

# 指定备份路径
BACKUP_ROOT=/mnt/data/nas-backup bash scripts/backup.sh
```

**功能亮点：**
- 自动发现 `stacks/` 下所有应用，无需手动维护应用列表
- 解析 `compose.yml` 卷挂载，智能区分 配置数据 / 缓存 / 外部挂载
- 每个应用预选推荐备份项（跳过缓存目录），可自由勾选
- 还原时列出所有历史备份，自由选择要还原的应用
- 备份格式：`{应用}_{目录}.tar.gz` 存入按时间戳命名的文件夹

### 命令行快速备份（向后兼容）

```bash
# 备份指定应用
bash scripts/backup.sh jellyfin vaultwarden

# 恢复指定应用
bash scripts/restore.sh backups/20250625-120000 jellyfin
```

## 仓库边界

- **进 Git**：全部文件，包括 `global.env`、`data/` 运行时数据、脚本、文档
- **不进 Git**：`backups/`（备份输出）
