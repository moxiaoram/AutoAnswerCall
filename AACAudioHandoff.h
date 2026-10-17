#import <Foundation/Foundation.h>
#import <notify.h>
#import "AACConfigBridge.h"
/* Cross-process signaling for LOCAL playback, not cellular voice uplink.
   SpringBoard is the single writer of playback state; InCallService writes stop requests.
   Darwin notifications carry no payload and are only hints; data is read from disk. */
static NSString * const AACAudioStateChanged=@"com.autoanswer.call.audio.statechanged";
static NSString * const AACAudioStopRequested=@"com.autoanswer.call.audio.stopRequested";
static inline NSString *AACAudioStatePath(void){return [AACBridgeDirectory() stringByAppendingPathComponent:@"playback-state.plist"];}
static inline NSString *AACAudioStopPath(void){return [AACBridgeDirectory() stringByAppendingPathComponent:@"playback-stop-request.plist"];}
static inline NSDictionary *AACAudioValidEvent(NSString *path){
 NSDictionary *data=[NSDictionary dictionaryWithContentsOfFile:path];
 if(![data isKindOfClass:NSDictionary.class]||![data[@"uuid"] isKindOfClass:NSString.class]||
    ![[NSUUID alloc] initWithUUIDString:data[@"uuid"]]||
    ![data[@"timestamp"] isKindOfClass:NSNumber.class])return nil;
 double age=NSDate.date.timeIntervalSince1970-[data[@"timestamp"] doubleValue];
 if(age < -30 || age > 7200)return nil; // no stale handoff from an earlier boot/session
 return data;
}
static inline NSDictionary *AACAudioReadState(void){return AACAudioValidEvent(AACAudioStatePath());}
static inline NSDictionary *AACAudioReadStopRequest(void){return AACAudioValidEvent(AACAudioStopPath());}
static inline BOOL AACAudioWriteEvent(NSString *path,NSString *uuid,NSString *status){
 if(![[NSUUID alloc] initWithUUIDString:uuid])return NO;
 NSDictionary *data=@{@"uuid":uuid,@"status":status?:@"",@"timestamp":@(NSDate.date.timeIntervalSince1970)};
 NSError *e=nil;
 if(![NSFileManager.defaultManager createDirectoryAtPath:AACBridgeDirectory() withIntermediateDirectories:YES attributes:nil error:&e])return NO;
 if(![data writeToFile:path atomically:YES])return NO;
 NSDictionary *readback=AACAudioValidEvent(path);
 return [readback[@"uuid"] isEqualToString:uuid]&&[readback[@"status"] isEqualToString:status];
}
static inline BOOL AACAudioPublishStatus(NSUUID *uuid,NSString *status){
 if(!uuid||!status.length)return NO;
 BOOL ok=AACAudioWriteEvent(AACAudioStatePath(),uuid.UUIDString,status);
 if(ok)notify_post(AACAudioStateChanged.UTF8String);
 return ok;
}
static inline BOOL AACAudioRequestManualStop(NSUUID *uuid){
 if(!uuid)return NO;
 BOOL ok=AACAudioWriteEvent(AACAudioStopPath(),uuid.UUIDString,@"stop");
 if(ok)notify_post(AACAudioStopRequested.UTF8String);
 return ok;
}
static inline BOOL AACAudioStopMatches(NSUUID *uuid){
 NSDictionary *r=AACAudioReadStopRequest();
 return uuid&&[r[@"uuid"] isEqualToString:uuid.UUIDString]&&[r[@"status"] isEqualToString:@"stop"];
}
