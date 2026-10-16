#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "../AACSharedLog.h"
#import "AACLogViewerController.h"
/* 进程探测 / 环境清单 (1.10.0, evidence only).
   Darwin notifications carry no payload, so this page registers one observer per
   process notification name and timestamps arrivals. Nothing on this page claims that
   the phone module was injected, that answering works, or that any cross-process path
   is shared; a missing arrival is reported as "not observed here". */
@interface AACProbeController : UITableViewController
@property(nonatomic,strong) NSMutableArray<NSNumber *> *tokens;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableArray<NSDate *> *> *arrivals;
@property(nonatomic,strong) NSDate *opened;
@property(nonatomic,copy) NSString *loopbackStatus;
@property(nonatomic) NSUInteger loopbackCount;
@property(nonatomic) int loopbackToken;
@property(nonatomic) BOOL observingLoopback;
@end
static inline NSArray *AACProbeWatchedProcesses(void){return @[@"mobilephone",@"springboard",@"settings"];}
/* Must match AACProbePrefix in ../AACProbe.h; kept as a literal so the Settings
   translation unit does not need the injected-process header. */
static inline NSString *AACProbeNameText(NSString *process){return [@"com.autoanswer.call.probe." stringByAppendingString:process];}
@implementation AACProbeController
- (instancetype)initWithStyle:(UITableViewStyle)style{
 if((self=[super initWithStyle:style])){
  _tokens=[NSMutableArray new];_arrivals=[NSMutableDictionary new];_opened=NSDate.date;
  _loopbackStatus=@"尚未测试：回环只证明设置进程自身能收发 Darwin 通知，不证明其他进程已注入。";
  for(NSString *process in AACProbeWatchedProcesses())_arrivals[process]=[NSMutableArray new];
 }
 return self;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"进程探测 / 环境清单";
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
 __weak typeof(self) weakSelf=self;
 for(NSString *process in AACProbeWatchedProcesses()){
  NSString *name=AACProbeNameText(process);int token=0;
  uint32_t status=notify_register_dispatch(name.UTF8String,&token,dispatch_get_main_queue(),^(int t){[weakSelf record:process];});
  if(status==NOTIFY_STATUS_OK)[self.tokens addObject:@(token)];
  else self.loopbackStatus=[NSString stringWithFormat:@"注册 %@ 失败（notify 状态 %u）；该进程的到达记录不可用。",name,status];
 }
 /* Legacy 1.9.x ping/pong probe is kept so the old behaviour is unchanged. */
 int pong=0;
 if(notify_register_dispatch("com.autoanswer.call.pong",&pong,dispatch_get_main_queue(),^(int t){[weakSelf record:@"mobilephone-legacy-pong"];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(pong)];
 [self.tableView reloadData];
}
- (void)dealloc{for(NSNumber *token in _tokens)notify_cancel(token.intValue);}
- (void)record:(NSString *)process{
 if(![self.arrivals[process] isKindOfClass:NSMutableArray.class])self.arrivals[process]=[NSMutableArray new];
 [self.arrivals[process] addObject:NSDate.date];
 NSString *line=[NSString stringWithFormat:@"probe arrival observed on the settings side: %@ (count=%lu)",process,(unsigned long)[self.arrivals[process] count]];
 AACSharedAppend(@"settings",line);
 [self.tableView reloadData];
}
- (void)refresh{
 [self.tableView reloadData];
 /* Legacy probe: the phone module answers this if it is loaded and responsive. */
 uint32_t status=notify_post("com.autoanswer.call.ping");
 AACSharedAppend(@"settings",[NSString stringWithFormat:@"legacy Darwin ping posted status=%u from the probe page",status]);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.tableView reloadData];});
}
- (void)loopback{
 self.loopbackCount=0;
 __weak typeof(self) weakSelf=self;
 int token=0;
 __block uint32_t reg=NOTIFY_STATUS_FAILED;
 reg=notify_register_dispatch(AACProbeNameText(@"settings").UTF8String,&token,dispatch_get_main_queue(),^(int t){weakSelf.loopbackCount++;weakSelf.loopbackStatus=[NSString stringWithFormat:@"回环成功：本进程已收到自身通知（注册状态 %u，计数 %lu）。只证明设置进程内 Darwin 通知可用。",reg,(unsigned long)weakSelf.loopbackCount];[weakSelf.tableView reloadData];});
 if(reg==NOTIFY_STATUS_OK){self.loopbackToken=token;self.observingLoopback=YES;}
 uint32_t post=notify_post(AACProbeNameText(@"settings").UTF8String);
 self.loopbackStatus=[NSString stringWithFormat:@"已发送自身探测通知 post=%u 注册=%u；2 秒后未计数即为本进程 Darwin 通知不可用。",post,reg];
 [self.tableView reloadData];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  __strong typeof(weakSelf) strongSelf=weakSelf;if(!strongSelf)return;
  if(strongSelf.loopbackCount==0)strongSelf.loopbackStatus=[NSString stringWithFormat:@"回环失败：post=%u 注册=%u，2 秒内未收到自身通知。",post,reg];
  [strongSelf.tableView reloadData];
 });
 if(self.observingLoopback&&self.loopbackToken)[self.tokens addObject:@(self.loopbackToken)];
}
- (NSString *)timeText:(NSDate *)date{NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"HH:mm:ss";return [f stringFromDate:date];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
 if(section==0)return AACProbeWatchedProcesses().count+1;
 if(section==1)return 2;
 if(section==2)return AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"settings"]).count;
 return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 if(section==0)return [NSString stringWithFormat:@"本页打开后收到的进程通知（%@ 起）",[self timeText:self.opened]];
 if(section==1)return @"模块伴随记录与回环测试";
 if(section==2)return @"共享日志候选路径（逐路径结果）";
 return @"说明";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==0)return @"每个进程使用独立通知名 com.autoanswer.call.probe.<进程>；Darwin 通知无载荷，所以这里只按名称区分进程。未到达只表示本页没观察到，不等于该进程未注入。";
 if(section==2)return @"这是设置进程自己的读写结果；另一个进程中同一路径是否可写必须看该进程写入的日志，不能由此推断跨进程可见。";
 if(section==3)return @"本页不能证明接听可用；1.10.0 只采集注入与日志通道证据，未做设备验证。";
 return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.detailTextLabel.numberOfLines=3;cell.textLabel.numberOfLines=2;
 if(indexPath.section==0){
  if(indexPath.row<AACProbeWatchedProcesses().count){
   NSString *process=AACProbeWatchedProcesses()[indexPath.row];NSArray *dates=self.arrivals[process];
   cell.textLabel.text=[NSString stringWithFormat:@"%@（%@）",process,AACProbeNameText(process)];
   cell.detailTextLabel.text=dates.count?[NSString stringWithFormat:@"到达 %lu 次；最近 %@",(unsigned long)dates.count,[self timeText:dates.lastObject]]:@"本次未观察到到达；不代表该进程未注入";
   cell.accessoryType=dates.count?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
  }else{
   NSArray *legacy=self.arrivals[@"mobilephone-legacy-pong"];
   cell.textLabel.text=@"旧版 ping/pong（com.autoanswer.call.pong）";
   cell.detailTextLabel.text=legacy.count?[NSString stringWithFormat:@"到达 %lu 次；最近 %@",(unsigned long)legacy.count,[self timeText:legacy.lastObject]]:@"本次未观察到 pong；可能未注入、进程休眠或通知不可达";
  }
 }else if(indexPath.section==1){
  if(indexPath.row==0){cell.textLabel.text=@"本机回环测试（发送并等待自身通知）";cell.detailTextLabel.text=self.loopbackStatus;}
  else{cell.textLabel.text=@"伴随键记录";cell.detailTextLabel.text=[@"CFPreferences com.autoanswer.call.probe（跨进程可见性不保证）\n" stringByAppendingString:AACSharedProbeCompanionDump()];}
 }else if(indexPath.section==2){
  NSDictionary *entry=AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"settings"])[indexPath.row];
  BOOL exists=[entry[@"exists"] boolValue];BOOL readable=[entry[@"readable"] boolValue];
  cell.textLabel.text=entry[@"label"];
  if([entry[@"kind"] isEqualToString:@"dir"])cell.detailTextLabel.text=[NSString stringWithFormat:@"目录：%@；本进程可写=%@\n%@",exists?@"存在":@"不存在",[entry[@"writable"] boolValue]?@"是":@"否",entry[@"path"]];
  else cell.detailTextLabel.text=[NSString stringWithFormat:@"%@；可读=%@；%llu 字节\n%@",exists?@"文件存在":@"未创建",readable?@"是":@"否",[entry[@"size"] unsignedLongLongValue],entry[@"path"]];
  cell.accessoryType=readable?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
 }else{
  cell.textLabel.text=@"点击一行可重新探测；这里不会伪造成功状态";
  cell.detailTextLabel.text=@"未观察到到达时，请结合共享日志查看器与电话诊断判断，不要据此推断接听可用。";
 }
 return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 if(indexPath.section==0||indexPath.section==3){[self refresh];return;}
 if(indexPath.section==1){if(indexPath.row==0)[self loopback];else AACLogText(@"伴随键记录",AACSharedProbeCompanionDump(),self.navigationController);return;}
 NSDictionary *entry=AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"settings"])[indexPath.row];
 if(![entry[@"readable"] boolValue])return;
 if([entry[@"kind"] isEqualToString:@"dir"]){
  NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:entry[@"path"] error:nil];
  AACLogText(entry[@"path"],[NSString stringWithFormat:@"目录内容（最多列出的实际条目）：\n%@",files.count?[files componentsJoinedByString:@"\n"]:@"空或不可读"],self.navigationController);
  return;
 }
 NSError *error=nil;NSString *text=AACSharedReadFile(entry[@"path"],&error);
 AACLogText(entry[@"label"],text?:[NSString stringWithFormat:@"读取失败：%@",error.localizedDescription?:@"未知错误"],self.navigationController);
}
@end
