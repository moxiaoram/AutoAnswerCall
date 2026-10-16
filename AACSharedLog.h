#import <Foundation/Foundation.h>
/* Shared-log EVIDENCE channel (1.11.0): also carries the per-node discovery text file.
   Every injected process (MobilePhone, SpringBoard) and the Settings process use this
   header. No cross-process writable path is verified on RootHide, so this file does
   NOT claim one: it tries a list of real absolute candidate paths in order, keeps the
   first one that is actually writable IN THIS PROCESS, logs which one was chosen, and
   reports the per-path result of every candidate to the Settings log viewer.
   Write failures never throw out of here; the CFPreferences domain below is the last
   resort and its cross-process visibility is explicitly NOT claimed. */
static NSString * const AACSharedLogDomain=@"com.autoanswer.call.sharelog";
/* Owned by this tweak (not an Apple domain); companion records for Darwin probes. */
static NSString * const AACProbeCompanionDomain=@"com.autoanswer.call.probe";
static NSUInteger const AACSharedLogMaxBytes=240000;
static NSUInteger const AACSharedLogKeepBytes=120000;
static NSUInteger const AACSharedPrefsLogLimit=24000;

static inline NSArray *AACSharedLogCandidateDirs(void){
 NSMutableArray *out=[NSMutableArray new];
 NSString *container=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject?:@"" stringByAppendingPathComponent:@"AutoAnswerCall"];
 NSString *temp=[NSTemporaryDirectory()?:@"" stringByAppendingPathComponent:@"AutoAnswerCall"];
 NSArray *pairs=@[
  @[@"var-mobile",@"/var/mobile/Library/Application Support/AutoAnswerCall"],
  @[@"jb-var-mobile",@"/var/jb/var/mobile/Library/Application Support/AutoAnswerCall"],
  @[@"container-appsupport",container],
  @[@"nstemporary",temp],
  @[@"tmp",@"/tmp/AutoAnswerCall"]
 ];
 for(NSArray *pair in pairs){if(![pair[1] isKindOfClass:NSString.class]||![pair[1] length])continue;[out addObject:@{@"label":pair[0],@"dir":pair[1]}];}
 return out;
}
static inline NSString *AACSharedFileLeaf(NSString *process,NSString *suffix){
 NSString *p=[process isKindOfClass:NSString.class]&&process.length?process:@"unknown";
 p=[p stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
 suffix=[suffix isKindOfClass:NSString.class]&&suffix.length?suffix:@"log";
 return [NSString stringWithFormat:@"aac-%@.%@",p,suffix];
}
static inline NSString *AACSharedLine(NSString *s,NSUInteger cap){
 if(![s isKindOfClass:NSString.class])return @"";
 return s.length>cap?[[s substringToIndex:cap] stringByAppendingString:@"…<truncated>"]:s;
}
/* Per-process resolution state. Header-only, so each translation unit keeps its own copy. */
static NSMutableDictionary *AACSharedChosen=nil;
static NSMutableSet *AACSharedFailed=nil;
static inline NSDictionary *AACSharedResolve(NSString *process,BOOL reset){
 @try{
  if(!AACSharedChosen)AACSharedChosen=[NSMutableDictionary new];
  if(!AACSharedFailed)AACSharedFailed=[NSMutableSet new];
  if(reset)[AACSharedChosen removeObjectForKey:process];
  NSDictionary *cached=AACSharedChosen[process];if(cached)return cached;
  NSFileManager *fm=[NSFileManager defaultManager];
  for(NSDictionary *candidate in AACSharedLogCandidateDirs()){
   NSString *key=[NSString stringWithFormat:@"%@|%@",candidate[@"label"],process];
   if([AACSharedFailed containsObject:key])continue;
   NSString *dir=candidate[@"dir"];NSError *e=nil;NSString *why=nil;BOOL ok=NO;
   BOOL isDir=NO;BOOL exists=[fm fileExistsAtPath:dir isDirectory:&isDir];
   if(exists&&isDir)ok=[fm isWritableFileAtPath:dir];
   else ok=[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&e];
   if(!ok)why=e.localizedDescription?:(exists?@"目录不可写":@"目录不可创建");
   if(!ok){NSLog(@"[AutoAnswerCall] shared log candidate %@ unusable in %@: %@",candidate[@"label"],process,why?:@"unknown");[AACSharedFailed addObject:key];continue;}
   NSDictionary *chosen=@{@"label":candidate[@"label"],@"dir":dir,@"path":[dir stringByAppendingPathComponent:AACSharedFileLeaf(process,@"log")]};
   AACSharedChosen[process]=chosen;return chosen;
  }
 }@catch(NSException *e){NSLog(@"[AutoAnswerCall] shared log resolve exception: %@",e.reason?:@"unknown");}
 return nil;
}
static inline BOOL AACSharedPrefsAppend(NSString *process,NSString *line){
 @try{
  CFStringRef domain=(__bridge CFStringRef)AACSharedLogDomain;
  CFStringRef key=(__bridge CFStringRef)[@"Log." stringByAppendingString:process];
  CFPreferencesAppSynchronize(domain);
  NSString *old=CFBridgingRelease(CFPreferencesCopyAppValue(key,domain));
  if(![old isKindOfClass:NSString.class])old=@"";
  NSString *all=[old stringByAppendingString:line];
  if(all.length>AACSharedPrefsLogLimit)all=[all substringFromIndex:all.length-AACSharedPrefsLogLimit];
  CFPreferencesSetAppValue(key,(__bridge CFPropertyListRef)all,domain);
  BOOL synced=CFPreferencesAppSynchronize(domain);
  if(!synced)NSLog(@"[AutoAnswerCall] shared-log CFPreferences fallback sync returned NO");
  return synced;
 }@catch(NSException *e){NSLog(@"[AutoAnswerCall] shared-log CFPreferences fallback exception: %@",e.reason?:@"unknown");}
 return NO;
}
/* Recent-line ring buffer (1.15.0). Bounded in memory, fed by AACSharedAppend, and used only
   as the payload source for the shared CFPreferences host report below. It is NOT a second
   log: it never grows beyond AACSharedRecentLineCap entries and never throws. */
static NSMutableArray *AACSharedRecentLines=nil;
static NSUInteger const AACSharedRecentLineCap=200;
static inline void AACSharedRemember(NSString *line){
 if(![line isKindOfClass:NSString.class]||!line.length)return;
 @try{
  if(!AACSharedRecentLines)AACSharedRecentLines=[NSMutableArray new];
  [AACSharedRecentLines addObject:AACSharedLine(line,600)];
  while(AACSharedRecentLines.count>AACSharedRecentLineCap)[AACSharedRecentLines removeObjectAtIndex:0];
 }@catch(NSException *e){}
}
/* Appends one line. Returns YES only when it was written to a file path (or, failing
   that, to the preferences fallback). Every line is also sent to NSLog. */
static inline BOOL AACSharedAppend(NSString *process,NSString *message){
 NSString *text=[NSString stringWithFormat:@"[%@] %@ %@\n",NSDate.date,process?:@"unknown",AACSharedLine(message,2000)];
 NSLog(@"[AutoAnswerCall][%@] %@",process?:@"unknown",AACSharedLine(message,2000));
 AACSharedRemember(text);
 NSString *failure=nil;
 @try{
  NSDictionary *chosen=AACSharedResolve(process,NO);
  NSString *path=chosen[@"path"];
  if(path){
   NSFileManager *fm=[NSFileManager defaultManager];NSError *e=nil;BOOL ok=NO;
   NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];
   unsigned long long size=[attributes[NSFileSize] isKindOfClass:NSNumber.class]?[attributes[NSFileSize] unsignedLongLongValue]:0;
   if(size>AACSharedLogMaxBytes){
    NSString *old=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
    if([old isKindOfClass:NSString.class]){
     NSString *tail=old.length>AACSharedLogKeepBytes?[old substringFromIndex:old.length-AACSharedLogKeepBytes]:old;
     ok=[[tail stringByAppendingString:text] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&e];
    }
   } else if([fm fileExistsAtPath:path]){
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
    if(handle){@try{[handle seekToEndOfFile];[handle writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];[handle closeFile];ok=YES;}@catch(NSException *ex){ok=NO;e=[NSError errorWithDomain:@"AACSharedLog" code:1 userInfo:@{NSLocalizedDescriptionKey:ex.reason?:@"句柄写入异常"}];}}
   } else {
    ok=[[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic error:&e];
   }
   if(ok)return YES;
   failure=e.localizedDescription?:@"写入返回失败";
   @try{[AACSharedFailed addObject:[NSString stringWithFormat:@"%@|%@",chosen[@"label"],process]];AACSharedChosen[process]=nil;}@catch(NSException *ex){}
  } else failure=@"没有可用候选路径";
 }@catch(NSException *e){failure=e.reason?:@"共享日志写入异常";}
 BOOL fallback=AACSharedPrefsAppend(process,text);
 NSLog(@"[AutoAnswerCall][%@] shared-log file write failed (%@); CFPreferences fallback used=%d; cross-process visibility NOT claimed",process?:@"unknown",failure,fallback);
 return fallback;
}
/* Creates/overwrites a named file inside the resolved shared directory. */
static inline BOOL AACSharedWriteNamed(NSString *process,NSString *suffix,NSString *text,NSError **error){
 @try{
  NSDictionary *chosen=AACSharedResolve(process,NO);
  NSString *dir=chosen[@"dir"];
  if(!dir){if(error)*error=[NSError errorWithDomain:@"AACSharedLog" code:2 userInfo:@{NSLocalizedDescriptionKey:@"没有可写候选目录"}];return NO;}
  NSString *path=[dir stringByAppendingPathComponent:AACSharedFileLeaf(process,suffix)];
  return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
 }@catch(NSException *e){if(error)*error=[NSError errorWithDomain:@"AACSharedLog" code:3 userInfo:@{NSLocalizedDescriptionKey:e.reason?:@"命名写入异常"}];}
 return NO;
}
static inline NSString *AACSharedReadFile(NSString *path,NSError **error){
 if(![path isKindOfClass:NSString.class]||!path.length)return nil;
 return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
}
/* Per-candidate evidence for the Settings log viewer: existence/writability of every
   directory and every known file. Nothing here asserts that another process can see it. */
static inline NSArray *AACSharedViewerEntries(NSArray *processes){
 NSMutableArray *out=[NSMutableArray new];
 NSFileManager *fm=[NSFileManager defaultManager];
 for(NSDictionary *candidate in AACSharedLogCandidateDirs()){
  NSString *dir=candidate[@"dir"];
  BOOL isDir=NO;BOOL exists=[fm fileExistsAtPath:dir isDirectory:&isDir];
  BOOL writable=exists&&isDir&&[fm isWritableFileAtPath:dir];
  [out addObject:@{@"label":candidate[@"label"],@"kind":@"dir",@"path":dir,@"exists":@(exists&&isDir),@"writable":@(writable),@"readable":@(exists&&isDir),@"size":@0,@"note":(exists&&isDir)?@"目录存在":@"目录不存在"}];
  for(NSString *process in processes){
   for(NSString *suffix in @[@"log",@"txt",@"discovery.txt"]){
    NSString *path=[dir stringByAppendingPathComponent:AACSharedFileLeaf(process,suffix)];
    BOOL file=NO;[fm fileExistsAtPath:path isDirectory:&file];
    NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];
    unsigned long long size=[attributes[NSFileSize] isKindOfClass:NSNumber.class]?[attributes[NSFileSize] unsignedLongLongValue]:0;
    [out addObject:@{@"label":[NSString stringWithFormat:@"%@/%@",candidate[@"label"],path.lastPathComponent],@"kind":@"file",@"path":path,@"process":process,@"exists":@(file),@"writable":@(file&&[fm isWritableFileAtPath:path]),@"readable":@(file&&[fm isReadableFileAtPath:path]),@"size":@(size),@"note":file?@"文件存在":@"未创建"}];
   }
  }
 }
 [out addObject:@{@"label":[NSString stringWithFormat:@"CFPreferences %@",AACSharedLogDomain],@"kind":@"prefs",@"path":AACSharedLogDomain,@"exists":@YES,@"writable":@NO,@"readable":@YES,@"size":@0,@"note":@"最后手段回退域；跨进程可见性不保证"}];
 return out;
}
static inline NSString *AACSharedPrefsDump(void){
 NSMutableString *s=[NSMutableString string];
 @try{
  CFStringRef domain=(__bridge CFStringRef)AACSharedLogDomain;
  CFPreferencesAppSynchronize(domain);
  NSDictionary *all=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
  [s appendFormat:@"域 %@：本进程读取到 %lu 个键\n",AACSharedLogDomain,(unsigned long)([all isKindOfClass:NSDictionary.class]?all.count:0)];
  for(NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]){
   id value=all[key];
   if([key hasPrefix:@"Log."])[s appendFormat:@"\n--- %@ (%lu 字符) ---\n%@\n",key,(unsigned long)[value isKindOfClass:NSString.class]?[(NSString *)value length]:0,[value isKindOfClass:NSString.class]?value:@"<非字符串>"];
   else [s appendFormat:@"\n--- %@ ---\n%@\n",key,value];
  }
  if(!all.count)[s appendString:@"\n（本进程读不到任何键：可能从未写入，或其他进程写入对这里不可见。）\n"];
 }@catch(NSException *e){[s appendFormat:@"读取失败：%@\n",e.reason?:@"未知异常"];}
 return s;
}
static inline NSString *AACSharedProbeCompanionDump(void){
 NSMutableString *s=[NSMutableString string];
 @try{
  CFStringRef domain=(__bridge CFStringRef)AACProbeCompanionDomain;
  CFPreferencesAppSynchronize(domain);
  NSDictionary *all=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
  [s appendFormat:@"域 %@：本进程读取到 %lu 个键\n",AACProbeCompanionDomain,(unsigned long)([all isKindOfClass:NSDictionary.class]?all.count:0)];
  for(NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)])[s appendFormat:@"\n%@ = %@",key,all[key]];
  if(!all.count)[s appendString:@"\n（无记录：Darwin 通知本身无载荷，伴随键只是尽力而为。）\n"];
 }@catch(NSException *e){[s appendFormat:@"读取失败：%@\n",e.reason?:@"未知异常"];}
 return s;
}

