# Changelog

## 0.4.6 — Backend readiness diagnostics
- Added a runtime readiness report with explicit blockers for backend registration, bundle/build match, validation, required selectors, and a fresh complete live snapshot.
- Readiness is diagnostic only and never turns an observed caller offset into an invocable API.

## 0.4.5 — Real-device passive interface validation

- Added a dedicated read-only validation session entry in the UI.
- Added manual visible-state snapshot fields for scene, opponent's visible loot, cumulative battle loot, remaining troops, and deployed troops.
- Added validation session IDs and journal events for validation start/stop and state snapshots.
- Extended interface analysis to calculate adjacent manually observed state deltas, scoped to the current validation session.
- Unknown values remain null; manual entries are explicitly marked non-authoritative and are not fed into the battle runtime.
- Kept candidate Hook invocation disabled because observed caller offsets do not establish function signatures or semantics.
- Did not claim iOS/Theos compilation or live-device tests.

## 0.4.4 — Observed baseline and offline scheduler replay

- Added read-only timing/caller-offset baseline from `部落4.json`.
- Added deterministic offline scheduler replay for development tests only.
- Real game backend remained unimplemented.
