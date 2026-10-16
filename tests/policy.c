#include "../AACPolicy.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void){char n[128];
 assert(AACNormalize("+86 (138) 0013-8000",n,sizeof n)&&!strcmp(n,"8613800138000"));
 assert(AACNormalize("13800138000",n,sizeof n)&&strcmp(n,"38000"));
 assert(!AACNormalize("138*",n,sizeof n));assert(!AACNormalize("138abc",n,sizeof n));assert(!AACNormalize("++123",n,sizeof n));assert(!AACNormalize("",n,sizeof n));assert(!AACNormalize("12345",n,3));
 assert(AACBoundDelay(-3)==0);assert(AACBoundDelay(99)==60);assert(AACBoundDelay(NAN)==0.5);
 assert(AACShouldRequest(1,2,0,0,0,0,0));
 /* Revalidation after delay: toggle disabled/mode changed/manual connected/ended/outgoing/exclusion/unknown. */
 assert(!AACShouldRequest(0,2,0,0,0,0,0));assert(!AACShouldRequest(1,1,0,0,0,0,0));assert(!AACShouldRequest(1,2,0,1,0,0,0));assert(!AACShouldRequest(1,2,0,0,1,0,0));assert(!AACShouldRequest(1,2,1,0,0,0,0));assert(!AACShouldRequest(1,2,0,0,0,1,0));assert(!AACShouldRequest(1,2,0,0,0,0,1));
 puts("PASS: normalization, exact-match boundaries, bounded delay, delayed policy transitions");return 0;
}
