#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <QuartzCore/QuartzCore.h>
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
 for(UIWindow *w in app.windows)if(![candidates containsObject:w])[candidates addObject:w];
 UIWindow *fallback=nil;
 for(UIWindow *w in candidates){
  if(w.hidden||w.alpha<0.05||w.bounds.size.width<200||w.bounds.size.height<350||!w.rootViewController)continue;
  NSUInteger visited=0;
  UIView *add=AACStopOverlayFindAdd(w,&visited);
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
 /* Geometry fallback only for an already connected in-call host; do not use in SpringBoard.
    iOS 17.3 screenshot: Add Call is lower-left of the 3-column call-controls grid. */
 if(fallback&&target){
  CGFloat centerX=fallback.bounds.size.width*0.20;
  CGFloat centerY=fallback.bounds.size.height*0.875;
  *target=CGRectMake(MAX(2,centerX-56),MIN(fallback.bounds.size.height-120,MAX(2,centerY-58)),112,116);
 }
 return fallback;
}
static void AACStopOverlayUpdate(void);
@interface AACStopOverlayHandler : NSObject
- (void)stopPressed:(id)sender;
@end
@implementation AACStopOverlayHandler
- (void)stopPressed:(id)sender{
 NSUUID *connected=AACStopOverlayConnectedUUID();
 NSDictionary *state=AACAudioReadState();
 if(!connected||![state[@"uuid"] isEqualToString:connected.UUIDString]||
    ![state[@"status"] isEqualToString:@"playing"]){
  AACStopOverlayLog(@"MANUAL_HANDOFF reject=not-playing-or-stale-UUID; call remains connected");
  AACStopOverlayUpdate();return;
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
 NSUUID *connected=AACStopOverlayConnectedUUID();
 NSDictionary *cfg=AACBridgeRead();
 BOOL optIn=[cfg[@"Enabled"] boolValue]&&[cfg[@"PlayAudio"] boolValue];
 if(!connected||!optIn){if(AACStopOverlayHost)AACStopOverlayLog(@"MANUAL_HANDOFF native-add-replacement-removed call-ended-or-disabled");AACStopOverlayRemove();return;}
 NSDictionary *state=AACAudioReadState();
 BOOL matching=[state[@"uuid"] isEqualToString:connected.UUIDString];
 BOOL playing=matching&&[state[@"status"] isEqualToString:@"playing"];
 if(AACStopOverlayWaitingForAck){
  if(!playing)AACStopOverlayWaitingForAck=NO;
  else if(CFAbsoluteTimeGetCurrent()-AACStopOverlayWaitStart>3.0){
   AACStopOverlayWaitingForAck=NO;
   AACStopOverlayLog(@"MANUAL_HANDOFF stop-request ACK timeout; allow retry");
  }
 }
 UIView *native=nil;CGRect frame=CGRectZero;
 UIWindow *w=AACStopOverlayWindow(&native,&frame);
 if(!w){
  NSString *event=[NSString stringWithFormat:@"no-call-window host=InCallService uuid=%@",connected.UUIDString];
  if(![AACStopOverlayLastEvent isEqualToString:event]){AACStopOverlayLastEvent=event;AACStopOverlayLog([@"MANUAL_HANDOFF " stringByAppendingString:event]);}
  return;
 }
 /* If the native Add control is known, hide just that control while the replacement
    occupies its own window-space frame. Restore on hangup / disabled mode. */
 if(native&&native!=AACStopOverlayNativeAdd){
  AACStopOverlayRestoreNative();
  AACStopOverlayNativeAdd=native;
  AACStopOverlayNativeWasHidden=native.hidden;
  native.hidden=YES;
  AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF native-add-found class=%@ frame=%@",NSStringFromClass(native.class),NSStringFromCGRect(frame)]);
 }
 if(!AACStopOverlayHost){
  UIView *host=[[UIView alloc] initWithFrame:frame];
  host.backgroundColor=UIColor.clearColor;
  UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
  b.accessibilityIdentifier=@"AACManualStopAudioButton";
  b.accessibilityLabel=@"停止预设音频，人工继续通话";
  b.frame=CGRectMake(15,0,82,82);
  b.layer.cornerRadius=41;b.layer.masksToBounds=YES;
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
  AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF native-add-replacement-created uuid=%@ window=%@ nativeFound=%d",connected.UUIDString,NSStringFromClass(w.class),native!=nil]);
 }
 AACStopOverlayHost.frame=frame;
 if(AACStopOverlayHost.superview!=w){[AACStopOverlayHost removeFromSuperview];[w addSubview:AACStopOverlayHost];}
 [w bringSubviewToFront:AACStopOverlayHost];
 AACStopOverlayButton.backgroundColor=playing?[UIColor colorWithRed:0.87 green:0.19 blue:0.18 alpha:1.0]:[UIColor colorWithWhite:0.43 alpha:1.0];
 AACStopOverlayButton.enabled=playing&&!AACStopOverlayWaitingForAck;
 AACStopOverlayLabel.text=AACStopOverlayWaitingForAck?@"正在停止…":(playing?@"停止播放":([state[@"status"] isEqualToString:@"stopped"]?@"已停止":@"音频未播放"));
 NSString *event=[NSString stringWithFormat:@"native-add-replacement-visible uuid=%@ playing=%d status=%@ nativeFound=%d window=%@",connected.UUIDString,playing,matching?state[@"status"]:@"no-matching-state",native!=nil,NSStringFromClass(w.class)];
 if(![AACStopOverlayLastEvent isEqualToString:event]){AACStopOverlayLastEvent=event;AACStopOverlayLog([@"MANUAL_HANDOFF " stringByAppendingString:event]);}
}
static inline void AACStopOverlayStart(CXCallObserver *observer,void(^logger)(NSString *)){
 AACStopOverlayObserver=observer;
 AACStopOverlayLogger=[logger copy];
 AACStopOverlayTarget=[AACStopOverlayHandler new];
 int token=0;
 uint32_t result=notify_register_dispatch(AACAudioStateChanged.UTF8String,&token,dispatch_get_main_queue(),^(int t){AACStopOverlayUpdate();});
 AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF 1.17.8 InCallService UI registered status=%u",result]);
 NSTimer *timer=[NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t){AACStopOverlayUpdate();}];
 [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
 AACStopOverlayUpdate();
}
