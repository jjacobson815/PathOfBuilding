# Reference: Text-Rendering Subsystem (fonts, metrics parity, color codes)

The single most pervasive cross-cutting concern: every visible string flows through
the legacy `DrawString`/`DrawStringWidth`/`DrawStringCursorIndex` pipeline. Getting
this wrong silently breaks visual fidelity **and** the layout math that EditControl,
DropDown, ListControl, and Tooltip depend on. Verified against the upstream
SimpleGraphic source (`github.com/PathOfBuildingCommunity/PathOfBuilding-SimpleGraphic`).

## Correction to earlier assumptions

- It is **not** three fonts. `fontMap` = `{FIXED, VAR, VAR BOLD, FONTIN SC, FONTIN
  SC ITALIC, FONTIN, FONTIN ITALIC}` — the **FONTIN family is used at 104 sites**
  (item titles, gem tooltips, tree labels: `ItemsTab.lua` 56, `GemTooltip.lua` 29,
  `PassiveTreeView.lua` 15, ...). Default font when the arg is omitted/nil is
  **FIXED**.
- `DrawStringWidth`/`DrawStringCursorIndex` are **NOT permanently stubbable** (this
  corrects [[00-architecture]]/[[host-api-contract]]). The *draw* globals
  (`DrawString`/`DrawImage`/`SetDrawColor`) stay stubbed — QML draws — but the two
  *measure* globals must become **real**, because ported control layout math calls
  them.

## The fonts (already bundled — do not re-source)

SimpleGraphic does **not** rasterize TTF at runtime. It loads pre-baked bitmap
atlases: a `.tgf` metrics file + one `.tga` per pixel height. **These exact assets
already ship in the Qt repo** at `runtime/SimpleGraphic/Fonts/` (119 files):
`Liberation Sans.tgf`, `Liberation Sans Bold.tgf`, `Bitstream Vera Sans Mono.tgf`,
`Fontin.tgf`, `Fontin Italic.tgf`, `Fontin SmallCaps.tgf`, `Fontin SmallCaps
Italic.tgf`, each with 16 `.tga` atlases (heights 10,12,14,16,18,20,22,24,26,28,32,
36,40,48,56,64). Legacy name → real font: VAR→Liberation Sans, VAR BOLD→Liberation
Sans Bold, FIXED→Bitstream Vera Sans Mono, FONTIN*→Fontin family.

`.tgf` format: repeated `HEIGHT <h>;` blocks, each with `GLYPH x y width spLeft
spRight;` lines. **Only ASCII 0-127 are stored**; non-ASCII renders as a `[U+XXXX]`
tofu placeholder in a reduced font size.

**Current Qt state (the defect):** `Theme.cpp:80` hardcodes `m_fontFamily =
"sans-serif"` — one family, no bold, no monospace, no bundled font; QML binds
`font.family: theme.fontFamily` with no fixed/bold variant. No
`QFontDatabase::addApplicationFont` anywhere. All text falls back to the system
`sans-serif`, and monospace column alignment is impossible.

**Licenses:** Liberation (OFL) and Bitstream Vera (permissive) are freely
bundleable. **Fontin (exljbris) requires an Extended License to bundle with an
app** — a legal risk for the 104 item/gem/tree sites (see decision below).

## Metrics parity (the load-bearing algorithm)

`r_font_c::StringWidthInternal` (legacy `engine/render/r_font.cpp`): choose the
atlas via nearest baked height (PoB usually requests an exact baked size → scale
1.0, pure integers); split on `\n`, return max line width; per char: skip `^`
escapes inline (advance 2 or 8, add nothing), tab = 4×space, codepoint ≥128 = tofu,
else `advance = (glyph.width + spLeft + spRight) * scale`; **`width = ceil(width)`
after EVERY character** (cumulative per-glyph rounding). `StringCursorInternal`
walks the same way to return the char index at a pixel x (and line by y) — caret
hit-testing.

**This is why `QFontMetrics` cannot substitute:** it does not reproduce integer
per-glyph-ceil against hinted bitmap atlases; it will drift 1–several px per string,
breaking caret hit-testing, ellipsis clip points, and dropdown/tooltip auto-width.

