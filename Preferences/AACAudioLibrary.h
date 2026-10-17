/* Included after LocalDir/Defaults/ErrorText in the Settings translation unit. */
@interface AACAudioLibrary : NSObject
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *items;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,copy) NSString *failure;
+ (instancetype)shared;
- (BOOL)save;
- (BOOL)select:(NSDictionary *)item;
- (BOOL)remove:(NSDictionary *)item;
@end
@implementation AACAudioLibrary
+ (instancetype)shared{static AACAudioLibrary *lib;static dispatch_once_t once;dispatch_once(&once,^{lib=[self new];});return lib;}
- (instancetype)init{if((self=[super init])){
 self.items=[NSMutableArray new];NSString *dir=LocalDir(nil);NSString *path=[dir stringByAppendingPathComponent:@"audio-library.plist"];
 NSDictionary *saved=path?[NSDictionary dictionaryWithContentsOfFile:path]:nil;
 if(saved){
  if(![saved[@"Items"] isKindOfClass:NSArray.class]){self.failure=@"音频库文件格式无效；禁止覆盖，请先导出诊断";return self;}
  NSMutableSet *ids=[NSMutableSet new];
  for(id entry in saved[@"Items"]){if(![entry isKindOfClass:NSDictionary.class]||![entry[@"id"] isKindOfClass:NSString.class]||![entry[@"id"] length]||[ids containsObject:entry[@"id"]]||![entry[@"path"] isKindOfClass:NSString.class]||![entry[@"path"] length]||![entry[@"name"] isKindOfClass:NSString.class]||![entry[@"size"] isKindOfClass:NSNumber.class]||![entry[@"duration"] isKindOfClass:NSNumber.class]){self.failure=@"音频库条目无效/重复；禁止覆盖";return self;}[ids addObject:entry[@"id"]];[self.items addObject:entry];}
  self.selected=[saved[@"SelectedAudioID"] isKindOfClass:NSString.class]?saved[@"SelectedAudioID"]:nil;
 }else if(path&&[[NSFileManager defaultManager] fileExistsAtPath:path]){self.failure=@"音频库不可读；禁止覆盖";}
 else{
  NSDictionary *old=dir?[NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"audio.plist"]]:nil;
  NSString *p=old[@"AudioPath"]?:[Defaults() stringForKey:@"AudioPath"];
  if([p isKindOfClass:NSString.class]&&p.length){NSString *ident=NSUUID.UUID.UUIDString;AVAudioPlayer *probe=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:p] error:nil];
   NSDictionary *entry=@{@"id":ident,@"path":p,@"name":old[@"AudioName"]?:[Defaults() stringForKey:@"AudioName"]?:p.lastPathComponent,@"size":old[@"AudioSize"]?:@([Defaults() integerForKey:@"AudioSize"]),@"duration":@(probe?probe.duration:0)};
   [self.items addObject:entry];self.selected=ident;[self save];[self select:entry];
  }
 }
 }return self;}
