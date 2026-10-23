#import <Foundation/Foundation.h>
#import "CABattleCore.h"

/* Backend must use verified APIs for the exact game build; diagnostic offsets/raw words are not APIs. */
@protocol CAVerifiedGameBackend <NSObject>
@property(nonatomic,readonly) NSString *backendName;
@property(nonatomic,readonly) NSString *expectedBundleID;
@property(nonatomic,readonly) NSString *expectedBuildVersion;
/* Verify exact executable UUID, ABI/signatures, object lifecycle, main-thread rules and deployment plan. */
- (BOOL)validate:(NSError **)error;
/* Fill CAWorld only from a fresh real observation; set validFields and observedAtMonotonic on every successful read. */
- (BOOL)readWorld:(CAWorld *)world error:(NSError **)error;
/* YES means request accepted, not success. Core waits for a new observed state/revision. */
- (BOOL)searchOpponent:(NSError **)error;
/* Submit exactly one unit from a verified plan; no raw diagnostic argument replay. */
- (BOOL)deployOneUnit:(NSError **)error;
/* Request end/confirm. Core waits for a real settlement observation. */
- (BOOL)endBattle:(NSError **)error;
/* After confirmed settlement, request return home. Core waits for observed CAHome. */
- (BOOL)returnHome:(NSError **)error;
/* Cancel all deferred submissions/confirmation steps; idempotent. Accepted game commands cannot be undone. */
- (void)cancelPendingActions;
@end

@interface CABattleRuntime : NSObject
@property(nonatomic,readonly) BOOL running;
@property(nonatomic,readonly) NSString *statusText;
+ (instancetype)shared;
- (BOOL)registerBackend:(id<CAVerifiedGameBackend>)backend error:(NSError **)error;
- (BOOL)start:(CABattleConfig)config error:(NSError **)error;
- (void)stop:(NSString *)reason;
- (NSDictionary *)snapshot;
@end
