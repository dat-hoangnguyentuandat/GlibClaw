#!/system/bin/sh
# ============================================================
# GlibClaw — uninstall.sh
# Runs when user removes module from Magisk
# Preserves /data/adb/openclaw/home (user data)
# ============================================================
INSTALL_DIR="/data/adb/openclaw"
OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"

# Stop daemon gracefully
if [ -x "$OPENCLAW_BIN" ]; then
  "$OPENCLAW_BIN" stop 2>/dev/null || true
fi

# Remove glibc libs
rm -rf "$INSTALL_DIR/glibc"

# Remove Node.js runtime (downloaded, can be re-downloaded on reinstall)
rm -rf "$INSTALL_DIR/node"

# Remove OpenClaw runtime (will be re-installed via npm)
rm -rf "$INSTALL_DIR/bin"
rm -rf "$INSTALL_DIR/lib"
rm -rf "$INSTALL_DIR/tmp"
rm -f  "$INSTALL_DIR/.install_state"
rm -f  "$INSTALL_DIR/doh-proxy.mjs"
rm -f  "$INSTALL_DIR/doh-proxy.pid"
rm -f  "$INSTALL_DIR/openclaw.pid"

echo "OpenClaw uninstalled. User data preserved at $INSTALL_DIR/home"
