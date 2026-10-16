#import <Foundation/Foundation.h>
#import <notify.h>
#import "AACSharedLog.h"
/* Per-process Darwin probe (1.11.0, evidence only).
   Darwin notifications carry no payload, so each process uses its OWN notification
   name (com.autoanswer.call.probe.<process>) and additionally writes a companion
   record into an own-domain CFPreferences key whose cross-process visibility is NOT
   claimed. Settings registers one observer per known process name and timestamps
   arrivals, so it can list which process responded and when. */
static NSString * const AACProbePrefix=@"com.autoanswer.call.probe.";
static NSTimeInterval const AACProbeInterval=20.0;
static dispatch_source_t AACProbeTimer=nil; /* retained so the timer survives */

static inline NSString *AACProbeName(NSString *process){
 NSString *p=[process isKindOfClass:NSString.class]&&process.length?process:@"unknown";
 return [AACProbePrefix stringByAppendingString:p];
}
static inline uint32_t AACProbePost(NSString *process){
 uint32_t status=NOTIFY_STATUS_FAILED;
 @try{
  NSString *name=AACProbeName(process);
  status=notify_post(name.UTF8String);
  BOOL synced=NO;
  @try{
   NSDictionary *record=@{@"process":process?:@"unknown",@"date":NSDate.date,@"pid":@(NSProcessInfo.processInfo.processIdentifier),@"postStatus":@(status),@"name":name};
   CFStringRef domain=(__bridge CFStringRef)AACProbeCompanionDomain;
   CFPreferencesSetAppValue((__bridge CFStringRef)[@"LastProbe." stringByAppendingString:process?:@"unknown"],(__bridge CFPropertyListRef)record,domain);
   synced=CFPreferencesAppSynchronize(domain);
  }@catch(NSException *e){NSLog(@"[AutoAnswerCall] probe companion record failed: %@",e.reason?:@"unknown");}
  AACSharedAppend(process,[NSString stringWithFormat:@"probe posted name=%@ status=%u companionKeySynced=%d (Darwin notifications carry no payload; companion CFPreferences record visibility is NOT claimed)",name,status,synced]);
 }@catch(NSException *e){NSLog(@"[AutoAnswerCall] probe post exception: %@",e.reason?:@"unknown");}
 return status;
}
/* Posts once immediately, then repeats every ~20 seconds. */
static inline void AACProbeStart(NSString *process){
 AACProbePost(process);
 @try{
  dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  if(!timer){AACSharedAppend(process,@"probe timer creation failed; only the load-time notification was posted");return;}
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACProbeInterval*NSEC_PER_SEC)),(uint64_t)(AACProbeInterval*NSEC_PER_SEC),5ull*NSEC_PER_SEC);
  dispatch_source_set_event_handler(timer,^{AACProbePost(process);});
  AACProbeTimer=timer;
  dispatch_resume(timer);
  AACSharedAppend(process,[NSString stringWithFormat:@"probe timer started every %.0f seconds (process=%@)",AACProbeInterval,process]);
 }@catch(NSException *e){AACSharedAppend(process,[@"probe timer exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
