#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
/* ======================= 1.17.1 TASK 1/2: 活体按钮发现 + 模拟点击 =======================
   为什么换成按钮路径（决定性设备证据，来自用户在 iOS 17.3 RootHide 设备上的 1.16.0 分片回读）：
     - 三个宿主全部注入：springboard pid=9061、mobilephone pid=9145、incall pid=9146。
     - 三个宿主全部自报 role=LOG-ONLY、answerPaths=0：incall「0 个 ACTION（其中已挂钩 0、
       NSInvocation 候选 0），8 个 ACCESSOR 挂钩（仅证据）」，springboard 同形；mobilephone
       keys=0（fail-closed，配置对它不可见）。
     - 状态槽通道本身可用（校验=通过，incall 88 槽 / 525 字节）；名内分片通道无法被注册
       （Darwin 通知不支持通配，1.16.0 已记录该限制）。
   结论：以「类名 + 选择器关键字」为唯一策略的发现，在任何宿主里都找不到真正的接听动作，
   而且这是结构性的——真正的接听是一个 UI 按钮，它的响应走 UIControl 的 action 机制
   （sendActionsForControlEvents:），方法名里永远不会出现 answer/accept。关键字匹配在原理上
   就不可能找到它。
   1.17.1 因此把按钮路径变为主策略（方法名关键字发现保留，但已知不足）：
     1) 来电期间在每个拥有来电 UI 的宿主里遍历活体层级（窗口场景 → 已呈现/子视图控制器 →
        子视图 → 响应者链），有界（≤6000 节点、深度 ≤40、1.5 秒时间预算）；
     2) 收集候选 UIControl（含 UIButton 及任意 UIControl 子类），按信号优先级打分；
     3) 只对「非黑名单」候选执行点击，点击方式按顺序尝试三种；
     4) 全部候选、所选控件、所用机制、以及随后是否真的接通都写进发现文件、共享日志，并通过
        1.16.0 的分片/状态槽通道一起发布出去。
   安全闸门（本版本绝不放松）：
     - 拒绝/挂断关键字（decline/reject/hangup/end call/… /拒接/挂断/结束）同时作用于
       accessibilityIdentifier、accessibilityLabel、accessibilityValue 与按钮标题；颜色为红色
       主导的控件同样一律列入黑名单。黑名单候选会被记录但绝不点击。
     - 只点 enabled、userInteractionEnabled、非隐藏、alpha>0.01、有 window 的控件。
     - 每个通话 UUID 只点击一次；点击前若已观察到更高优先级宿主真的点过（buttontap 通知），
       直接让出，绝不出现两个宿主同时点击。
     - 整个扫描/点击都在 @try 内，任何异常都只记录，不抛出。 */

/* 通知通道：某个宿主真的点击了接听按钮时广播（1.17.1 新增）。名内无载荷，只断言到达。
   这是「避免双重点击」的依据：低优先级宿主在结算窗口后看到高优先级宿主的点击通知就让出。 */
static NSString * const AACButtonTapPrefix=@"com.autoanswer.call.buttontap.";

enum {
 AACButtonNodeCap=6000,          /* 单次扫描最多访问的层级节点数 */
 AACButtonDepthCap=40,           /* 最大递归深度 */
 AACButtonCandidateCap=32,       /* 最多收集的候选控件数 */
 AACButtonResponderUpCap=12,     /* 响应者链最多上溯层数 */
 AACButtonScanRunCap=6,          /* 保留的最近扫描报告条数（有界） */
 AACButtonTapArgumentCap=3       /* NSInvocation 机制最多构造的显式参数个数 */
};
static NSTimeInterval const AACButtonScanBudgetSeconds=1.5;   /* 时间预算，超时安全停止 */
static NSTimeInterval const AACButtonOwnerSettleSeconds=1.2;  /* 低优先级宿主让出前的结算窗口 */
static NSTimeInterval const AACButtonTapFreshSeconds=90.0;    /* 对端点击通知的有效窗口 */
static double const AACButtonGreenThreshold=0.18;             /* 绿色主导判定阈值 */
static double const AACButtonRedThreshold=0.18;               /* 红色主导（黑名单）判定阈值 */

/* 信号种类，数字越小越强。这就是任务要求的优先级顺序。 */
typedef NS_ENUM(NSInteger,AACButtonSignalKind){
 AACButtonSignalNone=0,
 AACButtonSignalAccessibilityIdentifier=1,
 AACButtonSignalAccessibilityLabel=2,
 AACButtonSignalAccessibilityValue=3,
 AACButtonSignalTitle=4,
 AACButtonSignalLocalization=5,
 AACButtonSignalGreenPrimary=6
};
static inline NSString *AACButtonSignalText(AACButtonSignalKind kind){
 switch(kind){
  case AACButtonSignalAccessibilityIdentifier:return @"accessibilityIdentifier";
  case AACButtonSignalAccessibilityLabel:return @"accessibilityLabel";
  case AACButtonSignalAccessibilityValue:return @"accessibilityValue";
  case AACButtonSignalTitle:return @"titleLabel.text/currentTitle";
  case AACButtonSignalLocalization:return @"localisationSubstring";
  case AACButtonSignalGreenPrimary:return @"greenLeftPrimary(弱信号)";
  default:return @"none";
 }
}
/* 接听关键字（任务给定的清单，逐字保留）。 */
static inline NSArray *AACButtonAcceptKeywords(void){
 return @[@"accept",@"answer",@"acceptcall",@"接听",@"应答",@"answer_call"];
}
/* 已知本地化子串（弱于标识/标题，但强于绿色弱信号）。 */
static inline NSArray *AACButtonLocalizationKeywords(void){
 return @[@"accept",@"answer",@"接听",@"应答",@"annehmen",@"antworten",@"répondre",@"repondre",@"responder",@"rispondi",@"atender",@"aceitar",@"odpowiedz",@"riposta"];
}
/* 硬安全黑名单：命中标识/标签/值/标题的任一候选绝不点击。 */
static inline NSArray *AACButtonForbiddenKeywords(void){
 return @[@"decline",@"reject",@"hangup",@"hang up",@"hang-up",@"endcall",@"end call",@"end_call",@"disconnect",@"dismiss",@"ignore",@"sendtovoicemail",@"voicemail",@"拒接",@"拒绝",@"挂断",@"结束通话",@"结束",@"拒"];
}
static inline NSString *AACButtonMatchedKeyword(NSString *text,NSArray *keywords){
 if(![text isKindOfClass:NSString.class]||!text.length)return nil;
 NSString *lower=text.lowercaseString;
 for(NSString *keyword in keywords){if(keyword.length&&[lower rangeOfString:keyword].location!=NSNotFound)return keyword;}
 return nil;
}
static inline NSString *AACButtonMatchedAcceptKeyword(NSString *text){return AACButtonMatchedKeyword(text,AACButtonAcceptKeywords());}
static inline NSString *AACButtonMatchedLocalizationKeyword(NSString *text){return AACButtonMatchedKeyword(text,AACButtonLocalizationKeywords());}
/* 黑名单检查作用于标识、标签、值与标题四者（任务要求：红色 decline 按钮绝不能被点击）。 */
static inline NSString *AACButtonBlacklistKeyword(id control){
 if(![control isKindOfClass:UIControl.class])return nil;
 UIControl *c=(UIControl *)control;
 NSString *hit=AACButtonMatchedKeyword(c.accessibilityIdentifier,AACButtonForbiddenKeywords());if(hit)return [NSString stringWithFormat:@"identifier:%@",hit];
 hit=AACButtonMatchedKeyword(c.accessibilityLabel,AACButtonForbiddenKeywords());if(hit)return [NSString stringWithFormat:@"label:%@",hit];
 hit=AACButtonMatchedKeyword([c accessibilityValue],AACButtonForbiddenKeywords());if(hit)return [NSString stringWithFormat:@"value:%@",hit];
 if([c isKindOfClass:UIButton.class]){
  UIButton *b=(UIButton *)c;
  hit=AACButtonMatchedKeyword(b.currentTitle,AACButtonForbiddenKeywords());if(hit)return [NSString stringWithFormat:@"title:%@",hit];
  hit=AACButtonMatchedKeyword(b.titleLabel.text,AACButtonForbiddenKeywords());if(hit)return [NSString stringWithFormat:@"titleLabel:%@",hit];
 }
 return nil;
}
/* 按钮标题：titleLabel.text 优先，其次 currentTitle。 */
static inline NSString *AACButtonTitleOf(UIControl *control){
 if(![control isKindOfClass:UIButton.class])return nil;
 UIButton *b=(UIButton *)control;
 @try{
  NSString *label=b.titleLabel.text;
  if([label isKindOfClass:NSString.class]&&label.length)return label;
  NSString *current=b.currentTitle;
  if([current isKindOfClass:NSString.class]&&current.length)return current;
 }@catch(NSException *e){}
 return nil;
}
/* 颜色 → 「绿色主导」「红色主导」的简单判据：该通道比另两个通道的最大值高出阈值。
   非 RGB 颜色（图案、灰度等）返回 0，不猜测。 */
