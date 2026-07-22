# Reference: Build, Test, Run & Packaging

How to build/run/gate/ship the Qt port today, and what's missing for CI-quality
gating of a long port. Paths relative to the Qt repo
`PathOfBuilding/` unless noted.

## Build system

`app/CMakeLists.txt` — CMake ≥3.16, C++17, AUTOMOC/RCC/UIC. Deps: Qt6 (Core Gui
Qml Quick Svg QuickControls2), **LuaJIT via pkg-config**, ZLIB (Inflate/Deflate),
libcurl via pkg-config (the `l_pob_http` shim). Two targets: **`pob-qt`** (GUI;
main.cpp + LuaEngine + ~17 models + `qml/qml.qrc`) and **`pob-selftest`** (headless;
`POB_NO_GUI`, Qt6::Core only). Both define `POB_LUA_DIR` build-tree fallback;
runtime resolution is exe-relative first.

**Windows toolchain (live):** Ninja + MSYS2 mingw64 g++ (`C:/msys64/mingw64`),
**Qt 6.11.1**, LuaJIT from mingw64. Build dir `build-win/`.

### Build + run commands (Windows, today)

```bash
# dev loop (run_pob_fusion.bat equivalent)
export PATH=/c/msys64/mingw64/bin:$PATH
cmake -S app -B build-win -G Ninja
ninja -C build-win
cmake --install build-win --prefix .     # lays out dist/
cp build-win/pob-qt.exe dist/pob-qt.exe  # force-copy: cmake install-manifest staleness
./dist/pob-qt.exe
```

`QT_QUICK_CONTROLS_STYLE=Fusion` is forced (native Windows style rejects custom
`background` on themed controls → warning flood + UI lockup; also set in
`main.cpp`). CLI flags: `--headless` (runs selftest, exit code = pass), `--capture
[dir]` (screenshot every view), `--src`/`--runtime`/`--host`. **Binaries run with
cwd = `src/`** (engine opens data dirs relative to CWD).

## Selftest gate (the per-phase regression suite)

`app/src/selftest_checks.h` — one `pob_run_all_selftests(LuaEngine&)` shared by
`pob-selftest` and `pob-qt --headless` (**identical assertions in CI and GUI
binary**). Checks (each backed by a `pob_selftest*` Lua global): modes contain
LIST+BUILD; `viewList` = 9 entries; calc output Life/Mana/TotalDPS; zlib round-trip;
`require` lcurl.safe + lzip; SaveDB→LoadDB XML round-trip; build library scan;
LIST→BUILD flow; tree data/alloc/search; items; skills (incl. gem op); calcs;
config toggle; misc tabs (notes/import/compare/party). **This is a Lua-seam
functional gate, NOT a rendering or numeric-accuracy gate** — it passes green while
8/10 views are visually broken. Verified exit 0 as of the analysis.

## Visual regression tooling (half-wired)

- `pob-qt --capture [dir]` — iterates every view via `setActiveView`,
  `grabWindow()` → `<id>.png` + `_status.log`. **Offscreen QPA crashes on Windows
  (STATUS_STACK_BUFFER_OVERRUN)** → needs a real desktop session (or
  `POB_CAPTURE_OFFSCREEN=1` opt-in). This is the only gate that catches the
  broken-view class of bug — but it is not currently run as a gate.
- `tools/screenshot_diff.py` — mean/std blank detection, histogram correlation,
  luminance SSIM/MSE.
- `tools/verify_style.py` — SSIM gate (default 0.85). **Reference PNGs are NOT in
  the repo** (`skill_tree/legacy.png`, `import/legacy.png` missing) — the gate has
  likely never run end-to-end from a clean checkout.

## Calc-parity harness (inherited, host-agnostic — the real numeric gate)

