#!/system/bin/sh
# ============================================================
# OpenClaw — action.sh
# Runs when user taps "Action" in Magisk/KSU app
# Open dashboard directly in browser with local token
# ============================================================

INSTALL_DIR="/data/adb/openclaw"
CONF="$INSTALL_DIR/home/.openclaw/openclaw.json"
PORT="18789"
BASE_URL="http://127.0.0.1:${PORT}/"

ui_print() { echo "$1"; }

ui_print "=============================="
ui_print " OpenClaw Dashboard Launcher"
ui_print "=============================="

if [ ! -f "$CONF" ]; then
  ui_print "Config not found: $CONF"
  exit 1
fi

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
