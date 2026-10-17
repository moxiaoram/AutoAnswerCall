#import <Foundation/Foundation.h>
/* A connection cannot prove who answered. Suppress audio unless an automatic button
   event was dispatched for this UUID; this is still only a local-output attempt. */
static void AACCancelForObservedConnection(NSMutableDictionary *state){
 state[@"connectedObserved"]=@YES;
 if(![state[@"buttonTapped"] boolValue])state[@"audioSuppressed"]=@YES;
 state[@"scheduled"]=@NO;state[@"pending"]=@NO;state[@"attempted"]=@YES;
 state[@"callGeneration"]=@([state[@"callGeneration"] unsignedIntegerValue]+1);
}
static BOOL AACMaySubmit(NSDictionary *state,NSUInteger generation,BOOL present,BOOL connected,BOOL ended){
 return present&&!connected&&!ended&&![state[@"connectedObserved"] boolValue]&&generation==[state[@"callGeneration"] unsignedIntegerValue];
}
/* Opt-in LOCAL playback only after an actual answer button event AND a later
   observed connection. Neither event proves that the tweak, rather than the
   user/system, connected the call. This never injects microphone/uplink audio. */
static BOOL AACMayAutoplay(NSDictionary *state){
 return [state[@"buttonTapped"] boolValue]&&[state[@"connectedObserved"] boolValue]&&
        ![state[@"audioSuppressed"] boolValue]&&![state[@"audioPlayed"] boolValue];
}
