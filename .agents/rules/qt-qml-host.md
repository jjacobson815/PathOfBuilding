---
trigger: glob
globs: "app/**/*"
---

# Qt6 / QML Host Conventions & Hard Invariants

These invariants govern all C++ and QML work under `app/` and override older documents in the repository.

## Rendering & Architecture
- **Do NOT emulate SimpleGraphic draw globals.** QML owns all rendering; draw globals stay stubbed. Re-author each view in QML over marshalled plain Lua tables.
- **No frame loop.** Everything legacy `buildMode:OnFrame` (`Build.lua`) recomputed per frame is dead code under Qt (`unsaved`, skill-select refresh, class/ascendancy resync, Ctrl hotkeys). Port each to an explicit bridge call or QML `Shortcut` — never reintroduce a frame pump.
- **Legacy Control side-effect caveat:** Bridge calls that end in `runCallback("OnFrame")` (mode switches, `pob_loadBuildXML`) still execute `ProcessControlsInput` once across the legacy Control tree. Do not assume legacy controls are inert in selftest state snapshots (e.g., auto-level `EstimatePlayerProgress()` can mutate `characterLevel`).
- **Sprite UVs:** `node.sprites[1..4]` are **normalised UVs** (`coords.x / sheet.width`), never pixels. De-normalise against sheet dimensions measured via `pob.imageSize` (`sheetInfo` in `app/lua/pob_host.lua`) and read `sw`/`sh` from sprite integer `width`/`height`.

## QML & Qt Platform Gotchas
- **Never name a QML component property `data`.** It shadows `QtObject`'s default children list and silently swallows all declared children with zero QML warnings.
- **Empty Lua tables marshal as `QVariantMap`, not `QVariantList`.** `model.length` evaluates to `undefined` rather than `0`; guard `int` bindings accordingly. Also guard `parent` being `null` during component construction inside a `Layout`.
- **Text measurement vs positioning:** Use `TextMetrics` (`.tgf` atlas for legacy measurements like ellipsis/column widths), but position Qt-painted TTF text using a real layout box and `horizontalAlignment` — never `x: anchor - measuredWidth` arithmetic.
- **No clipboard on Qt `offscreen`:** `QClipboard::setText` segfaults under `pob-qt --headless`. Selftests must never reach the real `Copy()` path.
- **QML is compiled into qrc:** Always rebuild (`ninja -C build-win` or `ninja -C build-linux`) after any QML edit before running captures or interactive checks. `--headless` does not load QML.
- **Dynamic `setContextProperty` tokens vs `qmllint.exe`:** Static `qmllint.exe` cannot validate dynamically injected host properties (`theme.*`, `luaEngine.*`). Cross-check every `theme.<token>` reference against `Q_PROPERTY` declarations in `app/src/Theme.h` and always run `pob-qt.exe --capture` after QML edits to catch `[undefined] to QColor` or runtime binding errors.

## Build, Editing & Runtime Hygiene
- **Binaries run with `cwd = src/`** so the embedded engine resolves data paths relative to CWD.
- **Windows `run_command` shell:** Antigravity's Windows `run_command` defaults to PowerShell—invoke bash snippets explicitly via `C:/Program Files/Git/bin/bash.exe -lc "..."` rather than mixing `FOO=bar cmd` or bash `for` loops into raw PowerShell.
- **Windows MinGW64 `PATH`:** Prefix `PATH="/c/msys64/mingw64/bin:$PATH"` for both `ninja` (prevents silent `FAILED: [code=1]` from missing `cc1plus.exe` DLLs) and executing `pob-selftest.exe` / `pob-qt.exe` (prevents exit `127`).
- **`app/src/selftest_checks.h` line endings:** This file contains mixed CRLF and LF regions; match exact per-region context when editing.
- **Baselines are Windows captures:** Only re-baseline `app/tests/capture-baseline/*.png` on Windows; Linux captures differ in font rendering across every view.
