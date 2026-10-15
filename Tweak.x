#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static AVAudioPlayer *AACPlayer;
static NSString *AACSharedDir(void) { return @"/var/jb/Library/Application Support/AutoAnswerCall"; }
static void AACLog(NSString *s) { [[NSFileManager defaultManager] createDirectoryAtPath:AACSharedDir() withIntermediateDirectories:YES attributes:nil error:nil]; NSString *p=[AACSharedDir() stringByAppendingPathComponent:@"AutoAnswerCall.log"]; NSString *line=[NSString stringWithFormat:@"[%@] %@\n",NSDate.date,s]; NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:p]; if(!h){[line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];}else{[h seekToEndOfFile];[h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];} }
static NSDictionary *AACPrefs(void) { return [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.autoanswer.call"] copy] ?: @{}; }
static BOOL AACEnabled(void) { id v=AACPrefs()[@"Enabled"]; return v ? [v boolValue] : YES; }
static NSTimeInterval AACDelay(void) { id v=AACPrefs()[@"Delay"]; return v ? MAX(0.0,MIN([v doubleValue],60.0)) : 0.5; }
static BOOL AACIncomingState(id state) { AACLog([NSString stringWithFormat:@"来电状态类型：%@",NSStringFromClass([state class])]); if (![state isKindOfClass:NSString.class]) return NO; NSString *s=[state lowercaseString]; return [s containsString:@"incoming"]||[s containsString:@"ring"]||[s containsString:@"alert"]||[s containsString:@"来电"]; }
static BOOL AACWhitelisted(id call) {
 NSString *number=nil; for (NSString *key in @[@"phoneNumber",@"address",@"remoteAddress",@"callerNumber"]) { SEL s=NSSelectorFromString(key); if([call respondsToSelector:s]) { id v=((id(*)(id,SEL))objc_msgSend)(call,s); if([v isKindOfClass:NSString.class]){number=v;break;} } }
 if(!number.length)return NO; NSString *list=AACPrefs()[@"Whitelist"];
 for(NSString *item in [list componentsSeparatedByString:@","]) { NSString *x=[item stringByReplacingOccurrencesOfString:@" " withString:@""]; if(x.length&&[number containsString:x])return YES; }
 return NO;
}
static void AACPlayAudio(void) {
 NSDictionary *prefs=AACPrefs(); if(![prefs[@"PlayAudio"] boolValue]) { AACLog(@"音频播放已关闭"); return; }
 NSString *path=prefs[@"AudioPath"]; if(!path.length) path=[AACSharedDir() stringByAppendingPathComponent:@"answer-audio"]; if(!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { AACLog(@"音频文件不存在"); return; } NSURL *url=[NSURL fileURLWithPath:path]; if(![[NSFileManager defaultManager] fileExistsAtPath:path])return;
 NSError *e=nil; AACPlayer=[[AVAudioPlayer alloc] initWithContentsOfURL:url error:&e]; if(e){AACLog([NSString stringWithFormat:@"音频初始化失败：%@",e.localizedDescription]);return;} [AACPlayer prepareToPlay]; [AACPlayer play]; AACLog(@"音频播放开始");
}
%hook CTCall
- (void)setCallState:(id)state {
 %orig;
 if(!AACEnabled()){AACLog(@"自动接听已关闭");return;} if(!AACIncomingState(state)){AACLog(@"状态未匹配");return;} if(AACWhitelisted(self)){AACLog(@"命中白名单，跳过接听");return;}
 AACLog(@"检测到符合条件的来电"); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACDelay()*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(!AACEnabled())return; Class cls=objc_getClass("IOBluetoothHandsFreeDevice"); if(!cls){AACLog(@"蓝牙接听类不存在");return;} id i=nil; SEL shared=@selector(sharedInstance); if([cls respondsToSelector:shared])i=((id(*)(id,SEL))objc_msgSend)((id)cls,shared); SEL accept=@selector(acceptCall); if(i&&[i respondsToSelector:accept]){AACLog(@"调用 acceptCall");((void(*)(id,SEL))objc_msgSend)(i,accept); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{AACPlayAudio();});}
 });
}
%end
%ctor { if([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobilePhone"]) NSLog(@"[AutoAnswer] loaded"); }
