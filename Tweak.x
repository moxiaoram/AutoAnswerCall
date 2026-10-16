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
#import "AACAnswerHost.h"
#import "AACSpringBoard.h"
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
/* 1.12.0: the answer host installs its own submit step (runtime-discovered UI answer
   path). Left nil in the phone module, which keeps the 1.9.x/1.10.0 CXAnswerCallAction
   transaction path byte-for-byte unchanged. */
static void (^SubmitBlock)(NSUUID *,NSMutableDictionary *);
/* Device evidence 1.11.0 (19:46:53 call): SpringBoard detected the call, ran the 6 s
   delay and the policy layer correctly, then reported "未发现可调用的 UI 接听路径" and the
   public CXAnswerCallAction fallback failed with
   com.apple.CallKit.error.requesttransaction code 1 = unknownCallUUID: our own
   CXCallController does not own this cellular call, so the public transaction path is
   effectively dead on this device. It stays a single clearly-labelled diagnostic
   attempt and is never treated as the answering plan. */
static NSString *CallKitErrorMeaning(NSString *domain,NSInteger code){
 if([domain isEqualToString:@"com.apple.CallKit.error.requesttransaction"]){
  switch(code){
   case 1:return @"code 1 = unknownCallUUID：本进程的 CXCallController 不拥有该蜂窝通话，公开事务路径在本设备上无效（已实测）";
   case 2:return @"code 2 = callUUIDAlreadyExists：同一 UUID 已存在通话，事务被拒绝";
   case 3:return @"code 3 = invalidAction：事务中的 action 类型不被接受";
   case 4:return @"code 4 = maximumCallGroupsReached：通话组数量达到上限";
   default:return [NSString stringWithFormat:@"code %ld = requesttransaction 未记录/未知错误（不猜测含义）",(long)code];
  }
 }
 if([domain isEqualToString:@"com.apple.CallKit.error.incomingcall"]){
  switch(code){
   case 1:return @"code 1 = unentitled：缺少 CallKit 权限";
   case 2:return @"code 2 = callUUIDAlreadyExists：UUID 已存在";
   case 3:return @"code 3 = filteredByDoNotDisturb：被勿扰模式过滤";
   case 4:return @"code 4 = filteredByBlockList：被黑名单过滤";
   default:return [NSString stringWithFormat:@"code %ld = incomingcall 未记录/未知错误（不猜测含义）",(long)code];
  }
 }
 return [NSString stringWithFormat:@"未记录的错误域/码：%@/%ld（不猜测含义）",domain,(long)code];
}
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
 if(!Allowed(call,Prefs())){Record(uuid,s,@"跳过：插件关闭、模式或排除策略不符合（见共享日志：Eligibility 行）",nil);return;}
 /* A call event can arrive before the answer UI classes are loaded; retry the bounded
    runtime enumeration once here (SpringBoard only; no-op for the phone module). */
 if(SubmitBlock)AACSBRetryDiscoveryIfEmpty();
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
  s[@"attempted"]=@YES;s[@"pending"]=@YES;
  /* 1.11.0: SpringBoard installs the runtime-discovered UI answer step here; the phone
     module leaves SubmitBlock nil and keeps the original transaction code untouched. */
  if(SubmitBlock){SubmitBlock(uuid,s);}else{
  s[@"submitted"]=@YES;
  Record(uuid,s,@"已提交接听请求",@{@"submitted":@YES});
  CXAnswerCallAction *action=[[CXAnswerCallAction alloc] initWithCallUUID:uuid]; CXTransaction *tx=[[CXTransaction alloc] initWithAction:action];
  Log([NSString stringWithFormat:@"Submitting CXAnswerCallAction %@ (cellular authorization not guaranteed)",uuid.UUIDString]);
  [Controller requestTransaction:tx completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
   if(error){s[@"pending"]=@NO;Record(uuid,s,[NSString stringWithFormat:@"请求失败：%@/%ld %@",error.domain,(long)error.code,error.localizedDescription?:@""],@{@"failed":@YES});Log([NSString stringWithFormat:@"Answer transaction failed domain=%@ code=%ld detail=%@",error.domain,(long)error.code,error.localizedDescription?:@"No description"]);}
   else {s[@"accepted"]=@YES;Record(uuid,s,@"事务已接受；不代表连接",@{@"accepted":@YES});Log(@"Answer transaction accepted; this alone does not confirm connected");}
  });}];
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(States[uuid]!=s)return; if([s[@"pending"] boolValue]){s[@"pending"]=@NO;Record(uuid,s,@"观察超时：未确认连接",@{@"timedOut":@YES});Log(@"Answer request observation timeout: no confirmed connection");}});
 });
}
@interface AACDelegate : NSObject<CXCallObserverDelegate> @end
@implementation AACDelegate
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call{Changed(call);}
@end
/* 1.9.x/1.10.0 control notifications, unchanged semantics: the same three names are
   registered by whichever module is actually loaded. On this device only SpringBoard is
   present, so SpringBoard also owns record deletion. */
