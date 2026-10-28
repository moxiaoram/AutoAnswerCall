#!/usr/bin/env python3
"""Static regression for 2.0.19 feed-safe video-under-tabbar. Not a device test."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DYYY.xm').read_text()
ci=(r/'.github/workflows/build.yml').read_text()
mk=(r/'Makefile').read_text()
checks={
 'video is extended only when stable and bottom hidden': 'DYYYStableFeedLayoutEnabled() || !DYYYGetBool(@"DYYYHideBottomBg")' in s and 'DYYYTryStableVideoUnderlay(content)' in s,
 'actual same-window visible tab bar required': 'gDYYYLiveTabBar.window != content.window' in s and 'gDYYYLiveTabBar.hidden' in s,
 'footer gap is bounded': 'gap < 25 || gap > 145' in s,
 'reject secondary and partially scrolled video cells': 'CGRectGetMaxY(visible) < screenH * 0.70' in s and 'fabs(CGRectGetMaxY(visible) - CGRectGetMinY(tab)) > 24' in s,
 'only matching known renderers resized': 'DYYYExtendStableRenderSubviews' in s and '[name isEqualToString:@"TTMetalView"]' in s and '[name isEqualToString:@"TTPlayerView"]' in s,
 'strong ownership not retained for reused players': 'static __weak UIView *gDYYYActiveStablePlayer' in s and '[NSHashTable weakObjectsHashTable]' in s,
 'no active full-screen resizes in generic UIView hook': 'BOOL enableFS = !DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar();' in s,
 'Feed table frame stays native in stable mode': 'if (DYYYStableFeedLayoutEnabled()) return;' in s,
 'detail table height rounding still guarded': 'if (!DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar())' in s,
 'clip and render frames restored on switch': 'DYYYRestoreStableVideoUnderlay();' in s and 'kDYYYStableClipOriginalKey' in s and 'kDYYYStableRenderBaseKey' in s,
 'no video snapshot / no overlay copy': 'drawViewHierarchyInRect' not in s and 'renderInContext:' not in s,
 'current video content controllers both wired': s.count('DYYYExtendPlayerContentUnderTabBar(self.contentView);') == 2,
 'footer layout can reapply after player appears': 'DYYYTryStableVideoUnderlay(gDYYYLastPlayerContent)' in s,
 'scrolling restores clipped active video before adjacent item appears': 'CGRectGetMaxY(current) - bottom' in s and 'DYYYRestoreStableVideoUnderlay();' in s,
 'reuse and disappearance restore underlay': '[gDYYYActiveStablePlayer isDescendantOfView:self]' in s and s.count('gDYYYActiveStablePlayer == self.contentView')==2,
 'black footer not repainted by TTPlayerView': '!(DYYYStableFeedLayoutEnabled() && DYYYGetBool(@"DYYYHideBottomBg"))' in s,
 'diagnostics show active underlay and clipping': 'underlay=active player=' in s and 'underlay=inactive' in s,
 'CI includes this test': 'python3 scripts/check_219_stable_tab_underlay.py' in ci,
 'version bumped everywhere': 'Version: 2.0.19' in (r/'control').read_text() and '#define DYYY_VERSION @"2.0.19"' in (r/'DYYYConstants.h').read_text(),
 'RELAXIN RootHide strict linker': 'THEOS_PACKAGE_SCHEME := roothide' in mk and '-Wl,-undefined,error' in mk and '-Wl,-undefined,dynamic_lookup' not in mk,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL')+': '+label)
print(f'{sum(checks.values())}/{len(checks)} checks passed (static only)')
if not all(checks.values()): raise SystemExit(1)
