#ifndef AAC_PCM_DECODER_H
#define AAC_PCM_DECODER_H
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AACPCMQueue.h"
#import "AACUplinkAdapter.h"
/* Offline, decode-only probe. NO AVAudioSession activation, output AudioUnit,
   MIC capture, daemon injection, file writing or cellular uplink modification.
   Max 2 seconds of output and 5 MiB compressed input to bound CPU/memory.
   16 kHz mono S16 little-endian is an experiment format, NOT a discovery of
   the device's real telephony uplink format. */
static inline NSDictionary *AACPCMProbeFile(NSString *path,uint32_t requestedFrames){
 const uint32_t maxFrames=(requestedFrames>32000u)?32000u:requestedFrames;
 NSMutableDictionary *result=[@{ @"result":@"decode-failed", @"format":@"s16le-mono-16000", @"frames":@0,
  @"uplink":@"UNAVAILABLE", @"remoteAudible":@NO, @"sentFrames":@0, @"playedLocally":@NO } mutableCopy];
 if(![path isKindOfClass:NSString.class]||!path.length||maxFrames==0){result[@"error"]=@"invalid-path-or-limit";return result;}
 NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
 uint64_t bytes=[attributes[NSFileSize] unsignedLongLongValue];
 if(!bytes||bytes>5*1024*1024ULL){result[@"error"]=@"input-missing-empty-or-over-5MiB";return result;}
 ExtAudioFileRef file=NULL;
 OSStatus st=ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],&file);
 if(st!=noErr||!file){result[@"error"]=@"ExtAudioFileOpenURL";result[@"osStatus"]=@(st);return result;}
 AudioStreamBasicDescription target={0};
 target.mSampleRate=16000.0;
 target.mFormatID=kAudioFormatLinearPCM;
 target.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
 target.mFramesPerPacket=1;
 target.mChannelsPerFrame=1;
 target.mBitsPerChannel=16;
 target.mBytesPerFrame=sizeof(int16_t);
 target.mBytesPerPacket=sizeof(int16_t);
 st=ExtAudioFileSetProperty(file,kExtAudioFileProperty_ClientDataFormat,sizeof(target),&target);
 if(st!=noErr){
  result[@"error"]=@"client-format-conversion-unavailable";result[@"osStatus"]=@(st);
  ExtAudioFileDispose(file);return result;
 }
 AACPCMQueue queue={0};AACPCMStats stats={0};
 AACPCMQueueReset(&queue);
 uint32_t left=maxFrames;
 while(left){
  int16_t buffer[1024]={0};
  UInt32 frames=(left<1024)?left:1024;
  AudioBufferList audio={0};
  audio.mNumberBuffers=1;
  audio.mBuffers[0].mNumberChannels=1;
  audio.mBuffers[0].mData=buffer;
  audio.mBuffers[0].mDataByteSize=frames*sizeof(int16_t);
  st=ExtAudioFileRead(file,&frames,&audio);
  if(st!=noErr){result[@"error"]=@"ExtAudioFileRead";result[@"osStatus"]=@(st);break;}
  if(!frames)break;
  /* Validate the same bounded queue planned for a future, validated adapter. */
  size_t pushed=AACPCMQueuePush(&queue,buffer,frames);
  if(pushed!=(size_t)frames){result[@"error"]=@"pcm-queue-overflow";break;}
  int16_t consumed[1024]={0};
  size_t popped=AACPCMQueuePop(&queue,consumed,frames);
  if(popped!=(size_t)frames){result[@"error"]=@"pcm-queue-underflow";break;}
  AACPCMStatsAccumulate(&stats,consumed,popped);
  left-=frames;
 }
 ExtAudioFileDispose(file);
 result[@"frames"]=@(stats.frames);
 result[@"durationMs"]=@((double)stats.frames*1000.0/16000.0);
 result[@"peak"]=@((double)stats.peak/32768.0);
 result[@"rms"]=@(AACPCMStatsRMS(&stats));
 if(stats.frames && !result[@"error"]){result[@"result"]=@"decoded-only";}
 else if(!result[@"error"]){result[@"error"]=@"no-decodable-frames";}
 result[@"uplinkReason"]=AACUplinkRouteReason();
 return result;
}
#endif
