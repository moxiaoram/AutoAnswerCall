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
#import "AACChunkMsg.h"
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
/* 1.13.0/1.14.0: the answer host installs its own submit step (runtime-discovered UI answer path,
   now with a relaxed ABI gate and an NSInvocation fallback for argument-taking methods).
   Left nil in the phone module, which keeps the 1.9.x/1.10.0 CXAnswerCallAction
   transaction path byte-for-byte unchanged. */
static void (^SubmitBlock)(NSUUID *,NSMutableDictionary *);
/* Device evidence (1.11.0 call, re-confirmed by the 1.13.0 analysis): SpringBoard detected
   the call, ran the delay and the policy layer correctly, then reported "未发现可调用的 UI
   接听路径" and the public CXAnswerCallAction fallback failed with
   com.apple.CallKit.error.requesttransaction code 1.
   Apple's CXErrorCodeRequestTransactionError order is unknown(0), unentitled(1),
   unknownCallProvider(2), emptyTransaction(3), unknownCallUUID(4), callUUIDAlreadyExists(5),
   invalidAction(6), maximumCallGroupsReached(7) — so code 1 means UNENTITLED
   ("The app doesn't have the entitlement to perform the actions in the requested
   transaction"), NOT unknownCallUUID. The 1.12.0 table mapped this wrong and is corrected
   here.
   Apple documents requestTransaction as "Requests that the actions in the specified
   transaction be asynchronously performed by the telephony provider" and CXAnswerCallAction
   as performed by a CallKit provider, so this public path is not usable by a tweak process:
   it stays exactly ONE clearly labelled diagnostic attempt and is never the answering plan. */
