#!/system/bin/sh
# ============================================================
# GlibClaw — action.sh
# Runs when user taps "Action" in Magisk/KSU app
# 1) Start OpenClaw gateway if not running
# 2) Open dashboard in browser with local token
# ============================================================

INSTALL_DIR="/data/adb/openclaw"
CONF="$INSTALL_DIR/home/.openclaw/openclaw.json"
PID_FILE="$INSTALL_DIR/openclaw.pid"
LOG="$INSTALL_DIR/openclaw.log"
OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"
PORT="18789"
BASE_URL="http://127.0.0.1:${PORT}/"

ui_print() { echo "$1"; }

ui_print "=============================="
ui_print "  GlibClaw Dashboard Launcher"
ui_print "=============================="

if [ ! -f "$CONF" ]; then
  ui_print "Config not found: $CONF"
  exit 1
fi

# ── Check if gateway is running ──
GATEWAY_RUNNING=false
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    GATEWAY_RUNNING=true
    ui_print "Gateway is already running (PID $PID)"
  fi
fi

if [ "$GATEWAY_RUNNING" = false ]; then
  if [ ! -x "$OPENCLAW_BIN" ]; then
    ui_print "OpenClaw binary not found: $OPENCLAW_BIN"
    exit 1
  fi

  ui_print "Starting OpenClaw gateway..."
  "$OPENCLAW_BIN" gateway run \
    --allow-unconfigured \
    --bind loopback \
    >> "$LOG" 2>&1 &
  NEW_PID=$!
  echo $NEW_PID > "$PID_FILE"
  sleep 2

  if kill -0 $NEW_PID 2>/dev/null; then
    ui_print "Gateway started (PID $NEW_PID)"
  else
    ui_print "WARNING: Gateway might not have started — check logs"
    ui_print "Log: $LOG"
  fi
fi

# ── Open dashboard ──
TOKEN=$(grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONF" | head -1 | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')

if [ -z "$TOKEN" ]; then
  ui_print "Gateway token not found in config"
  exit 1
fi

URL="${BASE_URL}#token=${TOKEN}"

ui_print "Opening dashboard..."
ui_print "$URL"

am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1

ui_print "Done"
exit 0