static inline double AACButtonDominance(double r,double g,double b,double a){
 if(a<=0.01)return 0.0;
 double other=r>b?r:b;
 return g-other;
}
static inline double AACButtonRedDominance(double r,double g,double b,double a){
 if(a<=0.01)return 0.0;
 double other=g>b?g:b;
 return r-other;
}
/* 把任意 UIImage 缩到 1×1 再取像素，得到平均颜色（backgroundImage 的绿色判定靠它）。 */
static inline BOOL AACButtonSampleImageColor(UIImage *image,double *r,double *g,double *b,double *a){
 if(![image isKindOfClass:UIImage.class])return NO;
 CGImageRef cg=image.CGImage;
 if(!cg)return NO;
 unsigned char pixel[4]={0,0,0,0};
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 if(!space)return NO;
 CGContextRef ctx=CGBitmapContextCreate(pixel,1,1,8,4,space,kCGImageAlphaPremultipliedLast);
 CGColorSpaceRelease(space);
 if(!ctx)return NO;
 @try{CGContextDrawImage(ctx,CGRectMake(0,0,1,1),cg);}@catch(NSException *e){}
 CGContextRelease(ctx);
 *r=pixel[0]/255.0;*g=pixel[1]/255.0;*b=pixel[2]/255.0;*a=pixel[3]/255.0;
 return YES;
}
/* 绿色主导分数：backgroundColor 优先，其次 UIButton 的背景图（backgroundImage / 当前背景图）。
   返回该控件最绿的一个分数；无可用颜色时返回 0。 */
static inline double AACButtonGreenScore(UIControl *control){
 double best=0.0;
 @try{
  double r=0,g=0,b=0,a=0;
  UIColor *background=control.backgroundColor;
  if([background isKindOfClass:UIColor.class]&&[background getRed:&r green:&g blue:&b alpha:&a]){
   double score=AACButtonDominance(r,g,b,a);if(score>best)best=score;
  }
  if([control isKindOfClass:UIButton.class]){
   UIButton *button=(UIButton *)control;
   UIImage *image=nil;
   @try{image=[button backgroundImageForState:UIControlStateNormal];}@catch(NSException *e){}
   if(!image)@try{image=[button backgroundImageForState:UIControlStateHighlighted];}@catch(NSException *e){}
   if(image&&AACButtonSampleImageColor(image,&r,&g,&b,&a)){double score=AACButtonDominance(r,g,b,a);if(score>best)best=score;}
  }
 }@catch(NSException *e){}
 return best;
}
/* 红色主导（背景色或背景图），用于把红色挂断/拒接按钮一并列入黑名单。 */
static inline BOOL AACButtonIsRedDominant(UIControl *control){
 @try{
  double r=0,g=0,b=0,a=0;
  UIColor *background=control.backgroundColor;
  if([background isKindOfClass:UIColor.class]&&[background getRed:&r green:&g blue:&b alpha:&a])
   if(AACButtonRedDominance(r,g,b,a)>=AACButtonRedThreshold)return YES;
  if([control isKindOfClass:UIButton.class]){
   UIButton *button=(UIButton *)control;
   UIImage *image=nil;
   @try{image=[button backgroundImageForState:UIControlStateNormal];}@catch(NSException *e){}
   if(image&&AACButtonSampleImageColor(image,&r,&g,&b,&a))
    if(AACButtonRedDominance(r,g,b,a)>=AACButtonRedThreshold)return YES;
  }
 }@catch(NSException *e){}
 return NO;
}
/* 同父控件里的 UIControl 数量，以及本控件是否是其中最靠左的那个（两按钮来电布局的主/左按钮）。 */
static inline NSUInteger AACButtonSiblingControlCount(UIControl *control){
 NSUInteger count=0;
 @try{
  UIView *parent=control.superview;
  if(!parent)return 0;
  for(UIView *sibling in parent.subviews)if([sibling isKindOfClass:UIControl.class])count++;
 }@catch(NSException *e){}
 return count;
}
static inline BOOL AACButtonIsLeftPrimary(UIControl *control){
 BOOL left=YES;
 @try{
  UIView *parent=control.superview;
  if(!parent)return NO;
  CGRect mine=control.frame;
  for(UIView *sibling in parent.subviews){
   if(sibling==control||![sibling isKindOfClass:UIControl.class])continue;
   if(sibling.frame.origin.x<mine.origin.x)left=NO;
  }
 }@catch(NSException *e){return NO;}
 return left;
}
/* 可点击性闸门：禁用、隐藏、透明或没有窗口的控件一律不点。 */
static inline BOOL AACButtonIsTappable(UIControl *control){
 if(![control isKindOfClass:UIControl.class])return NO;
 @try{
  if(!control.enabled||!control.userInteractionEnabled)return NO;
  if(control.hidden)return NO;
  if(control.alpha<=0.01)return NO;
  if(!control.window)return NO;
 }@catch(NSException *e){return NO;}
 return YES;
}
static inline NSString *AACButtonFrameText(CGRect frame){
 return [NSString stringWithFormat:@"{{%.0f,%.0f},{%.0f,%.0f}}",frame.origin.x,frame.origin.y,frame.size.width,frame.size.height];
}
static inline NSString *AACButtonColorText(UIColor *color){
 if(![color isKindOfClass:UIColor.class])return @"(nil)";
 double r=0,g=0,b=0,a=0;
 if(![color getRed:&r green:&g blue:&b alpha:&a])return @"(非RGB)";
 return [NSString stringWithFormat:@"r%.2f g%.2f b%.2f a%.2f",r,g,b,a];
}

