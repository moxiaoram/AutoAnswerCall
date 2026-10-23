#!/usr/bin/env python3
"""Offline summary for ClashAssist 0.4.6 diagnostic JSON. No network access."""
import argparse
import json
import math
import sys
from pathlib import Path


def ms(value):
    try:
        return f"{float(value):.3f} ms"
    except (TypeError, ValueError):
        return "n/a"


def summarize_calls(timeline):
    """Pair only retained entries; report missing pairs without assuming a crash."""
    entered, returned, durations = {}, set(), []
    for event in timeline:
        key = (event.get("kind"), event.get("callID"))
        if key[1] is None:
            continue
        if event.get("phase") == "enter":
            entered[key] = event
        elif event.get("phase") == "return":
            returned.add(key)
            value = event.get("durationMs")
            if isinstance(value, (int, float)) and math.isfinite(value) and value >= 0:
                durations.append(float(value))
    durations.sort()
    return {"paired": len(entered.keys() & returned),
            "entryWithoutReturn": len(entered.keys() - returned),
            "returnWithoutEntry": len(returned - entered.keys()),
            "p50Ms": durations[(len(durations)-1)//2] if durations else None,
            "p95Ms": durations[max(0, math.ceil(len(durations)*0.95)-1)] if durations else None,
            "maxMs": max(durations) if durations else None}



def summarize_runtime_events(journal):
    """Summarize structured runtime state samples and action request/confirmation evidence."""
    entries = journal.get("events", []) if isinstance(journal, dict) else []
    counts = {}
    samples, requests, results, transitions = [], {}, {}, []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = entry.get("event", "unknown")
        counts[name] = counts.get(name, 0) + 1
        fields = entry.get("fields", {})
        if not isinstance(fields, dict):
            continue
        if name == "state.sample":
            world = fields.get("world", {})
            if isinstance(world, dict):
                samples.append(world)
        elif name == "action.request":
            requests[fields.get("actionID")] = fields
        elif name == "action.result":
            results[fields.get("actionID")] = fields
        elif name == "state.transition":
            transitions.append(fields)
    accepted = sum(1 for value in results.values() if value.get("accepted") is True)
    milestones = {"candidatePassedResourceThreshold": 0, "singleUnitDeploymentsConfirmed": 0,
                  "settlementObserved": 0, "homeObservedBeforeNextSearch": 0}
    for transition in transitions:
        reason = str(transition.get("reason", ""))
        if "candidate-passed-resource-threshold" in reason:
            milestones["candidatePassedResourceThreshold"] += 1
        if "single-unit-deployment-confirmed" in reason:
            milestones["singleUnitDeploymentsConfirmed"] += 1
        if "settlement-confirmed-await-home" in reason:
            milestones["settlementObserved"] += 1
        if transition.get("toPhase") == "waitSearch" and transition.get("fromPhase") == "waitHome":
            milestones["homeObservedBeforeNextSearch"] += 1
    resource_increases = {"gold": 0, "elixir": 0, "dark": 0}
    previous = None
    for world in samples:
        loot = [world.get("battleLootGold"), world.get("battleLootElixir"), world.get("battleLootDark")]
        if all(isinstance(v, (int, float)) for v in loot):
            if previous is not None:
                for key, old, new in zip(resource_increases, previous, loot):
                    if new > old:
                        resource_increases[key] += 1
            previous = loot
    return {"eventCounts": counts, "stateSamples": len(samples), "actionRequests": len(requests),
            "actionResults": len(results), "acceptedRequests": accepted, "transitions": len(transitions),
            "observedMilestones": milestones, "lootIncreaseObservations": resource_increases,
            "unmatchedActionRequests": sorted(str(k) for k in requests.keys() - results.keys() if k is not None),
            "actionResultsWithoutRequest": sorted(str(k) for k in results.keys() - requests.keys() if k is not None)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="JSON copied from ClashAssist")
    parser.add_argument("--context", type=int, default=4,
                        help="number of nearby records to show on each side of a marker (default: 4)")
    args = parser.parse_args()
    try:
        data = json.loads(args.report.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"无法读取 JSON 报告：{exc}", file=sys.stderr)
        return 2

    if not isinstance(data, dict):
        print("报告根节点须为 JSON 对象", file=sys.stderr)
        return 2
    envelope = data
    data = envelope.get("observation", envelope)
    if not isinstance(data, dict):
        print("observation 须为 JSON 对象", file=sys.stderr)
        return 2
    journal = envelope.get("journal", {})
    if isinstance(journal, dict) and journal:
        print("Runtime:", json.dumps(envelope.get("runtime", {}), ensure_ascii=False))
        print("Journal disk error:", journal.get("diskError") or "none")
        print("Journal records:", journal.get("totalRecords", 0), "dropped:", journal.get("droppedOldestRecords", 0))
        runtime_summary = summarize_runtime_events(journal)
        print("Structured runtime summary:", json.dumps(runtime_summary, ensure_ascii=False))
        for entry in journal.get("events", []):
            if isinstance(entry, dict):
                print("EVENT", entry.get("seq"), entry.get("elapsedMs"), entry.get("event"), json.dumps(entry.get("fields", {}), ensure_ascii=False))
        runtime = envelope.get("runtime", {})
        if isinstance(runtime, dict) and not runtime.get("backendConnected", runtime.get("backend", "not-connected") not in ("not-connected", "未接入")):
            print("BLOCKER: no concrete backend is registered; runtime state/action data cannot prove real game behavior.")
        if runtime_summary["stateSamples"] == 0:
            print("BLOCKER: no structured state.sample events; scene, opponent resources, battle loot and troop counts are unverified.")
        if runtime_summary["actionResults"] == 0:
            print("BLOCKER: no action.result events; no real action request has a recorded acceptance result.")
    print("ClashAssist diagnostic report")
    print("=" * 72)
    print(f"Schema:       {data.get('schemaVersion', 'unknown')}")
    print(f"Session:      {data.get('sessionID', 'unknown')}")
    print(f"Started at:   {data.get('startedAt', 'unknown')}")
    print(f"Duration:     {ms(data.get('durationMs'))}")
    print(f"Active:       {data.get('active', 'unknown')}")
    print(f"Stop reason:  {data.get('stopReason', 'unknown')}")
    env = data.get("environment", {})
    print(f"Bundle:       {env.get('bundleID', 'unknown')} {env.get('bundleVersion', '')} ({env.get('buildVersion', '')})")
    print(f"OS:           {env.get('osVersion', 'unknown')}")

    info = data.get("timelineInfo", {})
    print("\nLog buffer")
    print("-" * 72)
    print(f"Total records: {info.get('totalRecords', 'unknown')}")
    print(f"Retained:      {info.get('retainedRecords', 'unknown')}")
    print(f"Dropped old:   {info.get('droppedOldestRecords', 'unknown')}")

    print("\nHook counters (hits are calls observed, not successful game actions)")
    print("-" * 72)
    for hook in data.get("hooks", []):
        print("{:<24} hits={:<6} main={:<6} original-return={}".format(
            hook.get("name", "unknown"), hook.get("hits", "?"),
            hook.get("mainThreadHits", "?"), hook.get("returnedFromOriginal", "?")))

    print("\nMost common observed caller offsets (from retained entries)")
    print("-" * 72)
    caller_summary = data.get("callerSummary", [])
    if caller_summary:
        for item in caller_summary[:20]:
            print("{:<24} {:<24} calls={} main={}".format(
                item.get("hook", "unknown"), item.get("callerOffset", "unknown"),
                item.get("calls", "?"), item.get("mainThreadCalls", "?")))
    else:
        print("No caller summary in report (older schema or no retained hook entries).")

    timeline = data.get("timeline", [])
    if not isinstance(timeline, list):
        timeline = []
    print("\nCall pairing / wrapper durations (retained entries only)")
    print(json.dumps(summarize_calls(timeline), ensure_ascii=False))
    print("Missing pairs may be overwritten, in flight, or stopped; do not infer a crash.")
    print(f"\nTimeline entries: {len(timeline)}")
    print("-" * 72)
    for event in timeline:
        if event.get("kind") == "人工操作标记":
            print("MARK seq={seq} t={t} label={label}".format(
                seq=event.get("seq", "?"), t=ms(event.get("elapsedMs")),
                label=event.get("marker", "unknown")))

    markers = [(i, event) for i, event in enumerate(timeline)
               if event.get("kind") == "人工操作标记"]
    if markers:
        print("\nHook activity near each manual marker")
        print("-" * 72)
        used = set()
        for idx, marker in markers:
            start = max(0, idx - max(0, args.context))
            end = min(len(timeline), idx + max(0, args.context) + 1)
            print("\n>>> {} at {} (seq {})".format(
                marker.get("marker", "marker"), ms(marker.get("elapsedMs")), marker.get("seq", "?")))
            for j in range(start, end):
                if j in used:
                    continue
                used.add(j)
                event = timeline[j]
                label = event.get("marker") if event.get("kind") == "人工操作标记" else event.get("kind", "?")
                detail = f"{event.get('phase', '?')}"
                if "callID" in event:
                    detail += f" callID={event['callID']} depth={event.get('depth', '?')}"
                if "durationMs" in event:
                    detail += f" duration={ms(event['durationMs'])}"
                if "arg1RawHex" in event:
                    detail += f" arg1={event['arg1RawHex']} arg2={event.get('arg2RawHex', 'n/a')}"
                detail += f" thread={event.get('threadID', '?')} main={event.get('mainThread', '?')}"
                detail += f" caller={event.get('callerOffset', 'n/a')}"
                print("  seq={:<5} t={:<14} {:<20} {}".format(
                    event.get("seq", "?"), ms(event.get("elapsedMs")), str(label)[:20], detail))
    else:
        print("\n没有人工标记。下一次观测建议在每次手动操作前点对应标记，方便对齐时间线。")

    print("\nInstall diagnostics")
    print("-" * 72)
    for item in data.get("installDiagnostics", []):
        print("{name}: offset={offset} readable={readable} fingerprint={fingerprintMatched} installed={hookInstalled}".format(
            name=item.get("name", item.get("status", "unknown")),
            offset=item.get("offset", "n/a"), readable=item.get("readable", "n/a"),
            fingerprintMatched=item.get("fingerprintMatched", "n/a"),
            hookInstalled=item.get("hookInstalled", "n/a")))

    print("\nInterpretation guardrails")
    print("- A hit only means a candidate function was entered; it does not prove search/deploy/end succeeded.")
    print("- Caller offsets are diagnostic offsets, not callable function addresses.")
    print("- Raw argument words may be pointers or scalars; they are not dereferenced and their types are unknown.")
    print("- Manual markers are user annotations, not automatic game-state detection.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
