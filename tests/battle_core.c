#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "CABattleCore.h"
static CABattleConfig cfg(void) { return (CABattleConfig){.minGold=10,.minElixir=20,.minDark=1,.maxSearch=10,.maxUnits=2,.maxBattles=2,.actionTimeout=20,.battleTimeout=60,.noLootGrowthTimeout=5}; }
static CAWorld home(uint64_t rev) { return (CAWorld){.scene=CAHome,.revision=rev}; }
static CAWorld opponent(uint64_t rev,uint64_t id) { return (CAWorld){.scene=CAOpponent,.revision=rev,.opponentID=id,.gold=10,.elixir=20,.dark=1,.remainingUnits=2}; }
static void test_no_growth_and_loop(void) {
    CABattle b; CAWorld w=home(1); assert(CABattleStart(&b,cfg(),w,0)==CASearch);
    w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne); assert(b.deployed==0);
    w.revision++; w.deployedUnits=1; w.remainingUnits=1; assert(CABattleTick(&b,w,2)==CADeployOne); assert(b.deployed==1);
    w.revision++; w.deployedUnits=2; w.remainingUnits=0; assert(CABattleTick(&b,w,3)==CANoAction && b.phase==CAWaitBattle);
    w.revision++; w.scene=CAFighting; assert(CABattleTick(&b,w,4)==CANoAction); /* start five-second clock */
    w.revision++; assert(CABattleTick(&b,w,8.9)==CANoAction);
    w.revision++; assert(CABattleTick(&b,w,9.1)==CAEndBattle); assert(b.reason && b.phase==CAWaitEnd);
    w.revision++; w.scene=CASettlement; assert(CABattleTick(&b,w,10)==CAReturnHome); assert(b.battlesCompleted==1 && b.phase==CAWaitHome);
    w=home(w.revision+1); assert(CABattleTick(&b,w,11)==CASearch); assert(b.phase==CAWaitSearch);
    w=opponent(w.revision+1,43); assert(CABattleTick(&b,w,12)==CADeployOne);
    w.revision++; w.deployedUnits=1; w.remainingUnits=1; assert(CABattleTick(&b,w,13)==CADeployOne);
    w.revision++; w.deployedUnits=2; w.remainingUnits=0; assert(CABattleTick(&b,w,14)==CANoAction && b.phase==CAWaitBattle);
    w.revision++; w.scene=CAFighting; w.lootGoldEarned=1; assert(CABattleTick(&b,w,15)==CANoAction);
    w.revision++; w.lootGoldEarned=2; assert(CABattleTick(&b,w,18)==CANoAction); /* growth resets clock */
    w.revision++; assert(CABattleTick(&b,w,22.9)==CANoAction);
    w.revision++; assert(CABattleTick(&b,w,23.1)==CAEndBattle);
    w.revision++; w.scene=CASettlement; assert(CABattleTick(&b,w,24)==CANoAction);
    assert(b.phase==CADone && b.battlesCompleted==2 && !CABattleRunning(&b));
}
static void test_filter_and_search_limit(void) {
    CABattle b; assert(CABattleStart(&b,cfg(),home(1),0)==CASearch);
    CAWorld w=opponent(2,10); w.gold=0; assert(CABattleTick(&b,w,1)==CASearch && b.searches==2);
    w.revision++; w.opponentID=11; w.gold=10; assert(CABattleTick(&b,w,2)==CADeployOne);
}
static void test_loot_counter_regression_fails_closed(void) {
    CABattle b; assert(CABattleStart(&b,cfg(),home(1),0)==CASearch);
    CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
    w.revision++; w.deployedUnits=1; w.remainingUnits=1; assert(CABattleTick(&b,w,2)==CADeployOne);
    w.revision++; w.deployedUnits=2; w.remainingUnits=0; assert(CABattleTick(&b,w,3)==CANoAction);
    w.revision++; w.scene=CAFighting; w.lootGoldEarned=10; assert(CABattleTick(&b,w,4)==CANoAction);
    w.revision++; w.lootGoldEarned=9; assert(CABattleTick(&b,w,5)==CANoAction && b.phase==CAError);
    assert(!CABattleRunning(&b) && b.reason && b.reason[0]);
}
static void test_confirmation_timeout_and_revision(void) {
    CABattle b; assert(CABattleStart(&b,cfg(),home(1),0)==CASearch);
    CAWorld w=home(1); assert(CABattleTick(&b,w,19)==CANoAction && b.phase==CAWaitSearch);
    assert(CABattleTick(&b,w,20)==CANoAction && b.phase==CAError);
    assert(CABattleStart(&b,cfg(),home(5),0)==CASearch);
    w=opponent(4,42); assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAError);
}

