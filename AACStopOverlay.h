#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AACAudioHandoff.h"
/* iOS 17.3 in-call layout test. This is a reversible in-window COVER of the
   native "添加 / Add Call" button, not a new independent top-right button and
   not a private call-control action. No tap event is forwarded to Add Call. */
static UIView *AACStopOverlayHost;
static UIButton *AACStopOverlayButton;
static UILabel *AACStopOverlayLabel;
static __weak UIView *AACStopOverlayNativeAdd;
static BOOL AACStopOverlayNativeWasHidden;
static id AACStopOverlayTarget;
static CXCallObserver *AACStopOverlayObserver;
static BOOL AACStopOverlayWaitingForAck;
static CFAbsoluteTime AACStopOverlayWaitStart;
static NSString *AACStopOverlayLastEvent;
static CFAbsoluteTime AACStopOverlayLastInventory;
static NSUInteger AACStopOverlayInventoryCount;
static void (^AACStopOverlayLogger)(NSString *);
static inline void AACStopOverlayLog(NSString *s){if(AACStopOverlayLogger)AACStopOverlayLogger(s);}
static inline NSUUID *AACStopOverlayConnectedUUID(void){
 for(CXCall *call in AACStopOverlayObserver.calls){
  if(!call.outgoing&&!call.hasEnded&&call.hasConnected)return call.UUID;
 }
 return nil;
}
static inline void AACStopOverlayRestoreNative(void){
 if(AACStopOverlayNativeAdd)AACStopOverlayNativeAdd.hidden=AACStopOverlayNativeWasHidden;
 AACStopOverlayNativeAdd=nil;
}
static inline void AACStopOverlayRemove(void){
 [AACStopOverlayHost removeFromSuperview]; AACStopOverlayHost=nil;
 AACStopOverlayButton=nil;AACStopOverlayLabel=nil;
 AACStopOverlayRestoreNative();
 AACStopOverlayWaitingForAck=NO;
}
static inline BOOL AACStopOverlayIsAddLabel(NSString *text){
 if(![text isKindOfClass:NSString.class])return NO;
 NSString *t=[[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
 return [@[@"添加",@"添加通话",@"add call",@"add calls"] containsObject:t];
}
/* Search visible label/control on the actual call scene; capped to avoid UI stalls.
   This needs injection in the call-screen host. SpringBoard's home window is not a substitute. */
static inline UIView *AACStopOverlayFindAdd(UIView *root,NSUInteger *visited){
 if(!root||++*visited>1600||root.hidden||root.alpha<0.05)return nil;
 BOOL matching=AACStopOverlayIsAddLabel(root.accessibilityLabel)||AACStopOverlayIsAddLabel(root.accessibilityIdentifier);
 if([root isKindOfClass:UILabel.class])matching=matching||AACStopOverlayIsAddLabel(((UILabel *)root).text);
 if([root isKindOfClass:UIButton.class])matching=matching||AACStopOverlayIsAddLabel([(UIButton *)root currentTitle]);
 if(matching){
  UIView *v=root;
  /* Prefer the tappable call-control container rather than hiding just its caption. */
  for(NSUInteger n=0;n<4&&v.superview;n++){
   if([v isKindOfClass:UIControl.class]&&v.bounds.size.width>=60)return v;
   if(v.superview.bounds.size.width>=70&&v.superview.bounds.size.width<=170&&
      v.superview.bounds.size.height>=70&&v.superview.bounds.size.height<=170)return v.superview;
   v=v.superview;
  }
  return root;
 }
 for(UIView *child in root.subviews){
  UIView *found=AACStopOverlayFindAdd(child,visited);
  if(found)return found;
  if(*visited>=1600)break;
 }
 return nil;
}
/* TelephonyUI evidence in CallAssist: TPSlidingButton / TPPillView exist there.
   Those classes relate to incoming-call controls, NOT automatically to the active Add control.
   Prefer visible native view identification; this optional accessor probe is read-only.
   Guard signature before invoking unknown private implementations. */
static inline UIView *AACStopOverlayFindAddAccessor(UIViewController *controller,NSUInteger depth){
 if(!controller||depth>6)return nil;
 for(NSString *name in @[@"addCallButton",@"addCallButtonView",@"addButton",@"addCallView",@"addCallControl"]){
  SEL sel=NSSelectorFromString(name);
  Method m=class_getInstanceMethod([controller class],sel);
  if(!m||method_getNumberOfArguments(m)!=2)continue;
  char result[16]={0};method_getReturnType(m,result,sizeof(result));
  if(result[0]!='@')continue;
  @try{
   id value=((id(*)(id,SEL))objc_msgSend)(controller,sel);
   if([value isKindOfClass:UIView.class]){
    UIView *view=(UIView *)value;
    if(view.window&&!view.hidden&&view.alpha>0.05&&view.bounds.size.width>20){
     AACStopOverlayLog([NSString stringWithFormat:@"CALLUI add-accessor controller=%@ selector=%@ view=%@",NSStringFromClass(controller.class),name,NSStringFromClass(view.class)]);
     return view;
    }
   }
  }@catch(NSException *e){AACStopOverlayLog([NSString stringWithFormat:@"CALLUI accessor exception selector=%@ type=%@",name,NSStringFromClass(controller.class)]);}
 }
 for(UIViewController *child in controller.childViewControllers){
  UIView *v=AACStopOverlayFindAddAccessor(child,depth+1);if(v)return v;
 }
 if(controller.presentedViewController)return AACStopOverlayFindAddAccessor(controller.presentedViewController,depth+1);
 return nil;
}
/* Read-only environment snapshot: never include phone numbers or arbitrary labels. */
static inline void AACStopOverlayInventory(void){
 CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
 if(now-AACStopOverlayLastInventory<12)return;
 AACStopOverlayLastInventory=now;
 NSMutableArray *known=[NSMutableArray new];
 for(NSString *className in @[@"TPSlidingButton",@"TPPillView",@"TPInComingCallUISnapshotViewController"]){
  [known addObject:[NSString stringWithFormat:@"%@=%d",className,objc_getClass(className.UTF8String)!=nil]];
 }
 UIApplication *app=UIApplication.sharedApplication;
 NSUInteger scenes=0,windows=0,addMatches=0,controls=0,telephony=0;
 NSMutableArray *samples=[NSMutableArray new];
 for(UIScene *scene in app.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class])continue;
  scenes++;
  for(UIWindow *window in ((UIWindowScene *)scene).windows){
   windows++;
   NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:window];
   NSUInteger visited=0;
   while(queue.count&&visited<1800){
    UIView *v=queue.lastObject;[queue removeLastObject];visited++;
    if([v isKindOfClass:UIControl.class])controls++;
    NSString *cls=NSStringFromClass(v.class);
    if([cls hasPrefix:@"TP"]||[cls hasPrefix:@"PH"]||[cls hasPrefix:@"ICS"]){
     telephony++;
     if(samples.count<12&&![samples containsObject:cls])[samples addObject:cls];
    }
    NSString *identifier=v.accessibilityIdentifier;
    if(AACStopOverlayIsAddLabel(identifier)||AACStopOverlayIsAddLabel(v.accessibilityLabel))addMatches++;
    if([v isKindOfClass:UILabel.class]&&AACStopOverlayIsAddLabel(((UILabel *)v).text))addMatches++;
    [queue addObjectsFromArray:v.subviews];
   }
   if(windows<=4)AACStopOverlayLog([NSString stringWithFormat:@"CALLUI window type=%@ root=%@ hidden=%d alpha=%.1f bounds=%@",NSStringFromClass(window.class),window.rootViewController?NSStringFromClass(window.rootViewController.class):@"none",window.hidden,window.alpha,NSStringFromCGRect(window.bounds)]);
  }
 }
 AACStopOverlayInventoryCount++;
 AACStopOverlayLog([NSString stringWithFormat:@"CALLUI inventory seq=%lu scene=%lu windows=%lu controls=%lu telephonyViews=%lu addLabels=%lu classes={%@} sample={%@}",(unsigned long)AACStopOverlayInventoryCount,(unsigned long)scenes,(unsigned long)windows,(unsigned long)controls,(unsigned long)telephony,(unsigned long)addMatches,[known componentsJoinedByString:@","],[samples componentsJoinedByString:@","]]);
}
static inline UIWindow *AACStopOverlayWindow(UIView **nativeAdd,CGRect *target){
 /* Once native Add is hidden by us, a normal visible-view scan cannot rediscover it.
    Reuse its existing live window and coordinate anchor until the call ends. */
 UIView *cached=AACStopOverlayNativeAdd;
 if(cached&&cached.window&&cached.bounds.size.width>0){
  UIWindow *w=cached.window;
  CGRect r=[cached convertRect:cached.bounds toView:w];
  CGFloat x=CGRectGetMidX(r),y=CGRectGetMidY(r);
  if(r.size.height<45)y-=50;
  if(nativeAdd)*nativeAdd=cached;
  if(target)*target=CGRectMake(MAX(2,x-56),MAX(2,y-56),112,116);
  return w;
 }
 UIApplication *app=UIApplication.sharedApplication;
 NSMutableArray<UIWindow *> *candidates=[NSMutableArray new];
 for(UIScene *scene in app.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *w in ((UIWindowScene *)scene).windows)if(![candidates containsObject:w])[candidates addObject:w];
 }
 /* app.windows 在 iOS15+ 标记弃用；语义仍为“回退枚举所有窗口”，保持原行为，仅抑制 -Werror 弃用告警。 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
 for(UIWindow *w in app.windows)if(![candidates containsObject:w])[candidates addObject:w];
#pragma clang diagnostic pop
 UIWindow *fallback=nil;
 for(UIWindow *w in candidates){
  if(w.hidden||w.alpha<0.05||w.bounds.size.width<200||w.bounds.size.height<350||!w.rootViewController)continue;
  NSUInteger visited=0;
  UIView *add=AACStopOverlayFindAdd(w,&visited);
  if(!add)add=AACStopOverlayFindAddAccessor(w.rootViewController,0);
  if(add){
   CGRect r=[add convertRect:add.bounds toView:w];
   if(CGRectIsEmpty(r)||CGRectIsNull(r))continue;
   if(nativeAdd)*nativeAdd=add;
   /* The original caption is below the round control. Keep its column center. */
   CGFloat x=CGRectGetMidX(r), y=CGRectGetMidY(r);
   BOOL captionSize=r.size.height<45;
   if(captionSize)y-=50;
   if(target)*target=CGRectMake(MAX(2,x-56),MAX(2,y-56),112,116);
   return w;
  }
  if(!fallback||w.isKeyWindow)fallback=w;
 }
 /* The prior percentage-of-screen fallback could conceal a different system action.
    Do not overlay without identifying the real Add control in this very window. */
 if(fallback)AACStopOverlayLog(@"CALLUI add-not-located: no geometry fallback; native controls preserved");
 return nil;
}
static inline NSUUID *AACStopOverlayVerifiedUUID(void){
 NSUUID *connected=AACStopOverlayConnectedUUID();
 NSDictionary *state=AACAudioReadState();
 if(connected)return connected; /* trusted active CXCallObserver UUID even when audio failed */
 if(![state[@"status"] isEqualToString:@"playing"]||![state[@"timestamp"] respondsToSelector:@selector(doubleValue)])return nil;
 double age=NSDate.date.timeIntervalSince1970-[state[@"timestamp"] doubleValue];
 if(age<0||age>12)return nil;
 UIView *add=nil;CGRect frame=CGRectZero;
 if(!AACStopOverlayWindow(&add,&frame)||!add)return nil;
 return [[NSUUID alloc] initWithUUIDString:state[@"uuid"]];
}
static void AACStopOverlayUpdate(void);
@interface AACStopOverlayHandler : NSObject
- (void)stopPressed:(id)sender;
@end
@implementation AACStopOverlayHandler
- (void)stopPressed:(id)sender{
 NSUUID *connected=AACStopOverlayVerifiedUUID();
 NSDictionary *state=AACAudioReadState();
 if(!connected){
  AACStopOverlayLog(@"MANUAL_HANDOFF reject=no-verified-call; native Add remains unchanged");
  AACStopOverlayUpdate();return;
 }
 if(AACAudioStopMatches(connected)){
  AACStopOverlayLog(@"MANUAL_HANDOFF already-manually-stopped; no duplicate request");return;
 }
 if(AACStopOverlayWaitingForAck)return;
 BOOL sent=AACAudioRequestManualStop(connected);
 AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF native-add-replacement-tapped uuid=%@ stopRequestWritten=%d; no hangup",connected.UUIDString,sent]);
 if(sent){
  AACStopOverlayWaitingForAck=YES;
  AACStopOverlayWaitStart=CFAbsoluteTimeGetCurrent();
  [AACStopOverlayLabel setText:@"正在停止…"];
  AACStopOverlayButton.enabled=NO;
 }else{
  [AACStopOverlayLabel setText:@"重试停止播放"];
  AACStopOverlayButton.enabled=YES;
 }
}
@end
static void AACStopOverlayUpdate(void){
 AACStopOverlayInventory();
 NSDictionary *cfg=AACBridgeRead();
 BOOL optIn=[cfg[@"Enabled"] boolValue]&&[cfg[@"PlayAudio"] boolValue];
 NSDictionary *state=AACAudioReadState();
 NSUUID *connected=AACStopOverlayVerifiedUUID();
 BOOL playing=connected&&[state[@"uuid"] isEqualToString:connected.UUIDString]&&
     [state[@"status"] isEqualToString:@"playing"];
 /* A verified connected call may have no audio due to session suppression. Still show
    a manual-takeover control in place of Add, per user preference. */
 if(!optIn||!connected){
  if(AACStopOverlayHost)AACStopOverlayLog(@"MANUAL_HANDOFF native-add-restored: no connected call or opt-in disabled");
  AACStopOverlayRemove();return;
 }
 if(AACStopOverlayWaitingForAck&&CFAbsoluteTimeGetCurrent()-AACStopOverlayWaitStart>3.0){
  AACStopOverlayWaitingForAck=NO;
  AACStopOverlayLog(@"MANUAL_HANDOFF stop ACK timeout; retry enabled");
 }
 UIView *native=nil;CGRect frame=CGRectZero;
 UIWindow *w=AACStopOverlayWindow(&native,&frame);
 if(!w||!native){
  if(AACStopOverlayHost)AACStopOverlayRemove();
  NSString *event=[NSString stringWithFormat:@"no-native-add host=InCallService uuid=%@ (system Add preserved)",connected.UUIDString];
  if(![AACStopOverlayLastEvent isEqualToString:event]){AACStopOverlayLastEvent=event;AACStopOverlayLog([@"MANUAL_HANDOFF " stringByAppendingString:event]);}
  return;
 }
 if(native!=AACStopOverlayNativeAdd){
  AACStopOverlayRemove();
  AACStopOverlayNativeAdd=native;
  AACStopOverlayNativeWasHidden=native.hidden;
  AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF native-add-identified class=%@ frame=%@",NSStringFromClass(native.class),NSStringFromCGRect(frame)]);
 }
 /* The user chose to replace Add during the connected call, even if local audio is
    blocked by iOS. Native Add is restored at hangup or when the opt-in is disabled.
    Never hide an unverified control or do a geometry-only overlay. */
 native.hidden=YES;
 if(!AACStopOverlayHost){
  UIView *host=[[UIView alloc] initWithFrame:frame];
  host.backgroundColor=UIColor.clearColor;
  UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
  b.accessibilityIdentifier=@"AACManualStopAudioButton";
  b.accessibilityLabel=@"停止预设音频，人工继续通话";
  b.frame=CGRectMake(15,0,82,82);b.layer.cornerRadius=41;b.layer.masksToBounds=YES;
  b.titleLabel.font=[UIFont boldSystemFontOfSize:30];
  [b setTitle:@"■" forState:UIControlStateNormal];
  [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  [b addTarget:AACStopOverlayTarget action:@selector(stopPressed:) forControlEvents:UIControlEventTouchUpInside];
  [host addSubview:b];
  UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(0,88,112,27)];
  label.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
  label.textColor=UIColor.whiteColor;label.textAlignment=NSTextAlignmentCenter;
  [host addSubview:label];
  AACStopOverlayButton=b;AACStopOverlayLabel=label;AACStopOverlayHost=host;
  AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF native-add-replacement-created uuid=%@ window=%@",connected.UUIDString,NSStringFromClass(w.class)]);
 }
 AACStopOverlayHost.frame=frame;
 if(AACStopOverlayHost.superview!=w){[AACStopOverlayHost removeFromSuperview];[w addSubview:AACStopOverlayHost];}
 [w bringSubviewToFront:AACStopOverlayHost];
 AACStopOverlayButton.backgroundColor=[UIColor colorWithRed:0.87 green:0.19 blue:0.18 alpha:1.0];
 BOOL manuallyStopped=AACAudioStopMatches(connected);
 AACStopOverlayButton.enabled=!AACStopOverlayWaitingForAck&&!manuallyStopped;
 AACStopOverlayLabel.text=AACStopOverlayWaitingForAck?@"正在停止…":(manuallyStopped?@"已接管":(playing?@"停止播放":@"人工接管"));
 NSString *event=[NSString stringWithFormat:@"native-add-replacement-visible uuid=%@ window=%@",connected.UUIDString,NSStringFromClass(w.class)];
 if(![AACStopOverlayLastEvent isEqualToString:event]){AACStopOverlayLastEvent=event;AACStopOverlayLog([@"MANUAL_HANDOFF " stringByAppendingString:event]);}
}
static inline void AACStopOverlayStart(CXCallObserver *observer,void(^logger)(NSString *)){
 AACStopOverlayObserver=observer;
 AACStopOverlayLogger=[logger copy];
 AACStopOverlayTarget=[AACStopOverlayHandler new];
 int token=0;
 uint32_t result=notify_register_dispatch(AACAudioStateChanged.UTF8String,&token,dispatch_get_main_queue(),^(int t){AACStopOverlayUpdate();});
 AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF 1.17.9 InCallService UI registered status=%u",result]);
 NSTimer *timer=[NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t){AACStopOverlayUpdate();}];
 [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
 AACStopOverlayUpdate();
}