static void RegisterControls(void){
 int resumeToken=0;uint32_t resumeStatus=notify_register_dispatch("com.autoanswer.call.resume",&resumeToken,dispatch_get_main_queue(),^(int t){Stopped=NO;Log(@"Explicit resume observed from settings; stop latch cleared");});if(resumeStatus!=NOTIFY_STATUS_OK)Log(@"Resume notification registration failed");
 int stopToken=0;uint32_t stopStatus=notify_register_dispatch("com.autoanswer.call.stop",&stopToken,dispatch_get_main_queue(),^(int t){StopGeneration++;Stopped=YES;for(NSMutableDictionary *s in States.allValues){if([s[@"scheduled"] boolValue]){s[@"scheduled"]=@NO;s[@"attempted"]=@YES;}}[Player stop];Log(@"Plugin stop observed; invalidated unsubmitted timers, existing transactions cannot be revoked; native system switch unaffected");});if(stopStatus!=NOTIFY_STATUS_OK)Log(@"Plugin stop notification registration failed; delayed preferences revalidation still applies");
 int clearToken=0;uint32_t clearStatus=notify_register_dispatch("com.autoanswer.call.records.clear",&clearToken,dispatch_get_main_queue(),^(int t){
  /* The loaded module owns deletion. Never trust a Settings-side empty read as acknowledgement. */
  for(NSMutableDictionary *state in States.allValues)state[@"recordsCleared"]=@YES;
  Records=@[];BOOL saved=AACWriteRecords(Records);BOOL synced=NO,present=NO;NSArray *readback=AACReadRecords(&synced,&present);
  if(saved&&synced&&present&&!readback.count)notify_post("com.autoanswer.call.records.cleared");
  else notify_post("com.autoanswer.call.records.clearFailed");
 });if(clearStatus!=NOTIFY_STATUS_OK)Log(@"Record clear notification registration failed; phone diagnostics remain the only fallback");
}
/* Host-parameterised answer module (1.12.0).
   Device evidence that shaped this version: SpringBoard announces itself over Darwin and
   detects a real call (UUID recorded, 6 s delay executed, policy layer worked), but it
   has NO hookable answer UI and the public CXAnswerCallAction fallback fails with
   com.apple.CallKit.error.requesttransaction code 1 (unknownCallUUID) — a third-party
   controller does not own the cellular call. InCallService is therefore the primary
   answering host: the exact same 1.9.x/1.10.0/1.11.0 policy (fail-closed config, stop
   latch, mode 2, exact-match exclusion list, N-second delay, re-verification before
   acting) plus the SAME runtime discovery + dynamic hook + capture machinery from
   AACSpringBoard.h, parameterised by the host descriptor from AACAnswerHost.h.
   Only ONE host answers: the single-owner rule is enforced in AACSBShouldAnswer before
   anything is submitted, and a per-host answered-UUID set refuses a second submission
   for the same call UUID. */