/* ============================ 1.15.0 TASK 1: SHARED HOST REPORT ============================
   CLOSE THE VISIBILITY GAP. Device evidence that drove this (the user's real 1.14.0
   SpringBoard shared log, 2026-10-16, quoted verbatim because it is the authoritative record):
     - 14:19:05 discovery: matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER.
     - the 4 HOOKED methods are ALL accessors, not answer actions:
       -[INAnswerCallIntentResponse answeredCall] (0args+object),
       -[_INPBAnswerCallIntentResponse hasAnsweredCall] (0args+BOOL),
       -[_INPBAnswerCallIntentResponse answeredCall] (0args+object),
       -[TPInComingCallUISnapshotViewController acceptButton] (0args+object).
     - the 5 INVOKABLE candidates are setters/unrelated:
       -[CXCallControllerHost listener:shouldAcceptNewConnection:],
       -[INAnswerCallIntentResponse setAnsweredCall:],
       -[_INPBAnswerCallIntentResponse setAnsweredCall:],
       -[TUCallNotificationManager answeringMachineStreamTokenChangedForCall:],
       -[TPInComingCallUISnapshotViewController setAcceptButton:].
     - a real incoming call (UUID A8059645-...) was detected at 14:20:03; at 14:20:04 the host
       demoted itself because InCallService broadcast an ownership claim, then at 14:20:21 the
       takeover path submitted=yes, but immediately after:
         hierarchy re-scan for the incoming-call UI object: windows=21 visited=1771 found=0
         LOG-ONLY primary path in SpringBoard: no captured/rescanned UI object could answer.
       The secondary public transaction failed with CallKit error 1 = unentitled. The call ended
       unanswered at 14:20:27.
     - InCallService DOES run the tweak and claimed ownership, but its own discovery/log files
       live in its own container and are invisible to the Settings process, so we never saw what
       it found.
   WHAT THIS SECTION DOES: every host ALSO publishes its discovery summary and its recent log
   lines into this OWN CFPreferences domain with per-host keys, so Settings and the other hosts
   can try to read them. The publication is bounded (a few KB per host, truncated with an
   explicit marker) and the DOMAIN IS OUR OWN — no Apple preference key is ever written or
   invented. The file-based channel above is kept exactly as it was.
   WHAT THIS SECTION DOES NOT DO: it does NOT claim that the domain is visible across
   processes. Every reader reports only what it actually reads in its own process, plus the
   real on-disk plist path of the domain and whether that file is readable here. */
