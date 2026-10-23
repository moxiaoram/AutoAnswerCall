#ifndef CA_BATTLE_CORE_H
#define CA_BATTLE_CORE_H
#include <stdbool.h>
#include <stdint.h>

/* Pure state machine only. It cannot observe or control the game by itself. */
typedef enum { CAUnknown, CAHome, CASearching, CAOpponent, CAFighting, CASettlement } CAScene;
typedef enum { CAIdle, CAWaitSearch, CADeploy, CAWaitDeploy, CAWaitBattle, CAWaitEnd, CAWaitHome, CADone, CAError } CAPhase;
typedef enum { CANoAction, CASearch, CADeployOne, CAEndBattle, CAReturnHome } CAAction;
typedef struct {
    CAScene scene;
    uint64_t opponentID; /* nonzero local scene identity; changes for each candidate */
    uint64_t revision; /* monotonic version of a fresh backend observation */
    uint64_t gold, elixir, dark; /* current opponent's remaining loot, for threshold filtering */
    uint64_t lootGoldEarned, lootElixirEarned, lootDarkEarned; /* cumulative loot gained in this battle */
    uint32_t remainingUnits, deployedUnits; /* actual observed counts for this battle */
} CAWorld;
typedef struct {
    uint64_t minGold, minElixir, minDark;
    uint32_t maxSearch, maxUnits, maxBattles;
    double actionTimeout, battleTimeout, noLootGrowthTimeout;
} CABattleConfig;
typedef struct {
    CAPhase phase;
    CABattleConfig config;
    uint32_t searches, battlesCompleted, baselineDeployed, deployed;
    uint64_t lastRevision, commandRevision, searchOpponentID, battleOpponentID;
    uint64_t lastLootGold, lastLootElixir, lastLootDark;
    double deadline, battleDeadline, lastLootGrowthAt;
    bool battleStarted;
    const char *reason;
} CABattle;
static inline void CABattleFail(CABattle *b, const char *reason) { b->phase = CAError; b->reason = reason; }
static inline bool CABattleRunning(const CABattle *b) { return b->phase >= CAWaitSearch && b->phase <= CAWaitHome; }
static inline bool CALootRegressed(const CABattle *b, const CAWorld *w) {
    return w->lootGoldEarned < b->lastLootGold || w->lootElixirEarned < b->lastLootElixir || w->lootDarkEarned < b->lastLootDark;
}
static inline bool CALootIncreased(const CABattle *b, const CAWorld *w) {
    return w->lootGoldEarned > b->lastLootGold || w->lootElixirEarned > b->lastLootElixir || w->lootDarkEarned > b->lastLootDark;
}
static inline void CAUpdateLoot(CABattle *b, const CAWorld *w, double now) {
    b->lastLootGold = w->lootGoldEarned;
    b->lastLootElixir = w->lootElixirEarned;
    b->lastLootDark = w->lootDarkEarned;
    b->lastLootGrowthAt = now;
}
static inline CAAction CABattleSearch(CABattle *b, CAWorld w, double now) {
    if (b->searches >= b->config.maxSearch) { b->phase=CADone; b->reason="search-limit"; return CANoAction; }
    ++b->searches; b->phase=CAWaitSearch; b->commandRevision=w.revision;
    b->searchOpponentID=w.opponentID;
    b->deadline=now+b->config.actionTimeout; b->reason="await-opponent"; return CASearch;
}
static inline CAAction CABattleStart(CABattle *b, CABattleConfig c, CAWorld w, double now) {
    *b=(CABattle){.config=c, .lastRevision=w.revision};
    if (!c.maxSearch || !c.maxUnits || !c.maxBattles || !(c.actionTimeout>0 && c.actionTimeout<=300) ||
        !(c.battleTimeout>0 && c.battleTimeout<=1800) || !(c.noLootGrowthTimeout>0 && c.noLootGrowthTimeout<=300)) {
        CABattleFail(b,"invalid-config"); return CANoAction;
    }
    if (w.scene!=CAHome || !w.revision) { CABattleFail(b,"start-requires-confirmed-home"); return CANoAction; }
    return CABattleSearch(b,w,now);
}
static inline CAAction CABattleTick(CABattle *b, CAWorld w, double now) {
    if (!CABattleRunning(b)) return CANoAction;
    if (now>=b->deadline) { CABattleFail(b,"confirmation-timeout"); return CANoAction; }
    if (w.revision<b->lastRevision) { CABattleFail(b,"observation-revision-regressed"); return CANoAction; }
    if (w.revision==b->lastRevision) return CANoAction;
    b->lastRevision=w.revision;
    if (w.scene==CAUnknown) { CABattleFail(b,"unknown-game-state"); return CANoAction; }
    if (b->battleOpponentID && w.opponentID!=b->battleOpponentID && w.scene!=CAHome && w.scene!=CASettlement) {
        CABattleFail(b,"opponent-changed-during-battle"); return CANoAction;
    }

    /* A settlement is accepted only after a candidate was actually selected. */
    if (w.scene==CASettlement && b->battleOpponentID && b->phase!=CAWaitSearch) {
        ++b->battlesCompleted;
        b->battleOpponentID=0; b->battleStarted=false;
        if (b->battlesCompleted>=b->config.maxBattles) {
            b->phase=CADone; b->reason="battle-limit-reached"; return CANoAction;
        }
        b->phase=CAWaitHome; b->deadline=now+b->config.actionTimeout;
        b->commandRevision=w.revision; b->reason="await-home-after-settlement";
        return CAReturnHome;
    }

    if (b->phase==CAWaitHome) {
        if (w.scene!=CAHome) return CANoAction;
        return CABattleSearch(b,w,now);
    }
    if (w.scene==CAHome && b->phase!=CAWaitSearch) { CABattleFail(b,"unexpected-home"); return CANoAction; }

    if (b->phase==CAWaitSearch) {
        if (w.scene==CASearching) return CANoAction;
        if (w.scene!=CAOpponent) { CABattleFail(b,"unexpected-search-state"); return CANoAction; }
        if (!w.opponentID || w.opponentID==b->searchOpponentID) return CANoAction;
        if (w.gold<b->config.minGold || w.elixir<b->config.minElixir || w.dark<b->config.minDark)
            return CABattleSearch(b,w,now);
        b->battleOpponentID=w.opponentID; b->baselineDeployed=w.deployedUnits; b->deployed=0; b->battleStarted=false;
        b->lastLootGold=0; b->lastLootElixir=0; b->lastLootDark=0; b->phase=CADeploy;
        b->battleDeadline=now+b->config.battleTimeout; b->reason="opponent-qualified";
    }

    if (b->battleOpponentID && w.scene==CAFighting) {
        if (!b->battleStarted) {
            b->battleStarted=true;
            CAUpdateLoot(b,&w,now); /* start the no-growth clock on first confirmed fighting state */
        } else {
            if (CALootRegressed(b,&w)) { CABattleFail(b,"loot-counter-regressed"); return CANoAction; }
            if (CALootIncreased(b,&w)) CAUpdateLoot(b,&w,now);
        }
    }

    if (b->phase==CAWaitDeploy) {
        if (w.scene!=CAOpponent && w.scene!=CAFighting) { CABattleFail(b,"unexpected-deploy-state"); return CANoAction; }
        if (w.deployedUnits<b->baselineDeployed) { CABattleFail(b,"deployment-counter-regressed"); return CANoAction; }
        uint32_t count=w.deployedUnits-b->baselineDeployed;
        if (count<b->deployed) { CABattleFail(b,"deployment-counter-regressed"); return CANoAction; }
        if (count==b->deployed) return CANoAction;
        if (count!=b->deployed+1) { CABattleFail(b,"unexpected-deployment-count"); return CANoAction; }
        b->deployed=count; b->phase=CADeploy;
    }
    if (b->phase==CADeploy) {
        if (w.scene!=CAOpponent && w.scene!=CAFighting) { CABattleFail(b,"unexpected-deploy-state"); return CANoAction; }
        if (w.remainingUnits && b->deployed<b->config.maxUnits && now<b->battleDeadline) {
            b->phase=CAWaitDeploy; b->commandRevision=w.revision;
            b->deadline=now+b->config.actionTimeout; b->reason="await-deployment"; return CADeployOne;
        }
        if (!b->deployed) { CABattleFail(b,"no-deployable-units"); return CANoAction; }
        b->phase=CAWaitBattle; b->deadline=b->battleDeadline+b->config.actionTimeout; b->reason="await-loot-growth-or-timeout";
    }
    if (b->phase==CAWaitBattle) {
        /* Deployment may finish on the opponent scene before the battle scene is confirmed. */
        if (w.scene==CAOpponent) return CANoAction;
        if (w.scene!=CAFighting) { CABattleFail(b,"end-requires-confirmed-battle"); return CANoAction; }
        if (b->battleStarted && now-b->lastLootGrowthAt>=b->config.noLootGrowthTimeout) {
            b->phase=CAWaitEnd; b->commandRevision=w.revision; b->deadline=now+b->config.actionTimeout;
            b->reason="no-loot-growth-timeout"; return CAEndBattle;
        }
        if (now>=b->battleDeadline) {
            b->phase=CAWaitEnd; b->commandRevision=w.revision; b->deadline=now+b->config.actionTimeout;
            b->reason="battle-hard-timeout"; return CAEndBattle;
        }
    }
    if (b->phase==CAWaitEnd && w.scene!=CAFighting && w.scene!=CASettlement) {
        CABattleFail(b,"unexpected-end-state");
    }
    return CANoAction;
}
#endif
