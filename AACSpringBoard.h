#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "AACSharedLog.h"
#import "AACAnswerHost.h"
/* Host-parameterised answer module (1.14.0; 1.13.0 relaxed the hook ABI gate, 1.12.0 shipped
   the host table, 1.11.0 shipped this file SpringBoard-only). The SAME machinery runs in whichever host process the caller
   names through AACSBEnv.host: probe/pong Darwin names, discovery file name and the
   ownership role all come from the host table in AACAnswerHost.h. Refactor basis: runtime
   discovery + dynamic hook + capture.

   1.13.0 HOOK ABI RELAXATION (device evidence that drove it):
   1.12.0 hooked ONLY methods whose runtime signature was exactly (self,_cmd) with a void
   return, because its replacement was a fixed-signature C function. On the iOS 17.3
   RootHide device that gate rejected every candidate: SpringBoard announced itself, detected
   a real call, ran the delay and the policy layer, and then reported "未发现可调用的 UI 接听
   路径（仅日志）", while nothing at all was HOOKED. The real answer entry very likely takes an
   argument (a sender, a button, a completion block) and/or returns BOOL, so the gate itself
   was the most likely reason nothing was ever hooked. 1.13.0 replaces the gate with a graded
   strategy and records the outcome OF EVERY CANDIDATE METHOD so the next device test is
   conclusive:
     - HOOKED: zero explicit arguments and a return type that a fixed C thunk can forward
       correctly (void / BOOL / object / integer / floating point). Installed through
       MSHookMessageEx (ElleKit / substrate compat, resolved with dlsym so the tweak does not
       hard-link a private header) and, when that symbol is absent in this process, through
       method_setImplementation with the same saved original IMP. The thunk forwards to the
       saved original with the type-appropriate signature and never changes behaviour.
     - INVOKABLE_BY_INVOCATION: methods with explicit arguments are NOT hooked — a C
       replacement cannot rebuild an arbitrary ABI's arguments, and blindly forwarding them is
       exactly the bug class this version removes. They are registered as candidates instead:
       the answer step locates a live instance of that class through the bounded window /
       view-controller / responder scan and calls the method with NSInvocation built from the
       runtime signature, passing nil / 0 default arguments (bounded: at most 3 explicit
       arguments, only argument types whose default value can be constructed safely, never a
       decline/reject/hang-up selector). This is a best-effort path and is labelled as such.
     - CAPTURED: a live instance of a candidate class was seen by a hook or by the scan.
     - INVOKED_BY_INVOCATION: the answer step really used path 2 on a live instance.
     - SKIPPED: rejected with the concrete reason (unsupported return type for a thunk,
       unsafe/too many arguments, forbidden selector, already hooked, hook cap/class cap,
       duplicate IMP).

   Nothing in this header hardcodes a private class name: the module enumerates the real objc
   runtime with objc_getClassList + class_copyMethodList and never guesses. If nothing is
   discovered, or no candidate can be forwarded or invoked, or no live object can be located,
   the module degrades to LOG-ONLY and says so explicitly: it never reports an answer that was
   not performed, and never claims connected without an observed CXCall.hasConnected. */

enum { AACSBHookCap=24, AACSBClassCap=400, AACSBSelectorCap=12, AACSBScanNodeCap=4000, AACSBScanDepthCap=30, AACSBResponderUpCap=12, AACSBInvocationCap=12, AACSBGlobalClassCap=600 };
static NSTimeInterval const AACSBStrongHoldSeconds=180.0;
static NSUInteger const AACSBMaxDiscoverRuns=3;

@interface AACSBEnv : NSObject
/* The host descriptor from AACAnswerHost.h. Every name this module uses (process tag,
   probe/pong name, discovery file name, priority, answer capability) comes from here, so the
   module body is identical in InCallService and in SpringBoard. */
@property(nonatomic,copy) NSDictionary *host;
/* Legacy field kept for 1.11.0 compatibility; used only when host is nil. */
@property(nonatomic,copy) NSString *process;
@property(nonatomic,copy) NSDictionary *(^prefs)(void);
@property(nonatomic,copy) BOOL (^allowed)(CXCall *call);
@property(nonatomic,copy) void (^log)(NSString *message);
@property(nonatomic,copy) void (^record)(NSString *status,NSDictionary *flags);
@end
@implementation AACSBEnv @end

typedef struct { Class cls; SEL sel; IMP original; BOOL countsAsPath; } AACSBHookRecord;
typedef struct { Class cls; SEL sel; BOOL countsAsPath; } AACSBInvocationRecord;
static AACSBEnv *AACSBEnvShared=nil;
static AACSBHookRecord AACSBHookRecords[AACSBHookCap];
static NSUInteger AACSBHookCount=0;
/* Candidate methods that take explicit arguments: not hooked, invoked with NSInvocation. */
static AACSBInvocationRecord AACSBInvocationRecords[AACSBInvocationCap];
static NSUInteger AACSBInvocationCount=0;
static NSMutableSet *AACSBHookedKeys=nil;
static NSMutableSet *AACSBHookedIMPs=nil;
static NSMutableSet *AACSBInvocationKeys=nil;
static NSMutableArray *AACSBDiscoveryLines=nil;
static NSMutableArray *AACSBHookedSelectors=nil;
static NSMutableArray *AACSBInvokableSelectors=nil;
/* One detail string per hook record, index-aligned with AACSBHookRecords. */
static NSMutableArray *AACSBHookDetails=nil;
/* 1.15.0 TASK 2 counters. An ACCESSOR may still be hooked (behaviour-neutral capture of a live
   instance) but it may NEVER count as an answer path and may never be the object the answer
   step acts on. These two counters exist so the log can state that distinction explicitly
   instead of silently folding accessors into the answer-path count (which is what made the
   1.14.0 device run report role=OWNER with four pure accessors). */
static NSUInteger AACSBHookActionCount=0,AACSBHookAccessorCount=0,AACSBInvokableActionCount=0;
static NSUInteger AACSBAccessorSkipped=0,AACSBUnsupportedSkipped=0;
static NSUInteger AACSBMatchedClasses=0,AACSBRejectedMethods=0,AACSBDiscoverRuns=0,AACSBInvokableSkipped=0,AACSBInvokedByInvocation=0,AACSBGlobalScanned=0,AACSBRescanVisits=0;
static __weak id AACSBWeakTarget=nil;
static id AACSBStrongTarget=nil;
static SEL AACSBInvokeSelector=NULL;
static volatile int32_t AACSBDepth=0;
static volatile int32_t AACSBInvoking=0;
/* 1.12.0 single-owner arbitration state. AACSBAnswerRole mirrors AACAnswerRole; the module
   is the only place in this process that may submit an answer. */
static AACAnswerRole AACSBRole=AACAnswerRoleLogOnly;
static NSString *AACSBHostTag=nil;
static NSString *AACSBHostDisplay=nil;
static NSString *AACSBOwnerTag=nil;
static NSString *AACSBRoleReason=nil;
static NSMutableSet *AACSBSubmittedUUIDs=nil;

/* Forward declarations: the ownership helpers below are defined above these two. */
static void AACSBLog(NSString *message);
static void AACSBRecord(NSString *status,NSDictionary *flags);
static void AACSBAppendDiscovery(NSString *line);
static void AACSBCapture(id object,SEL selector);
/* Defined together with the 1.15.0 ACTION/ACCESSOR classifier further down; declared here
   because the class filters already use the same '*' wildcard matcher. */
static BOOL AACSBWildcardMatch(NSString *text,NSString *pattern);

static NSDictionary *AACSBHost(void){
 NSDictionary *host=AACSBEnvShared.host;
 if([host isKindOfClass:NSDictionary.class]&&host[@"tag"])return host;
 return AACAnswerHostByTag(@"springboard");
}
/* Process tag drives probe name (com.autoanswer.call.probe.<tag>) and the discovery file
   (aac-<tag>.discovery.txt) through the shared-log leaf naming. */
static NSString *AACSBProcess(void){
 NSDictionary *host=AACSBHost();NSString *tag=host[@"tag"];
 if([tag isKindOfClass:NSString.class]&&tag.length)return tag;
 return AACSBEnvShared.process.length?AACSBEnvShared.process:@"springboard";
}
static NSString *AACSBDisplay(void){
 NSDictionary *host=AACSBHost();NSString *name=host[@"display"];
 return [name isKindOfClass:NSString.class]&&name.length?name:AACSBProcess();
}
static NSString *AACSBHostDiscoveryFile(void){
 NSString *name=AACAnswerHostDiscoveryName(AACSBHost()[@"tag"]);
 return name?:@"aac-springboard.discovery.txt";
}
/* Number of ANSWER PATHS this host really holds. 1.15.0 TASK 2: ONLY ACTION methods count.
   A hooked ACCESSOR (property getter/setter, see AACSBClassifySelector) can never answer a
   call, so counting it was a false positive: the device run reported role=OWNER from four pure
   accessors (answeredCall / hasAnsweredCall / answeredCall / acceptButton) that cannot answer
   anything. Accessor hooks are still installed for evidence/capture, but they are excluded
   here, they are never registered as NSInvocation candidates, and they are never the object
   the answer step acts on (AACSBOriginalForAnswer / AACSBMatchedAnswerClass below). */
static NSUInteger AACSBAnswerPathCount(void){
 NSUInteger count=0;
 for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].countsAsPath)count++;
 for(NSUInteger i=0;i<AACSBInvocationCount;i++)if(AACSBInvocationRecords[i].countsAsPath)count++;
 return count;
}
/* Answer-path-only IMP lookup: the answer step may never act through an accessor hook. */
static IMP AACSBOriginalForAnswer(id object,SEL selector){
 if(!object||!selector)return NULL;
 Class cls=object_getClass(object);
 @try{
  while(cls){
   for(NSUInteger i=0;i<AACSBHookCount;i++)
    if(AACSBHookRecords[i].countsAsPath&&AACSBHookRecords[i].cls==cls&&AACSBHookRecords[i].sel==selector)return AACSBHookRecords[i].original;
   cls=class_getSuperclass(cls);
  }
 }@catch(NSException *e){}
 return NULL;
}
static BOOL AACSBSelectorIsAnswerPath(Class cls,SEL selector){
 if(!cls||!selector)return NO;
 @try{
  Class walk=cls;
  while(walk){
   for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].countsAsPath&&AACSBHookRecords[i].cls==walk&&AACSBHookRecords[i].sel==selector)return YES;
   for(NSUInteger i=0;i<AACSBInvocationCount;i++)if(AACSBInvocationRecords[i].countsAsPath&&AACSBInvocationRecords[i].cls==walk&&AACSBInvocationRecords[i].sel==selector)return YES;
   walk=class_getSuperclass(walk);
  }
 }@catch(NSException *e){}
 return NO;
}
/* Re-evaluates the single-owner role from the role table plus observed host presence.
   1.14.0: AACAnswerHostRoleForTag takes the number of answer paths this host really holds and
   demotes ONLY on a fresh explicit higher-priority ownership claim (see the device evidence at
   the top of AACAnswerHost.h). A probe from the peer can no longer demote us. */
static void AACSBRecomputeRole(void){
 NSString *reason=nil;NSString *owner=nil;
 AACAnswerRole role=AACAnswerHostRoleForTag(AACSBHost()[@"tag"],AACSBAnswerPathCount(),&reason,&owner);
 BOOL changed=(role!=AACSBRole)||![owner isEqualToString:AACSBOwnerTag?:@""];
 AACSBRole=role;AACSBHostTag=AACSBHost()[@"tag"];AACSBHostDisplay=AACSBDisplay();AACSBOwnerTag=owner;AACSBRoleReason=reason;
 if(!changed)return;
 NSString *line=[NSString stringWithFormat:@"%@ 接听归属角色：%@（%@）",AACSBDisplay(),role==AACAnswerRoleOwner?@"OWNER 本宿主负责接听":(role==AACAnswerRoleObserver?@"OBSERVER 仅观察与记录":@"LOG-ONLY 仅日志"),reason?:@"无说明"];
 dispatch_async(dispatch_get_main_queue(),^{
  AACSBLog(line);
  if(role==AACAnswerRoleOwner)AACSBRecord(@"接听归属：本宿主负责执行接听（单一负责宿主规则）",@{@"owner":@YES});
  else AACSBRecord(owner?[NSString stringWithFormat:@"观察者：接听由 %@ 负责，本宿主不提交接听",owner]:@"仅日志：本宿主不提交接听",@{@"owner":@NO});
 });
 if(role!=AACAnswerRoleOwner&&owner.length){
  dispatch_async(dispatch_get_main_queue(),^{
   AACSBLog([NSString stringWithFormat:@"observer only, answer owned by %@（本宿主不会为该通话提交接听；绝不出现两个宿主同时提交）",owner]);
  });
 }
}
/* A higher-priority host's probe/claim just arrived: refresh observed liveness/claim state and
   re-run the role rule. 1.14.0: a PROBE arrival can no longer change the role (a probe is
   presence only); only a claim arrival can, because AACAnswerHostRoleForTag consults
   AACAnswerPeerClaimReason exclusively. The call is still kept because the presence line goes
   into the recorded reason and because an already-loaded lower-priority host must re-check when
   a real claim shows up later. */
