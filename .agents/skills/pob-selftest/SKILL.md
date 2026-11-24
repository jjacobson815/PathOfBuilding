---
name: pob-selftest
description: >-
  Build pob-selftest and pob-qt, run Windows MinGW64 or Linux verification gates,
  lint QML, and execute ad-hoc Lua probes against the embedded LuaJIT engine.
---

# PoB Qt Port — Build, Selftest & Headless Smoke

Use this skill after any C++, QML, or `app/lua/` change to run the mandatory verification gate (`pob-selftest` exit `0` + `pob-qt --headless` exit `0`).

## Pre-Build Hygiene
Terminate any running `pob-qt` process before rebuilding so binary replacement succeeds cleanly:
- **Windows (PowerShell):** `Stop-Process -Name pob-qt -ErrorAction SilentlyContinue`
- **Linux:** `pkill pob-qt || true` *(never use `pkill -f` with a pattern that appears in your own command line)*

## Windows Gate (Git Bash / MSYS2 MinGW64)
Always prepend `/c/msys64/mingw64/bin` to `PATH`. Without it, `ninja` reports bare `FAILED: [code=1]` with zero compiler diagnostics (`cc1plus.exe` missing DLLs) and `.exe` runs fail with exit `127`.

1. **Rebuild (required after C++ or QML edits — QML is compiled into qrc):**
   ```bash
   PATH="/c/msys64/mingw64/bin:$PATH" ninja -C build-win
   ```
2. **Optional QML lint:**
   ```bash
   PATH="/c/msys64/mingw64/bin:$PATH" /c/msys64/mingw64/bin/qmllint.exe app/qml/<changed-file>.qml
   ```
3. **Run `pob-selftest.exe` and `pob-qt.exe --headless` from `cwd = src/`:**
   ```bash
   cd src
   PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
     ../build-win/pob-selftest.exe "$PWD" "$PWD/../runtime" "$PWD/../app/lua/pob_host.lua"
   echo "SELFTEST_EXIT=$?"

   PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
     ../build-win/pob-qt.exe --headless
   echo "HEADLESS_EXIT=$?"
   ```

## Linux / Cloud Gate
Run from the repository root (installs apt deps on Ubuntu 24.04 if needed, builds `utf8.so`, `pob-selftest`, and `pob-qt` into `build-linux/`, and runs both binaries under `QT_QPA_PLATFORM=offscreen`):
```bash
tools/linux-selftest.sh
# Or skip apt/dependency installation after first run:
SKIP_DEPS=1 tools/linux-selftest.sh
```

## Ad-Hoc Lua Probe Against the Real Engine
Create a small probe script that loads `pob_host.lua` first, prints a `PROBE ... ok=true` line, and exits with `os.exit(ok and 0 or 1)` (either at the end of the script or in its first-check hook) so execution exits cleanly without falling through to unrelated `pob_run_all_selftests` entries:
```lua
_POB_LUA_DIR = _SRC_DIR .. "/../app/lua"
dofile(_POB_LUA_DIR .. "/pob_host.lua")
-- probe assertions / diagnostics here
local ok = true
print("PROBE example ok=" .. tostring(ok))
os.exit(ok and 0 or 1)
```
- **Linux:**
  ```bash
  cd src
  ../build-linux/pob-selftest "$PWD" "$PWD/../runtime" /tmp/probe.lua
  ```
- **Windows (MinGW64):**
  ```bash
  cd src
  PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
    ../build-win/pob-selftest.exe "$PWD" "$PWD/../runtime" ../_tmp_probe.lua
  ```
- **Concurrent `/swarm` or Git worktree (`workspace: "share"`) probes on Windows:** Copy the main repo's `build-win/pob-selftest.exe` to a worktree-local `_tmp_selftest.exe` before running so concurrent probes never hold an OS file lock against `ld.exe` during `ninja -C build-win` or break when `selftest_checks.h` gains new compiled checks. Delete both `_tmp_selftest.exe` and `_tmp_probe.lua` before staging/committing:
  ```bash
  cp ../main-repo/build-win/pob-selftest.exe ./_tmp_selftest.exe
  cd src && PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
    ../_tmp_selftest.exe "$PWD" "$PWD/../runtime" ../_tmp_probe.lua
  cd .. && rm -f _tmp_selftest.exe _tmp_probe.lua
  ```

## Gate Verification Checklist
- Both `pob-selftest` and `pob-qt --headless` exit with code `0` (exit code is the sole verdict).
- Clean-checkout safety: verify new selftests do not assume gitignored `src/Settings.xml` exists (unset options read as `nil`).
- Offscreen safety: selftests must never call real `QClipboard::setText` / `Copy()`, which segfaults under Qt `offscreen`.
- Remember `--headless` does **not** load QML; run `pob-visual-capture` after any QML change.
