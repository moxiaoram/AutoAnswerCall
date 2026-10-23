#!/usr/bin/env python3
"""Static sanity checks for the diagnostic UI/API and report schema."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
observe = (root / "CAObserve.m").read_text(encoding="utf-8")
header = (root / "CAObserve.h").read_text(encoding="utf-8")
ui = (root / "CALabUI.m").read_text(encoding="utf-8")

required_observe = [
    "CA_LOG_CAPACITY 8192", "arg1RawHex", "arg2RawHex", "callerOffset",
    "returnedFromOriginal", "droppedOldestRecords", "callerSummary",
    "CAObserveMarkerSearchBefore", "CAObserveMarkerNextRoundVisible",
    "CAObserveStopTimeout", "CAObserveIsActive"
]
missing = [item for item in required_observe if item not in observe and item not in header]
if missing:
    raise SystemExit("Missing diagnostic implementation markers: " + ", ".join(missing))

selectors = [
    "markSearchBefore", "markSearchResult", "markDeployBefore", "markDeployObserved",
    "markEndBefore", "markSettlement", "markNextRound"
]
missing = [selector for selector in selectors if f"@selector({selector})" not in ui or f"- (void){selector}" not in ui]
if missing:
    raise SystemExit("Missing UI marker handlers: " + ", ".join(missing))

if "manual-action-observation-only" not in observe:
    raise SystemExit("Observation scope marker missing")
assert "CALabTick" not in ui and "CALabStart" not in ui
assert "开始模拟" not in ui
assert "pthread_mutex_lock(&gRecordLock)" in observe
assert "generation==atomic_load(&gGeneration)" in observe
assert "saveCheckpoint" in observe
assert "exportReport" in ui and "CAEventSnapshot" in ui
print("PASS: detailed timeline fields, ring buffer, marker APIs, UI handlers, and observation-only scope")
