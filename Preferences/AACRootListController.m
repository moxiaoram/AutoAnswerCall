#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
static NSString * const Domain=@"com.autoanswer.call";
static NSUInteger const Limit=5*1024*1024;
static NSString *LocalDir(NSError **e){NSURL *u=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:e]; if(!u)return nil;NSString *p=[u.path stringByAppendingPathComponent:@"AutoAnswerCall"];return [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:e]?p:nil;}
static NSUserDefaults *Defaults(void){return [[NSUserDefaults alloc] initWithSuiteName:Domain];}
static NSString *ErrorText(NSError *e,NSString *fallback){return e?[NSString stringWithFormat:@"%@ (%@/%ld)",e.localizedDescription?:fallback,e.domain,(long)e.code]:fallback;}
@interface AACRootListController : PSListController<UIDocumentPickerDelegate>
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
- (void)viewDidLoad{[super viewDidLoad];[self log:@"设置模块已加载 1.8.0；不代表电话模块已加载"]; __weak typeof(self) w=self;int token=0;uint32_t status=notify_register_dispatch("com.autoanswer.call.pong",&token,dispatch_get_main_queue(),^(int t){w.pong=NSDate.date;[w log:@"收到 MobilePhone Darwin pong；仅证明当时存活，不证明接听能力"];});if(status==NOTIFY_STATUS_OK){self.pongToken=token;self.observing=YES;}else [self log:[NSString stringWithFormat:@"pong registration failed %u",status]];}
- (void)dealloc{if(_observing)notify_cancel(_pongToken);}
- (void)pickAudio:(PSSpecifier *)s{UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.audio"]] asCopy:YES];p.delegate=self;p.allowsMultipleSelection=NO;[self presentViewController:p animated:YES completion:nil];}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller{[self log:@"音频导入已取消"];}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 NSURL *source=urls.firstObject;if(!source){[self alert:@"导入失败" message:@"来源选择器返回空 URL"];return;}
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  BOOL scoped=[source startAccessingSecurityScopedResource];__block NSData *data=nil;__block NSError *readError=nil;NSError *coordError=nil;
  NSFileCoordinator *fc=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
  [fc coordinateReadingItemAtURL:source options:0 error:&coordError byAccessor:^(NSURL *u){
   NSNumber *size=nil;[u getResourceValue:&size forKey:NSURLFileSizeKey error:&readError];
   if(readError)return;
   if(size.unsignedLongLongValue>Limit){readError=[NSError errorWithDomain:@"AACImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"来源文件超过 5MB 限制"}];return;}
   NSFileHandle *h=[NSFileHandle fileHandleForReadingFromURL:u error:&readError];if(!h)return;
   @try {data=[h readDataUpToLength:Limit+1 error:&readError];[h closeFile];} @catch(NSException *ex){readError=[NSError errorWithDomain:@"AACImport" code:2 userInfo:@{NSLocalizedDescriptionKey:ex.reason?:@"来源读取异常"}];}
  }];
  if(scoped)[source stopAccessingSecurityScopedResource];
  NSString *failure=nil;if(coordError||readError)failure=[@"来源读取失败：" stringByAppendingString:ErrorText(coordError?:readError,@"来源不可读")];
  else if(!data.length||data.length>Limit)failure=@"来源读取失败：文件为空或超过 5MB";
  NSError *e=nil;NSURL *dest=nil;
  if(!failure){NSString *dir=LocalDir(&e);if(dir){NSString *ext=source.pathExtension;NSString *leaf=[[@"audio-" stringByAppendingString:NSUUID.UUID.UUIDString] stringByAppendingPathExtension:ext.length?ext:@"audio"];dest=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:leaf]];}
   if(!dest||![data writeToURL:dest options:NSDataWritingAtomic error:&e])failure=[@"目标写入失败：" stringByAppendingString:ErrorText(e,@"Application Support 无可写路径")];
  }
  if(!failure){AVAudioPlayer *probe=[[AVAudioPlayer alloc] initWithContentsOfURL:dest error:&e];if(!probe){failure=[@"音频格式验证失败：" stringByAppendingString:ErrorText(e,@"AVAudioPlayer 返回空")];[[NSFileManager defaultManager] removeItemAtURL:dest error:nil];}}
  dispatch_async(dispatch_get_main_queue(),^{
   if(failure){[self log:failure];[self alert:@"导入失败" message:failure];return;}
   NSUserDefaults *d=Defaults(); NSString *old=[d stringForKey:@"AudioPath"];self.localAudio=dest;
   [d setObject:dest.path forKey:@"AudioPath"];[d setObject:source.lastPathComponent?:@"音频" forKey:@"AudioName"];[d setInteger:data.length forKey:@"AudioSize"];
   BOOL synced=[d synchronize];[self log:[NSString stringWithFormat:@"导入成功：%@，%lu bytes，路径 %@，配置同步=%d；未确认跨进程访问",source.lastPathComponent,(unsigned long)data.length,dest.path,synced]];
   NSError *dirError=nil;NSString *local=LocalDir(&dirError);if([old hasPrefix:[local stringByAppendingString:@"/"]])[[NSFileManager defaultManager] removeItemAtPath:old error:nil];
   [self alert:@"导入成功" message:[NSString stringWithFormat:@"%@\n%lu bytes\n已保存至设置沙盒，仅保证本地试听路径。电话进程可能无权读取。",source.lastPathComponent,(unsigned long)data.length]];
  });
 });
}
- (NSURL *)audioURL{return self.localAudio?:([Defaults() stringForKey:@"AudioPath"].length?[NSURL fileURLWithPath:[Defaults() stringForKey:@"AudioPath"]]:nil);}
- (void)testAudio:(PSSpecifier *)s{
 NSURL *u=[self audioURL];NSError *e=nil;if(!u){[self alert:@"试听失败" message:@"未导入音频"];return;}
 self.player=[[AVAudioPlayer alloc] initWithContentsOfURL:u error:&e];
 if(!self.player||![self.player prepareToPlay]||![self.player play]){NSString *msg=ErrorText(e,@"播放器 prepare/play 返回 NO；文件可能不存在、格式不支持或音频路由不可用");[self log:[@"试听失败：" stringByAppendingString:msg]];[self alert:@"试听失败" message:msg];return;}[self log:@"设置模块本地试听开始；无通话上行注入，无电话模块运行证明"];
}
- (void)text:(NSString *)text title:(NSString *)title{UIViewController *c=[UIViewController new];UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero];v.text=text;v.editable=NO;v.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];c.view=v;c.title=title;[self.navigationController pushViewController:c animated:YES];}
- (void)openSystemAutoAnswer:(PSSpecifier *)s{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"方案1：系统备选" message:@"系统自动接听由 iOS 独立控制，插件总开关不能关闭它，且不支持本插件排除白名单。请手动前往：设置 → 辅助功能 → 触控 → 通话音频路由 → 自动接听通话。使用方案2时必须手动关闭该系统选项，避免系统先接听。下方深链未验证，可能不受当前 iOS 支持。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"尝试打开未验证深链" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSURL *u=[NSURL URLWithString:@"App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/CALL_AUDIO_ROUTING/AutoAnswerCalls"];[[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{[self log:ok?@"系统接受打开 URL；不证明到达自动接听页面":@"系统拒绝设置深链，请使用手动路径"];if(!ok)[self alert:@"无法打开" message:@"请手动前往：设置 → 辅助功能 → 触控 → 通话音频路由 → 自动接听通话"];});}];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)showLog:(PSSpecifier *)s{NSError *e=nil;NSString *dir=LocalDir(&e);NSString *text=[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"settings.log"] encoding:NSUTF8StringEncoding error:&e];NSString *name=[Defaults() stringForKey:@"AudioName"]?:@"未导入";[self text:[NSString stringWithFormat:@"仅设置进程日志（不是电话日志）\n音频：%@ (%ld bytes)\n路径：%@\n持久写入错误：%@\n读取：%@\n\n%@",name,(long)[Defaults() integerForKey:@"AudioSize"],[self audioURL].path?:@"无",self.writeError?:@"无",e?ErrorText(e,@"未知错误"):@"成功",text?:@"尚无本地日志"] title:@"设置诊断"] ;}
- (void)showCallRecords:(PSSpecifier *)s{CFStringRef domain=CFSTR("com.autoanswer.call.phone");CFPreferencesAppSynchronize(domain);id log=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Log"),domain));[self text:[NSString stringWithFormat:@"电话模块诊断（独立域，跨沙盒可见性不保证）\n最近本页收到 pong：%@\n未收到不等于未注入，也可能进程休眠或通知不可达。\n\n%@",self.pong?:@"未收到",[log isKindOfClass:NSString.class]?log:@"无法读取电话诊断域/没有记录；设置试听不能证明电话模块已加载。"] title:@"电话诊断"] ;}
- (void)pingPhone:(PSSpecifier *)s{self.pong=nil;uint32_t result=notify_post("com.autoanswer.call.ping");[self log:[NSString stringWithFormat:@"发送电话 ping status=%u",result]];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self alert:@"电话进程探测" message:self.pong?@"收到 MobilePhone pong，仅证明进程当时响应；未验证接听、锁屏或音频权限。":@"未收到 pong：可能未注入、进程休眠/未启动或通知不可达。请查看电话诊断，不能从设置试听推断插件可接听。"] ;});}
- (void)clearLog:(PSSpecifier *)s{NSError *e=nil;NSString *dir=LocalDir(&e);NSString *p=[dir stringByAppendingPathComponent:@"settings.log"];if(p&&[[NSFileManager defaultManager] fileExistsAtPath:p]&&![[NSFileManager defaultManager] removeItemAtPath:p error:&e])[self alert:@"清除失败" message:ErrorText(e,@"本地日志删除失败")];}
- (void)clearAudio:(PSSpecifier *)s{[self.player stop];self.player=nil;NSError *e=nil;NSString *dir=LocalDir(&e);NSURL *u=[self audioURL];if(u&&[u.path hasPrefix:[dir stringByAppendingString:@"/"]]&&[[NSFileManager defaultManager] fileExistsAtPath:u.path]&&![[NSFileManager defaultManager] removeItemAtURL:u error:&e]){[self alert:@"清除失败" message:ErrorText(e,@"目标删除失败")];return;}self.localAudio=nil;NSUserDefaults *d=Defaults();for(NSString *k in @[@"AudioPath",@"AudioName",@"AudioSize"])[d removeObjectForKey:k];[d synchronize];[self log:@"已清除本地音频配置"];}
@end
