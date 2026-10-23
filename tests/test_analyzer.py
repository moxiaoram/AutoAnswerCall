import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("analyzer", ROOT/"tools/analyze_report.py")
analyzer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
class AnalyzerTests(unittest.TestCase):
    def test_partial_pairs(self):
        events=[{"kind":"hook","phase":"enter","callID":1},
                {"kind":"hook","phase":"return","callID":1,"durationMs":2.5},
                {"kind":"hook","phase":"enter","callID":2},
                {"kind":"hook","phase":"return","callID":3,"durationMs":9}]
        self.assertEqual(analyzer.summarize_calls(events),{"paired":1,"entryWithoutReturn":1,"returnWithoutEntry":1,"p50Ms":2.5,"p95Ms":9.0,"maxMs":9.0})
    def test_envelope_and_legacy(self):
        legacy=json.loads((ROOT/"tests/fixtures/sample-diagnostic-report.json").read_text())
        with tempfile.TemporaryDirectory() as folder:
            for data in (legacy,{"observation":legacy,"runtime":{"backend":"not-connected"},"journal":{"totalRecords":1,"events":[{"seq":1,"event":"runtime.error","fields":{"message":"missing backend"}}]}}):
                path=Path(folder)/"report.json"; path.write_text(json.dumps(data))
                result=subprocess.run([sys.executable,str(ROOT/"tools/analyze_report.py"),str(path)],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn("Most common observed caller offsets",result.stdout)
                self.assertIn("Call pairing",result.stdout)
                if "journal" in data: self.assertIn("missing backend",result.stdout)
    def test_invalid_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"bad.json"; path.write_text("{")
            result=subprocess.run([sys.executable,str(ROOT/"tools/analyze_report.py"),str(path)],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
    def test_empty(self):
        self.assertEqual(analyzer.summarize_calls([])["paired"],0)
    def test_runtime_summary_missing_real_state(self):
        result=analyzer.summarize_runtime_events({"events":[
            {"event":"runtime.error","fields":{"message":"backend not connected"}},
            {"event":"action.request","fields":{"actionID":"a","action":"searchOpponent"}},
            {"event":"action.result","fields":{"actionID":"a","accepted":False}}
        ]})
        self.assertEqual(result["stateSamples"],0)
        self.assertEqual(result["actionRequests"],1)
        self.assertEqual(result["actionResults"],1)
        self.assertEqual(result["acceptedRequests"],0)
    def test_runtime_summary_synthetic_fixture(self):
        fixture=json.loads((ROOT/"tests/fixtures/sample-runtime-report.json").read_text())
        result=analyzer.summarize_runtime_events(fixture["journal"])
        self.assertEqual(result["stateSamples"],2)
        self.assertEqual(result["actionRequests"],1)
        self.assertEqual(result["acceptedRequests"],1)
        self.assertEqual(result["observedMilestones"]["singleUnitDeploymentsConfirmed"],1)
        self.assertEqual(result["observedMilestones"]["settlementObserved"],1)
if __name__=="__main__": unittest.main()
