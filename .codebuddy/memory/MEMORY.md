# 项目记忆

## 环境信息

- 服务器 IP: `192.168.1.146`
- 项目路径: `/opt/docker-stacks/`
- 备份目录: `/opt/docker-stacks/backups/`
- 全局命令: `ds-backup`（交互式备份+还原），已废弃 `ds-restore`

## Docker Compose 约定

- `global.env` 包含 `PROXY_HOST` 和 `PROXY_BRIDGE` 两个代理变量，按网络模式选用
- Jellyfin 用 `network_mode: host`，访问其他 bridge 容器用 `localhost:<映射端口>`，不能用容器名
- HomeAssistant 不使用 `user:` 指令——HA 的 s6 初始化阶段需要 root，容器内部自行管理权限

## Home Assistant

- 长期访问令牌入口: 用户头像 → 安全 → 长期访问令牌
- HA 重启后旧 session token 全部失效，客户端需重新登录或更新长期令牌
- HASS.Agent 配置时 Server URI 用 IP（`http://192.168.1.146:8123`），不用 `homeassistant.local`

## 米家 & 美的集成

- 小米: HACS 安装 `ha_xiaomi_home`（XiaoMi 官方），OAuth 用 `http://192.168.1.146:8123`
- 美的: HACS 安装 Midea AC LAN，自动发现可能失败，手动 IP
  - 净化器 KJ400G-L1 Lite: `192.168.1.150`（提示音控制无效）
  - 空调: `192.168.1.195`（MAC OUI 34:5b:bb = GD Midea）

## 代理注意

- Clash Party bypass 不支持 `.local` 通配，需单独加具体域名
- `global.env` NO_PROXY 用 `.local` 通配正常（Linux 标准）

## 备份/还原

- 只保留一个入口: `ds-backup`（含交互式 TUI 备份和还原）
- 推荐用 `sudo ds-backup ...` 执行，一次密码全流程 root 运行，tar 完整保留 UID/GID
- `--install` 安装到 `/usr/local/bin/`，sudo 和普通用户都能找到
- 还原流程: 自动停止目标容器 → 解压 → 自动启动容器
- 选择交互: 方向键/jk 移动，空格选中/取消，a 全选/取消全选
- 权限问题: HA `.storage/` 和 mosquitto `.db` 属主非当前用户 → `sudo ds-backup` 即可解决（tar 以 root 运行）
