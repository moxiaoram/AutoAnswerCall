#!/usr/bin/env python3
"""Static guardrails, not a simulator of Douyin private view hierarchies."""
from pathlib import Path
s = (Path(__file__).resolve().parent.parent / 'DYYY.xm').read_text()
assert 'DYYYClearTabBarPaintLayers(self, YES);' in s
assert 'DYYYClearTabBarPaintLayers(self, NO);' in s
assert 'DYYYSetPaintViewHidden(sibling, hide);' in s
assert 'CGRectIntersectsRect(CGRectInset(tabFrame, -4, -7), frame)' in s
assert 'DYYYSetPaintLayerHidden(layer, hide)' in s
assert 'kDYYYCommentPanelBlurTag' in s
assert 'DYYYApplyCommentPanelBlur(self.view);' in s
assert 'DYYYFindCommentPanelBackground' in s
assert 'DYYYClearCommentListPaint(target, YES, 0);' in s
assert 'DYYYClearCommentListPaint(old, NO, 0);' in s
assert 'addSubview:whiteBackgroundView' not in s
assert 'DYYYFullScreenOrClearTabBar(void)' in s
assert 'if (DYYYStableFeedLayoutEnabled()) return NO;' in s
print('PASS 12/12: visual effect regression guards (source-only)')
