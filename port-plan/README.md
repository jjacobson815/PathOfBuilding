# PoB Legacy → Qt Port Plan — Document System

This folder is the complete, phased plan for porting Path of Building (legacy
Lua + SimpleGraphic host) to the Qt6/QML + C++ host that embeds the unchanged
LuaJIT calc engine. Copy this folder into the Qt repo root
(`PathOfBuilding/port-plan/`).

## How Claude sessions must use this folder (token discipline)

**Never load the whole folder.** The per-session protocol is:

1. Read `STATUS.md` — always. It is deliberately small: current phase pointer,
   invariants, and the completed-work log in order of importance.
2. Read **only** the phase file that `STATUS.md` names as ACTIVE
   (`phases/PHASE-N-*.md`).
3. Read a `reference/*.md` file **only** when the active work touches that
   subsystem (each phase file says which references it needs).
4. Everything else stays unread.

When a work item completes: update its checkbox in the active phase file, and
if it changed anything a future session must know (a new invariant, a gotcha,
a decision), add ONE line to the log in `STATUS.md`. When a phase completes:
flip the ACTIVE pointer in `STATUS.md` and add a one-paragraph phase summary.

To wire this up in the Qt repo, append the snippet in `CLAUDE-SNIPPET.md` to
that repo's `CLAUDE.md`.

## Contents

| Path | Purpose | Loaded |
|---|---|---|
| `STATUS.md` | Current phase, invariants, importance-ordered done log | Every session |
| `phases/PHASE-*.md` | Full spec for one phase: goals, work items, acceptance gates | Active phase only |
| `reference/*.md` | Subsystem maps of the legacy app + the host-API contract | On demand |
| `CLAUDE-SNIPPET.md` | Block to paste into the Qt repo's `CLAUDE.md` | Once, by human |
