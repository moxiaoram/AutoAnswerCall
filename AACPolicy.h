#ifndef AAC_POLICY_H
#define AAC_POLICY_H
#include <stddef.h>
#include <math.h>
#include <stdlib.h>
/* Decimal seconds editor: full parse, finite, 0..60. No signs/exponent/units. */
static inline int AACParseDelay(const char *text,double *result){
 if(!text||!*text||!result)return 0;int digits=0,dot=0;
 for(const char *p=text;*p;p++){if(*p>='0'&&*p<='9')digits++;else if(*p=='.'&&!dot)dot=1;else return 0;}
 if(!digits)return 0;char *end=NULL;double x=strtod(text,&end);if(!end||*end||!isfinite(x)||x<0||x>60)return 0;*result=x;return 1;
}
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
