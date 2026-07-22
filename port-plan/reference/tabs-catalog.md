# Reference: Tab & Screen Feature Catalog (parity checklist)

Every user-facing screen and its full feature surface. **Missing anything here =
a silently lost feature.** Paths are `src/Classes/` or `src/Modules/`. Use this as
the acceptance checklist for each tab's phase.

## App shell (`Modules/Main.lua`, 1758 lines)

Two modes `LIST`/`BUILD`; mode+args persisted in `Settings.xml <Mode>` (reopens
last build). Always-drawn bottom-left bar: **Options**, **About**, **Check for
Update / Update Ready**, "Dev Mode" label, version labels. Toast system
(`ToastNotification.lua`). F1 = context help for current tab. Startup URL arg =
import from build site.

**Options popup** (`Main.lua:818-1251`, responsive 1/2-col): connection protocol
(Auto/IPv4/IPv6), proxy (HTTP/SOCKS/SOCKS5H + URL), DPI scaling override, build
save path, node-power color theme, hex color overrides, weekly-beta opt-in, edge
search circles, show public builds, styled tooltips, animations, all-affix-sliders;
build options: thousands separators (+ custom sep chars), name-in-titlebar,
default gem quality/level, default item affix quality, show warnings, slot-only
tooltips, migrate eldritch implicits, invert slider scroll, dev-autosave disable.
**About popup** = changelog.txt + help.txt viewer (F1 target).
`Settings.xml`: Mode+Args, Accounts (OAuth token/refresh/expiry, per-account
sessionIDs), SharedItems, Misc (all options + buildSortMode + lastExportedWebsite).

## Build List screen (`Modules/BuildList.lua` + BuildListControl + PathControl)

Toolbar New / New Folder / Open / Copy / Rename / Delete + Sort dropdown
(Name/Class/Last Edited/Level) + search box. Rows show name or `>> folder` +
colored "Level N Ascendancy" (parsed cheaply from each XML `<Build>` header).
Double-click/Enter opens; F2 rename; Copy/Cut/Paste of builds+folders across
folders (auto-rename on collision); **drag build → folder / breadcrumb**;
Ctrl+N new; MOUSE4/5 path undo/redo. **PoB Archives public-builds pane**
(ExtBuildListControl) — currently hard-disabled via `if false` (confirm scope).

## Build mode shell (`Modules/Build.lua`, 1997 lines)

- **Top bar left:** `<< Back` (unsaved prompt), **Save**, **Save As**, build-name
  display (relocates to sidebar on narrow screens).
- **Top bar right:** points display (used/max asc/max) with tooltip (req level,
  act estimate, quest points, lab); auto/manual level toggle + level edit;
  **Class / Ascendancy / Secondary-ascendancy** dropdowns (tree-reset confirm with
  "Connect Path" option); **Loadouts dropdown** (`SyncLoadouts`: matches Tree/Item/
  Skill/Config set titles exactly or by `{tag}`; selecting swaps all four sets;
  "New Loadout"/"Sync"/"Help").
- **Side bar (312px):** tab strip (Import/Notes/Config/Tree/Skills/Items/Calcs/
  Party/Compare) + hotkeys (Ctrl+1..7, Ctrl+I, Ctrl+S, Ctrl+W/MOUSE4); **main-skill
  selector stack** (socket group / active skill / part / stages / mines / minion /
  minion-skill dropdowns; "Manage Spectres" button); **stat panel** (`TextListControl`
  from `BuildDisplayStats.lua`: per-stat fmt/color/condFunc/warnFunc, FullDPS rows,
  minion section, disabled-reason); **warnings** ("N Warnings" tooltip: over-cap
  points, insufficient Life/Mana/ES for costs, unreserved %, Vixen's, multiple
  Aspects, jewel limit, missing anoints).
- **Persistence:** savers map XML section → tab (`Config,Notes,Party,Tree,
  TreeView(=treeTab.viewer),Items,Skills,Calcs,Import`; legacy `Spec`→treeTab).
  Load order: Build first, Tree deferred last (jewels before tree), then PostLoad.
  `<Build>` attribs + denormalized `<PlayerStat>/<MinionStat>/<FullDPSSkill>`
  (computed from calc output — **saving requires a completed calc pass**),
  `<Spectre>`, `<TimelessData>`. `unsaved` = OR of all tab modFlags. Version-
  conversion popup for old builds; dev autosave to `~~temp~~.xml`.
