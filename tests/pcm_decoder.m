#import <Foundation/Foundation.h>
#import "../AACPCMDecoder.h"
int main(int argc,const char **argv){
 @autoreleasepool {
  if(argc!=2){fprintf(stderr,"Expected WAV test fixture path\n");return 2;}
  NSString *path=[NSString stringWithUTF8String:argv[1]];
  NSDictionary *r=AACPCMProbeFile(path,32000);
  NSLog(@"PCM decoder smoke test: %@",r);
  if(![r[@"result"] isEqual:@"decoded-only"])return 3;
  if([r[@"frames"] intValue]<15000||[r[@"frames"] intValue]>16000)return 4;
  if([r[@"peak"] doubleValue]<0.10 || [r[@"rms"] doubleValue]<0.02)return 5;
  if(![r[@"uplink"] isEqual:@"UNAVAILABLE"]||[r[@"remoteAudible"] boolValue]||[r[@"sentFrames"] integerValue]!=0)return 6;
  NSLog(@"PASS: decoder converts 48kHz stereo wave to at most 2s 16kHz mono s16 and fails closed on uplink");
 }
 return 0;
}
