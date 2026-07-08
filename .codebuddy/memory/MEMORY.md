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

## 备份/还原

- 只保留一个入口: `ds-backup`（含交互式 TUI 备份和还原）
- 还原流程: 自动停止目标容器 → 解压 → 自动启动容器
- 选择交互: 方向键/jk 移动，空格选中/取消，a 全选/取消全选
