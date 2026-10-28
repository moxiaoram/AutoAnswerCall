#!/usr/bin/env python3
"""Source-only regression guards for 2.0.13; these are NOT iOS integration tests."""
from pathlib import Path
r=Path(__file__).resolve().parent.parent
s=(r/'DYYY.xm').read_text()
checks={
 'stable feed unchanged': 'if (DYYYStableFeedLayoutEnabled()) return;' in s,
 'player-specific underlay helper': 'static void DYYYExtendPlayerContentUnderTabBar' in s,
 'player underlay honors transparency switch': 'return DYYYGetBool(@"DYYYHideBottomBg") || DYYYFullScreenOrClearTabBar();' in s,
 'player geometry gap guarded': 'gap >= 36.0 && gap <= 135.0' in s,
 'both player controllers apply extension': s.count('DYYYExtendPlayerContentUnderTabBar(self.contentView);') == 2,
 'comment white paint recognition': 'DYYYIsWhiteCommentPlate' in s,
 'comment surface label/control scoped': 'BOOL textOrControl' in s and 'DYYYHasWhiteCommentPlate(surface)' in s,
 'attributed text white plate clear': '[result removeAttribute:NSBackgroundColorAttributeName range:range];' in s,
 'attributed text restore': 'label.attributedText = original;' in s,
 'comment panel-only recursive application': 'DYYYSetCommentLabelTextPlateClear((UILabel *)child, enabled);' in s,
 'blur switch remains opt-in': 'DYYYGetBool(@"DYYYEnableCommentBlur")' in s,
 'strict RootHide linker': '-Wl,-undefined,error' in (r/'Makefile').read_text() and '-Wl,-undefined,dynamic_lookup' not in (r/'Makefile').read_text(),
 'new Debian version': 'Version: 2.0.15' in (r/'control').read_text(),
 'new app-visible version': '#define DYYY_VERSION @"2.0.15"' in (r/'DYYYConstants.h').read_text(),
}
for name, ok in checks.items():
 print(('PASS' if ok else 'FAIL'),name)
if not all(checks.values()): raise SystemExit(1)
print(f'{len(checks)}/{len(checks)} source-only assertions pass')
