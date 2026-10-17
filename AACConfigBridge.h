#import <Foundation/Foundation.h>
/* Explicit bridge because the Settings preference suite may be sandboxed away from
   SpringBoard/InCallService/MobilePhone. Availability is checked, never assumed. */
static inline NSString *AACBridgeDirectory(void){
 return @"/var/mobile/Library/Application Support/AutoAnswerCall";
}
static inline NSString *AACBridgeConfigPath(void){
 return [AACBridgeDirectory() stringByAppendingPathComponent:@"runtime-config.plist"];
}
static inline NSDictionary *AACBridgeRead(void){
 NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:AACBridgeConfigPath()];
 if(![p isKindOfClass:NSDictionary.class]||![p[@"ConfigVersion"] isKindOfClass:NSNumber.class]||
    ![p[@"Enabled"] isKindOfClass:NSNumber.class]||![p[@"Mode"] isKindOfClass:NSNumber.class]||
    ![p[@"Delay"] isKindOfClass:NSNumber.class]||![p[@"PlayAudio"] isKindOfClass:NSNumber.class]||
    ![p[@"Whitelist"] isKindOfClass:NSString.class]||
    (p[@"SystemAnswerPlaybackTest"]&&![p[@"SystemAnswerPlaybackTest"] isKindOfClass:NSNumber.class])||
    (p[@"UplinkPCMProbe"]&&![p[@"UplinkPCMProbe"] isKindOfClass:NSNumber.class]))return nil;
 return p;
}
/* Settings-side only. Copies the selected audio out of Settings' private application
   support path when the shared directory is writable. This is LOCAL OUTPUT ONLY:
   it does not attach to cellular-call microphone/uplink audio. */
static inline BOOL AACBridgePublish(NSDictionary *settings,NSString **error){
 if(error)*error=nil;
 NSFileManager *fm=NSFileManager.defaultManager;
 NSError *e=nil;NSString *dir=AACBridgeDirectory();
 if(![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&e]){
  if(error)*error=[NSString stringWithFormat:@"共享配置目录不可写: %@",e.localizedDescription?:@"未知原因"];
  return NO;
 }
 NSMutableDictionary *saved=[NSMutableDictionary new];
 for(NSString *k in @[@"Enabled",@"Mode",@"Delay",@"Whitelist",@"PlayAudio",@"SystemAnswerPlaybackTest",@"UplinkPCMProbe"]){
  id v=settings[k];
  if(v)saved[k]=v;
 }
 if(!saved[@"Enabled"])saved[@"Enabled"]=@NO;
 if(!saved[@"Mode"])saved[@"Mode"]=@2;
 if(!saved[@"Delay"])saved[@"Delay"]=@0.5;
 if(!saved[@"Whitelist"])saved[@"Whitelist"]=@"";
 if(!saved[@"PlayAudio"])saved[@"PlayAudio"]=@NO;
 if(!saved[@"SystemAnswerPlaybackTest"])saved[@"SystemAnswerPlaybackTest"]=@NO;
 if(!saved[@"UplinkPCMProbe"])saved[@"UplinkPCMProbe"]=@NO;
 saved[@"ConfigVersion"]=@2;
 NSString *source=settings[@"AudioPath"];
 NSString *uuid=settings[@"SelectedAudioID"];
 if([source isKindOfClass:NSString.class]&&source.length&&[uuid isKindOfClass:NSString.class]&&[[NSUUID alloc] initWithUUIDString:uuid]){
  NSString *suffix=source.pathExtension.lowercaseString;
  NSCharacterSet *bad=[[NSCharacterSet alphanumericCharacterSet] invertedSet];
  if(!suffix.length||[suffix rangeOfCharacterFromSet:bad].location!=NSNotFound||suffix.length>8)suffix=@"audio";
  NSString *file=[NSString stringWithFormat:@"shared-audio-%@.%@",uuid,suffix];
  NSString *destination=[dir stringByAppendingPathComponent:file];
  NSDictionary *attrs=[fm attributesOfItemAtPath:source error:&e];
  unsigned long long size=[attrs[NSFileSize] unsignedLongLongValue];
  if(!attrs||size==0||size>5*1024*1024){
   if(error)*error=[NSString stringWithFormat:@"所选音频不存在、不可读或超过 5MB: %@",source];
   return NO;
  }
  NSData *data=[NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:&e];
  if(!data||data.length!=size||![data writeToFile:destination options:NSDataWritingAtomic error:&e]){
   if(error)*error=[NSString stringWithFormat:@"复制所选音频到共享路径失败: %@",e.localizedDescription?:@"未知原因"];
   return NO;
  }
  saved[@"AudioPath"]=destination;
  if([settings[@"AudioName"] isKindOfClass:NSString.class])saved[@"AudioName"]=settings[@"AudioName"];
 }
 if(![saved writeToFile:AACBridgeConfigPath() atomically:YES]){
  if(error)*error=@"共享配置写入失败（设置沙盒可能无法访问该路径）";
  return NO;
 }
 NSDictionary *readback=AACBridgeRead();
 BOOL ok=readback&&[readback[@"ConfigVersion"] integerValue]==2&&[readback[@"Enabled"] isEqual:saved[@"Enabled"]]&&[readback[@"SystemAnswerPlaybackTest"] isEqual:saved[@"SystemAnswerPlaybackTest"]]&&[readback[@"UplinkPCMProbe"] isEqual:saved[@"UplinkPCMProbe"]]&&((!readback[@"AudioPath"]&&!saved[@"AudioPath"])||[readback[@"AudioPath"] isEqual:saved[@"AudioPath"]]);
 if(!ok&&error)*error=@"共享配置写入后回读校验失败";
 return ok;
}
