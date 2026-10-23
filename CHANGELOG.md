# 0.4.2

- Inject sanitized observed-log baseline into source and runtime diagnostics.
- Add `runtime.preflight` and `runtime.start.blocked` events with missing backend capabilities.
- Add backend expected/actual build details and action phase/reason fields to diagnostics.
- Add tests for observed evidence counts, missing live-state evidence, and absence of raw pointers/callsite offsets in the shareable fixture.
- Preserve fail-closed behavior when no backend is connected. No live-game action backend is added.

# 0.4.1

- Analyze the supplied report and document the evidence: only the unified-command candidate hit (67 calls); the other two candidates had zero hits; all candidate signatures remained unverified; no manual markers or loot values were recorded; runtime backend was not connected.
- Add cumulative battle-loot fields separate from opponent's currently available resources.
- End request can be issued after five seconds without cumulative loot growth while a fresh observation confirms the fight is still active; retain a per-battle hard timeout.
- Add a bounded multi-battle loop: confirm settlement, request return home, confirm home, then search again until maxBattles/maxSearch.
- Reset per-battle counters and fail closed on regressions/timeouts.
- Add evidence-limited report findings to offline analyzer and tests.
