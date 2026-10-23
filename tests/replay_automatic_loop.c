#include <assert.h>
#include <stdio.h>
#include "../CAReplaySimulation.h"

static const char *action_name(CAAction a) {
    switch (a) {
        case CASearch: return "search";
        case CADeployOne: return "deployOne";
        case CAEndBattle: return "endBattle";
        case CAReturnHome: return "returnHome";
        default: return "none";
    }
}
int main(void) {
    CAReplayResult r = CARunOfflineReplay();
    printf("mode=offline-synthetic-world-replay\n");
    printf("realGameBackendUsed=false\ngameActionsSent=false\n");
    for (uint32_t i=0; i<r.eventCount; ++i) {
        const CAReplayEvent *e=&r.events[i];
        printf("%02u t=%.3f rev=%llu scene=%u action=%s phase=%u %s label=%s\n",
            i+1, e->now, (unsigned long long)e->revision, (unsigned)e->scene,
            action_name(e->action), (unsigned)e->phaseAfter, e->passed?"PASS":"FAIL", e->label);
        assert(e->passed);
    }
    assert(r.passed);
    assert(r.eventCount==9);
    assert(r.searches==2);
    assert(r.completedBattles==1);
    assert(r.confirmedDeployed==1);
    assert(r.finalPhase==CAWaitDeploy);
    puts("PASS: full offline automatic loop; no game backend connected and no game actions sent");
    return 0;
}
