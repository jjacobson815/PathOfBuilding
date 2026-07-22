#!/bin/sh
# Builds the Qt/QML + LuaJIT frontend inside the dev sandbox and runs the
# headless self-test (and an offscreen GUI smoke test). Mount the repo at
# /workdir and run: docker run --rm -it -v "%CD%:/workdir" -w /workdir pob-qt-dev sh docker/run-selftest.sh
# NOTE: in this fork the engine's data dirs (TreeData/, Assets/, Data/) live
# under src/, and the engine opens them relative to the process cwd. So the
# binaries MUST run with cwd = src/ (manifest.xml is found via the engine's
# "../manifest.xml" fallback from there).
set -e

SRC=/workdir
BUILD="$SRC/build"
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

cmake -S "$SRC/app" -B . -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build . -j"$(nproc)"

# Run from src/ so relative asset paths (TreeData/, Assets/, Data/) resolve.
# manifest.xml is read via the engine's "../manifest.xml" fallback.
cd "$SRC/src"

echo "=== SELFTEST (headless bridge verification) ==="
timeout 60 "$BUILD"/pob-selftest "$SRC/src" "$SRC/runtime"
st_rc=$?
if [ "$st_rc" -eq 124 ]; then
    echo "SELFTEST TIMED OUT (60s) -- possible hang"
fi

echo "=== HEADLESS MODE (pob-qt --headless, no display) ==="
"$BUILD"/pob-qt --headless --src "$SRC/src" --runtime "$SRC/runtime" && echo "HEADLESS OK" || { echo "HEADLESS FAILED"; exit 1; }

echo "=== GUI SMOKE TEST (offscreen, SIGKILL-safe) ==="
# Use SIGKILL (not SIGTERM): the offscreen Qt surface ignores SIGTERM, which
# would leave a zombie that wedges the Docker daemon. SIGKILL guarantees cleanup.
QT_QPA_PLATFORM=offscreen timeout -s KILL 12 "$BUILD"/pob-qt --src "$SRC/src" --runtime "$SRC/runtime" || rc=$?
if [ "${rc:-0}" -eq 124 ] || [ "${rc:-0}" -eq 137 ]; then
    echo "GUI ran with no crash (offscreen platform, killed after timeout)"
else
    echo "GUI exited with code ${rc:-0}"
fi

echo "DONE"
