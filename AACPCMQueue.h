#ifndef AAC_PCM_QUEUE_H
#define AAC_PCM_QUEUE_H
/* Bounded, allocation-free S16 mono sample ring. The test harness can exercise
   the queue on Linux/macOS; no real-time audio callback is hooked by this code. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define AAC_PCM_QUEUE_CAPACITY 4096u
typedef struct {
 int16_t slots[AAC_PCM_QUEUE_CAPACITY];
 size_t head, tail, count;
} AACPCMQueue;
static inline void AACPCMQueueReset(AACPCMQueue *q){if(q)memset(q,0,sizeof(*q));}
static inline size_t AACPCMQueuePush(AACPCMQueue *q,const int16_t *src,size_t n){
 if(!q||!src)return 0;
 size_t written=0;
 while(written<n && q->count<AAC_PCM_QUEUE_CAPACITY){
  q->slots[q->tail]=src[written++];
  q->tail=(q->tail+1)%AAC_PCM_QUEUE_CAPACITY;
  q->count++;
 }
 return written;
}
static inline size_t AACPCMQueuePop(AACPCMQueue *q,int16_t *dst,size_t n){
 if(!q||!dst)return 0;
 size_t used=0;
 while(used<n && q->count){
  dst[used++]=q->slots[q->head];
  q->head=(q->head+1)%AAC_PCM_QUEUE_CAPACITY;
  q->count--;
 }
 return used;
}

typedef struct {uint64_t frames; double squareSum; uint32_t peak;} AACPCMStats;
static inline void AACPCMStatsAccumulate(AACPCMStats *s,const int16_t *pcm,size_t n){
 if(!s||!pcm)return;
 for(size_t i=0;i<n;i++){
  int32_t v=(int32_t)pcm[i];
  uint32_t absSample=(uint32_t)(v<0?-v:v); /* -32768 stays representable */
  if(absSample>s->peak)s->peak=absSample;
  double scaled=(double)v/32768.0;
  s->squareSum+=scaled*scaled;
 }
 s->frames+=(uint64_t)n;
}
static inline double AACPCMStatsRMS(const AACPCMStats *s){
 if(!s||!s->frames)return 0.0;
 double average=s->squareSum/(double)s->frames;
 /* Newton iterations avoid depending on libm in iOS callers. */
 double x=average>1.0?average:1.0;
 for(int i=0;i<32;i++)x=0.5*(x+average/x);
 return average>0.0?x:0.0;
}
#endif
