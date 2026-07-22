# Phase 14 — Packaging, Update & Distribution

**Status:** NOT STARTED
**Goal:** Turn the built app into a shippable, self-updating product on Windows
(and optionally Linux): a real installer, a replacement for the legacy auto-update
system, a full CI matrix, and the visual/parity gates run automatically.
**Depends on:** Phase 0 (deploy consolidation started there), Phase 10 (network for
update download).
**References to load:** [[build-test-packaging]] (primary), [[core-lifecycle]]
(legacy update system to replace), [[data-and-assets]] (520 MB TreeData / installer
size decision).

## Part 14.1 — Installer & standalone deploy

- [ ] Finalize `app/deploy-win-standalone.sh` (windeployqt + mingw dependency-
  closure fixpoint + `qt.conf` + clean-PATH smoke test already exist). Codify the
  `cmake --install` force-copy staleness workaround into CMake install so a third
  consumer doesn't ship stale binaries. (S)
- [ ] Build an installer (NSIS/MSI). Decide TreeData strategy: ship all 39 versions
  (520 MB, preserves loading any build) vs download-on-demand old versions (smaller
  installer, but the network tree-download fallback is disabled in code → needs new
  work). Recommend ship-all for v1. (M-L)
- [ ] Code signing (Windows). (M)
- [ ] Optional: Linux AppImage/flatpak (docker build already works). (L)

## Part 14.2 — Replace the auto-update system

- [ ] The legacy updater (`UpdateCheck`/`UpdateApply`/`LaunchInstall` + `manifest.xml`
  + `Update.exe` + `SpawnProcess`/`Restart`, sha1-diff against a remote manifest,
  zip bundles via `lzip`) is Windows/SimpleGraphic-specific. **Replace it** with an
  installer-native updater (Qt IFW / Sparkle-alike / GitHub-release check). (M-L)
- [ ] Keep the engine-side update UI inert but non-crashing: `launch.updateAvailable`/
  `updateProgress` still drive Main.lua buttons/toasts and the `CanExit("UPDATE")`
  path — stub them so they degrade cleanly. Decide what replaces the `first.run`/
  `installed.cfg`/`manifest.xml`-derived devMode + userPath selection. (M)
- [ ] If you keep manifest.xml for versioning, keep `update_manifest.py` working
  (regenerate on release); the dist layout differs from legacy parts (default/
  runtime/program/tree). (S)

## Part 14.3 — CI matrix & gates

- [ ] Linux CI job (docker `run-selftest.sh`) — extend the Phase 0 minimal job. (S)
- [ ] Windows CI build (msys2 mingw64 Qt6 or aqtinstall/MSVC — pick one blessed
  toolchain) + `pob-qt --headless` gate. (M)
- [ ] Retire/re-point the inherited upstream workflows (installer.yml, release.yml,
  beta.yml, update-simple-graphic.yml, test.yml container assumptions) so fork CI is
  honest and not red-noise. (S)
- [ ] Wire the **calc-parity gate** (Phase 0 harness) into CI: `busted` default task
  + the Qt-host TestBuilds diff. (S)
- [ ] Wire the **screenshot-diff gate**: fix or work around the Windows offscreen
  QPA crash (STATUS_STACK_BUFFER_OVERRUN) or run capture on a desktop-session
  runner; commit per-view reference PNGs (the `verify_style.py` default paths don't
  exist yet); add per-view SSIM thresholds instead of one global 0.85. (M)
- [ ] Per-tab QML smoke/interaction tests (Qt Quick Test or a scripted `--capture`
  driver walking all views + basic clicks) — catch the broken-view class the Lua
  selftest can't see. (M-L)

## Acceptance gate

- A clean machine (no MSYS2, no Qt) installs the app from the installer and it runs
  (the clean-PATH smoke test passes on a real fresh box, not just `PATH=System32`).
- An update is detected and applied end-to-end (or the replacement mechanism does).
- CI (Linux + Windows) builds, runs selftest, runs calc-parity, and runs the
  screenshot gate on push/PR; all green.
- No hardcoded machine paths remain (`deploy_deps.ps1` gone, `mainLog` fixed,
  `C:\msys64` parameterized).

## Notes

- Auto-update is a **product decision**, not just a port task — the distribution
  channel (GitHub releases? own server? installer framework?) determines the
  mechanism. Surface the decision to the user (it's an OPEN DECISION in STATUS).
- The offscreen-QPA crash is the main blocker for true headless visual CI; until
  fixed, gate visuals on a desktop-session runner.
