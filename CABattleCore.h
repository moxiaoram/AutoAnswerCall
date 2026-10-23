#ifndef CA_BATTLE_CORE_H
#define CA_BATTLE_CORE_H
#include <stdbool.h>
#include <stdint.h>

typedef enum { CAUnknown, CAHome, CASearching, CAOpponent, CAFighting, CASettlement } CAScene;
typedef enum { CAIdle, CAWaitSearch, CADeploy, CAWaitDeploy, CAWaitBattle, CAWaitEnd, CADone, CAError } CAPhase;
typedef enum { CANoAction, CASearch, CADeployOne, CAEndBattle } CAAction;
typedef struct {
    CAScene scene;
    uint64_t opponentID; /* nonzero identity for current opponent; changes after each completed search */
    uint64_t revision; /* strictly increasing fresh observations; never a timer counter */
    uint64_t gold, elixir, dark;
    uint32_t remainingUnits, deployedUnits; /* confirmed game values for this battle */
} CAWorld;
typedef struct {
    uint64_t minGold, minElixir, minDark;
    uint32_t maxSearch, maxUnits;
    double actionTimeout, battleTimeout;
} CABattleConfig;
typedef struct {
    CAPhase phase;
    CABattleConfig config;
    uint32_t searches, baselineDeployed, deployed;
    uint64_t lastRevision, commandRevision, searchOpponentID, battleOpponentID;
    double deadline, battleDeadline;
    const char *reason;
} CABattle;
static inline void CABattleFail(CABattle *b, const char *reason) { b->phase = CAError; b->reason = reason; }
static inline bool CABattleRunning(const CABattle *b) { return b->phase >= CAWaitSearch && b->phase <= CAWaitEnd; }
static inline CAAction CABattleSearch(CABattle *b, CAWorld w, double now) {
    if (b->searches >= b->config.maxSearch) { CABattleFail(b,"search-limit"); return CANoAction; }
    ++b->searches; b->phase=CAWaitSearch; b->commandRevision=w.revision;
    b->searchOpponentID=w.opponentID;
    b->deadline=now+b->config.actionTimeout; b->reason="await-opponent"; return CASearch;
}
static inline CAAction CABattleStart(CABattle *b, CABattleConfig c, CAWorld w, double now) {
    *b=(CABattle){.config=c, .lastRevision=w.revision};
    if (!c.maxSearch || !c.maxUnits || !(c.actionTimeout>0 && c.actionTimeout<=300) ||
        !(c.battleTimeout>0 && c.battleTimeout<=1800)) { CABattleFail(b,"invalid-config"); return CANoAction; }
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
    if (b->battleOpponentID && w.opponentID!=b->battleOpponentID) { CABattleFail(b,"opponent-changed-during-battle"); return CANoAction; }
    if (w.scene==CASettlement && b->phase!=CAWaitSearch) {
        b->phase=CADone; b->reason="settlement-confirmed"; return CANoAction;
    }
    if (w.scene==CAHome) { CABattleFail(b,"unexpected-home"); return CANoAction; }
    if (b->phase==CAWaitSearch) {
        if (w.scene==CASearching) return CANoAction;
        if (w.scene!=CAOpponent) { CABattleFail(b,"unexpected-search-state"); return CANoAction; }
        if (!w.opponentID || w.opponentID==b->searchOpponentID) return CANoAction;
        if (w.gold<b->config.minGold || w.elixir<b->config.minElixir || w.dark<b->config.minDark)
            return CABattleSearch(b,w,now);
        b->battleOpponentID=w.opponentID; b->baselineDeployed=w.deployedUnits; b->phase=CADeploy;
        b->battleDeadline=now+b->config.battleTimeout;
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
        b->phase=CAWaitBattle; b->deadline=b->battleDeadline+b->config.actionTimeout; b->reason="await-battle-end";
    }
    if (b->phase==CAWaitBattle && now>=b->battleDeadline) {
        if (w.scene!=CAFighting) { CABattleFail(b,"end-requires-confirmed-battle"); return CANoAction; }
        b->phase=CAWaitEnd; b->commandRevision=w.revision; b->deadline=now+b->config.actionTimeout;
        b->reason="await-settlement"; return CAEndBattle;
    }
    if ((b->phase==CAWaitBattle || b->phase==CAWaitEnd) && w.scene!=CAFighting) {
        CABattleFail(b,"unexpected-battle-state");
    }
    return CANoAction;
}
#endif
