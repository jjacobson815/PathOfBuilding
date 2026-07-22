# Reference: Game Data & Assets

Legacy ships ~590 MB of data/assets. The port ships them verbatim next to the app
and loads them through host primitives the Qt bridge mostly already provides.

## What ships (all under `src/`)

- **`Data/`** — 65 MB, 132 Lua files. Nearly all GGPK-generated
  (`-- automatically generated`). Hand-written: `Global.lua`, `SkillStatMap.lua`,
  `Uniques/*.lua`, `Uniques/Special/{New,WatchersEye,race,BoundByDestiny}.lua`.
  Shipped pre-built but runtime-regenerable: `ModCache.lua` (2.3 MB),
  `QueryMods.lua` (1.5 MB), `TradeSiteStats.lua` (2.5 MB).
- **`TreeData/`** — 520 MB, **39 tree versions** (`treeVersionList` in
  `GameVersions.lua`; latest `3_28`). Per recent version (~15 MB): `tree.lua`
  (2.9 MB), `sprites.lua` (698 KB atlas metadata), sprite sheets incl.
  **`.webp`** (`ascendancy-3.webp`, `bloodline-3.webp` → **Qt needs the
  qtimageformats webp plugin**). Older versions differ in format (assets-in-tree
  vs `sprites.lua`, zoom-key nesting, CDN URLs) — `PassiveTree.lua` has 5+
  version-gated code paths. `TreeData/legion/` loaded for every tree instance.
- **`Assets/`** — 2.5 MB UI chrome (tooltip header strips per rarity incl. foil,
  slot icons, tree rings, `range_guide.png`, ascendancy jpegs).

## Load mechanism & order

Everything under `Data/` loads via host `LoadModule` (not `require`) — supports
varargs + return values. Module order (`Main.lua:17`): GameVersions → Common →
CalcFormat → Data → ModTools → ItemTools → CalcTools → PantheonTools →
BuildSiteTools. `Modules/Data.lua` eagerly builds one giant global `data` table
(~34 MB parsed at startup). **`Data/Global.lua` loads FIRST** — defines `colorCodes`
(the `^x` inline escapes the QML text renderer must honor), `ModFlag`/`KeywordFlag`
bitmasks (LuaJIT `bit.*`), `SkillType`, `GlobalCache`.

**Lazy loads (host-behavior contracts — do not break):**
- Only `latestTreeVersion` at startup; others via `main:LoadTree` on demand (cached
  in `main.tree[ver]` forever, no eviction).
- Unique/rare item DB built over multiple frames by a coroutine (`Main.lua:268-280`,
  `pairsYield`) — **requires the Qt frame loop to pump `OnFrame`**.
- `StatDescriptions/*` per-scope on first use.
- Timeless jewel LUTs lazy per jewel type.

## Timeless jewel LUTs (binary, zlib — not zstd, not real zips)

`Data/TimelessJewelData/`: `LegionPassives.lua`, `NodeIndexMapping.lua`, and 6
jewel LUTs shipped as `.zip` (BrutalRestraint/ElegantHubris/HeroicTragedy/
LethalPride/MilitantFaith) + `GloriousVanity.zip.part0..part4` (split for repo
limits, concatenated before inflate). **The `.zip` files are raw zlib streams
(magic `78 da`), inflated via host `Inflate()`. No zstd anywhere** (grep-verified).
Inflated: GV 51.5 MB, others ~3.6 MB. `DataLegionLookUpTableHelper.lua`:
`loadJewelFile` uses `NewFileSearch` (incl. `.zip.part*` glob) + mtime compare;
prefers an uncompressed `.bin` cache if newer, else inflates and **writes the
`.bin` next to the install** (fails silently under read-only Program Files → per-
launch re-inflate). `readLUT(seed, nodeID, jewelType)` does byte indexing; Elegant
Hubris seeds divided by 20.

## `src/Export/` — dev-only, NOT ported

A separate SimpleGraphic app ("Dat View") that regenerates `Data/*.lua` from the
game's `Content.ggpk` via `bun_extract_file.exe` (a Windows exe not in the repo).
**Stays a dev-only Windows tool.** League data refreshes run legacy Export +
copy regenerated `Data/`/`TreeData/` into the Qt distribution. Not a runtime port.

## Qt repo divergence (must resync — Phase 0)

- Qt `src/` is an **older upstream snapshot** than this legacy repo (~8 days).
  Legacy has `Data/ModScalability.lua` + `Data/TradeSiteStats.lua` and merged
  implicits into `ModItemExclusive.lua`; Qt still ships separate `Data/ModImplicit.lua`.
  **`Modules/*.lua` and `Data/*.lua` are coupled — resync as a unit.**
- Qt working tree has **5 timeless-jewel `.zip` LUTs locally deleted** (only GV
  parts remain); restore via `git checkout -- src/Data/TimelessJewelData/`.
- Most "130 files differ" between repos is **CRLF/LF only** — normalize before
  diffing; never let a `.gitattributes` change rewrite the binary `.zip` LUTs.

## Host primitives the data layer needs (Qt status)

`LoadModule`/`PLoadModule` (varargs + returns), `io.*` + `loadstring` (TreeData),
`NewFileSearch` (glob + `.part*` + `GetFileModifiedTime`), `GetScriptPath`,
`Inflate`/`Deflate` (zlib), `NewImageHandle` (`:Load(path,"ASYNC"/"CLAMP")`,
`:ImageSize`), `MakeDir`. **Already bridged** in `pob_host.lua` + `LuaEngine.cpp`
except real image loading (stubbed → tree sprites resolved as raw pixel sub-rects
in Lua) and the `.bin`/json-writeback path redirection.

## Port items (feed Phase 0 + Phase 4)

- Ship `Data`/`TreeData`/`Assets` verbatim; point `_SRC_DIR`/CWD at them (S).
- Resync Qt `src/` to the legacy snapshot; Modules+Data together (S, mechanical).
- Restore the 5 deleted timeless `.zip` LUTs (S).
- Redirect `.bin` inflate cache + TreeData json→lua writeback to a **writable
  user-cache dir** (installed app dir is read-only) (M).
- Enable WebP decoding (qtimageformats plugin) (S, build flag + deploy).
- Preserve lazy-loading contracts (frame-loop-pumped item-DB coroutine, per-version
  tree load) (M).
- Verify Inflate/Deflate against the real 51.5 MB GV LUT as a selftest (S).
- Confirm `^x` color codes render in the Qt text pipeline (data files embed them
  everywhere) (M).

## Risks

- **Repo drift is active + coupled** — plan a defined upstream-sync procedure per
  league (~quarterly); Modules+Data always move atomically.
- **Install-dir writes** (timeless `.bin`, TreeData json→lua, dev ModCache/QueryMods)
  fail silently under read-only install → per-launch re-inflate cost + trade-stats
  stop persisting.
- **Frame-loop coupling** of data loading — no `OnFrame` pump = item search never ready.
- **520 MB TreeData dominates installer size** — trimming old versions breaks
  loading older builds (network download fallback is disabled in code).
- **Memory** — all-eager Data + per-version accumulation + 51.5 MB GV can pressure
  LuaJIT GC; keep GC64 on x64.
