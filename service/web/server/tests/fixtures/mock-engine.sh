#!/bin/sh
# ── 模拟引擎 ──
# 用法: mock-engine.sh <subcommand> [args...]
# 模拟 entry.sh 的 JSONL 输出，不操作真实文件系统
case "$1" in
  discover)
    echo '{"type":"apps","engine":{"privilege":"root"},"apps":[{"name":"test-app","description":"Test application","dirs":[{"path":"data/config","recommended":true,"exists":true},{"path":"data/downloads","recommended":false,"exists":false}]}]}'
    ;;
  backup)
    echo '{"type":"start","op":"backup","file":"test.tar.gz","apps":["test-app"]}'
    echo '{"type":"progress","step":"收集 test-app 目录","current":0,"total":3}'
    echo '{"type":"progress","step":"打包 2 个目录","current":1,"total":3}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","file":"test.tar.gz","size":"1M","path":"/tmp/test.tar.gz","success":1,"fail":0}'
    ;;
  restore)
    echo '{"type":"start","op":"restore","file":"test.tar.gz","apps":["test-app"]}'
    echo '{"type":"progress","step":"停止 test-app","current":1,"total":4}'
    echo '{"type":"progress","step":"安全备份","current":2,"total":4}'
    echo '{"type":"progress","step":"解压 test-app","current":3,"total":4}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","success":1,"fail":0}'
    ;;
  deploy)
    echo '{"type":"start","op":"deploy","apps":["test-app"]}'
    echo '{"type":"progress","step":"test-app .env 已就绪","current":1,"total":2}'
    echo '{"type":"progress","step":"部署 test-app","current":2,"total":2}'
    echo '{"type":"ok","app":"test-app"}'
    echo '{"type":"done","success":1,"fail":0}'
    ;;
  fail)
    echo '{"type":"error","msg":"模拟失败场景"}'
    exit 1
    ;;
  busy)
    echo '{"type":"busy","msg":"已有任务运行中: 12345 backup"}'
    exit 2
    ;;
  *)
    echo '{"type":"error","msg":"未知子命令: '"$1"'"}'
    exit 1
    ;;
esac
exit 0
