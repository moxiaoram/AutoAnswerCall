#!/usr/bin/env python3
"""Offline regression: edge touch exclusion and native speed preservation."""
from pathlib import Path
root=Path(__file__).resolve().parent.parent
press=(root/'DYYYLongPressPanel.xm').read_text()
main=(root/'DYYY.xm').read_text()
make=(root/'Makefile').read_text()
checks={
    'Center-zone guard uses window coordinates': 'convertPoint:point toView:window' in press and 'CGRectGetWidth(window.bounds)' in press,
    'Both edges reserved for native speed': 'width * 0.20' in press and 'location.x >= nativeSpeedEdgeWidth' in press and 'location.x <= (width - nativeSpeedEdgeWidth)' in press,
    'Recognizer rejects edge at touch down': 'shouldReceiveTouch:(UITouch *)touch' in press and '!DYYYPluginLongPressAllowedAtPoint(view, [touch locationInView:view])' in press,
    'Recognizer rechecks before presenting': '!DYYYPluginLongPressAllowedAtPoint(recognizer.view' in press,
    'Cell fallback duplication suppressed': 'objc_getAssociatedObject(hitCell, &kDYYYDirectLongPressRelayKey)' in press,
    'Cell recognizer still attached': 'DYYYInstallDirectLongPressOnCell((UIView *)self, model)' in main,
    'Feed recognizer still attached': 'DYYYInstallDirectLongPressOnFeedView((UIScrollView *)self)' in main,
    'Native long-press playback-speed handler retained': '- (void)handleLongPressFastSpeed:(UILongPressGestureRecognizer *)gesture' in main and '%orig;' in main[main.find('- (void)handleLongPressFastSpeed:'):main.find('- (void)handleLongPressFastSpeed:')+150],
    'No touch cancellation': 'press.cancelsTouchesInView = NO;' in press,
    'No dynamic_lookup': '-Wl,-undefined,dynamic_lookup' not in make,
}
for title,passed in checks.items():
    print(('PASS' if passed else 'FAIL'), title)
print(f'{sum(checks.values())}/{len(checks)} checks passed (static only)')
raise SystemExit(0 if all(checks.values()) else 1)
