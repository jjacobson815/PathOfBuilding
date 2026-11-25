#!/usr/bin/env bash
# Produce a FULLY SELF-CONTAINED Windows dist of Path of Building (Qt) that
# double-clicks with no msys2/mingw on PATH — unlike run_pob_fusion.bat, which
# is a dev launcher that rebuilds and relies on C:\msys64\mingw64\bin being on
# PATH.
#
# Run from an msys2/git-bash shell after building:
#     ninja -C build-win pob-qt          # (or your build dir)
#     bash app/deploy-win-standalone.sh  # -> populates ./dist as standalone
#
# What this does that plain `cmake --install` + `windeployqt` do NOT:
#   * copies the FULL mingw dependency closure next to the exe. msys2's
#     windeployqt bundles the Qt6 DLLs but NOT the base mingw runtime
#     (zlib1, libgcc, libstdc++, libwinpthread, ICU, lua51, ...), so a clean-
#     PATH launch dies with "zlib1.dll: cannot open shared object file" etc.
#   * writes a qt.conf. Without it, Qt6Core (now loaded from dist/) resolves its
#     QML import path relative to ITSELF as ../share/qt6/qml (nonexistent), so
#     `qml.load` fails with 'module "QtQuick.Controls" plugin ... not found'
#     even though windeployqt deployed dist/qml correctly. msys2 windeployqt
#     does not emit this file.
set -euo pipefail

MINGW="${MINGW:-/c/msys64/mingw64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$ROOT/build-win}"
DIST="${DIST:-$ROOT/dist}"

export PATH="$MINGW/bin:$MINGW/share/qt6/bin:$PATH"   # qt6/bin holds qmlimportscanner

[ -x "$BUILD/pob-qt.exe" ] || { echo "pob-qt.exe not in $BUILD — build first (ninja -C $BUILD pob-qt)"; exit 1; }
command -v windeployqt.exe >/dev/null || { echo "windeployqt.exe not on PATH (set MINGW=... to your mingw64 root)"; exit 1; }

echo "[deploy] 1/4 cmake --install -> $DIST"
CMAKE_INSTALL_ALWAYS=1 cmake --install "$BUILD" --prefix "$DIST/.." >/dev/null    # lays out exe, lua, src, runtime (+ lua-utf8/lua51 via install rule)
cp -f "$BUILD/pob-qt.exe" "$DIST/pob-qt.exe"               # force-copy so dist is never stale vs build

echo "[deploy] 2/4 windeployqt (Qt6 DLLs + qml modules + plugins, Fusion style)"
windeployqt.exe --qmldir "$ROOT/app/qml" --no-translations "$DIST/pob-qt.exe" >/dev/null

# libcurl (MSYS2 build) resolves its default CA bundle relative to libcurl-4.dll, which
# is nonexistent once the DLL lives in dist/. Ship a CA bundle; TlsCa.h looks for it.
mkdir -p "$DIST/certs"
cp -f "$MINGW/etc/ssl/certs/ca-bundle.crt" "$DIST/certs/ca-bundle.crt"

# Verify critical Qt6 plugins and runtime assets deployed cleanly; fail loudly if missing.
# The 3_27+/3_28+ trees ship their ascendancy/bloodline art as .webp, which Qt can
# only decode through the qtimageformats webp plugin -- a SEPARATE msys2 package
# (mingw-w64-x64-64/mingw-w64-x86_64-qt6-imageformats). Without it QImageReader returns
# a null QImage and that art renders blank, with no error logged anywhere.
required_files=(
    "pob-qt.exe"
    "Qt6Core.dll"
    "Qt6Gui.dll"
    "Qt6Network.dll"
    "Qt6Qml.dll"
    "Qt6Quick.dll"
    "platforms/qwindows.dll"
    "imageformats/qwebp.dll"
    "runtime/lua-utf8.dll"
    "runtime/lua51.dll"
    "lua/pob_host.lua"
    "src/Launch.lua"
    "src/installed.cfg"
    "manifest.xml"
    "certs/ca-bundle.crt"
)
for rel in "${required_files[@]}"; do
    if [ ! -f "$DIST/$rel" ]; then
        echo "[deploy] ERROR: required runtime asset missing: $DIST/$rel" >&2
        if [ "$rel" = "imageformats/qwebp.dll" ]; then
            echo "[deploy]        Install it and re-run: pacman -S mingw-w64-x86_64-qt6-imageformats" >&2
        fi
        exit 1
    fi
done

for reldir in "runtime/lua" "runtime/SimpleGraphic/Fonts" "src/TreeData"; do
    if [ ! -d "$DIST/$reldir" ]; then
        echo "[deploy] ERROR: required runtime directory missing: $DIST/$reldir" >&2
        exit 1
    fi
done

