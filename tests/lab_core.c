#include "CALabCore.h"
#include <assert.h>
#include <stdio.h>
static void finish(CALab *s) {
 for(unsigned i=0;i<100000 && s->phase!=CALabStopped;i++) CALabTick(s);
 assert(s->phase==CALabStopped);
}
static void test_event_driven_api(void) {
 CALab s; CALabConfig c={500000,500000,0,10,1,180,false};
 CALabStart(&s,c);
 assert(!CALabOnSearchResult(&s,100000,100000,0));
 assert(s.searches==1 && s.phase==CALabSearching);
 assert(CALabOnSearchResult(&s,600000,700000,0));
 assert(s.searches==2 && s.phase==CALabDeploying);
 for(unsigned i=0;i<8;i++) assert(CALabOnUnitDeployed(&s));
 assert(s.phase==CALabFighting && s.units==8);
 CALabObserveResources(&s,100,200,300);
 for(unsigned i=0;i<4;i++) CALabObserveResources(&s,100,200,300);
 assert(s.phase==CALabFighting && s.idleSeconds==4);
 CALabObserveResources(&s,101,200,300);
 assert(s.phase==CALabFighting && s.idleSeconds==0);
 for(unsigned i=0;i<5;i++) CALabObserveResources(&s,101,200,300);
 assert(s.phase==CALabSettling && !strcmp(s.reason,"no-resource-growth"));
 CALabCompleteSettlement(&s);
 assert(s.phase==CALabStopped && s.battles==1 && !strcmp(s.reason,"battle-limit"));
 puts("PASS: event-driven search filter, deployment, resource monitor, and settlement transitions");

 c.timeout=2; c.maxBattles=2; c.loop=true; CALabStart(&s,c);
 assert(CALabOnSearchResult(&s,600000,700000,0));
 for(unsigned i=0;i<8;i++) assert(CALabOnUnitDeployed(&s));
 CALabOnBattleSecond(&s,100,200,300);
 assert(s.elapsed==1 && s.phase==CALabFighting);
 CALabOnBattleSecond(&s,100,200,300);
 assert(s.elapsed==2 && s.phase==CALabSettling && !strcmp(s.reason,"battle-timeout"));
 CALabCompleteSettlement(&s);
 assert(s.phase==CALabSearching && s.battles==1);
 puts("PASS: event-driven clock enforces timeout and resumes search after settlement");
}

static void test_resource_observer(void) {
 CALab s; CALabConfig c={0,0,0,10,10,180,false};
 CALabStart(&s,c); s.phase=CALabDeploying; s.units=3;
 CALabObserveResources(&s,100,200,10);
 for(unsigned i=0;i<8;i++) CALabObserveResources(&s,100,200,10);
 assert(s.idleSeconds==0 && s.phase==CALabDeploying);
 s.units=8; s.phase=CALabFighting;
 CALabObserveResources(&s,100,200,10); assert(s.idleSeconds==1);
 CALabObserveResources(&s,100,200,10); assert(s.idleSeconds==2);
 CALabObserveResources(&s,100,200,10); assert(s.idleSeconds==3);
 CALabObserveResources(&s,100,200,10); assert(s.idleSeconds==4 && s.phase==CALabFighting);
 CALabObserveResources(&s,101,200,10); assert(s.idleSeconds==0 && s.phase==CALabFighting);
 CALabObserveResources(&s,101,201,10); assert(s.idleSeconds==0 && s.phase==CALabFighting);
 CALabObserveResources(&s,101,201,10); assert(s.idleSeconds==1);
 CALabObserveResources(&s,101,201,10); assert(s.idleSeconds==2);
 CALabObserveResources(&s,101,201,10); assert(s.idleSeconds==3);
 CALabObserveResources(&s,101,201,10); assert(s.idleSeconds==4);
 CALabObserveResources(&s,101,201,10);
 assert(s.phase==CALabSettling && !strcmp(s.reason,"no-resource-growth"));
 puts("PASS: observed resource growth resets the five-second timer; no growth settles after five samples");

 CALabStart(&s,c); s.phase=CALabFighting; s.units=8;
 uint64_t large=UINT64_C(1)<<32;
 CALabObserveResources(&s,large,large+1,large+2);
 CALabObserveResources(&s,large+1,large+1,large+2);
 assert(s.idleSeconds==0 && s.lastObservedGold==large+1);
 puts("PASS: resource snapshots remain correct above 32-bit counters");
}
int main(void) {
 CALab s; CALabConfig c={500000,500000,0,50,10,180,false};
 CALabStart(&s,c); CALabTick(&s); assert(s.phase==CALabSearching); assert(s.reason && !strcmp(s.reason,"filtered"));
 CALabTick(&s); assert(s.phase==CALabDeploying); assert(s.gold>=c.minGold && s.elixir>=c.minElixir);
 uint32_t gold=s.gold,elixir=s.elixir,dark=s.dark;
 finish(&s); assert(s.battles==1 && s.units==8 && s.elapsed==12 && s.idleSeconds==5);
 assert(s.earnedGold==CALabLoot(gold,3) && s.earnedElixir==CALabLoot(elixir,3) && s.earnedDark==CALabLoot(dark,3));
 assert(!strcmp(s.reason,"single-complete")); puts("PASS: AND resource filter, deployment, five-second no-growth settlement");
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
 puts("PASS: invalid configuration refused");
 test_event_driven_api();
 test_resource_observer();
 return 0;
}
