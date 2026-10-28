#!/usr/bin/env python3
"""Source-only regression check against the earliest available 1.1 and the working 1.7 logic.
Does not claim on-device verification.
"""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
s = (r / "DYYY.xm").read_text()
start = s.index("static inline BOOL DYYYFullScreenOrClearTabBar(void)")
end = s.index("static inline BOOL DYYYShouldExtendPlayerUnderTabBar", start)
fn = s[start:end]
checks = {
 "1.7: transparency activates video-under-tab display": 'DYYYGetBool(@"DYYYHideBottomBg")' in fn,
 "stable mode cannot veto drawing underneath tab": 'if (DYYYStableFeedLayoutEnabled()) return NO;' not in fn,
 "native skin hidden when transparent": 'self.skinContainerView.hidden = YES;' in s,
 "bottom tab paint cleared": 'DYYYClearTabBarPaintViews(self, 0, YES)' in s,
 "render-backed player hook isolated from stable feed geometry": 'BOOL enableFS = !DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar();' in s and 'DYYYTryStableVideoUnderlay(content)' in s,
 "stable mode still guards Feed layout": 'if (DYYYStableFeedLayoutEnabled()) return;' in s,
 "stable mode still guards detail table rounding": 'if (!DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar())' in s,
 "stable mode guards legacy concern-cell shift": 'if (!DYYYStableFeedLayoutEnabled() && DYYYFullScreenOrClearTabBar() && gCurrentTabBarHeight > 0)' in s,
 "Strict link does not use dynamic lookup": '-Wl,-undefined,error' in (r/'Makefile').read_text() and '-Wl,-undefined,dynamic_lookup' not in (r/'Makefile').read_text(),
 "RootHide build scheme": 'override THEOS_PACKAGE_SCHEME := roothide' in (r/'Makefile').read_text(),
 "correct Douyin bundle filter": 'com.ss.iphone.ugc.Aweme' in (r/'DYYY.plist').read_text(),
}
for name, okay in checks.items():
 print(("PASS" if okay else "FAIL") + " " + name)
assert all(checks.values()), 'Tab-bar regression audit failed'
print(f"PASS {len(checks)}/{len(checks)} 2.0.12 tab-bar source checks")
