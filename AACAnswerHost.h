#import <Foundation/Foundation.h>
#import <notify.h>
/* Answer-host table + single-owner arbitration (1.12.0).
   Background: on this iOS 17.3 RootHide device the SpringBoard module demonstrably loads
   and answers Darwin probes, while the phone app process (com.apple.mobilephone) never
   announced itself at all. On modern iOS the actual in-call / incoming-call UI is hosted
   by InCallService, so 1.12.0 generalises the 1.11.0 SpringBoard-only machinery into a
   host-parameterised answer module and adds an InCallService host.

   EVERY host may OBSERVE and RECORD, but the ANSWER action is performed by exactly ONE
   host. Ownership is decided deterministically from a static role table (priority) plus
   observed host liveness, and it is re-evaluated immediately before an answer is
   submitted:
     - a host that discovered no hookable answer method is LOG-ONLY (observer);
     - of the answer-capable hosts, the HIGHEST priority one whose discovery found a
       hookable answer method performs the answer;
     - every other answer-capable host records "observer only, answer owned by <host>"
       and never submits an answer;
     - a per-host set of already-submitted call UUIDs makes a double submission for the
       same UUID impossible even if ownership is recomputed mid-call.
   Liveness of a higher-priority host is evidence-based: the probe notifications of
   1.10.0/1.11.0 are proven to cross process boundaries on this device (SpringBoard's
   probes arrived in Settings), so a probe arrival within AACAnswerPresenceFreshSeconds
   is treated as "that host is present". A host also broadcasts an ownership claim on
   com.autoanswer.call.owner.<tag> when it decides to own the answer, and a lower-priority
   host yields to any higher-priority claim it has seen. Cross-process visibility of any
   file path is NOT claimed anywhere.

   1.14.0 OWNERSHIP DEMOTION FIX — a probe is NOT ownership. Device evidence (the user's
   real SpringBoard shared log, 2026-10-16, quoted verbatim because it is the authoritative
   record):
     - 1.12.0 run:  matchedClasses=103 hookedMethods=0 rejected=8 role=OBSERVER
       => the old narrow hook ABI gate really did block everything.
     - 1.13.0 run @14:03:05:  matchedClasses=150 hookedMethods=4 invokable=5 rejected=0
       role=OWNER  => the relaxed gate WORKS; real answer-path methods are now
       hooked/invokable in SpringBoard.
     - real incoming call @14:05:08 was detected (Call 908FA104-... outgoing=0 connected=0
       ended=0) and the configured 6 s delay was scheduled correctly.
     - BUT @14:05:09 the host re-evaluated ownership and DEMOTED ITSELF:
       "SpringBoard 接听归属角色：OBSERVER 仅观察与记录（观察者：接听由 InCallService 负责
        （incall 的探测通知在 90 秒内到达过本进程（存活证据））；本宿主只观察并记录）"
       followed by "observer only, answer owned by incall".
     - the call was never answered; InCallService never acted (its own host found nothing /
       never submitted); @14:05:30 "Answer request observation timeout"; @14:05:36 the call
       ended.
   ROOT CAUSE: the demotion trigger was PEER PROBE PRESENCE — a probe seen within 90 s was
   treated as proof that the peer would answer. A probe proves only that the peer PROCESS
   exists. It does not prove that the peer found a hookable answer path (a host whose
   discovery found nothing never posts a claim at all), that it claims ownership, or that it
   will submit. So 1.13.0 handed the answer to a host that could not answer, and the host
   that COULD answer went silent.
   1.14.0 RULE: a host demotes ONLY when a strictly higher-priority answer host has actually
   broadcast an explicit ownership claim (com.autoanswer.call.owner.<tag>) AND that claim is
   still inside the bounded AACAnswerClaimFreshSeconds window. Probe presence alone NEVER
   demotes (it is reported inside the reason text as presence-only evidence, and says so).
   A host that holds answer paths and sees no higher-priority CLAIM stays OWNER and really
   submits at the end of its delay. When a higher-priority host does claim but then never
   submits/never produces a connection, the lower host may take over exactly once per call
   UUID (AACAnswerTakeoverIdleSeconds after its own delay expired); that takeover still goes
   through the same per-UUID single-submission claim, so no UUID is ever submitted twice by
   this host. Every decision carries a durable reason string in AACSBRoleReason / Root
   reason= so the shared log states exactly why a host is OWNER or OBSERVER. */

