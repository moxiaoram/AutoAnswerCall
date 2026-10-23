#ifndef CA_LAB_CORE_H
#define CA_LAB_CORE_H

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

typedef enum {
    CALabIdle,
    CALabSearching,
    CALabDeploying,
    CALabFighting,
    CALabSettling,
    CALabStopped
} CALabPhase;

typedef struct {
    uint32_t minGold, minElixir, minDark;
    uint32_t maxSearch, maxBattles, timeout;
    bool loop;
} CALabConfig;

typedef struct {
    CALabPhase phase;
    CALabConfig config;
    uint32_t searches, battles, units, elapsed;
    uint32_t gold, elixir, dark;
    uint32_t idleSeconds;
    uint64_t lastObservedGold, lastObservedElixir, lastObservedDark;
    uint64_t earnedGold, earnedElixir, earnedDark;
    bool hasResourceSnapshot;
    const char *reason;
} CALab;

static inline void CALabStop(CALab *s, const char *reason) {
    s->phase = CALabStopped;
    s->reason = reason;
}

static inline void CALabStart(CALab *s, CALabConfig c) {
    memset(s, 0, sizeof(*s));
    s->config = c;
    if (!c.maxSearch || !c.maxBattles || !c.timeout ||
        c.maxSearch > 10000 || c.maxBattles > 10000 || c.timeout > 10000) {
        CALabStop(s, "invalid-config");
        return;
    }
    s->phase = CALabSearching;
    s->reason = "searching";
}

static inline bool CALabResourcesMatch(const CALabConfig *c,
                                       uint32_t gold, uint32_t elixir, uint32_t dark) {
    return gold >= c->minGold && elixir >= c->minElixir && dark >= c->minDark;
}

static inline void CALabBeginBattle(CALab *s) {
    s->units = 0;
    s->elapsed = 0;
    s->idleSeconds = 0;
    s->hasResourceSnapshot = false;
    s->lastObservedGold = 0;
    s->lastObservedElixir = 0;
    s->lastObservedDark = 0;
    s->phase = CALabDeploying;
    s->reason = "matched";
}

/*
 * Event-driven entry point for a verified backend: call this once after a
 * search result is available. It evaluates real values supplied by the caller;
 * it does not itself search the game or read any game memory.
 */
static inline bool CALabOnSearchResult(CALab *s,
                                       uint32_t gold, uint32_t elixir, uint32_t dark) {
    if (s->phase != CALabSearching) return false;
    if (s->searches >= s->config.maxSearch) {
        CALabStop(s, "search-limit");
        return false;
    }
    ++s->searches;
    s->gold = gold;
    s->elixir = elixir;
    s->dark = dark;
    if (CALabResourcesMatch(&s->config, gold, elixir, dark)) {
        CALabBeginBattle(s);
        return true;
    }
    if (s->searches >= s->config.maxSearch) CALabStop(s, "search-limit");
    else s->reason = "filtered";
    return false;
}

/* Call after the backend confirms that one troop was actually deployed. */
static inline bool CALabOnUnitDeployed(CALab *s) {
    if (s->phase != CALabDeploying && s->phase != CALabFighting) return false;
    if (s->units < 8) ++s->units;
    if (s->units >= 8) {
        s->phase = CALabFighting;
        s->reason = "fighting";
    } else {
        s->phase = CALabDeploying;
        s->reason = "deploying";
    }
    return true;
}

static inline void CALabOnBattleEnded(CALab *s, const char *reason) {
    if (s->phase != CALabDeploying && s->phase != CALabFighting) return;
    s->phase = CALabSettling;
    s->reason = reason ? reason : "battle-complete";
}

/*
 * Feed one resource snapshot per second from a verified backend. A change in
 * any observed resource resets the no-growth timer. Once all eight units have
 * been deployed, five consecutive unchanged snapshots end the battle.
 */
static inline void CALabObserveResources(CALab *s,
                                         uint64_t gold, uint64_t elixir, uint64_t dark) {
    if (s->phase != CALabDeploying && s->phase != CALabFighting) return;
    if (!s->hasResourceSnapshot) {
        s->lastObservedGold = gold;
        s->lastObservedElixir = elixir;
        s->lastObservedDark = dark;
        s->hasResourceSnapshot = true;
        return;
    }
    if (gold != s->lastObservedGold || elixir != s->lastObservedElixir ||
        dark != s->lastObservedDark) {
        s->lastObservedGold = gold;
        s->lastObservedElixir = elixir;
        s->lastObservedDark = dark;
        s->idleSeconds = 0;
        return;
    }
    if (s->units >= 8 && s->idleSeconds < UINT32_MAX) ++s->idleSeconds;
    if (s->units >= 8 && s->idleSeconds >= 5) {
        CALabOnBattleEnded(s, "no-resource-growth");
    }
}

/* Call once per real battle-second with a fresh, verified resource snapshot. */
static inline void CALabOnBattleSecond(CALab *s,
                                       uint64_t gold, uint64_t elixir, uint64_t dark) {
    if (s->phase != CALabDeploying && s->phase != CALabFighting) return;
    if (s->elapsed < UINT32_MAX) ++s->elapsed;
    if (s->elapsed >= s->config.timeout) {
        CALabOnBattleEnded(s, "battle-timeout");
        return;
    }
    CALabObserveResources(s, gold, elixir, dark);
}

static inline void CALabCompleteSettlement(CALab *s) {
    if (s->phase != CALabSettling) return;
    ++s->battles;
    if (s->battles >= s->config.maxBattles) CALabStop(s, "battle-limit");
    else if (!s->config.loop) CALabStop(s, "single-complete");
    else if (s->searches >= s->config.maxSearch) CALabStop(s, "search-limit");
    else {
        s->phase = CALabSearching;
        s->reason = "searching";
    }
}

/* Local-only simulator. A real backend must use the event-driven functions above. */
static inline uint32_t CALabLoot(uint32_t total, uint32_t tick) {
    return (uint32_t)(((uint64_t)total * tick) / 12);
}

static inline void CALabTick(CALab *s) {
    switch (s->phase) {
        case CALabSearching: {
            if (s->searches >= s->config.maxSearch) {
                CALabStop(s, "search-limit");
                break;
            }
            uint32_t attempt = s->searches + 1;
            uint32_t gold = 100000 + (attempt * 324791u) % 1900001u;
            uint32_t elixir = 100000 + (attempt * 469397u) % 1900001u;
            uint32_t dark = (attempt * 3911u) % 20001u;
            (void)CALabOnSearchResult(s, gold, elixir, dark);
            break;
        }
        case CALabDeploying:
        case CALabFighting: {
            uint32_t previous = s->elapsed;
            ++s->elapsed;
            /* Demo-only loot growth for the first three simulated seconds. */
            if (s->elapsed <= 3) {
                s->earnedGold += CALabLoot(s->gold, s->elapsed) - CALabLoot(s->gold, previous);
                s->earnedElixir += CALabLoot(s->elixir, s->elapsed) - CALabLoot(s->elixir, previous);
                s->earnedDark += CALabLoot(s->dark, s->elapsed) - CALabLoot(s->dark, previous);
            }
            (void)CALabOnUnitDeployed(s);
            CALabObserveResources(s, s->earnedGold, s->earnedElixir, s->earnedDark);
            if (s->elapsed >= s->config.timeout) {
                CALabOnBattleEnded(s, "battle-timeout");
            }
            break;
        }
        case CALabSettling:
            CALabCompleteSettlement(s);
            break;
        default:
            break;
    }
}

#endif
