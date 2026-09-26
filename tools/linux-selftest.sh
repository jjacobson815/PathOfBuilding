#!/usr/bin/env bash
# Linux build + self-test gate for the Qt port.
#
#   tools/linux-selftest.sh            # install deps (if missing), build, run both gates
#   SKIP_DEPS=1 tools/linux-selftest.sh  # skip apt/luautf8 step
#
# Steps: apt deps -> luautf8 (utf8.so) -> cmake+ninja (build-linux/) ->
# pob-selftest -> pob-qt --headless. Exits non-zero on the first failure.
# Tested on Ubuntu 24.04 (Qt 6.4.2, LuaJIT 2.1).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO/build-linux"
GATE_TIMEOUT="${GATE_TIMEOUT:-600}"

log() { printf '\n== %s\n' "$*"; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# ---- 1. Dependencies -------------------------------------------------------
APT_PKGS=(
  cmake ninja-build pkg-config git g++
  qt6-base-dev qt6-declarative-dev qt6-svg-dev
  qt6-image-formats-plugins   # REQUIRED: without it .webp tree art decodes to null silently
  qt6-qpa-plugins             # offscreen platform plugin
  qml6-module-qtqml qml6-module-qtqml-workerscript
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-templates
  qml6-module-qtquick-layouts qml6-module-qtquick-window
  libluajit-5.1-dev luajit libcurl4-openssl-dev zlib1g-dev libgl-dev
)
# lua-utf8: runtime/lua-utf8.dll is Windows-only. pob_host.lua falls back to
# require("utf8"), which LuaJIT finds on its default cpath here.
UTF8_SO=/usr/local/lib/lua/5.1/utf8.so

if [ "${SKIP_DEPS:-0}" != "1" ]; then
  log "Checking apt packages"
  missing=()
  for p in "${APT_PKGS[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    log "Installing: ${missing[*]}"
    $SUDO apt-get update -qq || true   # unrelated PPAs may 403; the main archive is enough
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  fi

  if [ ! -f "$UTF8_SO" ]; then
    log "Building luautf8 -> $UTF8_SO"
    tmp="$(mktemp -d)"
    git clone --depth 1 https://github.com/starwing/luautf8 "$tmp/luautf8"
    gcc -O2 -shared -fPIC -I/usr/include/luajit-2.1 -o "$tmp/utf8.so" "$tmp/luautf8/lutf8lib.c" -lm
    $SUDO install -D -m 0755 "$tmp/utf8.so" "$UTF8_SO"
    rm -rf "$tmp"
  fi
fi
luajit -e 'require("utf8")' || { echo "FAIL: luajit cannot require('utf8')"; exit 1; }

# ---- 2. Build --------------------------------------------------------------
log "Configuring + building (build-linux/)"
cmake -S "$REPO/app" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C "$BUILD" pob-selftest pob-qt

# ---- 3. Gates --------------------------------------------------------------
export QT_QPA_PLATFORM=offscreen
export QT_FORCE_STDERR_LOGGING=1
SRC="$REPO/src"; RT="$REPO/runtime"; HOST="$REPO/app/lua/pob_host.lua"   # must be absolute

status=0
run_gate() {
  local name="$1"; shift
  log "Running $name"
  local rc=0
  timeout "$GATE_TIMEOUT" "$@" || rc=$?
  echo "$name EXIT=$rc"
  [ "$rc" -eq 0 ] || status=1
  return 0
}
run_gate pob-selftest "$BUILD/pob-selftest" "$SRC" "$RT" "$HOST"
run_gate "pob-qt --headless" "$BUILD/pob-qt" --headless --src "$SRC" --runtime "$RT" --host "$HOST"

if [ "$status" -eq 0 ]; then log "ALL GATES PASSED"; else log "GATE FAILED"; fi
exit "$status"
