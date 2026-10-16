#import <Foundation/Foundation.h>
/* Shared-log EVIDENCE channel (1.10.0).
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
static NSUInteger const AACSharedInventoryCapBytes=200000;

static NSArray *AACSharedLogCandidateDirs(void){
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
 for(NSArray *pair in pairs){if(![pair[1] isKindOfClass:NSString.class]||!pair[1].length)continue;[out addObject:@{@"label":pair[0],@"dir":pair[1]}];}
 return out;
}
static NSString *AACSharedFileLeaf(NSString *process,NSString *suffix){
 NSString *p=[process isKindOfClass:NSString.class]&&process.length?process:@"unknown";
 p=[p stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
 suffix=[suffix isKindOfClass:NSString.class]&&suffix.length?suffix:@"log";
 return [NSString stringWithFormat:@"aac-%@.%@",p,suffix];
}
static NSString *AACSharedLine(NSString *s,NSUInteger cap){
 if(![s isKindOfClass:NSString.class])return @"";
 return s.length>cap?[[s substringToIndex:cap] stringByAppendingString:@"…<truncated>"]:s;
}
/* Per-process resolution state. Header-only, so each translation unit keeps its own copy. */
static NSMutableDictionary *AACSharedChosen=nil;
static NSMutableSet *AACSharedFailed=nil;
static NSDictionary *AACSharedResolve(NSString *process,BOOL reset){
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
   if(!ok){[AACSharedFailed addObject:key];continue;}
   NSDictionary *chosen=@{@"label":candidate[@"label"],@"dir":dir,@"path":[dir stringByAppendingPathComponent:AACSharedFileLeaf(process,@"log")]};
   AACSharedChosen[process]=chosen;return chosen;
  }
 }@catch(NSException *e){NSLog(@"[AutoAnswerCall] shared log resolve exception: %@",e.reason?:@"unknown");}
 return nil;
}
static BOOL AACSharedPrefsAppend(NSString *process,NSString *line){
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
/* Appends one line. Returns YES only when it was written to a file path (or, failing
   that, to the preferences fallback). Every line is also sent to NSLog. */
static BOOL AACSharedAppend(NSString *process,NSString *message){
 NSString *text=[NSString stringWithFormat:@"[%@] %@ %@\n",NSDate.date,process?:@"unknown",AACSharedLine(message,2000)];
 NSLog(@"[AutoAnswerCall][%@] %@",process?:@"unknown",AACSharedLine(message,2000));
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
static BOOL AACSharedWriteNamed(NSString *process,NSString *suffix,NSString *text,NSError **error){
 @try{
  NSDictionary *chosen=AACSharedResolve(process,NO);
  NSString *dir=chosen[@"dir"];
  if(!dir){if(error)*error=[NSError errorWithDomain:@"AACSharedLog" code:2 userInfo:@{NSLocalizedDescriptionKey:@"没有可写候选目录"}];return NO;}
  NSString *path=[dir stringByAppendingPathComponent:AACSharedFileLeaf(process,suffix)];
  return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
 }@catch(NSException *e){if(error)*error=[NSError errorWithDomain:@"AACSharedLog" code:3 userInfo:@{NSLocalizedDescriptionKey:e.reason?:@"命名写入异常"}];}
 return NO;
}
static NSString *AACSharedReadFile(NSString *path,NSError **error){
 if(![path isKindOfClass:NSString.class]||!path.length)return nil;
 return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
}
/* Per-candidate evidence for the Settings log viewer: existence/writability of every
   directory and every known file. Nothing here asserts that another process can see it. */
static NSArray *AACSharedViewerEntries(NSArray *processes){
 NSMutableArray *out=[NSMutableArray new];
 NSFileManager *fm=[NSFileManager defaultManager];
 for(NSDictionary *candidate in AACSharedLogCandidateDirs()){
  NSString *dir=candidate[@"dir"];
  BOOL isDir=NO;BOOL exists=[fm fileExistsAtPath:dir isDirectory:&isDir];
  BOOL writable=exists&&isDir&&[fm isWritableFileAtPath:dir];
  [out addObject:@{@"label":candidate[@"label"],@"kind":@"dir",@"path":dir,@"exists":@(exists&&isDir),@"writable":@(writable),@"readable":@(exists&&isDir),@"size":@0,@"note":(exists&&isDir)?@"目录存在":@"目录不存在"}];
  for(NSString *process in processes){
   for(NSString *suffix in @[@"log",@"txt"]){
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
static NSString *AACSharedPrefsDump(void){
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
static NSString *AACSharedProbeCompanionDump(void){
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
