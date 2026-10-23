#import <Foundation/Foundation.h>
#import "CABattleCore.h"

// All calls run on the main thread and must return promptly, without blocking.
// This repository does not supply an implementation of this protocol.
@protocol CAVerifiedGameBackend <NSObject>
@property(nonatomic,readonly) NSString *backendName;
@property(nonatomic,readonly) NSString *expectedBundleID;
@property(nonatomic,readonly) NSString *expectedBuildVersion;
// Validate exact image UUID, signatures, lifecycle, thread and plan prerequisites.
- (BOOL)validate:(NSError **)error;
// Fresh observed game state, not generated values. CAWorld.gold/elixir/dark are remaining opponent loot; loot*Earned are cumulative gains for the current battle. Errors must fail closed.
- (BOOL)readWorld:(CAWorld *)world error:(NSError **)error;
// YES = request accepted only; core waits for observed confirmation.
- (BOOL)searchOpponent:(NSError **)error;
// Select a real troop + valid location from backend's verified deployment plan.
// Submit exactly one unit. No replay of raw argument words from diagnostic logs.
- (BOOL)deployOneUnit:(NSError **)error;
// Handle end/confirm flow, then observe settlement; do not claim success here.
- (BOOL)endBattle:(NSError **)error;
// Navigate from confirmed settlement back to the home scene; do not assume success until readWorld reports CAHome.
- (BOOL)returnHome:(NSError **)error;
// Cancel all deferred submissions/confirmation steps on stop/error/settlement.
// Already accepted game commands cannot be undone. Must be idempotent.
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
