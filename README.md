# Docker Stacks

NAS 上运行的 Docker Compose 服务编排仓库，部署在 `/srv/docker-stacks` 下。

## 目录结构

```text
docker-stacks/
├── global.env               # 全局环境变量，所有 stack 的 .env 通过符号链接指向此文件
├── scripts/
│   └── backup.sh            # 备份/恢复交互式脚本，可注册为全局命令 ds-backup
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
# 1. 创建目录并克隆（放在 /srv 下，无需 sudo clone）
sudo install -d -o $USER -g $(id -gn) /srv
git clone https://github.com/314432150/docker-stacks.git /srv/docker-stacks
cd /srv/docker-stacks

# 2. 修改环境变量（按需调整 NAS_IP、存储路径等）
vim global.env

# 3. 安装备份脚本为全局命令
bash scripts/backup.sh --install

# 4. 通过还原命令导入备份数据并启动所有服务
sudo ds-backup restore
```
> 还原会自动停止/启动容器，无需手动管理。

## 入口说明

| 方式 | 命令 | 适用场景 |
|------|------|----------|
| 命令行 | `cd stacks/jellyfin && sudo docker compose up -d` | 启动/管理单个服务 |
| 全局命令 | `sudo ds-backup` | 备份 / 还原全部应用 |

> 修改根 `global.env` 后所有 stack 自动生效（符号链接）。



## 备份与恢复

零依赖，纯 Bash 实现。

### 全局命令（推荐）

安装后可在任意目录使用：

```bash
# 主菜单（备份 / 还原 / 安装 / 卸载）
sudo ds-backup

# 直接进入备份模式
sudo ds-backup backup

# 非交互式一键备份全部推荐项
sudo ds-backup backup -y

# 直接进入还原模式
sudo ds-backup restore

```



**功能亮点：**
- 自动发现 `stacks/` 下所有应用，无需手动维护应用列表
- 解析 `compose.yml` 卷挂载，智能区分 配置数据 / 缓存 / 外部挂载
- 每个应用预选推荐备份项（跳过缓存目录），可自由勾选
- 还原时列出所有历史备份，自由选择要还原的应用
- 备份格式：`{时间戳}_{描述}_{应用列表}.tar.gz`，如 `20260710-045320_test_homeassistant_jellyfin_...tar.gz`

