#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../AACSharedLog.h"
/* 共享日志查看器 (1.10.0).
   Tries every candidate path in order, shows whichever one is actually readable and
   clearly labels which path succeeded. It never merges contents and never claims that
   a file written by another process is visible here. */
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
@end
@implementation AACSharedLogController
static inline NSArray *AACLogViewerProcesses(void){return @[@"mobilephone",@"springboard",@"settings"];}
- (instancetype)initWithStyle:(UITableViewStyle)style{
 if((self=[super initWithStyle:style])){_entries=@[];_resolved=@{};}
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
 [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
 if(section==0)return AACLogViewerProcesses().count;
 if(section==1)return self.entries.count;
 return 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{
 if(section==0)return @"按顺序尝试后，第一个可读的日志路径";
 if(section==1)return @"全部候选路径与文件的逐项结果（设置进程视角）";
 return @"CFPreferences 回退";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==0)return @"标签写明命中的候选路径。没有可读路径时会明确写出“没有可读”，不会回退成伪造内容。";
 if(section==1)return @"这些结果只反映设置进程自身；另一进程是否可写/可读必须看它自己写下的记录。";
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
 AACLogText(indexPath.row==0?@"共享日志回退内容":@"模块伴随探测记录",indexPath.row==0?AACSharedPrefsDump():AACSharedProbeCompanionDump(),self.navigationController);
}
@end
