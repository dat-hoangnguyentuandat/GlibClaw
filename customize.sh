#!/system/bin/sh

INSTALL_DIR="/data/adb/openclaw"
LOG="$INSTALL_DIR/install.log"
BUNDLE="$MODPATH/glibc-node-bundle.tar.xz"

abort() { ui_print ""; ui_print "ERROR: $1"; ui_print "Log: $LOG"; exit 1; }
log()   { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

ui_print ""
ui_print "Network connection is required during installation."
ui_print ""

mkdir -p "$INSTALL_DIR"
log "===== Install start ====="

ARCH=$(uname -m)
[ "$ARCH" = "aarch64" ] || abort "Unsupported architecture: $ARCH"
[ -f "$BUNDLE" ] || abort "Missing glibc-node-bundle.tar.xz in module"
log "arch: $ARCH OK"
log "bundle found"

mkdir -p "$INSTALL_DIR/glibc-node"
tar -xJf "$BUNDLE" -C "$INSTALL_DIR" || abort "Bundle extraction failed"
chmod 755 "$INSTALL_DIR/glibc-node/bin/node"
chmod 755 "$INSTALL_DIR/glibc-node/bin/node.real"

NODE_BIN="$INSTALL_DIR/glibc-node/bin/node"
NODE_VER=$($NODE_BIN --version 2>&1)
[ $? -eq 0 ] || abort "Node failed to run: $NODE_VER"
log "node OK: $NODE_VER"

RETRY=0
while :; do
  if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    DNS1=$(/system/bin/getprop net.dns1 2>/dev/null)
    DNS2=$(/system/bin/getprop net.dns2 2>/dev/null)
    [ -n "$DNS1" ] && log "dns1=$DNS1"
    [ -n "$DNS2" ] && log "dns2=$DNS2"

    # 1) plain resolve reachability
    if ping -c 1 -W 3 registry.npmjs.org >/dev/null 2>&1; then
      # 2) https readiness to npm registry
      if "$NODE_BIN" "$INSTALL_DIR/glibc-node/lib/node_modules/npm/bin/npm-cli.js" view openclaw version --fetch-timeout=20000 >/dev/null 2>>"$LOG"; then
        break
      fi
    fi
  fi
  RETRY=$((RETRY+1))
  [ $RETRY -ge 45 ] && abort "Network/DNS is not ready for npm registry"
  sleep 2
done

export PATH="$INSTALL_DIR/glibc-node/bin:$PATH"
export HOME="$INSTALL_DIR/home"
export npm_config_prefix="$INSTALL_DIR"
export npm_config_cache="$INSTALL_DIR/tmp/npm-cache"
mkdir -p "$HOME" "$INSTALL_DIR/tmp/npm-cache"

rm -rf "$INSTALL_DIR/lib/node_modules/openclaw"
rm -f "$INSTALL_DIR/bin/openclaw"

ui_print "Installing OpenClaw..."
ATTEMPT=0
INSTALL_OK=0
while [ $ATTEMPT -lt 3 ]; do
  ATTEMPT=$((ATTEMPT+1))
  case "$ATTEMPT" in
    1) ui_print "Installing..." ;;
    2) ui_print "Retrying..." ;;
    3) ui_print "Final attempt, please wait..." ;;
  esac
  "$NODE_BIN" "$INSTALL_DIR/glibc-node/lib/node_modules/npm/bin/npm-cli.js" \
    install -g openclaw \
    --prefer-online \
    --fetch-timeout=180000 \
    --fetch-retry-mintimeout=30000 \
    --fetch-retry-maxtimeout=120000 \
    --fetch-retries=5 >/dev/null 2>>"$LOG"
  if [ -x "$INSTALL_DIR/bin/openclaw" ]; then
    INSTALL_OK=1
    break
  fi
  sleep 5
done
[ $INSTALL_OK -eq 1 ] || abort "npm install failed after 3 attempts"

OPENCLAW_MJS="$INSTALL_DIR/lib/node_modules/openclaw/openclaw.mjs"
[ -f "$OPENCLAW_MJS" ] || abort "openclaw.mjs not found after install"

rm -f "$INSTALL_DIR/bin/openclaw"
mkdir -p "$INSTALL_DIR/bin"
WRAPPER="$INSTALL_DIR/bin/openclaw"
printf '#!/system/bin/sh\n' > "$WRAPPER"
printf 'export PATH="%s/glibc-node/bin:$PATH"\n' "$INSTALL_DIR" >> "$WRAPPER"
printf 'export HOME="%s/home"\n' "$INSTALL_DIR" >> "$WRAPPER"
printf 'export npm_config_prefix="%s"\n' "$INSTALL_DIR" >> "$WRAPPER"
printf 'exec "%s/glibc-node/bin/node" "%s" "$@"\n' "$INSTALL_DIR" "$OPENCLAW_MJS" >> "$WRAPPER"
chmod 755 "$WRAPPER"

OPENCLAW_BIN="$INSTALL_DIR/bin/openclaw"
ENTRY_JS="$INSTALL_DIR/lib/node_modules/openclaw/dist/entry.js"
if [ -f "$ENTRY_JS" ]; then
  TMP_ENTRY="$ENTRY_JS.tmp"
  : > "$TMP_ENTRY"
  while IFS= read -r line; do
    case "$line" in
      *'const child = spawn(process$1.execPath, plan.argv, {'*)
        printf '%s\n' '        const child = spawn((process$1.execPath && process$1.execPath.indexOf("ld-linux-aarch64.so.1") === -1 ? process$1.execPath : "/data/adb/openclaw/glibc-node/bin/node"), plan.argv, {' >> "$TMP_ENTRY"
        ;;
      *)
        printf '%s\n' "$line" >> "$TMP_ENTRY"
        ;;
    esac
  done < "$ENTRY_JS"
  mv "$TMP_ENTRY" "$ENTRY_JS"
fi

OC_VER=$($OPENCLAW_BIN --version 2>&1 | head -1)
log "openclaw installed: $OC_VER"

CONF="$INSTALL_DIR/home/.openclaw/openclaw.json"
mkdir -p "$(dirname "$CONF")"
if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<'JSONEOF'
{
  "agents": {},
  "plugins": {},
  "gateway": {
    "bind": "loopback"
  }
}
JSONEOF
  chmod 600 "$CONF"
fi

chmod 755 "$OPENCLAW_BIN"
chmod 600 "$CONF"
set_perm "$MODPATH/system/bin/openclaw"         root root 0755
set_perm "$MODPATH/system/bin/openclaw.service" root root 0755

rm -rf "$INSTALL_DIR/tmp"
echo "done" > "$INSTALL_DIR/.install_state"
chmod 600 "$INSTALL_DIR/.install_state"
log "===== Install complete ====="

ui_print ""
ui_print "Installation completed."
ui_print "Reboot to activate OpenClaw."
ui_print ""
