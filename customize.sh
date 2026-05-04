#!/system/bin/sh

INSTALL_DIR="/data/adb/openclaw"
LOG="$INSTALL_DIR/install.log"
GLIBC_TAR="$MODPATH/glibc.tar.xz"
GLIBC_DIR="$INSTALL_DIR/glibc/lib"
NODE_DIR="$INSTALL_DIR/node"
DOH_PROXY_SRC="$MODPATH/openclaw/doh-proxy.mjs"
NODE_BASE_URL="${NODE_BASE_URL:-https://nodejs.org/dist}"
DOH_PORT=5300

abort() { ui_print ""; ui_print "ERROR: $1"; ui_print "Log: $LOG"; exit 1; }
log()   { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

ui_print ""
ui_print "Network connection is required during installation."

mkdir -p "$INSTALL_DIR"
log "===== Install start ====="

# ── Architecture check ─────────────────────────────
ARCH=$(uname -m)
[ "$ARCH" = "aarch64" ] || abort "Unsupported architecture: $ARCH"
log "arch: $ARCH OK"

# ── Detect upgrade ─────────────────────────────────
IS_UPGRADE=false
if [ -d "$NODE_DIR/bin" ] && [ -x "$NODE_DIR/bin/node" ]; then
  IS_UPGRADE=true
  ui_print "Upgrade mode — preserving existing Node.js"
  log "upgrade detected, node dir preserved"
fi

# ── Create runtime directories ─────────────────────
mkdir -p "$GLIBC_DIR" "$INSTALL_DIR/home" "$INSTALL_DIR/tmp"
log "directories created"

# ── Extract glibc libraries ────────────────────────
if [ "$IS_UPGRADE" = true ] && [ -f "$GLIBC_DIR/ld-linux-aarch64.so.1" ]; then
  rm -f "$GLIBC_TAR"
else
  [ -f "$GLIBC_TAR" ] || abort "Missing glibc.tar.xz in module"
  if tar -xJf "$GLIBC_TAR" -C "$GLIBC_DIR" 2>/dev/null; then
    : # ok
  elif command -v xz >/dev/null 2>&1; then
    xz -dc "$GLIBC_TAR" | tar -xf - -C "$GLIBC_DIR" || abort "Failed to extract glibc.tar.xz"
  elif command -v busybox >/dev/null 2>&1; then
    busybox xz -dc "$GLIBC_TAR" | busybox tar -xf - -C "$GLIBC_DIR" || abort "Failed to extract glibc.tar.xz"
  else
    abort "Cannot extract glibc.tar.xz: no xz support found"
  fi
  rm -f "$GLIBC_TAR"
  log "glibc libs extracted to $GLIBC_DIR"
fi

# ── Fix libc.so if linker script ───────────────────
if [ -f "$GLIBC_DIR/libc.so" ]; then
  MAGIC=$(dd if="$GLIBC_DIR/libc.so" bs=4 count=1 2>/dev/null \
          | od -A n -t x1 | tr -d ' \n')
  if [ "$MAGIC" != "7f454c46" ]; then
    rm "$GLIBC_DIR/libc.so"
    ln -s "$GLIBC_DIR/libc.so.6" "$GLIBC_DIR/libc.so"
    log "Fixed libc.so (linker script -> symlink)"
  fi
fi

# ── Install DoH proxy source ───────────────────────
[ -f "$DOH_PROXY_SRC" ] || abort "Missing openclaw/doh-proxy.mjs in module"
cp "$DOH_PROXY_SRC" "$INSTALL_DIR/doh-proxy.mjs"
chmod 644 "$INSTALL_DIR/doh-proxy.mjs"
log "doh-proxy.mjs installed"

# ── Add default route if missing ───────────────────
if ! ip route show | grep -q "^default"; then
  for iface in rmnet_data1 rmnet_data0 rmnet_data3 wlan0 eth0; do
    if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
      ip route add default dev "$iface" 2>/dev/null && \
        log "Default route added via $iface" && break
    fi
  done
fi

# ── Wait for basic network (native DNS) ────────────
ui_print "Waiting for network..."
RETRY=0
while :; do
  if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    break
  fi
  RETRY=$((RETRY+1))
  [ $RETRY -ge 45 ] && abort "Network not ready after 90 seconds"
  sleep 2
done
log "network ready (native DNS, ${RETRY}s wait)"

# ── Detect Node.js version ─────────────────────────
ui_print "Detecting latest Node.js LTS version..."
# Auto-detect latest Node.js LTS version if not specified
if [ -z "$NODE_VERSION" ]; then
  # Try to fetch latest LTS version from nodejs.org
  # Use dist-index.json which lists all versions, filter for v22.x (current LTS)
  LATEST_NODE=""
  if command -v curl >/dev/null 2>&1; then
    # Get latest v22.x version (Iron LTS)
    LATEST_NODE=$(curl -fsSL --max-time 10 https://nodejs.org/dist/index.json 2>/dev/null | \
      grep -o '"version":"v22\.[0-9]*\.[0-9]*"' | head -1 | cut -d'"' -f4)
  elif command -v busybox >/dev/null 2>&1; then
    LATEST_NODE=$(busybox wget -qO- --timeout=10 https://nodejs.org/dist/index.json 2>/dev/null | \
      grep -o '"version":"v22\.[0-9]*\.[0-9]*"' | head -1 | cut -d'"' -f4)
  fi
  
  if [ -n "$LATEST_NODE" ]; then
    NODE_VERSION="$LATEST_NODE"
    ui_print "Latest Node.js LTS (v22.x): $NODE_VERSION"
    log "Auto-detected Node.js LTS version: $NODE_VERSION"
  else
    NODE_VERSION="v22.19.0"
    ui_print "Failed to detect, using fallback: $NODE_VERSION"
    log "Failed to auto-detect Node.js, using fallback: $NODE_VERSION"
  fi
else
  ui_print "Using Node.js: $NODE_VERSION"
  log "Using specified Node.js version: $NODE_VERSION"
fi

# ════════════════════════════════════════════════════
#  Node.js Installation
# ════════════════════════════════════════════════════

if [ "$IS_UPGRADE" = false ]; then
  # ── Download Node.js ──
  ui_print "Downloading Node.js ${NODE_VERSION}..."
  ARCHIVE_NAME="node-${NODE_VERSION}-linux-arm64.tar.gz"
  DOWNLOAD_URL="${NODE_BASE_URL}/${NODE_VERSION}/${ARCHIVE_NAME}"
  log "Downloading: $DOWNLOAD_URL"

  DOWNLOAD_OK=0
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 "$DOWNLOAD_URL" -o "$INSTALL_DIR/tmp/$ARCHIVE_NAME" && DOWNLOAD_OK=1
  elif command -v busybox >/dev/null 2>&1; then
    busybox wget --no-check-certificate -O "$INSTALL_DIR/tmp/$ARCHIVE_NAME" "$DOWNLOAD_URL" && DOWNLOAD_OK=1
  fi

  [ $DOWNLOAD_OK -eq 1 ] || abort "Failed to download Node.js from $DOWNLOAD_URL"
  FILE_SIZE=$(stat -c%s "$INSTALL_DIR/tmp/$ARCHIVE_NAME" 2>/dev/null || echo "?")
  log "downloaded: $ARCHIVE_NAME ($FILE_SIZE bytes)"

  # ── Extract directly into NODE_DIR ──
  ui_print "Extracting Node.js..."
  rm -rf "$NODE_DIR"
  mkdir -p "$NODE_DIR"

  # Extract the whole archive (with top-level dir)
  tar -xzf "$INSTALL_DIR/tmp/$ARCHIVE_NAME" -C "$NODE_DIR" || \
    abort "Node.js extraction failed"

  # The archive has top-level dir like node-v22.14.0-linux-arm64/
  # Find it and move everything up one level
  ARCHIVE_TOP=$(ls -d "$NODE_DIR"/node-v*-linux-arm64 2>/dev/null | head -1)
  if [ -n "$ARCHIVE_TOP" ] && [ -d "$ARCHIVE_TOP" ]; then
    log "Found top-level dir: $ARCHIVE_TOP — promoting contents"
    
    # Backup original npm/npx before moving (they might be symlinks)
    if [ -e "$ARCHIVE_TOP/bin/npm" ]; then
      cp -P "$ARCHIVE_TOP/bin/npm" "$ARCHIVE_TOP/bin/npm.orig" 2>/dev/null || true
    fi
    if [ -e "$ARCHIVE_TOP/bin/npx" ]; then
      cp -P "$ARCHIVE_TOP/bin/npx" "$ARCHIVE_TOP/bin/npx.orig" 2>/dev/null || true
    fi
    
    mv "$ARCHIVE_TOP"/* "$NODE_DIR/" 2>/dev/null || true
    mv "$ARCHIVE_TOP"/.* "$NODE_DIR/" 2>/dev/null || true
    rmdir "$ARCHIVE_TOP" 2>/dev/null || true
  fi
  log "Archive extracted and flattened"

  rm -f "$INSTALL_DIR/tmp/$ARCHIVE_NAME"

  # ── Verify extraction ──
  [ -f "$NODE_DIR/bin/node" ] || abort "Extracted node binary not found at $NODE_DIR/bin/node"
  log "Extracted files verified at $NODE_DIR/bin"

  # ── Rename real node binary ──
  mv "$NODE_DIR/bin/node" "$NODE_DIR/bin/node.real"
  log "Renamed node -> node.real"

  # ── Create node wrapper ──
  cat > "$NODE_DIR/bin/node" << 'NOWRAP'
#!/system/bin/sh
unset LD_PRELOAD
LDSO="/data/adb/openclaw/glibc/lib/ld-linux-aarch64.so.1"
GLIBC="/data/adb/openclaw/glibc/lib"
REAL="$(dirname "$0")/node.real"
COMPAT="/data/adb/openclaw/node/lib/compat.js"

export HOME="${HOME:-/data/adb/openclaw/home}"
export TMPDIR="${TMPDIR:-/data/adb/openclaw/tmp}"

# Inject compat.js via NODE_OPTIONS (idempotent)
if [ -f "$COMPAT" ]; then
    case "${NODE_OPTIONS:-}" in
        *"$COMPAT"*) ;;
        *) export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $COMPAT" ;;
    esac
fi

# Hoist leading --flags into NODE_OPTIONS (ld.so doesn't understand node flags)
_COUNT=0
for _a in "$@"; do
    case "$_a" in --*) _COUNT=$((_COUNT+1)) ;; *) break ;; esac
done
if [ "$_COUNT" -gt 0 ] && [ "$_COUNT" -lt $# ]; then
    while [ $# -gt 0 ]; do
        case "$1" in
            --*) NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }$1"; shift ;;
            *) break ;;
        esac
    done
    export NODE_OPTIONS
fi

exec "$LDSO" --library-path "$GLIBC" "$REAL" "$@"
NOWRAP
  chmod 755 "$NODE_DIR/bin/node"
  log "Node wrapper created"

  # ── Create compat.js ──
  mkdir -p "$NODE_DIR/lib"
  cat > "$NODE_DIR/lib/compat.js" << 'COMPAT'
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

// Fix 1: process.execPath -> node wrapper
const NODE_WRAPPER = '/data/adb/openclaw/node/bin/node';
try {
  if (fs.existsSync(NODE_WRAPPER)) {
    Object.defineProperty(process, 'execPath', {
      value: NODE_WRAPPER, writable: true, configurable: true
    });
  }
} catch (_) {}

// Fix 2: os.networkInterfaces() -> EACCES on Android
const _origNet = os.networkInterfaces;
os.networkInterfaces = function networkInterfaces() {
  try { return _origNet.call(os); } catch (_) {
    return { lo: [{ address: '127.0.0.1', netmask: '255.0.0.0',
      family: 'IPv4', mac: '00:00:00:00:00:00',
      internal: true, cidr: '127.0.0.1/8' }] };
  }
};

// Fix 3: os.cpus() -> [] on Android (SELinux blocks /proc/stat)
const _origCpus = os.cpus;
os.cpus = function cpus() {
  const r = _origCpus.call(os);
  if (r.length > 0) return r;
  return [{ model: 'ARM Cortex', speed: 1800,
    times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } },
    { model: 'ARM Cortex', speed: 1800,
    times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }];
};

// Fix 4: HOME guard
if (!process.env.HOME || process.env.HOME === '/') {
  process.env.HOME = '/data/adb/openclaw/home';
}
COMPAT
  log "compat.js created"

  # ── Create npm/npx wrappers ──
  # Remove existing npm/npx (might be symlinks to npm-cli.js/npx-cli.js)
  rm -f "$NODE_DIR/bin/npm" "$NODE_DIR/bin/npx"
  
  cat > "$NODE_DIR/bin/npm" << 'NPMWRAP'
#!/system/bin/sh
export PATH="/data/adb/openclaw/node/bin:$PATH"
export NPM_CONFIG_PREFIX="/data/adb/openclaw/node"
exec "/data/adb/openclaw/node/bin/node" "/data/adb/openclaw/node/lib/node_modules/npm/bin/npm-cli.js" "$@"
NPMWRAP
  chmod 755 "$NODE_DIR/bin/npm"

  cat > "$NODE_DIR/bin/npx" << 'NPXWRAP'
#!/system/bin/sh
export PATH="/data/adb/openclaw/node/bin:$PATH"
export NPM_CONFIG_PREFIX="/data/adb/openclaw/node"
exec "/data/adb/openclaw/node/bin/node" "/data/adb/openclaw/node/lib/node_modules/npm/bin/npx-cli.js" "$@"
NPXWRAP
  chmod 755 "$NODE_DIR/bin/npx"
  log "npm/npx wrappers created"

  # ── Smoke test ──
  NODE_VER=$("$NODE_DIR/bin/node" --version 2>&1) || abort "Node smoke test failed: $NODE_VER"
  log "node OK: $NODE_VER"
  ui_print "Node.js ${NODE_VER} ready"
else
  # Upgrade: verify existing node
  NODE_VER=$("$NODE_DIR/bin/node" --version 2>&1) || abort "Existing Node.js broken: $NODE_VER"
  log "upgrade — existing node OK: $NODE_VER"
  ui_print "Using existing Node.js ${NODE_VER}"
fi

# ════════════════════════════════════════════════════
#  DoH Proxy (now we have Node)
# ════════════════════════════════════════════════════

# Stop any old doh-proxy
pkill -f doh-proxy.mjs 2>/dev/null || true
sleep 0.3

# Start DoH proxy
DOH_PORT=$DOH_PORT "$NODE_DIR/bin/node" "$INSTALL_DIR/doh-proxy.mjs" >> "$LOG" 2>&1 &
DOH_PID=$!
sleep 2

if kill -0 $DOH_PID 2>/dev/null; then
  log "DoH proxy running PID=$DOH_PID"
else
  log "WARNING: DoH proxy failed to start"
fi

# Apply iptables DNS redirect
iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port $DOH_PORT
iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port $DOH_PORT
log "iptables DNS redirect 53->$DOH_PORT applied"

# Wait for DNS to work through proxy
if kill -0 $DOH_PID 2>/dev/null; then
  RETRY=0
  while [ $RETRY -lt 30 ]; do
    if ping -c 1 -W 3 registry.npmjs.org >/dev/null 2>&1; then
      log "DNS via DoH proxy working"
      break
    fi
    RETRY=$((RETRY+1))
    sleep 2
  done
fi

# ════════════════════════════════════════════════════
#  OpenClaw Installation
# ════════════════════════════════════════════════════

export PATH="$NODE_DIR/bin:$PATH"
export HOME="$INSTALL_DIR/home"
export npm_config_prefix="$INSTALL_DIR"
export npm_config_cache="$INSTALL_DIR/tmp/npm-cache"

mkdir -p "$npm_config_cache"
rm -rf "$INSTALL_DIR/lib/node_modules/openclaw"
rm -f  "$INSTALL_DIR/bin/openclaw"

ui_print "Installing OpenClaw..."
ATTEMPT=0
INSTALL_OK=0
while [ $ATTEMPT -lt 3 ]; do
  ATTEMPT=$((ATTEMPT+1))
  case "$ATTEMPT" in
    1) ui_print "Installing...";;
    2) ui_print "Retrying...";;
    3) ui_print "Final attempt, please wait...";;
  esac

  "$NODE_DIR/bin/npm" install -g openclaw \
    --prefer-online \
    --omit=optional \
    --ignore-scripts \
    --fetch-timeout=180000 \
    --fetch-retry-mintimeout=30000 \
    --fetch-retry-maxtimeout=120000 \
    --fetch-retries=5 >>"$LOG" 2>&1
  
  NPM_EXIT=$?
  log "npm install attempt $ATTEMPT exit code: $NPM_EXIT"

  # Check if openclaw package was installed
  # npm might install to either $INSTALL_DIR/lib or $NODE_DIR/lib depending on config
  if [ -f "$INSTALL_DIR/lib/node_modules/openclaw/openclaw.mjs" ]; then
    OPENCLAW_MJS="$INSTALL_DIR/lib/node_modules/openclaw/openclaw.mjs"
    INSTALL_OK=1
    log "openclaw.mjs found at $OPENCLAW_MJS"
    break
  elif [ -f "$NODE_DIR/lib/node_modules/openclaw/openclaw.mjs" ]; then
    OPENCLAW_MJS="$NODE_DIR/lib/node_modules/openclaw/openclaw.mjs"
    INSTALL_OK=1
    log "openclaw.mjs found at $OPENCLAW_MJS"
    break
  fi
  
  log "openclaw.mjs not found after attempt $ATTEMPT"
  sleep 3
done

[ $INSTALL_OK -eq 1 ] || abort "npm install failed after 3 attempts"

# ── Create openclaw binary wrapper ─────────────────
mkdir -p "$INSTALL_DIR/bin"
OPENCLAW_WRAPPER="$INSTALL_DIR/bin/openclaw"
printf '#!/system/bin/sh\n'                                                  > "$OPENCLAW_WRAPPER"
printf 'export PATH="%s/bin:$PATH"\n'                   "$NODE_DIR"         >> "$OPENCLAW_WRAPPER"
printf 'export HOME="%s/home"\n'                        "$INSTALL_DIR"      >> "$OPENCLAW_WRAPPER"
printf 'export npm_config_prefix="%s"\n'                "$INSTALL_DIR"      >> "$OPENCLAW_WRAPPER"
printf 'exec "%s/bin/node" "%s" "$@"\n' "$NODE_DIR" "$OPENCLAW_MJS" >> "$OPENCLAW_WRAPPER"
chmod 755 "$OPENCLAW_WRAPPER"
log "openclaw wrapper created"

# ── Patch entry.js ──
OPENCLAW_DIR=$(dirname "$OPENCLAW_MJS")
ENTRY_JS="$OPENCLAW_DIR/dist/entry.js"
if [ -f "$ENTRY_JS" ]; then
  TMP_ENTRY="$ENTRY_JS.tmp"
  : > "$TMP_ENTRY"
  while IFS= read -r line; do
    case "$line" in
      *'const child = spawn(process$1.execPath, plan.argv, {'*)
        printf '%s\n' \
          ' const child = spawn((process$1.execPath && process$1.execPath.indexOf("ld-linux-aarch64.so.1") === -1 ? process$1.execPath : "/data/adb/openclaw/node/bin/node"), plan.argv, {' \
          >> "$TMP_ENTRY"
        ;;
      *)
        printf '%s\n' "$line" >> "$TMP_ENTRY"
        ;;
    esac
  done < "$ENTRY_JS"
  mv "$TMP_ENTRY" "$ENTRY_JS"
  log "entry.js patched at $ENTRY_JS"
else
  log "entry.js not found at $ENTRY_JS, skipping patch"
fi

# ── Default config ─────────────────────────────────
CONF="$INSTALL_DIR/home/.openclaw/openclaw.json"
mkdir -p "$(dirname "$CONF")"
if [ ! -f "$CONF" ]; then
  cat > "$CONF" << 'JSONEOF'
{
  "agents": {},
  "plugins": {},
  "gateway": {
    "bind": "loopback"
  }
}
JSONEOF
  chmod 600 "$CONF"
  log "default config created"
fi

# ── Verify ─────────────────────────────────────────
OC_VER=$("$OPENCLAW_WRAPPER" --version 2>&1 | head -1)
log "openclaw installed: $OC_VER"
ui_print "OpenClaw ${OC_VER} installed"

# ════════════════════════════════════════════════════
#  Cleanup
# ════════════════════════════════════════════════════

pkill -f doh-proxy.mjs 2>/dev/null || true
iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-port $DOH_PORT 2>/dev/null || true
log "DoH proxy stopped (will restart via service.sh on reboot)"

set_perm "$MODPATH/system/bin/openclaw"         root root 0755
set_perm "$MODPATH/system/bin/openclaw.service" root root 0755

rm -rf "$INSTALL_DIR/tmp"
chmod 755 "$OPENCLAW_WRAPPER"
chmod 600 "$CONF"
echo "done" > "$INSTALL_DIR/.install_state"
chmod 600 "$INSTALL_DIR/.install_state"

log "===== Install complete ====="
ui_print "Installation completed!"
ui_print ""
ui_print "Reboot to activate OpenClaw."
ui_print ""
