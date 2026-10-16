#include "../AACPolicy.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void){char n[128];double seconds=-1;
 assert(AACParseDelay("0",&seconds)&&seconds==0);assert(AACParseDelay("60",&seconds)&&seconds==60);assert(AACParseDelay("1.5",&seconds)&&seconds==1.5);assert(AACParseDelay(".5",&seconds)&&seconds==0.5);assert(AACParseDelay("5.0",&seconds)&&seconds==5);
 const char *bad[]={"",".","-1","61","60.0001","NaN","nan","Infinity","inf","1e1","2秒","5s","1,5","1.2.3","+1"," 1","1 ","1\n","9999999999999999999999999999999999999999999999"};
 for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++){seconds=7;assert(!AACParseDelay(bad[i],&seconds));assert(seconds==7);}
 assert(AACBoundDelay(INFINITY)==0.5);assert(AACBoundDelay(-INFINITY)==0.5);
 assert(AACNormalize("+86 (138) 0013-8000",n,sizeof n)&&!strcmp(n,"8613800138000"));
 assert(AACNormalize("13800138000",n,sizeof n)&&strcmp(n,"38000"));
 assert(!AACNormalize("138*",n,sizeof n));assert(!AACNormalize("138abc",n,sizeof n));assert(!AACNormalize("++123",n,sizeof n));assert(!AACNormalize("",n,sizeof n));assert(!AACNormalize("12345",n,3));
 assert(AACBoundDelay(-3)==0);assert(AACBoundDelay(99)==60);assert(AACBoundDelay(NAN)==0.5);
 assert(AACShouldRequest(1,2,0,0,0,0,0));
 /* Revalidation after delay: toggle disabled/mode changed/manual connected/ended/outgoing/exclusion/unknown. */
 assert(!AACShouldRequest(0,2,0,0,0,0,0));assert(!AACShouldRequest(1,1,0,0,0,0,0));assert(!AACShouldRequest(1,2,0,1,0,0,0));assert(!AACShouldRequest(1,2,0,0,1,0,0));assert(!AACShouldRequest(1,2,1,0,0,0,0));assert(!AACShouldRequest(1,2,0,0,0,1,0));assert(!AACShouldRequest(1,2,0,0,0,0,1));
 puts("PASS: normalization, exact-match boundaries, bounded delay, delayed policy transitions");return 0;
}
