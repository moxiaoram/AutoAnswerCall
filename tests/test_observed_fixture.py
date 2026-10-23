import json
import unittest
from pathlib import Path

FIXTURE = Path(__file__).parent / "fixtures" / "observed_operation_trace.json"

class ObservedTraceFixtureTests(unittest.TestCase):
    def test_fixture_contains_four_observed_windows(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(data["sourceFile"], "部落4.json")
        self.assertEqual([w["operation"] for w in data["operationWindows"]],
                         ["search", "deploy", "endBattle", "nextRound"])
        self.assertFalse(data["limitations"]["signatureVerified"])
        self.assertFalse(data["limitations"]["semanticProof"])
        self.assertFalse(data["limitations"]["invocationAllowed"])

    def test_fixture_does_not_store_raw_argument_words(self):
        text = FIXTURE.read_text(encoding="utf-8")
        self.assertNotIn("arg1RawHex", text)
        self.assertNotIn("arg2RawHex", text)
        self.assertNotIn("0x16b3d5e30", text)

if __name__ == "__main__":
    unittest.main()
