#!/usr/bin/env bash
# 一次性 root 配置：把信令服务从 /home/admin（root + PM2）迁到 deploy 用户的 user systemd。
# 用法（root 终端只跑这一条）：bash /tmp/setup_signal_service.sh
set -euo pipefail

REPO=/home/deploy/build/sunset-summit-duel
DEPLOY_HOME=/home/deploy
UNIT_DIR="$DEPLOY_HOME/.config/systemd/user"
DATA_DIR="$DEPLOY_HOME/.duel-signal"
OLD_DATA=/home/admin/duel-signal
OLD_SCRIPT=/home/admin/duel-signal/server.js
NODE_MODULES="$DEPLOY_HOME/build/node_modules"
NODE_LOCAL="$DEPLOY_HOME/build/tools/node"
PM2_HOME_DIR=/home/admin/.pm2

as_deploy() { sudo -u deploy XDG_RUNTIME_DIR="/run/user/$(id -u deploy)" "$@"; }

[ "$(id -u)" -eq 0 ] || { echo "请用 root 执行"; exit 1; }

echo "== 1/8 检查仓库版本 =="
grep -q 'DUEL_DATA_DIR' "$REPO/server/lan_signal_server.js" || { echo "服务器仓库还是旧版，先等 CI 更新"; exit 1; }
echo ok

echo "== 2/8 准备 deploy 可执行的 node =="
SRC_NODE=$(readlink -f "/proc/$(pgrep -f 'duel-signal/server.js' | head -1)/exe" 2>/dev/null || true)
[ -x "${SRC_NODE:-}" ] || SRC_NODE=$(command -v node || true)
[ -x "${SRC_NODE:-}" ] || { echo "找不到 node"; exit 1; }
echo "源 node: $SRC_NODE"
install -d -m 755 -o deploy -g deploy "$DEPLOY_HOME/build/tools"
if [ ! -x "$NODE_LOCAL" ] || ! sudo -u deploy "$NODE_LOCAL" -v >/dev/null 2>&1; then
  cp -f "$SRC_NODE" "$NODE_LOCAL"; chown deploy:deploy "$NODE_LOCAL"; chmod 755 "$NODE_LOCAL"
fi
sudo -u deploy "$NODE_LOCAL" -v >/dev/null && NODE_BIN="$NODE_LOCAL" && echo "deploy node: $NODE_BIN"

echo "== 3/8 准备 ws 依赖 =="
WS_ENTRY=$("$SRC_NODE" -e "console.log(require.resolve('ws'))" 2>/dev/null || true)
[ -n "${WS_ENTRY:-}" ] || WS_ENTRY=$("$SRC_NODE" -e "console.log(require.resolve('ws',{paths:['/home/admin/mirugumi.space/node_modules']}))" 2>/dev/null || true)
if [ -n "${WS_ENTRY:-}" ]; then
  WS_DIR=$(echo "$WS_ENTRY" | sed 's#/ws/.*##')
  install -d -m 755 -o deploy -g deploy "$NODE_MODULES"
  [ -d "$NODE_MODULES/ws" ] || { cp -r "$WS_DIR/ws" "$NODE_MODULES/"; chown -R deploy:deploy "$NODE_MODULES"; }
  echo "ws ok"
else
  echo "警告：找不到 ws"
fi

echo "== 4/8 目录与积分数据 =="
install -d -m 700 -o deploy -g deploy "$DATA_DIR"
install -d -m 755 -o deploy -g deploy "$UNIT_DIR"
if [ -f "$OLD_DATA/accounts.json" ] && [ ! -f "$DATA_DIR/accounts.json" ]; then
  cp "$OLD_DATA/accounts.json" "$DATA_DIR/accounts.json"; chown deploy:deploy "$DATA_DIR/accounts.json"; chmod 600 "$DATA_DIR/accounts.json"
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
chown deploy:deploy "$UNIT_DIR/duel-signal.service"; chmod 644 "$UNIT_DIR/duel-signal.service"
echo "unit 已写入"

