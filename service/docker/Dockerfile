# ==================== ds-web 管理界面 ====================
# 构建: docker build -f service/docker/Dockerfile -t ds-web:latest .
FROM node:22-slim

# 系统依赖
#  - wget:            healthcheck 探测
#  - curl:            WebDAV 上传/下载/列表
#  - ca-certificates: HTTPS 校验证书链
#  - python3:         shell 脚本读取 settings.json
#  - docker.io:       docker compose 命令（通过挂载的 docker.sock 操作宿主机）
RUN sed -i 's|deb.debian.org|mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    python3 \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/docker-stacks/service/web/server

# 依赖层缓存：先复制 package.json，npm install 只在依赖变更时重跑
COPY service/web/server/package*.json ./
RUN npm install --omit=dev

# 启动（源码通过 compose 卷挂载从宿主机同步，无需 COPY）
CMD ["node", "src/app.js"]
