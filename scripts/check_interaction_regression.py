#!/usr/bin/env python3
"""Offline source regressions for 2.0.13; cannot prove private runtime behavior."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
main = (root/'DYYY.xm').read_text()
settings=(root/'DYYYSettings.xm').read_text()
ui=(root/'DYYYSystemSettingsViewController.m').read_text()
press=(root/'DYYYLongPressPanel.xm').read_text()
panel=(root/'DYYYGridLongPressPanel.m').read_text()
make=(root/'Makefile').read_text()
verify=(root/'scripts/verify_relaxin_deb.py').read_text()
checks = {
    'Strict RootHide linker': '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,
    'Complete hook startup': 'AWEMEVISION_STARTUP ?= full' in make and '%init;' in main,
    'Progress default and migration': '@"DYYYVideoProgressDownOffset": @"10"' in main and 'AwemeVisionLayoutDefaultsMigrated204' in main,
    'Title default': '@"DYYYTabTitleDownOffset": @"6"' in main,
    'Progress transform reapplication': 'DYYYProgressTransformForWrite(self, transform, DYYYProgressHasContainer(self))' in main,
    'Feed geometry stable': 'if (DYYYStableFeedLayoutEnabled()) return;' in main,
    'Tab bar background paint clear': 'DYYYClearTabBarWrapperPaint(self, YES);' in main,
    'Cell long press fallback': 'DYYYInstallDirectLongPressOnCell((UIView *)self, nil)' in main,
    'Feed long press fallback': 'DYYYInstallDirectLongPressOnFeedView((UIScrollView *)self)' in main,
    'Early gesture with overlay': 'press.minimumPressDuration = 0.28;' in press and 'DYYYGridLongPressPanel showFromController:owner' in press,
    'No native panel premature dismissal': 'panel.sourceController != controller' in panel,
    'One dedicated settings navigation stack': '[[UINavigationController alloc] initWithRootViewController:settingsVC]' in settings and '[existingNav pushViewController:settingsVC animated:YES]' not in settings,
    'Modal navigation always full screen': 'settingsVC.dyyyUsesDedicatedModalNavigation = YES;' in settings and 'UIModalPresentationFullScreen' in settings,
    'Root dismisses modal in one step': 'nav.viewControllers.firstObject == self' in ui and '[nav dismissViewControllerAnimated:YES completion:nil]' in ui,
    'Subsections remain on active nav': '[weakSettingsVC.navigationController pushViewController:' in settings,
    'One-swipe exit gesture': 'dyyyHandleRootEdgePan:' in ui and 'viewControllers.count == 1' in ui,
    'Actual DEB version check': "'Version: 2.0.13'" in verify,
}
for key,value in checks.items(): print(('PASS' if value else 'FAIL'), key)
print(f'{sum(checks.values())}/{len(checks)}')
raise SystemExit(0 if all(checks.values()) else 1)