**Dependent layout sites (103 `DrawStringWidth` / 8 `DrawStringCursorIndex`):**
EditControl caret/selection (`EditControl.lua:233/235/317/495`, font default FIXED),
ListControl ellipsis (`ListControl.lua:221`), DropDown auto-width
(`DropDownControl.lua:541/552`), Tooltip columns (`Tooltip.lua:166/302/...`),
GemSelectControl (`116/120/321/394/541/552`), item-name clip
(`ItemsTab.lua:1974-1975`).

**Required:** a C++ `TextMetrics` class that loads `runtime/SimpleGraphic/Fonts/
*.tgf` and reproduces `r_font_c` exactly (per-glyph ceil, `width+spLeft+spRight`,
atlas selection + scale, tab=4×space, tofu ≥128, inline escape skip). Expose it to
Lua (real `DrawStringWidth`/`DrawStringCursorIndex`, replacing the
`pob_host.lua:78-83` stubs that return 1/0) **and** to QML (a `TextMetrics` QObject
with `Q_INVOKABLE int width(h,font,text)` / `cursorIndex(...)`). Use QFont only for
*rendering* (`setPixelSize(height)`), never for *measurement*.

## Color-code markup

Parser (`IsColorEscape`, `common.cpp:201-218`): `^` + digit → `^0..^9` (2 chars);
`^x`/`^X` + 6 hex → `^xRRGGBB` (8 chars, case-insensitive); anything else → literal
`^` (there is **no `^^` escape**). Each `DrawString` starts in the `SetDrawColor`
pen color; an inline escape changes color for the rest of the string; convention
uses `^7` (white) as "reset to default".

**The exact `^0..^9` palette** (`common.cpp:188-199` — the values that were
"missing"):

| ^0 black #000000 | ^1 red #FF0000 | ^2 green #00FF00 | ^3 blue #0000FF | ^4 yellow #FFFF00 |
|---|---|---|---|---|
| ^5 magenta #FF00FF | ^6 cyan #00FFFF | ^7 white #FFFFFF | **^8 gray 0.7,0.7,0.7 (#B2B2B2)** | **^9 darkGray 0.4,0.4,0.4 (#666666)** |

Use `QColor::fromRgbF(0.7,...)` / `fromRgbF(0.4,...)` for ^8/^9 to match exactly.

**Current Qt state:** no inline markup renderer exists on the Qt side.
`Theme.cpp:parseColor` handles a single leading token only and would **misparse**
`^0..^9` (treats "^7" as one hex char) — do NOT reuse it for markup. The named
`colorCodes` table (`Data/Global.lua`, all `^xRRGGBB`) is consumed fine for rarity
colors. **Missing:** one shared parser turning a PoB string into ordered
`(QColor, text)` runs, honoring `^0..^9` + `^xRRGGBB` + carry-forward default.

## Where this lands in the plan

- **Phase 1** owns this subsystem (it gates every text-bearing component): bundle
  fonts + `QFontDatabase::addApplicationFont`; extend `Theme` with `fontVar`/
  `fontVarBold`/`fontFixed` (+ Fontin if licensed); build the `TextMetrics` class
  and wire real `DrawStringWidth`/`DrawStringCursorIndex`; build the shared color-
  markup parser + QML rich-text rendering. See Phase 1 Part 1.2a.
- EditControl/DropDown/List/Tooltip/GemSelect (Phase 1/5) must call `TextMetrics`,
  not QFontMetrics.

## Risks / decisions

- **Fontin licensing (decide early)** — bundle TTFs with an exljbris Extended
  License, reuse the bundled atlases (legal question, not technical), or substitute
  an OFL small-caps face and accept item-name visual drift. Liberation + Bitstream
  Vera are clear.
- **ASCII-only atlases vs TTF** — legacy renders non-ASCII as tofu; a TTF path would
  render accented/CJK names correctly but at different widths → measure and render
  must use the same policy (recommend the atlas approach for parity, or accept the
  improvement and re-derive dependent layouts).
- **height→pixelSize** and **DPI/scaling** need a calibration pass — QFont pixelSize
  ≈ em, not atlas cell height; legacy applies a separate UI scale on top of integer
  metrics (currently stubbed to 1).
- **Pin the `.tgf` atlas set** — regenerating atlases with different hinting changes
  metrics; version them.
