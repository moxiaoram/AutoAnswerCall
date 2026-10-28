#!/usr/bin/env python3
"""Static checks for unified long-press panel and settings chrome in 2.0.19."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
press = (r/'DYYYLongPressPanel.xm').read_text()
main = (r/'DYYY.xm').read_text()
panel = (r/'DYYYGridLongPressPanel.m').read_text()
ui = (r/'DYYYSystemSettingsViewController.m').read_text()
settings = (r/'DYYYSettings.xm').read_text()
helper = (r/'DYYYSettingsHelper.m').read_text()
make = (r/'Makefile').read_text()
ci = (r/'.github/workflows/build.yml').read_text()
control = (r/'control').read_text()
checks = {
    '2.0.19 package version': 'Version: 2.0.19' in control,
    'feed uses shared fallback action factory': 'DYYYBuildSharedFallbackGroupForAweme(aweme)' in press and 'DYYYGridLongPressPanel showFromController:owner groups:fallback ? @[fallback] : @[]' in press,
    'known modern controller intercepted': '%hook AWEModernLongPressPanelTableViewController' in press,
    'known classic controller intercepted': '%hook AWELongPressPanelTableViewController' in press,
    'search/detail video panel fallback': 'void DYYYRefreshUnifiedLongPressPanel(UIViewController *controller)' in press,
    'fallback checks video panel class and dataArray': 'containsString:@"LongPressPanel"' in press and 'respondsToSelector:dataSelector' in press,
    'comment panel excluded': 'containsString:@"Comment"' in press,
    'fallback called from generic lifecycle': 'DYYYRefreshUnifiedLongPressPanel(self);' in main and '- (void)viewDidAppear:(BOOL)animated' in main and '- (void)viewDidLayoutSubviews' in main,
    'search/detail reuses shared fallback actions': 'DYYYBuildSharedFallbackGroupForAweme(aweme)' in press and 'DYYYResolveAwemeFromGroups(groups)' in press,
    'duplicate labels prefer working actions': 'if (!existingModel.action && model.action)' in panel,
    'both entry paths use same grid renderer': 'DYYYGridLongPressPanel showFromController:controller groups:unifiedGroups' in press and 'rebuildMenu' in panel,
    'native actions merge with feed fallback': 'native action models' in panel and 'existing.actions' in panel,
    'root profile close X removed': 'xmark.circle.fill' not in ui and 'exitButton.accessibilityLabel' not in ui,
    'root edge-swipe close remains': 'dyyyHandleRootEdgePan:' in ui and 'dyyyClose' in ui,
    'basic prefix removed at callsite': 'createSubSettingsViewController:@"设置" sections:sections' in settings and 'createSubSettingsViewController:@"基本设置"' not in settings,
    'all subpage title prefix normalized centrally': 'hasPrefix:@"基本"' in helper and 'substringFromIndex:2' in helper and 'settingsVC.dyyyPageTitle = resolvedTitle' in helper,
    'Theos includes all edited sources': 'DYYYLongPressPanel.xm' in make and 'DYYYSystemSettingsViewController.m' in make and 'DYYYSettingsHelper.m' in make,
    'strict RootHide linking retained': '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,
    'CI runs the new regression check': 'python3 scripts/check_218_panel_settings.py' in ci,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed (static only)')
if not all(checks.values()): raise SystemExit(1)
