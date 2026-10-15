#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static AVAudioPlayer *AACPlayer;
static NSDictionary *AACPrefs(void) { return [[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.autoanswer.call"] copy] ?: @{}; }
static BOOL AACEnabled(void) { id v=AACPrefs()[@"Enabled"]; return v ? [v boolValue] : YES; }
static NSTimeInterval AACDelay(void) { id v=AACPrefs()[@"Delay"]; return v ? MAX(0.0,MIN([v doubleValue],60.0)) : 0.5; }
static BOOL AACIncomingState(id state) { if (![state isKindOfClass:NSString.class]) return NO; NSString *s=[state lowercaseString]; return [s containsString:@"incoming"]||[s containsString:@"ring"]||[s containsString:@"alert"]||[s containsString:@"来电"]; }
static BOOL AACWhitelisted(id call) {
 NSString *number=nil; for (NSString *key in @[@"phoneNumber",@"address",@"remoteAddress",@"callerNumber"]) { SEL s=NSSelectorFromString(key); if([call respondsToSelector:s]) { id v=((id(*)(id,SEL))objc_msgSend)(call,s); if([v isKindOfClass:NSString.class]){number=v;break;} } }
 if(!number.length)return NO; NSString *list=AACPrefs()[@"Whitelist"];
 for(NSString *item in [list componentsSeparatedByString:@","]) { NSString *x=[item stringByReplacingOccurrencesOfString:@" " withString:@""]; if(x.length&&[number containsString:x])return YES; }
 return NO;
}
static void AACPlayAudio(void) {
 NSString *path=AACPrefs()[@"AudioPath"]; if(!path.length)return; NSURL *url=[NSURL fileURLWithPath:path]; if(![[NSFileManager defaultManager] fileExistsAtPath:path])return;
 NSError *e=nil; AACPlayer=[[AVAudioPlayer alloc] initWithContentsOfURL:url error:&e]; [AACPlayer prepareToPlay]; [AACPlayer play];
}
%hook CTCall
- (void)setCallState:(id)state {
 %orig;
 if(!AACEnabled()||!AACIncomingState(state)||AACWhitelisted(self))return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACDelay()*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(!AACEnabled())return; Class cls=objc_getClass("IOBluetoothHandsFreeDevice"); if(!cls)return; id i=nil; SEL shared=@selector(sharedInstance); if([cls respondsToSelector:shared])i=((id(*)(id,SEL))objc_msgSend)((id)cls,shared); SEL accept=@selector(acceptCall); if(i&&[i respondsToSelector:accept]){((void(*)(id,SEL))objc_msgSend)(i,accept); dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{AACPlayAudio();});}
 });
}
%end
%ctor { if([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobilePhone"]) NSLog(@"[AutoAnswer] loaded"); }
