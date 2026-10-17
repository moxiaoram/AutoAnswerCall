#include "../AACPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void){
 /* Prior regression: Mode 1 MUST permit a fully observed connected incoming call. */
 assert(AACShouldPlayForSystemConnection(1,1,0,1,0,1,1,0,0,0));
 assert(!AACShouldRequest(1,1,0,0,0,0,0)); // answer request still Mode-2 only
 /* Mode 1 ignores exclusions because its UI explicitly means all incoming. */
 assert(AACShouldPlayForSystemConnection(1,1,0,1,0,1,1,1,1,1));
 /* Mode 2 uses exact exclusions, requires known caller when a list exists. */
 assert(AACShouldPlayForSystemConnection(1,2,0,1,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,2,0,1,0,1,1,1,0,0));
 assert(!AACShouldPlayForSystemConnection(1,2,0,1,0,1,1,0,1,0));
 assert(!AACShouldPlayForSystemConnection(1,2,0,1,0,1,1,0,0,1));
 /* All modes fail closed on unknown mode, plugin OFF, audio OFF, outgoing, ended,
    not connected, or unobserved ring (do not start playback on an ongoing call). */
 assert(!AACShouldPlayForSystemConnection(1,0,0,1,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,3,0,1,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(0,1,0,1,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,1,0,1,0,1,0,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,1,1,1,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,1,0,1,1,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,1,0,0,0,1,1,0,0,0));
 assert(!AACShouldPlayForSystemConnection(1,1,0,1,0,0,1,0,0,0));
 puts("PASS: 1.17.9 independent system-connection playback policy (Mode 1, Mode 2, exclusions, opt-in and call state)");
 return 0;
}
