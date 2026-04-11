#!/system/bin/sh

# ============================================================
# OpenClaw — service.sh
# Runs on every boot by Magisk/KSU (root context)
# ============================================================

INSTALL_DIR="/data/adb/openclaw"
LOG="$INSTALL_DIR/openclaw.log"
OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"
STATE_FILE="$INSTALL_DIR/.install_state"
GLIBC_NODE="$INSTALL_DIR/glibc-node/bin/node"
DOH_PROXY="$INSTALL_DIR/doh-proxy.mjs"
DOH_PORT=5300

STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "not_installed")

if [ "$STATE" != "done" ]; then
  echo "[$(date '+%H:%M:%S')] Install not complete (state=$STATE)" >> "$LOG"
  exit 0
fi

if [ ! -x "$OPENCLAW_BIN" ]; then
  echo "[$(date '+%H:%M:%S')] openclaw binary not found" >> "$LOG"
  exit 1
fi

if ! ip route show | grep -q "^default"; then
  for iface in rmnet_data1 rmnet_data0 rmnet_data3 wlan0 eth0; do
    if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
      ip route add default dev "$iface" 2>/dev/null && \
        echo "[$(date '+%H:%M:%S')] Default route added via $iface" >> "$LOG" && break
    fi
  done
fi

pkill -f doh-proxy.mjs 2>/dev/null || true
sleep 0.3

echo "[$(date '+%H:%M:%S')] Starting DoH proxy on port $DOH_PORT..." >> "$LOG"

DOH_PORT=$DOH_PORT "$GLIBC_NODE" "$DOH_PROXY" >> "$LOG" 2>&1 &
DOH_PID=$!
echo $DOH_PID > "$INSTALL_DIR/doh-proxy.pid"

# Chờ proxy bind xong
sleep 2

# Verify proxy đang chạy
if ! kill -0 $DOH_PID 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] WARNING: DoH proxy exited early, DNS may fail" >> "$LOG"
else
  echo "[$(date '+%H:%M:%S')] DoH proxy running PID=$DOH_PID" >> "$LOG"
fi

iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port $DOH_PORT
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port $DOH_PORT
echo "[$(date '+%H:%M:%S')] iptables DNS redirect 53→$DOH_PORT applied" >> "$LOG"

echo "[$(date '+%H:%M:%S')] Starting openclaw gateway..." >> "$LOG"

unset NODE_OPTIONS
export NODE_NO_WARNINGS=1

"$OPENCLAW_BIN" gateway run \
  --allow-unconfigured \
  --bind loopback \
  >> "$LOG" 2>&1 &

echo "[$(date '+%H:%M:%S')] Gateway PID: $!" >> "$LOG"
echo $! > "$INSTALL_DIR/openclaw.pid"

exit 0