echo "[deploy] 3/4 copy mingw dependency closure next to exe (iterate to fixpoint)"
prev=0
for pass in 1 2 3 4 5; do
    # ldd the exe AND every deployed DLL; collect deps still resolving to mingw,
    # translate the msys mount path to a real one, copy any missing basenames.
    { ldd "$DIST/pob-qt.exe"; find "$DIST" -iname '*.dll' -exec ldd {} \; ; } 2>/dev/null \
        | grep -oiE '/mingw64/bin/[^ ]*\.dll' | sort -u | sed "s#^/mingw64/#$MINGW/#" \
        | while read -r dll; do b="$(basename "$dll")"; [ -f "$DIST/$b" ] || cp "$dll" "$DIST/"; done
    n="$(ls "$DIST"/*.dll 2>/dev/null | wc -l)"
    [ "$n" = "$prev" ] && break
    prev="$n"
done
echo "[deploy]     $prev DLLs next to exe"

# Ensure Qt6::Network TLS/OpenSSL dependencies are present if qopensslbackend.dll was deployed.
if [ -f "$DIST/tls/qopensslbackend.dll" ]; then
    for ssl_dll in "$MINGW/bin/libssl-"*.dll "$MINGW/bin/libcrypto-"*.dll; do
        if [ -f "$ssl_dll" ]; then
            b="$(basename "$ssl_dll")"
            [ -f "$DIST/$b" ] || cp "$ssl_dll" "$DIST/"
        fi
    done
    if ! ls "$DIST"/libssl-*.dll >/dev/null 2>&1 || ! ls "$DIST"/libcrypto-*.dll >/dev/null 2>&1; then
        echo "[deploy] ERROR: qopensslbackend.dll is deployed but OpenSSL DLLs (libssl/libcrypto) are missing." >&2
        exit 1
    fi
fi

echo "[deploy] 4/4 write qt.conf (point Qt at dist-local plugins + qml)"
cat > "$DIST/qt.conf" <<'EOF'
[Paths]
Prefix = .
Plugins = .
Imports = qml
Qml2Imports = qml
EOF

# The fixpoint loop above is the completion signal: it copies mingw DLLs until a
# pass adds none. A residual `ldd | grep /mingw64` count here would be a FALSE
# positive — ldd runs with mingw on PATH and reports the mingw copy of a DLL even
# when an identical one already sits in dist. The only honest verification is a
# clean-PATH launch (no mingw), so run that and report its exit code.
echo "[deploy] verifying with a clean-PATH smoke test (no mingw on PATH)..."
# --capture writes relative to the engine cwd (dist/src), so use a bare dir name.
( unset QML_IMPORT_PATH QT_PLUGIN_PATH; PATH="/c/Windows/System32:/c/Windows" \
    "$DIST/pob-qt.exe" --capture _deploycheck >/dev/null 2>&1 ) || true
if grep -Eq "viewList count=(8|9|10)" "$DIST/src/_deploycheck/_status.log" 2>/dev/null; then
    rm -rf "$DIST/src/_deploycheck"
    echo "[deploy] OK — standalone dist boots the engine with no mingw on PATH: $DIST"
    echo "[deploy] $(ls "$DIST"/*.dll | wc -l) DLLs bundled; dist/pob-qt.exe is now double-clickable."
else
    rm -rf "$DIST/src/_deploycheck"
    echo "[deploy] WARNING: clean-PATH smoke test FAILED — dist is not fully self-contained." >&2
    echo "[deploy] Re-run under an msys2 shell with MINGW pointing at your mingw64 root." >&2
    exit 1
fi

# Clean-PATH HTTPS/CA probe: run the headless selftest (offline TLS handshake against a
# plain-HTTP loopback server) using the deployed pob-qt.exe so applicationDirPath()
# (certs/) and DLL lookup are dist-local, with no pob-selftest.exe build dependency.
# CURLE_SSL_CACERT_BADFILE ("SSL CA cert") means the CA config is broken.
echo "[deploy] verifying standalone HTTPS CA init (clean PATH)..."
# Engine/Lua assets come from the repo (dist lacks files other selftest checks need).
https_out="$( cd "$ROOT/src" && unset QML_IMPORT_PATH QT_PLUGIN_PATH CURL_CA_BUNDLE SSL_CERT_FILE; \
    PATH="/c/Windows/System32:/c/Windows" QT_FORCE_STDERR_LOGGING=1 \
    "$DIST/pob-qt.exe" --headless --src "$PWD" --runtime "$ROOT/runtime" --host "$ROOT/app/lua/pob_host.lua" 2>&1 || true )"
if echo "$https_out" | grep -q "tlsCaInitOk=true"; then
    echo "[deploy] OK — standalone HTTPS CA init works with no mingw on PATH."
else
    echo "[deploy] ERROR: standalone HTTPS CA probe FAILED (missing/invalid CA config):" >&2
    echo "$https_out" | grep -iE "tlsCa|SSL CA cert" >&2 || true
    exit 1
fi
