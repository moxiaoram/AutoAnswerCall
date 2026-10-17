#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../AACPCMQueue.h"
int main(void){
 AACPCMQueue q={0};AACPCMQueueReset(&q);
 int16_t a[]={-32768,0,10000,-10000,32767};
 assert(AACPCMQueuePush(&q,a,5)==5 && q.count==5);
 int16_t b[5]={0};
 assert(AACPCMQueuePop(&q,b,5)==5 && q.count==0);
 for(size_t i=0;i<5;i++)assert(a[i]==b[i]);
 AACPCMStats stats={0};AACPCMStatsAccumulate(&stats,b,5);
 assert(stats.frames==5 && stats.peak==32768);
 assert(AACPCMStatsRMS(&stats)>0.60 && AACPCMStatsRMS(&stats)<0.70);
 /* Wraparound, overflow, underrun and reset. */
 int16_t data[5000];for(int i=0;i<5000;i++)data[i]=(int16_t)(i%20000);
 assert(AACPCMQueuePush(&q,data,5000)==AAC_PCM_QUEUE_CAPACITY);
 assert(AACPCMQueuePush(&q,data,1)==0);
 int16_t out[5000];assert(AACPCMQueuePop(&q,out,3000)==3000);
 assert(AACPCMQueuePush(&q,data,3000)==3000);
 assert(AACPCMQueuePop(&q,out,5000)==AAC_PCM_QUEUE_CAPACITY);
 assert(AACPCMQueuePop(&q,out,1)==0);
 AACPCMQueueReset(&q);assert(q.count==0 && q.head==0 && q.tail==0);
 puts("PASS: PCM bounded queue, wraparound, overflow/underflow, signed peak, rms");
 return 0;
}
