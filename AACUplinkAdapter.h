#ifndef AAC_UPLINK_ADAPTER_H
#define AAC_UPLINK_ADAPTER_H
#import <Foundation/Foundation.h>
#include <stdint.h>
/* Explicitly unavailable until a DEVICE-VALIDATED upstream route is found.
   Do not fake success by substituting AVAudioPlayer, an output AudioUnit,
   or a recording tap. This header performs NO private API calls. */
static inline BOOL AACUplinkRouteAvailable(void){return NO;}
static inline NSString *AACUplinkRouteReason(void){
 return @"unsupported-on-ios-17.3-no-verified-cellular-uplink-interface";
}
static inline BOOL AACUplinkSubmitPCM(const int16_t *samples,NSUInteger frames,NSUUID *uuid){
 (void)samples;(void)frames;(void)uuid;
 return NO; /* failure is intentional and testable */
}
#endif
