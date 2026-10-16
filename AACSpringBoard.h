#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AACSharedLog.h"
/* SpringBoard answer path (1.11.0): runtime discovery + dynamic hook + capture.
   Device evidence from the 1.10.0 probe build: the SpringBoard module loads on this
   iOS 17.3 RootHide device while the phone app process never announced itself, so
   SpringBoard is the only host that is known to be present. Nothing in this header
   hardcodes a private class name: the module enumerates the real objc runtime with
   objc_getClassList + class_copyMethodList, and for every candidate class it hooks
   ONLY the answer-ish selectors whose ABI it can prove (self+_cmd, zero explicit
   arguments, void return) so that a fixed-signature interposer is safe. The hook
   saves the original IMP per (class, method), records the receiving object, and then
   calls the original through. If nothing is discovered, or no ABI-provable method
   exists, or no live object can be located, the module degrades to LOG-ONLY and says
   so explicitly: it never reports an answer that was not performed, and never claims
   connected without an observed CXCall.hasConnected. */

enum { AACSBHookCap=24, AACSBClassCap=400, AACSBSelectorCap=12, AACSBScanNodeCap=4000, AACSBScanDepthCap=30, AACSBResponderUpCap=12 };
static NSTimeInterval const AACSBStrongHoldSeconds=180.0;
static NSUInteger const AACSBMaxDiscoverRuns=3;

@interface AACSBEnv : NSObject
@property(nonatomic,copy) NSString *process;
@property(nonatomic,copy) NSDictionary *(^prefs)(void);
@property(nonatomic,copy) BOOL (^allowed)(CXCall *call);
@property(nonatomic,copy) void (^log)(NSString *message);
@property(nonatomic,copy) void (^record)(NSString *status,NSDictionary *flags);
@end

typedef struct { Class cls; SEL sel; IMP original; } AACSBHookRecord;
static AACSBEnv *AACSBEnvShared=nil;
static AACSBHookRecord AACSBHookRecords[AACSBHookCap];
static NSUInteger AACSBHookCount=0;
static NSMutableSet *AACSBHookedKeys=nil;
static NSMutableSet *AACSBHookedIMPs=nil;
static NSMutableArray *AACSBDiscoveryLines=nil;
static NSMutableArray *AACSBHookedSelectors=nil;
static NSUInteger AACSBMatchedClasses=0,AACSBRejectedMethods=0,AACSBDiscoverRuns=0;
static __weak id AACSBWeakTarget=nil;
static id AACSBStrongTarget=nil;
static SEL AACSBInvokeSelector=NULL;
static volatile int32_t AACSBDepth=0;
static volatile int32_t AACSBInvoking=0;

static NSString *AACSBProcess(void){return AACSBEnvShared.process.length?AACSBEnvShared.process:@"springboard";}
static void AACSBLog(NSString *message){
 if(![message isKindOfClass:NSString.class])return;
 if(AACSBEnvShared.log){AACSBEnvShared.log(message);return;}
 AACSharedAppend(AACSBProcess(),message);
}
static void AACSBRecord(NSString *status,NSDictionary *flags){
 if(AACSBEnvShared.record)AACSBEnvShared.record(status,flags);
}
static NSArray *AACSBClassKeywords(void){return @[@"IncomingCall",@"CallAlert",@"CallToAction",@"CallPresentation",@"InCall",@"SBInCall",@"LockScreenCall",@"AnswerCall",@"CallController",@"CallUI"];}
static NSArray *AACSBSelectorKeywords(void){return @[@"answer",@"accept",@"pickup",@"pick up"];}
static BOOL AACSBClassMatches(NSString *name){
 if(!name.length||[name hasPrefix:@"AAC"])return NO;
 for(NSString *keyword in AACSBClassKeywords())if([name rangeOfString:keyword].location!=NSNotFound)return YES;
 if([name hasPrefix:@"SBLockScreen"]){NSString *lower=name.lowercaseString;if([lower rangeOfString:@"call"].location!=NSNotFound||[lower rangeOfString:@"answer"].location!=NSNotFound)return YES;}
 return NO;
}
static BOOL AACSBSelectorMatches(NSString *selector){
 NSString *lower=selector.lowercaseString;
 for(NSString *keyword in AACSBSelectorKeywords())if([lower rangeOfString:keyword].location!=NSNotFound)return YES;
 return NO;
}
/* Original IMP lookup walks the real class chain and is keyed by (class, selector), so
   two classes that share one selector never share an original by accident. */