static void AACSBHostProbeArrived(NSString *tag){
 if(![tag isKindOfClass:NSString.class]||!tag.length)return;
 AACAnswerHostSeenProbe(tag);
 if([tag isEqualToString:AACSBProcess()])return;
 if(![AACSBHost()[@"answer"] boolValue])return;
 AACSBRecomputeRole();
}
/* Answer-time gate: only the owner may submit, and only once per call UUID. */
static BOOL AACSBShouldAnswer(NSString **reason){
 AACSBRecomputeRole();
 if(AACSBRole!=AACAnswerRoleOwner){
  if(reason)*reason=AACSBHostTag.length?[NSString stringWithFormat:@"%@ 不是接听负责宿主（%@）：%@",AACSBHostDisplay,AACAnswerRoleTableText(),AACSBRoleReason?:@"无说明"]:@"本进程不在宿主表内，不接听";
  return NO;
 }
 if(reason)*reason=[NSString stringWithFormat:@"%@ 是接听负责宿主：%@",AACSBHostDisplay,AACSBRoleReason?:@""];
 return YES;
}
/* Role text used by Tweak.x logs/records: host, role and (when observer) the owner. */
static NSString *AACSBHostRoleText(void){
 return [NSString stringWithFormat:@"host=%@ role=%@ owner=%@",AACSBDisplay(),AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY"),AACSBOwnerTag?:@"(none)"];
}
static NSString *AACSBHostOwnerTagText(void){return AACSBOwnerTag.length?AACSBOwnerTag:@"(none)";}
/* 1.15.0: a LOG-ONLY host has no ACTION answer path at all; such a host never submits and the
   takeover path refuses immediately instead of scheduling a pointless bounded wait. */
static BOOL AACSBHostIsLogOnly(void){return AACSBRole==AACAnswerRoleLogOnly;}
/* 1.14.0: the durable reason string of the current decision, always loggable. */
static NSString *AACSBClaimReasonText(void){return AACSBRoleReason.length?AACSBRoleReason:@"无说明（角色尚未判定）";}
/* 1.15.0 TASK 1: what this host publishes through the shared host-report CFPreferences domain,
   and the publication call itself. The summary is bounded by AACHostReportSummaryBytes and the
   recent log lines by AACHostReportLogBytes inside AACSharedLog.h, so one host can never flood
   the domain. Publishing is best effort and its result is always reported as the REAL
   CFPreferences status, never as an assumption that another process can read it. */
static NSString *AACSBClassificationSummaryText(void){
 return [NSString stringWithFormat:@"%lu 个 ACTION（其中已挂钩 %lu、NSInvocation 候选 %lu），%lu 个 ACCESSOR 挂钩（仅证据），ACCESSOR 跳过 %lu，UNSUPPORTED 跳过 %lu",(unsigned long)(AACSBHookActionCount+AACSBInvokableActionCount),(unsigned long)AACSBHookActionCount,(unsigned long)AACSBInvokableActionCount,(unsigned long)AACSBHookAccessorCount,(unsigned long)AACSBAccessorSkipped,(unsigned long)AACSBUnsupportedSkipped];
}
static NSString *AACSBHostReportSummary(void){
 return [NSString stringWithFormat:@"host=%@ tag=%@ pid=%d role=%@ owner=%@ answerPaths=%lu；分类：%@；候选类=%lu 跳过=%lu discoverRuns=%lu；判定原因：%@",AACSBDisplay(),AACSBProcess(),(int)getpid(),(AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY")),AACSBHostOwnerTagText(),(unsigned long)AACSBAnswerPathCount(),AACSBClassificationSummaryText(),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBRejectedMethods,(unsigned long)AACSBDiscoverRuns,AACSBClaimReasonText()];
}
static NSDictionary *AACSBHostReportPublishNow(void){
 NSDictionary *facts=@{@"role":AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY"),
                       @"display":AACSBDisplay(),
                       @"hostTag":AACSBProcess(),
                       @"answerPaths":[NSString stringWithFormat:@"%lu",(unsigned long)AACSBAnswerPathCount()],
                       @"actionMethods":[NSString stringWithFormat:@"%lu",(unsigned long)(AACSBHookActionCount+AACSBInvokableActionCount)],
                       @"accessorMethods":[NSString stringWithFormat:@"%lu",(unsigned long)AACSBHookAccessorCount],
                       @"classification":AACSBClassificationSummaryText()};
 return AACHostReportPublish(AACSBProcess(),AACSBHostReportSummary(),facts);
}
/* 1.14.0 TASK 2: one explicit line per incoming call saying which host owns the answer, WHY,
   and whether a submission happened. The role is recomputed first, so the line is the
   discovery-time decision and (called again immediately before submitting) the submit-time
   decision. */
static NSString *AACSBAnswerOwnershipLine(NSString *uuid,BOOL submitted,NSString *detail){
 AACSBRecomputeRole();
 return [NSString stringWithFormat:@"接听归属判定 call=%@ owner=%@ role=%@ host=%@ answerPaths=%lu classification=[%@] why=%@ submitted=%@%@",uuid.length?uuid:@"(unknown)",AACSBHostOwnerTagText(),AACSBHostRoleText(),AACSBDisplay(),(unsigned long)AACSBAnswerPathCount(),AACSBClassificationSummaryText(),AACSBClaimReasonText(),submitted?@"yes":@"no",detail.length?[NSString stringWithFormat:@"；%@",detail]:@""];
}
/* 1.14.0 bounded safety takeover state. One takeover per call UUID, and the takeover
   submission still has to pass AACSBClaimAnswerUUID, so this host can never submit the same
   UUID twice even if the role is recomputed mid-call. */
static NSMutableSet *AACSBTakeoverUUIDs=nil;
static BOOL AACSBClaimTakeoverUUID(NSString *uuid){
 if(![uuid isKindOfClass:NSString.class]||!uuid.length)return NO;
 if(!AACSBTakeoverUUIDs)AACSBTakeoverUUIDs=[NSMutableSet new];
 @try{
  if([AACSBTakeoverUUIDs containsObject:uuid])return NO;
  [AACSBTakeoverUUIDs addObject:uuid];
 }@catch(NSException *e){return NO;}
 return YES;
}
static BOOL AACSBHasTakenOverUUID(NSString *uuid){return [uuid isKindOfClass:NSString.class]&&uuid.length&&AACSBTakeoverUUIDs&&[AACSBTakeoverUUIDs containsObject:uuid];}
/* Is a strictly higher-priority answer host asserting ownership right now (a real claim)? */
static BOOL AACSBHigherPriorityOwnerClaimed(NSString **ownerTag,NSString **reason){
 return AACAnswerHigherPriorityOwnerClaimed(AACSBHost()[@"tag"],ownerTag,reason);
}
/* The takeover gate. peerIdle==YES means Tweak.x really checked, AACAnswerTakeoverIdleSeconds
   after our own delay expired, that the call is still incoming/unconnected (so the claiming
   higher-priority owner has produced no submission evidence). Only then, and only once per
   UUID, may a host that holds answer paths take over. */
static BOOL AACSBMayTakeOver(NSString *uuid,BOOL peerIdle,NSString **reason){
 if(![AACSBHost()[@"answer"] boolValue]){if(reason)*reason=@"本宿主不是接听宿主：不可能接管";return NO;}
 if(AACSBAnswerPathCount()==0){if(reason)*reason=@"本宿主没有可用的接听路径（HOOKED/INVOKABLE 都是 0）：接管了也无法提交";return NO;}
 NSString *ownerTag=nil;NSString *claimReason=nil;
 if(!AACSBHigherPriorityOwnerClaimed(&ownerTag,&claimReason)){if(reason)*reason=claimReason;return NO;}
 if(!peerIdle){if(reason)*reason=[NSString stringWithFormat:@"更高优先级宿主 %@ 的归属声明仍在生效，且已观察到连接/状态变化：无需接管",ownerTag];return NO;}
 if(AACSBHasTakenOverUUID(uuid)){if(reason)*reason=[NSString stringWithFormat:@"该通话 UUID（%@）已经行使过接管权：每个 UUID 最多接管一次",uuid?:@"(unknown)"];return NO;}
 if(![AACSBHost()[@"tag"] isKindOfClass:NSString.class]){if(reason)*reason=@"宿主 tag 不可用：不接管";return NO;}
 if(!AACSBClaimTakeoverUUID(uuid)){if(reason)*reason=[NSString stringWithFormat:@"该通话 UUID（%@）已经行使过接管权：每个 UUID 最多接管一次",uuid?:@"(unknown)"];return NO;}
 if(reason)*reason=AACAnswerTakeoverReasonText(ownerTag,claimReason);
 return YES;
}
static BOOL AACSBClaimAnswerUUID(NSString *uuid){
 if(![uuid isKindOfClass:NSString.class]||!uuid.length)return NO;
 if(!AACSBSubmittedUUIDs)AACSBSubmittedUUIDs=[NSMutableSet new];
 @try{
  if([AACSBSubmittedUUIDs containsObject:uuid])return NO;
  [AACSBSubmittedUUIDs addObject:uuid];
 }@catch(NSException *e){return NO;}
 return YES;
}
static void AACSBLog(NSString *message){
 if(![message isKindOfClass:NSString.class])return;
 if(AACSBEnvShared.log){AACSBEnvShared.log(message);return;}
 AACSharedAppend(AACSBProcess(),message);
}
static void AACSBRecord(NSString *status,NSDictionary *flags){
 if(AACSBEnvShared.record)AACSBEnvShared.record(status,flags);
}
/* Class-name candidates. 1.13.0 keeps every 1.11.0/1.12.0 keyword and adds the modern
   phone-call UI families that the iOS 17 evidence suggests exist, so the keyword pass is not
   the only thing standing between the module and the real answer entry. */
static NSArray *AACSBClassKeywords(void){
 return @[@"IncomingCall",@"CallAlert",@"CallToAction",@"CallPresentation",@"InCall",@"SBInCall",@"LockScreenCall",@"AnswerCall",@"CallController",@"CallUI",
          @"PhoneCall",@"CallBanner",@"CallNotification",@"CallDisplay",@"CallViewController",@"CallButton",@"CallAction",@"CallWindow",@"InCallUI",@"HUDCall",@"SBCall",@"ICSInCall",@"ICSAnswer",
          @"TPInComingCall",@"PHInCall"];
}
/* 1.15.0 TASK 2: real in-call UI CLASS FAMILIES (the evidence shows the live incoming-call UI
   is NOT the TPInComingCallUISnapshotViewController snapshot, so the families below are added
   as first-class candidates next to the substring keywords). These are wildcard patterns, not
   guessed concrete class names: the module still asks the objc runtime what exists. */
static NSArray *AACSBClassFamilyPatterns(void){
 return @[@"TPInComingCallUI*",@"PHInCallUI*",@"ICSInCall*",@"CallBanner*",@"CallViewController*",@"InCall*ViewController"];
}
static BOOL AACSBClassNameMatchesFamily(NSString *name){
 if(!name.length||[name hasPrefix:@"AAC"])return NO;
 for(NSString *pattern in AACSBClassFamilyPatterns())if(AACSBWildcardMatch(name,pattern))return YES;
 return NO;
}
/* Answer-ish selectors. "answer" stays the primary keyword; the additions cover button
   handlers and the "pick up" wording without ever matching a decline/hang-up action. */
static NSArray *AACSBSelectorKeywords(void){return @[@"answer",@"accept",@"pickup",@"pick up",@"answerbutton",@"didtapanswer",@"answercall",@"answering"];}
/* Strict subset used by the global pass, where a class name only has to contain "call": the
   bare "accept" keyword is dropped there because framework methods such as
   -[NSXPCConnection acceptInputForMode:beforeDate:] are unrelated and must not become
   candidates of a tweak that answers phone calls. */
static NSArray *AACSBSelectorKeywordsStrict(void){return @[@"answer",@"pickup",@"pick up",@"answerbutton",@"didtapanswer",@"answercall",@"answering"];}
/* Hard safety blacklist: a selector that can decline/reject/hang up a call is never hooked,
   never registered and never invoked, whatever else it matches. */
static NSArray *AACSBSelectorForbidden(void){return @[@"decline",@"reject",@"hangup",@"hang up",@"hang-up",@"endcall",@"end call",@"disconnect",@"cancel",@"ignore",@"dismiss",@"sendtovoicemail"];}
static BOOL AACSBClassMatches(NSString *name){
 if(!name.length||[name hasPrefix:@"AAC"])return NO;
 for(NSString *keyword in AACSBClassKeywords())if([name rangeOfString:keyword].location!=NSNotFound)return YES;
 if(AACSBClassNameMatchesFamily(name))return YES;
 if([name hasPrefix:@"SBLockScreen"]){NSString *lower=name.lowercaseString;if([lower rangeOfString:@"call"].location!=NSNotFound||[lower rangeOfString:@"answer"].location!=NSNotFound)return YES;}
 return NO;
}
/* Global pass: any runtime class whose NAME contains "call" (case-insensitive) or matches one
   of the real in-call UI families, which is a far larger candidate set than the keyword list
   while still excluding unrelated classes. */
static BOOL AACSBClassMatchesGlobal(NSString *name){
 if(!name.length||[name hasPrefix:@"AAC"])return NO;
 if(AACSBClassNameMatchesFamily(name))return YES;
 return [name.lowercaseString rangeOfString:@"call"].location!=NSNotFound;
}
static NSString *AACSBForbiddenKeyword(NSString *selector){
 NSString *lower=selector.lowercaseString;
 for(NSString *keyword in AACSBSelectorForbidden())if([lower rangeOfString:keyword].location!=NSNotFound)return keyword;
 return nil;
}
/* ARC method families: for -init/-new/-copy/-mutableCopy/-alloc-like selectors the CALLER
   assumes a +1 (owned) return value, so an ARC-compiled thunk that returns the original's
   object as an autoreleased (+0) value would over-release it. Those selectors are therefore
   never hooked, never registered and never invoked. The family rule follows the documented
   ARC rule: the first selector component, prefix match, and the next character must not be a
   lowercase ASCII letter ("initialize"/"copying" are not in a family). */
static BOOL AACSBSelectorFamilyPrefix(NSString *first,NSString *family){
 if(![first hasPrefix:family])return NO;
 if(first.length==family.length)return YES;
 unichar c=[first characterAtIndex:family.length];
 return !(c>='a'&&c<='z');
}
static BOOL AACSBSelectorIsARCUnsafe(NSString *selector){
 NSRange colon=[selector rangeOfString:@":"];
 NSString *first=colon.location==NSNotFound?selector:[selector substringToIndex:colon.location];
 for(NSString *family in @[@"alloc",@"new",@"copy",@"mutableCopy",@"init"])if(AACSBSelectorFamilyPrefix(first,family))return YES;
 return NO;
}
static BOOL AACSBSelectorMatches(NSString *selector,BOOL strict){
 NSString *lower=selector.lowercaseString;
 if(AACSBForbiddenKeyword(selector))return NO;
 for(NSString *keyword in (strict?AACSBSelectorKeywordsStrict():AACSBSelectorKeywords()))if([lower rangeOfString:keyword].location!=NSNotFound)return YES;
 return NO;
}

/* ================= 1.15.0 TASK 2: ACTION vs ACCESSOR/NO-OP CLASSIFICATION =================
   WHAT WENT WRONG: the 1.14.0 device run (user's real SpringBoard shared log, 2026-10-16,
   14:19:05) reported "matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER".
   All four HOOKED methods were pure property ACCESSORS, i.e. they cannot answer anything:
     -[INAnswerCallIntentResponse answeredCall]                                   (0args+object)
     -[_INPBAnswerCallIntentResponse hasAnsweredCall]                             (0args+BOOL)
     -[_INPBAnswerCallIntentResponse answeredCall]                                (0args+object)
     -[TPInComingCallUISnapshotViewController acceptButton]                       (0args+object)
   and all five INVOKABLE candidates were setters/unrelated:
     -[CXCallControllerHost listener:shouldAcceptNewConnection:]
     -[INAnswerCallIntentResponse setAnsweredCall:]
     -[_INPBAnswerCallIntentResponse setAnsweredCall:]
     -[TUCallNotificationManager answeringMachineStreamTokenChangedForCall:]
     -[TPInComingCallUISnapshotViewController setAcceptButton:]
   Counting those as "answer paths" is what made role=OWNER false. So from 1.15.0 every
   candidate method carries exactly one classification, it is logged per method, and ONLY
   ACTION may set the answer-path count or be reached by the submission path:
     ACTION       the selector really names an answer action (see AACSBSelectorActionPatterns);
                  only ACTION methods may be hooked-as-answer / registered as invocable and
                  therefore only they can set answerPaths>0.
     ACCESSOR     a property accessor: a setter of the form set<Name>:, or a getter of the form
                  has<Name> / is<Name> / <name> that mirrors an existing setter on the same
                  class (plus the five concrete names observed on this device). Hooked only when
                  the existing safe zero-argument ABI applies, purely so a live instance can be
                  captured as evidence; NEVER counted as an answer path, never registered as an
                  NSInvocation candidate, never used as the answer target.
     FORBIDDEN    matches the decline/reject/hang-up blacklist: never hooked, never registered,
                  never invoked.
     UNSUPPORTED  anything else that the keyword/global pass happened to match but that is not a
                  real answer action (e.g. -[CXCallControllerHost listener:
                  shouldAcceptNewConnection:] and the "…Changed…"-style notification callbacks
                  such as -[TUCallNotificationManager
                  answeringMachineStreamTokenChangedForCall:]); logged with a reason, never
                  hooked, never registered. */
typedef NS_ENUM(NSInteger,AACSBClassification){
 AACSBClassificationAction=0,
 AACSBClassificationAccessor=1,
 AACSBClassificationForbidden=2,
 AACSBClassificationUnsupported=3
};
static NSString *AACSBClassificationText(AACSBClassification classification){
 switch(classification){
  case AACSBClassificationAction:return @"ACTION";
  case AACSBClassificationAccessor:return @"ACCESSOR";
  case AACSBClassificationForbidden:return @"FORBIDDEN";
  default:return @"UNSUPPORTED";
 }
}
/* Real-action selector patterns, matched case-insensitively against the selector with and
   without its colons, with '*' as "any run of characters (including none)". These are the
   patterns a genuine answer action uses; a bare "answer"/"accept" substring is NOT enough. */
static NSArray *AACSBSelectorActionPatterns(void){
 return @[@"handle*answer",@"didtap*answer",@"perform*answer",@"answer*call*action",@"invoke*answer",@"pickup",@"pick up",@"acceptcall",@"tapanswer"];
}
/* Wildcard match ('*' = any run). Deliberately tiny and allocation-free per character. */
static BOOL AACSBWildcardMatch(NSString *text,NSString *pattern){
 NSUInteger t=0,p=0,star=NSNotFound,mark=0;
 while(t<text.length){
  if(p<pattern.length&&([pattern characterAtIndex:p]==[text characterAtIndex:t])){t++;p++;continue;}
  if(p<pattern.length&&[pattern characterAtIndex:p]=='*'){star=p++;mark=t;continue;}
  if(star!=NSNotFound){p=star+1;t=++mark;continue;}
  return NO;
 }
 while(p<pattern.length&&[pattern characterAtIndex:p]=='*')p++;
 return p==pattern.length;
}
static BOOL AACSBSelectorMatchesActionPattern(NSString *selector){
 NSString *lower=selector.lowercaseString;
 NSString *plain=[lower stringByReplacingOccurrencesOfString:@":" withString:@""];
 for(NSString *pattern in AACSBSelectorActionPatterns()){
  if(AACSBWildcardMatch(lower,pattern))return YES;
  if(AACSBWildcardMatch(plain,pattern))return YES;
 }
 return NO;
}
/* The concrete accessor names seen on THIS device, as literal strings: the classification must
   cover them even if the mirroring-setter lookup cannot see the setter (readonly property,
   different class in the chain, or a class that only ships the getter in a given process). */
static NSArray *AACSBKnownAccessorSelectors(void){
 return @[@"answeredCall",@"hasAnsweredCall",@"acceptButton",@"setAnsweredCall:",@"setAcceptButton:"];
}
/* Property getter detection: has<Name> / is<Name> / <name> that mirrors an existing setter
   set<Name>: on the same class chain. Checked both ways for the has/is prefixes. */
static BOOL AACSBClassHasMirroringSetter(Class cls,NSString *selector){
 if(!cls||!selector.length||[selector rangeOfString:@":"].location!=NSNotFound)return NO;
 NSMutableArray *candidates=[NSMutableArray arrayWithObject:selector];
 if(selector.length>3&&[[selector substringToIndex:3].lowercaseString isEqualToString:@"has"])[candidates addObject:[selector substringFromIndex:3]];
 if(selector.length>2&&[[selector substringToIndex:2].lowercaseString isEqualToString:@"is"])[candidates addObject:[selector substringFromIndex:2]];
 for(NSString *base in candidates){
  if(!base.length)continue;
  unichar first=[base characterAtIndex:0];
  NSString *capital=[[[NSString stringWithFormat:@"%C",first] uppercaseString] stringByAppendingString:(base.length>1?[base substringFromIndex:1]:@"")];
  if(class_getInstanceMethod(cls,NSSelectorFromString([NSString stringWithFormat:@"set%@:",capital]))!=NULL)return YES;
  @try{if(class_getInstanceMethod(cls,NSSelectorFromString([NSString stringWithFormat:@"set%@:",base]))!=NULL)return YES;}@catch(NSException *e){}
 }
 return NO;
}
/* A plain Objective-C setter: set<Name>: with exactly one argument and a capitalized tail. */
static BOOL AACSBSelectorIsSetter(NSString *selector,NSUInteger arguments){
 if(![selector hasPrefix:@"set"]||selector.length<5)return NO;
 if([selector rangeOfString:@":"].location==NSNotFound)return NO;
 if([selector componentsSeparatedByString:@":"].count!=2)return NO;
 if(arguments!=3)return NO;
 unichar c=[selector characterAtIndex:3];
 return c>='A'&&c<='Z';
}
/* Getter-shaped: no explicit arguments. */
static BOOL AACSBSelectorIsGetterShaped(NSString *selector,NSUInteger arguments){
 return arguments==2&&[selector rangeOfString:@":"].location==NSNotFound;
}
static NSString *AACSBClassificationReason(Class cls,NSString *selector,NSUInteger arguments,AACSBClassification classification){
 (void)cls;
 switch(classification){
  case AACSBClassificationAccessor:
   if(AACSBSelectorIsSetter(selector,arguments))return @"属性 setter set<Name>:（1.15.0 设备证据：setAnsweredCall: / setAcceptButton:）";
   return [NSString stringWithFormat:@"属性 getter（has<Name>/is<Name>/<Name> 且类上存在对应的 set<Name>:；设备证据：answeredCall / hasAnsweredCall / acceptButton）"];
  case AACSBClassificationForbidden:return [NSString stringWithFormat:@"拒绝/挂断类关键字（%@）",AACSBForbiddenKeyword(selector)?:@"匹配"]; 
  case AACSBClassificationAction:return @"匹配真实接听动作模式";
  default:return @"关键字命中但不是真实接听动作（例如 XPC/通知回调、…Changed… 观察回调）：不作为接听路径";
 }
}
static AACSBClassification AACSBClassifySelector(Class cls,NSString *selector,NSUInteger arguments,NSString **detail){
 AACSBClassification classification=AACSBClassificationUnsupported;
 NSString *why=nil;
 if(AACSBForbiddenKeyword(selector)){classification=AACSBClassificationForbidden;why=AACSBClassificationReason(cls,selector,arguments,classification);}
 else{
  NSString *lower=selector.lowercaseString;
  for(NSString *known in AACSBKnownAccessorSelectors())if([known.lowercaseString isEqualToString:lower]){classification=AACSBClassificationAccessor;break;}
  if(classification!=AACSBClassificationAccessor){
   if(AACSBSelectorIsSetter(selector,arguments))classification=AACSBClassificationAccessor;
   else if(AACSBSelectorIsGetterShaped(selector,arguments)&&AACSBClassHasMirroringSetter(cls,selector))classification=AACSBClassificationAccessor;
  }
  if(classification==AACSBClassificationAccessor)why=AACSBClassificationReason(cls,selector,arguments,classification);
  else if(AACSBSelectorMatchesActionPattern(selector)){classification=AACSBClassificationAction;why=AACSBClassificationReason(cls,selector,arguments,classification);}
  else why=AACSBClassificationReason(cls,selector,arguments,AACSBClassificationUnsupported);
 }
 if(detail)*detail=why?:@"无说明";
 return classification;
}

/* Original IMP lookup walks the real class chain and is keyed by (class, selector), so two
   classes that share one selector never share an original by accident. */
static IMP AACSBOriginalFor(id object,SEL selector){
 if(!object||!selector)return NULL;
 Class cls=object_getClass(object);
 @try{
  while(cls){
   for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].cls==cls&&AACSBHookRecords[i].sel==selector)return AACSBHookRecords[i].original;
   cls=class_getSuperclass(cls);
  }
 }@catch(NSException *e){AACSBLog([@"original IMP lookup exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return NULL;
}
/* MSHookMessageEx from ElleKit / the substrate compatibility layer, resolved at runtime so
   the tweak neither hard-links nor includes a private header that may be missing in a given
   jailbreak process. Returns NULL when this process provides no such symbol; the caller then
   falls back to method_setImplementation with the same saved-original contract. */
typedef void (*AACMSHookMessageExFn)(Class,SEL,IMP,IMP *);
static AACMSHookMessageExFn AACSBResolveMSHook(void){
 static AACMSHookMessageExFn resolved=nil;
 static int attempted=0;
 if(!attempted){
  attempted=1;
  @try{
   resolved=(AACMSHookMessageExFn)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
   if(!resolved)resolved=(AACMSHookMessageExFn)dlsym(RTLD_DEFAULT,"MSHookMessageEx$");
  }@catch(NSException *e){resolved=nil;}
  AACSBAppendDiscovery([NSString stringWithFormat:@"# hookMechanism MSHookMessageEx resolved=%d（%s）；不可用时回退 method_setImplementation 并同样保存原始 IMP",resolved!=nil,resolved?"ElleKit/substrate 兼容层提供":"本进程没有该符号，使用回退机制"]);
 }
 return resolved;
}
/* A capture-only replacement must never re-enter policy while our own call is running: the
   depth counter and the invoking flag are the recursion guards. */
static void AACSBHookEnter(id self,SEL _cmd,const char *abi){
 if(!self)return;
 int32_t depth=__sync_add_and_fetch(&AACSBDepth,1);
 @try{
  if(depth==1&&!AACSBInvoking){
   AACSBCapture(self,_cmd);
   Class cls=object_getClass(self);
   NSString *line=[NSString stringWithFormat:@"answer-ish method invoked through our dynamic hook: -[%@ %@] (%s, recursion guard depth=1, invoking=0)",NSStringFromClass(cls),NSStringFromSelector(_cmd),abi];
   dispatch_async(dispatch_get_main_queue(),^{
    AACSBLog(line);
    AACSBRecord([NSString stringWithFormat:@"动态挂钩命中：−[%@ %@] 被调用，已记录接收对象",NSStringFromClass(cls),NSStringFromSelector(_cmd)],@{@"discovered":@YES});
   });
  }
 }@catch(NSException *e){AACSBLog([@"hook capture exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
static void AACSBHookExit(void){__sync_sub_and_fetch(&AACSBDepth,1);}
static void AACSBPassthroughMissing(id self,SEL _cmd){AACSBLog([NSString stringWithFormat:@"hooked selector %@ has no saved original IMP; passing nothing through",NSStringFromSelector(_cmd)]);}
/* Fixed-signature thunks: one per supported RETURN type, always zero explicit arguments, so
   the ABI is provably correct and forwarding to the saved original is behaviour-neutral. */
static void AACSBAnswerHook(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+void");
 IMP original=AACSBOriginalFor(self,_cmd);
 if(original)((void(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
}
static BOOL AACSBAnswerHookBool(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+BOOL");
 IMP original=AACSBOriginalFor(self,_cmd);BOOL result=NO;
 if(original)result=((BOOL(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
 return result;
}
static id AACSBAnswerHookObject(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+object");
 IMP original=AACSBOriginalFor(self,_cmd);id result=nil;
 if(original)result=((id(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
 return result;
}
static long long AACSBAnswerHookInteger(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+integer");
 IMP original=AACSBOriginalFor(self,_cmd);long long result=0;
 if(original)result=((long long(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
 return result;
}
static double AACSBAnswerHookDouble(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+float64");
 IMP original=AACSBOriginalFor(self,_cmd);double result=0;
 if(original)result=((double(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
 return result;
}
/* A float return must not be forwarded through a double thunk: the caller reads the low 32
   bits of s0, which are not the original float's bit pattern. */
static float AACSBAnswerHookFloat(id self,SEL _cmd){
 AACSBHookEnter(self,_cmd,"abi=0args+float32");
 IMP original=AACSBOriginalFor(self,_cmd);float result=0;
 if(original)result=((float(*)(id,SEL))original)(self,_cmd);else AACSBPassthroughMissing(self,_cmd);
 AACSBHookExit();
 return result;
}
/* Which return type can a fixed thunk forward correctly? Everything else is skipped with a
   reason instead of being hooked with a wrong ABI. */
static IMP AACSBThunkForReturnType(const char *returnType,NSString **abiText){
 if(!returnType||!returnType[0])return NULL;
 switch(returnType[0]){
  case 'v':case 'V':if(abiText)*abiText=@"0args+void";return (IMP)AACSBAnswerHook;
  case 'c':case 'B':if(abiText)*abiText=@"0args+BOOL";return (IMP)AACSBAnswerHookBool;
  case '@':if(abiText)*abiText=@"0args+object";return (IMP)AACSBAnswerHookObject;
  case 'd':if(abiText)*abiText=@"0args+float64";return (IMP)AACSBAnswerHookDouble;
  case 'f':if(abiText)*abiText=@"0args+float32";return (IMP)AACSBAnswerHookFloat;
  case 'q':case 'Q':case 'l':case 'L':case 'i':case 'I':case 's':case 'S':if(abiText)*abiText=@"0args+integer";return (IMP)AACSBAnswerHookInteger;
  default:return NULL;
 }
}
/* True when the implementation already in place is one of our own thunks: the double-hook
   guard relies on this as well as on the (class,selector) and IMP key sets. */
static BOOL AACSBIsOurThunk(IMP imp){
 return imp==(IMP)AACSBAnswerHook||imp==(IMP)AACSBAnswerHookBool||imp==(IMP)AACSBAnswerHookObject||imp==(IMP)AACSBAnswerHookInteger||imp==(IMP)AACSBAnswerHookDouble||imp==(IMP)AACSBAnswerHookFloat;
}
static void AACSBCapture(id object,SEL selector){
 if(!object)return;
 Class cls=object_getClass(object);
 NSString *detail=[NSString stringWithFormat:@"-[%@ %@]",NSStringFromClass(cls),NSStringFromSelector(selector)];
 /* 1.15.0 TASK 2: an ACCESSOR capture is evidence only. It never becomes the answer target and
    it never points the submission path at a method that cannot act. */
 if(!AACSBSelectorIsAnswerPath(cls,selector)){
  dispatch_async(dispatch_get_main_queue(),^{
   AACSBLog([NSString stringWithFormat:@"ACCESSOR capture (evidence only; NOT an answer path, never used as the answer target): %@",detail]);
   AACSBAppendDiscovery([@"  CAPTURED_ACCESSOR " stringByAppendingString:detail]);
  });
  return;
 }
 AACSBWeakTarget=object;
 AACSBStrongTarget=object;
 AACSBInvokeSelector=selector;
 dispatch_async(dispatch_get_main_queue(),^{
  AACSBLog([NSString stringWithFormat:@"captured live incoming-call UI object via dynamic hook: %@ (强引用仅在本通话窗口内保留，另有弱引用与重扫兜底)",detail]);
  AACSBAppendDiscovery([@"  CAPTURED " stringByAppendingString:detail]);
 });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACSBStrongHoldSeconds*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(AACSBStrongTarget==object){AACSBStrongTarget=nil;AACSBLog(@"bounded strong hold on the captured object expired; weak reference and hierarchy re-scan remain");}
 });
}
/* Bounded hierarchy walk: window tree, view controllers and responder chains. This is the
   fallback used when the weak/strong capture is gone by answer time, and it is also how a
   live instance of an NSInvocation candidate class is located.
   1.15.0 TASK 2: ONLY classes that carry a real ACTION answer method are matched, so the
   re-scan can never hand the submission path an object whose only relation to the call is a
   property accessor (that is exactly the 14:20:21 device case: windows=21 visited=1771
   found=0). */
static Class AACSBMatchedCandidateClass(id object){
 if(!object)return Nil;
 Class cls=object_getClass(object);
 while(cls){
  for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].countsAsPath&&AACSBHookRecords[i].cls==cls)return cls;
  for(NSUInteger i=0;i<AACSBInvocationCount;i++)if(AACSBInvocationRecords[i].countsAsPath&&AACSBInvocationRecords[i].cls==cls)return cls;
  cls=class_getSuperclass(cls);
 }
 return Nil;
}
static void AACSBScanResponder(id object,id *found){
 if(!object||*found)return;
 @try{
  id next=object;
  for(NSUInteger up=0;up<AACSBResponderUpCap&&next&&!*found;up++){
   if(AACSBMatchedCandidateClass(next)){*found=next;return;}
   next=[next isKindOfClass:UIResponder.class]?[(UIResponder *)next nextResponder]:nil;
  }
 }@catch(NSException *e){}
}
static void AACSBScanViewController(UIViewController *controller,NSUInteger depth,NSUInteger *visited,id *found){
 if(!controller||*found||depth>AACSBScanDepthCap||*visited>=AACSBScanNodeCap)return;
 *visited+=1;
 AACSBScanResponder(controller,found);
 if(*found)return;
 if(controller.presentedViewController)AACSBScanViewController(controller.presentedViewController,depth+1,visited,found);
 for(UIViewController *child in controller.childViewControllers)AACSBScanViewController(child,depth+1,visited,found);
}
static void AACSBScanView(UIView *view,NSUInteger depth,NSUInteger *visited,id *found){
 if(!view||*found||depth>AACSBScanDepthCap||*visited>=AACSBScanNodeCap)return;
 *visited+=1;
 AACSBScanResponder(view,found);
 if(*found)return;
 if(view.nextResponder&&[view.nextResponder isKindOfClass:UIViewController.class])AACSBScanViewController((UIViewController *)view.nextResponder,0,visited,found);
 if(*found||*visited>=AACSBScanNodeCap)return;
 for(UIView *subview in view.subviews)AACSBScanView(subview,depth+1,visited,found);
}
static id AACSBRescan(void){
 id found=nil;
 @try{
  NSUInteger visited=0;
  NSMutableArray *windows=[NSMutableArray new];
  UIApplication *application=UIApplication.sharedApplication;
  /* Scene API only: UIApplication.windows is deprecated since iOS 15 and this project
     builds with -Werror, so no deprecated accessor is used anywhere. */
  for(UIScene *scene in application.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])[windows addObjectsFromArray:((UIWindowScene *)scene).windows];
  for(UIWindow *window in windows){
   AACSBScanResponder(window,&found);
   if(!found&&window.rootViewController)AACSBScanViewController(window.rootViewController,0,&visited,&found);
   if(!found)AACSBScanView(window,0,&visited,&found);
   if(found)break;
  }
  AACSBRescanVisits=visited;
  AACSBLog([NSString stringWithFormat:@"hierarchy re-scan for the incoming-call UI object: windows=%lu visited=%lu found=%d",(unsigned long)windows.count,(unsigned long)visited,found!=nil]);
 }@catch(NSException *e){AACSBLog([@"hierarchy re-scan exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return found;
}
static id AACSBAnswerTarget(NSString **source){
 id target=AACSBWeakTarget;
 if(target){if(source)*source=@"弱引用捕获对象";return target;}
 target=AACSBStrongTarget;
 if(target){if(source)*source=@"本通话窗口内的强引用捕获对象";return target;}
 target=AACSBRescan();
 if(source)*source=target?@"窗口/视图控制器层级重扫":@"未找到：没有已捕获对象，重扫也没有发现已挂钩类的实例";
 return target;
}

/* ---- NSInvocation path for candidate methods that take explicit arguments --------------
   A C replacement function cannot rebuild the arguments of an arbitrary ABI, so these
   methods are NEVER hooked. They are invoked (only by the answer step, only on a live
   instance, only once, behind the recursion guard) with default arguments instead. The
   safety rules below are what makes that defensible: bounded argument count, only argument
   types whose default value can be constructed (object/pointer => nil, scalar => 0), a
   decline/hang-up blacklist applied before registration, and an explicit log line saying the
   arguments are guessed defaults and that the call is not proof of a connected call. */
static BOOL AACSBInvocationArgumentSafe(const char *type,NSString **why){
 if(!type||!type[0]){if(why)*why=@"参数类型编码为空";return NO;}
 switch(type[0]){
  case '@':case '#':case ':':case '^':case '*':case '?':
  case 'c':case 'C':case 'B':case 'i':case 'I':case 's':case 'S':case 'l':case 'L':case 'q':case 'Q':
  case 'f':case 'd':
   return YES;
  default:
   if(why)*why=[NSString stringWithFormat:@"参数类型 %s 的默认值无法安全构造（结构体/联合体/C++ 类型等）",type];
   return NO;
 }
}
static BOOL AACSBMethodInvocationSafe(Method method,NSString **why){
 if(!method){if(why)*why=@"方法不存在";return NO;}
 unsigned int arguments=method_getNumberOfArguments(method);
 if(arguments<=2){if(why)*why=[NSString stringWithFormat:@"显式参数数量=%u，无需 NSInvocation 路径",arguments>2?arguments-2:0];return NO;}
 if(arguments>5){if(why)*why=[NSString stringWithFormat:@"显式参数数量=%u 超过可安全构造默认值的上限 3",arguments-2];return NO;}
 const char *types=method_getTypeEncoding(method);
 if(!types){if(why)*why=@"方法类型编码为空";return NO;}
 NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:types];
 if(!signature){if(why)*why=@"无法从类型编码构造 NSMethodSignature（格式不受支持）";return NO;}
 if(signature.numberOfArguments!=arguments){if(why)*why=@"NSMethodSignature 与方法参数数量不一致";return NO;}
 for(NSUInteger index=2;index<arguments;index++){
  const char *type=[signature getArgumentTypeAtIndex:index];
  NSString *reason=nil;
  if(!AACSBInvocationArgumentSafe(type,&reason)){if(why)*why=reason;return NO;}
 }
 return YES;
}
/* Fewest-argument candidate in the target's class chain; nil when the class chain has none. */
static SEL AACSBInvocationSelectorFor(id target){
 if(!target)return NULL;
 Class cls=object_getClass(target);
 SEL best=NULL;
 unsigned int bestArguments=0;
 @try{
  while(cls){
   for(NSUInteger i=0;i<AACSBInvocationCount;i++){
    if(!AACSBInvocationRecords[i].countsAsPath)continue;
    if(AACSBInvocationRecords[i].cls!=cls)continue;
    SEL selector=AACSBInvocationRecords[i].sel;
    if(!selector)continue;
    Method method=class_getInstanceMethod(cls,selector);
    unsigned int arguments=method?method_getNumberOfArguments(method):0;
    if(!best||(arguments&&arguments<bestArguments)){best=selector;bestArguments=arguments;}
   }
   cls=class_getSuperclass(cls);
  }
 }@catch(NSException *e){AACSBLog([@"invocation candidate lookup exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return best;
}
static BOOL AACSBInvokeByInvocation(id target,SEL selector,NSString **reason){
 if(!target||!selector){if(reason)*reason=@"目标或选择器为空";return NO;}
 Class cls=object_getClass(target);
 Method method=class_getInstanceMethod(cls,selector);
 NSString *why=nil;
 if(!AACSBMethodInvocationSafe(method,&why)){if(reason)*reason=why?:@"方法无法用 NSInvocation 安全调用";return NO;}
 const char *types=method_getTypeEncoding(method);
 NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:types?:""];
 if(!signature){if(reason)*reason=@"NSMethodSignature 构造失败";return NO;}
 NSUInteger arguments=signature.numberOfArguments;
 NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];
 @try{
  [invocation setTarget:target];
  [invocation setSelector:selector];
  for(NSUInteger index=2;index<arguments;index++){
   const char *type=[signature getArgumentTypeAtIndex:index];
   if(!type)continue;
   switch(type[0]){
    case '@':case '#':case ':':case '^':case '*':{id value=nil;[invocation setArgument:&value atIndex:index];break;}
    case 'f':{float value=0;[invocation setArgument:&value atIndex:index];break;}
    case 'd':{double value=0;[invocation setArgument:&value atIndex:index];break;}
    default:{long long value=0;[invocation setArgument:&value atIndex:index];break;}
   }
  }
 }@catch(NSException *e){
  if(reason)*reason=[@"构造 NSInvocation 参数时抛出异常：" stringByAppendingString:e.reason?:@"unknown"];
  return NO;
 }
 __sync_add_and_fetch(&AACSBInvoking,1);
 BOOL ok=YES;
 @try{[invocation invoke];}
 @catch(NSException *e){ok=NO;if(reason)*reason=[@"用默认参数调用原始实现时抛出异常：" stringByAppendingString:e.reason?:@"unknown"];}
 __sync_sub_and_fetch(&AACSBInvoking,1);
 if(!ok)return NO;
 if(reason)*reason=[NSString stringWithFormat:@"已用 NSInvocation 以默认参数（对象/指针=nil、标量=0）调用 -[%@ %@]；参数值是猜测的默认值，调用本身不等于已接通",NSStringFromClass(cls),NSStringFromSelector(selector)];
 return YES;
}
/* ---- answer step ----------------------------------------------------------------------- */
static BOOL AACSBInvokeDiscovered(id target,NSString **reason){
 if(!target){if(reason)*reason=@"没有已捕获或可重新定位的来电 UI 对象";return NO;}
 /* 1) hooked, zero-explicit-argument method with a saved original IMP: call the original
       directly. AACSBInvokeSelector is the selector the capture saw; when it does not belong
       to the class chain, fall back to the first hooked method of a class in the chain. */
 IMP original=AACSBOriginalForAnswer(target,AACSBInvokeSelector);
 SEL chosen=AACSBInvokeSelector;
 if(!original){
  Class cls=object_getClass(target);
  while(cls&&!original){
   for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].countsAsPath&&AACSBHookRecords[i].cls==cls){original=AACSBHookRecords[i].original;chosen=AACSBHookRecords[i].sel;break;}
   if(!original)cls=class_getSuperclass(cls);
  }
 }
 if(original){
  __sync_add_and_fetch(&AACSBInvoking,1);
  @try{ ((void(*)(id,SEL))original)(target,chosen); }
  @catch(NSException *e){ __sync_sub_and_fetch(&AACSBInvoking,1); if(reason)*reason=[@"原始实现抛出异常：" stringByAppendingString:e.reason?:@"unknown"]; return NO; }
  __sync_sub_and_fetch(&AACSBInvoking,1);
  if(reason)*reason=[NSString stringWithFormat:@"已直接调用发现到的原始 IMP -[%@ %@]（递归守卫生效；调用本身不等于已接通）",NSStringFromClass(object_getClass(target)),NSStringFromSelector(chosen)];
  return YES;
 }
 /* 2) argument-taking candidate: NSInvocation with default arguments (labelled unverified). */
 SEL invocationSelector=AACSBInvocationSelectorFor(target);
 if(invocationSelector){
  NSString *why=nil;
  AACSBInvokedByInvocation++;
  BOOL invoked=AACSBInvokeByInvocation(target,invocationSelector,&why);
  NSString *className=NSStringFromClass(object_getClass(target));
  NSString *selectorName=NSStringFromSelector(invocationSelector);
  AACSBAppendDiscovery([NSString stringWithFormat:@"  INVOKED_BY_INVOCATION -[%@ %@] result=%d detail=%@",className,selectorName,invoked,why?:@""]);
  dispatch_async(dispatch_get_main_queue(),^{
   AACSBLog([NSString stringWithFormat:@"NSInvocation answer attempt in %@: -[%@ %@] invoked=%d (%@)",AACSBDisplay(),className,selectorName,invoked,why?:@"无说明"]);
  });
  if(invoked){if(reason)*reason=why;return YES;}
  if(reason)*reason=why?:@"NSInvocation 调用失败";
  return NO;
 }
 if(reason)*reason=@"目标对象的类链上没有已挂钩的原始 IMP，也没有可用的 NSInvocation 候选（发现结果不含该类）";
 return NO;
}
static NSString *AACSBHookedSummary(void){
 if(!AACSBHookedSelectors.count)return @"未发现可挂钩的来电接听方法（运行时枚举结果为空或被安全跳过）";
 NSArray *list=AACSBHookedSelectors.count>12?[AACSBHookedSelectors subarrayWithRange:NSMakeRange(0,12)]:AACSBHookedSelectors;
 NSString *text=[list componentsJoinedByString:@"、"];
 return AACSBHookedSelectors.count>12?[text stringByAppendingFormat:@" 等 %lu 个",(unsigned long)AACSBHookedSelectors.count]:text;
}
static NSString *AACSBInvokableSummary(void){
 if(!AACSBInvokableSelectors.count)return @"没有登记 NSInvocation 候选（有参数的方法都被安全跳过）";
 NSArray *list=AACSBInvokableSelectors.count>6?[AACSBInvokableSelectors subarrayWithRange:NSMakeRange(0,6)]:AACSBInvokableSelectors;
 return [list componentsJoinedByString:@"、"];
}
/* 1.13.0/1.14.0: at answer time, repeat each candidate method's outcome in the shared log (not only
   in the discovery file), so the next device test can read the conclusions from the log too. */
static void AACSBLogMethodOutcomes(void){
 NSMutableArray *lines=[NSMutableArray new];
 [lines addObject:[NSString stringWithFormat:@"方法处置摘要 host=%@：HOOKED=%lu（其中 ACTION=%lu，ACCESSOR=%lu；只有 ACTION 计入 answerPaths）INVOKABLE_BY_INVOCATION=%lu（ACTION=%lu）（%@）SKIPPED=%lu（ACCESSOR 跳过=%lu，UNSUPPORTED 跳过=%lu）invocationAttempts=%lu discoverRuns=%lu",AACSBDisplay(),(unsigned long)AACSBHookCount,(unsigned long)AACSBHookActionCount,(unsigned long)AACSBHookAccessorCount,(unsigned long)AACSBInvocationCount,(unsigned long)AACSBInvokableActionCount,AACSBInvokableSummary(),(unsigned long)AACSBRejectedMethods,(unsigned long)AACSBAccessorSkipped,(unsigned long)AACSBUnsupportedSkipped,(unsigned long)AACSBInvokedByInvocation,(unsigned long)AACSBDiscoverRuns]];
 @try{
  for(NSUInteger i=0;i<AACSBHookCount&&AACSBHookDetails&&i<AACSBHookDetails.count;i++)[lines addObject:[@"  HOOKED " stringByAppendingString:AACSBHookDetails[i]]];
  for(NSString *entry in AACSBInvokableSelectors)[lines addObject:[@"  INVOKABLE " stringByAppendingString:entry]];
 }@catch(NSException *e){[lines addObject:[@"  方法处置摘要拼接异常：" stringByAppendingString:e.reason?:@"unknown"]];}
 [lines addObject:@"  （每个候选方法的完整处置与原因见该宿主的运行时发现文件）"];
 NSArray *snapshot=lines;
 dispatch_async(dispatch_get_main_queue(),^{for(NSString *line in snapshot)AACSBLog(line);});
}
static void AACSBAppendDiscovery(NSString *line){
 if(![line isKindOfClass:NSString.class]||!line.length)return;
 @try{
  if(!AACSBDiscoveryLines)AACSBDiscoveryLines=[NSMutableArray new];
  if(AACSBDiscoveryLines.count>=4000)return;
  [AACSBDiscoveryLines addObject:line];
 }@catch(NSException *e){}
}
/* 1.14.0 TASK 2: the compact "HOOKED list" block. Because the shared-log digest is budgeted
   and because the full discovery file can be long, the hooked method NAMES (class + selector +
   mechanism) and the invokable-by-invocation candidates are emitted as their own explicitly
   labelled block that is placed FIRST in both the log lines and the discovery file. Bounded:
   at most AACSBListBlockMaxEntries hook entries and AACSBListBlockMaxEntries invocation
   entries, one line each, so the block can never itself become unreadable. */
enum { AACSBListBlockMaxEntries=24 };
static NSString *AACSBHookedBlockText(void){
 NSMutableArray *lines=[NSMutableArray new];
 NSUInteger hookTotal=AACSBHookCount;
 NSUInteger invokeTotal=AACSBInvocationCount;
 [lines addObject:@"# ===== HOOKED list（紧凑块：类+选择器+机制；日志行与发现文件都放在最前面，不受摘要预算截断影响） ====="];
 [lines addObject:[NSString stringWithFormat:@"# HOOKED_TOTAL hooked=%lu (action=%lu accessor=%lu) invokable=%lu answerPaths=%lu candidateClasses=%lu rejected=%lu role=%@ owner=%@ discoverRuns=%lu（只有 ACTION 计入 answerPaths：accessor 挂钩仅作证据）",(unsigned long)hookTotal,(unsigned long)AACSBHookActionCount,(unsigned long)AACSBHookAccessorCount,(unsigned long)invokeTotal,(unsigned long)AACSBAnswerPathCount(),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBRejectedMethods,AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY"),AACSBHostOwnerTagText(),(unsigned long)AACSBDiscoverRuns]];
 [lines addObject:[NSString stringWithFormat:@"# HOOKED_LIST count=%lu host=%@ display=%@",(unsigned long)hookTotal,AACSBProcess(),AACSBDisplay()]];
 if(hookTotal==0){
  [lines addObject:@"  HOOKED (none) 没有挂钩任何方法：没有「零显式参数且返回类型可直通」的候选（每个候选的具体原因见本文件 SKIPPED 行；访问器即使被挂钩也不计入 answerPaths）"];
 }else{
  for(NSUInteger i=0;i<hookTotal&&i<AACSBListBlockMaxEntries;i++){
   NSString *detail=(AACSBHookDetails&&i<AACSBHookDetails.count)?AACSBHookDetails[i]:[NSString stringWithFormat:@"-[%@ %@]（详情索引缺失）",@"(unknown-class)",@"(unknown-selector)"];
   [lines addObject:[@"  HOOKED " stringByAppendingString:detail]];
  }
  if(hookTotal>AACSBListBlockMaxEntries)[lines addObject:[NSString stringWithFormat:@"  HOOKED ... 其余 %lu 条见本文件的 HOOK_ENTRY 行",(unsigned long)(hookTotal-AACSBListBlockMaxEntries)]];
 }
 [lines addObject:[NSString stringWithFormat:@"# INVOKABLE_LIST count=%lu（有显式参数、未挂钩，接听步骤用 NSInvocation 传默认参数调用）",(unsigned long)invokeTotal]];
 if(invokeTotal==0){
  [lines addObject:@"  INVOKABLE (none) 没有登记 NSInvocation 候选"];
 }else{
  NSUInteger shown=invokeTotal<(NSUInteger)AACSBListBlockMaxEntries?invokeTotal:(NSUInteger)AACSBListBlockMaxEntries;
  for(NSUInteger i=0;i<shown&&i<AACSBInvokableSelectors.count;i++)[lines addObject:[@"  INVOKABLE " stringByAppendingString:AACSBInvokableSelectors[i]]];
  if(invokeTotal>shown)[lines addObject:[NSString stringWithFormat:@"  INVOKABLE ... 其余 %lu 条见本文件的 INVOKE_ENTRY 行",(unsigned long)(invokeTotal-shown)]];
 }
 [lines addObject:[NSString stringWithFormat:@"# roleReason=%@",AACSBClaimReasonText()]];
 [lines addObject:[NSString stringWithFormat:@"# observedHostPresence=%@",AACAnswerPresenceText()]];
 [lines addObject:@"# ===== end HOOKED list ====="];
 return [lines componentsJoinedByString:@"\n"];
}
/* 1.14.0 TASK 2: the shared log truncates every single line at 2000 chars, so the discovery
   digest is emitted in bounded chunks (default total budget raised to AACSBLogDigestTotalCap
   characters, chunk size AACSBLogDigestChunkCap) instead of one line that would silently lose
   its tail. The HOOKED list block is the first chunk, so it is always visible. */
static const NSUInteger AACSBLogDigestTotalCap=6000;
static const NSUInteger AACSBLogDigestChunkCap=1600;
static void AACSBLogDigest(NSString *text){
 if(![text isKindOfClass:NSString.class]||!text.length){AACSBLog(@"discovery digest: 空（运行时发现没有产生任何行）");return;}
 NSArray *sourceLines=[text componentsSeparatedByString:@"\n"];
 NSMutableArray *chunks=[NSMutableArray new];
 NSMutableString *current=[NSMutableString string];
 for(NSString *line in sourceLines){
  if(current.length&&current.length+line.length+1>AACSBLogDigestChunkCap){[chunks addObject:current.copy];current=[NSMutableString string];}
  [current appendString:line];[current appendString:@"\n"];
 }
 if(current.length)[chunks addObject:current.copy];
 NSUInteger total=chunks.count;NSUInteger index=1;NSUInteger budget=AACSBLogDigestTotalCap;
 AACSBLog([NSString stringWithFormat:@"discovery digest 分块输出（每行 <=2000 字符的共享日志上限，总预算 %lu 字符，共 %lu 块；完整内容见上面写出的发现文件路径）：",(unsigned long)AACSBLogDigestTotalCap,(unsigned long)total]);
 for(NSString *chunk in chunks){
  if(!budget){AACSBLog([NSString stringWithFormat:@"discovery digest 截断：剩余 %lu 块未写入日志（预算 %lu 字符已用完），完整内容在发现文件里",(unsigned long)(total-index+1),(unsigned long)AACSBLogDigestTotalCap]);break;}
  NSString *piece=chunk.length>budget?[chunk substringToIndex:budget]:chunk;
  AACSBLog([NSString stringWithFormat:@"discovery digest[%lu/%lu]:\n%@",(unsigned long)index,(unsigned long)total,piece]);
  budget=budget>piece.length?budget-(NSUInteger)piece.length:0;
  index++;
 }
}
static void AACSBWriteDiscoveryFile(void){
 if(!AACSBDiscoveryLines){AACSBDiscoveryLines=[NSMutableArray new];}
 AACSBRecomputeRole();
 /* Appended every run so a device test can read the host, its role and its hooks from one
    file, without any cross-process file visibility being assumed. */
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# host=%@ tag=%@ display=%@ discoveryFile=%@",AACSBDisplay(),AACSBProcess(),AACSBDisplay(),AACSBHostDiscoveryFile()]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# role=%@ owner=%@ roleTable=%@",AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY"),AACSBOwnerTag?:@"(none)",AACAnswerRoleTableText()]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# roleReason=%@",AACSBRoleReason?:@"(none)"]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# observedHostPresence=%@",AACAnswerPresenceText()]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# HOOKED_TOTAL hooked=%lu (action=%lu accessor=%lu) invokable=%lu (action=%lu) answerPaths=%lu of candidateClasses=%lu rejected=%lu invokableSkipped=%lu accessorSkipped=%lu unsupportedSkipped=%lu invocationAttempts=%lu rescanVisited=%lu discoverRuns=%lu globalPassScanned=%lu",(unsigned long)AACSBHookCount,(unsigned long)AACSBHookActionCount,(unsigned long)AACSBHookAccessorCount,(unsigned long)AACSBInvocationCount,(unsigned long)AACSBInvokableActionCount,(unsigned long)AACSBAnswerPathCount(),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBRejectedMethods,(unsigned long)AACSBInvokableSkipped,(unsigned long)AACSBAccessorSkipped,(unsigned long)AACSBUnsupportedSkipped,(unsigned long)AACSBInvokedByInvocation,(unsigned long)AACSBRescanVisits,(unsigned long)AACSBDiscoverRuns,(unsigned long)AACSBGlobalScanned]];
 if(AACSBHookCount){
  [AACSBDiscoveryLines addObject:[@"# HOOK_SUMMARY " stringByAppendingString:AACSBHookedSummary()]];
  for(NSString *entry in AACSBHookedSelectors)[AACSBDiscoveryLines addObject:[@"# HOOK_ENTRY " stringByAppendingString:entry]];
 }else{
  [AACSBDiscoveryLines addObject:@"# HOOK_SUMMARY 没有挂钩任何方法：本宿主没有零显式参数且返回类型可直通的接听方法（每个候选的原因见上面 SKIPPED/HOOKED 行）"];
 }
 if(AACSBInvocationCount){
  [AACSBDiscoveryLines addObject:[@"# INVOKE_SUMMARY " stringByAppendingString:AACSBInvokableSummary()]];
  for(NSString *entry in AACSBInvokableSelectors)[AACSBDiscoveryLines addObject:[@"# INVOKE_ENTRY " stringByAppendingString:entry]];
 }
 if(AACSBAnswerPathCount()){
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# CONCLUSIVE: 本宿主持有 %lu 条 ACTION 接听路径（已挂钩 ACTION=%lu，NSInvocation ACTION 候选=%lu）；另有 %lu 个 ACCESSOR 挂钩仅作证据、不计入 answerPaths；下一次设备来电若命中，日志会记录 ACTION 方法被调用 / CAPTURED 活实例 / INVOKED_BY_INVOCATION 及其结果。",(unsigned long)AACSBAnswerPathCount(),(unsigned long)AACSBHookActionCount,(unsigned long)AACSBInvokableActionCount,(unsigned long)AACSBHookAccessorCount]];
 }else{
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# CONCLUSIVE: 本宿主发现到的 ACTION 接听路径=0，因此本宿主不可能接听（role 必须是 LOG-ONLY，不是 OWNER）；本宿主有 %lu 个 ACCESSOR 挂钩（%lu 个 ACCESSOR 被跳过、%lu 个 UNSUPPORTED 被跳过），这些都只是属性访问器/无关方法，绝不能当作接听路径。请以下一次设备来电时的日志确认其他宿主是否可接听。",(unsigned long)AACSBHookAccessorCount,(unsigned long)AACSBAccessorSkipped,(unsigned long)AACSBUnsupportedSkipped]];
 }
 NSString *body=AACSBDiscoveryLines.count?[AACSBDiscoveryLines componentsJoinedByString:@"\n"]:@"# 运行时发现未运行";
 /* 1.14.0 TASK 2: the compact HOOKED list goes FIRST in the file (and in the log below), so the
    hooked class+selector+mechanism is readable even if the rest of the file is long. */
 NSString *hookedBlock=AACSBHookedBlockText();
 NSString *text=[hookedBlock stringByAppendingFormat:@"\n%@\n",body];
 NSError *error=nil;
 BOOL written=AACSharedWriteNamed(AACSBProcess(),@"discovery.txt",text,&error);
 NSDictionary *chosen=AACSharedResolve(AACSBProcess(),NO);
 NSString *path=chosen?[chosen[@"dir"] stringByAppendingPathComponent:AACSharedFileLeaf(AACSBProcess(),@"discovery.txt")]:nil;
 AACSBLog([NSString stringWithFormat:@"%@ runtime-discovered answer path: host=%@ role=%@ matchedClasses=%lu hookedMethods=%lu invokable=%lu rejected=%lu fileWritten=%d path=%@ error=%@",AACSBDisplay(),AACSBProcess(),AACSBRole==AACAnswerRoleOwner?@"OWNER":(AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY"),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBHookCount,(unsigned long)AACSBInvocationCount,(unsigned long)AACSBRejectedMethods,written,path?:@"<没有可写候选路径>",written?@"none":(error.localizedDescription?:@"unknown")]);
 if(AACSBHookCount)AACSBLog([@"已挂钩方法：" stringByAppendingString:AACSBHookedSummary()]);
 else AACSBLog(@"没有挂钩任何方法：零显式参数且返回类型可直通的接听方法为 0；若下面有 NSInvocation 候选，接听仍可能通过该路径发生（结果会写入 INVOKED_BY_INVOCATION 行）");
 if(AACSBInvocationCount)AACSBLog([@"NSInvocation 候选：" stringByAppendingString:AACSBInvokableSummary()]);
 /* 1.14.0 TASK 2: the compact HOOKED list is logged line by line first (each line is far below
    the 2000-char shared-log line cap), then the digest follows in bounded chunks. */
 for(NSString *blockLine in [hookedBlock componentsSeparatedByString:@"\n"])AACSBLog(blockLine);
 AACSBLog([NSString stringWithFormat:@"%@ 接听归属判定（发现时）：owner=%@ role=%@ submitted=no why=%@",AACSBDisplay(),AACSBHostOwnerTagText(),AACSBHostRoleText(),AACSBClaimReasonText()]);
 AACSBLogDigest(text);
 /* 1.15.0 TASK 1: also publish the discovery summary + this host's recent log lines through the
    shared host-report CFPreferences domain (our own domain, per-host keys, bounded payload).
    The result line below reports the REAL synchronize status and the real byte counts; it does
    NOT claim that Settings or another host can read them. */
 @try{
  NSDictionary *report=AACSBHostReportPublishNow();
  AACSBLog([NSString stringWithFormat:@"host report published to the shared CFPreferences domain: domain=%@ keys=%@ synced=%@ summaryBytes=%@ logBytes=%@ totalBytes=%@ boundBytes=%@ tag=%@（跨进程可见性未验证：本行只报告本进程实际写入与同步结果，其他进程能否读到由它们各自的读回结果显示）",report[@"domain"],report[@"keys"],report[@"synced"],report[@"summaryBytes"],report[@"logBytes"],report[@"totalBytes"],report[@"boundBytes"],report[@"tag"]]);
 }@catch(NSException *e){AACSBLog([@"host report publication exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 AACSBRecord(AACSBAnswerPathCount()?[NSString stringWithFormat:@"%@ 运行时发现（非硬编码，objc_getClassList 枚举）：候选类=%lu，已挂钩方法=%lu（%@），NSInvocation 候选=%lu（%@），安全跳过=%lu；角色=%@（%@）",AACSBDisplay(),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBHookCount,AACSBHookedSummary(),(unsigned long)AACSBInvocationCount,AACSBInvokableSummary(),(unsigned long)AACSBRejectedMethods,AACSBRole==AACAnswerRoleOwner?@"接听负责宿主":(AACSBRole==AACAnswerRoleObserver?@"观察者":@"仅日志"),AACSBClaimReasonText()]:[NSString stringWithFormat:@"%@ 运行时发现：候选类=%lu，但没有可挂钩或可调用的接听方法（跳过 %lu）；本宿主不可能接听（仅日志）%@；%@",AACSBDisplay(),(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBRejectedMethods,AACSBOwnerTag.length?[NSString stringWithFormat:@"，接听由 %@ 负责",AACSBOwnerTag]:@"",AACSBClaimReasonText()],@{@"discovered":@(AACSBAnswerPathCount()>0)});
}

/* ---- discovery ------------------------------------------------------------------------ */
/* Handles one candidate class: every method of it that matches the selector filter gets
   exactly one recorded outcome (HOOKED / INVOKABLE_BY_INVOCATION / SKIPPED+reason), so the
   discovery file alone tells the next device test what happened to every candidate. */
/* Installs one behaviour-neutral dynamic hook (thunk -> saved original IMP). Used for BOTH
   ACTION answer methods and ACCESSOR evidence hooks; the only difference is countsAsPath,
   which is what keeps accessors out of the answer-path count and out of the submission path.
   Returns YES only when a real original IMP was obtained and recorded. */
static BOOL AACSBInstallHook(Class cls,SEL selector,Method method,IMP current,IMP thunk,NSString *name,NSString *selectorName,NSString *abi,BOOL countsAsPath,NSString *classificationText){
 if(!cls||!selector||!method||!thunk)return NO;
 if(AACSBHookCount>=AACSBHookCap){
  AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=%@ reason=挂钩数量达到 %d 上限",selectorName,classificationText,AACSBHookCap]);
  return NO;
 }
 IMP original=NULL;
 NSString *mechanism=nil;
 AACMSHookMessageExFn hookFn=AACSBResolveMSHook();
 if(hookFn){
  @try{hookFn(cls,selector,thunk,&original);}
  @catch(NSException *e){original=NULL;AACSBLog([@"MSHookMessageEx exception: " stringByAppendingString:e.reason?:@"unknown"]);}
  mechanism=@"MSHookMessageEx（ElleKit/substrate 兼容层）";
 }else{
  original=method_setImplementation(method,thunk);
  mechanism=@"method_setImplementation（MSHookMessageEx 不可用时的回退，同样保存原始 IMP）";
 }
 if(!original||original==thunk){
  /* Roll back only when the mechanism allows it and says exactly what it replaced. */
  BOOL rolledBack=NO;
  if(!hookFn&&original==thunk){method_setImplementation(method,current);rolledBack=YES;}
  AACSBRejectedMethods++;
  AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=%@ reason=挂钩没有返回有效的原始 IMP 或检测到重复挂钩（mechanism=%@ rolledBack=%d）",selectorName,classificationText,mechanism?:@"none",rolledBack]);
  return NO;
 }
 AACSBHookRecords[AACSBHookCount].cls=cls;
 AACSBHookRecords[AACSBHookCount].sel=selector;
 AACSBHookRecords[AACSBHookCount].original=original;
 AACSBHookRecords[AACSBHookCount].countsAsPath=countsAsPath;
 AACSBHookCount++;
 [AACSBHookedKeys addObject:[NSString stringWithFormat:@"%@|%@",name,selectorName]];
 [AACSBHookedIMPs addObject:@((uintptr_t)current)];
 NSString *entry=[NSString stringWithFormat:@"-[%@ %@] abi=%@ classification=%@ countsAsPath=%@",name,selectorName,abi,classificationText,countsAsPath?@"yes":@"no"];
 [AACSBHookedSelectors addObject:entry];
 if(AACSBHookDetails)[AACSBHookDetails addObject:[NSString stringWithFormat:@"%@ mechanism=%@",entry,mechanism?:@"unknown"]];
 if(countsAsPath)AACSBHookActionCount++;else AACSBHookAccessorCount++;
 AACSBAppendDiscovery([NSString stringWithFormat:@"  HOOKED %@ classification=%@ countsAsPath=%@ abi=%@ mechanism=%@ originalIMP=%p",selectorName,classificationText,countsAsPath?@"yes":@"no",abi,mechanism,(void *)original]);
 return YES;
}
/* Handles one candidate class: every method of it that matches the selector filter gets exactly
   one recorded outcome with its 1.15.0 classification (ACTION / ACCESSOR / FORBIDDEN /
   UNSUPPORTED) plus HOOKED / INVOKABLE_BY_INVOCATION / SKIPPED+reason, so the discovery file
   alone tells the next device test what happened to every candidate. ONLY ACTION methods may
   become answer paths. */
static void AACSBHandleCandidateClass(Class cls,NSString *name,BOOL globalPass,NSUInteger *hooked,NSUInteger *invokable){
 unsigned int methodCount=0;
 Method *methods=class_copyMethodList(cls,&methodCount);
 AACSBAppendDiscovery([NSString stringWithFormat:@"CLASS %@ methods=%u pass=%@",name,methodCount,globalPass?@"global-call-scan":@"keyword"]);
 NSUInteger pickedHooks=0,pickedInvokable=0,pickedAccessors=0;
 if(methods){
  for(unsigned int j=0;j<methodCount;j++){
   SEL selector=method_getName(methods[j]);
   const char *rawSelector=selector?sel_getName(selector):NULL;
   if(!rawSelector)continue;
   NSString *selectorName=[NSString stringWithUTF8String:rawSelector];
   if(!AACSBSelectorMatches(selectorName,globalPass))continue;
   if(pickedHooks+pickedInvokable>=AACSBSelectorCap){AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ reason=该类候选方法达到 %d 上限，其余不再处理",selectorName,AACSBSelectorCap]);break;}
   Method method=methods[j];
   unsigned int arguments=method_getNumberOfArguments(method);
   char returnType[64]={0};
   method_getReturnType(method,returnType,sizeof(returnType));
   IMP current=method_getImplementation(method);
   /* 1.15.0 TASK 2: classify FIRST. Only ACTION may set answerPaths or reach a submission path. */
   NSString *classReason=nil;
   AACSBClassification classification=AACSBClassifySelector(cls,selectorName,arguments,&classReason);
   NSString *classText=AACSBClassificationText(classification);
   NSString *forbidden=AACSBForbiddenKeyword(selectorName);
   if(classification==AACSBClassificationForbidden){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=FORBIDDEN reason=拒绝/挂断类关键字（%@）：绝不挂钩也绝不调用，也不作为接听路径",selectorName,forbidden?:@"匹配"]);
    continue;
   }
   if(AACSBSelectorIsARCUnsafe(selectorName)){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=%@ reason=ARC 方法族（init/new/copy/mutableCopy/alloc 风格的首个选择器段）：返回值所有权约定由调用方假定，thunk 不能安全直通",selectorName,classText]);
    continue;
   }
   if(arguments<2){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=%@ reason=参数数量=%u 小于 2（类型编码异常）",selectorName,classText,arguments]);
    continue;
   }
   if(classification==AACSBClassificationUnsupported){
    AACSBUnsupportedSkipped++;
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=UNSUPPORTED reason=%@；关键字命中但不是真实接听动作：不挂钩、不登记、answerPaths 不会因此增加",selectorName,classReason?:@"不是接听动作"]);
    continue;
   }
   if(classification==AACSBClassificationAccessor){
    /* 1.15.0 TASK 2: an accessor is evidence only. It is hooked ONLY when the existing safe
       zero-argument ABI applies and only as a behaviour-neutral capture; it is NEVER counted as
       an answer path, NEVER registered as an NSInvocation candidate, and NEVER the object the
       answer step acts on (AACSBOriginalForAnswer / AACSBMatchedCandidateClass / AACSBCapture). */
    NSString *abi=nil;
    IMP thunk=(arguments==2)?AACSBThunkForReturnType(returnType,&abi):NULL;
    if(!thunk||AACSBIsOurThunk(current)||current==(IMP)thunk){
     AACSBAccessorSkipped++;
     AACSBRejectedMethods++;
     AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACCESSOR countsAsPath=no reason=%@；属性访问器无法接听：本版本不挂钩、也不登记为 NSInvocation 候选（有显式参数或无安全 thunk 时直接跳过）",selectorName,classReason?:@"属性访问器"]);
     continue;
    }
    NSString *key=[NSString stringWithFormat:@"%@|%@",name,selectorName];
    if([AACSBHookedKeys containsObject:key]){AACSBAppendDiscovery([NSString stringWithFormat:@"  ALREADY_HOOKED %@ classification=ACCESSOR countsAsPath=no reason=同一 (类,方法) 只挂钩一次",selectorName]);continue;}
    if(current&&[AACSBHookedIMPs containsObject:@((uintptr_t)current)]){
     AACSBRejectedMethods++;
     AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACCESSOR countsAsPath=no reason=同一 IMP 已在别处挂钩（绝不重复挂钩）",selectorName]);
     continue;
    }
    if(AACSBInstallHook(cls,selector,method,current,thunk,name,selectorName,abi,NO,classText))pickedAccessors++;
    continue;
   }
   /* ---- classification == ACTION from here on: this is the only branch that may produce an
      answer path. ---- */
   if(arguments>2){
    NSString *why=nil;
    if(!AACSBMethodInvocationSafe(method,&why)){
     AACSBInvokableSkipped++;AACSBRejectedMethods++;
     AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACTION reason=NSInvocation 候选也不安全：%@",selectorName,why?:@"未知"]);
     continue;
    }
    NSString *key=[NSString stringWithFormat:@"inv|%@|%@",name,selectorName];
    if([AACSBInvocationKeys containsObject:key]){AACSBAppendDiscovery([NSString stringWithFormat:@"  ALREADY_REGISTERED %@ reason=同一方法只登记一次",selectorName]);continue;}
    if(AACSBInvocationCount>=AACSBInvocationCap){AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ reason=参数化候选达到 %d 上限",selectorName,AACSBInvocationCap]);continue;}
    AACSBInvocationRecords[AACSBInvocationCount].cls=cls;
    AACSBInvocationRecords[AACSBInvocationCount].sel=selector;
    AACSBInvocationRecords[AACSBInvocationCount].countsAsPath=YES;
    AACSBInvocationCount++;
    AACSBInvokableActionCount++;
    [AACSBInvocationKeys addObject:key];
    NSString *entry=[NSString stringWithFormat:@"-[%@ %@] args=%u return=%s classification=ACTION countsAsPath=yes",name,selectorName,arguments-2,returnType];
    [AACSBInvokableSelectors addObject:entry];
    pickedInvokable++;(*invokable)++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  INVOKABLE_BY_INVOCATION %@ classification=ACTION countsAsPath=yes reason=有显式参数，任意 ABI 不能用固定 C thunk 安全直通；接听步骤会在活实例上用 NSInvocation 以默认参数调用，并把结果写成 INVOKED_BY_INVOCATION 行",entry]);
    continue;
   }
   NSString *abi=nil;
   IMP thunk=AACSBThunkForReturnType(returnType,&abi);
   if(!thunk){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACTION reason=零显式参数但返回类型=%s 不能用固定签名 thunk 直通",selectorName,returnType]);
    continue;
   }
   if(AACSBIsOurThunk(current)){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACTION reason=该实现已经是本插件的挂钩（绝不重复挂钩）",selectorName]);
    continue;
   }
   NSString *key=[NSString stringWithFormat:@"%@|%@",name,selectorName];
   if([AACSBHookedKeys containsObject:key]){AACSBAppendDiscovery([NSString stringWithFormat:@"  ALREADY_HOOKED %@ reason=同一 (类,方法) 只挂钩一次",selectorName]);continue;}
   if(current&&[AACSBHookedIMPs containsObject:@((uintptr_t)current)]){
    AACSBRejectedMethods++;
    AACSBAppendDiscovery([NSString stringWithFormat:@"  SKIPPED %@ classification=ACTION reason=同一 IMP 已在别处挂钩（绝不重复挂钩）",selectorName]);
    continue;
   }
   if(AACSBInstallHook(cls,selector,method,current,thunk,name,selectorName,abi,YES,classText)){pickedHooks++;(*hooked)++;}
  }
  free(methods);
 }
 AACSBAppendDiscovery([NSString stringWithFormat:@"  hooked=%lu invokable=%lu accessors=%lu pass=%@",(unsigned long)pickedHooks,(unsigned long)pickedInvokable,(unsigned long)pickedAccessors,globalPass?@"global-call-scan":@"keyword"]);
}
static void AACSBDiscover(void){
 if(AACSBDiscoverRuns>=AACSBMaxDiscoverRuns)return;
 AACSBDiscoverRuns++;
 if(!AACSBHookedKeys)AACSBHookedKeys=[NSMutableSet new];
 if(!AACSBHookedIMPs)AACSBHookedIMPs=[NSMutableSet new];
 if(!AACSBInvocationKeys)AACSBInvocationKeys=[NSMutableSet new];
 if(!AACSBDiscoveryLines)AACSBDiscoveryLines=[NSMutableArray new];
 if(!AACSBHookedSelectors)AACSBHookedSelectors=[NSMutableArray new];
 if(!AACSBInvokableSelectors)AACSBInvokableSelectors=[NSMutableArray new];
 if(!AACSBHookDetails)AACSBHookDetails=[NSMutableArray new];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# AutoAnswerCall 1.15.0 answer-host runtime discovery run %lu host=%@ tag=%@ (runtime-discovered; no hardcoded class name)",(unsigned long)AACSBDiscoverRuns,AACSBDisplay(),AACSBProcess()]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# discoveryFile=%@ roleTable=%@",AACSBHostDiscoveryFile(),AACAnswerRoleTableText()]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# classFamilyFilters=%@（真实来电 UI 类族，通配匹配）",[AACSBClassFamilyPatterns() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# realActionSelectorPatterns=%@（只有命中这些模式的候选才算 ACTION，才能成为接听路径）",[AACSBSelectorActionPatterns() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# process=%@ date=%@",AACSBProcess(),NSDate.date]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# classFilters=%@",[AACSBClassKeywords() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# selectorFilters=%@（全局扫描用严格子集，不含裸 accept）",[AACSBSelectorKeywords() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# selectorForbidden=%@（安全黑名单：拒绝/挂断类选择器永不挂钩、永不登记、永不调用）",[AACSBSelectorForbidden() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:@"# 1.15.0 分类（每个候选都必须有其中一个，且只有 ACTION 会增加 answerPaths）：ACTION=真实接听动作（命中 realActionSelectorPatterns）；ACCESSOR=属性访问器（set<Name>: 或镜像 setter 的 has<Name>/is<Name>/<Name>），只作证据，永不作为接听路径；FORBIDDEN=拒绝/挂断类；UNSUPPORTED=关键字命中但不是接听动作（XPC/通知回调等）。设备证据：1.14.0 的四个 HOOKED 全是访问器（answeredCall / hasAnsweredCall / answeredCall / acceptButton），却把 answerPaths 撑成了 role=OWNER。"];
 [AACSBDiscoveryLines addObject:@"# 每个候选方法的处置（本文件是下一次设备测试的判定依据）：HOOKED=已挂钩（零显式参数+返回类型可直通，已保存原始 IMP 并原样直通；ACCESSOR 挂钩只用于捕获证据，countsAsPath=no）；INVOKABLE_BY_INVOCATION=未挂钩，接听步骤可用 NSInvocation 传默认参数调用（仅 ACTION）；CAPTURED/CAPTURED_ACCESSOR=看到活实例；INVOKED_BY_INVOCATION=接听步骤真的调用了；SKIPPED=带具体原因跳过。"];
 [AACSBDiscoveryLines addObject:@"# 挂钩机制：MSHookMessageEx（ElleKit/substrate 兼容层，dlsym 解析）优先，不可用时回退 method_setImplementation；两种机制都保存原始 IMP 并依赖 (类,方法) 与 IMP 双重键避免重复挂钩。"];
 int total=objc_getClassList(NULL,0);
 if(total<=0){
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# objc_getClassList 返回 %d，没有枚举到任何运行时类",total]];
  AACSBWriteDiscoveryFile();
  return;
 }
 size_t capacity=(size_t)total+64;
 Class *classes=(Class *)calloc(capacity,sizeof(Class));
 if(!classes){
  [AACSBDiscoveryLines addObject:@"# 类缓冲分配失败，本次发现放弃（接听路径保持仅日志）"];
  AACSBWriteDiscoveryFile();
  return;
 }
 int count=objc_getClassList(classes,(int)capacity);
 if(count<=0)count=0;
 NSUInteger matched=0,hookedPass1=0,invokablePass1=0;
 for(int i=0;i<count;i++){
  if(matched>=AACSBClassCap){[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# 候选类达到 %d 上限，提前结束关键字枚举",AACSBClassCap]];break;}
  const char *raw=class_getName(classes[i]);
  if(!raw)continue;
  NSString *name=[NSString stringWithUTF8String:raw];
  if(!name.length||!AACSBClassMatches(name))continue;
  matched++;
  AACSBHandleCandidateClass(classes[i],name,NO,&hookedPass1,&invokablePass1);
  if(AACSBDiscoveryLines.count>3000){[AACSBDiscoveryLines addObject:@"# 摘要行数达上限，后续候选不再逐行记录"];break;}
 }
 AACSBMatchedClasses+=matched;
 AACSBAppendDiscovery([NSString stringWithFormat:@"# end keyword pass scanned=%d matchedClasses=%lu hooked=%lu invokable=%lu",count,(unsigned long)matched,(unsigned long)hookedPass1,(unsigned long)invokablePass1]);
 /* Fallback pass: if the keyword pass produced NO answer path at all, scan every runtime
    class whose NAME contains "call" with the strict selector set. This is the pass that is
    most likely to find the real iOS 17 answer entry, and it stays bounded by a processed
    class cap and by stopping as soon as enough answer paths exist. */
 if(AACSBAnswerPathCount()==0){
  NSUInteger hookedPass2=0,invokablePass2=0,processed=0;
  CFAbsoluteTime globalStarted=CFAbsoluteTimeGetCurrent();
  AACSBAppendDiscovery(@"# 关键字枚举没有产生任何接听路径：开始全局扫描（类名含 call，严格选择器子集；有 1.5 秒时间预算，超时安全停止以免阻塞宿主进程）");
  for(int i=0;i<count;i++){
   double globalElapsed=CFAbsoluteTimeGetCurrent()-globalStarted;
   if(globalElapsed>1.5){AACSBAppendDiscovery([NSString stringWithFormat:@"# 全局扫描用时 %.2f 秒超过 1.5 秒预算，安全停止（尚未处理的类不在本文件内）",globalElapsed]);break;}
   if(processed>=AACSBGlobalClassCap){AACSBAppendDiscovery([NSString stringWithFormat:@"# 全局扫描达到 %lu 个类的上限，停止（未找到的类不在本文件内）",(unsigned long)AACSBGlobalClassCap]);break;}
   const char *raw=class_getName(classes[i]);
   if(!raw)continue;
   NSString *name=[NSString stringWithUTF8String:raw];
   if(!name.length||AACSBClassMatches(name)||!AACSBClassMatchesGlobal(name))continue;
   processed++;
   AACSBGlobalScanned++;
   AACSBHandleCandidateClass(classes[i],name,YES,&hookedPass2,&invokablePass2);
   if(AACSBAnswerPathCount()>=8){AACSBAppendDiscovery(@"# 全局扫描已获得 8 条接听路径，停止以保持发现文件可读");break;}
   if(AACSBDiscoveryLines.count>3000){AACSBAppendDiscovery(@"# 摘要行数达上限，全局扫描提前结束");break;}
  }
  AACSBAppendDiscovery([NSString stringWithFormat:@"# end global pass processedClasses=%lu hooked=%lu invokable=%lu elapsedSeconds=%.2f",(unsigned long)processed,(unsigned long)hookedPass2,(unsigned long)invokablePass2,CFAbsoluteTimeGetCurrent()-globalStarted]);
 }
 free(classes);
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# end run %lu scanned=%d matchedClasses=%lu hookedMethods=%lu (action=%lu accessor=%lu) invokable=%lu (action=%lu) rejected=%lu accessorSkipped=%lu unsupportedSkipped=%lu answerPaths=%lu",(unsigned long)AACSBDiscoverRuns,count,(unsigned long)matched,(unsigned long)AACSBHookCount,(unsigned long)AACSBHookActionCount,(unsigned long)AACSBHookAccessorCount,(unsigned long)AACSBInvocationCount,(unsigned long)AACSBInvokableActionCount,(unsigned long)AACSBRejectedMethods,(unsigned long)AACSBAccessorSkipped,(unsigned long)AACSBUnsupportedSkipped,(unsigned long)AACSBAnswerPathCount()]];
 AACSBWriteDiscoveryFile();
}
static inline void AACSBRetryDiscoveryIfEmpty(void);
static inline void AACSBStart(AACSBEnv *env){
 AACSBEnvShared=env;
 AACSBHostTag=AACSBHost()[@"tag"];AACSBHostDisplay=AACSBDisplay();
 @try{AACSBDiscover();}@catch(NSException *e){AACSBLog([@"discovery exception: " stringByAppendingString:e.reason?:@"unknown"]);AACSBRecord(@"运行时发现异常：接听路径退化为仅日志",@{@"discovered":@NO});}
 AACSBRecomputeRole();
 if(AACSBRole==AACAnswerRoleOwner){
  /* Announce ownership once so lower-priority hosts can yield deterministically. 1.14.0: a
     claim is posted ONLY here, i.e. only by a host that decided it is the OWNER because its own
     runtime discovery really found answer paths. That is exactly why a CLAIM may take the
     answer away from another host while a probe (which proves nothing but process existence and
     is also sent by hosts that found nothing) may never do so. */
  uint32_t claim=AACAnswerPostOwnerClaim(AACSBProcess());
  AACSBLog([NSString stringWithFormat:@"%@ 已在 %@ 上广播接听归属声明（post=%u；Darwin 通知无载荷，只断言到达；只有 OWNER 才广播归属声明）",AACSBDisplay(),AACAnswerOwnerClaimName(AACSBProcess()),claim]);
 }else{
  AACSBLog([NSString stringWithFormat:@"%@ 未广播接听归属声明（role=%@，owner=%@）：没有归属声明的宿主不可能让更高优先级宿主让出接听",AACSBDisplay(),AACSBRole==AACAnswerRoleObserver?@"OBSERVER":@"LOG-ONLY",AACSBHostOwnerTagText()]);
 }
 AACSBLog(AACSBAnswerOwnershipLine(nil,NO,@"启动时的归属判定（还没有任何通话）"));
 /* 1.15.0 TASK 1: keep the shared host report fresh (discovery summary + recent log lines)
    for every host, so the Settings process and the other hosts have a chance to read what a
    host that lives in its own container actually found. */
 AACHostReportEnablePeriodic(AACSBProcess(),^NSString *{return AACSBHostReportSummary();});
 /* 1.13.0: the real call UI classes are often registered AFTER this dylib's constructor, so
    repeat the bounded enumeration on a timer as well as on a call event. This is how the
    relaxed gate gets a second chance without an unbounded scan. */
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{AACSBRetryDiscoveryIfEmpty();});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(12.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{AACSBRetryDiscoveryIfEmpty();});
}
/* A call arrived and we still have nothing hooked: the class list can grow after other
   frameworks load, so retry the enumeration a bounded number of times. */
static inline void AACSBRetryDiscoveryIfEmpty(void){
 if(AACSBAnswerPathCount())return;
 if(AACSBDiscoverRuns>=AACSBMaxDiscoverRuns)return;
 AACSBLog(@"no dynamic hook / invocation candidate discovered yet; re-running the runtime enumeration because a call or timer event arrived");
 @try{AACSBDiscover();}@catch(NSException *e){AACSBLog([@"discovery retry exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
