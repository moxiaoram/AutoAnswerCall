#!/usr/bin/env python3
"""Source-only checks for 2.0.9. Not a substitute for iOS/RootHide tests."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
main=(root/'DYYY.xm').read_text()
settings=(root/'DYYYSettings.xm').read_text()
ui=(root/'DYYYSystemSettingsViewController.m').read_text()
mk=(root/'Makefile').read_text()
checks={
 'progress base applied and offset state separated': all(k in main for k in ('kDYYYProgressBaseKey','kDYYYProgressAppliedKey','kDYYYProgressOffsetKey')),
 'progress offset refreshes after settings edits': 'DYYYOffsetNeedsRefresh(view, desired' in main,
 'progress handles both native container and slider': 'DYYYRefreshProgressLocation(self, DYYYProgressHasContainer(self))' in main and 'DYYYRefreshProgressLocation(self, NO)' in main,
 'title intercepts native transforms': '- (void)setTransform:(CGAffineTransform)transform {\n    %orig(DYYYComposeOffset(self, transform, DYYYTabTextOffset()' in main,
 'tab title applies after layout and setting changes': 'DYYYOffsetNeedsRefresh(self, DYYYTabTextOffset(),' in main,
 'no offscreen feed cell size changes for stable mode': 'if (!DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar())' in main,
 'player underlay tolerates safe-area delta': 'diff >= 36 && diff <= 135' in main and 'fabs(diff - nominal) <= 35' in main,
 'interaction underlay does not resize feed table': 'BOOL clearFooterStable' in main and 'if (clearFooterStable)' in main,
 'blank placeholder page removed': 'UIViewController *landing = [UIViewController new]' not in main,
 'settings always opens one dedicated nav': '[[UINavigationController alloc] initWithRootViewController:settingsVC]' in settings and '[existingNav pushViewController:settingsVC animated:YES]' not in settings,
 'root back dismisses modal': 'nav.viewControllers.firstObject == self' in ui and '[nav dismissViewControllerAnimated:YES completion:nil]' in ui,
 'strict RootHide linking unchanged': '-Wl,-undefined,error' in mk and '-Wl,-undefined,dynamic_lookup' not in mk,
 'default setup remains full': 'AWEMEVISION_STARTUP ?= full' in mk,
 'correct app filter': 'com.ss.iphone.ugc.Aweme' in (root/'DYYY.plist').read_text(),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+' '+k)
print(f'{sum(checks.values())}/{len(checks)} checks passed (source only)')
raise SystemExit(0 if all(checks.values()) else 1)
