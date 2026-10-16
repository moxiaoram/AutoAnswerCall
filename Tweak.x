#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "AACPolicy.h"
#import "AACRecords.h"
#import "AACCallLifecycle.h"
#import "AACSharedLog.h"
#import "AACProbe.h"
#import "AACInventory.h"
static NSString * const Domain=@"com.autoanswer.call";
static NSString * const PhoneDomain=@"com.autoanswer.call.phone";
static CXCallObserver *Observer;
static CXCallController *Controller;
static id RetainedDelegate;
static NSMutableDictionary<NSUUID *,NSMutableDictionary *> *States;
static AVAudioPlayer *Player;
static NSArray *Records;
static void Record(NSUUID *uuid,NSMutableDictionary *state,NSString *status,NSDictionary *flags){
 if([state[@"recordsCleared"] boolValue]||[state[@"outgoing"] boolValue])return;
 Records=AACRecordUpdate(Records,uuid.UUIDString,state[@"caller"],status,flags,NSDate.date);
 if(!AACWriteRecords(Records))NSLog(@"[AutoAnswerCall] record preferences write failed; Settings visibility not confirmed");
}
static NSUInteger StopGeneration;
static NSString *ProcessTag=@"unknown";
static void Log(NSString *s);
/* Stop latch and configuration validity are phone-side state, not derived
   from unverified cross-process preference visibility. */
