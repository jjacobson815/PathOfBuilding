# Snippet to append to the Qt repo's CLAUDE.md

Copy the block below (without this heading) to the end of
`PathOfBuilding/CLAUDE.md` after copying `port-plan/` into that repo.

---

## Port Plan (legacy → Qt)

This repo is a port of the legacy PoB (Lua + SimpleGraphic) to a Qt6/QML host
embedding the unchanged LuaJIT calc engine. The plan lives in `port-plan/`.

**Session protocol — do not deviate:**
1. Read `port-plan/STATUS.md` first. It names the ACTIVE phase.
2. Read only `port-plan/phases/<active phase file>`. Do NOT read other phase
   files or the whole `port-plan/` folder.
3. Load `port-plan/reference/*.md` files only when the active phase file
   directs you to for the work item at hand.
4. On completing a work item: tick its checkbox in the phase file; if future
   sessions must know something new (invariant, gotcha, decision), add one
   line to the top section of `STATUS.md`.
5. `port-plan/plans-archive/` and the repo-root `plans/` folder are historical;
   never treat them as current instructions.

**Hard invariants (apply to all phases):** see the Invariants section of
`port-plan/STATUS.md` — they override any older doc in this repo.