typedef NS_ENUM(NSInteger,AACAnswerRole){
 AACAnswerRoleLogOnly=0, /* this host cannot answer at all in this build */
 AACAnswerRoleObserver=1,
 AACAnswerRoleOwner=2
};

static NSString * const AACAnswerOwnerClaimPrefix=@"com.autoanswer.call.owner.";
/* The per-host probe interval is 20 s; anything older than this is stale PRESENCE evidence.
   Presence is reporting-only since 1.14.0: it never demotes anybody. */
static NSTimeInterval const AACAnswerPresenceFreshSeconds=90.0;
/* 1.14.0: an EXPLICIT ownership claim is honoured only inside this bounded window. A claim is
   the ONLY thing that can take the answer away from a host that holds answer paths. */
static NSTimeInterval const AACAnswerClaimFreshSeconds=90.0;
/* 1.14.0: bounded idle window used by the safety takeover. If a higher-priority host claimed
   ownership but produced no submission/no connection within this many seconds AFTER our own
   delay expired, the lower host may take over once for that call UUID. */
static NSTimeInterval const AACAnswerTakeoverIdleSeconds=12.0;
/* Short window used before the answer step to give a higher-priority owner the one
   run-loop chance to win the arbitration. */
static NSTimeInterval const AACAnswerOwnerHandshakeSeconds=0.4;

/* Host table: {bundle id, process name, probe name, pong name, discovery file name}.
   SpringBoard keeps its 1.11.0 probe/pong names and its discovery file name so nothing
   regresses; InCallService gets its own names. The lowercase-only rule applies to the
   phone id: the filter ships com.apple.mobilephone (and never com.apple.MobilePhone),
   while the runtime match stays case-insensitive for MobilePhone/InCallService variants. */
static inline NSArray *AACAnswerHostTable(void){
 return @[
  @{@"tag":@"incall",@"display":@"InCallService",
    @"bundle":@"com.apple.InCallService",@"altBundle":@"com.apple.incallservice",
    @"process":@"InCallService",
    @"probe":@"com.autoanswer.call.probe.incall",
    @"pong":@"com.autoanswer.call.pong.incall",
    @"discovery":@"aac-incall.discovery.txt",
    @"priority":@2,@"answer":@YES},
  @{@"tag":@"springboard",@"display":@"SpringBoard",
    @"bundle":@"com.apple.springboard",@"altBundle":@"com.apple.SpringBoard",
    @"process":@"SpringBoard",
    @"probe":@"com.autoanswer.call.probe.springboard",
    @"pong":@"com.autoanswer.call.pong.springboard",
    @"discovery":@"aac-springboard.discovery.txt",
    @"priority":@1,@"answer":@YES},
  @{@"tag":@"mobilephone",@"display":@"MobilePhone",
    @"bundle":@"com.apple.mobilephone",@"altBundle":@"com.apple.MobilePhone",
    @"process":@"MobilePhone",
    @"probe":@"com.autoanswer.call.probe.mobilephone",
    @"pong":@"com.autoanswer.call.pong",
    @"discovery":@"",
    @"priority":@0,@"answer":@NO},
  @{@"tag":@"settings",@"display":@"Settings",
    @"bundle":@"",@"altBundle":@"",
    @"process":@"",
    @"probe":@"com.autoanswer.call.probe.settings",
    @"pong":@"",
    @"discovery":@"",
    @"priority":@0,@"answer":@NO}
 ];
}
static inline NSDictionary *AACAnswerHostByTag(NSString *tag){
 if(![tag isKindOfClass:NSString.class]||!tag.length)return nil;
 for(NSDictionary *host in AACAnswerHostTable())if([host[@"tag"] isEqualToString:tag])return host;
 return nil;
}
static inline NSArray *AACAnswerHostsAnswerCapable(void){
 NSMutableArray *out=[NSMutableArray new];
 for(NSDictionary *host in AACAnswerHostTable())if([host[@"answer"] boolValue])[out addObject:host];
 return out;
}
/* Deterministic role table, strongest first: InCallService > SpringBoard > log-only. */
static inline NSString *AACAnswerRoleTableText(void){return @"InCallService(2) > SpringBoard(1) > 仅日志(0)";}
static inline NSArray *AACAnswerHostsHigherPriority(NSString *tag){
 NSDictionary *self=AACAnswerHostByTag(tag);NSMutableArray *out=[NSMutableArray new];
 if(!self)return out;NSInteger priority=[self[@"priority"] integerValue];
 for(NSDictionary *host in AACAnswerHostsAnswerCapable())if([host[@"priority"] integerValue]>priority)[out addObject:host];
 return out;
}
/* Runtime host detection (bundle id first, then the process-name fallback, exactly like
   the 1.10.0/1.11.0 MobilePhone/SpringBoard pattern). Case-insensitive so the file-case
   variants of the InCall bundle id cannot silently disable the new host. */
