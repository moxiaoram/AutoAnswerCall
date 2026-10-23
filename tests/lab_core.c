#include "CALabCore.h"
#include <assert.h>
#include <stdio.h>
static void finish(CALab *s) {
 for(unsigned i=0;i<100000 && s->phase!=CALabStopped;i++) CALabTick(s);
 assert(s->phase==CALabStopped);
}
int main(void) {
 CALab s; CALabConfig c={500000,500000,0,50,10,180,false};
 CALabStart(&s,c); CALabTick(&s); assert(s.phase==CALabSearching); assert(s.reason && !strcmp(s.reason,"filtered"));
 CALabTick(&s); assert(s.phase==CALabDeploying); assert(s.gold>=c.minGold && s.elixir>=c.minElixir);
 uint32_t gold=s.gold,elixir=s.elixir,dark=s.dark;
 finish(&s); assert(s.battles==1 && s.units==8 && s.elapsed==12);
 assert(s.earnedGold==gold && s.earnedElixir==elixir && s.earnedDark==dark);
 assert(!strcmp(s.reason,"single-complete")); puts("PASS: AND resource filter, deployment, exact synthetic loot, single run");
 c.loop=true; c.maxBattles=3; CALabStart(&s,c); finish(&s);
 assert(s.battles==3 && !strcmp(s.reason,"battle-limit")); puts("PASS: looping stops at global battle limit");
 c.minDark=20002; c.maxSearch=4; CALabStart(&s,c); finish(&s);
 assert(s.searches==4 && s.battles==0 && !strcmp(s.reason,"search-limit")); puts("PASS: impossible threshold stops at search limit");
 c=(CALabConfig){0,0,0,1,20,2,true}; CALabStart(&s,c); CALabTick(&s); gold=s.gold;
 CALabTick(&s); CALabTick(&s); assert(s.phase==CALabSettling && s.units==2 && s.elapsed==2);
 assert(!strcmp(s.reason,"battle-timeout") && s.earnedGold==CALabLoot(gold,2));
 finish(&s); assert(s.searches==1 && s.battles==1); puts("PASS: per-battle timeout covers deployment and total search cap covers loops");
 for(unsigned phase=CALabSearching; phase<=CALabSettling;phase++) {
  c=(CALabConfig){0,0,0,10,10,180,true}; CALabStart(&s,c);
  while(s.phase!=(CALabPhase)phase) CALabTick(&s);
  CALabStop(&s,"manual"); CALab copy=s;
  for(unsigned i=0;i<10;i++) CALabTick(&s);
  assert(memcmp(&copy,&s,sizeof(s))==0);
 }
 puts("PASS: stop in every active phase prevents all further progress");
 c.maxSearch=0; CALabStart(&s,c); assert(s.phase==CALabStopped && !strcmp(s.reason,"invalid-config"));
 c.maxSearch=1; c.timeout=10001; CALabStart(&s,c); assert(s.phase==CALabStopped);
 puts("PASS: invalid configuration refused"); return 0;
}
