import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "analyze_observed_interfaces.py"
spec = importlib.util.spec_from_file_location("observed_interfaces", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class InterfaceCorrelationTests(unittest.TestCase):
    def test_correlates_calls_in_manual_windows_without_authorizing_invocation(self):
        obs = {"timeline": [
            {"phase":"marker", "marker":"即将点击搜索对手", "elapsedMs":1000},
            {"phase":"enter", "kind":"统一命令提交候选", "callerOffset":"0xba1fe8", "elapsedMs":1500, "callID":1, "mainThread":True},
            {"phase":"marker", "marker":"对手战场/搜索结果已显示", "elapsedMs":3000},
        ], "installDiagnostics":[{"name":"统一命令提交候选", "offset":"0xf949f8", "hookInstalled":True, "fingerprintMatched":True, "signatureVerified":False}]}
        result = module.analyze(obs)
        search = result["operationWindows"][0]
        self.assertTrue(search["complete"])
        self.assertEqual(search["calls"][0]["callerOffset"], "0xba1fe8")
        self.assertFalse(search["semanticProof"])
        self.assertFalse(result["invocationAllowed"])
        self.assertFalse(result["hookRegistry"][0]["signatureVerified"])

    def test_missing_markers_are_not_inferred(self):
        result = module.analyze({"timeline": []})
        self.assertFalse(result["operationWindows"][0]["complete"])
        self.assertEqual(result["operationWindows"][0]["missingMarkers"], ["即将点击搜索对手", "对手战场/搜索结果已显示"])

if __name__ == "__main__":
    unittest.main()