static inline NSString *AACAnswerHostTagForBundle(NSString *bundle,NSString *process){
 NSString *b=[bundle isKindOfClass:NSString.class]?bundle:@"";
 NSString *p=[process isKindOfClass:NSString.class]?process:@"";
 for(NSDictionary *host in AACAnswerHostTable()){
  NSString *main=host[@"bundle"],*alt=host[@"altBundle"];
  if(main.length&&b.length&&[b caseInsensitiveCompare:main]==NSOrderedSame)return host[@"tag"];
  if(alt.length&&b.length&&[b caseInsensitiveCompare:alt]==NSOrderedSame)return host[@"tag"];
  NSString *procName=host[@"process"];
  if(procName.length&&p.length&&[p isEqualToString:procName])return host[@"tag"];
 }
 return nil;
}
static inline NSString *AACAnswerHostDiscoveryName(NSString *tag){
 NSDictionary *host=AACAnswerHostByTag(tag);NSString *name=host[@"discovery"];
 return [name isKindOfClass:NSString.class]&&name.length?name:nil;
}
/* Probe / ownership-claim notification names, used to observe the other hosts. */
static inline NSArray *AACAnswerProbeNames(void){
 NSMutableArray *out=[NSMutableArray new];
 for(NSDictionary *host in AACAnswerHostTable()){NSString *n=host[@"probe"];if(n.length)[out addObject:n];}
 return out;
}
static inline NSString *AACAnswerOwnerClaimName(NSString *tag){return [AACAnswerOwnerClaimPrefix stringByAppendingString:tag?:@"unknown"];}
static inline NSArray *AACAnswerOwnerClaimNames(void){
 NSMutableArray *out=[NSMutableArray new];
 for(NSDictionary *host in AACAnswerHostsAnswerCapable())[out addObject:AACAnswerOwnerClaimName(host[@"tag"])];
 return out;
}
/* Observed liveness/claim state. Header-only: exactly one translation unit (Tweak.x)
   includes this header, so the state is shared by all hosts in that process only. */
static NSMutableDictionary *AACAnswerProbeSeen=nil;
static NSMutableDictionary *AACAnswerClaimSeen=nil;
/* Two separate recorders instead of one helper taking &global: under ARC the address of a
   non-local object cannot be passed to an autoreleasing out-parameter. */
static inline void AACAnswerHostSeenProbe(NSString *tag){
 if(![tag isKindOfClass:NSString.class]||!tag.length)return;
 if(!AACAnswerProbeSeen)AACAnswerProbeSeen=[NSMutableDictionary new];
 @try{AACAnswerProbeSeen[tag]=NSDate.date;}@catch(NSException *e){}
}
static inline void AACAnswerHostSeenOwnerClaim(NSString *tag){
 if(![tag isKindOfClass:NSString.class]||!tag.length)return;
 if(!AACAnswerClaimSeen)AACAnswerClaimSeen=[NSMutableDictionary new];
 @try{AACAnswerClaimSeen[tag]=NSDate.date;}@catch(NSException *e){}
}
static inline NSDate *AACAnswerLastProbe(NSString *tag){id v=AACAnswerProbeSeen?AACAnswerProbeSeen[tag]:nil;return [v isKindOfClass:NSDate.class]?v:nil;}
static inline NSDate *AACAnswerLastOwnerClaim(NSString *tag){id v=AACAnswerClaimSeen?AACAnswerClaimSeen[tag]:nil;return [v isKindOfClass:NSDate.class]?v:nil;}
static inline BOOL AACAnswerFresh(NSDate *date,NSTimeInterval window){
 if(![date isKindOfClass:NSDate.class])return NO;
 return -[date timeIntervalSinceNow]<=window;
}
/* Why a higher-priority peer is considered present, or nil when it is not.
   1.14.0: this is a REPORTING/PRESENCE helper only. Its return value may never be used to
   demote a host that holds answer paths — see AACAnswerPeerClaimReason below, which is the
   only admission criterion for giving the answer away. */
