# Analysis of supplied report (2026-10-23)

The sanitized evidence is embedded in `evidence/observed-baseline-2026-10-23.json` and loaded by the runtime as a diagnostic baseline. Raw argument words, pointer-like values, caller offsets, and guessed action mappings are deliberately not copied into the shareable evidence fixture.

## Observed facts

- Source report plugin version: `0.4.0`; envelope schema `1`; observation schema `3`.
- Target build: `18.116.1`; OS: `iOS 17.3 (21D50)`.
- Observation duration: `186866.039 ms` (~186.9 seconds).
- Timeline: 135 retained records, no dropped records.
- `普通按钮分发`: 0 calls.
- `结束确认候选`: 0 calls.
- `统一命令提交候选`: 67 calls; all 67 were on main thread and returned from original.
- All three candidate signatures were marked unverified.
- No manual action markers, real world-state samples, or cumulative loot samples were present.
- Runtime backend was `not-connected`; searches and confirmed deployments were both 0.
- The frequency distribution across eight observed caller groups was 40, 13, 5, 3, 2, 2, 1, 1. These counts are preserved without embedding raw caller offsets.

## What is supported

The unified-command candidate was invoked during the observation window. The other two candidates were not observed in this session. All observed unified-candidate calls returned from the original.

## What is not supported

This report does not identify a verified search, deployment, end-battle, settlement, return-home, or resource-reading API. A call count does not equal a successful action. A matching code fingerprint does not verify a function signature or calling convention. No resource thresholds or five-second no-growth decision can be calculated because no actual resource samples were recorded.

## Runtime integration in 0.4.2

- `CAObservedEvidence.h` embeds only sanitized, supported facts from the report.
- `CABattleRuntime` emits `runtime.preflight` and `runtime.start.blocked`, including the baseline and missing backend capabilities.
- Backend registration and build mismatch events now include enough context to diagnose why the scheduler did not start.
- The scheduler remains fail-closed: no backend means no live game commands. No raw argument word is replayed.

This archive is a source/diagnostics update, not a working live-game bot. It was not compiled with Theos/iOS SDK or tested in a real game session.
