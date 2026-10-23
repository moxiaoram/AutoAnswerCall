#ifndef CA_REPLAY_SIMULATION_H
#define CA_REPLAY_SIMULATION_H
#include "CABattleCore.h"
#include <string.h>

/*
 * Deterministic OFFLINE replay. All CAWorld values below are synthetic test
 * fixtures. They are deliberately separate from observed Hook offsets and
 * must never be represented as live game state or sent to a game backend.
 */
#define CAReplayMaxEvents 16

typedef struct {
    const char *label;
    double now;
    uint64_t revision;
    CAScene scene;
    CAAction action;
    CAPhase phaseAfter;
    bool passed;
} CAReplayEvent;

typedef struct {
    bool passed;
    const char *failure;
    uint32_t eventCount;
    uint32_t searches;
    uint32_t completedBattles;
    uint32_t confirmedDeployed;
    CAPhase finalPhase;
    CAReplayEvent events[CAReplayMaxEvents];
} CAReplayResult;

static inline CAWorld CAReplayWorld(CAScene scene, uint64_t revision, double now) {
    CAWorld w = {0};
    w.scene = scene;
    w.revision = revision;
    w.observedAtMonotonic = now - 0.01;
    w.validFields = CAWorldRequiredFields(scene);
    return w;
}

static inline void CAReplayAppend(CAReplayResult *r, const char *label, double now,
                                  CAWorld w, CAAction action, const CABattle *b,
                                  bool passed) {
    if (r->eventCount >= CAReplayMaxEvents) { r->passed = false; r->failure = "replay-event-capacity-exceeded"; return; }
    r->events[r->eventCount++] = (CAReplayEvent){label, now, w.revision, w.scene,
                                                action, b->phase, passed};
    if (!passed) { r->passed = false; r->failure = label; }
}

static inline CAReplayResult CARunOfflineReplay(void) {
    CAReplayResult r = {.passed=true, .failure=""};
    CABattle b = {0};
    CABattleConfig c = {.minGold=500, .minElixir=500, .minDark=0,
        .maxSearch=2, .maxUnits=1, .actionTimeout=20.0,
        .battleTimeout=60.0, .noLootGrowthTimeout=5.0};

    CAWorld w = CAReplayWorld(CAHome, 1, 100.0);
    CAAction a = CABattleStart(&b, c, w, 100.0);
    CAReplayAppend(&r, "start-at-home-requests-search", 100.0, w, a, &b, a==CASearch && b.phase==CAWaitSearch);

    w = CAReplayWorld(CAOpponent, 2, 101.0);
    w.opponentID=7001; w.gold=1200; w.elixir=1500; w.dark=50;
    w.remainingUnits=2; w.deployedUnits=0;
    a = CABattleTick(&b, w, 101.0);
    CAReplayAppend(&r, "qualified-opponent-requests-one-unit", 101.0, w, a, &b, a==CADeployOne && b.phase==CAWaitDeploy);

    w = CAReplayWorld(CAOpponent, 3, 102.0);
    w.opponentID=7001; w.gold=1200; w.elixir=1500; w.dark=50;
    w.remainingUnits=1; w.deployedUnits=1;
    a = CABattleTick(&b, w, 102.0);
    CAReplayAppend(&r, "deployment-confirmed-plus-one-minus-one", 102.0, w, a, &b,
                   a==CANoAction && b.deployed==1 && b.phase==CAWaitBattle);
    r.confirmedDeployed = b.deployed;

    w = CAReplayWorld(CAFighting, 4, 103.0);
    w.opponentID=7001; w.lootGold=0; w.lootElixir=0; w.lootDark=0;
    w.remainingUnits=1; w.deployedUnits=1;
    a = CABattleTick(&b, w, 103.0);
    CAReplayAppend(&r, "battle-starts-loot-baseline", 103.0, w, a, &b,
                   a==CANoAction && b.lootBaselineSet && b.lastLootGrowthAt==103.0);

    w = CAReplayWorld(CAFighting, 5, 107.9);
    w.opponentID=7001; w.lootGold=0; w.lootElixir=0; w.lootDark=0;
    w.remainingUnits=1; w.deployedUnits=1;
    a = CABattleTick(&b, w, 107.9);
    CAReplayAppend(&r, "four-point-nine-seconds-no-growth-does-not-end", 107.9, w, a, &b,
                   a==CANoAction && b.phase==CAWaitBattle);

    w = CAReplayWorld(CAFighting, 6, 108.1);
    w.opponentID=7001; w.lootGold=0; w.lootElixir=0; w.lootDark=0;
    w.remainingUnits=1; w.deployedUnits=1;
    a = CABattleTick(&b, w, 108.1);
    CAReplayAppend(&r, "five-seconds-no-growth-requests-end", 108.1, w, a, &b,
                   a==CAEndBattle && b.phase==CAWaitEnd);

    w = CAReplayWorld(CASettlement, 7, 109.0);
    w.opponentID=7001; w.lootGold=0; w.lootElixir=0; w.lootDark=0;
    a = CABattleTick(&b, w, 109.0);
    CAReplayAppend(&r, "settlement-confirmed-requests-return-home", 109.0, w, a, &b,
                   a==CAReturnHome && b.phase==CAWaitHome && b.completedBattles==1);

    w = CAReplayWorld(CAHome, 8, 110.0);
    a = CABattleTick(&b, w, 110.0);
    CAReplayAppend(&r, "home-confirmed-requests-next-search", 110.0, w, a, &b,
                   a==CASearch && b.searches==2 && b.phase==CAWaitSearch);

    w = CAReplayWorld(CAOpponent, 9, 111.0);
    w.opponentID=7002; w.gold=800; w.elixir=900; w.dark=20;
    w.remainingUnits=2; w.deployedUnits=0;
    a = CABattleTick(&b, w, 111.0);
    CAReplayAppend(&r, "next-opponent-ready-for-next-single-unit", 111.0, w, a, &b,
                   a==CADeployOne && b.phase==CAWaitDeploy && b.searches==2);

    r.searches=b.searches;
    r.completedBattles=b.completedBattles;
    r.finalPhase=b.phase;
    if (r.eventCount != 9 && r.passed) { r.passed=false; r.failure="unexpected-replay-event-count"; }
    return r;
}
#endif
