#import <UIKit/UIKit.h>

// Non-interactive avatar-follow decoration. The original Douyin view owns all
// tap handling and follow state; this helper only draws the badge.
@interface DYYYFollowStarBadge : NSObject
+ (void)updatePromptView:(UIView *)prompt enabled:(BOOL)enabled;
@end
