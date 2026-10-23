#include <assert.h>
#include <stdio.h>
#include <math.h>
#include "CABattleCore.h"
static CABattleConfig cfg(void) { return (CABattleConfig){.minGold=10,.minElixir=20,.minDark=1,.maxSearch=4,.maxUnits=3,.actionTimeout=20,.battleTimeout=60,.noLootGrowthTimeout=5}; }
static CAWorld makeWorld(CAScene scene, uint64_t revision) {
    CAWorld w={.scene=scene,.revision=revision,.observedAtMonotonic=1.0,.validFields=CAWorldRequiredFields(scene)};
    if (scene==CAOpponent) w.validFields |= CAWorldHasBattleLoot; /* optional at candidate stage */
    return w;
}
static CAWorld home(uint64_t rev) { return makeWorld(CAHome,rev); }
static CAWorld opponent(uint64_t rev, uint64_t id) {
    CAWorld w=makeWorld(CAOpponent,rev); w.opponentID=id; w.gold=10; w.elixir=20; w.dark=1; w.remainingUnits=3; w.deployedUnits=0; return w;
}
static CABattle begin(void) { CABattle b; assert(CABattleStart(&b,cfg(),home(1),0)==CASearch); return b; }
int main(void) {
    unsigned groups=0;
    {
        CABattle b=begin(); CAWorld w=opponent(2,42);
        assert(CABattleTick(&b,w,1)==CADeployOne); assert(b.deployed==0);
        w.revision=3; w.deployedUnits=1; w.remainingUnits=2;
        assert(CABattleTick(&b,w,2)==CADeployOne); assert(b.deployed==1); /* one confirmed, next one requested */
        w.revision=4; w.scene=CAFighting; w.validFields=CAWorldRequiredFields(CAFighting); w.deployedUnits=2; w.remainingUnits=1;
        assert(CABattleTick(&b,w,3)==CADeployOne); assert(b.deployed==2);
        w.revision=5; w.deployedUnits=3; w.remainingUnits=0;
        assert(CABattleTick(&b,w,4)==CANoAction && b.phase==CAWaitBattle);
        w.revision=6; w.lootGold=7;
        assert(CABattleTick(&b,w,5)==CANoAction); /* growth resets the 5-second clock */
        w.revision=7; assert(CABattleTick(&b,w,9.9)==CANoAction);
        w.revision=8; assert(CABattleTick(&b,w,10)==CAEndBattle && b.phase==CAWaitEnd);
        w.revision=9; assert(CABattleTick(&b,w,11)==CANoAction && b.phase==CAWaitEnd); /* no duplicate end request */
        w.revision=10; w.scene=CASettlement; w.validFields=CAWorldRequiredFields(CASettlement);
        assert(CABattleTick(&b,w,12)==CAReturnHome && b.phase==CAWaitHome);
        w=home(11); assert(CABattleTick(&b,w,13)==CASearch && b.searches==2); /* return-home confirmed then next round */
        w=opponent(12,43); assert(CABattleTick(&b,w,14)==CADeployOne); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=home(2);
        assert(CABattleTick(&b,w,19)==CANoAction && b.phase==CAWaitSearch);
        assert(CABattleTick(&b,w,20)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); w.gold=0;
        assert(CABattleTick(&b,w,1)==CASearch && b.searches==2);
        w.revision=3; assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAWaitSearch); /* same opponent */
        w=opponent(4,43); w.gold=0; assert(CABattleTick(&b,w,3)==CASearch && b.searches==3);
        w=opponent(5,44); w.gold=0; assert(CABattleTick(&b,w,4)==CASearch && b.searches==4);
        w=opponent(6,45); assert(CABattleTick(&b,w,5)==CADeployOne && b.phase==CAWaitDeploy); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,0);
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAWaitSearch); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); w.remainingUnits=0;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=3; w.deployedUnits=1; /* remaining count did not decrease exactly one */
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=3; w.deployedUnits=2; w.remainingUnits=1;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); /* count jumped by two */ groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=3; w.deployedUnits=1; w.remainingUnits=2; assert(CABattleTick(&b,w,2)==CADeployOne);
        w.revision=4; w.scene=CAFighting; w.validFields=CAWorldRequiredFields(CAFighting); w.deployedUnits=2; w.remainingUnits=1;
        assert(CABattleTick(&b,w,3)==CADeployOne);
        w.revision=5; w.deployedUnits=3; w.remainingUnits=0; assert(CABattleTick(&b,w,4)==CANoAction);
        w.revision=6; w.lootGold=10; assert(CABattleTick(&b,w,5)==CANoAction);
        w.revision=7; w.lootGold=8; assert(CABattleTick(&b,w,6)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); w.validFields &= ~CAWorldHasOpponentResources;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b; CAWorld w=opponent(2,42);
        assert(CABattleStart(&b,cfg(),w,0)==CANoAction && b.phase==CAError);
        CABattleConfig c=cfg(); c.noLootGrowthTimeout=0;
        assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
        c=cfg(); c.noLootGrowthTimeout=6.0;
        assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
        c=cfg(); c.actionTimeout=NAN; assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError);
        c=cfg(); c.battleTimeout=INFINITY; assert(CABattleStart(&b,c,home(1),0)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CABattleFail(&b,"backend-action-rejected");
        assert(CABattleTick(&b,opponent(2,42),1)==CANoAction); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=3; w.deployedUnits=1; w.remainingUnits=2; assert(CABattleTick(&b,w,2)==CADeployOne);
        w.revision=4; w.scene=CAFighting; w.validFields=CAWorldRequiredFields(CAFighting); w.deployedUnits=2; w.remainingUnits=1;
        assert(CABattleTick(&b,w,3)==CADeployOne);
        w.revision=5; w.deployedUnits=3; w.remainingUnits=0; assert(CABattleTick(&b,w,4)==CANoAction);
        w.revision=6; assert(CABattleTick(&b,w,64)==CAEndBattle); /* hard battle timeout */ groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(2,42); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=3; w.validFields &= ~CAWorldHasTroops;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    printf("PASS: %u battle controller groups (synthetic test fixtures only; no game backend)\n",groups);
}
