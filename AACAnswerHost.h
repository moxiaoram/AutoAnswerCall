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
   file path is NOT claimed anywhere. */

typedef NS_ENUM(NSInteger,AACAnswerRole){
 AACAnswerRoleLogOnly=0, /* this host cannot answer at all in this build */
 AACAnswerRoleObserver=1,
 AACAnswerRoleOwner=2
};

static NSString * const AACAnswerOwnerClaimPrefix=@"com.autoanswer.call.owner.";
/* The per-host probe interval is 20 s; anything older than this is stale evidence. */
static NSTimeInterval const AACAnswerPresenceFreshSeconds=90.0;
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
static inline void AACAnswerRemember(NSMutableDictionary **table,NSString *key){
 if(![key isKindOfClass:NSString.class]||!key.length)return;
 if(!*table)*table=[NSMutableDictionary new];
 @try{(*table)[key]=NSDate.date;}@catch(NSException *e){}
}
static inline void AACAnswerHostSeenProbe(NSString *tag){AACAnswerRemember(&AACAnswerProbeSeen,tag);}
static inline void AACAnswerHostSeenOwnerClaim(NSString *tag){AACAnswerRemember(&AACAnswerClaimSeen,tag);}
static inline NSDate *AACAnswerLastProbe(NSString *tag){id v=AACAnswerProbeSeen?AACAnswerProbeSeen[tag]:nil;return [v isKindOfClass:NSDate.class]?v:nil;}
static inline NSDate *AACAnswerLastOwnerClaim(NSString *tag){id v=AACAnswerClaimSeen?AACAnswerClaimSeen[tag]:nil;return [v isKindOfClass:NSDate.class]?v:nil;}
static inline BOOL AACAnswerFresh(NSDate *date,NSTimeInterval window){
 if(![date isKindOfClass:NSDate.class])return NO;
 return -[date timeIntervalSinceNow]<=window;
}
/* Why a higher-priority peer is considered present, or nil when it is not. */
static inline NSString *AACAnswerPeerPresenceReason(NSString *tag){
 if(AACAnswerFresh(AACAnswerLastProbe(tag),AACAnswerPresenceFreshSeconds))
  return [NSString stringWithFormat:@"%@ 的探测通知在 %.0f 秒内到达过本进程（存活证据）",tag,AACAnswerPresenceFreshSeconds];
 if(AACAnswerFresh(AACAnswerLastOwnerClaim(tag),AACAnswerPresenceFreshSeconds))
  return [NSString stringWithFormat:@"%@ 广播过接听归属声明",tag];
 return nil;
}
/* The single-owner decision. selfDiscoveredHooks==NO means this host's runtime discovery
   found no hookable answer method, i.e. it cannot answer even if it wanted to. */
static inline AACAnswerRole AACAnswerHostRoleForTag(NSString *tag,BOOL selfDiscoveredHooks,NSString **reason,NSString **ownerTag){
 if(ownerTag)*ownerTag=nil;
 NSDictionary *host=AACAnswerHostByTag(tag);
 if(!host){if(reason)*reason=@"本进程不在宿主表中：不观察也不接听";return AACAnswerRoleLogOnly;}
 if(![host[@"answer"] boolValue]){
  if(reason)*reason=[NSString stringWithFormat:@"%@ 不是接听宿主（角色表：%@）；仅记录接听相关的观察结果",host[@"display"],AACAnswerRoleTableText()];
  return AACAnswerRoleLogOnly;
 }
 if(!selfDiscoveredHooks){
  if(reason)*reason=[NSString stringWithFormat:@"%@ 发现的可挂钩接听方法=0：观察并记录，但退化为仅日志，不执行接听",host[@"display"]];
  return AACAnswerRoleObserver;
 }
 for(NSDictionary *peer in AACAnswerHostsHigherPriority(tag)){
  NSString *presence=AACAnswerPeerPresenceReason(peer[@"tag"]);
  if(presence){
   if(ownerTag)*ownerTag=peer[@"tag"];
   if(reason)*reason=[NSString stringWithFormat:@"观察者：接听由 %@ 负责（%@）；本宿主只观察并记录",peer[@"display"],presence];
   return AACAnswerRoleObserver;
  }
 }
 if(reason)*reason=[NSString stringWithFormat:@"接听负责宿主：%@ 发现了可挂钩方法且更高优先级的接听宿主未出现（角色表 %@）",host[@"display"],AACAnswerRoleTableText()];
 return AACAnswerRoleOwner;
}
/* Human-readable presence snapshot for the discovery file and the log. */
static inline NSString *AACAnswerPresenceText(void){
 NSMutableArray *parts=[NSMutableArray new];
 for(NSDictionary *host in AACAnswerHostTable()){
  NSDate *probe=AACAnswerLastProbe(host[@"tag"]);NSDate *claim=AACAnswerLastOwnerClaim(host[@"tag"]);
  NSString *probeText=probe?[NSString stringWithFormat:@"探测 %.0f 秒前",-[probe timeIntervalSinceNow]]:@"探测未观察到";
  NSString *claimText=claim?@"、有归属声明":@"";
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