static IMP AACSBOriginalFor(id object,SEL selector){
 if(!object||!selector)return NULL;
 Class cls=object_getClass(object);
 @try{
  while(cls){
   for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].cls==cls&&AACSBHookRecords[i].sel==selector)return AACSBHookRecords[i].original;
   cls=class_getSuperclass(cls);
  }
 }@catch(NSException *e){AACSBLog([@"original IMP lookup exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return NULL;
}
static void AACSBCapture(id object,SEL selector){
 if(!object)return;
 AACSBWeakTarget=object;
 AACSBStrongTarget=object;
 AACSBInvokeSelector=selector;
 Class cls=object_getClass(object);
 NSString *description=[NSString stringWithFormat:@"- [%@ %@]",NSStringFromClass(cls),NSStringFromSelector(selector)];
 dispatch_async(dispatch_get_main_queue(),^{
  AACSBLog([NSString stringWithFormat:@"captured live incoming-call UI object via dynamic hook: %@ (强引用仅在本通话窗口内保留，另有弱引用与重扫兜底)",description]);
 });
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACSBStrongHoldSeconds*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  if(AACSBStrongTarget==object){AACSBStrongTarget=nil;AACSBLog(@"bounded strong hold on the captured object expired; weak reference and hierarchy re-scan remain");}
 });
}
/* Fixed-signature interposer. Because discovery only hooks selectors with exactly
   (self, _cmd) and a void return type, this signature is ABI-correct, and calling the
   saved original through is behaviour-neutral. AACSBDepth/AACSBInvoking are the
   recursion guards: while our own invocation runs, the hook re-enters as a pure
   pass-through and never re-runs the policy. */