static NSString * const AACHostReportDomain=@"com.autoanswer.call.hostreport";
static NSString * const AACHostReportKeyPrefix=@"Host.";
static NSString * const AACHostReportHostsKey=@"Hosts";
/* Per-host bound: summary + recent log lines may never exceed this many characters together
   (a few KB), and the truncation marker says exactly that the payload was cut. */
static NSUInteger const AACHostReportMaxBytes=6000;
static NSUInteger const AACHostReportLogBytes=4000;
static NSUInteger const AACHostReportSummaryBytes=1800;
static NSString * const AACHostReportTruncatedMarker=@"…<truncated>";
static NSTimeInterval const AACHostReportIntervalSeconds=20.0;
static inline NSArray *AACHostReportTags(void){return @[@"incall",@"springboard",@"mobilephone",@"settings"];}
static inline NSString *AACHostReportKey(NSString *tag,NSString *leaf){
 return [AACHostReportKeyPrefix stringByAppendingFormat:@"%@.%@",tag?:@"unknown",leaf?:@"unknown"];
}
/* Real on-disk plist paths that would hold this domain. Only paths, never invented keys. */
static inline NSArray *AACHostReportPlistPaths(void){
 return @[[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",AACHostReportDomain],
          [NSString stringWithFormat:@"/var/jb/var/mobile/Library/Preferences/%@.plist",AACHostReportDomain]];
}
static inline NSString *AACHostReportHeadBound(NSString *text,NSUInteger cap){
 NSString *body=[text isKindOfClass:NSString.class]?text:@"";
 if(body.length<=cap)return body;
 return [[body substringToIndex:cap] stringByAppendingString:AACHostReportTruncatedMarker];
}
/* Keeps the NEWEST characters and marks the cut explicitly at the front. */
static inline NSString *AACHostReportTailBound(NSString *text,NSUInteger cap){
 NSString *body=[text isKindOfClass:NSString.class]?text:@"";
 if(body.length<=cap)return body;
 return [AACHostReportTruncatedMarker stringByAppendingFormat:@"(earlier %lu characters dropped)\n%@",(unsigned long)(body.length-cap),[body substringFromIndex:body.length-cap]];
}
static inline NSString *AACHostReportRecentLog(void){
 NSMutableString *s=[NSMutableString string];
 @try{
  if(AACSharedRecentLines.count)for(NSString *line in AACSharedRecentLines)[s appendString:line];
 }@catch(NSException *e){[s appendFormat:@"（读取本进程最近日志行失败：%@）\n",e.reason?:@"未知异常"];}
 return s;
}
/* Publishes one host's report. facts may carry leaves (role, answerPaths, actionMethods,
   accessorMethods, classification, display, hostTag) and every leaf is written as the
   per-host key Host.<tag>.<leaf>. Returns REAL results, never an assumption: the CFPreferences
   synchronize status, the byte sizes actually written and the key list. */
static inline NSDictionary *AACHostReportPublish(NSString *tag,NSString *summary,NSDictionary *facts){
 NSMutableDictionary *result=[NSMutableDictionary new];
 @try{
  NSString *t=[tag isKindOfClass:NSString.class]&&tag.length?tag:@"unknown";
  NSString *summaryText=AACHostReportHeadBound(summary?:@"",AACHostReportSummaryBytes);
  NSString *logText=AACHostReportTailBound(AACHostReportRecentLog(),AACHostReportLogBytes);
  if(summaryText.length+logText.length>AACHostReportMaxBytes){
   NSUInteger room=AACHostReportMaxBytes>logText.length?AACHostReportMaxBytes-logText.length:0;
   summaryText=AACHostReportHeadBound(summaryText,room);
  }
  NSString *classification=nil;
  @try{classification=[facts[@"classification"] isKindOfClass:NSString.class]?(NSString *)facts[@"classification"]:facts[@"classification"]?[NSString stringWithFormat:@"%@",facts[@"classification"]]:nil;}@catch(NSException *e){classification=nil;}
  CFStringRef domain=(__bridge CFStringRef)AACHostReportDomain;
  CFPreferencesAppSynchronize(domain);
  NSMutableArray *leaves=[NSMutableArray arrayWithObjects:@"summary",@"log",@"updated",@"pid",nil];
  CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,@"summary"),(__bridge CFPropertyListRef)summaryText,domain);
  CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,@"log"),(__bridge CFPropertyListRef)logText,domain);
  CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,@"updated"),(__bridge CFPropertyListRef)NSDate.date,domain);
  CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,@"pid"),(__bridge CFPropertyListRef)@(NSProcessInfo.processInfo.processIdentifier),domain);
  for(NSString *leaf in facts.allKeys){
   @try{
    if(![leaf isKindOfClass:NSString.class]||!leaf.length)continue;
    id value=facts[leaf];
    if(!value||[value isKindOfClass:NSNull.class])continue;
    if([leaf isEqualToString:@"summary"]||[leaf isEqualToString:@"log"])continue;
    CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,leaf),(__bridge CFPropertyListRef)([value isKindOfClass:NSString.class]?(NSString *)value:[NSString stringWithFormat:@"%@",value]),domain);
    [leaves addObject:leaf];
   }@catch(NSException *e){}
  }
  if(classification.length)CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportKey(t,@"classification"),(__bridge CFPropertyListRef)classification,domain);
  NSArray *old=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)AACHostReportHostsKey,domain));
  NSMutableArray *hosts=[NSMutableArray new];
  if([old isKindOfClass:NSArray.class])for(id entry in old)if([entry isKindOfClass:NSString.class]&&[entry length])[hosts addObject:entry];
  if(![hosts containsObject:t])[hosts addObject:t];
  CFPreferencesSetAppValue((__bridge CFStringRef)AACHostReportHostsKey,(__bridge CFPropertyListRef)hosts.copy,domain);
  BOOL synced=CFPreferencesAppSynchronize(domain);
  result[@"domain"]=AACHostReportDomain;result[@"tag"]=t;result[@"synced"]=@(synced);
  result[@"summaryBytes"]=@(summaryText.length);result[@"logBytes"]=@(logText.length);
  result[@"totalBytes"]=@(summaryText.length+logText.length);result[@"keys"]=leaves.copy;
  result[@"boundBytes"]=@(AACHostReportMaxBytes);
 }@catch(NSException *e){
  result[@"synced"]=@NO;result[@"exception"]=e.reason?:@"未知异常";
 }
 return result;
}
/* 1.15.0: publish immediately and then every AACHostReportIntervalSeconds with a freshly
   computed summary, so a host that spends a long time in a call still keeps its report fresh.
   The block is retained by the timer's event handler; the timer is retained by the static. */
