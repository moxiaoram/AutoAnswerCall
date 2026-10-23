# ClashAssist 0.4.6 — Backend readiness and remaining blocker

## What changed

The runtime snapshot now includes `backendReadiness`, a machine-readable report of:

- whether a backend object has been registered;
- actual versus expected bundle ID and build version;
- whether the backend's `validate:` method passed during a start attempt;
- whether all required protocol selectors are present;
- whether a successful live world snapshot exists, is fresh, and contains the required fields for its scene;
- a `blockers` array explaining why automatic battle is not ready.

`automaticBattleReady=true` is only a necessary software gate. It is not proof that a game action worked; every action still requires a fresh observed state transition.

## Current state of this source package

There is no concrete `CAVerifiedGameBackend` implementation in this repository, and no call to `registerBackend:error:` exists outside the runtime declaration/implementation. Therefore the runtime correctly reports `backend-not-registered` and will not start automatic battle.

The `部落4.json` offsets are call-site offsets around observed operations. They are not callable target addresses. The three hooked target functions have matching byte fingerprints, but `signatureVerified=false`; no ABI, parameter types, object lifecycle, return semantics, or action semantics were established. This package intentionally does not call or replay them.

## What is required before a real backend can be written

A real backend provider for the exact installed build must supply all of the following with independently verified evidence:

1. Exact target Mach-O UUID and build identity.
2. Verified function/API signatures and calling conventions, including main-thread requirements and object lifetime.
3. A trustworthy source for current scene and opponent identity.
4. Trustworthy sources for opponent remaining loot, cumulative battle loot, remaining units, and deployed units.
5. Verified search, one-unit deployment, end/confirm, and return-home actions.
6. A way to confirm each action from a subsequent fresh state revision, not merely an accepted function call.

Manual values copied from the visible screen are useful for comparing logs but are not authoritative runtime state and are not consumed by the scheduler.

## Validation performed here

- C state-machine unit tests: local logic only.
- Python report/contract tests: source and fixture validation only.
- No iOS/Theos build, `.deb` package, device installation, or live-game action test was performed in this environment.
