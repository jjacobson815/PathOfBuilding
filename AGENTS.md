# Path of Building (Qt6/QML Port)

## Architecture & App Disambiguation
- Ports legacy PoB (Lua + SimpleGraphic) to a **Qt6/QML C++ host** (`app/src/main.cpp` + `app/lua/pob_host.lua` -> `build-win/pob-qt.exe`) embedding the unchanged **LuaJIT (GC64)** calc engine (`src/`).
- **"Launch/run/open the app"** or **"start the GUI"** ALWAYS means the Qt/QML port (`build-win/pob-qt.exe`) unless **"legacy"** (`src/Launch.lua`) is explicit.
- Never emulate SimpleGraphic draw globals or modify `src/` calc logic. QML owns rendering over marshalled Lua tables; run binaries with `cwd = src/`.

## Build, Selftest & Headless Smoke
- **Windows (MSYS2 MinGW64 / Git Bash):** Prepend `PATH="/c/msys64/mingw64/bin:$PATH"` for `ninja` (prevents silent `FAILED: [code=1]` from missing `cc1plus.exe` DLLs) and `.exe` runs (prevents exit `127`):
  ```bash
  PATH="/c/msys64/mingw64/bin:$PATH" ninja -C build-win
  cd src && PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
    ../build-win/pob-selftest.exe "$PWD" "$PWD/../runtime" "$PWD/../app/lua/pob_host.lua"
  cd src && PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
    ../build-win/pob-qt.exe --headless
  ```
- **Linux / Cloud:** Run `tools/linux-selftest.sh` from repo root (`SKIP_DEPS=1` after first run). Exit `0` on `pob-selftest` and `pob-qt --headless` is the gate verdict.

## Progressive Context Protocol
1. Read `port-plan/STATUS.md` first (active phase, hard invariants, done log).
2. Read the named handoff (e.g., `port-plan/handoff/HANDOFF-phase6.md`), then ONLY the single active `port-plan/phases/PHASE-N-*.md`.
3. Load `port-plan/reference/*.md` only when directed by the active phase.
4. Avoid bulk-scanning `src/TreeData/`, `TreeData/`, `build-win/`, `dist/`, or `captures/`.

## Model Routing & Workspace `.agents/`
- **Orchestrator (Neon)** *(default)*: Phased port work (Neon plans, Hydrogen executes; escalates after 2 failed verification gates).
- **Gemini 4 Carbon / Orchestrator (Carbon)**: LuaJIT calc/marshalling invariants, C++<->Lua bridge (`LuaEngine.cpp`, `pob_host.lua`), deep audits.
- **Gemini 4 Hydrogen**: QML UI wiring, selftests, visual captures, docs. Fallback: **Claude Opus 5.5 / Sonnet 5.5**.
- Scoped rules: `.agents/rules/`. Skills: `.agents/skills/pob-selftest/`, `.agents/skills/pob-visual-capture/`.
