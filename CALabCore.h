#ifndef CA_LAB_CORE_H
#define CA_LAB_CORE_H
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
typedef enum { CALabIdle, CALabSearching, CALabDeploying, CALabFighting, CALabSettling, CALabStopped } CALabPhase;
typedef struct { uint32_t minGold,minElixir,minDark,maxSearch,maxBattles,timeout; bool loop; } CALabConfig;
typedef struct {
 CALabPhase phase; CALabConfig config;
 uint32_t searches,battles,units,elapsed,gold,elixir,dark;
 uint64_t earnedGold,earnedElixir,earnedDark;
 const char *reason;
} CALab;
static inline void CALabStop(CALab *s,const char *reason) { s->phase=CALabStopped; s->reason=reason; }
static inline void CALabStart(CALab *s,CALabConfig c) {
 memset(s,0,sizeof(*s)); s->config=c;
 if (!c.maxSearch || !c.maxBattles || !c.timeout || c.maxSearch>10000 || c.maxBattles>10000 || c.timeout>10000) {
  CALabStop(s,"invalid-config"); return;
 }
 s->phase=CALabSearching; s->reason="searching";
}
static inline uint32_t CALabLoot(uint32_t total,uint32_t tick) {
 return (uint32_t)(((uint64_t)total*tick)/12);
}
static inline void CALabTick(CALab *s) {
 switch(s->phase) {
 case CALabSearching:
  if(s->searches>=s->config.maxSearch) { CALabStop(s,"search-limit"); break; }
  ++s->searches;
  s->gold=100000+(s->searches*324791u)%1900001u;
  s->elixir=100000+(s->searches*469397u)%1900001u;
  s->dark=(s->searches*3911u)%20001u;
  if(s->gold>=s->config.minGold && s->elixir>=s->config.minElixir && s->dark>=s->config.minDark) {
   s->units=0; s->elapsed=0; s->phase=CALabDeploying; s->reason="matched";
  } else if(s->searches>=s->config.maxSearch) CALabStop(s,"search-limit");
  else s->reason="filtered";
  break;
 case CALabDeploying:
 case CALabFighting: {
  uint32_t previous=s->elapsed; ++s->elapsed;
  s->earnedGold+=CALabLoot(s->gold,s->elapsed)-CALabLoot(s->gold,previous);
  s->earnedElixir+=CALabLoot(s->elixir,s->elapsed)-CALabLoot(s->elixir,previous);
  s->earnedDark+=CALabLoot(s->dark,s->elapsed)-CALabLoot(s->dark,previous);
  if(s->units<8) ++s->units;
  s->reason=s->units<8?"deploying":"fighting";
  if(s->units==8) s->phase=CALabFighting;
  if(s->elapsed>=12 || s->elapsed>=s->config.timeout) {
   s->phase=CALabSettling; s->reason=s->elapsed>=12?"battle-complete":"battle-timeout";
  }
  break;
 }
 case CALabSettling:
  ++s->battles;
  if(s->battles>=s->config.maxBattles) CALabStop(s,"battle-limit");
  else if(!s->config.loop) CALabStop(s,"single-complete");
  else if(s->searches>=s->config.maxSearch) CALabStop(s,"search-limit");
  else { s->phase=CALabSearching; s->reason="searching"; }
  break;
 default: break;
 }
}
#endif
