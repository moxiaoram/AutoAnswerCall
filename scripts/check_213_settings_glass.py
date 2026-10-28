#!/usr/bin/env python3
"""2.0.13 source-only guards: root settings chrome and subtle comment glass."""
from pathlib import Path
r=Path(__file__).resolve().parent.parent
ui=(r/'DYYYSystemSettingsViewController.m').read_text()
source=(r/'DYYY.xm').read_text()
checks={
  'root-only top chrome hidden': 'header.hidden = self.dyyyMainPage;' in ui and '(self.dyyyMainPage ? 0.0 : 54.0)' in ui,
  'subpages keep back navigation': '[back setTitle:@"返回"' in ui and '@selector(dyyyBack)' in ui,
  'main brand name retained': 'pluginName.text = DYYY_NAME;' in ui,
  'version subtitle gone': 'version.text = [NSString stringWithFormat:' not in ui,
  'root profile X removed while close method remains': 'exitButton.accessibilityLabel = @"关闭插件设置";' not in ui and '- (void)dyyyClose' in ui,
  'search remains active': 'search.placeholder = @"搜索插件设置项";' in ui,
  'comment blur default stronger': '@"DYYYCommentBlurTransparent": @"0.92"' in source,
  'old default migrated selectively': 'AwemeVisionCommentGlassMigrated213' in source and 'fabs([previous doubleValue] - 0.82)' in source,
  'targeted material style': 'UIBlurEffectStyleSystemMaterial' in source and 'DYYYEnhanceCommentGlass(target, alpha);' in source,
  'unrelated blur helper left untouched': 'DYYYEnhanceCommentGlass' not in (r/'DYYYUtils.m').read_text(),
  'strict linking unchanged': '-undefined,error' in (r/'Makefile').read_text() and '-undefined,dynamic_lookup' not in (r/'Makefile').read_text(),
  'new deb version': 'Version: 2.0.18' in (r/'control').read_text(),
}
for k,v in checks.items():
    print(('PASS' if v else 'FAIL') + ': ' + k)
if not all(checks.values()): raise SystemExit(1)
print(f'PASS {len(checks)}/{len(checks)} root UI and comment-glass source checks (not a device test)')