/* ======================= 状态（头文件唯一，只被 AACSpringBoard.h 包含一次） =============== */
typedef void (^AACButtonLogBlock)(NSString *message);
static AACButtonLogBlock AACButtonLogSink=nil; /* 由 AACSpringBoard.h 接到共享日志；为空则只记录不打印 */
static inline void AACButtonLogLine(NSString *message){
 if(![message isKindOfClass:NSString.class])return;
 if(!AACButtonLogSink)return;
 @try{AACButtonLogSink(message);}@catch(NSException *e){}
}
/* 最近一次扫描的完整证据（候选控件在本数组里被强引用，但整个数组有界、并在下一次扫描或通话
   结束时被清空；除此之外不保留任何控件引用）。 */
static NSMutableArray *AACButtonLastCandidates=nil;
static NSMutableArray *AACButtonReportLines=nil;
static NSMutableArray *AACButtonScanHistory=nil;
static NSUInteger AACButtonNodesVisited=0;
static NSUInteger AACButtonCandidatesFound=0;
static NSUInteger AACButtonBlacklistedFound=0;
static NSUInteger AACButtonScanRuns=0;
static BOOL AACButtonBudgetExceeded=NO;
/* 本宿主在最近一次来电扫描里找到的、可点击的候选控件数量。它是「活体按钮就是一条真实接听
   路径」的依据：0 表示本宿主没有按钮可点。 */
static NSUInteger AACButtonLiveCandidateCount=0;
static NSString *AACButtonChosenText=nil;
static NSString *AACButtonMechanismText=nil;
static NSString *AACButtonTapUUID=nil;
static NSUInteger AACButtonTapCount=0;
/* 接通状态三态：-1 未知、0 未观察到接通、1 观察到接通。 */
static NSInteger AACButtonConnectedState=-1;
static NSMutableSet *AACButtonTappedUUIDs=nil;
static NSMutableDictionary *AACButtonTapSeen=nil;
static volatile int32_t AACButtonScanning=0;
static __weak UIControl *AACButtonLastChosenControl=nil;
enum { AACButtonReportLineCap=160, AACButtonShortTextCap=64 };
static inline NSString *AACButtonShort(NSString *text){
 if(![text isKindOfClass:NSString.class])return @"-";
 NSString *trimmed=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(trimmed.length<=AACButtonShortTextCap)return trimmed.length?trimmed:@"-";
 return [[trimmed substringToIndex:AACButtonShortTextCap] stringByAppendingString:@"…"];
}
/* 前向声明：扫描报告在点击/接通路径里被调用，而它们的定义在文件末尾。 */
static NSString *AACButtonSummaryText(void);
static NSString *AACButtonReportText(void);
static NSString *AACButtonConnectedText(void);
static NSUInteger AACButtonScanReport(NSString *phase);
static inline NSMutableArray *AACButtonReportBuffer(void){
 if(!AACButtonReportLines)AACButtonReportLines=[NSMutableArray new];
 return AACButtonReportLines;
}
static inline void AACButtonReportAdd(NSString *line){
 if(![line isKindOfClass:NSString.class])return;
 @try{
  NSMutableArray *buffer=AACButtonReportBuffer();
  if(buffer.count>=AACButtonReportLineCap)return;
  [buffer addObject:line];
 }@catch(NSException *e){}
}
/* ======================= 活体层级遍历（有界） ============================================ */
/* 一个候选的完整证据行。class / 无障碍标识 / 标签 / 值 / 标题 / frame / tint / 背景色 /
   绿色分数 / 是否红色主导 / 是否左侧主按钮 / 同父控件数 / 命中的信号 / 黑名单 / 是否可点击。
   无论最后点不点，这一行都会写进发现文件与共享日志，保证下一次设备测试是决定性的。 */
