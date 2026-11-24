---
trigger: glob
globs: "port-plan/**/*.md"
---

# Port Plan Progressive Session Protocol

Follow this strict progressive-disclosure protocol whenever working with `port-plan/` documents. Never inline `port-plan/STATUS.md` into `always_on` context or load multiple phase specs at once.

## Session Read Order
1. Read `port-plan/STATUS.md` first — it names the single **ACTIVE** phase, current handoff pointer, and the **Hard Invariants** that override every older document in the repository.
2. If `STATUS.md` names an active handoff (for example `port-plan/handoff/HANDOFF-phase6.md`), read it next before opening the phase spec.
3. Read **only** the single active phase file (`port-plan/phases/PHASE-N-*.md`). Do NOT read inactive phase files or scan the whole `port-plan/` directory.
4. Load `port-plan/reference/*.md` files **only** when the active phase file explicitly directs you to for the work item at hand.

## Work-Item & Phase Wrap-Up
- On completing a work item: tick its checkbox in the active `port-plan/phases/PHASE-N-*.md` file and append concise verification evidence to its session log.
- If a session discovers a new cross-session invariant, environment gotcha, or resolved architectural decision, append **one concise line** to the top section of `port-plan/STATUS.md`.
- Flip the `ACTIVE` phase pointer in `port-plan/STATUS.md` **only** after every part of the current phase is ticked and passes its acceptance gate.
- Never commit changes that depend on gitignored local files such as `src/Settings.xml` — the selftest gate must pass on a clean checkout.

## Context-Bloat Paths
- Avoid bulk-reading generated or large static directories: `src/TreeData/`, `TreeData/`, `legacy-ref/`, `build-win/`, `build-linux/`, `dist/`, `captures/`, and binary media/database files.
