# Phase 10 — Network & Async Foundation

**Status:** DONE (2026-11-24, Wave 1, branch `phases-7-8-9`)
**Goal:** Bring the engine's networking back to life. Legacy runs all network work
through `LaunchSubScript` worker Lua states doing `lcurl.safe` — currently a no-op
stub, so every network feature is silently dead. Decide the strategy, implement it
off the GUI thread, and unblock import-from-URL, update check, poeurl, PoB Archives,
and (later) OAuth + trade.
**Depends on:** Phase 0 (host-contract fixes), Phase 1 (toast/async UI). Should
come before Phases 11 and 12.
**References to load:** [[host-api-contract]] (sub-script protocol + the 6 call
sites), [[core-lifecycle]] (`launch:DownloadPage`, the sub-script inventory).

## The decision (make it explicitly, record in STATUS)

- [x] Choose ONE:
  - **(A) Real sub-script protocol** *(CHOSEN & LOCKED 2026-11-24)* — implement `LaunchSubScript(scriptText,
    funcList, subList, ...)`: isolated `lua_State` on a worker thread, `funcList` =
    synchronous blocking proxies back to the main state, `subList` = async calls
    delivered to `OnSubCall` on the main thread, completion → `OnSubFinished`, error
    → `OnSubError`; plus `AbortSubScript`/`IsSubScriptRunning`. Covers all 6 sites
    unchanged (engine untouched). Highest fidelity, highest effort (L).
  - ~~(B) Targeted shim~~ *(rejected; would require per-site native rewrites for `LaunchServer.lua`, `UpdateCheck.lua`, PoEURL, and PoB Archives).*
  Record the choice + rationale in `STATUS.md`.

## Part 10.1 — Async HTTP off the GUI thread

- [x] Move `pob.http` (currently synchronous `curl_easy_perform` on the calling/GUI
  thread — freezes the app) to a worker thread with a Lua-side callback. Preserve
  the full option surface the engine uses: method, postfields, headers, **proxy**
  (http/socks5/socks5h), **connectionProtocol** (force IPv4/IPv6), **noSSL**, User-
  Agent "Path of Building/<ver>", follow-redirects, response header capture. (M)

## Part 10.2 — Wire the engine's network primitive

- [x] Make `launch:DownloadPage(url, callback, params)` actually deliver
  `{header, body}, errMsg` to its callback (via the chosen strategy). This single
  primitive unblocks import-from-URL, update check, poeurl resolve, PoB Archives,
  and build upload. (M — most effort is in the strategy from the decision.)
- [x] Verify the previously-dead paths now work end-to-end: import a build from a
  pobb.in/pastebin URL (Import tab uses this in Phase 11); resolve a poeurl tree
  link (Tree tab Phase 4). (S)

## Part 10.3 — CLI + protocol entry

- [x] `pob://` protocol handler: register the URL scheme with the OS, forward the
  URI as `arg[1]`, and drive the `Main.lua:67-81` startup-import path +
  `BuildSiteTools.ParseImportLinkFromURI`. (M)

## Acceptance gate

- Import a build from a real build-site URL → decodes and opens (no GUI freeze,
  even on a slow/throttled connection).
- A poeurl-shortened tree link resolves.
- Proxy + force-IPv4 options are honored (test behind a proxy or mock).
- The app never blocks the UI thread on a network call (verify with a delayed mock
  endpoint).
- `pob-selftest` green (the `require lcurl.safe`/`lzip` shim checks still pass).

## Notes / risks

- The sub-script model is a **semantic contract**, not just a function — some sites
  read a *file's text and execute it* (`UpdateCheck.lua`, `LaunchServer.lua`). A
  non-general implementation (strategy B) forces per-site work; budget for it.
- A same-`lua_State` implementation would block the UI on `lcurl` calls
  (`PoEAPI.lua:108` runs a long-lived HTTP listener) — isolation per sub-script
  state is mandatory if you pick strategy A.
- OAuth (`LaunchServer` localhost server) and trade are downstream of this — Phase
  11/12 assume DownloadPage works.
- `lzip` (update zip bundles) can stay stubbed until Phase 14 (updates); it's not
  needed for import/trade.

## Session log — 2026-11-24 (Wave 1, Windows)

- Strategy (A) implemented in `app/src/SubScriptManager.h`/`.cpp` with `LuaEngine` signals (`networkChanged`) and `pob.launchSubScript`/`abortSubScript`/`isSubScriptRunning`/`emitSignal` hooks.
- Fixed `app/lua/lcurl/safe.lua` error object (`:msg()` + `__tostring`), added `app/lua/pob_network.lua`, wired `TreeImportPopup.qml`/`TreeExportPopup.qml`, and hooked `SubScriptManager::registerUriScheme()` + `parseStartupUri()`/`pob_handleStartupUri` in `app/src/main.cpp`.
- Integrated selftests green (`pob-selftest.exe` + `pob-qt.exe --headless`): `subscript ok = true` (8 flags, `uiTicks=10..12`), `network ok = true` (10 flags incl. `delayedNonBlockingOk=true`, `proxyIpv4Ok=true`, `launchServerOk=true`, `pobUriOk=true`, `poeurlResolveOk=true`, `poeurlShrinkOk=true`).