static inline NSString *AACButtonEvidenceLine(UIControl *control,AACButtonSignalKind signal,NSString *keyword,NSString *blacklist,double green,BOOL red,BOOL leftPrimary,NSUInteger siblings,BOOL tappable){
 NSString *className=NSStringFromClass(object_getClass(control));
 return [NSString stringWithFormat:@"  BUTTON_CANDIDATE class=%@ id=%@ label=%@ value=%@ title=%@ frame=%@ tint=%@ bg=%@ green=%.2f redDominant=%@ leftPrimary=%@ siblingControls=%lu signal=%@ matched=%@ blacklisted=%@ tappable=%@",
   className,
   AACButtonShort(control.accessibilityIdentifier),
   AACButtonShort(control.accessibilityLabel),
   AACButtonShort([control accessibilityValue]),
   AACButtonShort(AACButtonTitleOf(control)),
   AACButtonFrameText(control.frame),
   AACButtonColorText(control.tintColor),
   AACButtonColorText(control.backgroundColor),
   green,red?@"yes":@"no",leftPrimary?@"yes":@"no",(unsigned long)siblings,
   AACButtonSignalText(signal),keyword?:@"-",blacklist?:@"no",tappable?@"yes":@"no"];
}
/* 评估一个 UIControl 的信号并生成候选记录；没有命中任何信号时返回 nil（不记为候选）。 */
static NSDictionary *AACButtonCandidateRecord(UIControl *control){
 NSString *identifier=control.accessibilityIdentifier;
 NSString *label=control.accessibilityLabel;
 NSString *value=[control accessibilityValue];
 NSString *title=AACButtonTitleOf(control);
 AACButtonSignalKind signal=AACButtonSignalNone;
 NSString *keyword=nil;
 NSString *hit=AACButtonMatchedAcceptKeyword(identifier);
 if(hit){signal=AACButtonSignalAccessibilityIdentifier;keyword=[NSString stringWithFormat:@"identifier:%@",hit];}
 if(signal==AACButtonSignalNone){
  hit=AACButtonMatchedAcceptKeyword(label);
  if(hit){signal=AACButtonSignalAccessibilityLabel;keyword=[NSString stringWithFormat:@"label:%@",hit];}
 }
 if(signal==AACButtonSignalNone){
  hit=AACButtonMatchedAcceptKeyword(value);
  if(hit){signal=AACButtonSignalAccessibilityValue;keyword=[NSString stringWithFormat:@"value:%@",hit];}
 }
 if(signal==AACButtonSignalNone){
  hit=AACButtonMatchedAcceptKeyword(title);
  if(hit){signal=AACButtonSignalTitle;keyword=[NSString stringWithFormat:@"title:%@",hit];}
 }
 if(signal==AACButtonSignalNone){
  hit=AACButtonMatchedLocalizationKeyword(title)||AACButtonMatchedLocalizationKeyword(label)?(AACButtonMatchedLocalizationKeyword(title)?:[NSString stringWithFormat:@"label:%@",AACButtonMatchedLocalizationKeyword(label)]):nil;
  if(hit){signal=AACButtonSignalLocalization;keyword=[NSString stringWithFormat:@"localisation:%@",hit];}
 }
 double green=AACButtonGreenScore(control);
 BOOL red=AACButtonIsRedDominant(control);
 BOOL leftPrimary=AACButtonIsLeftPrimary(control);
 NSUInteger siblings=AACButtonSiblingControlCount(control);
 if(signal==AACButtonSignalNone&&green>=AACButtonGreenThreshold&&leftPrimary&&siblings>=2){
  /* 最弱信号：两按钮来电布局里靠左的、绿色主导的主按钮。只有当它同时满足绿色、左侧、同一个
     父控件下至少有两个控件时才成立，绝不把它当成唯一依据去点一个随机按钮。 */
  signal=AACButtonSignalGreenPrimary;keyword=[NSString stringWithFormat:@"green=%.2f leftPrimary=yes siblings=%lu",green,(unsigned long)siblings];
 }
 NSString *blacklist=AACButtonBlacklistKeyword(control);
 if(!blacklist&&red)blacklist=@"红色主导颜色（可能是拒接/挂断按钮）";
 BOOL tappable=AACButtonIsTappable(control);
 if(signal==AACButtonSignalNone&&!blacklist)return nil;
 return @{@"control":control,@"className":NSStringFromClass(object_getClass(control)),@"signal":@(signal),@"keyword":keyword?:@"-",
          @"blacklist":blacklist?:@"",@"green":@(green),@"red":@(red),@"leftPrimary":@(leftPrimary),@"siblings":@(siblings),
          @"tappable":@(tappable),@"frameRect":[NSValue valueWithCGRect:control.frame],
          @"line":AACButtonEvidenceLine(control,signal,keyword,blacklist,green,red,leftPrimary,siblings,tappable)};
}
static void AACButtonConsiderControl(id object,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited){
 if(![object isKindOfClass:UIControl.class])return;
 *visited+=1;
 if(*visited>=AACButtonNodeCap)return;
 NSNumber *boxed=@((unsigned long)(uintptr_t)object);
 if([seen containsObject:boxed])return;
 [seen addObject:boxed];
 if(candidates.count>=AACButtonCandidateCap)return;
 NSDictionary *record=AACButtonCandidateRecord((UIControl *)object);
 if(record)[candidates addObject:record];
}
static BOOL AACButtonBudgetUsed(CFAbsoluteTime started){return (CFAbsoluteTimeGetCurrent()-started)>AACButtonScanBudgetSeconds;}
static void AACButtonVisitResponder(id object,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited,CFAbsoluteTime started,BOOL *exceeded){
 if(*exceeded)return;
 id next=object;
 for(NSUInteger up=0;up<AACButtonResponderUpCap&&next&&!*exceeded;up++){
  if(![next isKindOfClass:UIResponder.class])break;
  AACButtonConsiderControl(next,candidates,seen,visited);
  if(AACButtonBudgetUsed(started)){*exceeded=YES;return;}
  next=[(UIResponder *)next nextResponder];
 }
}
static void AACButtonVisitViewController(UIViewController *controller,NSUInteger depth,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited,CFAbsoluteTime started,BOOL *exceeded);
static void AACButtonVisitView(UIView *view,NSUInteger depth,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited,CFAbsoluteTime started,BOOL *exceeded);
static void AACButtonVisitViewController(UIViewController *controller,NSUInteger depth,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited,CFAbsoluteTime started,BOOL *exceeded){
 if(!controller||*exceeded||depth>AACButtonDepthCap||*visited>=AACButtonNodeCap)return;
 *visited+=1;
 if(AACButtonBudgetUsed(started)){*exceeded=YES;return;}
 @try{
  AACButtonVisitResponder(controller,candidates,seen,visited,started,exceeded);
  if(*exceeded)return;
  if(controller.presentedViewController)AACButtonVisitViewController(controller.presentedViewController,depth+1,candidates,seen,visited,started,exceeded);
  for(UIViewController *child in controller.childViewControllers)AACButtonVisitViewController(child,depth+1,candidates,seen,visited,started,exceeded);
  if(*exceeded)return;
  if(controller.view)AACButtonVisitView(controller.view,depth+1,candidates,seen,visited,started,exceeded);
 }@catch(NSException *e){}
}
static void AACButtonVisitView(UIView *view,NSUInteger depth,NSMutableArray *candidates,NSMutableSet *seen,NSUInteger *visited,CFAbsoluteTime started,BOOL *exceeded){
 if(!view||*exceeded||depth>AACButtonDepthCap||*visited>=AACButtonNodeCap)return;
 *visited+=1;
 if(AACButtonBudgetUsed(started)){*exceeded=YES;return;}
 @try{
  AACButtonConsiderControl(view,candidates,seen,visited);
  AACButtonVisitResponder(view,candidates,seen,visited,started,exceeded);
  if(*exceeded)return;
  for(UIView *subview in view.subviews){
   AACButtonVisitView(subview,depth+1,candidates,seen,visited,started,exceeded);
   if(*exceeded)return;
  }
 }@catch(NSException *e){}
}
/* 真正遍历：窗口场景 → 每个窗口的响应者链 / 根视图控制器 / 视图树。 */
static NSArray *AACButtonCollect(NSUInteger *visited,BOOL *exceeded){
 NSMutableArray *candidates=[NSMutableArray new];
 NSMutableSet *seen=[NSMutableSet new];
 *visited=0;*exceeded=NO;
 CFAbsoluteTime started=CFAbsoluteTimeGetCurrent();
 @try{
  NSMutableArray *windows=[NSMutableArray new];
  UIApplication *application=UIApplication.sharedApplication;
  /* 只用 scene API：UIApplication.windows 自 iOS 15 起弃用，本项目不使用弃用访问器。 */
  for(UIScene *scene in application.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])[windows addObjectsFromArray:((UIWindowScene *)scene).windows];
  for(UIWindow *window in windows){
   if(*exceeded)break;
   AACButtonVisitResponder(window,candidates,seen,visited,started,exceeded);
   if(!*exceeded&&window.rootViewController)AACButtonVisitViewController(window.rootViewController,0,candidates,seen,visited,started,exceeded);
   if(!*exceeded)AACButtonVisitView(window,0,candidates,seen,visited,started,exceeded);
  }
 }@catch(NSException *e){AACButtonLogLine([@"button hierarchy scan exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 return candidates;
}
/* 选一个候选：先按信号优先级（数字小者强），再按绿色分数高者，再按更靠左/更靠上。
   黑名单与不可点击的候选直接排除。 */
static NSDictionary *AACButtonSelectCandidate(NSArray *candidates){
 NSDictionary *best=nil;
 @try{
  for(NSDictionary *candidate in candidates){
   if([candidate[@"blacklist"] length])continue;
   if(![candidate[@"tappable"] boolValue])continue;
   NSInteger signal=[candidate[@"signal"] integerValue];
   if(signal==AACButtonSignalNone)continue;
   if(!best){best=candidate;continue;}
   NSInteger bestSignal=[best[@"signal"] integerValue];
   if(signal<bestSignal){best=candidate;continue;}
   if(signal>bestSignal)continue;
   double green=[candidate[@"green"] doubleValue],bestGreen=[best[@"green"] doubleValue];
   if(green>bestGreen+0.001){best=candidate;continue;}
   if(green<bestGreen-0.001)continue;
   CGRect frame=[candidate[@"frameRect"] CGRectValue],bestFrame=[best[@"frameRect"] CGRectValue];
   if(frame.origin.x<bestFrame.origin.x-0.5){best=candidate;continue;}
   if(frame.origin.x>bestFrame.origin.x+0.5)continue;
   if(frame.origin.y<bestFrame.origin.y-0.5)best=candidate;
  }
 }@catch(NSException *e){}
 return best;
}
/* 候选控件上真正注册的 target/action 对（机制 1/2 是否真的会触发动作、机制 3 要用它）。 */
static NSArray *AACButtonActionPairsForEvent(UIControl *control,UIControlEvents events){
 NSMutableArray *out=[NSMutableArray new];
 @try{
  for(id target in control.allTargets){
   NSArray *selectors=nil;
   @try{selectors=[control actionsForTarget:target forControlEvent:events];}@catch(NSException *e){selectors=nil;}
   for(NSString *name in selectors)if([name isKindOfClass:NSString.class]&&name.length)[out addObject:@{@"target":target,@"selector":name}];
  }
 }@catch(NSException *e){}
 return out;
}
/* 机制 3：用 allTargets + actionsForTarget:forControlEvent: 拿到 target/action 对，再用
   NSInvocation 以默认参数（对象/指针=nil、标量=0）直接调用。安全规则与 AACSpringBoard.h 的
   NSInvocation 候选完全相同：最多 3 个显式参数，参数类型必须能安全构造默认值。 */
static BOOL AACButtonInvocationArgumentSafe(const char *type,NSString **why){
 if(!type||!type[0]){if(why)*why=@"参数类型编码为空";return NO;}
 switch(type[0]){
  case '@':case '#':case ':':case '^':case '*':case '?':
  case 'c':case 'C':case 'B':case 'i':case 'I':case 's':case 'S':case 'l':case 'L':case 'q':case 'Q':
  case 'f':case 'd':
   return YES;
  default:
   if(why)*why=[NSString stringWithFormat:@"参数类型 %s 的默认值无法安全构造（结构体/联合体/C++ 类型等）",type];
   return NO;
 }
}
static BOOL AACButtonInvokeActionPair(NSDictionary *pair,NSString **why){
 id target=pair[@"target"];NSString *name=pair[@"selector"];
 if(!target||![name isKindOfClass:NSString.class]||!name.length){if(why)*why=@"target/selector 对不完整";return NO;}
 SEL selector=NSSelectorFromString(name);
 if(!selector){if(why)*why=[NSString stringWithFormat:@"选择器 %@ 无法解析",name];return NO;}
 Method method=class_getInstanceMethod(object_getClass(target),selector);
 if(!method){if(why)*why=[NSString stringWithFormat:@"target 上不存在 -%@",name];return NO;}
 unsigned int arguments=method_getNumberOfArguments(method);
 if(arguments<2){if(why)*why=@"类型编码异常（参数数量小于 2）";return NO;}
 if(arguments-2>AACButtonTapArgumentCap){if(why)*why=[NSString stringWithFormat:@"显式参数数量=%u 超过可安全构造默认值的上限 %d",arguments-2,AACButtonTapArgumentCap];return NO;}
 const char *types=method_getTypeEncoding(method);
 if(!types){if(why)*why=@"方法类型编码为空";return NO;}
 NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:types];
 if(!signature){if(why)*why=@"无法从类型编码构造 NSMethodSignature";return NO;}
 if(signature.numberOfArguments!=arguments){if(why)*why=@"NSMethodSignature 与方法参数数量不一致";return NO;}
 for(NSUInteger index=2;index<arguments;index++){
  NSString *reason=nil;
  if(!AACButtonInvocationArgumentSafe([signature getArgumentTypeAtIndex:index],&reason)){if(why)*why=reason;return NO;}
 }
 NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:signature];
 @try{
  [invocation setTarget:target];
  [invocation setSelector:selector];
  for(NSUInteger index=2;index<arguments;index++){
   const char *type=[signature getArgumentTypeAtIndex:index];
   if(!type)continue;
   switch(type[0]){
    case '@':case '#':case ':':case '^':case '*':{id value=nil;[invocation setArgument:&value atIndex:index];break;}
    case 'f':{float value=0;[invocation setArgument:&value atIndex:index];break;}
    case 'd':{double value=0;[invocation setArgument:&value atIndex:index];break;}
    default:{long long value=0;[invocation setArgument:&value atIndex:index];break;}
   }
  }
  [invocation invoke];
 }@catch(NSException *e){if(why)*why=[@"NSInvocation 调用抛出异常：" stringByAppendingString:e.reason?:@"unknown"];return NO;}
 if(why)*why=[NSString stringWithFormat:@"已用 NSInvocation 以默认参数调用 %@ 上的 -%@（参数是猜测的默认值，调用本身不等于已接通）",NSStringFromClass(object_getClass(target)),name];
 return YES;
}
/* 三种点击机制，按任务要求的顺序（1 安全 sendActions → 2 仅 TouchDown → 3 target/action
   + NSInvocation）。返回实际使用的机制的说明文本；返回 nil 表示没有任何可用的点击机制。 */
