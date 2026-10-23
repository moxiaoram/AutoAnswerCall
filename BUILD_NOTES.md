# Build and verification notes for 0.4.6

Completed in this source-editing environment:
- Added `real-device-passive-validation` UI flow.
- Added manual visible-screen snapshots and session-scoped state-delta analysis.
- Added source-contract tests for read-only behavior and invocation gate.
- Existing C scheduler tests and Python report analyzer tests are retained.

Not performed:
- iOS SDK/Theos compilation or `.deb` packaging.
- Device installation, runtime UI validation, or live-game operation.
- Verification of candidate Hook ABI/signatures, scene/resource/loot/troop field sources, or any game action API.

The passive validation mode does not read game memory, capture the screen, capture network traffic, invoke candidate functions, or send game actions. Manual snapshot values are typed by the operator from the actual visible game screen and are explicitly non-authoritative.


0.4.6 additions:
- Runtime snapshots include `backendReadiness` with explicit blockers.
- UI has a readiness-check button that prints blockers into the event log.
- Removed the offline replay button/method from the installed tweak UI and removed the replay simulation implementation from the tweak build list. Offline C replay remains only as a development test.
