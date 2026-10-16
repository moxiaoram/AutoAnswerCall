#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "AACSharedLog.h"
/* SpringBoard runtime inventory (1.10.0, EVIDENCE ONLY).
   No hooks and no behaviour change: this enumerates the real runtime classes and their
   candidate answer-related selectors so the next version can hook something that has
   actually been observed to exist on iOS 17.3. Everything is bounded and any failure
   degrades to a log line. */
static NSUInteger const AACInventoryMaxClasses=400;
static NSUInteger const AACInventoryMaxSelectors=40;
static NSUInteger const AACSharedInventoryCapBytes=200000;

static inline NSArray *AACInventoryClassKeywords(void){
 return @[@"IncomingCall",@"CallAlert",@"CallToAction",@"CallController",@"InCallService",@"AnswerCall",@"CallPresentation"];
}
static inline NSArray *AACInventorySelectorKeywords(void){return @[@"answer",@"accept",@"pick",@"dial",@"connect"];}

static inline BOOL AACInventoryMatchClass(NSString *name){
 for(NSString *keyword in AACInventoryClassKeywords())if([name rangeOfString:keyword].location!=NSNotFound)return YES;
 /* Lockscreen call-related names: SBLockScreen* combined with call/answer. */
 if([name hasPrefix:@"SBLockScreen"]){
  NSString *lower=name.lowercaseString;
  if([lower rangeOfString:@"call"].location!=NSNotFound||[lower rangeOfString:@"answer"].location!=NSNotFound)return YES;
 }
 return NO;
}
static inline NSString *AACInventorySafe(NSString *s,NSUInteger cap){
 if(![s isKindOfClass:NSString.class])return @"";
 NSString *clean=[s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
 return clean.length>cap?[clean substringToIndex:cap]:clean;
}
static inline NSString *AACInventoryScan(NSString *process){
 NSMutableString *out=[NSMutableString string];
 [out appendFormat:@"# AutoAnswerCall runtime inventory (evidence only; no hooks installed)\n# process=%@ pid=%d date=%@\n# filters: classes containing %@ or SBLockScreen + call/answer\n# selector filter: %@\n",process,getpid(),NSDate.date,[AACInventoryClassKeywords() componentsJoinedByString:@", "],[AACInventorySelectorKeywords() componentsJoinedByString:@"/"]];
 int total=objc_getClassList(NULL,0);
 if(total<=0){[out appendFormat:@"# objc_getClassList returned %d; no runtime classes enumerated\n",total];return out;}
 size_t capacity=(size_t)total+64;
 Class *classes=(Class *)calloc(capacity,sizeof(Class));
 if(!classes){[out appendString:@"# class buffer allocation failed\n"];return out;}
 int count=objc_getClassList(classes,(int)capacity);
 if(count<=0)count=0;
 NSUInteger matched=0,listed=0;BOOL truncated=NO;
 for(int i=0;i<count;i++){
  if(matched>=AACInventoryMaxClasses){truncated=YES;break;}
  const char *raw=class_getName(classes[i]);
  if(!raw)continue;
  NSString *name=[NSString stringWithUTF8String:raw];
  if(!name.length)continue;
  if(!AACInventoryMatchClass(name))continue;
  matched++;
  unsigned int methodCount=0;Method *methods=class_copyMethodList(classes[i],&methodCount);
  NSMutableArray *candidates=[NSMutableArray new];
  if(methods){
   for(unsigned int j=0;j<methodCount&&candidates.count<AACInventoryMaxSelectors;j++){
    const char *raw=sel_getName(method_getName(methods[j]));
    if(!raw)continue;
    NSString *selector=[NSString stringWithUTF8String:raw];
    NSString *lower=selector.lowercaseString;BOOL hit=NO;
    for(NSString *keyword in AACInventorySelectorKeywords())if([lower rangeOfString:keyword].location!=NSNotFound){hit=YES;break;}
    if(hit)[candidates addObject:AACInventorySafe(selector,180)];
   }
   free(methods);
  }
  [out appendFormat:@"CLASS %@ methods=%u answerLike=%lu\n",name,methodCount,(unsigned long)candidates.count];
  for(NSString *selector in candidates)[out appendFormat:@"  %@\n",selector];
  if(candidates.count>=AACInventoryMaxSelectors)[out appendString:@"  <selector list truncated at 40>\n"];
  listed++;
  if(out.length>AACSharedInventoryCapBytes){truncated=YES;[out appendString:@"# byte cap reached; inventory truncated safely\n"];break;}
 }
 free(classes);
 [out appendFormat:@"# end inventory scanned=%d matchedClasses=%lu listed=%lu truncated=%d\n",count,(unsigned long)matched,(unsigned long)listed,truncated];
 return out;
}
/* Writes the full inventory to a bounded file in the resolved shared directory and
   appends a bounded digest to the shared log channel. No behaviour change. */
static inline void AACRunInventory(NSString *process){
 @try{
  NSString *text=AACInventoryScan(process);
  NSError *error=nil;
  BOOL written=AACSharedWriteNamed(process,@"txt",text,&error);
  NSDictionary *chosen=AACSharedResolve(process,NO);
  NSString *path=chosen?[chosen[@"dir"] stringByAppendingPathComponent:AACSharedFileLeaf(process,@"txt")]:nil;
  AACSharedAppend(process,[NSString stringWithFormat:@"inventory: %lu characters, fileWritten=%d path=%@ error=%@",(unsigned long)text.length,written,path?:@"<no writable path>",written?@"none":(error.localizedDescription?:@"unknown")]);
  NSString *digest=text.length>6000?[text substringToIndex:6000]:text;
  AACSharedAppend(process,[@"inventory digest (first 6000 characters; full file path above):\n" stringByAppendingString:digest]);
 }@catch(NSException *e){AACSharedAppend(process,[@"inventory exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