static inline NSString *AACAnswerPeerPresenceReason(NSString *tag){
 if(AACAnswerFresh(AACAnswerLastProbe(tag),AACAnswerPresenceFreshSeconds))
  return [NSString stringWithFormat:@"%@ 的探测通知在 %.0f 秒内到达过本进程（存活证据）",tag,AACAnswerPresenceFreshSeconds];
 if(AACAnswerFresh(AACAnswerLastOwnerClaim(tag),AACAnswerPresenceFreshSeconds))
  return [NSString stringWithFormat:@"%@ 广播过接听归属声明",tag];
 return nil;
}
/* 1.14.0: the ONLY reason that may take the answer away from a host that holds answer paths:
   a fresh, EXPLICIT ownership claim from a strictly higher-priority answer host. The claim is
   a payload-less Darwin notification (arrival asserted only, never a payload), and it is only
   ever posted by a host that decided it is the owner — i.e. by a host whose own discovery DID
   find an answer path. A probe is deliberately not consulted here. */
static inline NSString *AACAnswerPeerClaimReason(NSString *tag){
 if(AACAnswerFresh(AACAnswerLastOwnerClaim(tag),AACAnswerClaimFreshSeconds))
  return [NSString stringWithFormat:@"%@ 在 %.0f 秒内广播过明确的接听归属声明（%@，无载荷，只断言到达；这与“探测到存在”不同）",tag,AACAnswerClaimFreshSeconds,AACAnswerOwnerClaimName(tag)];
 return nil;
}
/* 1.14.0: is a strictly higher-priority answer host asserting ownership RIGHT NOW (a real
   claim, not mere presence)? Returns the claiming tag + the durable reason. */
static inline BOOL AACAnswerHigherPriorityOwnerClaimed(NSString *tag,NSString **ownerTag,NSString **reason){
 if(ownerTag)*ownerTag=nil;
 if(reason)*reason=nil;
 if(!AACAnswerHostByTag(tag)){if(reason)*reason=@"本进程不在宿主表中：没有可比较的优先级";return NO;}
 for(NSDictionary *peer in AACAnswerHostsHigherPriority(tag)){
  NSString *claim=AACAnswerPeerClaimReason(peer[@"tag"]);
  if(claim){
   if(ownerTag)*ownerTag=peer[@"tag"];
   if(reason)*reason=claim;
   return YES;
  }
 }
 if(reason)*reason=[NSString stringWithFormat:@"没有更高优先级的接听宿主在 %.0f 秒内广播明确的接听归属声明；探测到存在只证明进程存在，不构成归属、也不触发让出或接管",AACAnswerClaimFreshSeconds];
 return NO;
}
/* Durable, log-ready explanation of a bounded takeover. */
static inline NSString *AACAnswerTakeoverReasonText(NSString *idleOwnerTag,NSString *claimReason){
 return [NSString stringWithFormat:@"takeover after idle higher-priority owner：%@ 广播过归属声明（%@），但本宿主自己的延时到期后又等待了 %.0f 秒，仍然没有观察到连接，也没有任何“已提交”的独立证据；本宿主手里确有可用的接听路径，因此对这个通话 UUID 接管一次（每个 UUID 最多一次，且仍然要经过同一套单次提交判定，绝不会出现同一 UUID 的两次提交）",idleOwnerTag.length?idleOwnerTag:@"更高优先级宿主",claimReason?:@"无说明",AACAnswerTakeoverIdleSeconds];
}
/* The single-owner decision. answerPaths==0 means this host's runtime discovery found no
   hookable/invokable answer method, i.e. it cannot answer even if it wanted to. */
