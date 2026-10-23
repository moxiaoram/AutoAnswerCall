# 0.4.0

- Remove all shipped synthetic battle state/data and simulator UI.
- Add a confirmed-state battle controller and main-thread runtime with a verified-backend protocol; explicitly reject starting without an implementation.
- Require exact bundle/build validation, fresh world observations, changed opponent identity after searching, exactly one confirmed deployment per request, and observed settlement.
- Add structured run/action/state logs, bounded asynchronous JSONL writes, full JSON file export and 5-second observation checkpoints.
- Serialize ring records/session changes and prevent late returns crossing sessions; expand to 8192 records / 300 seconds.
- Add retained-call pairing and duration analysis; retain support for old JSON reports.
- Replace simulator tests with 20 confirmed-state controller groups and four analyzer tests; update CI.
- Concrete game API implementation and live-game validation remain unavailable.
