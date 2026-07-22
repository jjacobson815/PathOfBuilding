> **SUPERSEDED** — historical tree-render notes. Current status: `port-plan/STATUS.md`; tree fixes landed (see the Done log). Kept only for the hard-verification methodology.

# Hand-off: pob-qt passive tree renders blank (canvas width = 0)

## Definitive root cause (confirmed via diagnostics)

The passive-tree `Canvas` (`treeCanvas`) has **width 0**, so nothing paints.
The width collapses because its parent chain is starved:

```
treeCanvas (w=0)  ->  treeView (w=0)  ->  contentArea Rectangle (w=0)  ->  mainRowLayout (w=1100)
```

Diagnostic proof (`diag_output/output.txt`):

```
[DIAG] CHAIN canvas=0 tree=0 content=0 row=1100 rowId=mainRowLayout
[DIAG] ROWCHILDREN count=3
  child[0] id=sideBar            w=312 fillW=false
  child[1] id=contentArea        w=0   fillW=true   <- holds treeView -> treeCanvas
  child[2] id=QQuickColumnLayout w=764 fillW=true   <- THE CULPRIT
```

- `row` is `mainRowLayout` (the RowLayout at `app/qml/main.qml:179`).
- The RowLayout has exactly **3** direct children: `sideBar`, `contentArea`, and a
  **`ColumnLayout`** (the "generic build content" block at `app/qml/main.qml:609`).
- That generic-content `ColumnLayout` is a **direct sibling of `contentArea`** inside the
  RowLayout (it should be NESTED INSIDE `contentArea`, per the comment at
  `app/qml/main.qml:251` which says all views are children of the content Rectangle).
- It declares `Layout.fillWidth: true` (`app/qml/main.qml:611`), so it grabs 764px and
  starves `contentArea` to width 0. `contentArea` holds `treeView` -> `treeCanvas`, so the
  tree canvas is 0px wide and renders blank even though tree DATA loads fine
  (`[TreeViewController][DIAG] refresh OK: nodes= 3222 ... boundsValid-would-be= true`).

## The fix

Make the RowLayout contain only `sideBar` + `contentArea`. Move the generic build-content
`ColumnLayout` (currently `app/qml/main.qml:609-688`) to be a child of `contentArea`
(indent +4 spaces; move `contentArea`'s closing brace to after it). Then `contentArea`
receives the full remaining width (1100 - 312 = 788) and the tree canvas becomes visible.

## Smaller parts (execution order)

1. **Re-read braces** `app/qml/main.qml` ~605-695 to confirm exactly where `contentArea`
   currently closes and where the generic-content `ColumnLayout` sits. (The file's
   indentation is misleading; trust the diagnostic: RowLayout has 3 children.)
2. **Nest the ColumnLayout**: indent the generic-content `ColumnLayout` block by 4 spaces so
   it becomes a child of `contentArea`, and ensure `contentArea`'s `}` is placed AFTER it
   (so `skillsView`/`calcsView`/`configView`/`notesView`/`importView`/`compareView`/
   `partyView` remain inside `contentArea`).
3. **Verify width**: rebuild + deploy, run, confirm `[DIAG] CHAIN content=788` (or remove
   diagnostics and confirm `canvas>0`).
4. **Remove diagnostics**: delete the Timer block, the `[DIAG] ONPAINT` log line, and the
   temporary `id`s `mainRowLayout` / `mainStack` / `contentArea` added for diagnosis.
5. **Rebuild + deploy** via `run_pob_fusion.bat`; confirm no `STALE BINARY` warning.
6. **Verify** the tree renders (nodes/connectors visible, not blank).

## Files touched (so far, diagnostic only — NOT yet the fix)
- `app/qml/main.qml` — added `id: mainRowLayout` (179), `id: mainStack` (173),
  `id: contentArea` (248), a diagnostic Timer, and an `[DIAG] ONPAINT` log. These must be
  removed in step 4.
- `app/src/TreeViewController.h` / `.cpp` — unchanged; `bounds` Q_PROPERTY is fine.
- `app/lua/pob_host.lua` — already fixed earlier (sources geometry from global
  `main.tree[treeVersion]`); unrelated to this width bug but required for no-build rendering.
