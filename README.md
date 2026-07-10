# Docker Stacks

NAS 上运行的 Docker Compose 服务编排仓库，部署在 `/srv/docker-stacks` 下。

## 目录结构

```text
docker-stacks/
├── global.env               # 全局环境变量，所有 stack 的 .env 通过符号链接指向此文件
├── scripts/
│   ├── dsctl                 # 主入口，可注册为全局命令 dsctl
│   └── lib/                  # 功能模块（按职责拆分）
│       ├── common.sh         #   终端颜色、工具函数
│       ├── discover.sh       #   应用发现、卷解析
│       ├── state.sh          #   备份选中状态管理
│       ├── backup.sh         #   交互式备份
│       ├── restore.sh        #   交互式还原
│       ├── deploy.sh         #   交互式部署
│       └── install.sh        #   安装/卸载全局命令
├── backups/                 # 备份输出目录，不进 Git
│
└── stacks/                  # 9 个 Docker Compose 应用
    ├── homeassistant/       # 智能家居
    │   ├── compose.yml
    │   ├── .env             # symlink → ../../global.env
    │   └── data/config/
    ├── jellyfin/            # 媒体服务器
    │   ├── compose.yml
    │   ├── .env
    │   └── data/{cache,config}/
    ├── lucky/               # DDNS / 反向代理 / SSL 证书
    │   ├── compose.yml
    │   ├── .env
    │   └── data/conf/
    ├── metacubex/           # 代理（Mihomo / Clash Meta）
    │   ├── compose.yml
    │   ├── .env
    │   └── data/mihomo/
    ├── metatube/            # 元数据刮削
    │   ├── compose.yml
    │   ├── .env
    │   └── data/config/
    ├── mosquitto/           # MQTT 消息代理
    │   ├── compose.yml
    │   ├── .env
    │   └── data/{config,data}/
    ├── openclaw/            # 聊天机器人框架
    │   ├── compose.yml
    │   ├── .env
    │   └── data/{auth,config}/
    ├── vaultwarden/         # 密码管理器（Bitwarden 兼容）
    │   ├── compose.yml
    │   ├── .env
    │   └── data/
    └── xunlei/              # 迅雷下载
        ├── compose.yml
        ├── .env
        └── data/{cache,data}/
```

## 快速开始

```bash
# 1. 创建目录并克隆（放在 /srv 下）
sudo install -d -o $USER -g $(id -gn) /srv
git clone https://github.com/314432150/docker-stacks.git /srv/docker-stacks
cd /srv/docker-stacks

# 2. 修改环境变量（按需调整 NAS_IP、存储路径等）
vim global.env

# 3. 安装为全局命令
bash scripts/dsctl --install

# 4. 部署所有应用（默认全选，支持交互式勾选）
sudo dsctl deploy
```
> 部署会自动创建/修复 .env → global.env 符号链接，然后逐应用 docker compose up -d。
>
> 恢复旧 NAS 数据：先导入备份文件，再通过 `sudo dsctl restore` 还原。

## 入口说明

| 方式 | 命令 | 适用场景 |
|------|------|----------|
| 命令行 | `cd stacks/jellyfin && sudo docker compose up -d` | 启动/管理单个服务 |
| 全局命令 | `sudo dsctl` | 主菜单（备份 / 还原 / 部署） |
| 全局命令 | `sudo dsctl deploy` | 快速部署全部/选中应用 |

> 修改根 `global.env` 后所有 stack 自动生效（符号链接）。



## 备份、还原与部署

零依赖，纯 Bash 实现。

### 全局命令（推荐）

安装后可在任意目录使用：

```bash
# 主菜单（备份 / 还原 / 部署 / 安装 / 卸载）
sudo dsctl

# 直接进入备份模式
sudo dsctl backup

# 非交互式一键备份全部推荐项
sudo dsctl backup -y

# 直接进入还原模式
sudo dsctl restore

# 直接进入部署模式（默认全选，可交互式勾选）
sudo dsctl deploy

# 一键部署全部应用
sudo dsctl deploy -y
```



**功能亮点：**
- 自动发现 `stacks/` 下所有应用，无需手动维护应用列表
- 解析 `compose.yml` 卷挂载，智能区分 配置数据 / 缓存 / 外部挂载
- 每个应用预选推荐备份项（跳过缓存目录），可自由勾选
- 还原时列出所有历史备份，自由选择要还原的应用
- 备份格式：`{时间戳}_{描述}_{应用列表}.tar.gz`，如 `20260710-045320_test_homeassistant_jellyfin_...tar.gz`
- 支持远程 WebDAV 备份/还原（坚果云、Nextcloud、群晖等）


## 远程 WebDAV 备份

dsctl 支持将备份文件上传到远程 WebDAV 服务器，以及从远程 WebDAV 下载还原。

### 配置

在 `global.env` 中设置以下变量：

```bash
WEBDAV_URL=https://your-webdav-server.com/path/to/backups
WEBDAV_USER=your_username
WEBDAV_PASS=your_password
```

### 坚果云 配置示例

1. 登录 [坚果云](https://www.jianguoyun.com/)
2. 进入 **账户信息 → 安全选项 → 第三方应用管理**
3. 添加一个应用，生成专用密码
4. 在坚果云中创建一个目录（如 `/backups`），用于存放备份文件
5. 在 `global.env` 中配置：

```bash
WEBDAV_URL=https://dav.jianguoyun.com/dav/backups
WEBDAV_USER=你的坚果云邮箱
WEBDAV_PASS=第三方应用专用密码
```

> ⚠️ **安全提示**：`WEBDAV_PASS` 是敏感信息。如果仓库需要公开，建议将 `global.env` 加入 `.gitignore`，或用单独的不受版本控制的凭据文件。

### 使用

```bash
# 备份：打包完成后会询问是否上传到 WebDAV
sudo dsctl backup

# 还原：可选择「本地备份」或「远程 WebDAV 备份」
sudo dsctl restore
```

- 备份时，本地 `.tar.gz` 始终保留，WebDAV 上传为额外副本
- 还原时，从 WebDAV 下载的文件会缓存到本地 `backups/` 目录

