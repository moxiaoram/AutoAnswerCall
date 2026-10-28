#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 首页视频定时沉浸式播放：仅在视频实际推进时累计观看时间。
@interface DYYYImmersivePlaybackManager : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, assign, readonly, getter=isImmersive) BOOL immersive;
+ (instancetype)sharedManager;
- (void)attachToFeedController:(UIViewController *)controller;
- (void)detachFromFeedController:(UIViewController *)controller;
- (void)feedDidChange;
- (void)recordPlaybackTime:(CGFloat)seconds duration:(CGFloat)duration source:(id)source;
- (void)refreshImmersiveElements;
- (void)userDidInteract;
@end

NS_ASSUME_NONNULL_END
