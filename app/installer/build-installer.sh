#!/usr/bin/env bash
# Build the Windows NSIS installer from a standalone dist/ directory.
#
# Usage:
#   bash app/installer/build-installer.sh [--deploy] [--version X.Y.Z] [--out path.exe]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
OUT_DIR="${OUT_DIR:-$ROOT/dist-installer}"
NSI_SCRIPT="$ROOT/app/installer/pob-qt.nsi"
RUN_DEPLOY=0
APP_VERSION="${APP_VERSION:-}"
OUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --deploy)
            RUN_DEPLOY=1
            shift
            ;;
        --version)
            APP_VERSION="$2"
            shift 2
            ;;
        --out)
            OUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: bash app/installer/build-installer.sh [--deploy] [--version X.Y.Z] [--out path.exe]"
            exit 0
            ;;
        *)
            echo "[installer] ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [ "$RUN_DEPLOY" -eq 1 ] || [ ! -f "$DIST/pob-qt.exe" ]; then
    echo "[installer] Running deploy-win-standalone.sh..."
    bash "$ROOT/app/deploy-win-standalone.sh"
fi

if [ ! -f "$DIST/pob-qt.exe" ]; then
    echo "[installer] ERROR: $DIST/pob-qt.exe not found; build and deploy first." >&2
    exit 1
fi

if [ ! -d "$DIST/src/TreeData" ]; then
    echo "[installer] ERROR: $DIST/src/TreeData not found." >&2
    exit 1
fi

tree_count="$(find "$DIST/src/TreeData" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
if [ "$tree_count" -lt 39 ]; then
    echo "[installer] ERROR: expected >= 39 TreeData versions in $DIST/src/TreeData, found $tree_count" >&2
    exit 1
fi
echo "[installer] Verified $tree_count TreeData directories in $DIST/src/TreeData"

if [ -z "$APP_VERSION" ]; then
    APP_VERSION="$(sed -n 's/.*<Version number="\([^"]*\)".*/\1/p' "$ROOT/manifest.xml" | head -n1)"
    APP_VERSION="${APP_VERSION:-0.0.0}"
fi

mkdir -p "$OUT_DIR"
if [ -z "$OUT_FILE" ]; then
    OUT_FILE="$OUT_DIR/PathOfBuilding-Qt-Setup-${APP_VERSION}.exe"
fi

MAKENSIS="${MAKENSIS:-}"
if [ -z "$MAKENSIS" ]; then
    if command -v makensis.exe >/dev/null 2>&1; then
        MAKENSIS="makensis.exe"
    elif command -v makensis >/dev/null 2>&1; then
        MAKENSIS="makensis"
    elif [ -x "/c/Program Files (x86)/NSIS/makensis.exe" ]; then
        MAKENSIS="/c/Program Files (x86)/NSIS/makensis.exe"
    else
        echo "[installer] ERROR: makensis not found on PATH or in C:\\Program Files (x86)\\NSIS" >&2
        exit 1
    fi
fi

to_win_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

DIST_WIN="$(to_win_path "$DIST")"
OUT_WIN="$(to_win_path "$OUT_FILE")"

echo "[installer] Building NSIS installer v$APP_VERSION -> $OUT_FILE"
"$MAKENSIS" \
    "-DAPP_VERSION=$APP_VERSION" \
    "-DDIST_DIR=$DIST_WIN" \
    "-DOUT_FILE=$OUT_WIN" \
    "$(to_win_path "$NSI_SCRIPT")"

echo "[installer] OK: $OUT_FILE"