static dispatch_source_t AACHostReportTimer=nil;
static inline void AACHostReportEnablePeriodic(NSString *tag,NSString *(^summaryBlock)(void)){
 @try{
  AACHostReportPublish(tag,summaryBlock?summaryBlock():@"（无摘要）",nil);
  if(AACHostReportTimer)return;
  dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  if(!timer){AACSharedAppend(tag,@"host report timer creation failed; only the immediate publication happened");return;}
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACHostReportIntervalSeconds*NSEC_PER_SEC)),(uint64_t)(AACHostReportIntervalSeconds*NSEC_PER_SEC),5ull*NSEC_PER_SEC);
  dispatch_source_set_event_handler(timer,^{
   @try{NSDictionary *r=AACHostReportPublish(tag,summaryBlock?summaryBlock():@"（无摘要）",nil);
    AACSharedRemember([NSString stringWithFormat:@"[%@] %@ host report re-published: domain=%@ synced=%@ summaryBytes=%@ logBytes=%@ totalBytes=%@ boundBytes=%@ keys=%@\n",NSDate.date,tag,r[@"domain"],r[@"synced"],r[@"summaryBytes"],r[@"logBytes"],r[@"totalBytes"],r[@"boundBytes"],r[@"keys"]]);
   }@catch(NSException *e){}
  });
  AACHostReportTimer=timer;
  dispatch_resume(timer);
  AACSharedAppend(tag,[NSString stringWithFormat:@"host report periodic publication started every %.0f seconds, bounded at %lu characters per host (domain=%@)",AACHostReportIntervalSeconds,(unsigned long)AACHostReportMaxBytes,AACHostReportDomain]);
 }@catch(NSException *e){AACSharedAppend(tag,[@"host report publication exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
/* Settings-side read-back. Reports the domain name, the real plist paths of that domain and
   the readability of each one HERE, then every key/value that this process can actually read.
   It never claims cross-process visibility: an empty read is reported as such, with the
   honest alternatives. */
static inline NSString *AACHostReportDump(void){
 NSMutableString *s=[NSMutableString string];
 @try{
  NSFileManager *fm=[NSFileManager defaultManager];
  [s appendFormat:@"# 宿主跨进程上报域（本插件自有域，不是任何 Apple 域）：%@\n",AACHostReportDomain];
  [s appendFormat:@"# 每宿主键前缀：%@<tag>.  键：summary, log, updated, pid, role, answerPaths, actionMethods, accessorMethods, classification, display（按实际写入的键为准）\n",AACHostReportKeyPrefix];
  [s appendFormat:@"# 每宿主载荷上限：%lu 字符（summary+最近日志行），超出即截断并写入标记 %@\n",(unsigned long)AACHostReportMaxBytes,AACHostReportTruncatedMarker];
  for(NSString *path in AACHostReportPlistPaths()){
   BOOL isDir=NO;BOOL exists=[fm fileExistsAtPath:path isDirectory:&isDir];
   NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];
   unsigned long long size=[attributes[NSFileSize] isKindOfClass:NSNumber.class]?[attributes[NSFileSize] unsignedLongLongValue]:0;
   [s appendFormat:@"# 域文件真实路径：%@ —— 本进程：%@%@\n",path,exists?@"存在":@"不存在/不可见",exists?[NSString stringWithFormat:@"，可读=%@，%llu 字节",[fm isReadableFileAtPath:path]?@"是":@"否",size]:@""];
  }
  CFStringRef domain=(__bridge CFStringRef)AACHostReportDomain;
  CFPreferencesAppSynchronize(domain);
  NSDictionary *all=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
  NSUInteger count=[all isKindOfClass:NSDictionary.class]?all.count:0;
  [s appendFormat:@"\n# 本进程从该域实际读到的键数：%lu\n",(unsigned long)count];
  for(NSString *key in [[all isKindOfClass:NSDictionary.class]?all.allKeys:@[] sortedArrayUsingSelector:@selector(compare:)]){
   id value=all[key];
   if([key hasPrefix:AACHostReportKeyPrefix]){
    if([value isKindOfClass:NSString.class]){
     [s appendFormat:@"\n--- %@（%lu 字符）---\n%@\n",key,(unsigned long)[(NSString *)value length],value];
    }else{
     [s appendFormat:@"\n--- %@ ---\n%@\n",key,value];
    }
   }else{
    [s appendFormat:@"\n%@ = %@\n",key,value];
   }
  }
  if(!count)[s appendString:@"\n（本进程读不到任何键：该域可能从未被写入，也可能写入发生在另一个进程且对本进程不可见——跨进程可见性未被本版本验证，这里不因此断言任何宿主未注入。）\n"];
  NSArray *hosts=nil;
  if([all isKindOfClass:NSDictionary.class])hosts=all[AACHostReportHostsKey];
  [s appendFormat:@"\n# 已上报宿主 tag（%@）：%@\n",AACHostReportHostsKey,[hosts isKindOfClass:NSArray.class]&&[(NSArray *)hosts count]?[hosts componentsJoinedByString:@", "]:@"本进程未读到"];
  for(NSString *tag in AACHostReportTags()){
   NSMutableString *broken=[NSMutableString string];
   if([all isKindOfClass:NSDictionary.class]){
    for(NSString *leaf in @[@"summary",@"log",@"updated",@"role",@"answerPaths",@"classification",@"display",@"pid"]){
     NSString *key=AACHostReportKey(tag,leaf);
     id value=all[key];
     if(!value)continue;
     if([value isKindOfClass:NSString.class])[broken appendFormat:@"\n  %@: %lu 字符%@",leaf,(unsigned long)[(NSString *)value length],[leaf isEqualToString:@"summary"]?[NSString stringWithFormat:@"\n%@",value]:@""];
     else [broken appendFormat:@"\n  %@ = %@",leaf,value];
    }
   }
   [s appendFormat:@"\n[%@] %@\n",tag,broken.length?broken:@"本进程未读到该宿主的任何键（≠ 该宿主未注入）"];
  }
 }@catch(NSException *e){[s appendFormat:@"读取失败：%@\n",e.reason?:@"未知异常"];}
 return s;
}
/* Structured, honest per-host summary for the Settings/export list: how many keys this process
   can actually read for each host, and the real plist path of the domain. */
static inline NSArray *AACHostReportEntries(void){
 NSMutableArray *out=[NSMutableArray new];
 @try{
  CFStringRef domain=(__bridge CFStringRef)AACHostReportDomain;
  CFPreferencesAppSynchronize(domain);
  NSDictionary *all=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
  NSFileManager *fm=[NSFileManager defaultManager];
  NSString *path=AACHostReportPlistPaths().firstObject;
  NSDictionary *attributes=[fm attributesOfItemAtPath:path error:nil];
  unsigned long long size=[attributes[NSFileSize] isKindOfClass:NSNumber.class]?[attributes[NSFileSize] unsignedLongLongValue]:0;
  BOOL exists=[fm fileExistsAtPath:path];
  [out addObject:@{@"label":[NSString stringWithFormat:@"域 %@（真实 plist 路径）",AACHostReportDomain],@"path":path,@"exists":@(exists),@"readable":@(exists&&[fm isReadableFileAtPath:path]),@"size":@(size),@"note":exists?@"域文件在本进程可见":@"域文件在本进程不可见（跨进程可见性未验证，不据此断言）"}];
  for(NSString *tag in AACHostReportTags()){
   NSUInteger keys=0;NSUInteger bytes=0;
   if([all isKindOfClass:NSDictionary.class]){
    for(NSString *key in all.allKeys)if([key hasPrefix:AACHostReportKey(tag,@"")]){keys++;id v=all[key];if([v isKindOfClass:NSString.class])bytes+=[(NSString *)v length];}
   }
   [out addObject:@{@"label":[NSString stringWithFormat:@"上报 %@（%lu 个键）",tag,(unsigned long)keys],@"path":[NSString stringWithFormat:@"CFPreferences 键（不是文件路径）：%@",AACHostReportKey(tag,@"summary")],@"exists":@(keys>0),@"readable":@(keys>0),@"size":@(bytes),@"note":keys?@"本进程可读到该宿主的键":@"本进程读不到该宿主的键（≠ 该宿主未注入）"}];
  }
 }@catch(NSException *e){[out addObject:@{@"label":@"上报域读取异常",@"path":AACHostReportDomain,@"exists":@NO,@"readable":@NO,@"size":@0,@"note":e.reason?:@"未知异常"}];}
 return out;
}
