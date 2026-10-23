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
    def test_evidence_findings_report_missing_markers_and_backend(self):
        observation={"timeline":[],"installDiagnostics":[{"signatureVerified":False}],
                     "hooks":[{"name":"a","hits":0},{"name":"b","hits":4}]}
        envelope={"observation":observation,"runtime":{"backend":"not-connected"}}
        findings=analyzer.evidence_findings(envelope, observation)
        joined="\n".join(findings)
        self.assertIn("人工操作标记",joined)
        self.assertIn("函数签名均未验证",joined)
        self.assertIn("后端未注册",joined)
        self.assertIn("战利品累计值",joined)
    def test_invalid_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"bad.json"; path.write_text("{")
            result=subprocess.run([sys.executable,str(ROOT/"tools/analyze_report.py"),str(path)],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
    def test_empty(self):
        self.assertEqual(analyzer.summarize_calls([])["paired"],0)
if __name__=="__main__": unittest.main()
