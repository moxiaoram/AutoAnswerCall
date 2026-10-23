#include <assert.h>
#include <stdio.h>
#include <math.h>
#include "CABattleCore.h"
static CABattleConfig cfg(void) { return (CABattleConfig){.minGold=10,.minElixir=20,.minDark=1,.maxSearch=3,.maxUnits=2,.actionTimeout=20,.battleTimeout=60}; }
static CAWorld home(void) { return (CAWorld){.scene=CAHome,.revision=1}; }
static CAWorld opponent(void) { return (CAWorld){.scene=CAOpponent,.revision=2,.opponentID=42,.gold=10,.elixir=20,.dark=1,.remainingUnits=2}; }
static CABattle begin(void) { CABattle b; assert(CABattleStart(&b,cfg(),home(),0)==CASearch); return b; }
int main(void) {
    unsigned groups=0;
    {
        CABattle b=begin(); CAWorld w=opponent();
        assert(CABattleTick(&b,w,1)==CADeployOne);
        assert(b.deployed==0); /* accepted request is not success */
        w.revision++; assert(CABattleTick(&b,w,2)==CANoAction); /* fresh but no unit confirmation */
        w.revision++; w.scene=CAFighting; w.deployedUnits=1; w.remainingUnits=1;
        assert(CABattleTick(&b,w,3)==CADeployOne); assert(b.deployed==1);
        w.revision++; w.deployedUnits=2; w.remainingUnits=0;
        assert(CABattleTick(&b,w,4)==CANoAction && b.phase==CAWaitBattle);
        w.revision++; assert(CABattleTick(&b,w,61)==CAEndBattle);
        w.revision++; w.scene=CASettlement;
        assert(CABattleTick(&b,w,62)==CANoAction && b.phase==CADone);
        assert(CABattleTick(&b,w,63)==CANoAction); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=home();
        assert(CABattleTick(&b,w,19)==CANoAction && b.phase==CAWaitSearch);
        assert(CABattleTick(&b,w,20)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); w.gold=0;
        assert(CABattleTick(&b,w,1)==CASearch && b.searches==2);
        w.revision++; assert(CABattleTick(&b,w,2)==CANoAction && b.searches==2); /* old opponent */
        w.opponentID++; w.revision++; assert(CABattleTick(&b,w,3)==CASearch && b.searches==3);
        w.opponentID++; w.revision++; assert(CABattleTick(&b,w,4)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); w.opponentID=0;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAWaitSearch); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); w.remainingUnits=0;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.scene=CASettlement;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CADone); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.opponentID++;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.deployedUnits=3;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); w.deployedUnits=5;
        assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.deployedUnits=4;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision=1; assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAError); groups++;
    }
    for (CAScene scene=CAUnknown; scene<=CASettlement; ++scene) {
        if (scene==CASearching || scene==CAOpponent) continue;
        CABattle b=begin(); CAWorld w=opponent(); w.scene=scene;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); w.scene=CASearching;
        assert(CABattleTick(&b,w,1)==CANoAction && b.phase==CAWaitSearch);
        w.revision++; w.scene=CAOpponent;
        assert(CABattleTick(&b,w,2)==CADeployOne); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; assert(CABattleTick(&b,w,21)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b; CAWorld w=opponent();
        assert(CABattleStart(&b,cfg(),w,0)==CANoAction && b.phase==CAError);
        CABattleConfig c=cfg(); c.actionTimeout=NAN;
        assert(CABattleStart(&b,c,home(),0)==CANoAction && b.phase==CAError);
        c=cfg(); c.battleTimeout=INFINITY;
        assert(CABattleStart(&b,c,home(),0)==CANoAction && b.phase==CAError);
        c=cfg(); c.maxUnits=0;
        assert(CABattleStart(&b,c,home(),0)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CABattleFail(&b,"backend-action-rejected");
        assert(CABattleTick(&b,opponent(),1)==CANoAction); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.scene=CAFighting; w.deployedUnits=1; w.remainingUnits=0;
        assert(CABattleTick(&b,w,2)==CANoAction && b.phase==CAWaitBattle);
        /* No fresh observations at battle timeout => do not issue end with stale data. */
        assert(CABattleTick(&b,w,61)==CANoAction && b.phase==CAWaitBattle);
        assert(CABattleTick(&b,w,81)==CANoAction && b.phase==CAError); groups++;
    }
    {
        CABattle b=begin(); CAWorld w=opponent(); assert(CABattleTick(&b,w,1)==CADeployOne);
        w.revision++; w.scene=CAFighting; w.deployedUnits=1; w.remainingUnits=0;
        assert(CABattleTick(&b,w,2)==CANoAction);
        w.revision++; assert(CABattleTick(&b,w,61)==CAEndBattle);
        w.revision++; assert(CABattleTick(&b,w,62)==CANoAction && b.phase==CAWaitEnd);
        w.revision++; assert(CABattleTick(&b,w,81)==CANoAction && b.phase==CAError); groups++;
    }
    printf("PASS: %u battle controller groups (test inputs only; no game backend)\n",groups);
}
