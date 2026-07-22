# Phase 12 — Trade (PoB Trader)

**Status:** NOT STARTED — SCOPE: confirm with user (large, network-heavy, optional
for a first shippable release).
**Goal:** Port the in-app trade tooling: the PoB Trader popup (per-slot weighted
trade searches with result import + evaluation), the TradeQueryGenerator (weighted
pseudo-stat query builder), rate limiting, and poe.ninja currency conversion.
**Depends on:** Phase 10 (async network + OAuth session), Phase 6 (items tab — the
"Trade for these items" entry point + item eval), Phase 2 (calc deltas for weights).
**References to load:** [[tabs-catalog]] (Items tab → PoB Trader), [[core-lifecycle]]
(trade rate limiter, poe.ninja), [[calc-engine-contract]] (calcFunc deltas for
stat weights).

## Part 12.1 — PoB Trader popup

- [ ] Per-visible-slot rows + active jewel sockets + special rows (Megalomaniac,
  Watcher's Eye): slot name, price-sorted result dropdown with full item tooltips +
  import (equips into build for diff), search button (session mode) or generate
  weighted URL + paste-result box (no-session mode), price display. (L)
- [ ] Top controls: item-set dropdown, OAuth login/logout status, buyout-type
  dropdown, realm + league dropdowns (fetched), fetch-pages count, **Adjust search
  weights** popup (TradeStatWeightMultiplierListControl), sort mode (StatValue /
  per-price / Price / WeightedSum), poe.ninja currency conversion + total price,
  rate-limit countdown (TradeQueryRateLimiter / TradeQueryRequests). (L)

## Part 12.2 — TradeQueryGenerator

- [ ] Build weighted pseudo-stat queries per slot from calc deltas (`calcFunc`
  compares, Phase 2), with per-row options (max price + currency, include corrupted/
  eldritch/influence weights) and special handling for Megalomaniac (notable weights)
  and Watcher's Eye (aura mod weights). Persists `<TradeSearchWeights>` per build. (L)

## Part 12.3 — Buy Similar

- [ ] CompareBuySimilar popup (from the Items tab "Buy similar" button). (S-M)

## Acceptance gate

- Generate a weighted trade URL for a slot → opens a valid pathofexile.com/trade
  search matching legacy's query for the same build/slot.
- Session-mode search returns results; importing a result shows the correct stat
  diff vs equipped.
- Rate limiting backs off correctly (don't get the account throttled — test against
  the real API cautiously or mock it).
- poe.ninja currency conversion produces a sane total price.

## Notes / risks

- **Broadest network surface in the app** (OAuth, trade API with rate-limit queue,
  poe.ninja). Respect GGG rate limits — the legacy `TradeQueryRateLimiter` logic
  must be preserved faithfully or accounts get throttled.
- This is a strong candidate to defer past a first shippable release — a fully
  functional offline planner (Phases 0–11 minus trade) is already the core product.
  Confirm scope/priority with the user.
