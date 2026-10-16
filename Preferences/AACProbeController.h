#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "../AACSharedLog.h"
#import "AACLogViewerController.h"
/* 进程探测 / 环境清单 (1.16.0；1.13.0 建立，evidence only).
   1.16.0：本页的「到达 2 次」正是分片消息通道存在的理由（InCallService 的探测通知确实跨进程到达，
   而它的文件/偏好上报读不回来）。新增的读回页见 AACChunkMsgController.h：
   「跨进程分片消息（Darwin 名内载荷）」（名内 base64url 分片 + 固定名字状态槽 + 按需上报）。
   1.15.0 增加「宿主跨进程上报读回」一行：读回自有 CFPreferences 域 com.autoanswer.call.hostreport
   （每宿主键 + 真实 plist 路径 + 本进程实际读到的键数）。没有读到就是没有读到，不据此断言宿主未注入。
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
static inline NSArray *AACProbeWatchedProcesses(void){return @[@"mobilephone",@"springboard",@"incall",@"settings"];}
/* Must match AACProbePrefix in ../AACProbe.h; kept as a literal so the Settings
   translation unit does not need the injected-process header. */
static inline NSString *AACProbeNameText(NSString *process){return [@"com.autoanswer.call.probe." stringByAppendingString:process];}
/* Answer hosts and their own runtime-discovery files. Mirrors the host table in
   ../AACAnswerHost.h: InCallService (priority 2) then SpringBoard (priority 1). The
   Settings process only READS these files; if one is unreadable the page says so instead
   of showing an invented result, and every row names the host and the path it came from. */
static inline NSArray *AACDiscoveryHosts(void){return @[@"incall",@"springboard"];}
static inline NSString *AACDiscoveryHostLabel(NSString *tag){
 if([tag isEqualToString:@"incall"])return @"InCallService";
 if([tag isEqualToString:@"springboard"])return @"SpringBoard";
 return tag;
}
static inline NSString *AACDiscoveryFileName(NSString *tag){return [NSString stringWithFormat:@"aac-%@.discovery.txt",tag];}
/* Literal names, kept as real strings so the artifact checker (tests/deb_check.py) and a
   human reading the binary can see both files without following the format string. */
