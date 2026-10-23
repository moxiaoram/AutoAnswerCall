#ifndef CA_BATTLE_CORE_H
#define CA_BATTLE_CORE_H
#include <stdbool.h>
#include <stdint.h>

/* Values describe observed state; they are not inferred from Hook names. */
typedef enum { CAUnknown=0, CAHome=1, CASearching=2, CAOpponent=3, CAFighting=4, CASettlement=5 } CAScene;
typedef enum { CAIdle=0, CAWaitSearch=1, CADeploy=2, CAWaitDeploy=3, CAWaitBattle=4, CAWaitEnd=5, CAWaitHome=6, CADone=7, CAError=8 } CAPhase;
typedef enum { CANoAction=0, CASearch=1, CADeployOne=2, CAEndBattle=3, CAReturnHome=4 } CAAction;

enum {
    CAWorldHasScene             = 1u << 0,
    CAWorldHasRevision          = 1u << 1,
    CAWorldHasTimestamp         = 1u << 2,
    CAWorldHasOpponentID        = 1u << 3,
    CAWorldHasOpponentResources = 1u << 4,
    CAWorldHasBattleLoot        = 1u << 5,
    CAWorldHasTroops             = 1u << 6
};
#define CAWorldBaseFields (CAWorldHasScene | CAWorldHasRevision | CAWorldHasTimestamp)

typedef struct {
    CAScene scene;
    uint64_t opponentID; /* Ephemeral local opponent identity; never an account ID. */
    uint64_t revision; /* Must increase for each fresh successful observation. */
    double observedAtMonotonic; /* Same monotonic clock as NSProcessInfo.systemUptime. */
    uint32_t validFields; /* Missing is distinct from a legitimate zero. */
    uint32_t evidenceFlags; /* Backend-defined provenance flags, not a confidence score. */
    uint64_t gold, elixir, dark; /* Current opponent's remaining loot for candidate filtering. */
    uint64_t lootGold, lootElixir, lootDark; /* Cumulative loot earned in this battle. */
    uint32_t remainingUnits, deployedUnits; /* Actual counts; one accepted deploy must change each by exactly one. */
} CAWorld;

typedef struct {
    uint64_t minGold, minElixir, minDark;
    uint32_t maxSearch, maxUnits;
    double actionTimeout, battleTimeout;
    double noLootGrowthTimeout; /* Set to 5.0 seconds for the requested policy. */
} CABattleConfig;

typedef struct {
    CAPhase phase;
    CABattleConfig config;
    uint32_t searches, completedBattles, baselineDeployed, deployed;
    uint32_t expectedRemainingUnits;
    uint64_t lastRevision, commandRevision, searchOpponentID, battleOpponentID;
    uint64_t lastLootGold, lastLootElixir, lastLootDark;
    double deadline, battleDeadline, lastLootGrowthAt;
    bool lootBaselineSet;
    const char *reason;
} CABattle;

