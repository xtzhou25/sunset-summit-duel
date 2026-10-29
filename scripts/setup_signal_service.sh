#!/usr/bin/env bash
# 一次性 root 配置：把信令服务从 /home/admin（root + PM2）迁到 deploy 用户的 user systemd。
# 迁移完成后，deploy 用户无需 root 即可重启服务，GitHub Actions 也能自动重启。
#
# 用法（必须 root）：
#   bash /home/deploy/build/sunset-summit-duel/scripts/setup_signal_service.sh
#
# 幂等：重复执行不会重复添加，也不会覆盖已有积分数据。
set -euo pipefail

REPO=/home/deploy/build/sunset-summit-duel
DEPLOY_HOME=/home/deploy
UNIT_DIR="$DEPLOY_HOME/.config/systemd/user"
DATA_DIR="$DEPLOY_HOME/.duel-signal"
OLD_DATA=/home/admin/duel-signal
NODE_MODULES="$DEPLOY_HOME/build/node_modules"
NODE_LOCAL="$DEPLOY_HOME/build/tools/node"
PM2_HOME_DIR=/home/admin/.pm2

as_deploy() {
  sudo -u deploy XDG_RUNTIME_DIR="/run/user/$(id -u deploy)" "$@"
}

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 执行：sudo bash $0"
  exit 1
fi

echo "== 1/8 检查仓库版本 =="
if ! grep -q 'DUEL_DATA_DIR' "$REPO/server/lan_signal_server.js" 2>/dev/null; then
  echo "仓库里的信令服务还是旧版本（没有 DUEL_DATA_DIR）。"
  echo "请先 push，并等 CI 或手动把 $REPO 更新到 origin/main 后再跑本脚本。"
  exit 1
fi

echo "== 2/8 准备 deploy 可执行的 node =="
SRC_NODE=$(readlink -f "/proc/$(pgrep -f '/home/admin/duel-signal/server.js' | head -1)/exe" 2>/dev/null || true)
[ -x "${SRC_NODE:-}" ] || SRC_NODE=$(command -v node || true)
[ -x "${SRC_NODE:-}" ] || { echo "找不到 node"; exit 1; }
echo "源 node: $SRC_NODE"
install -d -m 755 -o deploy -g deploy "$DEPLOY_HOME/build/tools"
if [ ! -x "$NODE_LOCAL" ] || ! sudo -u deploy "$NODE_LOCAL" -v >/dev/null 2>&1; then
  # /root 下的 node 对 deploy 不可见，复制一份出来
  cp -f "$SRC_NODE" "$NODE_LOCAL"
  chown deploy:deploy "$NODE_LOCAL"
  chmod 755 "$NODE_LOCAL"
fi
sudo -u deploy "$NODE_LOCAL" -v
NODE_BIN="$NODE_LOCAL"

echo "== 3/8 准备 ws 依赖 =="
WS_ENTRY=$("$SRC_NODE" -e "console.log(require.resolve('ws'))" 2>/dev/null || true)
[ -n "${WS_ENTRY:-}" ] || WS_ENTRY=$("$SRC_NODE" -e "console.log(require.resolve('ws',{paths:['/home/admin/mirugumi.space/node_modules']}))" 2>/dev/null || true)
if [ -n "${WS_ENTRY:-}" ]; then
  WS_DIR=$(echo "$WS_ENTRY" | sed 's#/ws/.*##')
  install -d -m 755 -o deploy -g deploy "$NODE_MODULES"
  if [ ! -d "$NODE_MODULES/ws" ]; then
    cp -r "$WS_DIR/ws" "$NODE_MODULES/"
    chown -R deploy:deploy "$NODE_MODULES"
  fi
  echo "ws: $NODE_MODULES/ws"
else
  echo "警告：找不到 ws 模块，服务可能起不来"
fi

echo "== 4/8 准备目录与积分数据 =="
install -d -m 700 -o deploy -g deploy "$DATA_DIR"
install -d -m 755 -o deploy -g deploy "$UNIT_DIR"
if [ -f "$OLD_DATA/accounts.json" ] && [ ! -f "$DATA_DIR/accounts.json" ]; then
  cp "$OLD_DATA/accounts.json" "$DATA_DIR/accounts.json"
  chown deploy:deploy "$DATA_DIR/accounts.json"
  chmod 600 "$DATA_DIR/accounts.json"
  echo "已迁移 accounts.json"
else
  echo "无新数据需要迁移"
fi

echo "== 5/8 生成 user unit =="
cat > "$UNIT_DIR/duel-signal.service" <<EOF
[Unit]
Description=sunset-summit-duel LAN signal server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$REPO
Environment=SIGNAL_HOST=172.17.0.1
Environment=SIGNAL_PORT=8899
Environment=SIGNAL_GRACE_MS=60000
Environment=DUEL_DATA_DIR=$DATA_DIR
Environment=NODE_PATH=$NODE_MODULES
ExecStart=$NODE_BIN $REPO/server/lan_signal_server.js
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
chown deploy:deploy "$UNIT_DIR/duel-signal.service"
chmod 644 "$UNIT_DIR/duel-signal.service"
grep -E '^(ExecStart|Environment)=' "$UNIT_DIR/duel-signal.service"

echo "== 6/8 从 PM2 摘掉旧进程 =="
if command -v pm2 >/dev/null 2>&1; then
  PM2_HOME="$PM2_HOME_DIR" pm2 jlist > /tmp/pm2-list.json 2>/dev/null || true
  OLD_NAME=$("$SRC_NODE" -e "
    try { const a=require('/tmp/pm2-list.json');
      const p=a.find(x=>JSON.stringify(x.pm2_env||{}).includes('duel-signal')||JSON.stringify(x).includes('duel-signal'));
      if (p) console.log(p.name); } catch(e) {}" 2>/dev/null || true)
  if [ -n "${OLD_NAME:-}" ]; then
    echo "pm2 delete: $OLD_NAME"
    PM2_HOME="$PM2_HOME_DIR" pm2 delete "$OLD_NAME" >/dev/null
    PM2_HOME="$PM2_HOME_DIR" pm2 save >/dev/null 2>&1 || true
  else
    echo "PM2 里没找到 duel-signal（可能不是 PM2 管理）"
  fi
fi
pkill -f "/home/admin/duel-signal/server.js" 2>/dev/null || true

echo "== 7/8 等端口释放并启动 =="
for i in $(seq 1 15); do
  ss -lnt 2>/dev/null | grep -q ':8899' || break
  sleep 1
done
if ss -lnt 2>/dev/null | grep -q ':8899'; then
  echo "8899 仍被占用，先不启动，占用者："
  ss -lntp 2>/dev/null | grep ':8899'
  exit 1
fi
loginctl enable-linger deploy
as_deploy systemctl --user daemon-reload
as_deploy systemctl --user enable --now duel-signal

echo "== 8/8 检查 =="
sleep 3
if ss -lnt 2>/dev/null | grep -q ':8899'; then
  ss -lntp 2>/dev/null | grep ':8899'
  as_deploy systemctl --user --no-pager status duel-signal | head -8
  echo
  echo "完成：之后 deploy 可直接 systemctl --user restart duel-signal，CI 也能自动重启。"
else
  echo "8899 没有起来，最近日志："
  as_deploy journalctl --user -u duel-signal -n 30 --no-pager
  exit 1
fi