static void test_search_limit_is_bounded(void) {
    CABattle b; CABattleConfig c=cfg(); c.maxSearch=1;
    assert(CABattleStart(&b,c,home(1),0)==CASearch);
    CAWorld w=opponent(2,42); w.gold=0;
    assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CADone);
    assert(b.searches==1 && b.reason && b.reason[0]);
}
static void test_hard_timeout_and_natural_settlement(void) {
    CABattle b; assert(CABattleStart(&b,cfg(),home(1),0)==CASearch);
    CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
    w.revision++; w.deployedUnits=1; w.remainingUnits=1; assert(CABattleTick(&b,w,2)==CADeployOne);
    w.revision++; w.deployedUnits=2; w.remainingUnits=0; assert(CABattleTick(&b,w,3)==CANoAction);
    w.revision++; w.scene=CAFighting; w.lootGoldEarned=1; assert(CABattleTick(&b,w,4)==CANoAction);
    w.revision++; w.lootGoldEarned=2; assert(CABattleTick(&b,w,8)==CANoAction);
    w.revision++; w.lootGoldEarned=3; assert(CABattleTick(&b,w,12)==CANoAction);
    w.revision++; w.lootGoldEarned=4; assert(CABattleTick(&b,w,16)==CANoAction);
    w.revision++; w.lootGoldEarned=5; assert(CABattleTick(&b,w,20)==CANoAction);
    w.revision++; w.lootGoldEarned=6; assert(CABattleTick(&b,w,24)==CANoAction);
    w.revision++; w.lootGoldEarned=7; assert(CABattleTick(&b,w,28)==CANoAction);
    w.revision++; w.lootGoldEarned=8; assert(CABattleTick(&b,w,32)==CANoAction);
    w.revision++; w.lootGoldEarned=9; assert(CABattleTick(&b,w,36)==CANoAction);
    w.revision++; w.lootGoldEarned=10; assert(CABattleTick(&b,w,40)==CANoAction);
    w.revision++; w.lootGoldEarned=11; assert(CABattleTick(&b,w,44)==CANoAction);
    w.revision++; w.lootGoldEarned=12; assert(CABattleTick(&b,w,48)==CANoAction);
    w.revision++; w.lootGoldEarned=13; assert(CABattleTick(&b,w,52)==CANoAction);
    w.revision++; w.lootGoldEarned=14; assert(CABattleTick(&b,w,56)==CANoAction);
    w.revision++; w.lootGoldEarned=15; assert(CABattleTick(&b,w,60)==CANoAction);
    w.revision++; assert(CABattleTick(&b,w,61)==CAEndBattle && b.reason && b.phase==CAWaitEnd);
    w.revision++; w.scene=CASettlement; assert(CABattleTick(&b,w,62)==CAReturnHome);
}
static void test_invalid_config(void) {
    CABattle b; CABattleConfig c=cfg(); c.noLootGrowthTimeout=0;
    assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
    c=cfg(); c.maxBattles=0; assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
    c=cfg(); c.battleTimeout=INFINITY; assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
}
int main(void) {
    test_no_growth_and_loop(); test_filter_and_search_limit(); test_loot_counter_regression_fails_closed();
    test_confirmation_timeout_and_revision(); test_search_limit_is_bounded();
    test_hard_timeout_and_natural_settlement(); test_invalid_config();
    puts("PASS: 7 state-machine test groups (synthetic test inputs only; no game backend)");
    return 0;
}
