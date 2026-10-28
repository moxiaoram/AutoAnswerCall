// Screenshot-matched feed glyphs.  Original copyright notices preserved in upstream files.
#import <UIKit/UIKit.h>

@interface DYYYCapturedFeedIcons : NSObject
// Keeps native UIImage point bounds; only replaces the visible artwork.
+ (UIImage *)iconForFileName:(NSString *)fileName matchingNativeImage:(UIImage *)nativeImage;
@end
