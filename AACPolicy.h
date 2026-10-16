#ifndef AAC_POLICY_H
#define AAC_POLICY_H
#include <stddef.h>
#include <math.h>
/* Exact digits only; optional leading + and visual separators. No substring/wildcard matching. */
static inline int AACNormalize(const char *s, char *out, size_t cap) {
 size_t n=0; int seen=0; if(!s||!out||cap<2)return 0;
 for(;*s;s++){ unsigned char c=(unsigned char)*s;
  if(c>='0'&&c<='9'){if(n+1>=cap)return 0;out[n++]=c;seen=1;}
  else if(c=='+'&&!seen){seen=1;}
  else if(c==' '||c=='-'||c=='('||c==')'||c=='.'||c=='\t'||c=='\r'){}
  else return 0;
 } out[n]=0;return n>0;
}
static inline double AACBoundDelay(double x){return isfinite(x)?fmax(0,fmin(60,x)):0.5;}
static inline int AACShouldRequest(int enabled,int mode,int outgoing,int connected,int ended,int excluded,int unknownWithList){return enabled&&mode==2&&!outgoing&&!connected&&!ended&&!excluded&&!unknownWithList;}
#endif