`.busted` (both repos): `default` task runs `spec/` with `HeadlessWrapper.lua`, cwd
`src/`. `spec/System/` — **18 spec files in Qt repo vs 26 in legacy** (repos at
different upstream snapshots — pick one as the parity baseline). `spec/TestBuilds/
3.13/` — 5 build XMLs each paired with a generated `.lua` snapshot of
`build.calcsTab.mainOutput` (rounded 4 dp); `spec/GenerateBuilds.lua` regenerates
them. **This is the closest thing to a numeric calc-parity harness and is fully
host-independent** — the substrate for a Qt-host parity gate (load the same
TestBuilds XMLs through `LuaEngine`, diff `calcsTab.mainOutput` against the committed
snapshots). Runner: `docker-compose up` (image
`ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`). Upstream `test.yml` also
has a ModCache-drift check.

## Docker / Linux sandbox

`docker/Dockerfile.dev` (Alpine + Qt6 + LuaJIT pinned to the upstream commit +
luautf8) and `docker/run-selftest.sh` — the canonical phase gate: fresh cmake+ninja
into `/workdir/build`, `pob-selftest` (60 s timeout), `pob-qt --headless`, and an
offscreen GUI smoke (exit 124/137 = killed-no-crash = pass). Invoke:
`docker run --rm -v "$PWD:/workdir" -w /workdir pob-qt-dev sh docker/run-selftest.sh`.

## Packaging / distribution

- `app/deploy-win-standalone.sh` (wrapped by `deploy.ps1`): `cmake --install` +
  force-copy exe → `windeployqt --qmldir app/qml` → **ldd fixpoint loop** copying
  the mingw64 dependency closure (windeployqt doesn't bundle base mingw runtime) →
  writes `dist/qt.conf` → **clean-PATH smoke test** (`--capture` + grep `viewList
  count=9`). Also installs required native modules `runtime/lua-utf8.dll` +
  `lua51.dll` (omitting = blank UI). Resulting `dist/` = exe + ~40 Qt/mingw DLLs +
  qml/ + plugins + lua/ + src/ (full engine+assets) + manifest.xml.
- **Auto-update is NOT ported** — dist ships manifest.xml (version display) but no
  Update.exe and no host-side update support. Legacy flow = `update_manifest.py`
  (regen SHA1 manifest) → GitHub release → clients self-update via `UpdateCheck.lua`.
- `deploy_deps.ps1` (repo root) — **stale/dangerous**: hardcodes the pre-move repo
  path `c:\Users\User\source\repos\PathOfBuilding\dist`. `main.cpp` `mainLog` has
  the same stale path. Delete/parameterize.

## The big gaps for gating a long port

1. **Version control** — the entire port (`app/`, `TreeData/`, plans, tools) is
   **untracked**; `src/` has 6 modified engine files + 5 deleted data zips. No CI
   possible until committed. (Phase 0.)
2. **No CI builds the Qt app** — all 9 workflows are inherited upstream and target
   SimpleGraphic. Add a Linux docker job (nearly free) + a Windows msys2/aqtinstall
   job. (Phase 14; a minimal version in Phase 0.)
3. **No numeric calc-parity gate** wired for the Qt host (TestBuilds snapshots are
   the substrate).
4. **Working Windows headless capture** (offscreen crash) + versioned reference
   images + per-view thresholds.
5. **Per-tab QML smoke/interaction tests** (Qt Quick Test) — the broken-view class
   is invisible to the selftest.
6. **Packaging pipeline** (installer, code-signing, auto-update replacement).
7. **Remove hardcoded machine paths** (`deploy_deps.ps1`, `main.cpp` mainLog,
   `C:\msys64` in `run_pob_fusion.bat`, `/workdir` Docker outputs).

## Recommended gate ladder (apply at every phase boundary)

1. `pob-selftest` exit 0 (functional Lua seam). **Mandatory.**
2. `pob-qt --capture` on a desktop session; diff changed views vs the previous
   boundary's captures (catch broken/blanked views). **Mandatory once Phase 0
   commits a capture baseline.**
3. `busted` calc-parity (when `src/` changes or per release).
4. Manual GUI smoke of the phase's feature.