static NSString *AACButtonPerformTap(UIControl *control,NSString **detail){
 if(![control isKindOfClass:UIControl.class]){if(detail)*detail=@"目标不是 UIControl";return nil;}
 NSArray *pairsUp=AACButtonActionPairsForEvent(control,UIControlEventTouchUpInside);
 BOOL upSent=NO;
 if(pairsUp.count){
  @try{[control sendActionsForControlEvents:UIControlEventTouchUpInside];upSent=YES;}
  @catch(NSException *e){AACButtonLogLine([@"sendActions(TouchUpInside) 抛出异常：" stringByAppendingString:e.reason?:@"unknown"]);}
 }
 if(upSent){
  if(detail)*detail=[NSString stringWithFormat:@"控件确实为该事件注册了 %lu 个 target/action 对；真正的接听与否由 CXCallObserver 的 hasConnected 判定",(unsigned long)pairsUp.count];
  return @"(1) sendActionsForControlEvents:UIControlEventTouchUpInside";
 }
 /* 机制 1 没有任何 target/action 对 => 它实际上没有触发任何动作；继续机制 2。 */
 UIControlEvents combined=UIControlEventTouchUpInside|UIControlEventTouchDown;
 NSArray *pairsCombined=AACButtonActionPairsForEvent(control,combined);
 NSArray *pairsDown=AACButtonActionPairsForEvent(control,UIControlEventTouchDown);
 BOOL downSent=NO;
 if(pairsDown.count && !pairsUp.count){
  @try{[control sendActionsForControlEvents:UIControlEventTouchDown];downSent=YES;}
  @catch(NSException *e){AACButtonLogLine([@"sendActions(TouchDown) 抛出异常：" stringByAppendingString:e.reason?:@"unknown"]);}
 }
 if(downSent){
  if(detail)*detail=[NSString stringWithFormat:@"机制 1 没有注册任何 target/action，因此改用组合事件（%lu 个 target/action 对）",(unsigned long)pairsCombined.count];
  return @"(2) sendActionsForControlEvents:UIControlEventTouchDown";
 }
 NSArray *pairs=pairsCombined.count?pairsCombined:pairsUp;
 if(!pairs.count){
  if(detail)*detail=@"控件没有注册任何 target/action 对（allTargets+actionsForTarget 均为空），不能安全模拟点击";
  return nil;
 }
 NSUInteger invoked=0;NSString *lastReason=nil;
 for(NSDictionary *pair in pairs){
  NSString *why=nil;
  if(AACButtonInvokeActionPair(pair,&why))invoked++;
  else lastReason=why;
 }
 if(!invoked){
  if(detail)*detail=[NSString stringWithFormat:@"机制 3 没有任何 target/action 对可以被安全调用：%@",lastReason?:@"无说明"];
  return nil;
 }
 if(detail)*detail=[NSString stringWithFormat:@"机制 3 直接调用了 %lu 个 target/action 对（默认参数）；参数是猜测的默认值，调用本身不等于已接通",(unsigned long)invoked];
 return @"(3) allTargets + actionsForTarget:forControlEvent: → NSInvocation（默认参数）";
}