static NSString *CallKitErrorMeaning(NSString *domain,NSInteger code){
 if([domain isEqualToString:@"com.apple.CallKit.error.requesttransaction"]){
  switch(code){
   case 0:return @"code 0 = unknown：CXErrorCodeRequestTransactionErrorUnknown，未分类错误";
   case 1:return @"code 1 = unentitled：本进程没有执行该事务所需的权利（Apple 文档：The app doesn't have the entitlement to perform the actions in the requested transaction）——实测结果；tweak 进程不是 CallKit 提供者，公开事务路径在本设备上无效";
   case 2:return @"code 2 = unknownCallProvider：找不到可执行该事务的通话提供者";
   case 3:return @"code 3 = emptyTransaction：事务为空";
   case 4:return @"code 4 = unknownCallUUID：事务中的通话 UUID 未知";
   case 5:return @"code 5 = callUUIDAlreadyExists：同一 UUID 已存在通话，事务被拒绝";
   case 6:return @"code 6 = invalidAction：事务中的 action 类型不被接受";
   case 7:return @"code 7 = maximumCallGroupsReached：通话组数量达到上限";
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
 /* 1.17.0 TASK 1: 按钮路径到底接通了吗——只有 CXCallObserver 的 hasConnected 才算证据。 */
 if(SubmitBlock&&[s[@"buttonTapped"] boolValue]){AACButtonNoteConnected(YES);AACSBButtonPublishNow();}
 Record(uuid,s,submitted?@"观察到连接；请求与人工/系统接听归因不明，已抑制自动播放":@"请求提交前已连接：手动/系统/其他，已取消自动接听和自动播放",@{@"connected":@YES,@"beforeRequest":@(!submitted)});
 Log(submitted?@"Connected after submission: answer ownership ambiguous; autoplay suppressed; imported files retained":@"Connected before submission (manual/system/other): UUID timers invalidated, autoplay suppressed; imported files retained");
 if(AACMayAutoplay(s))PlayLocal();
}
/* Subscribe to UUID-specific peer signals while THIS call is active. The old fixed
   buttontap.<host> notification could poison the next call; it is deliberately ignored. */
static void AACWatchPeerTaps(NSUUID *uuid,NSMutableDictionary *state){
 if(!SubmitBlock||!uuid||state[@"peerTapTokens"])return;
 NSMutableArray *tokens=[NSMutableArray new];
 state[@"peerTapTokens"]=tokens;
 for(NSString *peerTag in @[@"incall",@"springboard"]){
  if([peerTag isEqualToString:ProcessTag])continue;
  NSString *notification=AACButtonTapNameForCall(peerTag,uuid.UUIDString);
  if(!notification.length)continue;
  int token=0;
  uint32_t result=notify_register_dispatch(notification.UTF8String,&token,dispatch_get_main_queue(),^(int t){
   AACButtonNotePeerTap(peerTag,uuid.UUIDString);
   AACSBButtonPeerTapArrived(peerTag);
   Log([NSString stringWithFormat:@"UUID-specific peer tap observed: host=%@ uuid=%@",peerTag,uuid.UUIDString]);
  });
  if(result==NOTIFY_STATUS_OK)[tokens addObject:@(token)];
  else Log([NSString stringWithFormat:@"buttontap UUID observer registration failed host=%@ uuid=%@ result=%u",peerTag,uuid.UUIDString,result]);
 }
}
static void AACUnwatchPeerTaps(NSUUID *uuid,NSMutableDictionary *state){
 for(NSNumber *token in state[@"peerTapTokens"])notify_cancel(token.intValue);
 [state removeObjectForKey:@"peerTapTokens"];
 AACButtonForgetCall(uuid.UUIDString);
}
static void Changed(CXCall *call){
 NSUUID *uuid=call.UUID; if(!uuid)return; NSMutableDictionary *s=States[uuid];
 if(!s){s=[NSMutableDictionary dictionaryWithDictionary:@{@"scheduled":@NO,@"pending":@NO,@"attempted":@NO,@"accepted":@NO}];States[uuid]=s;}
 s[@"outgoing"]=@(call.outgoing);NSString *caller=Number(call);if(caller.length)s[@"caller"]=caller;
 if(!call.outgoing&&!call.hasEnded)AACWatchPeerTaps(uuid,s);
 Log([NSString stringWithFormat:@"Call %@ outgoing=%d connected=%d ended=%d",uuid.UUIDString,call.outgoing,call.hasConnected,call.hasEnded]);
 if(call.hasEnded){
  AACCancelForObservedConnection(s);
  if(!call.hasConnected)s[@"connectedObserved"]=@NO;
  NSString *endedStatus=call.hasConnected?@"通话已结束（观察到过连接，归因不明）":
    ([s[@"buttonTapped"] boolValue]?@"通话已结束：已发送按钮事件，但未观察到连接":
    ([s[@"submitted"] boolValue]?@"通话已结束：已尝试接听请求，但未观察到连接":
    ([s[@"attempted"] boolValue]?@"通话已结束：已进入尝试流程，但没有有效接听动作":@"通话已结束：未开始接听流程（检查配置与宿主日志）")));
  Record(uuid,s,endedStatus,(call.hasConnected?@{@"ended":@YES,@"connected":@YES}:@{@"ended":@YES,@"attempted":@([s[@"attempted"] boolValue])}));
  s[@"pending"]=@NO;s[@"attempted"]=@YES;
  if(SubmitBlock)AACSBButtonNoteCallEnded(call.hasConnected);
  AACUnwatchPeerTaps(uuid,s);
  [States removeObjectForKey:uuid];return;
 }
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
 /* 1.14.0 TASK 2: exactly one explicit ownership line per incoming call, at detection time. The
    same line is written again immediately before any submission (see PerformAnswer). */
 if(SubmitBlock)Log(AACSBAnswerOwnershipLine(uuid.UUIDString,NO,[NSString stringWithFormat:@"来电检测时的判定；本宿主延时=%.15g 秒，提交前会再判定一次",delay]));
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(generation!=StopGeneration){Log(@"Delayed answer cancelled by plugin stop generation");Record(uuid,s,@"取消：插件已停止",nil);return;}
  if(States[uuid]!=s){Log(@"Delayed answer dropped: call state no longer current");return;} s[@"scheduled"]=@NO; CXCall *live=Current(uuid);
  if(live.hasConnected){ObserveConnection(uuid,s);return;}
  if(!AACMaySubmit(s,callGeneration,live!=nil,live.hasConnected,live.hasEnded)){Log(@"Delayed answer invalidated by UUID connection/end generation or absent call");return;}
  if(!live||!Allowed(live,Prefs())){Log(@"Delayed answer cancelled: call absent/state or settings changed");Record(uuid,s,@"取消：通话消失、状态或设置已改变",nil);return;}
  s[@"attempted"]=@YES;s[@"pending"]=@YES;
  /* 1.17.0 TASK 1: 延迟到期、通话仍是来电状态，现在做一次现场按钮发现（有界遍历，记录每一个
     候选），这样按钮路径才是一条真实接听路径，而且归属判定发生在它之后。 */
  if(SubmitBlock)AACSBButtonProbeForIncomingCall(@"call");
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
/* Host-parameterised answer module (1.14.0; 1.13.0 relaxed the hook ABI gate; 1.14.0 fixes the
   ownership demotion bug — see the device evidence block in AACAnswerHost.h. the hook ABI and the per-method outcome
   reporting were relaxed and extended in this version).
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
 Log([NSString stringWithFormat:@"Loaded 1.17.1 answer host: %@ (tag=%@ probe=%@ pong=%@ discovery=%@); retained its own CXCallObserver in %@; runtime discovery of the real incoming-call UI starts now (ABI gate relaxed: zero-arg any-return -> MSHookMessageEx hook, arg-taking -> NSInvocation candidate)",display,tag,host[@"probe"],pong,host[@"discovery"],display]);
 Log([NSString stringWithFormat:@"接听归属角色表：%@；每个宿主都观察并记录，但只有一个宿主提交接听（InCallService 优先，其次 SpringBoard，否则仅日志）",AACAnswerRoleTableText()]);
 /* 1.16.0 TASK 1/TASK 2: the chunked Darwin message transport is started by AACSBStart (it owns
    the discovery summary text); this log line only states that it is part of every answer host. */
 Log([NSString stringWithFormat:@"分片消息通道（1.16.0）：%@",AACChunkMsgBoundText()]);
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
 /* UUID-specific buttontap registrations are managed per active call by AACWatchPeerTaps.
    The former fixed-name registration is intentionally removed to prevent stale peer events
    from suppressing a different call. */
 /* 1.17.0 TASK 1/TASK 2: 按钮路径是主策略。 */
 Log([NSString stringWithFormat:@"接听主策略（1.17.0）＝活体按钮发现＋模拟点击：%@；信号优先级 accessibilityIdentifier(%@) > accessibilityLabel(%@) > accessibilityValue(%@) > 标题(%@) > 本地化子串(%@) > 绿色左侧主按钮(%@)；黑名单作用于标识/标签/值/标题，红色主导控件一并列入，黑名单候选绝不点击",AACButtonRuleText(),AACButtonSignalText(AACButtonSignalAccessibilityIdentifier),AACButtonSignalText(AACButtonSignalAccessibilityLabel),AACButtonSignalText(AACButtonSignalAccessibilityValue),AACButtonSignalText(AACButtonSignalTitle),AACButtonSignalText(AACButtonSignalLocalization),AACButtonSignalText(AACButtonSignalGreenPrimary)]);
 int pingToken=0;uint32_t pingStatus=notify_register_dispatch("com.autoanswer.call.ping",&pingToken,dispatch_get_main_queue(),^(int t){Log([NSString stringWithFormat:@"Legacy Darwin ping observed in %@; answering on %@",display,pong]);uint32_t posted=notify_post(pong.UTF8String);if(posted!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"pong post failed status=%u",posted]);});
 if(pingStatus!=NOTIFY_STATUS_OK)Log([NSString stringWithFormat:@"%@ ping notification registration failed",display]);
 /* 1.14.0: the submission body is one block so that the bounded takeover path runs the
    EXACT same code (same per-UUID claim, same fail-closed re-read, same honest reporting)
    instead of a second, weaker copy. takeover=YES only when the observer branch decided to
    take over after an idle higher-priority owner. */
 void (^PerformAnswer)(NSUUID *,NSMutableDictionary *,BOOL) = ^(NSUUID *uuid,NSMutableDictionary *state,BOOL takeover){
  if(!AACSBClaimAnswerUUID(uuid.UUIDString)){
   Record(uuid,state,@"已拒绝重复提交：该通话 UUID 已由本宿主提交过接听",@{@"duplicate":@YES});
   Log([NSString stringWithFormat:@"duplicate answer submission refused for %@ (同一 UUID 只提交一次)",uuid.UUIDString]);
   Log(AACSBAnswerOwnershipLine(uuid.UUIDString,NO,@"重复提交被拒：同一 UUID 只提交一次"));
   return;
  }
  NSDictionary *recheck=Prefs();
  Log([NSString stringWithFormat:@"%@ re-verify before answering: settings re-read (fail-closed configValid=%d keys=%lu enabled=%@ mode=%@ delay=%@); %@; candidate classification: %@; the call itself was re-checked as still incoming/unanswered immediately before this step",display,ConfigValid,(unsigned long)recheck.count,recheck[@"Enabled"]?:@"missing",recheck[@"Mode"]?:@"missing",recheck[@"Delay"]?:@"missing",AACSBHostRoleText(),AACSBClassificationSummaryText()]);
  /* 1.14.0 TASK 2: the decision is logged again immediately before submitting. */
  Log(AACSBAnswerOwnershipLine(uuid.UUIDString,YES,takeover?@"提交前的判定（接管路径：takeover after idle higher-priority owner）":@"提交前的判定（常规 OWNER 路径，已通过同一 UUID 的单次提交判定）"));
  AACSBLogMethodOutcomes();
  /* 1.17.0 TASK 1: 方法名关键字路径（保留，但已知不足）作为回退，包在一个块里，这样按钮路径
     可以在结算窗口之后决定要不要退回、也不会复制第二份提交逻辑。 */
  void (^MethodPath)(void) = ^{
  NSString *source=nil;id target=AACSBAnswerTarget(&source);
  NSString *reason=nil;BOOL invoked=AACSBInvokeDiscovered(target,&reason);
  state[@"discoveredPath"]=@(invoked);
  if(invoked){
   state[@"submitted"]=@YES;
   Record(uuid,state,takeover?@"接管后已调用运行时发现的 UI 接听方法（尚未确认接通）":@"已调用运行时发现的 UI 接听方法（尚未确认接通）",@{@"submitted":@YES,@"discovered":@YES});
   Log([NSString stringWithFormat:@"discovered UI answer path invoked; host=%@ source=%@ takeover=%d; %@",display,source?:@"unknown",takeover,reason?:@""]);
   Log(@"this call is NOT yet confirmed: success is only reported when CXCallObserver reports hasConnected");
   return;
  }
  /* Primary path unavailable: stay honest, log-only, then make exactly ONE clearly
     labelled secondary attempt with the public transaction API. That API is proven
     ineffective for a third-party process on this device — Apple documents
     requestTransaction as asking the telephony provider to perform the actions, and
     CXAnswerCallAction as being performed by a CallKit provider, so a tweak process gets
     com.apple.CallKit.error.requesttransaction code 1 = unentitled (NOT unknownCallUUID).
     It is therefore a diagnostic and not the answering plan. */
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
  /* 1.17.0 TASK 1/TASK 2: 主策略＝活体按钮发现 + 模拟点击。候选已经在归属判定之前（延迟到期
     时）扫描并逐条记录；这里只决定「由谁真的点」：本宿主是唯一最高优先级时立刻点，否则先在
     结算窗口里等一等，看更高优先级宿主有没有真的点过（buttontap 通知）。绝不双重点击，且每个
     通话 UUID 每个宿主只点一次。 */
  NSArray *higherPriorityHosts=AACAnswerHostsHigherPriority(tag);
  NSMutableArray *higherPriorityTags=[NSMutableArray new];
  for(NSDictionary *peerHost in higherPriorityHosts){NSString *peerTag=peerHost[@"tag"];if([peerTag isKindOfClass:NSString.class]&&peerTag.length)[higherPriorityTags addObject:peerTag];}
  NSUInteger buttonLive=AACSBButtonLiveCandidates();
  if(buttonLive){
   NSTimeInterval settle=higherPriorityTags.count?AACButtonOwnerSettleSeconds:0.0;
   Log([NSString stringWithFormat:@"按钮路径（1.17.0 主策略）：延迟已到期，本宿主发现 %lu 个可点击的接听按钮候选；结算窗口 %.1f 秒（更高优先级宿主：%@）；点击只由一个宿主执行，绝不双重点击",(unsigned long)buttonLive,settle,higherPriorityTags]);
   NSUInteger buttonGeneration=StopGeneration;
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(settle*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    if(buttonGeneration!=StopGeneration){Log(@"button tap cancelled by plugin stop generation");return;}
    if(States[uuid]!=state){Log(@"button tap dropped: call state no longer current");return;}
    CXCall *liveCall=Current(uuid);
    if(!liveCall){Log(@"button tap dropped: the call UUID is no longer observed");return;}
    if(liveCall.hasConnected){Log(@"button tap not needed: a connection was already observed");return;}
    if(liveCall.hasEnded){Log(@"button tap dropped: the call already ended");return;}
    if(!Allowed(liveCall,Prefs())){
     Log(@"button tap cancelled: current preferences or exclusion rule no longer permits answering");
     Record(uuid,state,@"取消按钮尝试：设置或排除规则已变化",nil);return;
    }
    NSString *buttonWhy=nil;
    NSString *mechanism=AACButtonTryTap(uuid.UUIDString,tag,higherPriorityTags,&buttonWhy);
    if(mechanism){
     state[@"buttonTapped"]=@YES;state[@"buttonMechanism"]=mechanism;state[@"submitted"]=@YES;
     Record(uuid,state,@"已用活体按钮发现 + 模拟点击接听（尚未确认接通）",@{@"submitted":@YES,@"button":@YES});
     Log([NSString stringWithFormat:@"button path invoked; host=%@ mechanism=%@ detail=%@",display,mechanism,buttonWhy?:@""]);
     Log(@"this call is NOT yet confirmed: success is only reported when CXCallObserver reports hasConnected");
     AACSBButtonPublishNow();
     return;
    }
    Log([NSString stringWithFormat:@"button path unavailable at tap time: %@; 退回方法名关键字路径（保留，但已知不足）",buttonWhy?:@"无说明"]);
    MethodPath();
   });
   return;
  }
  Log(@"button path: 本次来电里没有发现任何可点击的接听按钮候选（候选、黑名单与节点数见发现文件的 BUTTON 候选分节），退回方法名关键字路径（保留，但已知不足）");
  MethodPath();
 };
 SubmitBlock=^(NSUUID *uuid,NSMutableDictionary *state){
  /* Single-owner gate, re-evaluated at answer time (not only at load).
     1.14.0: this gate now demotes ONLY on a fresh EXPLICIT higher-priority ownership claim.
     Peer PROBE presence can no longer take the answer away (device evidence: the 1.13.0 run
     demoted SpringBoard at 14:05:09 because InCallService's probe had arrived within 90 s, and
     the call was then answered by nobody). */
  NSString *ownership=nil;
  if(!AACSBShouldAnswer(&ownership)){
   state[@"observerOnly"]=@YES;
   Record(uuid,state,[NSString stringWithFormat:@"观察者：本宿主不提交接听（接听由 %@ 负责）",AACSBHostOwnerTagText()],@{@"observerOnly":@YES});
   if(AACSBHostIsLogOnly()){
    /* 1.15.0 TASK 2: never dress a pointlessly firing path up as a normal observer yield. A host
       with no ACTION method cannot answer, so it says so and the takeover below is skipped. */
    Log([NSString stringWithFormat:@"log-only: %@ 没有任何 ACTION 接听路径（1.15.0 起属性访问器 ACCESSOR 不计入 answerPaths），本次不提交、也不接管：%@",display,ownership?:@""]);
   }else{
    Log([NSString stringWithFormat:@"observer only, answer owned by %@; %@ 不提交接听，避免两个宿主对同一通话重复提交：%@",AACSBHostOwnerTagText(),display,ownership?:@""]);
   }
   Log(AACSBAnswerOwnershipLine(uuid.UUIDString,NO,@"观察者路径：本次不提交；探测量达到只能说明对方进程存在，绝不能作为让出接听的依据"));
   /* 1.14.0 BOUNDED SAFETY TAKEOVER. We yield only to an explicit claim, and a claim is not a
      submission. AACAnswerTakeoverIdleSeconds after our own delay expired we check once
      whether the claiming higher-priority host produced anything; if the call is still
      incoming/unconnected we may take over ONCE for this UUID. */
   if(AACSBHostIsLogOnly()){
    Log(@"no takeover scheduled: 本宿主是 LOG-ONLY（ACTION 接听路径=0，访问器不算）：接管也无法提交，因此不排定接管");
    return;
   }
   NSString *claimOwner=nil;NSString *claimReason=nil;
   if(!AACSBHigherPriorityOwnerClaimed(&claimOwner,&claimReason)){
    Log([NSString stringWithFormat:@"no takeover scheduled: %@",claimReason?:@"无说明"]);
    return;
   }
   Log([NSString stringWithFormat:@"takeover observation started: %@ 广播了明确归属声明（%@）；%@ 将在 %.0f 秒后（本宿主延时到期之后）检查它是否真的提交/接通，若没有则接管一次",claimOwner,claimReason,display,(double)AACAnswerTakeoverIdleSeconds]);
   NSUInteger takeoverGeneration=StopGeneration;
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(((double)AACAnswerTakeoverIdleSeconds)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    if(takeoverGeneration!=StopGeneration){Log(@"takeover cancelled by plugin stop generation");return;}
    if(States[uuid]!=state){Log(@"takeover dropped: call state no longer current");return;}
    CXCall *liveCall=Current(uuid);
    if(!liveCall){Log(@"takeover dropped: the call UUID is no longer observed");return;}
    if(liveCall.hasConnected){Log(@"takeover not needed: a connection was observed (the claiming owner or the user acted)");return;}
    if(liveCall.hasEnded){Log(@"takeover dropped: the call already ended");return;}
    NSString *takeoverReason=nil;
    if(!AACSBMayTakeOver(uuid.UUIDString,YES,&takeoverReason)){
     Log([NSString stringWithFormat:@"takeover refused: %@",takeoverReason?:@"条件不满足"]);
     Record(uuid,state,[NSString stringWithFormat:@"未接管：%@",takeoverReason?:@"条件不满足"],nil);
     return;
    }
    Log([NSString stringWithFormat:@"%@ 接管：%@",display,takeoverReason]);
    Log(AACSBAnswerOwnershipLine(uuid.UUIDString,NO,@"接管前：更高优先级宿主空闲未提交，本宿主将提交一次"));
    Record(uuid,state,@"接管：更高优先级宿主空闲未提交，本宿主对该 UUID 接管一次（每个 UUID 最多一次）",@{@"takeover":@YES});
    PerformAnswer(uuid,state,YES);
   });
   return;
  }
  PerformAnswer(uuid,state,NO);
 };
 AACSBStart(env);
 Log([NSString stringWithFormat:@"%@ discovery/ownership summary: %@",display,AACSBHostRoleText()]);
 Log(@"Initial observer snapshot processed with a fresh full delay from the observation instant, not from the real ringing start");
 for(CXCall *call in Observer.calls.copy){if(!call.hasEnded&&!call.hasConnected&&!call.outgoing){Log([NSString stringWithFormat:@"%@ snapshot incoming call scheduled from observation instant",display]);Changed(call);}}
}
%ctor {
 NSString *bundle=NSBundle.mainBundle.bundleIdentifier?:@"";
 NSString *process=NSProcessInfo.processInfo.processName?:@"";
 /* 1.13.0 injects into the four filter ids: com.apple.mobilephone, com.apple.springboard,
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
  AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"Loaded 1.17.1 EVIDENCE build; bundle=%@ process=%@ tag=%@",bundle,process,ProcessTag]);
  AACProbeStart(ProcessTag);
  if(inAnswerHostProcess){
   AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"%@ answer host 1.17.0: runtime discovery + MSHookMessageEx hook + NSInvocation candidate answer path shared with SpringBoard (names discovered at runtime, never hardcoded; only ACTION methods count as answer paths, property ACCESSORS are evidence only; log-only when no ACTION path exists; every candidate method, its ACTION/ACCESSOR/FORBIDDEN/UNSUPPORTED classification and its outcome are written to the discovery file and published through the shared host-report domain)",answerHost[@"display"]]);
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AACRunInventory(ProcessTag);});
   AnswerHostStart(answerHost);
   return;
  }
  if(inPhoneProcess){
  Records=AACReadRecords(NULL,NULL);States=[NSMutableDictionary new];Controller=[CXCallController new];Observer=[CXCallObserver new];RetainedDelegate=[AACDelegate new];[Observer setDelegate:RetainedDelegate queue:dispatch_get_main_queue()];
  Log(@"Loaded 1.17.1 evidence build; retained CXCallObserver in MobilePhone; suspension/lockscreen delivery not guaranteed (this module is unchanged from 1.10.0)");
  /* 1.16.0 TASK 1: 电话模块也通过分片消息通道上报自己的真实读数（结论仍是 1.10.0 行为不变）。 */
  AACChunkMsgStart(@"mobilephone",^NSString *{
   NSDictionary *actual=Prefs();
   return [NSString stringWithFormat:@"host=MobilePhone tag=mobilephone pid=%d keys=%lu enabledPresent=%d mode=%@ delay=%@ whitelistPresent=%d；本模块保留 1.9.x/1.10.0 的 CXCallObserver 策略层行为不变；该摘要只说明本进程正在按既有流程运行，不证明接听可用",(int)getpid(),(unsigned long)actual.count,actual[@"Enabled"]!=nil,actual[@"Mode"]?:@"missing",actual[@"Delay"]?:@"missing",actual[@"Whitelist"]!=nil];
  });
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
