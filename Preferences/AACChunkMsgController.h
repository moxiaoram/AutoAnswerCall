#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "../AACChunkMsg.h"
#import "AACLogViewerController.h"
/* 跨进程分片消息（Darwin 名内载荷）1.16.0 —— 设置侧读回页（TASK 1 的 UI + TASK 2 的按需上报）。
   为什么要有这一页（1.15.0 的真实设备证据，用户 iOS 17.3 RootHide 设备）：
     - 进程探测页显示 incall (com.autoanswer.call.probe.incall) 到达 2 次、springboard 到达 2 次：
       InCallService 的 so 确实被注入，它的 Darwin 通知确实跨进程到达（1.15.0 之前「incall 从未
       到达」是时序假象，该进程只在通话期间运行）。
     - 宿主跨进程上报读回页显示 Hosts = ( springboard )、[incall] 本进程未读到该宿主的任何键，
       两个真实 plist 路径在设置进程里都不可见，而同一域却能读到 12 个键：文件/CFPreferences
       通道只对共享同一容器上下文的宿主有效。
     - 所以唯一被证实可跨进程的通道是 Darwin 通知，而通知名是任意字符串。本页读回该通道。
   诚实性规则：本页只显示本进程真实读到的内容与真实状态码；读不到就写「未观察到」，绝不因此
   断言任何宿主未注入，也绝不断言自动接听可用。名内载荷通道的片内容写在通知名里，无法预先注册
   （Darwin 通知不支持通配），所以本页对它的解码字节一般是 0——这一限制在页面上直接写明，
   内容由固定名字的状态槽通道给出。 */
