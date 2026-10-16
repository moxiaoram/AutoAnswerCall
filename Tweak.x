#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "AACPolicy.h"
static NSString * const Domain=@"com.autoanswer.call";
static NSString * const PhoneDomain=@"com.autoanswer.call.phone";
static CXCallObserver *Observer;
static CXCallController *Controller;
static id RetainedDelegate;
static NSMutableDictionary<NSUUID *,NSMutableDictionary *> *States;
static AVAudioPlayer *Player;
static NSUInteger StopGeneration;
static NSDictionary *Prefs(void){CFPreferencesAppSynchronize((__bridge CFStringRef)Domain); return CFBridgingRelease(CFPreferencesCopyMultiple(NULL,(__bridge CFStringRef)Domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost))?:@{};}
static void Log(NSString *s){
 NSString *line=[NSString stringWithFormat:@"[%@] PHONE %@\n",NSDate.date,s]; NSLog(@"[AutoAnswerCall] %@",s);
 CFPreferencesAppSynchronize((__bridge CFStringRef)PhoneDomain);
 NSString *old=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Log"),(__bridge CFStringRef)PhoneDomain))?:@"";
 NSString *all=[old stringByAppendingString:line]; if(all.length>24000)all=[all substringFromIndex:all.length-24000];
 CFPreferencesSetAppValue(CFSTR("Log"),(__bridge CFPropertyListRef)all,(__bridge CFStringRef)PhoneDomain);
 CFPreferencesSetAppValue(CFSTR("LastSeen"),(__bridge CFPropertyListRef)NSDate.date,(__bridge CFStringRef)PhoneDomain);
 if(!CFPreferencesAppSynchronize((__bridge CFStringRef)PhoneDomain))NSLog(@"[AutoAnswerCall] phone diagnostic preferences write failed");
}
static NSString *Normal(NSString *s){char b[128];return AACNormalize(s.UTF8String,b,sizeof(b))?[NSString stringWithUTF8String:b]:nil;}
/* CXCall has no public caller-number API. Only invoke an optional object-returning,
 zero-argument getter after checking its complete ABI; do not use KVC or scalars. */
