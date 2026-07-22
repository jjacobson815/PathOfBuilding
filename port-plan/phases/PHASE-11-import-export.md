# Phase 11 — Import/Export Tab

**Status:** NOT STARTED
**Goal:** Port the Import/Export tab: OAuth + account-name character import, the
full item/tree/skill import pipeline, and build sharing (generate/copy/share/import
across the 7 build sites). This is where a user's real character comes into the
planner.
**Depends on:** Phase 10 (network + OAuth), Phase 4 (tree import target), Phase 5
(skills import target), Phase 6 (items import target — shares the item JSON parser),
Phase 3 (shell/level/title write-backs).
**References to load:** [[tabs-catalog]] (Import/Export tab), [[core-lifecycle]]
(OAuth/LaunchServer, build sites, share codes), [[host-api-contract]] (SetForeground
after OAuth).

## Part 11.1 — OAuth account import

- [ ] "Import From Your Account": Authorize with Path of Exile (30 s timer, rate-
  limit countdown, status/error labels, logout); the OAuth flow uses `PoEAPI.lua` +
  `LaunchServer.lua` (localhost redirect server) — via the Phase 10 strategy (real
  sub-script running LaunchServer, or a `QTcpServer` returning the same `(code,
  errMsg, state, port)` contract). `SetForeground()` (Phase 0) raises the window
  after token receipt. Realm dropdown (PC/Xbox/Sony), Fetch Characters, league +
  character dropdowns (class-colored). (L)

## Part 11.2 — Account-name import

- [ ] "Import By Account Name": realm + account-name edit (requires `#1234`
  discriminator, unicode paste filter), Start, account-history dropdown; staged flow
  GETACCOUNTNAME → SELECTCHAR → IMPORTING; profile-page scrape to fix account-name
  case; league/char dropdowns. Uses get-characters/get-passive-skills/get-items
  endpoints. Account history saved to Settings.xml. (M)

## Part 11.3 — Import pipeline (shared logic)

- [ ] `ImportPassiveTreeAndJewels`: masteries, jewel_data, skill_overrides→tattoos,
  hashes_ex, alt-ascendancy mapping, ruthless/phrecia suffix, cluster jewel graphs,
  sets char level + auto-off, resistance-penalty config estimate, bandit/pantheon
  config; confirm-overwrite if tree non-empty; "Delete jewels" option. (M)
- [ ] `ImportItemsAndSkills`: full item JSON parser (rarity/slot maps, abyssal
  sockets, catalysts, two-toned boots, energy blade, influences, fractured/crafted/
  scourge/crucible/mutated/flavour mods, foils, socketed-gems → socket groups with
  dedupe/merge, imbued supports), **socket-group order + state preservation on re-
  import** via reimport keys, main-group guessing. Delete-skills / Delete-equipment /
  Ignore-weapon-swap options. **Reuse the Phase 6 item parser** — do not build a
  second one. (L)

## Part 11.4 — Build sharing

- [ ] Generate code (URL-safe base64 + zlib deflate over the build XML — verify
  against real codes from all 7 sites), Copy, **Export dropdown** (sites with
  postUrl) + **Share** (upload → short link, via Phase 10). Import: URL/code edit
  (site URLs incl. youtube/google redirect unwrap, raw base64, dev-mode character
  JSON), validity label, **mode dropdown** (this build [confirm overwrite] / new
  build / **as comparison** → CompareTab), Import button. (M)
- [ ] `<Import>` XML section (lastRealm/League/AccountHash/CharacterHash, exportParty,
  importLink). **Export Support checkbox** feeding PartyTab exports (Phase 9). (S)

## Acceptance gate

- OAuth authorize → fetch characters → import Passive Tree + Items&Skills of a real
  character; the imported build matches what the character actually has (tree, gems,
  gear, level, bandit/pantheon).
- Account-name import (with `#discriminator`) works for a public account.
- Generate a share code → paste into legacy PoB → identical build (and vice-versa).
- Import a pobb.in/pastebin URL → correct build; "import as comparison" opens the
  Compare tab.
- `pob-selftest` import check green.

## Notes

- OAuth stores tokens in Settings.xml plaintext today — consider OS keychain (a
  deliberate deviation; record in STATUS if you do it, since it changes
  LoadSettings/SaveSettings + PoEAPI).
- The item JSON parser is the crux and is shared with Phase 6 — one implementation.
- Re-import state preservation (keeping socket-group order/enabled across re-imports)
  is subtle and easy to regress; test a re-import of an edited build.