@interface AACChunkMsgController : UITableViewController
@property(nonatomic,strong) NSArray *observerTokens;
@property(nonatomic,strong) dispatch_source_t pollTimer;
@property(nonatomic,strong) NSDate *opened;
@property(nonatomic,copy) NSString *lastAction;
@end
@implementation AACChunkMsgController
- (instancetype)initWithStyle:(UITableViewStyle)style{
 if((self=[super initWithStyle:style])){
  _opened=NSDate.date;
  _lastAction=@"尚未执行任何操作。";
  _observerTokens=@[];
 }
 return self;
}
- (void)viewDidLoad{
 [super viewDidLoad];
 self.title=@"跨进程分片消息（Darwin 名内载荷）";
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
 /* 接收方：只注册可以被枚举出来的固定名字（结构名/结束标记），并按需读回固定名字的状态槽。 */
 self.observerTokens=AACChunkMsgObserveStart();
 AACChunkMsgRefresh();
 AACSharedAppend(@"settings",[NSString stringWithFormat:@"分片消息接收方已启动：注册 %lu 个观察名（每 tag 结构名 78 个 + 结束标记 12 个 × 4 个 tag），状态槽按需读回；%@",(unsigned long)self.observerTokens.count,AACChunkMsgNameChannelNote()]);
 [self startPolling];
 [self.tableView reloadData];
}
- (void)dealloc{
 if(_pollTimer)dispatch_source_cancel(_pollTimer);
 AACChunkMsgObserveStop(_observerTokens);
}
- (void)startPolling{
 if(self.pollTimer)return;
 dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 if(!timer)return;
 __weak typeof(self) weakSelf=self;
 dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),(uint64_t)(3.0*NSEC_PER_SEC),1ull*NSEC_PER_SEC);
 dispatch_source_set_event_handler(timer,^{
  __strong typeof(weakSelf) strongSelf=weakSelf;if(!strongSelf)return;
  AACChunkMsgRefresh();
  [strongSelf.tableView reloadData];
 });
 self.pollTimer=timer;
 dispatch_resume(timer);
}
- (void)refresh{
 AACChunkMsgRefresh();
 self.lastAction=[NSString stringWithFormat:@"已于 %@ 重新读回本进程视角的分片消息读数（只读本进程能读到的内容）。",NSDate.date];
 [self.tableView reloadData];
}
- (void)requestAll{
 NSDictionary *statuses=AACChunkMsgRequestAll();
 NSMutableString *text=[NSMutableString stringWithFormat:@"已向四个 tag 发送按需上报请求（%@）：\n",@"com.autoanswer.call.msgrequest.<tag>"];
 for(NSString *tag in AACChunkMsgKnownTags())[text appendFormat:@"  %@ → post 状态 %@（status 0 = 已投递到 notifyd，送达该进程未确认）\n",tag,statuses[tag]];
 [text appendString:@"\n请求只让该宿主的发送端立刻重发一次；如果本进程随后仍然读不到内容，本页会如实写「未观察到」，不会假装收到。"];
 self.lastAction=text;
 AACSharedAppend(@"settings",text);
 [self scheduleFollowUpRefreshes];
 [self.tableView reloadData];
}
- (void)loopback{
 /* 本进程自测：状态槽通道的机制（notify_register_check + set_state + get_state）在本进程是否
    真的工作。它只证明本进程内可用，不证明跨进程可用。 */
 NSString *text=[NSString stringWithFormat:@"Settings 自测回环消息：本进程用同一名字族给自己发了一条分片消息，用于验证 96 槽 × 6 字节状态槽 + 16 位代次 + 长度 + CRC32 的机制在本进程是否可用（这只证明本进程内可用，不证明跨进程可用）。utc=%@",NSDate.date];
 NSDictionary *post=AACChunkMsgPublish(@"settings",text,@"settings-loopback");
 AACChunkMsgRefresh();
 self.lastAction=[NSString stringWithFormat:@"回环发送：名内载荷通道 片=%@ 发送=%@ 成功=%@ 失败=%@；状态槽通道 代次=%@ 槽=%@ 发送=%@ 成功=%@ 失败=%@。\n读回结果见下方 settings 行：如果状态槽通道显示「完整 + 校验通过」，则本进程内的机制可用；跨进程仍然未验证。",post[@"nameChannel"][@"chunkCount"],post[@"nameChannel"][@"posts"],post[@"nameChannel"][@"ok"],post[@"nameChannel"][@"failed"],post[@"stateChannel"][@"generation"],post[@"stateChannel"][@"wordCount"],post[@"stateChannel"][@"posts"],post[@"stateChannel"][@"ok"],post[@"stateChannel"][@"failed"]];
 AACSharedAppend(@"settings",self.lastAction);
 [self scheduleFollowUpRefreshes];
 [self.tableView reloadData];
}
- (void)scheduleFollowUpRefreshes{
 /* 按需上报之后（例如刚结束一次通话），在 2/5/10 秒各读一次，不必等 20 秒周期。 */
 for(NSNumber *delay in @[@2.0,@5.0,@10.0]){
  __weak typeof(self) weakSelf=self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
   __strong typeof(weakSelf) strongSelf=weakSelf;if(!strongSelf)return;
   AACChunkMsgRefresh();
   [strongSelf.tableView reloadData];
  });
 }
}
- (NSString *)timeText:(NSDate *)date{
 if(![date isKindOfClass:NSDate.class]||[date isEqualToDate:NSDate.distantPast])return @"无";
 NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"HH:mm:ss";return [f stringFromDate:date];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
 if(section==0)return AACChunkMsgKnownTags().count;
 if(section==1)return 3;
 return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 if(section==0)return [NSString stringWithFormat:@"逐 tag 读数（本页打开于 %@）",[self timeText:self.opened]];
 if(section==1)return @"操作";
 return @"通道形状、上限与诚实性说明";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 cell.detailTextLabel.numberOfLines=4;
 cell.textLabel.numberOfLines=2;
 if(indexPath.section==0){
  NSString *tag=AACChunkMsgKnownTags()[indexPath.row];
  NSDictionary *report=AACChunkMsgTagReport(tag);
  BOOL verified=[report[@"stateVerified"] boolValue];
  cell.textLabel.text=[NSString stringWithFormat:@"%@（名内片 %@/%@；状态槽 %@ 槽，校验=%@）",tag,report[@"chunksReceived"],report[@"chunksTotal"],report[@"stateWordsNeeded"],verified?@"通过":@"未通过"];
  if(verified){
   NSString *text=report[@"stateText"];
   NSString *head=text.length>160?[text substringToIndex:160]:text;
   cell.detailTextLabel.text=[NSString stringWithFormat:@"最近更新 %@（名内）/ 代次 %@（状态槽）；%@ 字节；CRC32 %@\n%@…\n落盘：%@",[self timeText:report[@"nameUpdated"]],report[@"statesGen"],report[@"stateBytes"],report[@"stateActualCrc32"],head,report[@"filePath"]];
   cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  }else{
   cell.detailTextLabel.text=[NSString stringWithFormat:@"名内片 %@/%@（完整性=%@；结束标记 %@）；状态槽代次 %@，缺 %@ 槽；%@\n最近更新 %@\n落盘：%@",report[@"chunksReceived"],report[@"chunksTotal"],([report[@"nameComplete"] boolValue]?@"完整":@"不完整"),([report[@"endSeen"] boolValue]?@"已收到":@"未收到"),report[@"statesGen"],report[@"stateWordsMissing"],report[@"stateNote"],[self timeText:report[@"nameUpdated"]],report[@"filePath"]];
   cell.accessoryType=UITableViewCellAccessoryNone;
  }
 }else if(indexPath.section==1){
  if(indexPath.row==0){cell.textLabel.text=@"请求全部宿主立刻重发一次（按需上报）";cell.detailTextLabel.text=@"POST com.autoanswer.call.msgrequest.<tag>（incall / springboard / mobilephone / settings）；只让发送端立刻重发，不保证送达，也不改变任何既有通道。";}
  else if(indexPath.row==1){cell.textLabel.text=@"本进程回环发送并读回（只证明本进程内机制）";cell.detailTextLabel.text=@"用同一名字族给自己发一条消息并读回：验证 96 槽 × 6 字节状态 + 16 位代次 + 长度 + CRC32 的机制在本进程内可用；跨进程仍然未验证。";}
  else{cell.textLabel.text=@"重新读回本进程视角读数";cell.detailTextLabel.text=@"只读本进程当前能读到的结构与状态，不缓存任何「应该收到」的假设。";}
 }else{
  cell.textLabel.text=@"名字形状 / 上限 / 本次操作结果";
  cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n\n%@\n\n%@",AACChunkMsgNameShapeText(),AACChunkMsgBoundText(),self.lastAction];
  cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
 }
 return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 if(indexPath.section==0){
  NSString *tag=AACChunkMsgKnownTags()[indexPath.row];
  AACChunkMsgRefresh();
  AACLogText([NSString stringWithFormat:@"分片消息读数（%@）",tag],AACChunkMsgTagSummaryText(tag),self.navigationController);
  return;
 }
 if(indexPath.section==1){
  if(indexPath.row==0){[self requestAll];return;}
  if(indexPath.row==1){[self loopback];return;}
  [self refresh];
  return;
 }
 AACLogText(@"跨进程分片消息：完整转储",AACChunkMsgDump(),self.navigationController);
}
@end
