#!/usr/bin/env python3
"""Static sanity checks for the diagnostic UI/API and report schema."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
observe = (root / "CAObserve.m").read_text(encoding="utf-8")
header = (root / "CAObserve.h").read_text(encoding="utf-8")
ui = (root / "CALabUI.m").read_text(encoding="utf-8")
core = (root / "CABattleCore.h").read_text(encoding="utf-8")
runtime = (root / "CABattleRuntime.m").read_text(encoding="utf-8")
contract = (root / "INTERFACE_CONTRACT.md").read_text(encoding="utf-8")

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
for marker in ["CAWorldHasOpponentResources", "CAWorldHasBattleLoot", "observedAtMonotonic", "noLootGrowthTimeout", "CAReturnHome"]:
    assert marker in core, f"Missing core state contract: {marker}"
for marker in ["state.sample", "state.transition", "scheduler.decision", "action.request", "action.result", "state.read.stale", "returnHome:"]:
    assert marker in runtime, f"Missing runtime diagnostics/action: {marker}"
assert "INTERFACE_CONTRACT.md" in (root / "README.md").read_text(encoding="utf-8")
assert "67" in (root / "LOG_ANALYSIS_2026-10-23.md").read_text(encoding="utf-8")
assert "pthread_mutex_lock(&gRecordLock)" in observe
assert "generation==atomic_load(&gGeneration)" in observe
assert "saveCheckpoint" in observe
assert "exportReport" in ui and "CAEventSnapshot" in ui
assert "启动真机接口验证（只读 300 秒）" in ui
assert "validation.manualStateSnapshot" in ui
assert "CAAnalyzeObservedInterfaces(observation, journal" in ui
assert "manualStateAnalysis" in (root / "CAInterfaceRegistry.m").read_text(encoding="utf-8")
assert '@"invocationAllowed": @NO' in (root / "CAInterfaceRegistry.m").read_text(encoding="utf-8")
print("PASS: hook diagnostics, manual markers, validity-aware world contract, no-growth timer, return-home loop, and fail-closed runtime logging")