/* ======================= 报告 / 扫描 / 点击 API ========================================== */
static inline NSString *AACButtonConnectedText(void){
 if(AACButtonConnectedState<0)return @"未观察到（不能据此断言失败）";
 return AACButtonConnectedState?@"是（CXCallObserver 已报告 hasConnected）":@"否（该通话结束时仍未观察到连接）";
}
static inline NSString *AACButtonRuleText(void){
 return @"策略：活体按钮发现 + 模拟点击是主策略；方法名关键字发现（ACTION/ACCESSOR 分类）保留但已知不足，因为真正的接听按钮的响应走 UIControl 的 action 机制，方法名里通常不含 answer/accept";
}
static inline NSArray *AACButtonTapNames(void){
 NSMutableArray *out=[NSMutableArray new];
 for(NSString *tag in @[@"incall",@"springboard"])[out addObject:[AACButtonTapPrefix stringByAppendingString:tag]];
 return out;
}
static inline NSString *AACButtonTapName(NSString *tag){return [AACButtonTapPrefix stringByAppendingString:[tag isKindOfClass:NSString.class]&&tag.length?tag:@"unknown"];}
/* Each peer tap must be identified by both host and call UUID. A host-only notification
   can suppress answering for the NEXT incoming call for up to 90 seconds. */
