# Status · ClashAssist 0.4.6

- Added an explicit **real-device passive interface validation** mode in the UI.
- Added manual visible-screen state snapshots for scene, opponent loot, cumulative loot, remaining troops, and deployed troops. Empty values remain unknown (`null`), not zero.
- Added per-session adjacent-snapshot delta analysis for manually entered state values. The report explicitly marks these values as operator-entered and non-authoritative; they are not used by the battle scheduler.
- Retained Hook enter/return timing, caller offsets, thread IDs, nesting depth, manual operation markers, and correlation windows.
- No observed caller offset or raw argument is invoked/replayed. `signatureVerified=false` and `invocationAllowed=false` remain enforced.
- Live device data collection still requires the user to operate the game and manually record visible values. No game-memory reads, screenshots, network capture, or game actions are performed by this mode.
- Theos/iOS build, `.deb` packaging, and device runtime validation were not performed in this environment.
- Added `backendReadiness` to runtime diagnostics: explicit blockers for missing backend registration, bundle/build mismatch, validation status, required protocol methods, and missing/stale live state snapshots.
- No concrete backend was added because the available logs do not establish any callable game API or authoritative state source.

- The installed tweak no longer includes a user-facing offline simulation action; offline replay remains only in test sources.
- Added a UI action to print backend readiness blockers into the diagnostic journal.
