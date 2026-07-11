# Docker Stacks

NAS 上运行的 Docker Compose 服务编排仓库，部署在 `/srv/docker-stacks` 下。

## 目录结构

```text
docker-stacks/
├── global.env               # 全局基础环境变量（NAS_IP、PUID/PGID、存储路径、代理），所有 stack 共享
├── service/                  # 基础服务层
│   ├── compose.yml           #   ds-web 编排
│   ├── web.env               #   Web 系统配置（认证 + WebDAV 备份），不进 Git
│   ├── web.env.example
│   ├── engine/               #   引擎脚本集
│   │   ├── cmd/              #     命令实现层（组装 lib → cmd_*，输出 JSONL）
│   │   │   ├── entry.sh      #       主入口 / 路由分发
│   │   │   ├── _lib.sh       #       emit / 锁 / 启动信息
│   │   │   ├── discover.sh   #       cmd_discover()
│   │   │   ├── backup.sh     #       cmd_backup()
│   │   │   ├── restore.sh    #       cmd_restore()
│   │   │   └── deploy.sh     #       cmd_deploy()
│   │   ├── lib/              #     纯函数库
│   │   │   ├── common.sh     #       终端颜色、工具函数
│   │   │   ├── discover.sh   #       应用发现、卷解析
│   │   │   ├── state.sh      #       备份选中状态管理
│   │   │   └── webdav.sh     #       WebDAV 上传/下载/列表
│   │   └── tests/
│   │       └── test_engine.sh  #   引擎集成测试
│   └── web/                  #   Web 前后端源码
│       ├── client/           #     Vue 前端
│       └── server/           #     Node 后端
├── backups/                 # 备份输出目录，不进 Git
│
└── stacks/                  # 9 个 Docker Compose 应用
    ├── homeassistant/       # 智能家居
    ├── jellyfin/            # 媒体服务器
    ├── lucky/               # DDNS / 反向代理 / SSL 证书
    ├── metacubex/           # 代理（Mihomo / Clash Meta）
    ├── metatube/            # 元数据刮削
    ├── mosquitto/           # MQTT 消息代理
    ├── openclaw/            # 聊天机器人框架
    ├── vaultwarden/         # 密码管理器（Bitwarden 兼容）
    └── xunlei/              # 迅雷下载
```

## 快速开始

```bash
# 1. 创建目录并克隆（放在 /srv 下）
sudo install -d -o $USER -g $(id -gn) /srv
git clone https://github.com/314432150/docker-stacks.git /srv/docker-stacks
cd /srv/docker-stacks

# 2. 修改环境变量（按需调整 NAS_IP、存储路径等）
cp global.env.example global.env
vim global.env

# 3. 配置 Web 系统（可选：Web 界面认证、远程 WebDAV 备份）
cp service/web.env.example service/web.env
vim service/web.env

# 4. 部署所有应用
sudo bash service/engine/cmd/entry.sh deploy homeassistant jellyfin lucky metacubex metatube mosquitto openclaw vaultwarden xunlei
```

## 引擎命令

引擎以 JSONL 事件流输出，可通过 `sudo` 以 root 权限运行以完整备份所有文件。

```bash
# 发现所有应用（JSON 列表）
sudo bash service/engine/cmd/entry.sh discover

# 备份指定应用
sudo bash service/engine/cmd/entry.sh backup homeassistant jellyfin

# 从备份还原
sudo bash service/engine/cmd/entry.sh restore backups/20260711-031727_homeassistant.tar.gz homeassistant

# 部署应用
sudo bash service/engine/cmd/entry.sh deploy homeassistant jellyfin
```

> 退出码：0=成功, 1=参数错误, 2=锁冲突, 3=前置条件不满足

## 权限模型

引擎代码不含任何 `sudo` 调用，权限完全由调用方 EUID 决定：

| 启动方式 | 能备份 root 文件 | 能还原文件所有者 |
|---------|:---------------:|:-------------:|
| `sudo bash entry.sh ...` | ✓ | ✓ |
| `bash entry.sh ...`（普通用户） | ✗ | ✗ |

建议始终以 `sudo` 启动引擎。

## 远程 WebDAV 备份

### 配置

在 `service/web.env` 中设置：

```bash
WEBDAV_URL=https://your-webdav-server.com/path
WEBDAV_USER=your_username
WEBDAV_PASS=your_password
```

### 坚果云 配置示例

1. 登录 [坚果云](https://www.jianguoyun.com/)
2. 进入 **账户信息 → 安全选项 → 第三方应用管理**，添加应用，生成专用密码
3. 在坚果云中创建目录，填入 `global.env` 即可

> ⚠️ **安全提示**：`global.env` 和 `web.env` 含敏感凭据，不进 Git（`.gitignore` 已忽略）。仓库提供 `.example` 模板。

### 使用

WebDAV 函数通过 `lib/webdav.sh` 暴露，可在脚本中调用：

```bash
source service/engine/lib/webdav.sh

# 上传
webdav_upload backups/file.tar.gz file.tar.gz

# 列出远程文件
webdav_list

# 下载
webdav_download file.tar.gz backups/file.tar.gz
```

## 运行测试

```bash
bash service/engine/tests/test_engine.sh
```