static inline uint32_t CAWorldRequiredFields(CAScene scene) {
    uint32_t fields = CAWorldBaseFields;
    switch (scene) {
        case CAHome: case CASearching: return fields;
        case CAOpponent: return fields | CAWorldHasOpponentID | CAWorldHasOpponentResources | CAWorldHasTroops;
        case CAFighting: return fields | CAWorldHasOpponentID | CAWorldHasBattleLoot | CAWorldHasTroops;
        case CASettlement: return fields | CAWorldHasOpponentID | CAWorldHasBattleLoot;
        default: return fields;
    }
}
static inline uint32_t CAWorldMissingFields(CAWorld w) {
    if (w.scene < CAUnknown || w.scene > CASettlement) return CAWorldRequiredFields(CAUnknown);
    return CAWorldRequiredFields(w.scene) & ~w.validFields;
}
static inline void CABattleFail(CABattle *b, const char *reason) { b->phase=CAError; b->reason=reason; }
static inline bool CABattleRunning(const CABattle *b) { return b->phase>=CAWaitSearch && b->phase<=CAWaitHome; }
static inline CAAction CABattleSearch(CABattle *b, CAWorld w, double now) {
    if (b->searches >= b->config.maxSearch) { CABattleFail(b,"search-limit"); return CANoAction; }
    ++b->searches; b->phase=CAWaitSearch; b->commandRevision=w.revision;
    b->searchOpponentID=(w.validFields & CAWorldHasOpponentID) ? w.opponentID : 0; b->deadline=now+b->config.actionTimeout;
    b->reason="await-new-opponent"; return CASearch;
}
static inline CAAction CABattleStart(CABattle *b, CABattleConfig c, CAWorld w, double now) {
    *b=(CABattle){.config=c,.lastRevision=w.revision};
    if (!c.maxSearch || !c.maxUnits || !(c.actionTimeout>0 && c.actionTimeout<=300) ||
        !(c.battleTimeout>0 && c.battleTimeout<=1800) || c.noLootGrowthTimeout!=5.0) {
        CABattleFail(b,"invalid-config"); return CANoAction;
    }
    if (CAWorldMissingFields(w) || !w.revision || !(w.observedAtMonotonic>0) || w.scene!=CAHome) {
        CABattleFail(b,"start-requires-complete-fresh-home-observation"); return CANoAction;
    }
    return CABattleSearch(b,w,now);
}
static inline bool CABattleLootIncreased(CABattle *b, CAWorld w, double now) {
    if (!b->lootBaselineSet) {
        b->lastLootGold=w.lootGold; b->lastLootElixir=w.lootElixir; b->lastLootDark=w.lootDark;
        b->lastLootGrowthAt=now; b->lootBaselineSet=true; return false;
    }
    if (w.lootGold < b->lastLootGold || w.lootElixir < b->lastLootElixir || w.lootDark < b->lastLootDark) {
        CABattleFail(b,"cumulative-loot-counter-regressed"); return false;
    }
    bool increased = w.lootGold>b->lastLootGold || w.lootElixir>b->lastLootElixir || w.lootDark>b->lastLootDark;
    if (increased) {
        b->lastLootGrowthAt=now; b->lastLootGold=w.lootGold; b->lastLootElixir=w.lootElixir; b->lastLootDark=w.lootDark;
    }
    return increased;
}
static inline CAAction CABattleTick(CABattle *b, CAWorld w, double now) {
    if (!CABattleRunning(b)) return CANoAction;
    if (!w.revision || !(w.observedAtMonotonic>0)) { CABattleFail(b,"invalid-observation-metadata"); return CANoAction; }
    if (CAWorldMissingFields(w)) { CABattleFail(b,"required-world-fields-missing"); return CANoAction; }
    if (now >= b->deadline) { CABattleFail(b,"confirmation-timeout"); return CANoAction; }
    if (w.revision < b->lastRevision) { CABattleFail(b,"observation-revision-regressed"); return CANoAction; }
    if (w.revision == b->lastRevision) return CANoAction;
    b->lastRevision=w.revision;
    if (w.scene<CAUnknown || w.scene>CASettlement) { CABattleFail(b,"invalid-game-scene"); return CANoAction; }
    if (w.scene==CAUnknown) { CABattleFail(b,"unknown-game-state"); return CANoAction; }

    /* A confirmed settlement is the only transition that permits return-home. */
    if (w.scene==CASettlement && b->phase!=CAWaitSearch && b->phase!=CAWaitHome) {
        if (b->battleOpponentID && w.opponentID!=b->battleOpponentID) { CABattleFail(b,"opponent-changed-before-settlement"); return CANoAction; }
        ++b->completedBattles; b->phase=CAWaitHome; b->deadline=now+b->config.actionTimeout;
        b->reason="settlement-confirmed-await-home"; b->commandRevision=w.revision; return CAReturnHome;
    }
    if (b->phase==CAWaitHome) {
        if (w.scene==CAHome) {
            b->battleOpponentID=0; b->searchOpponentID=(w.validFields & CAWorldHasOpponentID) ? w.opponentID : 0;
            if (b->searches>=b->config.maxSearch) { b->phase=CADone; b->reason="search-limit-reached-home-confirmed"; return CANoAction; }
            return CABattleSearch(b,w,now);
        }
        if (w.scene!=CASettlement) { CABattleFail(b,"unexpected-scene-while-returning-home"); return CANoAction; }
        return CANoAction;
    }

    if (b->phase!=CAWaitSearch && w.scene!=CAHome && w.scene!=CASearching &&
        b->battleOpponentID && w.opponentID!=b->battleOpponentID) {
        CABattleFail(b,"opponent-changed-during-battle"); return CANoAction;
    }
    if (w.scene==CAHome && b->phase!=CAWaitSearch) { CABattleFail(b,"unexpected-home-before-settlement"); return CANoAction; }

    if (b->phase==CAWaitSearch) {
        if (w.scene==CAHome || w.scene==CASearching) return CANoAction;
        if (w.scene!=CAOpponent) { CABattleFail(b,"unexpected-search-state"); return CANoAction; }
        if (!w.opponentID || w.opponentID==b->searchOpponentID) return CANoAction;
        if (w.gold<b->config.minGold || w.elixir<b->config.minElixir || w.dark<b->config.minDark)
            return CABattleSearch(b,w,now);
        b->battleOpponentID=w.opponentID; b->baselineDeployed=w.deployedUnits; b->deployed=0;
        b->expectedRemainingUnits=w.remainingUnits; b->lootBaselineSet=false;
        b->battleDeadline=now+b->config.battleTimeout; b->phase=CADeploy; b->reason="candidate-passed-resource-threshold";
    }

    if (b->phase==CAWaitDeploy) {
        if (w.scene!=CAOpponent && w.scene!=CAFighting) { CABattleFail(b,"unexpected-scene-during-deploy-confirmation"); return CANoAction; }
        if (w.deployedUnits < b->baselineDeployed || w.remainingUnits > b->expectedRemainingUnits) {
            CABattleFail(b,"deployment-counter-regressed"); return CANoAction;
        }
        uint32_t count=w.deployedUnits-b->baselineDeployed;
        if (count==b->deployed) return CANoAction;
        if (count!=b->deployed+1 || b->expectedRemainingUnits==0 || w.remainingUnits+1!=b->expectedRemainingUnits) {
            CABattleFail(b,"deployment-not-confirmed-as-exactly-one-unit"); return CANoAction;
        }
        b->deployed=count; b->expectedRemainingUnits=w.remainingUnits; b->phase=CADeploy; b->reason="single-unit-deployment-confirmed";
    }

    if (w.scene==CAFighting && b->phase!=CAWaitEnd) {
        (void)CABattleLootIncreased(b,w,now);
        if (b->phase==CAError) return CANoAction;
        if (now>=b->battleDeadline || now-b->lastLootGrowthAt>=b->config.noLootGrowthTimeout) {
            b->phase=CAWaitEnd; b->deadline=now+b->config.actionTimeout; b->commandRevision=w.revision;
            b->reason=now>=b->battleDeadline ? "battle-timeout-request-end" : "loot-growth-stalled-request-end";
            return CAEndBattle;
        }
    }

    if (b->phase==CADeploy) {
        if (w.scene!=CAOpponent && w.scene!=CAFighting) { CABattleFail(b,"unexpected-scene-before-deployment"); return CANoAction; }
        if (w.remainingUnits && b->deployed<b->config.maxUnits && now<b->battleDeadline) {
            b->phase=CAWaitDeploy; b->commandRevision=w.revision; b->expectedRemainingUnits=w.remainingUnits;
            b->deadline=now+b->config.actionTimeout; b->reason="await-single-unit-deployment"; return CADeployOne;
        }
        if (!b->deployed) { CABattleFail(b,"no-deployment-confirmed"); return CANoAction; }
        b->phase=CAWaitBattle; b->deadline=b->battleDeadline+b->config.actionTimeout; b->reason="await-loot-growth-or-battle-timeout";
    }

    if (b->phase==CAWaitBattle) {
        if (w.scene==CAOpponent) return CANoAction; /* Wait for an observed active fight. */
        if (w.scene!=CAFighting) { CABattleFail(b,"unexpected-scene-while-waiting-for-battle"); return CANoAction; }
        if (now>=b->battleDeadline || (b->lootBaselineSet && now-b->lastLootGrowthAt>=b->config.noLootGrowthTimeout)) {
            b->phase=CAWaitEnd; b->deadline=now+b->config.actionTimeout; b->commandRevision=w.revision;
            b->reason=now>=b->battleDeadline ? "battle-timeout-request-end" : "loot-growth-stalled-request-end";
            return CAEndBattle;
        }
    }
    if (b->phase==CAWaitEnd) {
        if (w.scene!=CAFighting) { CABattleFail(b,"unexpected-scene-awaiting-settlement"); return CANoAction; }
        return CANoAction;
    }
    return CANoAction;
}
#endif
