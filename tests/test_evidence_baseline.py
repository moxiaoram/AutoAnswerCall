import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class EvidenceBaselineTests(unittest.TestCase):
    def test_baseline_contains_only_supported_observations(self):
        data = json.loads((ROOT / "evidence/observed-baseline-2026-10-23.json").read_text(encoding="utf-8"))
        self.assertEqual(data["timelineRecords"], 135)
        self.assertEqual(data["hookCounters"]["统一命令提交候选"]["hits"], 67)
        self.assertEqual(data["hookCounters"]["普通按钮分发"]["hits"], 0)
        self.assertEqual(data["hookCounters"]["结束确认候选"]["hits"], 0)
        self.assertEqual(data["candidateSignatureVerification"], {"verified": 0, "total": 3})
        self.assertEqual(data["manualActionMarkers"], 0)
        self.assertEqual(data["realWorldStateSamples"], 0)
        self.assertEqual(data["cumulativeLootSamples"], 0)
        self.assertEqual(data["runtimeAtCapture"]["backend"], "not-connected")

    def test_shareable_fixture_excludes_raw_addresses_and_action_mapping(self):
        data = json.loads((ROOT / "evidence/observed-baseline-2026-10-23.json").read_text(encoding="utf-8"))
        self.assertFalse(data["privacy"]["rawArgumentWordsIncluded"])
        self.assertFalse(data["privacy"]["pointerValuesIncluded"])
        self.assertFalse(data["privacy"]["callerOffsetsIncluded"])
        not_supported = " ".join(data["interpretation"]["notSupported"])
        self.assertIn("不能确认任何候选Hook对应搜索、部署或结束战斗", not_supported)

    def test_runtime_injects_baseline_and_fail_closed_blocker(self):
        runtime = (ROOT / "CABattleRuntime.m").read_text(encoding="utf-8")
        header = (ROOT / "CAObservedEvidence.h").read_text(encoding="utf-8")
        self.assertIn("CAObservedEvidenceSummary()", runtime)
        self.assertIn("runtime.start.blocked", runtime)
        self.assertIn("verified-single-unit-deploy", runtime)
        self.assertIn("allCandidateSignaturesVerified", header)

if __name__ == "__main__":
    unittest.main()