static inline NSString *AACButtonTapNameForCall(NSString *tag,NSString *uuid){
 if(!tag.length||!uuid.length)return nil;
 return [NSString stringWithFormat:@"%@%@.%@",AACButtonTapPrefix,tag,uuid];
}
static inline NSString *AACButtonPeerKey(NSString *tag,NSString *uuid){
 return [NSString stringWithFormat:@"%@|%@",tag?:@"",uuid?:@""];
}
static inline void AACButtonNotePeerTap(NSString *tag,NSString *uuid){
 if(!tag.length||!uuid.length)return;
 if(!AACButtonTapSeen)AACButtonTapSeen=[NSMutableDictionary new];
 @try{AACButtonTapSeen[AACButtonPeerKey(tag,uuid)]=NSDate.date;}@catch(NSException *e){}
}
/* Peer evidence is eligible ONLY for the same call UUID. */
static inline NSString *AACButtonPeerTapped(NSArray *higherPriorityTags,NSString *uuid){
 if(!uuid.length)return nil;
 @try{
  for(NSString *tag in higherPriorityTags){
   NSDate *when=AACButtonTapSeen?AACButtonTapSeen[AACButtonPeerKey(tag,uuid)]:nil;
   if([when isKindOfClass:NSDate.class]&&-[when timeIntervalSinceNow]<=AACButtonTapFreshSeconds)return tag;
  }
 }@catch(NSException *e){}
 return nil;
}
static inline NSString *AACButtonPeerTapText(void){
 if(!AACButtonTapSeen.count)return @"（未观察到任何宿主的按钮点击通知）";
 NSMutableArray *parts=[NSMutableArray new];
 @try{for(NSString *tag in AACButtonTapSeen.allKeys)[parts addObject:[NSString stringWithFormat:@"%@:%@",tag,AACButtonTapSeen[tag]]];}@catch(NSException *e){}
 return [parts componentsJoinedByString:@" "];
}
/* 每个通话 UUID 只点击一次。 */
static inline BOOL AACButtonClaimTapUUID(NSString *uuid){
 if(![uuid isKindOfClass:NSString.class]||!uuid.length)return NO;
 if(!AACButtonTappedUUIDs)AACButtonTappedUUIDs=[NSMutableSet new];
 @try{
  if([AACButtonTappedUUIDs containsObject:uuid])return NO;
  [AACButtonTappedUUIDs addObject:uuid];
 }@catch(NSException *e){return NO;}
 return YES;
}
static inline BOOL AACButtonHasTappedUUID(NSString *uuid){return [uuid isKindOfClass:NSString.class]&&uuid.length&&AACButtonTappedUUIDs&&[AACButtonTappedUUIDs containsObject:uuid];}
/* An exception/no-action attempt must not permanently consume this UUID. */
static inline void AACButtonUnclaimTapUUID(NSString *uuid){
 if(uuid.length)@try{[AACButtonTappedUUIDs removeObject:uuid];}@catch(NSException *e){}
}
static inline void AACButtonForgetCall(NSString *uuid){
 if(!uuid.length)return;
 AACButtonUnclaimTapUUID(uuid);
 @try{
  for(NSString *tag in @[@"incall",@"springboard"])
   [AACButtonTapSeen removeObjectForKey:AACButtonPeerKey(tag,uuid)];
 }@catch(NSException *e){}
}
/* 一次扫描：遍历 + 打分 + 记录 EVERY 候选。返回非黑名单且可点击的候选数量。 */
static NSUInteger AACButtonScanReport(NSString *phase){
 if(__sync_add_and_fetch(&AACButtonScanning,1)>1){
  __sync_sub_and_fetch(&AACButtonScanning,1);
  AACButtonLogLine(@"button hierarchy scan re-entry refused (recursion guard)");
  return AACButtonLiveCandidateCount;
 }
 NSUInteger nodes=0;BOOL exceeded=NO;NSArray *candidates=@[];
 @try{candidates=AACButtonCollect(&nodes,&exceeded)?: @[];}@catch(NSException *e){AACButtonLogLine([@"button hierarchy scan exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 __sync_sub_and_fetch(&AACButtonScanning,1);
 @try{
  if(!AACButtonReportLines)AACButtonReportLines=[NSMutableArray new];
  [AACButtonReportLines removeAllObjects];
  AACButtonLastCandidates=[NSMutableArray arrayWithArray:candidates];
  AACButtonScanRuns++;AACButtonNodesVisited=nodes;AACButtonBudgetExceeded=exceeded;AACButtonCandidatesFound=candidates.count;
  NSUInteger blacklisted=0,live=0;
  for(NSDictionary *candidate in candidates){
   if([candidate[@"blacklist"] length])blacklisted++;
   else if([candidate[@"tappable"] boolValue]&&[candidate[@"signal"] integerValue]!=AACButtonSignalNone)live++;
  }
  AACButtonBlacklistedFound=blacklisted;AACButtonLiveCandidateCount=live;
  NSMutableArray *lines=[NSMutableArray new];
  [lines addObject:[NSString stringWithFormat:@"# BUTTON_SCAN phase=%@ run=%lu nodesVisited=%lu candidates=%lu blacklisted=%lu live=%lu nodeCap=%d depthCap=%d budgetSeconds=%.1f budgetExceeded=%@",phase?:@"scan",(unsigned long)AACButtonScanRuns,(unsigned long)nodes,(unsigned long)candidates.count,(unsigned long)blacklisted,(unsigned long)live,AACButtonNodeCap,AACButtonDepthCap,AACButtonScanBudgetSeconds,exceeded?@"yes":@"no"]];
  if(!candidates.count)[lines addObject:@"  BUTTON_CANDIDATE (none) 活体层级里没有找到任何看起来像接听控件的 UIControl（没有候选就没有可点的东西）"];
  for(NSDictionary *candidate in candidates)[lines addObject:candidate[@"line"]];
  [lines addObject:[NSString stringWithFormat:@"# BUTTON_SCAN_END phase=%@ candidates=%lu blacklisted=%lu live=%lu",phase?:@"scan",(unsigned long)candidates.count,(unsigned long)blacklisted,(unsigned long)live]];
  if(!AACButtonScanHistory)AACButtonScanHistory=[NSMutableArray new];
  if(AACButtonScanHistory.count>=AACButtonScanRunCap)[AACButtonScanHistory removeObjectAtIndex:0];
  [AACButtonScanHistory addObject:[NSString stringWithFormat:@"scan run=%lu phase=%@ nodes=%lu candidates=%lu blacklisted=%lu live=%lu budgetExceeded=%@",(unsigned long)AACButtonScanRuns,phase?:@"scan",(unsigned long)nodes,(unsigned long)candidates.count,(unsigned long)blacklisted,(unsigned long)live,exceeded?@"yes":@"no"]];
  for(NSString *line in lines)AACButtonReportAdd(line);
  for(NSString *line in lines)AACButtonLogLine(line);
  AACButtonLogLine([NSString stringWithFormat:@"button discovery summary: %@；%@",AACButtonSummaryText(),AACButtonRuleText()]);
  return live;
 }@catch(NSException *e){
  AACButtonLogLine([@"button discovery report exception: " stringByAppendingString:e.reason?:@"unknown"]);
  return 0;
 }
}
/* 点击：先做让出判定（更高优先级宿主是否真的点过），再现场重新扫描并选定控件，然后按 1→2→3
   的顺序尝试点击机制。每个通话 UUID 只点一次。返回所用机制的说明文本；返回 nil 时 *why 写原因。 */
static NSString *AACButtonTryTap(NSString *uuid,NSString *tag,NSArray *higherPriorityTags,NSString **why){
 if(![uuid isKindOfClass:NSString.class]||!uuid.length){if(why)*why=@"通话 UUID 不可用：不点击";return nil;}
 NSString *peer=AACButtonPeerTapped(higherPriorityTags,uuid);
 if(peer){
  if(why)*why=[NSString stringWithFormat:@"已观察到更高优先级宿主 %@ 真的点击过接听按钮（窗口 %.0f 秒内）：本宿主让出，绝不双重点击",peer,AACButtonTapFreshSeconds];
  return nil;
 }
 NSUInteger live=AACButtonScanReport(@"tap");
 if(!live){if(why)*why=@"现场重扫没有找到任何非黑名单且可点击的候选控件";return nil;}
 NSDictionary *chosen=nil;
 @try{chosen=AACButtonSelectCandidate(AACButtonLastCandidates);}@catch(NSException *e){chosen=nil;}
 if(!chosen){if(why)*why=@"候选里没有任何一个可以通过黑名单/可点击闸门";return nil;}
 UIControl *control=chosen[@"control"];
 NSString *blacklist=AACButtonBlacklistKeyword(control);
 if(!blacklist&&[chosen[@"blacklist"] length])blacklist=chosen[@"blacklist"];
 if(blacklist){if(why)*why=[NSString stringWithFormat:@"所选控件命中拒绝/挂断黑名单（%@）：绝不点击",blacklist];return nil;}
 if(!AACButtonIsTappable(control)){if(why)*why=@"所选控件不可点击（禁用/隐藏/透明/无窗口）";return nil;}
 if(!AACButtonClaimTapUUID(uuid)){if(why)*why=@"该通话 UUID 已经由本宿主点击过一次（每个 UUID 只点一次）";return nil;}
 NSString *detail=nil;
 NSString *mechanism=AACButtonPerformTap(control,&detail);
 if(!mechanism){AACButtonUnclaimTapUUID(uuid);if(why)*why=detail?:@"没有任何可用的点击机制";return nil;}
 @try{
  AACButtonChosenText=[NSString stringWithFormat:@"class=%@ id=%@ label=%@ title=%@ frame=%@ signal=%@ matched=%@ green=%.2f blacklisted=no tappable=yes",
    NSStringFromClass(object_getClass(control)),AACButtonShort(control.accessibilityIdentifier),AACButtonShort(control.accessibilityLabel),AACButtonShort(AACButtonTitleOf(control)),
    AACButtonFrameText(control.frame),AACButtonSignalText((AACButtonSignalKind)[chosen[@"signal"] integerValue]),chosen[@"keyword"], [chosen[@"green"] doubleValue]];
  AACButtonMechanismText=mechanism;AACButtonTapUUID=uuid;AACButtonTapCount++;
  AACButtonLastChosenControl=control;
  AACButtonReportAdd([NSString stringWithFormat:@"# BUTTON_CHOSEN %@",AACButtonChosenText]);
  AACButtonReportAdd([NSString stringWithFormat:@"# BUTTON_TAP uuid=%@ host=%@ mechanism=%@ detail=%@ tapCount=%lu",uuid,tag?:@"unknown",mechanism,detail?:@"-",(unsigned long)AACButtonTapCount]);
  AACButtonReportAdd([NSString stringWithFormat:@"# BUTTON_CONNECTED uuid=%@ connected=%@（点击机制成功只表示事件被发出，接通必须由 CXCallObserver 的 hasConnected 确认）",uuid,AACButtonConnectedText()]);
  AACButtonLogLine([NSString stringWithFormat:@"button tap performed: uuid=%@ host=%@ chosen=[%@] mechanism=%@ detail=%@",uuid,tag?:@"unknown",AACButtonChosenText?:@"-",mechanism,detail?:@"-"]);
  if(tag.length){
   uint32_t posted=notify_post(AACButtonTapNameForCall(tag,uuid).UTF8String);
   AACButtonLogLine([NSString stringWithFormat:@"buttontap 通知已广播：name=%@ post=%u（只会断言到达；它让更低优先级宿主让出，避免双重点击）",AACButtonTapNameForCall(tag,uuid),posted]);
  }
 }@catch(NSException *e){AACButtonLogLine([@"button tap reporting exception: " stringByAppendingString:e.reason?:@"unknown"]);}
 if(why)*why=detail?:@"已点击";
 return mechanism;
}
static inline void AACButtonNoteConnected(BOOL connected){
 AACButtonConnectedState=connected?1:0;
 @try{for(NSString *line in @[[NSString stringWithFormat:@"# BUTTON_CONNECTED_OBSERVED connected=%@ uuid=%@",connected?@"yes":@"no",AACButtonTapUUID?:@"-"]])AACButtonReportAdd(line);}@catch(NSException *e){}
 AACButtonLogLine([NSString stringWithFormat:@"button path connection observation: uuid=%@ connected=%@ tapCount=%lu mechanism=%@",AACButtonTapUUID?:@"-",connected?@"yes":@"no",(unsigned long)AACButtonTapCount,AACButtonMechanismText?:@"-"]);
}
/* 通话结束时调用：清掉「活体候选」计数（否则过期的候选会让下一次通话误判为有按钮路径），
   并把该通话最终是否接通写进报告。 */
static inline void AACButtonNoteCallEnded(BOOL connected){
 AACButtonNoteConnected(connected);
 AACButtonLiveCandidateCount=0;
 @try{[AACButtonLastCandidates removeAllObjects];}@catch(NSException *e){}
}
static inline NSString *AACButtonSummaryText(void){
 return [NSString stringWithFormat:@"按钮发现：扫描=%lu 次，访问节点=%lu，候选=%lu（黑名单=%lu，可点击活体=%lu），所选=%@，机制=%@，点击次数=%lu，接通=%@",
   (unsigned long)AACButtonScanRuns,(unsigned long)AACButtonNodesVisited,(unsigned long)AACButtonCandidatesFound,(unsigned long)AACButtonBlacklistedFound,(unsigned long)AACButtonLiveCandidateCount,
   AACButtonChosenText?:@"（还没有选定任何控件）",AACButtonMechanismText?:@"（还没有使用任何点击机制）",(unsigned long)AACButtonTapCount,AACButtonConnectedText()];
}
static inline NSString *AACButtonReportText(void){
 NSMutableArray *lines=[NSMutableArray new];
 [lines addObject:@"# ===== BUTTON 候选（1.17.1 活体层级发现 + 模拟点击；与同文件里 ACTION/ACCESSOR 方法分类相互独立） ====="];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_RULE %@",AACButtonRuleText()]];
 [lines addObject:@"# BUTTON_SIGNAL_PRIORITY accessibilityIdentifier > accessibilityLabel > accessibilityValue > titleLabel.text/currentTitle > knownLocalisationSubstring > greenLeftPrimary(弱信号：绿色主导且是同父控件里靠左的主按钮，且同父至少两个控件)"];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_BLACKLIST %@（黑名单作用于 accessibilityIdentifier / accessibilityLabel / accessibilityValue / 按钮标题，并且颜色为红色主导的控件一律列入；黑名单候选只记录，绝不点击）",[AACButtonForbiddenKeywords() componentsJoinedByString:@","]]];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_BOUNDS nodeCap=%d depthCap=%d budgetSeconds=%.1f responderUpCap=%d candidateCap=%d tapArgumentCap=%d settleSeconds=%.1f",AACButtonNodeCap,AACButtonDepthCap,AACButtonScanBudgetSeconds,AACButtonResponderUpCap,AACButtonCandidateCap,AACButtonTapArgumentCap,AACButtonOwnerSettleSeconds]];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_TOTAL %@",AACButtonSummaryText()]];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_BUDGET exceeded=%@（时间预算 %.1f 秒；超限即安全停止，未处理的部分不在本报告内）",AACButtonBudgetExceeded?@"yes":@"no",AACButtonScanBudgetSeconds]];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_LAST_CHOSEN %@",AACButtonLastChosenControl?[NSString stringWithFormat:@"-%@（弱引用，可能已被释放）",NSStringFromClass(object_getClass(AACButtonLastChosenControl))]:@"(none)"]];
 [lines addObject:[NSString stringWithFormat:@"# BUTTON_PEER_TAPS %@",AACButtonPeerTapText()]];
 @try{for(NSString *line in AACButtonScanHistory)[lines addObject:[@"# BUTTON_SCAN_HISTORY " stringByAppendingString:line]];}@catch(NSException *e){}
 @try{
  if(AACButtonReportLines.count)for(NSString *line in AACButtonReportLines)[lines addObject:line];
  else [lines addObject:@"  BUTTON_SCAN (none) 本次进程还没有运行过按钮扫描"];
 }@catch(NSException *e){}
 [lines addObject:@"# ===== end BUTTON 候选 ====="];
 return [lines componentsJoinedByString:@"\n"];
}