- (BOOL)save{if(self.failure)return NO;NSError *e=nil;NSString *dir=LocalDir(&e);NSString *path=[dir stringByAppendingPathComponent:@"audio-library.plist"];BOOL ok=path&&[@{@"Items":self.items,@"SelectedAudioID":self.selected?:@""} writeToURL:[NSURL fileURLWithPath:path] error:&e];if(!ok)self.failure=ErrorText(e,@"音频库目标不可写");return ok;}
- (BOOL)select:(NSDictionary *)item{
 if(self.failure)return NO;NSString *old=self.selected;self.selected=item[@"id"];
 if(![self save]){self.selected=old;return NO;}
 NSUserDefaults *d=Defaults();NSError *e=nil;NSString *dir=LocalDir(&e);NSString *path=[dir stringByAppendingPathComponent:@"audio.plist"];
 if(item){NSDictionary *metadata=@{@"AudioPath":item[@"path"],@"AudioName":item[@"name"],@"AudioSize":item[@"size"]?:@0,@"SelectedAudioID":item[@"id"]};
  if(!path||![metadata writeToURL:[NSURL fileURLWithPath:path] error:&e]){self.failure=ErrorText(e,@"所选音频元数据不可写");return NO;}
  for(NSString *k in metadata)[d setObject:metadata[k] forKey:k];
 }else{if(path&&[[NSFileManager defaultManager] fileExistsAtPath:path]&&![[NSFileManager defaultManager] removeItemAtPath:path error:&e]){self.failure=ErrorText(e,@"清除元数据失败");return NO;}for(NSString *k in @[@"AudioPath",@"AudioName",@"AudioSize",@"SelectedAudioID"])[d removeObjectForKey:k];}
 if(![d synchronize]){self.failure=@"所选音频配置同步失败；电话侧可见性未确认";return NO;}
 #ifndef AAC_LIBRARY_MODEL_ONLY
 NSString *bridgeError=AACBridgePublishSettings();
 if(bridgeError)NSLog(@"[AutoAnswerCall] audio selected in Settings, but shared source unavailable to call hosts: %@",bridgeError);
#endif
 return YES;
}
- (BOOL)remove:(NSDictionary *)item{
 if(self.failure)return NO;NSMutableArray *backup=[self.items mutableCopy];NSString *previous=self.selected;BOOL wasSelected=[previous isEqual:item[@"id"]];[self.items removeObject:item];
 if(wasSelected)self.selected=self.items.firstObject[@"id"];
 if(![self save]){self.items=backup;self.selected=previous;return NO;}
 if(wasSelected&&![self select:self.items.firstObject])return NO;
 NSString *file=[[item[@"path"] stringByStandardizingPath] stringByResolvingSymlinksInPath];
 BOOL shared=NO;for(NSDictionary *other in self.items)if([[[other[@"path"] stringByStandardizingPath] stringByResolvingSymlinksInPath] isEqual:file])shared=YES;
 NSError *e=nil;NSString *dir=[LocalDir(&e) stringByResolvingSymlinksInPath];
 if(!shared&&dir&&[file hasPrefix:[[dir stringByStandardizingPath] stringByAppendingString:@"/"]]&&[[NSFileManager defaultManager] fileExistsAtPath:file]&&![[NSFileManager defaultManager] removeItemAtPath:file error:&e]){self.failure=ErrorText(e,@"条目已移除，但音频文件删除失败");return NO;}return YES;
}
@end
#ifndef AAC_LIBRARY_MODEL_ONLY
@interface AACAudioListController : UITableViewController
@property(nonatomic,strong) AVAudioPlayer *player;
@end
@implementation AACAudioListController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"音频库：点击选择，ⓘ 操作";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"停止试听" style:UIBarButtonItemStylePlain target:self action:@selector(stop)];}
- (void)stop{[self.player stop];self.player=nil;}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self stop];}
- (void)message:(NSString *)text{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"音频库" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return MAX(1,AACAudioLibrary.shared.items.count);}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
 UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];AACAudioLibrary *lib=AACAudioLibrary.shared;
 if(!lib.items.count){cell.textLabel.text=lib.failure?:@"暂无音频；返回导入，可一次多选";return cell;}
 NSDictionary *e=lib.items[ip.row];BOOL available=[[NSFileManager defaultManager] isReadableFileAtPath:e[@"path"]];BOOL selected=[lib.selected isEqual:e[@"id"]];cell.textLabel.text=[NSString stringWithFormat:@"%@%@",selected?@"✓ ":@"",e[@"name"]];cell.textLabel.numberOfLines=2;
 cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %.2f 秒 · %@%@",[NSByteCountFormatter stringFromByteCount:[e[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile],[e[@"duration"] doubleValue],available?@"可读取":@"不可用/文件丢失",selected?@" · 已选":@""];cell.detailTextLabel.numberOfLines=2;cell.accessoryType=UITableViewCellAccessoryDetailButton;return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
 AACAudioLibrary *lib=AACAudioLibrary.shared;if(!lib.items.count)return;NSDictionary *e=lib.items[ip.row];if(![[NSFileManager defaultManager] isReadableFileAtPath:e[@"path"]]){[self message:@"文件不可用，未更改选择。请重新导入或删除失效条目。"];return;}
 [self stop];if(![lib select:e])[self message:lib.failure?:@"选择保存失败"];[t reloadData];
}
- (void)tableView:(UITableView *)t accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip{
 AACAudioLibrary *lib=AACAudioLibrary.shared;if(ip.row>=lib.items.count)return;NSDictionary *e=lib.items[ip.row];UIAlertController *a=[UIAlertController alertControllerWithTitle:e[@"name"] message:@"本地设置沙盒试听；不证明电话进程可读，不是通话上行" preferredStyle:UIAlertControllerStyleActionSheet];
 [a addAction:[UIAlertAction actionWithTitle:@"试听此音频（不改变选择）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self stop];NSError *error=nil;self.player=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:e[@"path"]] error:&error];if(!self.player||![self.player prepareToPlay]||![self.player play])[self message:ErrorText(error,@"播放器 prepare/play 失败，文件可能丢失或不受支持")];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"停止试听" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self stop];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"删除此音频…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){UIAlertController *c=[UIAlertController alertControllerWithTitle:@"确认删除？" message:e[@"name"] preferredStyle:UIAlertControllerStyleAlert];[c addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[c addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *y){[self stop];if(![lib remove:e])[self message:lib.failure?:@"删除失败"];[t reloadData];}]];[self presentViewController:c animated:YES completion:nil];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];if(a.popoverPresentationController){a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:ip];a.popoverPresentationController.sourceRect=[t cellForRowAtIndexPath:ip].bounds;}[self presentViewController:a animated:YES completion:nil];
}
@end
#endif
