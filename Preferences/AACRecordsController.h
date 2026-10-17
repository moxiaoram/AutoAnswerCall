#import "../AACRecords.h"
#import <notify.h>
@interface AACRecordsController : UITableViewController
@property(nonatomic,copy) NSArray *records;
@property(nonatomic,copy) NSString *readStatus;
@property(nonatomic,copy) NSString *phoneStatus;
@property(nonatomic,strong) NSDate *pong;
@property(nonatomic) NSUInteger refreshGeneration;
@property(nonatomic) NSUInteger clearGeneration;
@property(nonatomic) BOOL clearing;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *tokens;
@end
@implementation AACRecordsController
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"自动接听记录";self.tokens=[NSMutableArray new];self.records=@[];
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=100;
 self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshRecords)]];
 self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refreshRecords) forControlEvents:UIControlEventValueChanged];
 __weak typeof(self) w=self;
 int pong=0;if(notify_register_dispatch("com.autoanswer.call.pong",&pong,dispatch_get_main_queue(),^(int t){w.pong=NSDate.date;w.phoneStatus=@"电话模块刚刚响应；不证明接听权限。";[w readRecords];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(pong)];
 int cleared=0;if(notify_register_dispatch("com.autoanswer.call.records.cleared",&cleared,dispatch_get_main_queue(),^(int t){if(!w.clearing)return;w.clearing=NO;[w readRecords];[w message:@"电话进程已确认清空" text:@"MobilePhone 已写入空记录并在电话进程回读成功。设置页当前读取结果见列表；跨沙盒可见性仍受系统限制。清空时仍活动的旧通话后续回调不再重新写入，新通话正常记录。"];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(cleared)];
 int failed=0;if(notify_register_dispatch("com.autoanswer.call.records.clearFailed",&failed,dispatch_get_main_queue(),^(int t){if(!w.clearing)return;w.clearing=NO;[w readRecords];[w message:@"电话记录清空未确认" text:@"电话进程报告写入或回读失败；不能保证持久删除。"];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(failed)];
 [self refreshRecords];
}
- (void)dealloc{for(NSNumber *token in _tokens)notify_cancel(token.intValue);}
- (void)message:(NSString *)title text:(NSString *)text{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)readRecords{
 BOOL synced=NO,present=NO;self.records=AACReadRecords(&synced,&present);
 self.readStatus=!synced?@"电话记录域同步失败，当前读取可能是缓存。":(!present?@"没有可读取的电话记录：可能尚无事件、电话模块未运行或跨沙盒不可见。":(self.records.count?@"已读取电话结构化记录；可能受跨进程缓存影响。":@"当前可见电话记录为空；不据此推断电话模块是否运行。"));
 [self.tableView reloadData];[self.refreshControl endRefreshing];
}
- (void)refreshRecords{
 NSUInteger generation=++self.refreshGeneration;self.pong=nil;self.phoneStatus=@"正在探测电话模块…";[self readRecords];uint32_t status=notify_post("com.autoanswer.call.ping");
 if(status!=NOTIFY_STATUS_OK){self.phoneStatus=@"电话探测通知发送失败。";[self readRecords];return;}
 __weak typeof(self) w=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!w||generation!=w.refreshGeneration)return;if(!w.pong)w.phoneStatus=@"电话模块未响应：可能休眠、未启动、未注入或通知不可达。";[w readRecords];});
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.records.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return [NSString stringWithFormat:@"最近 %lu 条（最多200条）",(unsigned long)self.records.count];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return nil;}
- (NSString *)dateText:(NSDate *)date{if(![date isKindOfClass:NSDate.class])return @"时间未知";NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm:ss ZZZZ";return [f stringFromDate:date];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *c=[tableView dequeueReusableCellWithIdentifier:@"record"];if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"record"];
 NSDictionary *r=self.records[indexPath.row];c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",[self dateText:r[@"timestamp"]],r[@"caller"]?:@"来电号码未知"];c.textLabel.numberOfLines=0;c.detailTextLabel.text=AACRecordResult(r);c.detailTextLabel.numberOfLines=0;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];NSDictionary *r=self.records[indexPath.row];NSMutableString *text=[NSMutableString stringWithFormat:@"通话 UUID：%@\n来电：%@\n首次观察：%@\n最近更新：%@\n结果：%@\n\n事件（最多24项）：\n",r[@"id"],r[@"caller"]?:@"未知（CXCall 无公开号码接口）",[self dateText:r[@"timestamp"]],[self dateText:r[@"updated"]],AACRecordResult(r)];
 for(id event in r[@"events"])if([event isKindOfClass:NSDictionary.class])[text appendFormat:@"%@  %@\n",[self dateText:event[@"timestamp"]],event[@"status"]?:@"未知事件"];
 UIViewController *detail=[UIViewController new];detail.title=@"记录详情";UITextView *view=[[UITextView alloc] initWithFrame:CGRectZero];view.editable=NO;view.font=[UIFont systemFontOfSize:15];view.text=text;detail.view=view;[self.navigationController pushViewController:detail animated:YES];
}
- (void)confirmClear{
 if(self.clearing)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认清空自动接听记录？" message:@"请求电话进程删除其全部结构化记录。电话进程未响应时无法确认删除；不会用设置页的空缓存代替电话确认。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 __weak typeof(self) w=self;[a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[w requestClear];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)requestClear{
 self.clearing=YES;NSUInteger generation=++self.clearGeneration;uint32_t status=notify_post("com.autoanswer.call.records.clear");if(status!=NOTIFY_STATUS_OK){self.clearing=NO;[self message:@"未发送清空请求" text:@"Darwin 通知发送失败；没有确认删除电话记录。"];return;}
 __weak typeof(self) w=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!w||generation!=w.clearGeneration||!w.clearing)return;w.clearing=NO;[w readRecords];[w message:@"电话记录清空未确认" text:@"未收到电话进程写入及回读确认。可能休眠或通知不可达；设置页未代写电话域，也未宣称已删除。可待电话模块响应后重试。"];});
}
@end
