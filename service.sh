#!/system/bin/sh
# ============================================================
# OpenClaw — service.sh
# Runs on every boot by Magisk/KSU (root context)
# ============================================================

INSTALL_DIR="/data/adb/openclaw"
LOG="$INSTALL_DIR/openclaw.log"
OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"
STATE_FILE="$INSTALL_DIR/.install_state"

STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "not_installed")

if [ "$STATE" != "done" ]; then
  echo "[$(date '+%H:%M:%S')] Install not complete (state=$STATE)" >> "$LOG"
  exit 0
fi

if [ ! -x "$OPENCLAW_BIN" ]; then
  echo "[$(date '+%H:%M:%S')] openclaw binary not found at $OPENCLAW_BIN" >> "$LOG"
  exit 1
fi

echo "[$(date '+%H:%M:%S')] Starting openclaw gateway..." >> "$LOG"

# Unset NODE_OPTIONS để tránh flag không tương thích truyền vào ld-linux
unset NODE_OPTIONS
export NODE_NO_WARNINGS=1

# Chạy gateway foreground trong background process
# gateway run = foreground mode, & = detach
"$OPENCLAW_BIN" gateway run \
  --allow-unconfigured \
  --bind loopback \
  >> "$LOG" 2>&1 &

echo "[$(date '+%H:%M:%S')] Gateway PID: $!" >> "$LOG"
echo $! > "$INSTALL_DIR/openclaw.pid"

exit 0
