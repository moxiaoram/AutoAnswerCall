#import <Foundation/Foundation.h>
#import "CAReplaySimulation.h"
#import "CAEventLog.h"

static NSString *CAReplayActionName(CAAction a) {
    switch (a) {
        case CASearch: return @"search-request (offline only)";
        case CADeployOne: return @"deploy-one-request (offline only)";
        case CAEndBattle: return @"end-battle-request (offline only)";
        case CAReturnHome: return @"return-home-request (offline only)";
        default: return @"no-action";
    }
}
static NSString *CAReplayPhaseName(CAPhase p) {
    switch (p) {
        case CAIdle: return @"idle"; case CAWaitSearch: return @"waitSearch";
        case CADeploy: return @"deploy"; case CAWaitDeploy: return @"waitDeploy";
        case CAWaitBattle: return @"waitBattle"; case CAWaitEnd: return @"waitEnd";
        case CAWaitHome: return @"waitHome"; case CADone: return @"done"; case CAError: return @"error";
    }
    return @"invalid";
}
static NSString *CAReplaySceneName(CAScene s) {
    switch (s) {
        case CAHome: return @"home"; case CASearching: return @"searching";
        case CAOpponent: return @"opponent"; case CAFighting: return @"fighting";
        case CASettlement: return @"settlement"; default: return @"unknown";
    }
}
NSDictionary *CARunOfflineReplayAndLog(void) {
    CAEvent(@"replay.start", @{
        @"mode": @"offline-synthetic-world-replay",
        @"realGameBackendUsed": @NO,
        @"gameActionsSent": @NO,
        @"observedTraceReference": @"部落4.json",
        @"observedCallerOffsetsAreExecutableAPIs": @NO,
        @"note": @"Observed caller offsets are read-only correlation metadata. Replay worlds and resource/troop counts are synthetic test fixtures."});
    CAReplayResult result = CARunOfflineReplay();
    NSMutableArray *events = [NSMutableArray new];
    for (uint32_t i=0; i<result.eventCount; ++i) {
        CAReplayEvent e=result.events[i];
        NSDictionary *item=@{@"index":@(i+1), @"label":[NSString stringWithUTF8String:e.label ?: ""],
            @"simulatedMonotonicSeconds":@(e.now), @"revision":@(e.revision),
            @"scene":CAReplaySceneName(e.scene), @"schedulerAction":CAReplayActionName(e.action),
            @"phaseAfter":CAReplayPhaseName(e.phaseAfter), @"passed":@(e.passed)};
        [events addObject:item];
        CAEvent(@"replay.step", item);
    }
    NSDictionary *summary=@{@"mode":@"offline-synthetic-world-replay", @"passed":@(result.passed),
        @"failure": [NSString stringWithUTF8String:result.failure ?: ""], @"eventCount":@(result.eventCount),
        @"searchRequests":@(result.searches), @"completedBattles":@(result.completedBattles),
        @"confirmedDeployedUnits":@(result.confirmedDeployed), @"finalPhase":CAReplayPhaseName(result.finalPhase),
        @"realGameBackendUsed":@NO, @"gameActionsSent":@NO, @"events":events};
    CAEvent(@"replay.complete", summary);
    return summary;
}