- `AddStatComparesToTooltip`/`CompareStatList` — the universal "equipping/allocating
  this gives you:" diff (used by tree nodes, items, gems).

## Import/Export tab (`ImportTab.lua`, 1861 lines) — needs network

OAuth section (Authorize with PoE, 30 s timer, realm/league/char pickers, import
Passive-Tree-and-Jewels / Items-and-Skills with delete checkboxes) + account-name
section (needs `#1234` discriminator, profile-scrape for case fix, account history).
Import impl: `ImportPassiveTreeAndJewels` (masteries, jewel_data, tattoos, cluster
graphs, alt ascendancy, bandit/pantheon) + `ImportItemsAndSkills` (full item JSON
parser: rarity/slot maps, abyssal sockets, catalysts, influences, all mod types,
foils, socketed-gems→socket-groups with dedupe/merge, imbued supports, **reimport
state preservation** via reimport keys). Build Sharing: generate code, copy, export
dropdown (7 sites), share (upload → short link); import URL/code with mode dropdown
(this build / new build / **as comparison** → CompareTab). `<Import>` XML section.

## Notes tab (`NotesTab.lua`, 107 lines) — small

Full-tab rich EditControl (zoom via Ctrl +/-/0, undo). 13 color-code insert buttons
(NORMAL/MAGIC/RARE/UNIQUE/FIRE/COLD/LIGHTNING/CHAOS/STR/DEX/INT/DEFAULT). Show/Hide
Color Codes toggle. `<Notes>` = raw text.

## Config tab (`ConfigTab.lua`, 993 lines + `ConfigOptions.lua`)

Config sets + Manage popup. Search (Ctrl+F) + "Show All Configurations" toggle.
Controls generated from `ConfigOptions` varList; multi-column section flow.
**Conditional visibility engine** (ifNode/ifOption/ifCond/ifMult/ifStat/ifFlag/
ifSkill/... + implyCondList) depends on live `mainEnv` usage sets. Invalid-but-
hidden non-default options shown red with tooltip. `BuildModList` → modList/
enemyModList (the calc input). Bandit + Pantheon live here (mirrored to `<Build>`).
`ImportCalcSettings` migrates pre-Config builds. See [[calc-engine-contract]] for
the varControls-shim requirement.

## Tree tab (`TreeTab.lua` 2683 + `PassiveTreeView.lua` 1762 + `PassiveSpec.lua`)

Bottom bar (wraps to 3 lines): Spec dropdown (respec-gold tooltip) + Manage popup
(new/copy/delete/rename/reorder + **Import/Export Tree** URL, poeurl, poeplanner);
Compare checkbox+dropdown; Reset popup (tree/tattoos); Version dropdown + convert
(single/all); **Search** (Ctrl+F, Lua patterns, `oil:` anoint prefix, edge circles);
**Find Timeless Jewel** popup (6 jewel types, seed LUT search, multi-socket,
protect notables, fallback-weight generation, results w/ tree preview, **trade URL
builder**); Show Node Power + depth + power-stat dropdown (heat map); Show/Hide
**Power Report** drawer. Viewer: pan/zoom/alloc/path-trace/hover-preview; node
tooltips w/ stat-diff + gold cost; jewel radius rings + cluster subgraphs; hotkeys
(p heat map, Ctrl+D diff tooltips, Ctrl+C copy node, Shift socket compare, wiki
key); **right-click mastery → effect popup**, **right-click tattooable node →
tattoo popup**; compare overlay coloring. XML `<Tree>` + `<Spec>` + `<TreeView>`
(zoom/pan/search state). **Mostly rendered already — Phase 4 finishes the rest.**

## Skills tab (`SkillsTab.lua` 1351 + GemSelectControl)

Skill sets + Manage. Socket-group list (Ctrl+C/V copy/paste as text, Ctrl+click
enable/disable, Ctrl+right-click FullDPS, right-click set main). Gem options (sort
by DPS + stat dropdown, default level/quality, show support/legacy gems). Group
detail (label, socketed-in slot, enabled, FullDPS, count, **imbued support
selector**). Dynamic gem rows: delete, GemSelect (fuzzy match, DPS-sorted, tooltips),
level (+N from supports), quality (compare tooltip), enabled, count, error label,
per-Vaal enableGlobal1/2. `<Skills>` XML with full gem attribs (variantId, skillPart
+ *Calcs variants, minion fields). Legacy flat `<Skill>` support.

