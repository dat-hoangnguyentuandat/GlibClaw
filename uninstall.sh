#!/system/bin/sh
# ============================================================
# OpenClaw — uninstall.sh
# Runs when user removes module from Magisk
# ============================================================
INSTALL_DIR="/data/adb/openclaw"
OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"

# Stop daemon gracefully
if [ -x "$OPENCLAW_BIN" ]; then
  "$OPENCLAW_BIN" stop 2>/dev/null || true
fi

# Remove runtime (keep /data/adb/openclaw/home for user data)
rm -rf "$INSTALL_DIR/glibc-node"
rm -rf "$INSTALL_DIR/bin"
rm -rf "$INSTALL_DIR/lib"
rm -rf "$INSTALL_DIR/tmp"
rm -f  "$INSTALL_DIR/.install_state"

echo "OpenClaw uninstalled. User data preserved at $INSTALL_DIR/home"
