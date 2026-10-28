#import <UIKit/UIKit.h>

/// 仿参考图：顶部五个圆形快捷操作 + 深色分组列表 + 倍速选择；其余插件动作以双列扩展卡片保留。
@interface DYYYGridLongPressPanel : UIViewController
+ (BOOL)showFromController:(UIViewController *)controller groups:(NSArray *)groups;
+ (void)clearFromController:(UIViewController *)controller;
@end
