#import <Foundation/Foundation.h>
/* Observed connection cannot prove who answered. Suppression stays sticky per UUID. */
static void AACCancelForObservedConnection(NSMutableDictionary *state){
 state[@"connectedObserved"]=@YES;state[@"audioSuppressed"]=@YES;
 state[@"scheduled"]=@NO;state[@"pending"]=@NO;state[@"attempted"]=@YES;
 state[@"callGeneration"]=@([state[@"callGeneration"] unsignedIntegerValue]+1);
}
static BOOL AACMaySubmit(NSDictionary *state,NSUInteger generation,BOOL present,BOOL connected,BOOL ended){
 return present&&!connected&&!ended&&![state[@"connectedObserved"] boolValue]&&generation==[state[@"callGeneration"] unsignedIntegerValue];
}
static BOOL AACMayAutoplay(NSDictionary *state){
 return [state[@"accepted"] boolValue]&&![state[@"audioSuppressed"] boolValue]&&[state[@"ownershipConfirmed"] boolValue];
 /* Current CXCall observer/transaction path never sets ownershipConfirmed. */
}