static inline AACAnswerRole AACAnswerHostRoleForTag(NSString *tag,NSUInteger answerPaths,NSString **reason,NSString **ownerTag){
 if(ownerTag)*ownerTag=nil;
 NSDictionary *host=AACAnswerHostByTag(tag);
 if(!host){if(reason)*reason=[NSString stringWithFormat:@"本进程不在宿主表中（tag=%@）：不观察也不接听",tag?:@"(nil)"];return AACAnswerRoleLogOnly;}
 if(![host[@"answer"] boolValue]){
  if(reason)*reason=[NSString stringWithFormat:@"%@ 不是接听宿主（角色表：%@）；仅记录接听相关的观察结果",host[@"display"],AACAnswerRoleTableText()];
  return AACAnswerRoleLogOnly;
 }
 if(answerPaths==0){
  if(reason)*reason=[NSString stringWithFormat:@"%@ 发现的可挂钩/可调用接听路径=0：观察并记录，但退化为仅日志，不执行接听",host[@"display"]];
  return AACAnswerRoleObserver;
 }
 /* 1.14.0: only an EXPLICIT, fresh, higher-priority ownership claim demotes us. */
 for(NSDictionary *peer in AACAnswerHostsHigherPriority(tag)){
  NSString *claim=AACAnswerPeerClaimReason(peer[@"tag"]);
  if(claim){
   if(ownerTag)*ownerTag=peer[@"tag"];
   if(reason)*reason=[NSString stringWithFormat:@"观察者：接听由 %@ 负责（%@）；本宿主只观察并记录（只有明确归属声明能让本宿主让出接听，探测到存在不算）",peer[@"display"],claim];
   return AACAnswerRoleObserver;
  }
 }
 /* No higher-priority CLAIM: we keep ownership. Presence is still reported, and the reason
    states explicitly that presence is not an ownership basis. */
 NSString *presence=nil;
 for(NSDictionary *peer in AACAnswerHostsHigherPriority(tag)){
  NSString *why=AACAnswerPeerPresenceReason(peer[@"tag"]);
  if(why){presence=[NSString stringWithFormat:@"%@（仅存活证据：只证明该进程存在，不构成归属、也不代表它会接听，因此不触发让出）",why];break;}
 }
 if(reason)*reason=[NSString stringWithFormat:@"接听负责宿主：%@ 持有 %lu 条运行时发现的接听路径（HOOKED/INVOKABLE），且 %.0f 秒内没有任何更高优先级的接听宿主广播过明确的接听归属声明%@（角色表 %@）",host[@"display"],(unsigned long)answerPaths,AACAnswerClaimFreshSeconds,presence?[NSString stringWithFormat:@"；观察到 %@",presence]:@"；也没有观察到更高优先级宿主存在",AACAnswerRoleTableText()];
 return AACAnswerRoleOwner;
}
/* Human-readable presence snapshot for the discovery file and the log. 1.14.0: the claim
   part is separated from the probe part and marked as the only ownership-relevant evidence. */
static inline NSString *AACAnswerPresenceText(void){
 NSMutableArray *parts=[NSMutableArray new];
 for(NSDictionary *host in AACAnswerHostTable()){
  NSDate *probe=AACAnswerLastProbe(host[@"tag"]);NSDate *claim=AACAnswerLastOwnerClaim(host[@"tag"]);
  NSString *probeText=probe?[NSString stringWithFormat:@"探测 %.0f 秒前（仅存在证据，不构成归属）",-[probe timeIntervalSinceNow]]:@"探测未观察到";
  NSString *claimText=claim?[NSString stringWithFormat:@"、归属声明 %.0f 秒前%@（%.0f 秒窗口外即失效）",-[claim timeIntervalSinceNow],AACAnswerFresh(claim,AACAnswerClaimFreshSeconds)?@"（仍有效）":@"（已过期）",AACAnswerClaimFreshSeconds]:@"、无归属声明";
  [parts addObject:[NSString stringWithFormat:@"%@{%@%@}",host[@"tag"],probeText,claimText]];
 }
 return [parts componentsJoinedByString:@" "];
}
/* Broadcast an ownership claim (best effort: Darwin notifications carry no payload, so
   one notification name per host is used and nothing but the arrival is asserted). */
static inline uint32_t AACAnswerPostOwnerClaim(NSString *tag){
 uint32_t status=NOTIFY_STATUS_FAILED;
 @try{status=notify_post(AACAnswerOwnerClaimName(tag).UTF8String);}@catch(NSException *e){}
 return status;
}
