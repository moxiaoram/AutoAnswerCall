#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../AACSharedLog.h"
/* 共享日志查看器 (1.12.0；1.13.0/1.14.0 未改动；1.15.0 增加宿主跨进程上报域读回页面，
   运行日志分享见 AACLogExportController.h).
   Tries every candidate path in order, shows whichever one is actually readable and
   clearly labels which path succeeded. It never merges contents and never claims that
   a file written by another process is visible here.
   1.15.0 TASK 1: the 「宿主跨进程上报」 section reads the shared host-report CFPreferences
   domain BACK and shows, per host, exactly how many keys THIS process can read, plus the real
   on-disk plist path of that domain and whether it is readable here. An empty read is shown as
   an empty read and explicitly NOT as "that host is not injected". */
static inline void AACLogText(NSString *title,NSString *text,UINavigationController *navigation){
 UIViewController *controller=[UIViewController new];UITextView *view=[UITextView new];
 view.text=[text isKindOfClass:NSString.class]?text:@"（无内容）";view.editable=NO;
 view.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
 view.frame=controller.view.bounds;view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 controller.view=view;controller.title=title;
 if(navigation)[navigation pushViewController:controller animated:YES];
}
/* First readable file for a process among the candidates; the winning label is kept. */
static inline NSDictionary *AACSharedFirstReadable(NSString *process){
 NSFileManager *manager=[NSFileManager defaultManager];
 for(NSDictionary *candidate in AACSharedLogCandidateDirs()){
  NSString *path=[candidate[@"dir"] stringByAppendingPathComponent:AACSharedFileLeaf(process,@"log")];
  if(![manager isReadableFileAtPath:path])continue;
  NSError *error=nil;NSString *text=AACSharedReadFile(path,&error);
  return @{@"label":candidate[@"label"],@"path":path,@"text":text?:[NSString stringWithFormat:@"读取失败：%@",error.localizedDescription?:@"未知错误"]};
 }
 return nil;
}
@interface AACSharedLogController : UITableViewController
@property(nonatomic,strong) NSArray *entries;
@property(nonatomic,strong) NSDictionary<NSString *,NSDictionary *> *resolved;
@property(nonatomic,strong) NSArray *hostReportEntries;
@end
@implementation AACSharedLogController
static inline NSArray *AACLogViewerProcesses(void){return @[@"incall",@"springboard",@"mobilephone",@"settings"];}
- (instancetype)initWithStyle:(UITableViewStyle)style{
 if((self=[super initWithStyle:style])){_entries=@[];_resolved=@{};_hostReportEntries=@[];}
 return self;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"共享日志查看器";
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
 [self reload];
}
- (void)reload{
 NSMutableDictionary *resolved=[NSMutableDictionary new];
 for(NSString *process in AACLogViewerProcesses()){NSDictionary *found=AACSharedFirstReadable(process);if(found)resolved[process]=found;}
 self.resolved=resolved;self.entries=AACSharedViewerEntries(AACLogViewerProcesses());
 self.hostReportEntries=AACHostReportEntries();
 [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
 if(section==0)return AACLogViewerProcesses().count;
 if(section==1)return self.entries.count;
 if(section==2)return self.hostReportEntries.count+1;
 return 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 if(section==0)return @"按顺序尝试后，第一个可读的日志路径";
 if(section==1)return @"全部候选路径与文件的逐项结果（设置进程视角）";
 if(section==2)return [NSString stringWithFormat:@"宿主跨进程上报读回（自有 CFPreferences 域 %@）",AACHostReportDomain];
 return @"旧的 CFPreferences 回退域";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==0)return @"标签写明命中的候选路径。没有可读路径时会明确写出“没有可读”，不会回退成伪造内容。";
 if(section==1)return @"这些结果只反映设置进程自身；另一进程是否可写/可读必须看它自己写下的记录。";
 if(section==2)return @"每个宿主在发现后与每 20 秒把「发现摘要 + 最近日志行」写入这个自有域（每宿主有独立键，载荷有上限并带截断标记）。本页只显示设置进程实际读到的键数与真实 plist 路径；读不到空域不代表该宿主未注入，也不代表接听可用。";
 return @"回退域 com.autoanswer.call.sharelog 的跨进程可见性不保证，也未被本版本验证。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.detailTextLabel.numberOfLines=3;cell.textLabel.numberOfLines=2;
 if(indexPath.section==0){
  NSString *process=AACLogViewerProcesses()[indexPath.row];NSDictionary *found=self.resolved[process];
  cell.textLabel.text=[NSString stringWithFormat:@"%@ 日志",process];
  if(found){cell.detailTextLabel.text=[NSString stringWithFormat:@"命中路径标签：%@\n%@\n%lu 字符",found[@"label"],found[@"path"],[found[@"text"] length]];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
  else{cell.detailTextLabel.text=@"没有可读路径（已逐项尝试，见下一节）；不代表该进程未写日志。";cell.accessoryType=UITableViewCellAccessoryNone;}
 }else if(indexPath.section==1){
  NSDictionary *entry=self.entries[indexPath.row];BOOL readable=[entry[@"readable"] boolValue];
  cell.textLabel.text=entry[@"label"];
  if([entry[@"kind"] isEqualToString:@"dir"])cell.detailTextLabel.text=[NSString stringWithFormat:@"目录：%@；可写=%@\n%@",[entry[@"exists"] boolValue]?@"存在":@"不存在",[entry[@"writable"] boolValue]?@"是":@"否",entry[@"path"]];
  else if([entry[@"kind"] isEqualToString:@"file"])cell.detailTextLabel.text=[NSString stringWithFormat:@"文件：%@；可读=%@；%llu 字节\n%@",[entry[@"exists"] boolValue]?@"存在":@"未创建",readable?@"是":@"否",[entry[@"size"] unsignedLongLongValue],entry[@"path"]];
  else cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",entry[@"note"],entry[@"path"]];
  cell.accessoryType=readable?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
 }else if(indexPath.section==2){
  if(indexPath.row<self.hostReportEntries.count){
   NSDictionary *entry=self.hostReportEntries[indexPath.row];
   cell.textLabel.text=entry[@"label"];
   cell.detailTextLabel.text=[NSString stringWithFormat:@"%@；%llu 字符\n%@",entry[@"note"],[entry[@"size"] unsignedLongLongValue],entry[@"path"]];
   cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  }else{
   cell.textLabel.text=@"打开完整读回内容（域、每宿主键、真实 plist 路径）";
   cell.detailTextLabel.text=[NSString stringWithFormat:@"域 %@；本页不做任何可见性推断，只显示本进程实际读到的内容。",AACHostReportDomain];
   cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
  }
 }else{
  if(indexPath.row==0){cell.textLabel.text=@"共享日志回退内容";cell.detailTextLabel.text=@"com.autoanswer.call.sharelog（本进程可读到多少就显示多少）";}
  else{cell.textLabel.text=@"模块伴随探测记录";cell.detailTextLabel.text=@"com.autoanswer.call.probe 的 LastProbe.* 键";}
  cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
 }
 return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
 [tableView deselectRowAtIndexPath:indexPath animated:YES];
 if(indexPath.section==0){
  NSString *process=AACLogViewerProcesses()[indexPath.row];NSDictionary *found=self.resolved[process];
  if(!found)return;
  AACLogText([NSString stringWithFormat:@"%@ 日志（%@）",process,found[@"label"]],found[@"text"],self.navigationController);
  return;
 }
 if(indexPath.section==1){
  NSDictionary *entry=self.entries[indexPath.row];
  if(![entry[@"readable"] boolValue])return;
  if([entry[@"kind"] isEqualToString:@"dir"]){
   NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:entry[@"path"] error:nil];
   AACLogText(entry[@"path"],files.count?[files componentsJoinedByString:@"\n"]:@"空或不可读",self.navigationController);return;
  }
  if([entry[@"kind"] isEqualToString:@"file"]){
   NSError *error=nil;NSString *text=AACSharedReadFile(entry[@"path"],&error);
   AACLogText(entry[@"label"],text?:[NSString stringWithFormat:@"读取失败：%@",error.localizedDescription?:@"未知错误"],self.navigationController);return;
  }
  AACLogText(@"CFPreferences 回退",AACSharedPrefsDump(),self.navigationController);return;
 }
 if(indexPath.section==2){
  /* 1.15.0 TASK 1: the read-back itself. Always shows the domain, its real plist paths and
     every key this process can actually read, per host. */
  AACLogText([NSString stringWithFormat:@"宿主上报读回（%@）",AACHostReportDomain],AACHostReportDump(),self.navigationController);
  return;
 }
 AACLogText(indexPath.row==0?@"共享日志回退内容":@"模块伴随探测记录",indexPath.row==0?AACSharedPrefsDump():AACSharedProbeCompanionDump(),self.navigationController);
}
@end
