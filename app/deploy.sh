#!/bin/sh
# Deploy Path of Building (Qt) on Linux.
#
# Prerequisites:
#   * A build:  cmake -S app -B build -DCMAKE_BUILD_TYPE=Release ; cmake --build build
#
# Usage:
#   sh app/deploy.sh
#
# Produces build/dist/ containing pob-qt + the Lua engine sources. The legacy
# SimpleGraphic runtime is NOT copied — the Qt app replaces that engine. If
# linuxdeployqt is available it bundles the Qt6 runtime; otherwise the binary
# links against the system Qt6 (install qt6-qtbase/qt6-qtdeclarative/qt6-qtsvg).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$BUILD/dist"

if [ ! -x "$BUILD/pob-qt" ]; then
    echo "pob-qt not found in $BUILD. Build the project first." >&2
    exit 1
fi

# 1) Lay out the Qt app + Lua engine sources (no SimpleGraphic runtime).
cmake --install "$BUILD" --prefix "$BUILD"

# 2) Bundle the Qt6 runtime next to the executable (if linuxdeployqt present).
if command -v linuxdeployqt >/dev/null 2>&1; then
    linuxdeployqt "$DIST/pob-qt" -qmldir="$ROOT/app/qml" -bundle-non-qt-libs -appimage
else
    echo "linuxdeployqt not found; the binary links against the system Qt6."
    echo "Ensure qt6-qtbase / qt6-qtdeclarative / qt6-qtsvg are installed at runtime."
fi

echo "Deployment ready at: $DIST"
echo "Launch with: $DIST/pob-qt   (or: $DIST/pob-qt --headless for CI)"
