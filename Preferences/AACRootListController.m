#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import "../AACPolicy.h"
#import "AACSystemControl.h"
static NSString * const Domain=@"com.autoanswer.call";
static NSUInteger const Limit=5*1024*1024;
static NSString *LocalDir(NSError **e){NSURL *u=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:e]; if(!u)return nil;NSString *p=[u.path stringByAppendingPathComponent:@"AutoAnswerCall"];return [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:e]?p:nil;}
static NSUserDefaults *Defaults(void){return [[NSUserDefaults alloc] initWithSuiteName:Domain];}
static NSString *ErrorText(NSError *e,NSString *fallback){return e?[NSString stringWithFormat:@"%@ (%@/%ld)",e.localizedDescription?:fallback,e.domain,(long)e.code]:fallback;}
#import "AACAudioLibrary.h"
#import "AACRecordsController.h"
@interface AACRootListController : PSListController<UIDocumentPickerDelegate>
@property(nonatomic) BOOL importing;
@property(nonatomic,strong) UIAlertController *importProgress;
@property(nonatomic,strong) AVAudioPlayer *player;
@property(nonatomic,strong) NSURL *localAudio;
@property(nonatomic,copy) NSString *writeError;
@property(nonatomic,strong) NSDate *pong;
@property(nonatomic) int pongToken;
@property(nonatomic) BOOL observing;
@end
@implementation AACRootListController
- (NSArray *)specifiers{if(!_specifiers)_specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];return _specifiers;}
- (void)log:(NSString *)message{
 NSError *e=nil;NSString *dir=LocalDir(&e); NSString *path=[dir stringByAppendingPathComponent:@"settings.log"];
 NSString *old=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]:nil;
 NSString *all=[(old?:@"") stringByAppendingFormat:@"[%@] SETTINGS %@\n",NSDate.date,message];if(all.length>24000)all=[all substringFromIndex:all.length-24000];
 if(!path||![all writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&e])self.writeError=ErrorText(e,@"Settings log destination unavailable"); else self.writeError=nil;
}
- (void)alert:(NSString *)title message:(NSString *)message{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message.length?message:@"未提供详细错误" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)viewDidLoad{[super viewDidLoad];AACAudioLibrary *library=AACAudioLibrary.shared;if(library.failure)[self log:library.failure];[self log:@"设置模块已加载 1.9.1；不代表电话模块已加载"]; __weak typeof(self) w=self;int token=0;uint32_t status=notify_register_dispatch("com.autoanswer.call.pong",&token,dispatch_get_main_queue(),^(int t){w.pong=NSDate.date;[w log:@"收到 MobilePhone Darwin pong；仅证明当时存活，不证明接听能力"];});if(status==NOTIFY_STATUS_OK){self.pongToken=token;self.observing=YES;}else [self log:[NSString stringWithFormat:@"pong registration failed %u",status]];}
- (void)dealloc{if(_observing)notify_cancel(_pongToken);}
- (void)pickAudio:(PSSpecifier *)s{if(self.importing)return;AACAudioLibrary *lib=AACAudioLibrary.shared;if(lib.failure){[self alert:@"音频库不可写" message:lib.failure];return;}UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.audio"]] asCopy:YES];p.delegate=self;p.allowsMultipleSelection=YES;[self presentViewController:p animated:YES completion:nil];}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller{[self log:@"音频导入已取消"];}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 if(!urls.count||self.importing)return;self.importing=YES;
 self.importProgress=[UIAlertController alertControllerWithTitle:@"正在追加到音频库" message:@"准备读取（每个文件最多5MB）" preferredStyle:UIAlertControllerStyleAlert];
 /* The picker can still be dismissing; defer presentation without blocking import. */
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.importing&&!self.presentedViewController)[self presentViewController:self.importProgress animated:YES completion:nil];});
 AACAudioLibrary *lib=AACAudioLibrary.shared;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  __block NSUInteger count=0;NSMutableArray *failures=[NSMutableArray new];NSUInteger index=0;
  for(NSURL *source in urls){@autoreleasepool{index++;NSUInteger progress=index;dispatch_async(dispatch_get_main_queue(),^{self.importProgress.message=[NSString stringWithFormat:@"%lu/%lu：%@",(unsigned long)progress,(unsigned long)urls.count,source.lastPathComponent];});
   BOOL scoped=[source startAccessingSecurityScopedResource];__block NSData *data=nil;__block NSError *readError=nil;NSError *coordError=nil;
   NSFileCoordinator *fc=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
   [fc coordinateReadingItemAtURL:source options:0 error:&coordError byAccessor:^(NSURL *u){
    NSNumber *size=nil;[u getResourceValue:&size forKey:NSURLFileSizeKey error:&readError];if(readError)return;
    if(size.unsignedLongLongValue>Limit){readError=[NSError errorWithDomain:@"AACImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"来源文件超过 5MB 限制"}];return;}
    NSFileHandle *h=[NSFileHandle fileHandleForReadingFromURL:u error:&readError];if(!h)return;
    @try{data=[h readDataUpToLength:Limit+1 error:&readError];[h closeFile];}@catch(NSException *ex){readError=[NSError errorWithDomain:@"AACImport" code:2 userInfo:@{NSLocalizedDescriptionKey:ex.reason?:@"来源读取异常"}];}
   }];if(scoped)[source stopAccessingSecurityScopedResource];
   NSString *failure=nil;if(coordError||readError)failure=[@"来源读取失败：" stringByAppendingString:ErrorText(coordError?:readError,@"来源不可读")];else if(!data.length||data.length>Limit)failure=@"来源为空或超过5MB";
   NSError *e=nil;NSURL *dest=nil;NSString *ident=NSUUID.UUID.UUIDString;double duration=0;
   if(!failure){NSString *dir=LocalDir(&e);NSString *ext=source.pathExtension;NSString *leaf=[[@"audio-" stringByAppendingString:ident] stringByAppendingPathExtension:ext.length?ext:@"audio"];if(dir)dest=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:leaf]];if(!dest||![data writeToURL:dest options:NSDataWritingAtomic error:&e])failure=[@"目标写入失败：" stringByAppendingString:ErrorText(e,@"Application Support 无可写路径")];}
   if(!failure){AVAudioPlayer *probe=[[AVAudioPlayer alloc] initWithContentsOfURL:dest error:&e];if(!probe)failure=[@"音频验证失败：" stringByAppendingString:ErrorText(e,@"AVAudioPlayer 返回空")];else duration=probe.duration;}
   if(!failure){NSDictionary *entry=@{@"id":ident,@"path":dest.path,@"name":source.lastPathComponent?:@"音频",@"size":@(data.length),@"duration":@(duration)};
    /* Library/UI mutations remain on main; sequential worker holds only one bounded file. */
    __block NSString *saveError=nil;dispatch_sync(dispatch_get_main_queue(),^{[lib.items addObject:entry];if(![lib save]){[lib.items removeObject:entry];saveError=lib.failure?:@"音频库写入失败";}else{count++;if(!lib.selected.length&&![lib select:entry])saveError=lib.failure?:@"首项选择失败";[self log:[NSString stringWithFormat:@"音频库追加 %@ (%lu bytes)；本地沙盒，未确认电话可读",entry[@"name"],(unsigned long)data.length]];}});failure=saveError;
   }
   if(failure){/* Keep committed library references, remove only uncommitted copies. */
    __block BOOL referenced=NO;dispatch_sync(dispatch_get_main_queue(),^{for(NSDictionary *entry in lib.items)if([entry[@"path"] isEqual:dest.path])referenced=YES;});if(dest&&!referenced)[[NSFileManager defaultManager] removeItemAtURL:dest error:nil];[failures addObject:[NSString stringWithFormat:@"%@：%@",source.lastPathComponent,failure]];
   }
  }}
  dispatch_async(dispatch_get_main_queue(),^{self.importing=NO;NSString *message=[NSString stringWithFormat:@"追加成功 %lu/%lu 个；已有音频与选择保持不变（空库自动选择首项）。\n%@\n仅设置沙盒本地试听；电话进程访问未保证。",(unsigned long)count,(unsigned long)urls.count,failures.count?[failures componentsJoinedByString:@"\n"]:@"可在音频库自由切换、逐项试听和删除。"];[self log:message];void(^done)(void)=^{self.importProgress=nil;[self alert:@"音频库导入结果" message:message];};if(self.presentedViewController==self.importProgress)[self dismissViewControllerAnimated:YES completion:done];else done();});
 });
}
- (void)showAudioLibrary:(PSSpecifier *)s{[self.player stop];self.player=nil;self.localAudio=nil;AACAudioLibrary *lib=AACAudioLibrary.shared;if(lib.failure)[self log:lib.failure];[self.navigationController pushViewController:[AACAudioListController new] animated:YES];}
- (NSDictionary *)localMetadata{NSString *dir=LocalDir(nil);return dir?[NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"audio.plist"]] error:nil]:nil;}
- (NSURL *)audioURL{NSString *p=[self localMetadata][@"AudioPath"]?:[Defaults() stringForKey:@"AudioPath"];return self.localAudio?:(p.length?[NSURL fileURLWithPath:p]:nil);}
- (void)exportConfig:(PSSpecifier *)s{NSError *e=nil;NSString *dir=LocalDir(&e);NSString *path=[dir stringByAppendingPathComponent:@"configuration.plist"];NSMutableDictionary *config=[NSMutableDictionary new];NSUserDefaults *d=Defaults();for(NSString *k in @[@"Mode",@"Enabled",@"Delay",@"Whitelist",@"PlayAudio",@"AudioPath",@"AudioName",@"AudioSize",@"SelectedAudioID"]){id v=[d objectForKey:k];if(v)config[k]=v;}[config addEntriesFromDictionary:[self localMetadata]?:@{}];config[@"Version"]=@"1.9.1";if(!path||![config writeToURL:[NSURL fileURLWithPath:path] error:&e]){[self alert:@"导出失败" message:ErrorText(e,@"配置目标不可写")];return;}UIActivityViewController *a=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];if(a.popoverPresentationController){a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1);}[self presentViewController:a animated:YES completion:nil];}
- (void)testAudio:(PSSpecifier *)s{
 NSURL *u=[self audioURL];NSError *e=nil;if(!u){[self alert:@"试听失败" message:@"未导入音频"];return;}
 self.player=[[AVAudioPlayer alloc] initWithContentsOfURL:u error:&e];
 if(!self.player||![self.player prepareToPlay]||![self.player play]){NSString *msg=ErrorText(e,@"播放器 prepare/play 返回 NO；文件可能不存在、格式不支持或音频路由不可用");[self log:[@"试听失败：" stringByAppendingString:msg]];[self alert:@"试听失败" message:msg];return;}[self log:@"设置模块本地试听开始；无通话上行注入，无电话模块运行证明"];
}
- (void)text:(NSString *)text title:(NSString *)title{UIViewController *c=[UIViewController new];UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero];v.text=text;v.editable=NO;v.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];c.view=v;c.title=title;[self.navigationController pushViewController:c animated:YES];}
- (id)readDelay:(PSSpecifier *)s{
 id v=[Defaults() objectForKey:@"Delay"];double seconds=v&&[v respondsToSelector:@selector(doubleValue)]?AACBoundDelay([v doubleValue]):0.5;
 return [NSDecimalNumber decimalNumberWithString:[@(seconds) stringValue]].stringValue;
}
- (void)setDelay:(id)value specifier:(PSSpecifier *)s{
 NSString *raw=[value isKindOfClass:NSString.class]?value:([value isKindOfClass:NSNumber.class]?[value stringValue]:nil);
 NSString *text=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 /* ASCII decimal only: no units, exponent, NaN, Infinity, signs or partial parse. */
 double seconds=0;BOOL valid=AACParseDelay(text.UTF8String,&seconds);
 if(!valid){[self alert:@"秒数无效，未保存" message:@"请输入 0～60 的有限数字，可用小数点，例如 5 或 1.5。单位是秒；旧值保持不变。"];[self reloadSpecifiers];return;}
 NSUserDefaults *d=Defaults();[d setDouble:AACBoundDelay(seconds) forKey:@"Delay"];BOOL synced=[d synchronize];
 [self log:[NSString stringWithFormat:@"接听等待已设置为 %.15g 秒；配置同步=%d；仅从电话来电事件开始计时，不代表实测响铃时长",seconds,synced]];
 if(!synced)[self alert:@"秒数已写入本进程" message:@"配置同步失败，电话进程是否可见未确认。"];
 [self reloadSpecifiers];
}
- (void)stopPlugin:(PSSpecifier *)s{
 NSUserDefaults *d=Defaults();[d setBool:NO forKey:@"Enabled"];BOOL synced=[d synchronize];BOOL off=![d boolForKey:@"Enabled"];
 uint32_t posted=notify_post("com.autoanswer.call.stop");[self reloadSpecifiers];
 [self log:[NSString stringWithFormat:@"停止插件策略：本进程回读关闭=%d 同步=%d stop通知=%u；系统自动接听状态未知/未修改",off,synced,posted]];
 [self alert:off&&synced?@"插件策略配置已关闭":@"插件关闭配置未确认" message:@"仅关闭插件 Enabled，并通知电话模块取消尚未提交的等待；不撤回已提交的接听事务。未收到电话确认不能保证通知送达。iOS 系统自动接听状态：未知，未修改。若系统已开启，仍须手动关闭。"];
}
- (void)systemStatus:(PSSpecifier *)s{BOOL enabled=NO;NSString *e=nil;BOOL known=AACSystemRead(&enabled,&e);[self alert:@"iOS 系统自动接听状态" message:known?[NSString stringWithFormat:@"AXSettings 访问器当前回读：%@。与插件 Enabled 完全独立；未验证跨进程/实机接听行为。",enabled?@"开启":@"关闭"]:[NSString stringWithFormat:@"未知/不可用：%@。不能切换；请用原生页面。",e?:@"读取失败"]];}
- (void)disableSystem:(PSSpecifier *)s{
 NSString *e=nil;BOOL before=NO;
 if(!AACSystemRead(&before,&e)||!AACSystemDisable(&e)){[self log:[@"系统关闭不可用：" stringByAppendingString:e?:@"未知错误"]];[self alert:@"无法切换系统开关" message:e?:@"无已验证的系统访问器，未修改系统偏好"];return;}
 /* The native setter owns persistence/notifications. Never invent notify names. */
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{BOOL on=YES;NSString *error=nil;BOOL read=AACSystemRead(&on,&error);NSString *message=read&&!on?@"系统访问器回读为关闭。仅确认此进程访问器值，不保证跨进程缓存同步或电话实测。插件 Enabled 未修改。":(error?:@"写入后未回读到关闭；请手动检查原生开关。");[self log:message];[self alert:read&&!on?@"系统开关回读：关闭":@"系统关闭未确认" message:message];});
}
- (void)openSystemAutoAnswer:(PSSpecifier *)s{
 NSURL *u=[NSURL URLWithString:@"prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/CALL_AUDIO_ROUTING/callAudioRoutingAutoAnswer"];
 [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{
  [self log:ok?@"系统接受打开 URL；不证明到达自动接听页面；系统开关未知/未修改":@"系统拒绝设置深链，请使用手动路径"];
  if(!ok)[self alert:@"无法打开原生页面" message:@"请手动前往：设置 → 辅助功能 → 触控 → 通话音频路由 → 自动接听通话。深链未在 iOS 17.3 设备验证，系统开关未修改。"];
 });}];
}
- (void)showLog:(PSSpecifier *)s{NSError *e=nil;NSString *dir=LocalDir(&e);NSString *text=dir?[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"settings.log"] encoding:NSUTF8StringEncoding error:&e]:nil;NSString *name=[Defaults() stringForKey:@"AudioName"]?:@"未导入";[self text:[NSString stringWithFormat:@"仅设置进程日志（不是电话日志）\n音频：%@ (%ld bytes)\n路径：%@\n持久写入错误：%@\n读取：%@\n\n%@",name,(long)[Defaults() integerForKey:@"AudioSize"],[self audioURL].path?:@"无",self.writeError?:@"无",e?ErrorText(e,@"未知错误"):@"成功",text?:@"尚无本地日志"] title:@"设置诊断"] ;}
- (void)showCallRecords:(PSSpecifier *)s{[self.navigationController pushViewController:[[AACRecordsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)showPhoneDiagnostics:(PSSpecifier *)s{CFStringRef domain=CFSTR("com.autoanswer.call.phone");CFPreferencesAppSynchronize(domain);id log=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Log"),domain));[self text:[NSString stringWithFormat:@"电话模块诊断（独立域，跨沙盒可见性不保证）\n最近本页收到 pong：%@\n未收到不等于未注入，也可能进程休眠或通知不可达。\n\n%@",self.pong?:@"未收到",[log isKindOfClass:NSString.class]?log:@"无法读取电话诊断域/没有记录；设置试听不能证明电话模块已加载。"] title:@"电话诊断"] ;}
- (void)pingPhone:(PSSpecifier *)s{self.pong=nil;uint32_t result=notify_post("com.autoanswer.call.ping");[self log:[NSString stringWithFormat:@"发送电话 ping status=%u",result]];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self alert:@"电话进程探测" message:self.pong?@"收到 MobilePhone pong，仅证明进程当时响应；未验证接听、锁屏或音频权限。":@"未收到 pong：可能未注入、进程休眠/未启动或通知不可达。请查看电话诊断，不能从设置试听推断插件可接听。"] ;});}
- (void)clearLog:(PSSpecifier *)s{NSError *e=nil;NSString *dir=LocalDir(&e);NSString *p=[dir stringByAppendingPathComponent:@"settings.log"];if(p&&[[NSFileManager defaultManager] fileExistsAtPath:p]&&![[NSFileManager defaultManager] removeItemAtPath:p error:&e])[self alert:@"清除失败" message:ErrorText(e,@"本地日志删除失败")];}
- (void)clearAudio:(PSSpecifier *)s{[self showAudioLibrary:s];}
@end
