#!/usr/bin/env python3
"""Static follow-badge audit: not a Theos compile or device test."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]
x=(p/'DYYY.xm').read_text(); h=(p/'DYYYFollowStarBadge.h').read_text(); m=(p/'DYYYFollowStarBadge.m').read_text()
s=(p/'DYYYSettings.xm').read_text(); make=(p/'Makefile').read_text(); c=(p/'control').read_text()
checks={
 'version': 'Version: 2.0.19' in c,
 'native follow prompt hook': '%hook AWEPlayInteractionFollowPromptView' in x,
 'native plus lottie scoped': 'self.superview isKindOfClass:%c(AWEPlayInteractionFollowPromptView)' in x,
 'badge helper included': '#import "DYYYFollowStarBadge.h"' in x,
 'native touch preserved': 'overlay.userInteractionEnabled = NO' in m and 'self.userInteractionEnabled = NO' not in m,
 'no new gesture recognizer': 'addGestureRecognizer' not in m,
 'follow status respected': 'alreadyFollowed' in x,
 'native hide setting respected': 'DYYYHideFollowPromptView' in x,
 'original opacity restored': 'self.layer.opacity = savedOpacity.floatValue' in x,
 'original clip restored': 'prompt.clipsToBounds = originalClip.boolValue' in m,
 'one overlay per prompt': 'objc_getAssociatedObject(prompt, &kDYFollowStarOverlayKey)' in m,
 'badge star path': 'bezierPathWithRoundedRect' in m and 'for (int i = 0; i < 10; i++)' in m,
 'default enabled': '@"DYYYUseFollowStarBadge": @YES' in x,
 'switch in settings': '@"DYYYUseFollowStarBadge"' in s,
 'header and implementation compiled': 'DYYYFollowStarBadge.m' in make and '+ (void)updatePromptView' in h,
 'strict linker preserved': '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,
}
for name,ok in checks.items():
 print(('PASS' if ok else 'FAIL')+': '+name)
assert all(checks.values()),'follow star static check failed'
print(f'PASS {len(checks)}/{len(checks)} follow-star checks')
