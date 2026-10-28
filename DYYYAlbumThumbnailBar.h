#import <UIKit/UIKit.h>
@class AWEAwemeModel;

// 只在图文合集 cell 中显示，普通视频不受影响。
@interface DYYYAlbumThumbnailBar : UIView
+ (void)configureFeedCell:(UIView *)cell model:(AWEAwemeModel *)model;
+ (void)layoutFeedCell:(UIView *)cell;
+ (void)clearFeedCell:(UIView *)cell;
@end
