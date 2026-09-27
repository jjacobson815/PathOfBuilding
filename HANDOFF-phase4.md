> **SUPERSEDED 2026-09-27.** The gate below was run on Linux (`tools/linux-selftest.sh`,
> both binaries exit 0) and Phase 4 is done — see `port-plan/STATUS.md`.

# Handoff — Phase 4 (Part 4.1), 2026-08-19

## FIRST COMMAND — the gate was never run after the final rebuild

    cd C:/Users/User/source/repos/pob_workspace/PathOfBuilding
    PATH="/c/msys64/mingw64/bin:$PATH" QT_FORCE_STDERR_LOGGING=1 \
      ./build-win/pob-selftest.exe \
      "C:/Users/User/source/repos/pob_workspace/PathOfBuilding/src" \
      "C:/Users/User/source/repos/pob_workspace/PathOfBuilding/runtime" \
      "C:/Users/User/source/repos/pob_workspace/PathOfBuilding/app/lua/pob_host.lua"
    echo "EXIT=$?"

Then `./build-win/pob-qt.exe --headless` the same way. Exit code is the source
of truth. Nothing below is proven until this passes.

## ENV GOTCHA (new, cost ~20 min this session — add to STATUS.md)

`ninja` fails with EVERY compile step reporting `FAILED: [code=1]` and **zero
diagnostics** unless `/c/msys64/mingw64/bin` is on PATH. Cause: `cc1plus.exe`
cannot resolve its own DLLs and exits 127; gcc swallows that as a bare failure.
It is NOT Smart App Control and NOT a code error. Always build as:
`PATH="/c/msys64/mingw64/bin:$PATH" ninja`. Same PATH prefix is needed to RUN
`pob-selftest.exe` / `pob-qt.exe` (without it: exit 127).

`app/src/selftest_checks.h` has MIXED line endings (some CRLF, some LF, even
inside one statement). Exact-string edits must match per-region. `pob_host.lua`
is now all-LF in the working tree (git normalises, so no content diff).

## What landed (all uncommitted, all in the working tree)

1. **Alloc-checksum linearity fix** — `app/lua/pob_host.lua`. The revision
   checksum was `sum((id*K) % M) % M`, which is LINEAR: the constant factors out
   and every sum-preserving swap still collides. Replaced by a new file-scope
   `foldAllocId(acc, id)` — scatter, xor-fold high half onto low, combine with
   xor (commutative + involutive). The stale comment citing 100+201==101+200 as
   "the case Knuth's scatter fixes" is corrected — that is the case it did NOT fix.
2. **Selftest coverage for that class** — `pob_selftestTreeInteract` now collects
   ALL allocatable frontier nodes (sorted, so failures reproduce), searches them
   for two DISJOINT sum-preserving pairs, and does a real two-node swap
   (`swap2Ok/swap2SumsEqual/swap2CountsEqual/swap2Restored/swap2Skipped`), plus a
   fixture-independent direct check (`checksumNonLinearOk` over {100,201}/{101,200},
   {5000,5003}/{5001,5002}, {1,5,6}/{2,3,7}; `checksumCommutativeOk`). All are in
   `res.ok`, so a stale binary still gates on them — only the printout is new.
3. **docker/Dockerfile.dev** — added `qt6-qtimageformats-dev` with the reason
   (silent blank webp art; CI's offscreen smoke test treats timeout as success).
4. **THE MAIN ITEM — sprite-UV consumption moved to match the real ImageSize().**
   The C++ `pob.imageSize` primitive and `NewImageHandle:Load` filename retention
   were ALREADY in the tree from the prior session; the consumer side was NOT —
   that was the dangerous half-applied state. Now:
   - `node.sprites[1..4]` are read as NORMALISED UVs (they are built at
     PassiveTree.lua:288-297 as `coords.x / sheet.width`), de-normalised back to
     pixels against the sheet measured through `pob.imageSize`. `sw/sh` come from
     the sprite data's own integer `width`/`height`, not a quotient multiplied out.
   - Guard for the ENGINE's division by a missing sheet (0x0 -> inf/nan UVs):
     bounds test rejects both, sprite is dropped rather than drawn absurdly.
   - Mastery path: sub-rect is now selected BY KEY (`ms[sheetKey]`) so the rect
     and the atlas it is sampled from always agree; the old `firstRect()` took an
     arbitrary rect but kept a fixed sheet name.
5. **Sprite probing memoised** — new file-scope `sheetInfo(ver, base)` (path +
   pixel dims, negative results cached). Replaces the per-node/per-group
   `io.open` in `nodeSprite`, `nodeFrame` and `resolveGroupBackground`: ~7,400
   probes per `pob_getTreeData` -> ~15. Probe order `<ver>/<base>` then
   `TreeData/<base>` — same as before; verified no atlas basename exists in both.
6. **Dead code removed** — `resolveAsset` (zero callers, and read `tree.assets`,
   which is stale on 3_20+), `firstRect` (no longer used), and the hand-rolled
   `pngSize`/`PNG_SIG` PNG-IHDR reader (existed ONLY because ImageSize was
   stubbed; `sheetInfo` measures any format now).
7. **New gate evidence** — `pob_selftestTreeRender` now checks every resolved
   sprite against the atlas it names: `sw >= 1` (the tell for reading normalised
   UVs as pixels — every rect would be a sub-pixel speck) and `sx+sw <= atlasW`
   (the tell for de-normalising against the wrong sheet). Returns
   spriteChecked/spriteBad/spriteIcons/spriteFrames/spriteGroupBgs/spriteMinW/
   spriteMaxW/spriteBadSample; `spriteBad == 0` and all three counts > 0 are in
   `ok`. `selftest_checks.h` prints them all.

## NOT done — deliberately

- **`spec:AddUndoState()` in pob_allocNode/pob_deallocNode** (tree undo is inert;
  legacy PassiveTreeView.lua:459/:489). Cheap, next up.
- **TreeScene / QQuickItem migration** — explicitly out of scope, needs a fresh
  session. Do not half-land it.
- **Connector arcs.** `connector.vert` is now CORRECT in the engine (ImageSize
  feeds `art.width * 2 * 1.33` at PassiveTree.lua:956), but `pob_getTreeData`
  still exports only endpoints (x1,y1,x2,y2), so QML still draws straight lines.
  Exporting 16 floats x ~9000 connectors has a real marshalling cost — decide
  with the renderer strategy, not before.

## Still owed by the wrap-up routine (I ran out of budget)

- Tick completed boxes in `port-plan/phases/PHASE-4-tree-tab.md` + add a
  "Session log — 2026-08-19 (part 2)" entry with the gate output as evidence.
- Add to STATUS.md top section: the mingw PATH gotcha above, and the invariant
  that **`node.sprites[1..4]` are normalised UVs — never read them as pixels**.
- Update the Part 4.1 progress summary (the `_gbByVersion` line is now stale:
  that table AND `pngSize` are both gone).