static void AnswerHostStart(NSDictionary *host){
 NSString *tag=host[@"tag"],*display=host[@"display"],*pong=host[@"pong"];
 Records=AACReadRecords(NULL,NULL);States=[NSMutableDictionary new];Controller=[CXCallController new];Observer=[CXCallObserver new];RetainedDelegate=[AACDelegate new];[Observer setDelegate:RetainedDelegate queue:dispatch_get_main_queue()];
 Log([NSString stringWithFormat:@"Loaded 1.12.0 answer host: %@ (tag=%@ probe=%@ pong=%@ discovery=%@); retained its own CXCallObserver in %@; runtime discovery of the real incoming-call UI starts now",display,tag,host[@"probe"],pong,host[@"discovery"],display]);
 Log([NSString stringWithFormat:@"接听归属角色表：%@；每个宿主都观察并记录，但只有一个宿主提交接听（InCallService 优先，其次 SpringBoard，否则仅日志）",AACAnswerRoleTableText()]);
 AACSBEnv *env=[AACSBEnv new];
 env.host=host;env.process=tag;
 env.prefs=^NSDictionary *{return Prefs();};
 env.allowed=^BOOL(CXCall *call){return Allowed(call,Prefs());};
 env.log=^(NSString *message){Log(message);};
 env.record=^(NSString *status,NSDictionary *flags){Records=AACRecordUpdate(Records,[NSString stringWithFormat:@"%@-discovery",tag],display,status,flags,NSDate.date);if(!AACWriteRecords(Records))Log(@"record preferences write failed; Settings visibility of the discovery record not confirmed");};
 RegisterControls();
 /* Observe EVERY host's probe (and every answer host's ownership claim): that observed
    liveness is the evidence behind the single-owner rule. Both of these notification
    families are proven to cross process boundaries on this device (SpringBoard's probes
    arrive in Settings). */
 for(NSString *probeName in AACAnswerProbeNames()){
  int probeToken=0;uint32_t probeStatus=notify_register_dispatch(probeName.UTF8String,&probeToken,dispatch_get_main_queue(),^(int t){
   NSString *peerTag=nil;
   for(NSDictionary *h in AACAnswerHostTable())if([h[@"probe"] isEqualToString:probeName]){peerTag=h[@"tag"];break;}
   if(!peerTag.length)return;
   AACAnswerHostSeenProbe(peerTag);
   AACSBHostProbeArrived(peerTag);
  });
  if(probeStatus!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"probe observer registration failed for %@ (status=%u); ownership freshness for that host is then unobserved",probeName,probeStatus]);
 }
 for(NSString *claimName in AACAnswerOwnerClaimNames()){
  int claimToken=0;uint32_t claimStatus=notify_register_dispatch(claimName.UTF8String,&claimToken,dispatch_get_main_queue(),^(int t){
   for(NSDictionary *h in AACAnswerHostsAnswerCapable())if([AACAnswerOwnerClaimName(h[@"tag"]) isEqualToString:claimName]){AACAnswerHostSeenOwnerClaim(h[@"tag"]);AACSBHostProbeArrived(h[@"tag"]);return;}
  });
  if(claimStatus!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"owner-claim observer registration failed for %@ (status=%u)",claimName,claimStatus]);
 }
 int pingToken=0;uint32_t pingStatus=notify_register_dispatch("com.autoanswer.call.ping",&pingToken,dispatch_get_main_queue(),^(int t){Log([NSString stringWithFormat:@"Legacy Darwin ping observed in %@; answering on %@",display,pong]);uint32_t posted=notify_post(pong.UTF8String);if(posted!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"pong post failed status=%u",posted]);});
 if(pingStatus!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"%@ ping notification registration failed",display]);
 SubmitBlock=^(NSUUID *uuid,NSMutableDictionary *state){
  /* Single-owner gate, re-evaluated at answer time (not only at load). */
  NSString *ownership=nil;
  if(!AACSBShouldAnswer(&ownership)){
   state[@"observerOnly"]=@YES;
   Record(uuid,state,[NSString stringWithFormat:@"观察者：本宿主不提交接听（接听由 %@ 负责）",AACSBHostOwnerTagText()],@{@"observerOnly":@YES});
   Log([NSString stringWithFormat:@"observer only, answer owned by %@; %@ 不提交接听，避免两个宿主对同一通话重复提交：%@",AACSBHostOwnerTagText(),display,ownership?:@""]);
   return;
  }
  if(!AACSBClaimAnswerUUID(uuid.UUIDString)){
   Record(uuid,state,@"已拒绝重复提交：该通话 UUID 已由本宿主提交过接听",@{@"duplicate":@YES});
   Log([NSString stringWithFormat:@"duplicate answer submission refused for %@ (同一 UUID 只提交一次)",uuid.UUIDString]);
   return;
  }
  NSDictionary *recheck=Prefs();
  Log([NSString stringWithFormat:@"%@ re-verify before answering: settings re-read (fail-closed configValid=%d keys=%lu enabled=%@ mode=%@ delay=%@); %@; the call itself was re-checked as still incoming/unanswered immediately before this step",display,ConfigValid,(unsigned long)recheck.count,recheck[@"Enabled"]?:@"missing",recheck[@"Mode"]?:@"missing",recheck[@"Delay"]?:@"missing",AACSBHostRoleText()]);
  NSString *source=nil;id target=AACSBAnswerTarget(&source);
  NSString *reason=nil;BOOL invoked=AACSBInvokeDiscovered(target,&reason);
  state[@"discoveredPath"]=@(invoked);
  if(invoked){
   state[@"submitted"]=@YES;
   Record(uuid,state,@"已调用运行时发现的 UI 接听方法（尚未确认接通）",@{@"submitted":@YES,@"discovered":@YES});
   Log([NSString stringWithFormat:@"discovered UI answer path invoked; host=%@ source=%@; %@",display,source?:@"unknown",reason?:@""]);
   Log(@"this call is NOT yet confirmed: success is only reported when CXCallObserver reports hasConnected");
   return;
  }
  /* Primary path unavailable: stay honest, log-only, then make exactly ONE clearly
     labelled secondary attempt with the public transaction API. That API is proven
     ineffective for a third-party controller on this device (it does not own the
     cellular call: com.apple.CallKit.error.requesttransaction code 1 = unknownCallUUID),
     so it is a diagnostic and not the answering plan. */
  Record(uuid,state,@"未发现可调用的 UI 接听路径（仅日志）；已做一次公开事务诊断尝试（本设备已证明无效）",@{@"discovered":@NO,@"logOnly":@YES});
  Log([NSString stringWithFormat:@"LOG-ONLY primary path in %@: no captured/rescanned UI object could answer (source=%@, reason=%@)",display,source?:@"unknown",reason?:@"unknown"]);
  state[@"submitted"]=@YES;
  CXAnswerCallAction *action=[[CXAnswerCallAction alloc] initWithCallUUID:uuid];CXTransaction *tx=[[CXTransaction alloc] initWithAction:action];
  Log([NSString stringWithFormat:@"secondary unverified diagnostic attempt (NOT the plan): CXAnswerCallAction %@ submitted from %@",uuid.UUIDString,display]);
  [Controller requestTransaction:tx completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
   if(error){NSString *meaning=CallKitErrorMeaning(error.domain,(NSInteger)error.code);Record(uuid,state,[NSString stringWithFormat:@"次要诊断路径失败：%@/%ld（%@）",error.domain,(long)error.code,meaning],@{@"failed":@YES});Log([NSString stringWithFormat:@"secondary CX answer transaction failed domain=%@ code=%ld detail=%@; 含义：%@",error.domain,(long)error.code,error.localizedDescription?:@"No description",meaning]);}
   else{state[@"accepted"]=@YES;Record(uuid,state,@"次要路径事务已接受；不代表连接",@{@"accepted":@YES});Log(@"secondary CX answer transaction accepted; this alone does not confirm connected, and on this device the primary runtime-discovered path is the one that matters");}
  });}];
 };
 AACSBStart(env);
 Log([NSString stringWithFormat:@"%@ discovery/ownership summary: %@",display,AACSBHostRoleText()]);
 Log(@"Initial observer snapshot processed with a fresh full delay from the observation instant, not from the real ringing start");
 for(CXCall *call in Observer.calls.copy){if(!call.hasEnded&&!call.hasConnected&&!call.outgoing){Log([NSString stringWithFormat:@"%@ snapshot incoming call scheduled from observation instant",display]);Changed(call);}}
}
%ctor {
 NSString *bundle=NSBundle.mainBundle.bundleIdentifier?:@"";
 NSString *process=NSProcessInfo.processInfo.processName?:@"";
 /* 1.12.0 injects into the four filter ids: com.apple.mobilephone, com.apple.springboard,
    com.apple.InCallService and com.apple.incallservice (the lowercase-only rule applies
    to the phone id; the two InCall spellings cover case differences, and duplicate or
    nonexistent ids are harmless). The wrong-case com.apple.MobilePhone is never written
    to the filter, only accepted here as a runtime compatibility fallback. */
 BOOL legacyPhone=[bundle isEqualToString:@"com.apple.mobilephone"]||[bundle isEqualToString:@"com.apple.MobilePhone"]||[process isEqualToString:@"MobilePhone"];
 BOOL inSpringBoardProcess=[bundle.lowercaseString isEqualToString:@"com.apple.springboard"]||[process isEqualToString:@"SpringBoard"];
 BOOL inInCallServiceProcess=[bundle.lowercaseString isEqualToString:@"com.apple.incallservice"]||[process isEqualToString:@"InCallService"];
 NSString *hostTag=AACAnswerHostTagForBundle(bundle,process);
 BOOL inPhoneProcess=[hostTag isEqualToString:@"mobilephone"]||legacyPhone;
 inSpringBoardProcess=inSpringBoardProcess||[hostTag isEqualToString:@"springboard"];
 inInCallServiceProcess=inInCallServiceProcess||[hostTag isEqualToString:@"incall"];
 /* Priority: InCallService > SpringBoard > phone module. */
 NSDictionary *answerHost=inInCallServiceProcess?AACAnswerHostByTag(@"incall"):(inSpringBoardProcess?AACAnswerHostByTag(@"springboard"):nil);
 BOOL inAnswerHostProcess=(answerHost!=nil);
 if(inAnswerHostProcess)ProcessTag=answerHost[@"tag"];
 else if(inPhoneProcess)ProcessTag=@"mobilephone";
 else ProcessTag=[@"other-" stringByAppendingString:(bundle.length?bundle:process)];
 NSLog(@"[AutoAnswerCall] dylib constructor reached; bundle=%@ process=%@ tag=%@ answerHost=%@",bundle,process,ProcessTag,inAnswerHostProcess?answerHost[@"tag"]:@"none");
 if(!inAnswerHostProcess&&!inPhoneProcess){
  /* The filter is supposed to scope injection to the four configured ids; anything else
     is reported as evidence instead of guessing which module should run. */
  AACSharedAppend(ProcessTag,@"unexpected process: no module logic runs; filter scoping may be wrong");
  return;
 }
 dispatch_async(dispatch_get_main_queue(),^{
  AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"Loaded 1.12.0 EVIDENCE build; bundle=%@ process=%@ tag=%@",bundle,process,ProcessTag]);
  AACProbeStart(ProcessTag);
  if(inAnswerHostProcess){
   AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"%@ answer host 1.12.0: runtime discovery + dynamic hook answer path shared with SpringBoard (names discovered at runtime, never hardcoded; observer-only when another host owns the answer; log-only when nothing is discovered)",answerHost[@"display"]]);
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AACRunInventory(ProcessTag);});
   AnswerHostStart(answerHost);
   return;
  }
  if(inPhoneProcess){
  Records=AACReadRecords(NULL,NULL);States=[NSMutableDictionary new];Controller=[CXCallController new];Observer=[CXCallObserver new];RetainedDelegate=[AACDelegate new];[Observer setDelegate:RetainedDelegate queue:dispatch_get_main_queue()];
  Log(@"Loaded 1.12.0 evidence build; retained CXCallObserver in MobilePhone; suspension/lockscreen delivery not guaranteed (this module is unchanged from 1.10.0)");
  int token=0;notify_register_dispatch("com.autoanswer.call.ping",&token,dispatch_get_main_queue(),^(int t){Log(@"Ping acknowledged in MobilePhone");NSDictionary *actual=Prefs();Log([NSString stringWithFormat:@"Configuration observed: keys=%lu enabledPresent=%d mode=%@ delay=%@ whitelistPresent=%d",(unsigned long)actual.count,actual[@"Enabled"]!=nil,actual[@"Mode"]?:@"missing",actual[@"Delay"]?:@"missing",actual[@"Whitelist"]!=nil]);notify_post("com.autoanswer.call.pong");});
  RegisterControls();
 /* MobilePhone keeps the 1.9.x registration order through RegisterControls(); on this device neither InCallService nor SpringBoard has ever been beaten to the answer by it. */
  /* A ringing call that predates this process has no observed start event. Scheduling a
     fresh full delay from the observation instant is the only defensible option; never
     assume the call began earlier. */
  Log(@"Initial observer snapshot processed with a fresh full delay from the observation instant, not from the real ringing start");
  for(CXCall *c in Observer.calls.copy){if(!c.hasEnded&&!c.hasConnected&&!c.outgoing){Log(@"Snapshot incoming call scheduled from observation instant");Changed(c);}}
  }
 });
}
