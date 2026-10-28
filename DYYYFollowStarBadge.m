#import "DYYYFollowStarBadge.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@implementation DYYYFollowStarBadge

static char kDYFollowStarOverlayKey;
static char kDYFollowStarClipKey;

+ (UIImage *)badgeImage {
    static UIImage *badge = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The uploaded screenshot shows a small white pill beneath the avatar,
        // with a white-centred pink/red five-point outlined star. Recreate as
        // resolution-independent UIKit paths, not a JPEG crop with background.
        CGSize size = CGSizeMake(36.0, 24.0);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (ctx) {
            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0.0, 0.75), 1.15,
                                        [UIColor colorWithRed:0.30 green:0.18 blue:0.24 alpha:0.22].CGColor);
            UIBezierPath *pill = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1.0, 1.5, 34.0, 21.0)
                                                            cornerRadius:10.5];
            [[UIColor whiteColor] setFill];
            [pill fill];
            CGContextRestoreGState(ctx);

            const CGPoint center = CGPointMake(18.0, 12.1);
            const CGFloat outer = 7.35;
            const CGFloat inner = 3.95;
            UIBezierPath *star = [UIBezierPath bezierPath];
            for (int i = 0; i < 10; i++) {
                CGFloat a = -M_PI_2 + (CGFloat)i * M_PI / 5.0;
                CGFloat r = (i % 2 == 0) ? outer : inner;
                CGPoint p = CGPointMake(center.x + cos(a) * r, center.y + sin(a) * r);
                if (i == 0) [star moveToPoint:p]; else [star addLineToPoint:p];
            }
            [star closePath];
            star.lineWidth = 1.85;
            star.lineJoinStyle = kCGLineJoinRound;
            [[UIColor colorWithRed:1.0 green:0.985 blue:0.99 alpha:1.0] setFill];
            [star fill];
            [[UIColor colorWithRed:0.94 green:0.24 blue:0.34 alpha:1.0] setStroke];
            [star stroke];
            // Inner rose highlight: keep the visible shape close to the
            // screenshot while retaining a crisp outline at 3x native scale.
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
        }
        badge = [UIGraphicsGetImageFromCurrentImageContext() imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        UIGraphicsEndImageContext();
    });
    return badge;
}

+ (void)updatePromptView:(UIView *)prompt enabled:(BOOL)enabled {
    if (!prompt) return;
    UIImageView *overlay = objc_getAssociatedObject(prompt, &kDYFollowStarOverlayKey);
    if (!enabled || CGRectIsEmpty(prompt.bounds)) {
        if (overlay) {
            [overlay removeFromSuperview];
            objc_setAssociatedObject(prompt, &kDYFollowStarOverlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        NSNumber *originalClip = objc_getAssociatedObject(prompt, &kDYFollowStarClipKey);
        if (originalClip) {
            prompt.clipsToBounds = originalClip.boolValue;
            objc_setAssociatedObject(prompt, &kDYFollowStarClipKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        return;
    }
    if (!overlay) {
        overlay = [[UIImageView alloc] initWithImage:[self badgeImage]];
        overlay.contentMode = UIViewContentModeScaleAspectFit;
        overlay.userInteractionEnabled = NO; // native follow/cancel still receives taps
        overlay.accessibilityElementsHidden = YES;
        overlay.isAccessibilityElement = NO;
        overlay.tag = 217017;
        objc_setAssociatedObject(prompt, &kDYFollowStarOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(prompt, &kDYFollowStarClipKey))
        objc_setAssociatedObject(prompt, &kDYFollowStarClipKey, @(prompt.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    prompt.clipsToBounds = NO; // pill may be wider than native + animation view
    CGFloat width = MIN(38.0, MAX(31.0, CGRectGetWidth(prompt.bounds) * 1.3));
    CGFloat height = width * (24.0 / 36.0);
    overlay.frame = CGRectIntegral(CGRectMake(CGRectGetMidX(prompt.bounds) - width / 2.0,
                                             CGRectGetMidY(prompt.bounds) - height / 2.0,
                                             width, height));
    if (overlay.superview != prompt) {
        [prompt addSubview:overlay];
    } else if (prompt.subviews.lastObject != overlay) {
        // Avoid repeatedly reordering subviews during every UIKit layout pass.
        [prompt bringSubviewToFront:overlay];
    }
}

@end
