#!/usr/bin/env python3
"""Source-level regressions for 2.0.8 UI fixes; runtime still needs device testing."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
main = (root / "DYYY.xm").read_text()
settings = (root / "DYYYSettings.xm").read_text()
ui = (root / "DYYYSystemSettingsViewController.m").read_text()
header = (root / "DYYYSystemSettingsViewController.h").read_text()
checks = {
    "transparent tabbar extends only player view in stable mode": 'DYYYStableFeedLayoutEnabled() && DYYYGetBool(@"DYYYHideBottomBg")' in main and "if (!DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar())" in main,
    "player extension limits width and underlay gap": "diff >= 36 && diff <= 135" in main and "frame.size.width - self.superview.bounds.size.width" in main,
    "black interaction overlay cleared for transparent tabbar": 'DYYYFullScreenOrClearTabBar() || DYYYGetBool(@"DYYYHideBottomBg")' in main,
    "title offset reapplied after native transform": "DYYYTabTextOffset()" in main and "DYYYOffsetNeedsRefresh(self, DYYYTabTextOffset()" in main and "remaining - 2" not in main,
    "comment containers recursively cleared": "DYYYSetCommentSurfaceClear(child, enabled);" in main and "if (!view || depth > 12) return;" in main,
    "comment collection cells refreshed on reuse": "DYYYRefreshCommentListSurface(self);" in main and "%hook UICollectionView" in main and "%hook UITableView" in main,
    "comment blur restores layer backgrounds": "kDYYYCommentScrollOriginalLayerKey" in main and "oldLayer == [NSNull null]" in main,
    "settings uses isolated root stack": "[[UINavigationController alloc] initWithRootViewController:settingsVC]" in settings and "[existingNav pushViewController:settingsVC animated:YES]" not in settings,
    "modal settings stack explicitly tracked": "settingsVC.dyyyUsesDedicatedModalNavigation = YES;" in settings,
    "settings root exits without intermediate view": "nav.viewControllers.firstObject == self" in ui and "[nav dismissViewControllerAnimated:YES completion:nil]" in ui,
    "dedicated modal navigation explicitly tracked": "dyyyUsesDedicatedModalNavigation" in header and "pluginRoot.dyyyUsesDedicatedModalNavigation" in ui,
    "strict linker retained": "-Wl,-undefined,error" in (root / "Makefile").read_text() and "-Wl,-undefined,dynamic_lookup" not in (root / "Makefile").read_text(),
}
for label, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + label)
print(f"{sum(checks.values())}/{len(checks)}")
raise SystemExit(0 if all(checks.values()) else 1)