static inline NSArray *AACDiscoveryFileNames(void){return @[@"aac-incall.discovery.txt",@"aac-springboard.discovery.txt"];}
static inline NSDictionary *AACDiscoveryEntryForHost(NSString *tag){
 for(NSDictionary *entry in AACSharedViewerEntries(@[tag]))if([entry[@"kind"] isEqualToString:@"file"]&&[entry[@"process"] isEqualToString:tag]&&[entry[@"path"] hasSuffix:AACDiscoveryFileName(tag)])return entry;
 return nil;
}
/* Highest-priority host (InCallService, then SpringBoard) that produced a discovery file. */
static inline NSDictionary *AACDiscoveryEntry(void){
 for(NSString *tag in AACDiscoveryHosts()){NSDictionary *entry=AACDiscoveryEntryForHost(tag);if(entry)return entry;}
 return nil;
}
static inline NSString *AACDiscoveryLabelForEntry(NSDictionary *entry){
 NSString *tag=entry[@"process"];
 return [NSString stringWithFormat:@"%@（%@）",AACDiscoveryHostLabel(tag),entry[@"path"]?:@"路径未知"];
}
static inline NSUInteger AACCountOccurrences(NSString *needle,NSString *haystack){
 if(!needle.length||!haystack.length)return 0;NSUInteger count=0,start=0;
 while(start<haystack.length){NSRange r=[haystack rangeOfString:needle options:0 range:NSMakeRange(start,haystack.length-start)];if(r.location==NSNotFound)break;count++;start=r.location+r.length;}
 return count;
}
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
 /* 1.13.0（沿用 1.12.0 结构）: every answer host answers the same ping on its own pong name, so this page
    shows per-host pong counters without pretending the phone app responded. */
 int sbPong=0;
 if(notify_register_dispatch("com.autoanswer.call.pong.springboard",&sbPong,dispatch_get_main_queue(),^(int t){[weakSelf record:@"springboard-pong"];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(sbPong)];
 int icPong=0;
 if(notify_register_dispatch("com.autoanswer.call.pong.incall",&icPong,dispatch_get_main_queue(),^(int t){[weakSelf record:@"incall-pong"];})==NOTIFY_STATUS_OK)[self.tokens addObject:@(icPong)];
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
 if(section==2)return AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"incall",@"settings"]).count;
 if(section==3)return 4;
 return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 if(section==0)return [NSString stringWithFormat:@"本页打开后收到的进程通知（%@ 起）",[self timeText:self.opened]];
 if(section==1)return @"模块伴随记录与回环测试";
 if(section==2)return @"共享日志候选路径（逐路径结果）";
 if(section==3)return @"接听宿主运行时发现/挂钩结果（runtime-discovered，非硬编码；逐宿主标注）";
 return @"说明";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==0)return @"每个进程使用独立通知名 com.autoanswer.call.probe.<进程>；Darwin 通知无载荷，所以这里只按名称区分进程。未到达只表示本页没观察到，不等于该进程未注入。";
 if(section==2)return @"这是设置进程自己的读写结果；另一个进程中同一路径是否可写必须看该进程写入的日志，不能由此推断跨进程可见。";
 if(section==3)return @"这些文件是各宿主在设备上枚举 objc_getClassList 得到的真实类/方法名（含分类 ACTION/ACCESSOR/FORBIDDEN/UNSUPPORTED、HOOKED 与跳过原因），构建不保证这些私有类在 iOS 17.3 存在。接听由唯一负责宿主提交：角色表 InCallService(2) > SpringBoard(1) > 仅日志(0)。若某宿主显示 0 个已挂钩方法，它在该设备上只能退化为仅日志，插件不会谎报接听成功。";
 if(section==4)return @"1.17.0：接听主策略改为「活体按钮发现 + 模拟点击」，方法名关键字发现（ACTION/ACCESSOR 分类）保留但已知不足、不再是主策略——设备证据（1.16.0 分片回读）显示三个宿主全部自报 role=LOG-ONLY、answerPaths=0，因为真正的接听是一个 UI 按钮，它的响应走 UIControl 的 action 机制（sendActionsForControlEvents:），方法名里永远不会出现 answer/accept，关键字匹配在原理上不可能命中它。1.17.0 在来电期间遍历活体层级（≤6000 节点、深度 ≤40、1.5 秒预算）收集候选 UIControl，按 accessibilityIdentifier > accessibilityLabel > accessibilityValue > 标题 > 已知本地化子串 > 绿色左侧主按钮（弱信号）打分，记录每一个候选，然后按 (1) sendActionsForControlEvents:UIControlEventTouchUpInside (2) 追加 UIControlEventTouchDown (3) allTargets/actionsForTarget + NSInvocation 的顺序真正点击；拒绝/挂断关键字与红色主导控件一律列入黑名单绝不点击，每个通话 UUID 每个宿主只点一次，低优先级宿主在 1.2 秒结算窗口后看到更高优先级宿主的 buttontap 通知就让出。候选、所选控件、所用机制与随后是否接通都写进发现文件（BUTTON 候选分节）、共享日志，并通过 1.16.0 的分片/状态槽通道一起发布。这一路径同样未在设备验证，点击机制成功只表示事件被发出，绝不等于已接通。本页不能证明接听可用；1.16.0 新增的跨进程分片消息通道（名内载荷 12 片 × 900 字符 / 总解码 12288 字节 + 固定名字状态槽 96 槽 × 6 字节、16 位代次 + 长度 + CRC32，按需上报 com.autoanswer.call.msgrequest.<tag>）同样未在设备验证，请在「跨进程分片消息」页看本进程的真实读数；1.15.0 的 InCallService/SpringBoard 接听路径仍未在设备验证（1.15.0 修正的是候选分类：属性访问器 ACCESSOR 不再计入 answerPaths，只有 ACTION 才算接听路径，因此只有访问器的宿主是 LOG-ONLY 而不是 OWNER；1.14.0 修正的是归属判定），依赖运行时到底存在哪个私有 UI 类。";
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
   NSArray *legacy=self.arrivals[@"mobilephone-legacy-pong"];NSArray *sbArrivals=self.arrivals[@"springboard-pong"];NSArray *icArrivals=self.arrivals[@"incall-pong"];
   cell.textLabel.text=@"ping 应答计数：电话旧通道 / SpringBoard / InCallService";
   cell.detailTextLabel.text=[NSString stringWithFormat:@"MobilePhone pong=%lu 次；SpringBoard pong=%lu 次；InCallService pong=%lu 次；最近 %@（未到达只表示本页未观察到，不等于该进程未注入）",(unsigned long)legacy.count,(unsigned long)sbArrivals.count,(unsigned long)icArrivals.count,icArrivals.count?[self timeText:icArrivals.lastObject]:(sbArrivals.count?[self timeText:sbArrivals.lastObject]:(legacy.count?[self timeText:legacy.lastObject]:@"无"))];
  }
 }else if(indexPath.section==1){
  if(indexPath.row==0){cell.textLabel.text=@"本机回环测试（发送并等待自身通知）";cell.detailTextLabel.text=self.loopbackStatus;}
  else{cell.textLabel.text=@"伴随键记录";cell.detailTextLabel.text=[@"CFPreferences com.autoanswer.call.probe（跨进程可见性不保证）\n" stringByAppendingString:AACSharedProbeCompanionDump()];}
 }else if(indexPath.section==2){
  NSDictionary *entry=AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"incall",@"settings"])[indexPath.row];
  BOOL exists=[entry[@"exists"] boolValue];BOOL readable=[entry[@"readable"] boolValue];
  cell.textLabel.text=entry[@"label"];
  if([entry[@"kind"] isEqualToString:@"dir"])cell.detailTextLabel.text=[NSString stringWithFormat:@"目录：%@；本进程可写=%@\n%@",exists?@"存在":@"不存在",[entry[@"writable"] boolValue]?@"是":@"否",entry[@"path"]];
  else cell.detailTextLabel.text=[NSString stringWithFormat:@"%@；可读=%@；%llu 字节\n%@",exists?@"文件存在":@"未创建",readable?@"是":@"否",[entry[@"size"] unsignedLongLongValue],entry[@"path"]];
  cell.accessoryType=readable?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
 }else if(indexPath.section==3){
  if(indexPath.row==3){
   NSMutableArray *lines=[NSMutableArray new];
   for(NSDictionary *entry in AACHostReportEntries())[lines addObject:[NSString stringWithFormat:@"%@：%@；%lu 字符\n%@",entry[@"label"],entry[@"note"],(unsigned long)[entry[@"size"] unsignedLongLongValue],entry[@"path"]]];
   cell.textLabel.text=@"宿主跨进程上报读回（自有 CFPreferences 域）";
   cell.detailTextLabel.text=[NSString stringWithFormat:@"域：%@（每宿主独立键，载荷有上限）。本进程实际读到的内容如下；读不到不代表该宿主未注入。\n%@",AACHostReportDomain,[lines componentsJoinedByString:@"\n"]];
   cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  }else if(indexPath.row==2){cell.textLabel.text=@"打开完整发现清单（类/方法/跳过原因）";NSString *t=nil;NSDictionary *e=AACDiscoveryEntry();if(e)t=AACSharedReadFile(e[@"path"],NULL);cell.detailTextLabel.text=t.length?[NSString stringWithFormat:@"来自 %@；点击查看该宿主实际枚举到的类与已挂钩方法。",AACDiscoveryLabelForEntry(e)]:@"暂无可读内容";cell.accessoryType=t.length?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;}
  else if(indexPath.row==1){
   NSMutableArray *lines=[NSMutableArray new];
   for(NSString *tag in AACDiscoveryHosts()){
    NSDictionary *entry=AACDiscoveryEntryForHost(tag);BOOL readable=entry?[entry[@"readable"] boolValue]:NO;
    [lines addObject:[NSString stringWithFormat:@"%@：%@%@",AACDiscoveryHostLabel(tag),entry?(readable?@"文件可读":@"文件存在但不可读"):@"未创建（该宿主未注入或尚未枚举）",entry?[NSString stringWithFormat:@"；路径 %@；%llu 字节",entry[@"path"],[entry[@"size"] unsignedLongLongValue]]:@""]];
   }
   cell.textLabel.text=@"全部宿主发现文件（逐宿主 + 路径）";
   cell.detailTextLabel.text=[lines componentsJoinedByString:@"\n"];
  }else{
   cell.textLabel.text=@"发现摘要（runtime-discovered，逐宿主）";
   NSMutableArray *lines=[NSMutableArray new];BOOL any=NO;
   for(NSString *tag in AACDiscoveryHosts()){
    NSDictionary *entry=AACDiscoveryEntryForHost(tag);NSString *text=entry?AACSharedReadFile(entry[@"path"],NULL):nil;
    if(text.length)any=YES;
    NSUInteger hooked=AACCountOccurrences(@"  HOOKED ",text);
    NSString *role=@"角色未知";if([text rangeOfString:@"role=OWNER"].location!=NSNotFound)role=@"OWNER（负责接听）";else if([text rangeOfString:@"role=OBSERVER"].location!=NSNotFound)role=@"OBSERVER（仅观察）";else if([text rangeOfString:@"role=LOG-ONLY"].location!=NSNotFound)role=@"LOG-ONLY";
    [lines addObject:[NSString stringWithFormat:@"%@：%@；已挂钩方法=%lu%@",AACDiscoveryHostLabel(tag),text.length?role:@"没有可读的发现文件",(unsigned long)hooked,entry?[NSString stringWithFormat:@"（%@）",entry[@"path"]]:@""]];
   }
   cell.detailTextLabel.text=any?[lines componentsJoinedByString:@"\n"]:[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n没有可读的发现文件：各接听宿主可能未注入或尚未枚举；这不代表接听可用。"];
  }
 }else{
  cell.textLabel.text=@"点击一行可重新探测；这里不会伪造成功状态";
  cell.detailTextLabel.text=@"未观察到到达时，请结合共享日志查看器与电话诊断判断，不要据此推断接听可用。";
 }
 return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 if(indexPath.section==0||indexPath.section==4){[self refresh];return;}
 if(indexPath.section==3){
  if(indexPath.row==3){AACLogText([NSString stringWithFormat:@"宿主跨进程上报读回（%@）",AACHostReportDomain],AACHostReportDump(),self.navigationController);return;}
  if(indexPath.row==0||indexPath.row==1){[self.tableView reloadData];return;}
  NSDictionary *found=AACDiscoveryEntry();NSError *error=nil;NSString *text=found?AACSharedReadFile(found[@"path"],&error):nil;
  NSString *title=found?[NSString stringWithFormat:@"运行时发现清单（%@）",AACDiscoveryLabelForEntry(found)]:@"运行时发现清单";
  AACLogText(title,text?:[NSString stringWithFormat:@"读取失败或文件不存在：%@（候选文件 %@；没有任何宿主的发现文件可读）",error.localizedDescription?:@"未创建",[AACDiscoveryFileNames() componentsJoinedByString:@"、"]],self.navigationController);
  return;}
 if(indexPath.section==1){if(indexPath.row==0)[self loopback];else AACLogText(@"伴随键记录",AACSharedProbeCompanionDump(),self.navigationController);return;}
 NSDictionary *entry=AACSharedViewerEntries(@[@"mobilephone",@"springboard",@"incall",@"settings"])[indexPath.row];
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
