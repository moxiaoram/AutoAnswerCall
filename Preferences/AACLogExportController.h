#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../AACSharedLog.h"
#import "../AACChunkMsg.h"
#import "../AACRecords.h"
#import "AACLogViewerController.h"
/* 运行日志导出 / 分享 (1.16.0；1.13.0 建立）。
   用户要求「增加所有运行日志可以分享被打开」：本文件把所有已经存在或应当存在的运行日志集中成
   一张清单，逐项记录 存在 / 大小 / 可读 / 缺失原因，然后
     - 「分享全部运行日志」把清单里真实存在的文件复制到临时导出目录后一次性交给
       UIActivityViewController（多个文件 URL，不打包、不改内容），并同时分享一份报告文本；
     - 「运行日志文件：逐项查看 / 分享」列出同一张清单，点行看文本、点 ⓘ 单独分享。
   诚实性规则（与 1.9.x~1.12.0 一致）：目录/文件是否存在、是否可读一律用 NSFileManager 实际读取；
   找不到的文件写「未创建」并给出原因（候选目录不存在 / 该目录里没有此文件 / 另一进程的跨进程
   可见性未验证），绝不虚构条目，也绝不在报告里声称自动接听可用。所有生成的文件只包含本插件
   自有偏好域与自有日志，不含任何凭据。 */

static NSString * const AACExportDomain=@"com.autoanswer.call";
/* The four hosts whose per-process files are collected. Mirrors the host table in
   ../AACAnswerHost.h (kept as literals so the Settings translation unit does not need the
   injected-process header, exactly like AACProbeController.h does). */
static inline NSArray *AACExportHosts(void){return @[@"incall",@"springboard",@"mobilephone",@"settings"];}
static inline NSString *AACExportHostLabel(NSString *tag){
 if([tag isEqualToString:@"incall"])return @"InCallService";
 if([tag isEqualToString:@"springboard"])return @"SpringBoard";
 if([tag isEqualToString:@"mobilephone"])return @"MobilePhone";
 if([tag isEqualToString:@"settings"])return @"Settings";
 return tag;
}
/* Literal discovery file names, like AACProbeController.h: readable in the binary itself. */
static inline NSArray *AACExportDiscoveryFiles(void){return @[@"aac-incall.discovery.txt",@"aac-springboard.discovery.txt"];}
static inline NSString *AACExportDiscoveryHost(NSString *leaf){return [leaf hasPrefix:@"aac-incall"]?@"incall":@"springboard";}
/* Settings-side directory: same resolution as the settings log and the audio library. */
static inline NSString *AACExportLocalDir(NSError **error){
 NSError *e=nil;
 NSURL *url=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&e];
 if(!url){if(error)*error=e;return nil;}
 NSString *path=[url.path stringByAppendingPathComponent:@"AutoAnswerCall"];
 if(![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&e]){if(error)*error=e;return nil;}
 return path;
}
static inline NSUserDefaults *AACExportDefaults(void){return [[NSUserDefaults alloc] initWithSuiteName:AACExportDomain];}
static inline NSString *AACExportErrorText(NSError *e,NSString *fallback){
 if([e isKindOfClass:NSError.class])return [NSString stringWithFormat:@"%@ (%@/%ld)",e.localizedDescription?:fallback,e.domain,(long)e.code];
 return [e isKindOfClass:NSString.class]?(NSString *)e:fallback;
}
static inline BOOL AACExportWriteText(NSString *dir,NSString *name,NSString *text,NSString **error){
 if(!dir||!name.length){if(error)*error=@"没有可写目录";return NO;}
 NSError *e=nil;
 NSString *body=[text isKindOfClass:NSString.class]?text:@"";
 if(![body writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:&e]){
  if(error)*error=AACExportErrorText(e,@"写入失败");
  return NO;
 }
 return YES;
}
/* Exported configuration: our own preference domain only, no Apple key is invented. */
static inline NSDictionary *AACExportConfiguration(void){
 NSMutableDictionary *config=[NSMutableDictionary new];
 NSUserDefaults *defaults=AACExportDefaults();
 for(NSString *key in @[@"Mode",@"Enabled",@"Delay",@"Whitelist",@"PlayAudio",@"AudioPath",@"AudioName",@"AudioSize",@"SelectedAudioID"]){id value=[defaults objectForKey:key];if(value)config[key]=value;}
 config[@"Version"]=@"1.16.0";
 config[@"ExportedAt"]=NSDate.date;
 config[@"ExportSource"]=@"AutoAnswerCall Settings 运行日志导出（仅本插件自有偏好域与自有日志文件；不含凭据）";
 return config;
}
static inline NSString *AACExportRecordsText(NSString **note){
 BOOL synced=NO,present=NO;
 NSArray *records=AACReadRecords(&synced,&present);
 NSMutableString *text=[NSMutableString stringWithFormat:@"# AutoAnswerCall 接听记录导出 (1.16.0)\n# 域名=%@ key=Records synchronized=%d present=%d count=%lu\n# 导出时刻=%@（时间戳为通话事件观察时刻）\n\n",AACRecordDomain,synced,present,(unsigned long)records.count,NSDate.date];
 if(!records.count)[text appendString:@"（本进程读不到任何记录：可能从未写入，或另一进程写入对这里不可见——跨进程可见性未验证。）\n"];
 for(NSDictionary *record in records){
  [text appendFormat:@"%@  %@  %@\n",record[@"timestamp"],record[@"id"],record[@"caller"]?:@"(号码不可得)"];
  [text appendFormat:@"    结果：%@\n",record[@"result"]?:@"(未判定)"];
  [text appendFormat:@"    状态：%@\n",record[@"status"]?:@"(无)"];
  for(NSDictionary *event in record[@"events"])[text appendFormat:@"      - %@ %@\n",event[@"timestamp"],event[@"status"]];
  [text appendString:@"\n"];
 }
 if(note)*note=[NSString stringWithFormat:@"记录 %lu 条（synchronized=%d present=%d）",(unsigned long)records.count,synced,present];
 return text;
}
/* Writes every derived file into the Settings Application Support directory so the same
   read/copy code paths are used for them as for the pre-existing settings log. */
