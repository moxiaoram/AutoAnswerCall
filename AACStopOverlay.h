#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <QuartzCore/QuartzCore.h>
#import "AACAudioHandoff.h"
/* Button is attached to a *real InCallService UIWindow*, when that process owns one.
   It does not intercept other call controls, touch the microphone, or end the call. */
static UIButton *AACStopOverlayButton;
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
static inline void AACStopOverlayRemove(void){
 if(AACStopOverlayButton){[AACStopOverlayButton removeFromSuperview];AACStopOverlayButton=nil;}
 AACStopOverlayWaitingForAck=NO;
}
static inline UIWindow *AACStopOverlayWindow(void){
 UIApplication *app=UIApplication.sharedApplication;
 /* The call UI is hosted by InCallService. We never choose SpringBoard's home window. */
 for(UIScene *scene in app.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class])continue;
  UIWindowScene *ws=(UIWindowScene *)scene;
  if(ws.activationState!=UISceneActivationStateForegroundActive&&
     ws.activationState!=UISceneActivationStateForegroundInactive)continue;
  for(UIWindow *w in ws.windows){
   if(w.hidden||w.alpha<0.01||!w.rootViewController||w.bounds.size.width<200||w.bounds.size.height<350)continue;
   if(w.isKeyWindow)return w;
  }
  for(UIWindow *w in ws.windows){
   if(!w.hidden&&w.alpha>0.01&&w.rootViewController&&w.bounds.size.width>=200&&w.bounds.size.height>=350)return w;
  }
 }
 return nil;
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
  AACStopOverlayLog(@"MANUAL_HANDOFF reject=stale-or-call-not-connected");
  AACStopOverlayRemove();return;
 }
 if(AACStopOverlayWaitingForAck)return;
 BOOL sent=AACAudioRequestManualStop(connected);
 AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF button-tapped uuid=%@ stopRequestWritten=%d (playback owner must ACK)",connected.UUIDString,sent]);
 if(sent){
  AACStopOverlayWaitingForAck=YES;
  AACStopOverlayWaitStart=CFAbsoluteTimeGetCurrent();
  [AACStopOverlayButton setTitle:@"正在停止…" forState:UIControlStateNormal];
  AACStopOverlayButton.enabled=NO;
 }else{
  [AACStopOverlayButton setTitle:@"停止失败，重试" forState:UIControlStateNormal];
  AACStopOverlayButton.enabled=YES;
 }
}
@end
static void AACStopOverlayUpdate(void){
 NSUUID *connected=AACStopOverlayConnectedUUID();
 NSDictionary *state=AACAudioReadState();
 BOOL active=connected&&[state[@"uuid"] isEqualToString:connected.UUIDString]&&
      [state[@"status"] isEqualToString:@"playing"];
 if(!active){
  if(AACStopOverlayButton){
   AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF button-hidden reason=%@",connected?@"not-playing":@"call-not-connected"]);
   AACStopOverlayRemove();
  }
  return;
 }
 if(AACStopOverlayWaitingForAck&&CFAbsoluteTimeGetCurrent()-AACStopOverlayWaitStart>3.0){
  AACStopOverlayWaitingForAck=NO;
  AACStopOverlayLog(@"MANUAL_HANDOFF stop-request ACK timeout; allow manual retry");
  [AACStopOverlayButton setTitle:@"重试停止播放" forState:UIControlStateNormal];
  AACStopOverlayButton.enabled=YES;
 }
 UIWindow *w=AACStopOverlayWindow();
 if(!w){
  NSString *event=[NSString stringWithFormat:@"no-call-window uuid=%@",connected.UUIDString];
  if(![AACStopOverlayLastEvent isEqualToString:event]){AACStopOverlayLastEvent=event;AACStopOverlayLog([@"MANUAL_HANDOFF " stringByAppendingString:event]);}
  return;
 }
 if(!AACStopOverlayButton){
  UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
  b.accessibilityIdentifier=@"AACManualStopAudioButton";
  b.accessibilityLabel=@"停止预设音频并人工接管通话";
  b.backgroundColor=[UIColor colorWithRed:0.78 green:0.12 blue:0.16 alpha:0.96];
  [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  [b setTitle:@"停止播放" forState:UIControlStateNormal];
  b.titleLabel.font=[UIFont boldSystemFontOfSize:15];
  b.layer.cornerRadius=11;
  b.layer.masksToBounds=YES;
  [b addTarget:AACStopOverlayTarget action:@selector(stopPressed:) forControlEvents:UIControlEventTouchUpInside];
  AACStopOverlayButton=b;
  AACStopOverlayWaitingForAck=NO;
  AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF button-created uuid=%@ window=%@",connected.UUIDString,NSStringFromClass(w.class)]);
 }
 if(AACStopOverlayButton.superview!=w){
  [AACStopOverlayButton removeFromSuperview];
  [w addSubview:AACStopOverlayButton];
 }
 CGFloat safeTop=MAX(w.safeAreaInsets.top,20.0);
 AACStopOverlayButton.frame=CGRectMake(MAX(8.0,w.bounds.size.width-140.0),safeTop+10.0,128.0,44.0);
 AACStopOverlayButton.hidden=NO;
 [w bringSubviewToFront:AACStopOverlayButton];
}
static inline void AACStopOverlayStart(CXCallObserver *observer,void(^logger)(NSString *)){
 AACStopOverlayObserver=observer;
 AACStopOverlayLogger=[logger copy];
 AACStopOverlayTarget=[AACStopOverlayHandler new];
 int token=0;
 uint32_t result=notify_register_dispatch(AACAudioStateChanged.UTF8String,&token,dispatch_get_main_queue(),^(int t){AACStopOverlayUpdate();});
 AACStopOverlayLog([NSString stringWithFormat:@"MANUAL_HANDOFF UI observer registered status=%u",result]);
 /* Also poll while the InCallService UI exists: on iOS 17 scene/window creation can
    lag behind the system answer. This avoids relying on a one-time notification. */
 NSTimer *timer=[NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t){
  AACStopOverlayUpdate();
 }];
 [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
 AACStopOverlayUpdate();
}