echo "== 6/8 处理 PM2 里的旧进程 =="
DAEMON_PID=$(pgrep -f 'PM2.*God Daemon' | head -1 || true)
PM2_OK=0
if [ -n "${DAEMON_PID:-}" ]; then
  DAEMON_NODE=$(readlink -f "/proc/$DAEMON_PID/exe" 2>/dev/null || true)
  echo "PM2 daemon pid=$DAEMON_PID node=${DAEMON_NODE:-未知}"
  # 用和 daemon 同目录的 pm2 CLI，版本不匹配会卡死
  CLI=""
  [ -n "${DAEMON_NODE:-}" ] && [ -x "$(dirname "$DAEMON_NODE")/pm2" ] && CLI="$(dirname "$DAEMON_NODE")/pm2"
  [ -z "$CLI" ] && CLI=$(command -v pm2 || true)
  if [ -n "${CLI:-}" ] && [ -x "$CLI" ]; then
    echo "用 $CLI 读取 PM2 列表"
    export PM2_HOME="$PM2_HOME_DIR"
    if timeout 12 "$CLI" jlist > /tmp/pm2-list.json 2>/dev/null; then
      IDS=$(NODE="$SRC_NODE" timeout 10 "$NODE_BIN" -e '
        try { const a=require("/tmp/pm2-list.json");
          const h=a.filter(x=>JSON.stringify(x).includes("duel-signal"));
          console.log(h.map(x=>x.pm_id).join(" ")); } catch(e){}' 2>/dev/null || true)
      if [ -n "${IDS:-}" ]; then
        echo "PM2 中的应用 id: $IDS"
        for i in $IDS; do timeout 12 "$CLI" delete "$i" >/dev/null 2>&1 && echo "pm2 delete $i ok"; done
        timeout 12 "$CLI" save >/dev/null 2>&1 || true
        PM2_OK=1
      else
        echo "PM2 列表可读，但没有匹配到 duel-signal"
      fi
    else
      echo "pm2 CLI 超时，走强制方案"
    fi
  fi
fi

if [ "$PM2_OK" != "1" ]; then
  echo "强制方案：把旧脚本改名，让 PM2 重试时必然失败，不会再抢 8899"
  [ -f "$OLD_SCRIPT" ] && mv -f "$OLD_SCRIPT" "$OLD_SCRIPT.disabled"
fi
pkill -9 -f 'duel-signal/server.js' 2>/dev/null || true
pkill -9 -f 'duel-signal/server.js.disabled' 2>/dev/null || true

echo "== 7/8 等端口释放 =="
FREE=0
for i in $(seq 1 20); do
  if ! ss -lnt 2>/dev/null | grep -q ':8899' && ! pgrep -f 'duel-signal/server.js' >/dev/null 2>&1; then
    sleep 2
    if ! ss -lnt 2>/dev/null | grep -q ':8899' && ! pgrep -f 'duel-signal/server.js' >/dev/null 2>&1; then FREE=1; break; fi
  fi
  sleep 1
done
if [ "$FREE" != "1" ]; then
  echo "8899 仍被占用："; ss -lntp 2>/dev/null | grep ':8899' || true
  pgrep -af 'duel-signal' || true
  echo "（如果旧脚本已改名还占着，说明是残留进程，手动 kill -9 上面那个 pid 再跑一次本脚本）"
  exit 1
fi
echo "端口已释放"

as_deploy systemctl --user stop duel-signal 2>/dev/null || true
loginctl enable-linger deploy
as_deploy systemctl --user daemon-reload
as_deploy systemctl --user enable --now duel-signal

echo "== 8/8 检查 =="
sleep 3
if ss -lnt 2>/dev/null | grep -q ':8899'; then
  ss -lntp 2>/dev/null | grep ':8899'
  as_deploy systemctl --user is-active duel-signal
  echo
  echo "完成：deploy 可直接 systemctl --user restart duel-signal，CI 也会自动重启。"
else
  echo "8899 没有起来，日志："
  as_deploy journalctl --user -u duel-signal -n 30 --no-pager
  exit 1
fi
