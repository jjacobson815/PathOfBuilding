---
name: pob-visual-capture
description: >-
  Capture QML view screenshots, inspect QML runtime logs, drive interactive Xvfb
  UI sessions on Linux, and refresh Windows capture baselines for PoB Qt views.
---

# PoB Qt Port — Visual Capture & UI Verification

Use this skill after any QML or rendering change (`pob-qt --headless` does not load QML, so visual capture is required to catch QML runtime errors and layout regressions).

## Prerequisites
- Rebuild first (`ninja -C build-win` or `ninja -C build-linux`), because QML files are bundled into the binary via qrc.
- Terminate any running `pob-qt` before rebuilding (`Stop-Process -Name pob-qt` on Windows; `pkill pob-qt` on Linux).

## Windows Visual Capture & Re-Baselining
Run from `cwd = src/` with MinGW64 on `PATH`:
```bash
cd src
PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
  ../build-win/pob-qt.exe --capture ../captures/verify \
  --src "$PWD" --runtime "$PWD/../runtime" --host "$PWD/../app/lua/pob_host.lua"
```
- **Re-baselining rule:** `app/tests/capture-baseline/*.png` files are Windows captures. Update baselines **only on Windows** — Linux font rendering differs on every view and must never overwrite Windows baselines.

## Linux Visual Capture (Xvfb — Never Plain `offscreen`)
Plain `QT_QPA_PLATFORM=offscreen --capture` renders the OpenGL `TreeScene` area **blank**. Always capture under Xvfb with `xcb`:
```bash
cd src
QT_QPA_PLATFORM=xcb xvfb-run -a -s "-screen 0 1280x800x24" \
  ../build-linux/pob-qt --capture /tmp/pob-capture \
  --src "$PWD" --runtime ../runtime --host ../app/lua/pob_host.lua
```
- Check `/tmp/pob-qt-main.log` first for any QML warnings or runtime errors.

## Driving the Interactive UI on Linux (Xvfb + `xdotool`)
When verifying popups, clicks, hovers, or tab interactions on Linux:
1. Ensure packages are installed: `apt-get install -y xdotool x11-apps imagemagick`.
2. Optional preload host wrapper (`/tmp/vis/host.lua`) to open directly into a populated test build:
   ```lua
   _POB_LUA_DIR = _SRC_DIR .. "/../app/lua"
   dofile(_POB_LUA_DIR .. "/pob_host.lua")
   local tb = dofile(_SRC_DIR .. "/../spec/TestBuilds/3.13/OccVortex.lua")
   pcall(pob_loadBuildXML, tb.xml, "OccVortex")
   ```
3. Launch under `Xvfb :99` from `cwd = src/`:
   ```bash
   Xvfb :99 -screen 0 1280x800x24 &
   QT_QPA_PLATFORM=xcb DISPLAY=:99 ../build-linux/pob-qt \
     --src "$PWD" --runtime ../runtime --host /tmp/vis/host.lua &
   ```
4. Drive interactions and grab screenshots:
   - Click / type / hotkey: `DISPLAY=:99 xdotool mousemove X Y click 1`, `xdotool key ctrl+c`, `xdotool type "..."`
   - Hover requires **two small `mousemove`s** to trigger Qt hover delivery.
   - Screenshot: `DISPLAY=:99 import -window root /tmp/vis/out.png`
5. Crash diagnostics: run under `gdb -batch -ex run -ex bt --args ../build-linux/pob-qt ...`.
6. Clean up `pob-qt` (`pkill pob-qt`) before rebuilding.
