from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class BackendReadinessTests(unittest.TestCase):
    def test_runtime_exports_explicit_backend_readiness(self):
        src = (ROOT / "CABattleRuntime.m").read_text()
        self.assertIn("- (NSDictionary *)backendReadiness", src)
        self.assertIn('@"automaticBattleReady"', src)
        self.assertIn('@"blockers"', src)
        self.assertIn('@"backendReadiness":[self backendReadiness]', src)

    def test_observed_offsets_are_not_executable_apis(self):
        src = (ROOT / "CAInterfaceRegistry.m").read_text()
        self.assertIn('@"invocationAllowed": @NO', src)
        self.assertIn('@"signatureVerified": @NO', src)
        self.assertIn("callerOffset 是调用来源位置，不是被 Hook 函数本身的地址", src)

    def test_installed_ui_does_not_offer_simulated_battle_button(self):
        ui = (ROOT / "CALabUI.m").read_text()
        makefile = (ROOT / "Makefile").read_text()
        self.assertNotIn("runOfflineReplay", ui)
        self.assertNotIn("离线模拟自动流程", ui)
        self.assertNotIn("CAReplaySimulation.m", makefile)

    def test_no_concrete_backend_is_falsely_claimed(self):
        readme = (ROOT / "BACKEND_READINESS.md").read_text()
        self.assertIn("There is no concrete `CAVerifiedGameBackend` implementation", readme)
        self.assertIn("will not start automatic battle", readme)

if __name__ == "__main__":
    unittest.main()