static inline NSArray *AACExportPrepare(NSString **summary){
 NSMutableArray *notes=[NSMutableArray new];
 NSError *error=nil;
 NSString *why=nil;
 NSString *dir=AACExportLocalDir(&error);
 if(!dir){[notes addObject:[@"设置侧目录不可用：" stringByAppendingString:AACExportErrorText(error,@"Application Support 不可写")]];if(summary)*summary=[notes componentsJoinedByString:@"；"];return notes;}
 NSError *plistError=nil;
 NSData *config=[NSPropertyListSerialization dataWithPropertyList:AACExportConfiguration() format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
 if([config isKindOfClass:NSData.class]&&[config writeToFile:[dir stringByAppendingPathComponent:@"configuration.plist"] options:NSDataWritingAtomic error:&error])
  [notes addObject:@"configuration.plist：已按当前设置重新生成"];
 else
  [notes addObject:[@"configuration.plist：生成失败 " stringByAppendingString:AACExportErrorText([config isKindOfClass:NSData.class]?error:plistError,@"写入或序列化失败")]];
 NSString *recordsNote=nil;
 NSString *records=AACExportRecordsText(&recordsNote);
 if(AACExportWriteText(dir,@"call-records.txt",records,&why))[notes addObject:[NSString stringWithFormat:@"call-records.txt：已生成（%@）",recordsNote?:@"无说明"]];
 else [notes addObject:[@"call-records.txt：生成失败 " stringByAppendingString:why?:@"写入失败"]];
 if(AACExportWriteText(dir,@"shared-prefs-fallback.txt",AACSharedPrefsDump(),&why))[notes addObject:@"shared-prefs-fallback.txt：已生成（本进程视角的 CFPreferences 回退域内容）"];
 else [notes addObject:[@"shared-prefs-fallback.txt：生成失败 " stringByAppendingString:why?:@"写入失败"]];
 if(AACExportWriteText(dir,@"host-report.txt",AACHostReportDump(),&why))[notes addObject:@"host-report.txt：已生成（宿主跨进程上报域读回；只包含本进程实际读到的键与真实 plist 路径）"];
 else [notes addObject:[@"host-report.txt：生成失败 " stringByAppendingString:why?:@"写入失败"]];
 /* 1.16.0 TASK 1: the chunked Darwin message read-back. Written here so the export always
    contains it; it reports only what THIS process actually read (per tag: name-channel chunk
    arrivals, state-slot generation/completeness/CRC verification, and the reassembled text). */
 if(AACExportWriteText(dir,@"host-messages.txt",AACChunkMsgDump(),&why))[notes addObject:@"host-messages.txt：已生成（跨进程分片消息读回；只包含本进程实际读到的片/槽、完整性、CRC32 校验结果与重组文本）"];
 else [notes addObject:[@"host-messages.txt：生成失败 " stringByAppendingString:why?:@"写入失败"]];
 if(AACExportWriteText(dir,@"probe-companion.txt",AACSharedProbeCompanionDump(),&why))[notes addObject:@"probe-companion.txt：已生成（模块伴随探测记录）"];
 else [notes addObject:[@"probe-companion.txt：生成失败 " stringByAppendingString:why?:@"写入失败"]];
 if(summary)*summary=[notes componentsJoinedByString:@"；"];
 return notes;
}
static inline NSDictionary *AACExportEntry(NSString *group,NSString *host,NSString *label,NSString *path,NSString *missingReason){
 NSFileManager *manager=[NSFileManager defaultManager];
 BOOL isDirectory=NO;
 BOOL exists=[manager fileExistsAtPath:path isDirectory:&isDirectory];
 NSDictionary *attributes=exists?[manager attributesOfItemAtPath:path error:nil]:nil;
 unsigned long long size=[attributes[NSFileSize] isKindOfClass:NSNumber.class]?[attributes[NSFileSize] unsignedLongLongValue]:0;
 BOOL readable=exists&&!isDirectory&&[manager isReadableFileAtPath:path];
 NSString *note=exists?[NSString stringWithFormat:@"%@；%llu 字节；可读=%@",isDirectory?@"目录":@"文件",size,readable?@"是":@"否"]:missingReason;
 NSString *flatPrefix=[NSString stringWithFormat:@"%@-%@",group,host?:@"settings"];
 flatPrefix=[flatPrefix stringByReplacingOccurrencesOfString:@" " withString:@"_"];
 NSString *flat=[NSString stringWithFormat:@"%@__%@",flatPrefix,path.lastPathComponent];
 return @{@"group":group,@"host":host?:@"settings",@"label":label,@"path":path,@"leaf":path.lastPathComponent,@"exists":@(exists&&!isDirectory),@"isDirectory":@(isDirectory),@"size":@(size),@"readable":@(readable),@"note":note?:@"未创建",@"flat":flat};
}
/* The full 清单: every shared directory × every per-process file, plus the Settings-side ones.
   Nothing here is fabricated: each entry carries the real filesystem answer and, when the file
   is missing, the reason why it could not be produced from this process. */
static inline NSDictionary *AACExportGather(void){
 NSMutableArray *entries=[NSMutableArray new];
 NSFileManager *manager=[NSFileManager defaultManager];
 NSError *error=nil;
 NSString *dir=AACExportLocalDir(&error);
 for(NSDictionary *candidate in AACSharedLogCandidateDirs()){
  NSString *base=candidate[@"dir"];
  NSString *label=candidate[@"label"];
  BOOL isDirectory=NO;
  BOOL dirExists=[manager fileExistsAtPath:base isDirectory:&isDirectory];
  dirExists=dirExists&&isDirectory;
  for(NSString *host in AACExportHosts()){
   NSString *missing=dirExists?[NSString stringWithFormat:@"未创建：候选目录 %@ 存在，但该进程没有在里面写这个文件（跨进程可见性未验证）",label]:[NSString stringWithFormat:@"未创建：候选目录不可用（%@：本进程读不到或不可写）",label];
   [entries addObject:AACExportEntry(@"shared-log",host,[NSString stringWithFormat:@"%@ 共享日志",AACExportHostLabel(host)],[base stringByAppendingPathComponent:AACSharedFileLeaf(host,@"log")],missing)];
   [entries addObject:AACExportEntry(@"inventory",host,[NSString stringWithFormat:@"%@ 运行清单",AACExportHostLabel(host)],[base stringByAppendingPathComponent:AACSharedFileLeaf(host,@"txt")],missing)];
   /* 1.16.0 TASK 1: the per-tag reassembled chunked message persisted next to the shared logs. */
   [entries addObject:AACExportEntry(@"host-messages",host,[NSString stringWithFormat:@"%@ 分片消息读回文件",AACExportHostLabel(host)],[base stringByAppendingPathComponent:AACSharedFileLeaf(host,@"host-messages.txt")],missing)];
  }
  for(NSString *leaf in AACExportDiscoveryFiles()){
   NSString *host=AACExportDiscoveryHost(leaf);
   NSString *missing=dirExists?[NSString stringWithFormat:@"未创建：候选目录 %@ 存在，但该宿主没有写出运行时发现文件（宿主未注入或发现尚未运行）",label]:[NSString stringWithFormat:@"未创建：候选目录不可用（%@）",label];
   [entries addObject:AACExportEntry(@"discovery",host,[NSString stringWithFormat:@"%@ 运行时发现文件",AACExportHostLabel(host)],[base stringByAppendingPathComponent:leaf],missing)];
  }
 }
 NSString *localReason=dir?@"未创建：设置侧目录里没有此文件（尚未生成或已被清除）":@"未创建：设置侧 Application Support 目录不可用";
 /* 1.15.0 TASK 1: the shared host-report domain and its REAL on-disk plist path. The entry
    carries the actual existence/readability answer of that path in this process, and the
    host-report.txt copy carries the read-back dump. */
 for(NSDictionary *entry in AACHostReportEntries()){
  /* Only the entry whose "path" is the REAL plist file of the domain is added here; the
     per-host rows carry a CFPreferences KEY, not a file path, and are shown in the read-back
     text instead of being reported as a missing file. */
  if(![entry[@"path"] hasSuffix:@".plist"])continue;
  [entries addObject:AACExportEntry(@"host-report",@"settings",entry[@"label"],entry[@"path"],entry[@"note"])];
 }
 for(NSArray *pair in @[@[@"设置模块日志",@"settings.log"],@[@"导出的配置 plist",@"configuration.plist"],@[@"接听记录导出文本",@"call-records.txt"],@[@"CFPreferences 回退域内容",@"shared-prefs-fallback.txt"],@[@"模块伴随探测记录",@"probe-companion.txt"],@[@"跨进程分片消息读回",@"host-messages.txt"],@[@"音频库元数据",@"audio-library.plist"]]){
  [entries addObject:AACExportEntry(@"settings",@"settings",pair[0],dir?[dir stringByAppendingPathComponent:pair[1]]:pair[1],localReason)];
 }
 [entries addObject:AACExportEntry(@"settings",@"settings",@"宿主跨进程上报读回文本",dir?[dir stringByAppendingPathComponent:@"host-report.txt"]:@"host-report.txt",localReason)];
 NSUInteger found=0,missing=0;
 for(NSDictionary *entry in entries){if([entry[@"exists"] boolValue])found++;else missing++;}
 NSMutableString *report=[NSMutableString stringWithFormat:@"# AutoAnswerCall 运行日志导出报告 (1.16.0)\n# 生成时刻=%@\n# 设置侧目录=%@\n# 说明：下表逐项列出所有应当存在的运行日志路径及其在本进程中的真实状态。\n#       存在的条目会被复制到临时导出目录并一起分享；缺失的条目写明原因，不做任何虚构。\n#       跨进程可写/可读没有在 RootHide 上验证过，因此「未创建」既可能是没有写入，也可能是写到了\n#       另一个进程可写、本进程不可见的候选路径。\n#       本报告只描述文件是否存在与是否可读：它不能证明自动接听可用，也不能证明任何宿主已注入。\n\n存在 %lu 项，缺失 %lu 项，共 %lu 项。\n\n",NSDate.date,dir?:@"(设置侧目录不可用)",(unsigned long)found,(unsigned long)missing,(unsigned long)entries.count];
 for(NSDictionary *entry in entries){
  [report appendFormat:@"[%@] %@\n    分组：%@\n    路径：%@\n    状态：%@\n",[entry[@"exists"] boolValue]?@"存在":@"缺失",entry[@"label"],entry[@"group"],entry[@"path"],entry[@"note"]];
 }
 report=[([report stringByAppendingString:@"\n# 结束。以上均为本进程实际读数。\n"]) mutableCopy];
 NSString *writeError=nil;
 BOOL written=AACExportWriteText(dir,@"运行导出报告.txt",report,&writeError);
 return @{@"entries":entries,@"report":[report copy],@"found":@(found),@"missing":@(missing),@"localDir":dir?:@"",@"reportWritten":@(written),@"reportPath":dir?[dir stringByAppendingPathComponent:@"运行导出报告.txt"]:@"(设置侧目录不可用)",@"reportError":writeError?:@"none"};
}
/* Copies every existing, readable file into one fresh temporary directory with a flat, unique
   name so the share sheet shows a readable set instead of many identical leaf names. Files are
   copied, never moved, and nothing outside this list is collected. */
static inline NSArray *AACExportCopy(NSArray *entries,NSMutableArray *failures){
 NSMutableArray *urls=[NSMutableArray new];
 NSFileManager *manager=[NSFileManager defaultManager];
 NSError *error=nil;
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"AutoAnswerCall-export-%lld",(long long)(NSDate.date.timeIntervalSince1970*1000)]];
 if(![manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]){
  if(failures)[failures addObject:[@"临时导出目录不可创建：" stringByAppendingString:AACExportErrorText(error,@"未知错误")]];
  return urls;
 }
 NSMutableSet *used=[NSMutableSet new];
 for(NSDictionary *entry in entries){
  if(![entry[@"exists"] boolValue]||![entry[@"readable"] boolValue])continue;
  NSString *flat=[entry[@"flat"] isKindOfClass:NSString.class]?entry[@"flat"]:entry[@"leaf"];
  if([used containsObject:flat])flat=[NSString stringWithFormat:@"%lu-%@",(unsigned long)used.count,flat];
  [used addObject:flat];
  NSString *destination=[root stringByAppendingPathComponent:flat];
  NSError *copyError=nil;
  if([manager copyItemAtPath:entry[@"path"] toPath:destination error:&copyError])[urls addObject:[NSURL fileURLWithPath:destination]];
  else if(failures)[failures addObject:[NSString stringWithFormat:@"%@ 复制失败：%@",entry[@"path"],AACExportErrorText(copyError,@"未知错误")]];
 }
 if(failures)[failures addObject:[NSString stringWithFormat:@"导出目录：%@（已复制 %lu 个文件）",root,(unsigned long)urls.count]];
 return urls;
}
static inline void AACExportShare(UIViewController *controller,NSArray *urls,NSString *report,UIView *sourceView,void (^completion)(void)){
 if(!urls.count||!controller)return;
 NSMutableArray *items=[urls mutableCopy];
 if(report.length){
  NSString *reportPath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"AutoAnswerCall-运行导出报告.txt"];
  NSError *error=nil;
  if([report writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:&error])[items addObject:[NSURL fileURLWithPath:reportPath]];
 }
 UIActivityViewController *activity=[[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
 activity.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *returned,NSError *error){if(completion)completion();};
 if(activity.popoverPresentationController){
  activity.popoverPresentationController.sourceView=sourceView?:controller.view;
  activity.popoverPresentationController.sourceRect=sourceView?sourceView.bounds:CGRectMake(controller.view.bounds.size.width/2,controller.view.bounds.size.height/2,1,1);
 }
 [controller presentViewController:activity animated:YES completion:nil];
}
/* ---- UI: 运行日志文件逐项查看 / 逐项分享 -------------------------------------------------- */
@interface AACLogExportController : UITableViewController
@property(nonatomic,strong) NSDictionary *gathered;
@property(nonatomic,copy) NSString *prepareSummary;
@end
@implementation AACLogExportController
- (void)viewDidLoad{
 [super viewDidLoad];
 self.title=@"运行日志：逐项查看 / 分享";
 self.tableView.rowHeight=UITableViewAutomaticDimension;
 self.tableView.estimatedRowHeight=90;
 self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)],[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareEverything)]];
 [self reload];
}
- (void)reload{
 self.prepareSummary=[[AACExportPrepare(NULL) componentsJoinedByString:@"；"] copy];
 self.gathered=AACExportGather();
 [self.tableView reloadData];
}
- (NSArray *)entries{return self.gathered[@"entries"]?:@[];}
- (UIAlertController *)alertWithTitle:(NSString *)title message:(NSString *)message{
 UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message?:@"未提供详细说明" preferredStyle:UIAlertControllerStyleAlert];
 [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
 return alert;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?1:[self entries].count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 return section==0?@"导出报告（本进程真实读数）":@"每一项运行日志文件（点行查看，点 ⓘ 单独分享）";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==0)return [NSString stringWithFormat:@"存在 %@ 项，缺失 %@ 项。缺失项在下面写明原因；本页不虚构条目，也不声称自动接听可用。\n生成结果：%@",self.gathered[@"found"],self.gathered[@"missing"],self.prepareSummary?:@"无"];
 return @"跨进程可写/可读未在 RootHide 上验证：某个进程写下的日志可能在本进程不可见，此时会明确写「未创建」而不是伪造内容。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 cell.detailTextLabel.numberOfLines=4;
 cell.textLabel.numberOfLines=2;
 if(indexPath.section==0){
  cell.textLabel.text=@"运行日志导出报告";
  cell.detailTextLabel.text=[NSString stringWithFormat:@"存在 %@ / 缺失 %@（共 %lu 项）\n生成：%@\n报告文件：%@",self.gathered[@"found"],self.gathered[@"missing"],(unsigned long)[self entries].count,self.prepareSummary?:@"无",[self.gathered[@"reportWritten"] boolValue]?self.gathered[@"reportPath"]:self.gathered[@"reportError"]];
  cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  return cell;
 }
 NSDictionary *entry=[self entries][indexPath.row];
 cell.textLabel.text=[NSString stringWithFormat:@"%@（%@）",entry[@"label"],entry[@"group"]];
 cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",entry[@"note"],entry[@"path"]];
 if([entry[@"exists"] boolValue])cell.accessoryType=UITableViewCellAccessoryDetailButton;
 return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 if(indexPath.section==0){AACLogText(@"运行日志导出报告",self.gathered[@"report"]?:@"（无报告）",self.navigationController);return;}
 NSDictionary *entry=[self entries][indexPath.row];
 if(![entry[@"exists"] boolValue]){
  [self presentViewController:[self alertWithTitle:entry[@"label"] message:[NSString stringWithFormat:@"%@\n%@\n\n该文件不存在，因此没有内容可以打开：原因见上面的状态行。",entry[@"path"],entry[@"note"]]] animated:YES completion:nil];
  return;
 }
 if(![entry[@"readable"] boolValue]){
  [self presentViewController:[self alertWithTitle:entry[@"label"] message:[NSString stringWithFormat:@"%@\n\n文件存在但本进程不可读（沙盒/权限），因此无法在这里显示文本；可用 ⓘ 尝试交给系统分享。",entry[@"path"]]] animated:YES completion:nil];
  return;
 }
 NSError *error=nil;
 NSString *text=AACSharedReadFile(entry[@"path"],&error);
 if(!text)text=[NSString stringWithFormat:@"按 UTF-8 文本读取失败：%@\n（可能是二进制 plist 或其他非文本内容；用 ⓘ 分享原文件。）",error.localizedDescription?:@"未知错误"];
 AACLogText(entry[@"label"],text,self.navigationController);
}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath{
 if(indexPath.section==0)return;
 NSDictionary *entry=[self entries][indexPath.row];
 if(![entry[@"exists"] boolValue]||![entry[@"readable"] boolValue])return;
 NSMutableArray *failures=[NSMutableArray new];
 NSArray *urls=AACExportCopy(@[entry],failures);
 if(!urls.count){
  [self presentViewController:[self alertWithTitle:@"无法分享该文件" message:[failures componentsJoinedByString:@"\n"]] animated:YES completion:nil];
  return;
 }
 AACExportShare(self,urls,nil,[tableView cellForRowAtIndexPath:indexPath],^{});
}
- (void)shareEverything{
 NSMutableArray *failures=[NSMutableArray new];
 NSArray *urls=AACExportCopy([self entries],failures);
 if(!urls.count){
  [self presentViewController:[self alertWithTitle:@"没有可分享的运行日志" message:[NSString stringWithFormat:@"%@\n\n%@",self.gathered[@"report"],failures.count?[failures componentsJoinedByString:@"\n"]:@""]] animated:YES completion:nil];
  return;
 }
 NSDictionary *gathered=self.gathered;
 AACExportShare(self,urls,gathered[@"report"],nil,^{
  AACSharedAppend(@"settings",[NSString stringWithFormat:@"运行日志分享完成：文件=%lu，报告已附带；缺失 %@ 项（逐项原因见报告）",(unsigned long)urls.count,gathered[@"missing"]]);
 });
}
@end
