# Style Fix — Pass 2 Plan

## Root-Cause Diagnosis (from investigation)

- **No `Theme.qml` exists.** The QML `theme` object *is* the C++ `Theme` singleton
  (`app/src/Theme.cpp`, `init()` at line 30), which loads `uiTheme.colour` from
  `src/Modules/UITheme.lua` via `LoadModule`. There is **one** color pipeline, not two
  disconnected systems. The "two disconnected color systems" hypothesis is incorrect —
  the real disconnect was the deploy gap below.
- **Stale binary = root cause of "no theme applied".** `ninja` builds
  `build-win/pob-qt.exe`. `run_pob_fusion.bat` launches `dist\pob-qt.exe`. The `install()`
  rules in `app/CMakeLists.txt:92-97` copy the binary + `src/` + `lua/` into top-level
  `dist`, but the first pass never ran `cmake --install`. So the running app used a
  pre-first-pass binary; all first-pass changes (theme, tree sprites, zoom split, layout)
  were never deployed. This also explains "tree nodes still outline-only" and "zoom still
  laggy" — those fixes existed in source but not in the deployed binary.
- **Sprite path is correct.** `resolveAsset` (`app/lua/pob_host.lua:1190`) builds
  `_SRC_DIR/TreeData/<ver>/<base>`; `_SRC_DIR` = exe-relative `src` (main.cpp chdir's to
  dist/src). Files exist (e.g. `src/TreeData/3_22/skills-3.jpg`). After deploy, sprites
  render; the "faint outline dots" was the fallback circle in the stale binary.
- **Zoom split is in place.** `transformChanged` vs `viewChanged`; canvas repaints only on
  `viewChanged`/`searchChanged` (`app/qml/main.qml:431-446`). After deploy, zoom is smooth.
- **All 10 views exist in QML** (treeView, skillsView, itemsView, calcsView, configView,
  notesView, importView, compareView, partyView, + LIST mode). "Config/data grids missing"
  was a stale-binary artifact.

## Functional Bug Fix (independent of theming)

- **LIST page clipping** (`app/qml/main.qml:1381-1385`): the LIST `ColumnLayout` is a direct
  child of the `StackLayout` (`app/qml/main.qml:159`) but uses `anchors.margins: 12`, which
  `StackLayout` ignores (it sets child geometry directly). Result: content touches window
  edges (right columns off-screen; left text clipped to "uild Library"). The BUILD page
  `RowLayout` (`app/qml/main.qml:165`) correctly uses `Layout.fillWidth/fillHeight` with no
  anchors, which is why it renders fine.
  - **Fix:** replace `anchors.margins: 12` with
    `Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 12; Layout.bottomMargin: 12`.

## Theme Refinement (refined "Cyber Citrus" palette)

Map the refined palette onto the single pipeline:

| Semantic          | Hex      | UITheme.lua key            | Theme.cpp property        |
|-------------------|----------|----------------------------|---------------------------|
| Background        | #0F172A  | sideBarBg / topBarBg       | m_background / m_titleBar |
| Accent (primary)  | #A3E635  | navActiveAccent            | m_accent                  |
| Accent (alt)      | #22C55E  | accentAlt (NEW)            | m_accentAlt (NEW)         |
| Secondary action  | #06B6D4  | groupHeader                | m_section                 |
| Text/Base         | #FFFFFF  | (UI default)               | m_text                    |

Changes:
1. `src/Modules/UITheme.lua`: set `navActiveAccent = {0.639, 0.902, 0.208}` (#A3E635);
   add `accentAlt = {0.133, 0.773, 0.369}` (#22C55E).
2. `app/src/Theme.cpp` + `Theme.h`: add `m_accentAlt` + `Q_PROPERTY(QColor accentAlt ...)`
   + parse `colour.accentAlt` in `init()`; map `m_accentAlt = parseColor(colour.value("accentAlt"))`.
3. (Optional polish) Use `theme.accentAlt` for positive values in calcsView/itemsView.

## Critical Deploy Step (was missing in pass 1)

From repo root, with MSYS2 on PATH:

```
set PATH=C:\msys64\mingw64\bin;%PATH%
cd build-win
ninja
cmake --install . --prefix "C:/Users/User/source/repos/PathOfBuilding"
```

This copies `pob-qt.exe`, `src/`, `lua/` into top-level `dist` (the folder
`run_pob_fusion.bat` launches). Without this, changes are invisible.

## Verification

- `ninja` build clean; `pob-selftest` headless pass.
- Launch via `run_pob_fusion.bat`; confirm: theme applied (lime accents, cyan secondary,
  white text on #0F172A), tree nodes show sprite frames + background, zoom smooth, LIST
  page inset 12px (no clipping), all 10 views render.

## Wiki

- Update `.obsidian-vault/01_Wiki/00_Overview/Architecture.md` (last_modified + theme/tree/
  clipping notes) per repo rules.
