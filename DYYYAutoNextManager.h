#import <UIKit/UIKit.h>

@interface DYYYAutoNextManager : NSObject
+ (instancetype)sharedManager;
- (void)attachFeed:(UIViewController *)feed;
- (void)detachFeed:(UIViewController *)feed;
- (void)feedDidSwitch;
- (void)recordCurrentTime:(CGFloat)current duration:(CGFloat)duration source:(id)source;
@end
