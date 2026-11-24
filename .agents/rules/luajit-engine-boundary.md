---
trigger: glob
globs: "src/**/*.lua, app/lua/**/*.lua"
---

# LuaJIT Engine & Bridge Boundary Invariants

These invariants govern all Lua code across the embedded `src/` engine and the `app/lua/` host bridge.

## Engine Immutability & Host Seams
- **Do NOT modify `src/` calc logic.** Only `app/` and the bridge seam (`app/lua/pob_host.lua`, `app/lua/pob_*.lua`, `app/src/LuaEngine.cpp`) may change.
- **Sanctioned `src/` seams:** Only four host contract seams exist in `src/` (`viewList` registry, `sideBarCollapsed`, `TotalDotDPS`, `UITheme.lua`). Do not expand this set without logging an explicit decision in `port-plan/STATUS.md`.
- **Keep LuaJIT (GC64 on x64).**
- **Native DLL/SO boundary:** `runtime/*.dll` files are Windows-only. On Linux, `lua-utf8` resolves via `pob_host.lua`'s `require("utf8")` fallback (`/usr/local/lib/lua/5.1/utf8.so`). Never add `.so` files to `runtime/`.

## Driving the Engine & Preserving Tab State
- **Drive calcs via `build.calcsTab` + `build.buildFlag`**, never raw `calcs.*`.
- **Preserve Lua tab objects** (`skillsTab`, `configTab`, `itemsTab`, `partyTab`): the engine writes back into them directly; never re-model them in C++.
- **Upstream class construction (`bcbca9b60`):** Always instantiate engine objects as `new("X"):X(args)`. Passing extra arguments to `new()` throws an error, and calling `new("X")` without `:X()` returns an unconstructed object that fails on first use (often masked inside a bridge `pcall` as an empty feature). Grep `app/` for `new("` after any upstream sync.

## Bridge Marshalling & State Traps
- **Return plain tables only.** Never marshal a raw engine `Item`, slot control, `Tooltip`, or dropdown row holding `modList` across the C++ bridge (causes multi-gigabyte recursion/copy blowups).
- **Stubbed input globals:** `IsKeyDown` and `GetCursorPos` are stubs in the Qt host. Pass explicit `shift`/`ctrl` flags from QML (or use helper wrappers like `withKeys`) rather than invoking legacy `OnSelClick`.
- **Draw-coupled helpers & undo semantics:**
  - `ItemsTab:UpdateSockets()` normally runs only from `Draw`/`AddItemTooltip` — call it explicitly before reading sockets.
  - `ItemSlotControl:Populate` iterates with `pairs` (unstable order) — sort deterministically by `itemOrderList`.
  - `AddItem` pushes no undo state; callers and undo-testing selftests must call `AddUndoState()`.
  - Undo replaces `items` and `itemSets` tables wholesale; address items by id/index and re-read after undo.
  - `CreateDisplayItemFromRaw` aliases equipped mod-line tables and mutates `displayItem`; do not use it for compare hovers.
  - `node.sprites[1..4]` are normalised UVs (`coords.x / sheet.width`), never raw pixel coordinates.
