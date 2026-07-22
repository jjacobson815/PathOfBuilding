# Plan: Run pob-qt stably (RESOLVED)

## Status
- **Cross-compile of `pob-qt.exe` + `pob-selftest.exe` via MinGW-w64 on Linux: DONE** (WSL agent, using [`app/CMakeToolchainMinGW.cmake`](app/CMakeToolchainMinGW.cmake)). `dist/` bundle built; `utf8.dll` gap closed; Architecture.md updated.
- **`pob-qt.exe` verified working on REAL Windows** — user ran `pob-qt.exe --headless` from `dist/` → engine initialised, self-test ran. ✅
- **`pob-selftest.exe`: passes under Wine** (Linux paths exist there) **but FAILS on real Windows** (`INIT FAILED`) — see remaining bug below.
- **Docker build idea: rejected** — Alpine/musl vs Ubuntu 24.04 glibc; doesn't fix launch; and the Windows binary already runs.

## Root-cause summary (the "smoking gun" was half-right)
- The ONLY compile-time path macro is `POB_LUA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/lua"` ([`app/CMakeLists.txt:57`](app/CMakeLists.txt:57)) = `app/lua` on the build host. There is **NO `SRC_DIR`/`RUNTIME_DIR` macro** (prior agent's narrative was wrong).
- **`pob-qt` already resolves paths exe-relative first** ([`app/src/main.cpp:54-55`](app/src/main.cpp:54)): if `exeDir/src` exists next to the exe it is used, `POB_LUA_DIR` only as fallback. So a `pob-qt.exe` run from a correct `dist/` works on Windows.
- **`pob-selftest` lacks that check** ([`app/src/selftest.cpp:18-26,33`](app/src/selftest.cpp:18)) — only uses the baked `POB_LUA_DIR` and hardcodes `hostFile = POB_LUA_DIR + "/pob_host.lua"`. So cross-compiled `pob-selftest.exe` fails on real Windows (but passes under Wine, where the Linux path exists). **This is the one real code bug.**
- The engine does **not** hang — it errors out cleanly ([`app/src/LuaEngine.cpp:94-98`](app/src/LuaEngine.cpp:94)). The WSL "lockup/DC" was the separate WSLg-GPU issue (Part A), now sidestepped by running the Windows GUI natively.

## Remaining real bug (optional — app itself works)
Fix `selftest.cpp` to mirror `main.cpp`'s `resolveDir` + `resolveHost` (prefer `QCoreApplication::applicationDirPath()` + subdir, fall back to `POB_LUA_DIR` only when needed, and resolve `hostFile` the same way). This makes the cross-compiled selftest work on real Windows, not just under Wine.

## Steps (todo)
- [x] Decision: do NOT build in Docker (Alpine/musl incompatible with Ubuntu 24.04 glibc; doesn't fix launch crash)
- [x] Refine path diagnosis: pob-qt already resolves exe-relative (main.cpp:54-55); the real bug is pob-selftest.cpp lacking that check. No SRC_DIR macro; engine errors out cleanly (no hang)
- [x] Verify pob-qt.exe --headless from dist/ on REAL Windows - engine initialised and self-test ran (SUCCESS)
- [x] Cross-compile pob-qt.exe + dist/ bundle via MinGW-w64 (WSL agent); deliverable verified working on real Windows
- [ ] Fix selftest.cpp to mirror main.cpp's resolveDir + resolveHost so cross-compiled pob-selftest.exe works on real Windows (not just Wine)
- [ ] Optional hardening: make the POB_LUA_DIR fallback fail loud when the resolved path does not exist
- [ ] (If WSL GUI ever needed) Launch with software rendering QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 to avoid WSLg GPU crash
- [ ] Optional: investigate Lua engine errors from guitest_clean.log (PassiveTree.lua:78, TradeQuery.lua:55)
