from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RealDeviceValidationModeTests(unittest.TestCase):
    def test_ui_exposes_passive_validation(self):
        ui = (ROOT / "CALabUI.m").read_text(encoding="utf-8")
        self.assertIn('启动真机接口验证（只读 300 秒）', ui)
        self.assertIn('validation.session.start', ui)
        self.assertIn('validation.manualStateSnapshot', ui)
        self.assertIn('gameActionsSent', ui)
        self.assertIn('authoritativeGameAPI', ui)

    def test_manual_state_values_are_not_claimed_as_authoritative(self):
        registry = (ROOT / "CAInterfaceRegistry.m").read_text(encoding="utf-8")
        self.assertIn('manual-visible-screen-entry', registry)
        self.assertIn('@"authoritativeGameAPI":@NO', registry)
        self.assertIn('空值表示未知，不等于零', registry)
        self.assertIn('adjacentStateDeltas', registry)

    def test_unverified_hooks_cannot_be_invoked(self):
        registry = (ROOT / "CAInterfaceRegistry.m").read_text(encoding="utf-8")
        self.assertIn('@"signatureVerified": @NO', registry)
        self.assertIn('@"invocationAllowed": @NO', registry)
        self.assertNotIn('MSHookFunction(', registry)
        self.assertNotIn('((void (*)(', registry)

    def test_session_scopes_manual_snapshots(self):
        registry = (ROOT / "CAInterfaceRegistry.m").read_text(encoding="utf-8")
        self.assertIn('validationSessionID', registry)
        self.assertIn('![fields[@"validationSessionID"] isEqual:validationSessionID]', registry)

if __name__ == "__main__":
    unittest.main()
