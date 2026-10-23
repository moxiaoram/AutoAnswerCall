#!/usr/bin/env python3
"""Correlate manual markers and already-observed pass-through hook calls.

This tool never resolves or invokes game functions. Correlation is not semantic proof.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

WINDOWS = [
    ("search", "即将点击搜索对手", "对手战场/搜索结果已显示"),
    ("deploy", "即将选择或部署兵力", "已观察到兵力部署结果"),
    ("endBattle", "即将手动结束战斗", "已看到结算界面"),
    ("nextRound", "已看到结算界面", "已看到下一轮/新对手界面"),
]

def analyze(observation):
    timeline = observation.get("timeline") or []
    markers = {}
    for event in timeline:
        if event.get("phase") == "marker" and event.get("marker"):
            markers.setdefault(event["marker"], event)
    output = []
    for name, start_name, end_name in WINDOWS:
        start, end = markers.get(start_name), markers.get(end_name)
        complete = bool(start and end and float(end.get("elapsedMs", -1)) >= float(start.get("elapsedMs", 0)))
        item = {"operation": name, "complete": complete, "calls": [],
                "semanticProof": False, "signatureVerified": False, "invocationAllowed": False}
        if not complete:
            item["missingMarkers"] = [m for m, ev in ((start_name, start), (end_name, end)) if ev is None]
            output.append(item)
            continue
        begin, finish = float(start["elapsedMs"]), float(end["elapsedMs"])
        item.update(startElapsedMs=begin, endElapsedMs=finish, windowDurationMs=finish-begin)
        groups = defaultdict(lambda: {"calls": 0, "mainThreadCalls": 0, "callIDs": []})
        for event in timeline:
            if event.get("phase") != "enter":
                continue
            t = float(event.get("elapsedMs", -1))
            if begin <= t <= finish:
                key = (event.get("kind", "unknown"), event.get("callerOffset", "unknown"))
                group = groups[key]
                group["calls"] += 1
                group["mainThreadCalls"] += int(bool(event.get("mainThread")))
                if event.get("callID") is not None and event["callID"] not in group["callIDs"]:
                    group["callIDs"].append(event["callID"])
        item["calls"] = [{"hook": k[0], "callerOffset": k[1], **v}
                          for k, v in sorted(groups.items(), key=lambda kv: -kv[1]["calls"])]
        item["candidateCount"] = len(item["calls"])
        output.append(item)
    registry = []
    for hook in observation.get("installDiagnostics") or []:
        registry.append({"name": hook.get("name", "unknown"),
                         "targetOffset": hook.get("offset", "unknown"),
                         "hookInstalled": bool(hook.get("hookInstalled")),
                         "fingerprintMatched": bool(hook.get("fingerprintMatched")),
                         "signatureVerified": bool(hook.get("signatureVerified")),
                         "invocationAllowed": False})
    return {"schemaVersion": 1, "mode": "observed-correlation-only", "operationWindows": output,
            "hookRegistry": registry, "invocationAllowed": False,
            "sourceNote": "callerOffset 是调用来源位置，不是被 Hook 函数本身地址；时间相关性不证明函数语义。"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    data = json.loads(args.report.read_text(encoding="utf-8"))
    observation = data.get("observation", data)
    result = analyze(observation)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8")
    else:
        print(text)

if __name__ == "__main__":
    main()
