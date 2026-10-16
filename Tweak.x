#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CallKit/CallKit.h>

static AVAudioPlayer *AACPlayer;
static NSString *AACSharedDir(void) { return @"/var/jb/Library/Application Support/AutoAnswerCall"; }
static void AACLog(NSString *s) { NSString *line=[NSString stringWithFormat:@"[%@] %@\n",NSDate.date,s]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d setObject:line forKey:@"LastStatus"]; NSString *old=[d stringForKey:@"LastLog"]?:@""; NSString *all=[[old stringByAppendingString:line] length]>12000?[old substringFromIndex:MIN(old.length,6000)]:[old stringByAppendingString:line]; [d setObject:all forKey:@"LastLog"]; [d synchronize]; [[NSFileManager defaultManager] createDirectoryAtPath:AACSharedDir() withIntermediateDirectories:YES attributes:nil error:nil]; NSString *p=[AACSharedDir() stringByAppendingPathComponent:@"AutoAnswerCall.log"]; NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:p]; if(!h){[line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];}else{[h seekToEndOfFile];[h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];} }
static NSDictionary *AACPrefs(void) { return [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.autoanswer.call"] copy] ?: @{}; }
static BOOL AACEnabled(void) { NSDictionary *p=AACPrefs(); id v=p[@"Enabled"]?:p[@"AutoAnswerEnabled"]; return v ? [v boolValue] : YES; }
static NSTimeInterval AACDelay(void) { NSDictionary *p=AACPrefs(); id v=p[@"Delay"]?:p[@"DelayTime"]; return v ? MAX(0.0,MIN([v doubleValue],60.0)) : 0.5; }
static BOOL AACIncomingState(id state) { AACLog([NSString stringWithFormat:@"来电状态类型：%@",NSStringFromClass([state class])]); if (![state isKindOfClass:NSString.class]) return NO; NSString *s=[state lowercaseString]; return [s containsString:@"incoming"]||[s containsString:@"ring"]||[s containsString:@"alert"]||[s containsString:@"来电"]; }
static BOOL AACWhitelisted(id call) {
 NSString *number=nil; for (NSString *key in @[@"phoneNumber",@"address",@"remoteAddress",@"callerNumber"]) { SEL s=NSSelectorFromString(key); if([call respondsToSelector:s]) { id v=((id(*)(id,SEL))objc_msgSend)(call,s); if([v isKindOfClass:NSString.class]){number=v;break;} } }
 if(!number.length)return NO; NSString *list=AACPrefs()[@"Whitelist"];
 for(NSString *item in [list componentsSeparatedByString:@","]) { NSString *x=[item stringByReplacingOccurrencesOfString:@" " withString:@""]; if(x.length&&[number containsString:x])return YES; }
 return NO;
}
static void AACRecord(NSString *number, NSString *result) { NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; NSDateFormatter *f=[NSDateFormatter new]; f.dateFormat=@"yyyy-MM-dd HH:mm:ss"; NSString *line=[NSString stringWithFormat:@"%@ 号码：%@ 结果：%@\n",[f stringFromDate:NSDate.date],number.length?number:@"未知",result]; NSString *old=[d stringForKey:@"CallRecords"]?:@""; NSString *all=[old stringByAppendingString:line]; if(all.length>12000)all=[all substringFromIndex:all.length-12000]; [d setObject:all forKey:@"CallRecords"]; [d synchronize]; AACLog(line); }
static void AACPlayAudio(void) {
 NSDictionary *prefs=AACPrefs(); if(![prefs[@"PlayAudio"] boolValue]) { AACLog(@"音频播放已关闭"); return; }
 NSString *path=prefs[@"AudioPath"]; if(!path.length) path=[AACSharedDir() stringByAppendingPathComponent:@"answer-audio"]; if(!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { AACLog(@"音频文件不存在"); return; } NSURL *url=[NSURL fileURLWithPath:path]; if(![[NSFileManager defaultManager] fileExistsAtPath:path])return;
 NSError *e=nil; AACPlayer=[[AVAudioPlayer alloc] initWithContentsOfURL:url error:&e]; if(e){AACLog([NSString stringWithFormat:@"音频初始化失败：%@",e.localizedDescription]);return;} [AACPlayer prepareToPlay]; [AACPlayer play]; AACLog(@"音频播放开始");
}
static NSString *AACCallNumber(id update) { @try { id remote=[update valueForKey:@"remoteID"]; NSURL *uri=[remote valueForKey:@"URI"]; NSString *v=uri.absoluteString; return [v hasPrefix:@"tel:"]?[v substringFromIndex:4]:nil; } @catch(__unused NSException *e){ return nil; } }
static void AACHandleCallUpdate(id update) {
 @try {
  BOOL outgoing=[[update valueForKey:@"hasOutgoing"] boolValue]; BOOL connected=[[update valueForKey:@"hasConnected"] boolValue]; BOOL ended=[[update valueForKey:@"hasEnded"] boolValue]; NSString *number=AACCallNumber(update);
  AACLog([NSString stringWithFormat:@"锁屏CallKit回调 outgoing=%@ connected=%@ ended=%@ number=%@",outgoing?@"YES":@"NO",connected?@"YES":@"NO",ended?@"YES":@"NO",number.length?@"已取得":@"未知"]);
  if(!outgoing&&!connected&&!ended&&AACEnabled()) { AACRecord(number,@"检测到锁屏来电，等待延迟"); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACDelay()*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ AACRecord(number,@"锁屏延迟结束；系统接听事务需设备接口验证"); }); }
 } @catch(NSException *e) { AACLog([NSString stringWithFormat:@"锁屏回调解析失败：%@",e.reason]); }
}
@interface AACCallObserverDelegate : NSObject <CXCallObserverDelegate> @end
@implementation AACCallObserverDelegate
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCallUpdate *)update { AACHandleCallUpdate(update); }
@end
static CXCallObserver *AACObserver; static AACCallObserverDelegate *AACObserverDelegate;
static void AACStartObserver(void) { AACObserver=[CXCallObserver new]; AACObserverDelegate=[AACCallObserverDelegate new]; [AACObserver setDelegate:AACObserverDelegate queue:dispatch_get_main_queue()]; AACLog(@"锁屏 CallKit 观察者已创建"); }
%hook CTCall
- (void)setCallState:(id)state {
 %orig;
 if(!AACEnabled()){AACRecord(nil,@"未启用");return;} if(!AACIncomingState(state)){AACRecord(nil,@"状态不匹配");return;} if(AACWhitelisted(self)){AACRecord(nil,@"命中白名单，跳过");return;}
 AACRecord(nil,@"检测到来电，等待延迟"); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACDelay()*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(!AACEnabled()){AACRecord(nil,@"延迟后已关闭");return;} Class cls=objc_getClass("IOBluetoothHandsFreeDevice"); if(!cls){AACRecord(nil,@"接听类不存在");return;} id i=nil; SEL shared=@selector(sharedInstance); if([cls respondsToSelector:shared])i=((id(*)(id,SEL))objc_msgSend)((id)cls,shared); SEL accept=@selector(acceptCall); if(i&&[i respondsToSelector:accept]){AACRecord(nil,@"调用 acceptCall");((void(*)(id,SEL))objc_msgSend)(i,accept); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{AACPlayAudio();});}
 });
}
%end
%hook CXCallObserver
- (void)callObserver:(id)observer callChanged:(id)callUpdate {
 %orig;
 AACLog([NSString stringWithFormat:@"CXCallObserver回调，update类型=%@",NSStringFromClass([callUpdate class])]);
 @try {
  BOOL outgoing=[[callUpdate valueForKey:@"hasOutgoing"] boolValue];
  BOOL connected=[[callUpdate valueForKey:@"hasConnected"] boolValue];
  BOOL ended=[[callUpdate valueForKey:@"hasEnded"] boolValue];
  AACLog([NSString stringWithFormat:@"通话状态 outgoing=%@ connected=%@ ended=%@",outgoing?@"YES":@"NO",connected?@"YES":@"NO",ended?@"YES":@"NO"]);
 } @catch(NSException *e) { AACLog([NSString stringWithFormat:@"读取 CXCallUpdate 失败：%@",e.reason]); }
}
%end
%ctor { if([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobilePhone"]) { AACLog(@"插件已加载：MobilePhone"); AACStartObserver(); NSLog(@"[AutoAnswer] loaded"); } }
