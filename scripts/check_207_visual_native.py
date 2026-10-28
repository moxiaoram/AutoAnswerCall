#!/usr/bin/env python3
"""Static feature regressions. Does not assert real Douyin 40.8.0 behavior."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
main=(root/'DYYY.xm').read_text()
menu=(root/'DYYYGridLongPressPanel.m').read_text()
press=(root/'DYYYLongPressPanel.xm').read_text()
mk=(root/'Makefile').read_text()
checks={
 'footer host paint, no feed resize': 'DYYYClearTabBarAncestorPaint(self, YES);' in main and 'DYYYSetTabHostPaintClear' in main and 'if (DYYYStableFeedLayoutEnabled()) return NO;' in main,
 'footer restore': 'DYYYClearTabBarAncestorPaint(self, NO);' in main and 'kDYYYTabHostOldOpaqueKey' in main,
 'comment panel blur': 'DYYYApplyCommentPanelBlur(self.view);' in main and 'kDYYYCommentPanelBlurTag' in main,
 'comment cell clear': 'DYYYSetCommentSurfaceClear(((UICollectionViewCell *)child).contentView, enabled);' in main,
 'comment scroll reuse': '%hook UITableView' in main and 'kDYYYCommentTableRefreshBusyKey' in main,
 'comment paint restored': 'DYYYSetCommentSurfaceClear(old, NO);' in main and 'DYYYClearCommentListPaint(old, NO, 0);' in main,
 'native actions merge rather than replace': 'NSMutableArray *merged = [NSMutableArray arrayWithArray:all]' in menu and 'for (AWELongPressPanelBaseViewModel *item in existing.actions)' in menu,
 'native complete menu fallback': '打开抖音原生完整菜单' in menu and '原生菜单尚未生成' in menu,
 'do not simplify away native menu in custom mode': press.count('&& !DYYYGridPanelIsEnabled()') == 2,
 'default visual flags': '@"DYYYHideBottomBg": @YES' in main and '@"DYYYEnableCommentBlur": @YES' in main,
 'strict rootHide linking': '-Wl,-undefined,error' in mk and '-Wl,-undefined,dynamic_lookup' not in mk,
}
for name, result in checks.items():print(('PASS' if result else 'FAIL')+': '+name)
print(f'{sum(checks.values())}/{len(checks)}')
raise SystemExit(0 if all(checks.values()) else 1)