## Items tab (`ItemsTab.lua`, 4771 lines — the largest)

Item sets + Manage (useSecondWeaponSet). Slot panel: all baseSlots (Weapon 1/2 +
Swap each w/ 6 abyssal; Helmet/Body/Gloves/Boots/Belt w/ abyssal; Amulet, Rings 1/2,
conditional **Ring 3** and **Graft 1/2**, Flasks 1-5 w/ active checkboxes, Charms),
Weapon Set I/II buttons, jewel sockets from tree. All-items list (drag to slots/
shared/minion) + Uniques DB + Rare Templates DB (ItemDBControl, stat-sort) + Shared
items. Craft-item popup; custom/edit-text popup. **Display-item editor:** variants
(up to 6), socket color/link editors, **Enchant / Anoint(4) / Corrupt / Add Implicit**
popups, influences (2), quality/catalysts, cluster-jewel crafting, crafted prefix/
suffix affix dropdowns (up to 6, tier lists, roll sliders), **Add modifier** (bench/
essence/prefix/suffix/veiled/delve), **Add Crucible mod**, range sliders (single +
stacked). Full comparison tooltip vs equipped (dps/def diffs, jewel-radius spec
cloning). **Trade for these items** → PoB Trader (see Trade below). XML `<Items>`.

## Calcs tab (`CalcsTab.lua` 757 + `CalcSections.lua` 2520 + CalcBreakdownControl)

Grid of collapsible sections (responsive/portrait reflow, collapse state persisted).
First section "View Skill Details" with **independent `*Calcs` selectors** + "Show
Minion Stats" + **Calculation Mode** dropdown (Unbuffed/Buffed/In Combat/Effective).
Every stat cell → **breakdown popup** (hover transient / click pinned): text lines,
generic tables, reservation/damage-type/slot tables w/ item tooltips, mod tables
(value/stat/flags/tags/source), **inline mini tree viewer** for Tree sources,
**radius visualiser**. Search (Ctrl+F). `BuildOutput` + **PowerBuilder coroutine**.

## Party tab (`PartyTab.lua`, 1034 lines)

Import support-character buffs. Import code/URL box, destination dropdown (All /
Party Stats / Aura / Curse / Warcry / Link / EnemyConditions / EnemyMods), Import,
Append, Clear, Show Advanced Info (raw text vs summary), Disable Party Effects,
Rebuild All. 7 data buffers each with advanced EditControl + summary label.
`ParseBuffs` → ModLists. Export side (`setBuffExports`) when exported with "Export
Support" enabled. `<Party>` XML.

## Compare tab (`CompareTab.lua`, 4986 lines) — SCOPE-GATED

**Appears to be a fork-specific feature, NOT in upstream PoB, NOT in the savers
list (session-only, no XML).** Compare-with build selector + Import popup (code/URL/
file/folder) + Re-import Current + Remove; per-compare set + main-skill selectors.
Six sub-views: Summary (stat diff), Tree (overlay/side-by-side), Skills, Items,
Calcs (dual grid + "only differences"), Config (side-by-side interactive). **Compare
Power Report** (category attribution coroutine). Confirm with user before porting.

## Cross-tab interactions (parity-critical)

- `buildFlag` → full recalc; `outputRevision` drives tooltip caches; per-tab
  `modFlag` → unsaved indicator.
- Items↔Tree: jewel sockets are item slots keyed by nodeId; per-spec jewel memory;
  cluster jewels rebuild tree subgraphs; tattoos/radius affect item tooltips.
- Skills↔Items: socket groups reference slots; item-granted skills create locked
  groups; abyssal sockets import gems.
- Sidebar↔Skills/Calcs: **two independent main-skill selections** (plain + `*Calcs`).
- Import writes into spec/items/skills/config/level/title.
- Loadouts tie all four set systems by title/`{tag}`.
- Undo/redo per-tab. Drag-drop matrix across item lists/slots/shared/minion/build folders.