static void AACSBAnswerHook(id self,SEL _cmd){
 int32_t depth=__sync_add_and_fetch(&AACSBDepth,1);
 @try{
  if(depth==1&&!AACSBInvoking&&self){
   AACSBCapture(self,_cmd);
   Class cls=object_getClass(self);
   NSString *line=[NSString stringWithFormat:@"answer-ish method invoked through our dynamic hook: -[%@ %@] (recursion guard depth=1, invoking=0)",NSStringFromClass(cls),NSStringFromSelector(_cmd)];
   dispatch_async(dispatch_get_main_queue(),^{
    AACSBLog(line);
    AACSBRecord([NSString stringWithFormat:@"动态挂钩命中：−[%@ %@] 被调用，已记录接收对象",NSStringFromClass(cls),NSStringFromSelector(_cmd)],@{@"discovered":@YES});
   });
  }else if(depth>1||AACSBInvoking){
   /* Recursion guard: our own invocation or a nested call must not re-enter policy. */
  }
 }@catch(NSException *e){AACSBLog([@"hook capture exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 IMP original=AACSBOriginalFor(self,_cmd);
 if(original)((void(*)(id,SEL))original)(self,_cmd);
 else AACSBLog([NSString stringWithFormat:@"hooked selector %@ has no saved original IMP; passing nothing through",NSStringFromSelector(_cmd)]);
 __sync_sub_and_fetch(&AACSBDepth,1);
}
/* Bounded hierarchy walk: window tree, view controllers and responder chains. This is
   the fallback used when the weak/strong capture is gone by answer time. */
static void AACSBScanResponder(id object,id *found){
 if(!object||*found)return;
 @try{
  id next=object;
  for(NSUInteger up=0;up<AACSBResponderUpCap&&next&&!*found;up++){
   for(NSUInteger i=0;i<AACSBHookCount;i++){Class cls=AACSBHookRecords[i].cls;if(cls&&[next isKindOfClass:cls]){*found=next;return;}}
   next=[next isKindOfClass:UIResponder.class]?[(UIResponder *)next nextResponder]:nil;
  }
 }@catch(NSException *e){}
}
static void AACSBScanViewController(UIViewController *controller,NSUInteger depth,NSUInteger *visited,id *found){
 if(!controller||*found||depth>AACSBScanDepthCap||*visited>=AACSBScanNodeCap)return;
 *visited+=1;
 AACSBScanResponder(controller,found);
 if(*found)return;
 if(controller.presentedViewController)AACSBScanViewController(controller.presentedViewController,depth+1,visited,found);
 for(UIViewController *child in controller.childViewControllers)AACSBScanViewController(child,depth+1,visited,found);
}
static void AACSBScanView(UIView *view,NSUInteger depth,NSUInteger *visited,id *found){
 if(!view||*found||depth>AACSBScanDepthCap||*visited>=AACSBScanNodeCap)return;
 *visited+=1;
 AACSBScanResponder(view,found);
 if(*found)return;
 if(view.nextResponder&&[view.nextResponder isKindOfClass:UIViewController.class])AACSBScanViewController((UIViewController *)view.nextResponder,0,visited,found);
 if(*found||*visited>=AACSBScanNodeCap)return;
 for(UIView *subview in view.subviews)AACSBScanView(subview,depth+1,visited,found);
}
static id AACSBRescan(void){
 id found=nil;
 @try{
  NSUInteger visited=0;
  NSMutableArray *windows=[NSMutableArray new];
  UIApplication *application=UIApplication.sharedApplication;
  /* Scene API only: UIApplication.windows is deprecated since iOS 15 and this project
     builds with -Werror, so no deprecated accessor is used anywhere. */
  for(UIScene *scene in application.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])[windows addObjectsFromArray:((UIWindowScene *)scene).windows];
  for(UIWindow *window in windows){
   AACSBScanResponder(window,&found);
   if(!found&&window.rootViewController)AACSBScanViewController(window.rootViewController,0,&visited,&found);
   if(!found)AACSBScanView(window,0,&visited,&found);
   if(found)break;
  }
  AACSBLog([NSString stringWithFormat:@"hierarchy re-scan for the incoming-call UI object: windows=%lu visited=%lu found=%d",(unsigned long)windows.count,(unsigned long)visited,found!=nil]);
 }@catch(NSException *e){AACSBLog([@"hierarchy re-scan exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return found;
}
static id AACSBAnswerTarget(NSString **source){
 id target=AACSBWeakTarget;
 if(target){if(source)*source=@"弱引用捕获对象";return target;}
 target=AACSBStrongTarget;
 if(target){if(source)*source=@"本通话窗口内的强引用捕获对象";return target;}
 target=AACSBRescan();
 if(source)*source=target?@"窗口/视图控制器层级重扫":@"未找到：没有已捕获对象，重扫也没有发现已挂钩类的实例";
 return target;
}
static BOOL AACSBInvokeDiscovered(id target,NSString **reason){
 if(!target){if(reason)*reason=@"没有已捕获或可重新定位的来电 UI 对象";return NO;}
 IMP original=AACSBOriginalFor(target,AACSBInvokeSelector);
 if(!original){
  Class cls=object_getClass(target);
  while(cls&&!original){
   for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].cls==cls){original=AACSBHookRecords[i].original;AACSBInvokeSelector=AACSBHookRecords[i].sel;break;}
   if(!original)cls=class_getSuperclass(cls);
  }
 }
 if(!original){if(reason)*reason=@"目标对象的类链上没有已挂钩的原始 IMP（发现结果不含该类）";return NO;}
 __sync_add_and_fetch(&AACSBInvoking,1);
 @try{ ((void(*)(id,SEL))original)(target,AACSBInvokeSelector); }
 @catch(NSException *e){ __sync_sub_and_fetch(&AACSBInvoking,1); if(reason)*reason=[@"原始实现抛出异常：" stringByAppendingString:e.reason?:@"unknown"]; return NO; }
 __sync_sub_and_fetch(&AACSBInvoking,1);
 if(reason)*reason=[NSString stringWithFormat:@"已直接调用发现到的原始 IMP -[%@ %@]（递归守卫生效；调用本身不等于已接通）",NSStringFromClass(object_getClass(target)),NSStringFromSelector(AACSBInvokeSelector)];
 return YES;
}
static NSString *AACSBHookedSummary(void){
 if(!AACSBHookedSelectors.count)return @"未发现可挂钩的来电接听方法（运行时枚举结果为空或被安全跳过）";
 NSArray *list=AACSBHookedSelectors.count>12?[AACSBHookedSelectors subarrayWithRange:NSMakeRange(0,12)]:AACSBHookedSelectors;
 NSString *text=[list componentsJoinedByString:@"、"];
 return AACSBHookedSelectors.count>12?[text stringByAppendingFormat:@" 等 %lu 个",(unsigned long)AACSBHookedSelectors.count]:text;
}
static void AACSBWriteDiscoveryFile(void){
 NSString *text=AACSBDiscoveryLines.count?[AACSBDiscoveryLines componentsJoinedByString:@"\n"]:@"# 运行时发现未运行";
 NSError *error=nil;
 BOOL written=AACSharedWriteNamed(AACSBProcess(),@"discovery.txt",text,&error);
 NSDictionary *chosen=AACSharedResolve(AACSBProcess(),NO);
 NSString *path=chosen?[chosen[@"dir"] stringByAppendingPathComponent:AACSharedFileLeaf(AACSBProcess(),@"discovery.txt")]:nil;
 AACSBLog([NSString stringWithFormat:@"runtime-discovered answer path: matchedClasses=%lu hookedMethods=%lu rejected=%lu fileWritten=%d path=%@ error=%@",(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBHookCount,(unsigned long)AACSBRejectedMethods,written,path?:@"<没有可写候选路径>",written?@"none":(error.localizedDescription?:@"unknown")]);
 if(AACSBHookCount)AACSBLog([@"已挂钩方法：" stringByAppendingString:AACSBHookedSummary()]);
 else AACSBLog(@"没有挂钩任何方法：接听路径在本版本退化为仅日志；下一步设备测试请查看发现摘要判断真实类名");
 NSString *digest=text.length>4000?[text substringToIndex:4000]:text;
 AACSBLog([@"discovery digest (summary only; full file path above):\n" stringByAppendingString:digest]);
 AACSBRecord(AACSBHookCount?[NSString stringWithFormat:@"运行时发现（非硬编码，objc_getClassList 枚举）：候选类=%lu，已挂钩方法=%lu（%@），安全跳过=%lu",(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBHookCount,AACSBHookedSummary(),(unsigned long)AACSBRejectedMethods]:[NSString stringWithFormat:@"运行时发现：候选类=%lu，但没有可安全挂钩的接听方法（跳过 %lu）；接听路径退化为仅日志",(unsigned long)AACSBMatchedClasses,(unsigned long)AACSBRejectedMethods],@{@"discovered":@(AACSBHookCount>0)});
}
static void AACSBDiscover(void){
 if(AACSBDiscoverRuns>=AACSBMaxDiscoverRuns)return;
 AACSBDiscoverRuns++;
 if(!AACSBHookedKeys){AACSBHookedKeys=[NSMutableSet new];}
 if(!AACSBHookedIMPs){AACSBHookedIMPs=[NSMutableSet new];}
 if(!AACSBDiscoveryLines){AACSBDiscoveryLines=[NSMutableArray new];}
 if(!AACSBHookedSelectors){AACSBHookedSelectors=[NSMutableArray new];}
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# AutoAnswerCall 1.11.0 SpringBoard runtime discovery run %lu (runtime-discovered; no hardcoded class name)",(unsigned long)AACSBDiscoverRuns]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# process=%@ date=%@",AACSBProcess(),NSDate.date]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# classFilters=%@",[AACSBClassKeywords() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# selectorFilters=%@",[AACSBSelectorKeywords() componentsJoinedByString:@","]]];
 [AACSBDiscoveryLines addObject:@"# 只挂钩 ABI 可证安全的方法：参数数=2（self+_cmd）且返回类型=void；其余候选仅记录并跳过。"];
 int total=objc_getClassList(NULL,0);
 if(total<=0){
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# objc_getClassList 返回 %d，没有枚举到任何运行时类",total]];
  AACSBWriteDiscoveryFile();
  return;
 }
 size_t capacity=(size_t)total+64;
 Class *classes=(Class *)calloc(capacity,sizeof(Class));
 if(!classes){
  [AACSBDiscoveryLines addObject:@"# 类缓冲分配失败，本次发现放弃（接听路径保持仅日志）"];
  AACSBWriteDiscoveryFile();
  return;
 }
 int count=objc_getClassList(classes,(int)capacity);
 if(count<=0)count=0;
 NSUInteger matched=0;
 for(int i=0;i<count;i++){
  if(matched>=AACSBClassCap){[AACSBDiscoveryLines addObject:@"# 候选类达到 400 上限，提前结束枚举"];break;}
  const char *raw=class_getName(classes[i]);
  if(!raw)continue;
  NSString *name=[NSString stringWithUTF8String:raw];
  if(!AACSBClassMatches(name))continue;
  matched++;
  unsigned int methodCount=0;
  Method *methods=class_copyMethodList(classes[i],&methodCount);
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"CLASS %@ methods=%u",name,methodCount]];
  NSUInteger picked=0;
  if(methods){
   for(unsigned int j=0;j<methodCount&&picked<AACSBSelectorCap;j++){
    SEL selector=method_getName(methods[j]);
    const char *rawSelector=selector?sel_getName(selector):NULL;
    if(!rawSelector)continue;
    NSString *selectorName=[NSString stringWithUTF8String:rawSelector];
    if(!AACSBSelectorMatches(selectorName))continue;
    unsigned int arguments=method_getNumberOfArguments(methods[j]);
    if(arguments!=2){AACSBRejectedMethods++;[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  SKIP %@ reason=参数数量=%u（非零参，固定签名不安全）",selectorName,arguments]];continue;}
    char returnType[32]={0};
    method_getReturnType(methods[j],returnType,sizeof(returnType));
    if(returnType[0]!='v'){AACSBRejectedMethods++;[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  SKIP %@ reason=返回类型=%s（非 void，固定签名不安全）",selectorName,returnType]];continue;}
    IMP current=method_getImplementation(methods[j]);
    if(current==(IMP)AACSBAnswerHook){AACSBRejectedMethods++;[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  SKIP %@ reason=该实现已经是本插件的挂钩（绝不重复挂钩）",selectorName]];continue;}
    NSString *key=[NSString stringWithFormat:@"%@|%@",name,selectorName];
    if([AACSBHookedKeys containsObject:key])continue;
    if(current&&[AACSBHookedIMPs containsObject:@((uintptr_t)current)]){AACSBRejectedMethods++;[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  SKIP %@ reason=同一 IMP 已在别处挂钩（绝不重复挂钩）",selectorName]];continue;}
    if(AACSBHookCount>=AACSBHookCap){[AACSBDiscoveryLines addObject:@"# 挂钩数量达到 24 上限，其余候选只记录不挂钩"];break;}
    IMP original=method_setImplementation(methods[j],(IMP)AACSBAnswerHook);
    if(!original||original==(IMP)AACSBAnswerHook){
     if(original==(IMP)AACSBAnswerHook)method_setImplementation(methods[j],original);
     AACSBRejectedMethods++;[AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  SKIP %@ reason=挂钩失败或检测到重复挂钩，已回滚",selectorName]];continue;
    }
    AACSBHookRecords[AACSBHookCount].cls=classes[i];
    AACSBHookRecords[AACSBHookCount].sel=selector;
    AACSBHookRecords[AACSBHookCount].original=original;
    AACSBHookCount++;
    [AACSBHookedKeys addObject:key];
    [AACSBHookedIMPs addObject:@((uintptr_t)current)];
    [AACSBHookedSelectors addObject:[NSString stringWithFormat:@"-[%@ %@]",name,selectorName]];
    picked++;
    [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  HOOKED %@ originalIMP=%p（零参数 void，可安全直通）",selectorName,(void *)original]];
   }
   free(methods);
  }
  [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"  hooked=%lu",(unsigned long)picked]];
  if(AACSBDiscoveryLines.count>3000){[AACSBDiscoveryLines addObject:@"# 摘要行数达上限，后续候选不再逐行记录"];break;}
 }
 free(classes);
 AACSBMatchedClasses+=matched;
 [AACSBDiscoveryLines addObject:[NSString stringWithFormat:@"# end run %lu scanned=%d matchedClasses=%lu hookedMethods=%lu rejected=%lu",(unsigned long)AACSBDiscoverRuns,count,(unsigned long)matched,(unsigned long)AACSBHookCount,(unsigned long)AACSBRejectedMethods]];
 AACSBWriteDiscoveryFile();
}
static inline void AACSBStart(AACSBEnv *env){
 AACSBEnvShared=env;
 @try{AACSBDiscover();}@catch(NSException *e){AACSBLog([@"discovery exception: " stringByAppendingString:e.reason?:@"unknown"]);AACSBRecord(@"运行时发现异常：接听路径退化为仅日志",@{@"discovered":@NO});}
}
/* A call arrived and we still have nothing hooked: the class list can grow after other
   frameworks load, so retry the enumeration a bounded number of times. */
static inline void AACSBRetryDiscoveryIfEmpty(void){
 if(AACSBHookCount)return;
 if(AACSBDiscoverRuns>=AACSBMaxDiscoverRuns)return;
 AACSBLog(@"no dynamic hook discovered yet; re-running the runtime enumeration because a call event arrived");
 @try{AACSBDiscover();}@catch(NSException *e){AACSBLog([@"discovery retry exception: " stringByAppendingString:e.reason?:@"unknown"]);}
}