static BOOL Stopped;
static BOOL ConfigValid;
static NSDictionary *Prefs(void){
 BOOL synced=CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
 NSDictionary *p=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,(__bridge CFStringRef)Domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
 /* Settings writes ConfigVersion on first load. Without it the domain is either
    never configured or not visible here; both must fail closed, never default to enabled. */
 ConfigValid=(p!=nil && synced && p[@"ConfigVersion"]!=nil);
 if(!ConfigValid)Log([NSString stringWithFormat:@"CONFIG INVALID: synced=%d keys=%lu; automatic answering disabled until settings configuration is readable",synced,(unsigned long)(p.count?:0)]);
 return p?:@{};
}
static void Log(NSString *s){
 /* 1.10.0: every line goes to the shared evidence channel, which also NSLogs it and
    never throws. Which path was chosen is itself logged there. */
 AACSharedAppend(ProcessTag,s);
 if(![ProcessTag isEqualToString:@"mobilephone"])return;
 /* Phone-side structured diagnostics: own CFPreferences domain; cross-sandbox
    visibility of this domain is not claimed anywhere. */
 NSString *line=[NSString stringWithFormat:@"[%@] PHONE %@\n",NSDate.date,s];
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
 if(Stopped){Log(@"Eligibility: plugin stop latched in phone process; awaiting explicit resume");return NO;}
 if(!ConfigValid){Log(@"Eligibility: configuration unreadable; refusing to schedule (fail closed)");return NO;}
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
static void ObserveConnection(NSUUID *uuid,NSMutableDictionary *s){
 BOOL submitted=[s[@"submitted"] boolValue];AACCancelForObservedConnection(s);
 Record(uuid,s,submitted?@"观察到连接；请求与人工/系统接听归因不明，已抑制自动播放":@"请求提交前已连接：手动/系统/其他，已取消自动接听和自动播放",@{@"connected":@YES,@"beforeRequest":@(!submitted)});
 Log(submitted?@"Connected after submission: answer ownership ambiguous; autoplay suppressed; imported files retained":@"Connected before submission (manual/system/other): UUID timers invalidated, autoplay suppressed; imported files retained");
 if(AACMayAutoplay(s))PlayLocal();
}
static void Changed(CXCall *call){
 NSUUID *uuid=call.UUID; if(!uuid)return; NSMutableDictionary *s=States[uuid];
 if(!s){s=[NSMutableDictionary dictionaryWithDictionary:@{@"scheduled":@NO,@"pending":@NO,@"attempted":@NO,@"accepted":@NO}];States[uuid]=s;}
 s[@"outgoing"]=@(call.outgoing);NSString *caller=Number(call);if(caller.length)s[@"caller"]=caller;
 Log([NSString stringWithFormat:@"Call %@ outgoing=%d connected=%d ended=%d",uuid.UUIDString,call.outgoing,call.hasConnected,call.hasEnded]);
 if(call.hasEnded){AACCancelForObservedConnection(s);if(!call.hasConnected)s[@"connectedObserved"]=@NO;Record(uuid,s,@"通话已结束",(call.hasConnected?@{@"ended":@YES,@"connected":@YES}:@{@"ended":@YES}));s[@"pending"]=@NO;s[@"attempted"]=@YES;[States removeObjectForKey:uuid];return;}
 if(call.hasConnected){ObserveConnection(uuid,s);return;}
 if([s[@"scheduled"] boolValue]||[s[@"attempted"] boolValue])return;
 if(!Allowed(call,Prefs())){Record(uuid,s,@"跳过：插件关闭、模式或排除策略不符合（见电话诊断）",nil);return;}
 s[@"scheduled"]=@YES; NSDictionary *p=Prefs(); double delay=p[@"Delay"]?AACBoundDelay([p[@"Delay"] doubleValue]):0.5;
 NSUInteger generation=StopGeneration;NSUInteger callGeneration=[s[@"callGeneration"] unsignedIntegerValue];
 Record(uuid,s,[NSString stringWithFormat:@"等待 %.15g 秒后重新检查",delay],nil);
 Log([NSString stringWithFormat:@"Scheduled %@ delay=%.15g seconds from first eligible observed incoming event, NOT measured audible ringing",uuid.UUIDString,delay]);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(generation!=StopGeneration){Log(@"Delayed answer cancelled by plugin stop generation");Record(uuid,s,@"取消：插件已停止",nil);return;}
  if(States[uuid]!=s){Log(@"Delayed answer dropped: call state no longer current");return;} s[@"scheduled"]=@NO; CXCall *live=Current(uuid);
  if(live.hasConnected){ObserveConnection(uuid,s);return;}
  if(!AACMaySubmit(s,callGeneration,live!=nil,live.hasConnected,live.hasEnded)){Log(@"Delayed answer invalidated by UUID connection/end generation or absent call");return;}
  if(!live||!Allowed(live,Prefs())){Log(@"Delayed answer cancelled: call absent/state or settings changed");Record(uuid,s,@"取消：通话消失、状态或设置已改变",nil);return;}
  s[@"attempted"]=@YES;s[@"pending"]=@YES;s[@"submitted"]=@YES;
  Record(uuid,s,@"已提交接听请求",@{@"submitted":@YES});
  CXAnswerCallAction *action=[[CXAnswerCallAction alloc] initWithCallUUID:uuid]; CXTransaction *tx=[[CXTransaction alloc] initWithAction:action];
  Log([NSString stringWithFormat:@"Submitting CXAnswerCallAction %@ (cellular authorization not guaranteed)",uuid.UUIDString]);
  [Controller requestTransaction:tx completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
   if(error){s[@"pending"]=@NO;Record(uuid,s,[NSString stringWithFormat:@"请求失败：%@/%ld %@",error.domain,(long)error.code,error.localizedDescription?:@""],@{@"failed":@YES});Log([NSString stringWithFormat:@"Answer transaction failed domain=%@ code=%ld detail=%@",error.domain,(long)error.code,error.localizedDescription?:@"No description"]);}
   else {s[@"accepted"]=@YES;Record(uuid,s,@"事务已接受；不代表连接",@{@"accepted":@YES});Log(@"Answer transaction accepted; this alone does not confirm connected");}
  });}];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(States[uuid]!=s)return; if([s[@"pending"] boolValue]){s[@"pending"]=@NO;Record(uuid,s,@"观察超时：未确认连接",@{@"timedOut":@YES});Log(@"Answer request observation timeout: no confirmed connection");}});
 });
}
@interface AACDelegate : NSObject<CXCallObserverDelegate> @end
@implementation AACDelegate
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call{Changed(call);}
@end
%ctor {
 NSString *bundle=NSBundle.mainBundle.bundleIdentifier?:@"";
 NSString *process=NSProcessInfo.processInfo.processName?:@"";
 /* 1.10.0 injects into BOTH SpringBoard and MobilePhone (see AutoAnswerCall.plist).
    Both ids below are official and case-sensitive. The historical wrong-case phone id
    stays only as a runtime compatibility fallback; it is never written to the filter. */
 BOOL inPhoneProcess=[bundle isEqualToString:@"com.apple.mobilephone"]||[bundle isEqualToString:@"com.apple.MobilePhone"]||[process isEqualToString:@"MobilePhone"];
 BOOL inSpringBoardProcess=[bundle.lowercaseString isEqualToString:@"com.apple.springboard"]||[process isEqualToString:@"SpringBoard"];
 if(inPhoneProcess)ProcessTag=@"mobilephone";else if(inSpringBoardProcess)ProcessTag=@"springboard";
 else ProcessTag=[@"other-" stringByAppendingString:(bundle.length?bundle:process)];
 NSLog(@"[AutoAnswerCall] dylib constructor reached; bundle=%@ process=%@ tag=%@",bundle,process,ProcessTag);
 if(!inPhoneProcess&&!inSpringBoardProcess){
  /* The filter is supposed to scope injection to the two bundles; anything else is
     reported as evidence instead of guessing which module should run. */
  AACSharedAppend(ProcessTag,@"unexpected process: no module logic runs; filter scoping may be wrong");
  return;
 }
 dispatch_async(dispatch_get_main_queue(),^{
  AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"Loaded 1.10.0 EVIDENCE build; bundle=%@ process=%@ tag=%@",bundle,process,ProcessTag]);
  AACProbeStart(ProcessTag);
  if(inSpringBoardProcess){
   AACSharedAppend(ProcessTag,@"SpringBoard module: runtime inventory only; no hooks installed and no answer behaviour changed");
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AACRunInventory(ProcessTag);});
   return;
  }
  if(inPhoneProcess){
  Records=AACReadRecords(NULL,NULL);States=[NSMutableDictionary new];Controller=[CXCallController new];Observer=[CXCallObserver new];RetainedDelegate=[AACDelegate new];[Observer setDelegate:RetainedDelegate queue:dispatch_get_main_queue()];
  Log(@"Loaded 1.10.0 evidence build; retained CXCallObserver in MobilePhone; suspension/lockscreen delivery not guaranteed");
  int token=0;notify_register_dispatch("com.autoanswer.call.ping",&token,dispatch_get_main_queue(),^(int t){Log(@"Ping acknowledged in MobilePhone");NSDictionary *actual=Prefs();Log([NSString stringWithFormat:@"Configuration observed: keys=%lu enabledPresent=%d mode=%@ delay=%@ whitelistPresent=%d",(unsigned long)actual.count,actual[@"Enabled"]!=nil,actual[@"Mode"]?:@"missing",actual[@"Delay"]?:@"missing",actual[@"Whitelist"]!=nil]);notify_post("com.autoanswer.call.pong");});
  int resumeToken=0;uint32_t resumeStatus=notify_register_dispatch("com.autoanswer.call.resume",&resumeToken,dispatch_get_main_queue(),^(int t){Stopped=NO;Log(@"Explicit resume observed from settings; stop latch cleared");});if(resumeStatus!=NOTIFY_STATUS_OK)Log(@"Resume notification registration failed");
  int stopToken=0;uint32_t stopStatus=notify_register_dispatch("com.autoanswer.call.stop",&stopToken,dispatch_get_main_queue(),^(int t){StopGeneration++;Stopped=YES;for(NSMutableDictionary *s in States.allValues){if([s[@"scheduled"] boolValue]){s[@"scheduled"]=@NO;s[@"attempted"]=@YES;}}[Player stop];Log(@"Plugin stop observed; invalidated unsubmitted timers, existing transactions cannot be revoked; native system switch unaffected");});if(stopStatus!=NOTIFY_STATUS_OK)Log(@"Plugin stop notification registration failed; delayed preferences revalidation still applies");
  int clearToken=0;uint32_t clearStatus=notify_register_dispatch("com.autoanswer.call.records.clear",&clearToken,dispatch_get_main_queue(),^(int t){
   /* Only MobilePhone owns deletion. Never trust a Settings-side empty read as acknowledgement. */
   for(NSMutableDictionary *state in States.allValues)state[@"recordsCleared"]=@YES;
   Records=@[];BOOL saved=AACWriteRecords(Records);BOOL synced=NO,present=NO;NSArray *readback=AACReadRecords(&synced,&present);
   if(saved&&synced&&present&&!readback.count)notify_post("com.autoanswer.call.records.cleared");
   else notify_post("com.autoanswer.call.records.clearFailed");
  });if(clearStatus!=NOTIFY_STATUS_OK)Log(@"Phone record clear notification registration failed");
  /* A ringing call that predates this process has no observed start event. Scheduling a
     fresh full delay from the observation instant is the only defensible option; never
     assume the call began earlier. */
  Log(@"Initial observer snapshot processed with a fresh full delay from the observation instant, not from the real ringing start");
  for(CXCall *c in Observer.calls.copy){if(!c.hasEnded&&!c.hasConnected&&!c.outgoing){Log(@"Snapshot incoming call scheduled from observation instant");Changed(c);}}
  }
 });
}