static NSString *Number(CXCall *call){
 for(NSString *name in @[@"phoneNumber",@"callerNumber"]){
  SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(object_getClass(call),sel); if(!m||method_getNumberOfArguments(m)!=2)continue;
  char rt[32]={0}; method_getReturnType(m,rt,sizeof(rt)); if(rt[0]!='@')continue;
  @try {id value=((id(*)(id,SEL))objc_msgSend)(call,sel); if([value isKindOfClass:NSString.class])return Normal(value);} @catch(NSException *e){Log([@"Optional number getter failed: " stringByAppendingString:e.reason?:@"unknown exception"]);}
 } return nil;
}
static BOOL Allowed(CXCall *call,NSDictionary *p){
 BOOL enabled=p[@"Enabled"]?[p[@"Enabled"] boolValue]:YES; NSInteger mode=p[@"Mode"]?[p[@"Mode"] integerValue]:2;
 NSString *raw=[p[@"Whitelist"] isKindOfClass:NSString.class]?p[@"Whitelist"]:@""; BOOL hasList=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;
 NSString *number=Number(call); BOOL excluded=NO, invalid=NO;
 for(NSString *entry in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，;\n"]]){
  NSString *t=[entry stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!t.length)continue; NSString *n=Normal(t); if(!n)invalid=YES; if(n&&[n isEqualToString:number])excluded=YES;
 }
 BOOL ok=AACShouldRequest(enabled,(int)mode,call.outgoing,call.hasConnected,call.hasEnded,excluded,hasList&&!number)&&!invalid;
 if(!ok)Log([NSString stringWithFormat:@"Eligibility: enabled=%d mode=%ld outgoing=%d connected=%d ended=%d excluded=%d unknownWithList=%d invalidList=%d",enabled,(long)mode,call.outgoing,call.hasConnected,call.hasEnded,excluded,hasList&&!number,invalid]);
 return ok;
}
static CXCall *Current(NSUUID *uuid){for(CXCall *c in Observer.calls)if([c.UUID isEqual:uuid])return c;return nil;}
static void PlayLocal(void){
 NSDictionary *p=Prefs(); if(![p[@"PlayAudio"] boolValue])return; NSString *path=[p[@"AudioPath"] isKindOfClass:NSString.class]?p[@"AudioPath"]:nil;
 if(!path.length){Log(@"Local audio: no configured path; settings sandbox file is not shared by entitlement");return;}
 NSError *e=nil; Player=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&e];
 if(!Player){Log([NSString stringWithFormat:@"Local audio source inaccessible/unsupported: %@",e.localizedDescription?:@"AVAudioPlayer returned nil"]);return;}
 if(![Player prepareToPlay]||![Player play])Log(@"Local audio playback returned NO; no uplink injection"); else Log(@"Local playback started only; no call uplink injection");
}
static void Changed(CXCall *call){
 NSUUID *uuid=call.UUID; if(!uuid)return; NSMutableDictionary *s=States[uuid];
 if(!s){s=[NSMutableDictionary dictionaryWithDictionary:@{@"scheduled":@NO,@"pending":@NO,@"attempted":@NO,@"accepted":@NO}];States[uuid]=s;}
 Log([NSString stringWithFormat:@"Call %@ outgoing=%d connected=%d ended=%d",uuid.UUIDString,call.outgoing,call.hasConnected,call.hasEnded]);
 if(call.hasConnected){
  if([s[@"pending"] boolValue]){Log(@"Observed connected while answer request pending; correlation only, manual/system answer cannot be excluded");s[@"pending"]=@NO;if([s[@"accepted"] boolValue])PlayLocal();}
  else Log(@"Observed connected without pending request (manual/system/other); no automatic success claim");
  s[@"attempted"]=@YES;return;
 }
 if(call.hasEnded){s[@"pending"]=@NO;s[@"attempted"]=@YES;return;}
 if([s[@"scheduled"] boolValue]||[s[@"attempted"] boolValue]||!Allowed(call,Prefs()))return;
 s[@"scheduled"]=@YES; NSDictionary *p=Prefs(); double delay=p[@"Delay"]?AACBoundDelay([p[@"Delay"] doubleValue]):0.5;
 NSUInteger generation=StopGeneration;
 Log([NSString stringWithFormat:@"Scheduled %@ delay=%.15g seconds from first eligible observed incoming event, NOT measured audible ringing",uuid.UUIDString,delay]);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(States[uuid]!=s||generation!=StopGeneration){Log(@"Delayed answer cancelled by plugin stop generation");return;} s[@"scheduled"]=@NO; CXCall *live=Current(uuid);
  if(!live||!Allowed(live,Prefs())){Log(@"Delayed answer cancelled: call absent/state or settings changed");return;}
  s[@"attempted"]=@YES;s[@"pending"]=@YES;
  CXAnswerCallAction *action=[[CXAnswerCallAction alloc] initWithCallUUID:uuid]; CXTransaction *tx=[[CXTransaction alloc] initWithAction:action];
  Log([NSString stringWithFormat:@"Submitting CXAnswerCallAction %@ (cellular authorization not guaranteed)",uuid.UUIDString]);
  [Controller requestTransaction:tx completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
   if(error){s[@"pending"]=@NO;Log([NSString stringWithFormat:@"Answer transaction failed domain=%@ code=%ld detail=%@",error.domain,(long)error.code,error.localizedDescription?:@"No description"]);}
   else {s[@"accepted"]=@YES;Log(@"Answer transaction accepted; this alone does not confirm connected");}
  });}];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if([s[@"pending"] boolValue]){s[@"pending"]=@NO;Log(@"Answer request observation timeout: no confirmed connection");}});
 });
}
@interface AACDelegate : NSObject<CXCallObserverDelegate> @end
@implementation AACDelegate
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call{Changed(call);}
@end
%ctor {
 if([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobilePhone"]){dispatch_async(dispatch_get_main_queue(),^{
  States=[NSMutableDictionary new];Controller=[CXCallController new];Observer=[CXCallObserver new];RetainedDelegate=[AACDelegate new];[Observer setDelegate:RetainedDelegate queue:dispatch_get_main_queue()];
  Log(@"Loaded 1.9.0; retained CXCallObserver in MobilePhone; suspension/lockscreen delivery not guaranteed");
  int token=0;notify_register_dispatch("com.autoanswer.call.ping",&token,dispatch_get_main_queue(),^(int t){Log(@"Ping acknowledged in MobilePhone");notify_post("com.autoanswer.call.pong");});
  int stopToken=0;uint32_t stopStatus=notify_register_dispatch("com.autoanswer.call.stop",&stopToken,dispatch_get_main_queue(),^(int t){StopGeneration++;for(NSMutableDictionary *s in States.allValues){if([s[@"scheduled"] boolValue]){s[@"scheduled"]=@NO;s[@"attempted"]=@YES;}}[Player stop];Log(@"Plugin stop observed; invalidated unsubmitted timers, existing transactions cannot be revoked; native system switch unaffected");});if(stopStatus!=NOTIFY_STATUS_OK)Log(@"Plugin stop notification registration failed; delayed preferences revalidation still applies");
  Log(@"Initial observer snapshot is diagnostic only, not a ringing-start event; no delay scheduled until a delegate event");
 });}
}
