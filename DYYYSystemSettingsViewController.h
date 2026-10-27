#import "AwemeHeaders.h"

// 与原 AWESettingBaseViewController 兼容，保留全部现有设置模型和点击回调。
@interface DYYYSystemSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, copy) NSString *dyyyPageTitle;
@property(nonatomic, copy) NSString *dyyyFocusTitle;
@end
