#import <UIKit/UIKit.h>
#import "CABattleRuntime.h"
#import "CAEventLog.h"
#import "CAObserve.h"

static NSString * const CAPrefs = @"ClashAssist.settings.v2";
@interface CALabWindow : UIWindow
@end
@implementation CALabWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self || v == self.rootViewController.view ? nil : v;
}
@end

@interface CALabController : UIViewController
@property(nonatomic,strong) CALabWindow *overlay;
@property(nonatomic,weak) UIWindow *previousKey;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic,strong) NSMutableDictionary<NSString *,UITextField *> *fields;
@property(nonatomic,strong) UIButton *startButton;
@property(nonatomic,strong) UIButton *saveButton;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSURL *exportURL;
@property(nonatomic,copy) NSString *lastRuntimeStatus;
@property(nonatomic,assign) CGPoint dragOrigin;
@property(nonatomic,assign) BOOL dragging;
- (void)attach;
@end

@implementation CALabController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }
- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *v = [UILabel new]; v.text = text; v.numberOfLines = 0;
    v.font = [UIFont systemFontOfSize:size]; v.textColor = UIColor.whiteColor; return v;
}
- (UIButton *)button:(NSString *)title action:(SEL)action color:(UIColor *)color {
    UIButton *v = [UIButton buttonWithType:UIButtonTypeSystem];
    [v setTitle:title forState:UIControlStateNormal]; [v setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    v.backgroundColor = color; v.layer.cornerRadius = 9; v.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [v.heightAnchor constraintEqualToConstant:40].active = YES;
    [v addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return v;
}
- (void)loadView { self.view = [UIView new]; self.view.backgroundColor = UIColor.clearColor; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.events = [NSMutableArray new]; self.fields = [NSMutableDictionary new];
    self.bubble = [self button:@"实验" action:@selector(toggle) color:UIColor.systemBlueColor];
    self.bubble.frame = CGRectMake(24,64,54,54); self.bubble.layer.cornerRadius = 27;
    // This button is manually positioned; do not retain the generic height constraint.
    for (NSLayoutConstraint *c in self.bubble.constraints.copy) if (c.firstAttribute == NSLayoutAttributeHeight) c.active = NO;
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self.bubble addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    self.bubble.accessibilityLabel = @"战斗诊断，点击面板，长按停止";
    [self.view addSubview:self.bubble];
    self.panel = [UIView new]; self.panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.97];
    self.panel.layer.cornerRadius = 14; self.panel.clipsToBounds = YES; self.panel.hidden = YES;
    self.panel.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.panel];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *width = [self.panel.widthAnchor constraintEqualToConstant:660]; width.priority = 750;
    NSLayoutConstraint *height = [self.panel.heightAnchor constraintEqualToConstant:440]; height.priority = 750;
    [NSLayoutConstraint activateConstraints:@[width,height,
        [self.panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [self.panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:8],
        [self.panel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-8],
        [self.panel.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:8],
        [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-8]]];
    UIStackView *root = [UIStackView new]; root.axis = UILayoutConstraintAxisVertical; root.spacing = 7;
    root.translatesAutoresizingMaskIntoConstraints = NO; [self.panel addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:12],
        [root.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-12],
        [root.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:10],
        [root.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-10]]];
    UILabel *heading = [self label:@"ClashAssist 0.4.0 · 战斗调度与诊断" size:16];
    UIButton *close = [self button:@"收起" action:@selector(toggle) color:UIColor.darkGrayColor];
    [close.widthAnchor constraintEqualToConstant:66].active = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[heading,close]]; header.spacing = 8;
    [root addArrangedSubview:header];
    self.status = [self label:@"就绪 · 真实自动战斗后端未接入" size:12];
    self.status.textColor = UIColor.systemYellowColor; [root addArrangedSubview:self.status];
    self.scroll = [UIScrollView new]; self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.scroll.alwaysBounceVertical = YES; [root addArrangedSubview:self.scroll];
    UIStackView *content = [UIStackView new]; content.axis = UILayoutConstraintAxisVertical; content.spacing = 8;
    content.translatesAutoresizingMaskIntoConstraints = NO; [self.scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]]];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:CAPrefs];
    NSArray *rows = @[@[@"gold",@"最低金币",@500000],@[@"elixir",@"最低圣水",@500000],
        @[@"dark",@"最低黑水",@0],@[@"maxSearch",@"总搜索上限",@50],
        @[@"maxUnits",@"单场最多部署单位",@100],@[@"timeout",@"主动结束战斗秒数（1–1800）",@180]];
    for (NSArray *row in rows) {
        UILabel *label = [self label:row[1] size:14];
        UITextField *field = [UITextField new]; field.borderStyle = UITextBorderStyleRoundedRect;
        field.keyboardType = UIKeyboardTypeASCIICapableNumberPad;
        field.textColor = UIColor.blackColor; field.backgroundColor = UIColor.whiteColor;
        id value = saved[row[0]]; field.text = [([value isKindOfClass:NSNumber.class] ? value : row[2]) stringValue];
        field.accessibilityLabel = row[1]; self.fields[row[0]] = field;
        [field.widthAnchor constraintEqualToConstant:135].active = YES;
        [field.heightAnchor constraintEqualToConstant:34].active = YES;
        UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[label,field]]; line.spacing = 8;
        [content addArrangedSubview:line];
    }
    [content addArrangedSubview:[self label:@"真实接口由已验证后端提供。未注册后端时启动会报错；一次启动只处理一场战斗，结算后停止。长按悬浮按钮可停止后续指令。" size:12]];
    [content addArrangedSubview:[self button:@"观测调用 300 秒" action:@selector(observe) color:UIColor.systemOrangeColor]];
    [content addArrangedSubview:[self button:@"复制详细调用诊断 JSON" action:@selector(copyObservation) color:UIColor.darkGrayColor]];
    [content addArrangedSubview:[self label:@"最多保留最近 8192 条记录：入口/返回配对、相对时间、调用耗时、线程 ID、嵌套深度、调用点模块偏移，以及前一至两个参数机器字的十六进制值（可能是指针，不解引用）。分享报告前请注意地址信息。以下人工标记按钮会记录标记并自动收起面板。" size:12]];
    [content addArrangedSubview:[self button:@"标记：即将搜索对手" action:@selector(markSearchBefore) color:UIColor.systemIndigoColor]];
    [content addArrangedSubview:[self button:@"标记：搜索结果/战场已显示" action:@selector(markSearchResult) color:UIColor.systemIndigoColor]];
    [content addArrangedSubview:[self button:@"标记：即将选择/部署兵力" action:@selector(markDeployBefore) color:UIColor.systemPurpleColor]];
    [content addArrangedSubview:[self button:@"标记：已观察到部署结果" action:@selector(markDeployObserved) color:UIColor.systemPurpleColor]];
    [content addArrangedSubview:[self button:@"标记：即将手动结束战斗" action:@selector(markEndBefore) color:UIColor.systemOrangeColor]];
    [content addArrangedSubview:[self button:@"标记：结算界面已显示" action:@selector(markSettlement) color:UIColor.systemOrangeColor]];
    [content addArrangedSubview:[self button:@"标记：下一轮/新对手已显示" action:@selector(markNextRound) color:UIColor.systemGreenColor]];
    [content addArrangedSubview:[self button:@"导出完整诊断 JSON 文件" action:@selector(exportReport) color:UIColor.systemBlueColor]];
    self.logView = [UITextView new]; self.logView.editable = NO; self.logView.scrollEnabled = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1]; self.logView.textColor = UIColor.whiteColor;
    [self.logView.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [content addArrangedSubview:self.logView];
    self.saveButton = [self button:@"保存配置" action:@selector(save) color:UIColor.systemBlueColor];
    self.startButton = [self button:@"开始自动战斗" action:@selector(start) color:UIColor.systemGreenColor];
    UIButton *stop = [self button:@"立即停止" action:@selector(manualStop) color:UIColor.systemRedColor];
    UIButton *copy = [self button:@"复制日志" action:@selector(copyLog) color:UIColor.darkGrayColor];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.saveButton,self.startButton,stop,copy]];
    actions.distribution = UIStackViewDistributionFillEqually; actions.spacing = 6; [root addArrangedSubview:actions];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [self record:@"就绪：模拟代码已移除；等待注册已验证的真实游戏后端"];
    __weak CALabController *weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        CALabController *owner=weakSelf;
        if (!owner) { [timer invalidate]; return; }
        [owner setRunningControls:[CABattleRuntime.shared running]];
        [owner updateStatus];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (BOOL)running { return CABattleRuntime.shared.running; }
- (void)record:(NSString *)text {
    CAEvent(@"ui.message",@{@"message":text});
    [self.events addObject:[NSString stringWithFormat:@"[%.3f] %@",NSProcessInfo.processInfo.systemUptime,text]];
    if (self.events.count > 80) [self.events removeObjectAtIndex:0];
    self.logView.text = [self.events componentsJoinedByString:@"\n"];
}
- (BOOL)readConfig:(CABattleConfig *)out {
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (NSString *key in self.fields) {
        NSString *text = self.fields[key].text ?: @"";
        if (!text.length || text.length > 9 || [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) {
            self.status.text = @"配置错误：请输入 0–999999999 的整数"; return NO;
        }
        uint32_t n = (uint32_t)text.longLongValue;
        if ([@[@"maxSearch",@"maxUnits",@"timeout"] containsObject:key] && (n<1 || n>10000)) {
            self.status.text = @"次数和超时必须在 1–10000 之间"; return NO;
        }
        values[key] = @(n);
    }
    if ([values[@"timeout"] unsignedIntValue]>1800) { self.status.text=@"战斗秒数必须为 1–1800"; return NO; }
    *out = (CABattleConfig){.minGold=[values[@"gold"] unsignedLongLongValue], .minElixir=[values[@"elixir"] unsignedLongLongValue],
        .minDark=[values[@"dark"] unsignedLongLongValue], .maxSearch=[values[@"maxSearch"] unsignedIntValue],
        .maxUnits=[values[@"maxUnits"] unsignedIntValue], .actionTimeout=20, .battleTimeout=[values[@"timeout"] doubleValue]};
    [NSUserDefaults.standardUserDefaults setObject:values forKey:CAPrefs];
    [self.view endEditing:YES]; return YES;
}
- (void)save { CABattleConfig c; if ([self readConfig:&c]) self.status.text = @"配置已保存"; }
- (void)setRunningControls:(BOOL)running {
    self.startButton.enabled = !running; self.saveButton.enabled = !running;
    self.startButton.alpha = running ? 0.5 : 1; self.saveButton.alpha = running ? 0.5 : 1;
    for (UITextField *f in self.fields.allValues) f.enabled = !running;
    [self.bubble setTitle:running ? @"运行" : @"诊断" forState:UIControlStateNormal];
}
- (void)start {
    if ([self running]) return;
    CABattleConfig config; if (![self readConfig:&config]) return;
    NSError *error=nil;
    if (![CABattleRuntime.shared start:config error:&error]) {
        self.status.text=error.localizedDescription ?: @"启动失败"; [self record:self.status.text];
        return;
    }
    self.panel.hidden=YES; [self restoreKey];
    [self record:@"真实战斗调度已启动；所有动作等待游戏状态确认"];
    [self setRunningControls:YES]; [self updateStatus];
}
- (void)updateStatus {
    NSString *text=CABattleRuntime.shared.statusText;
    if (![text isEqual:self.lastRuntimeStatus]) {
        self.lastRuntimeStatus=text; self.status.text=text;
        [self record:text];
    }
}
- (void)stop:(NSString *)reason {
    [CABattleRuntime.shared stop:reason];
    CAObserveStopWithReason([reason isEqualToString:@"background"] ? CAObserveStopBackground : CAObserveStopManual);
    [self setRunningControls:NO]; [self.view endEditing:YES];
    [self record:[NSString stringWithFormat:@"停止后续指令：%@",reason]];
    self.status.text=CABattleRuntime.shared.statusText;
}
- (NSDictionary *)completeReport {
    CAEvent(@"report.export",@{});
    return @{@"schemaVersion":@1,@"pluginVersion":@"0.4.0",@"observation":CAObserveSnapshot(),
        @"runtime":[CABattleRuntime.shared snapshot],@"journal":CAEventSnapshot()};
}
- (void)exportReport {
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:[self completeReport] options:NSJSONWritingPrettyPrinted error:&error];
    NSString *name=[NSString stringWithFormat:@"ClashAssist-%@.json",NSUUID.UUID.UUIDString];
    NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        self.status.text=[NSString stringWithFormat:@"导出失败：%@",error.localizedDescription ?: @"JSON 编码失败"]; return;
    }
    self.exportURL=url;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.panel;
    share.popoverPresentationController.sourceRect=self.panel.bounds;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)observe {
    [self stop:@"manual"];
    NSString *error=nil;
    if(CAObserveStart(&error)) {
        self.status.text=@"调用观测中（300 秒）· 手动操作后导出完整报告";
        [self record:@"已开启候选调用观测"];
    } else { self.status.text=error?:@"观测启动失败"; [self record:self.status.text]; }
}
- (void)copyObservation {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self completeReport] options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || error) {
        self.status.text = [NSString stringWithFormat:@"生成诊断 JSON 失败：%@", error.localizedDescription ?: @"未知错误"];
        return;
    }
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.status.text = @"详细诊断 JSON 已复制；请同时说明每个人工标记对应的实际操作";
}
- (void)markAndHide:(CAObserveMarker)marker label:(NSString *)label {
    if (!CAObserveIsActive()) {
        self.status.text = @"请先开启 300 秒观测，再使用人工操作标记";
        return;
    }
    CAObserveMark(marker);
    [self record:[NSString stringWithFormat:@"人工标记：%@", label]];
    self.panel.hidden = YES;
    [self restoreKey];
}
- (void)markSearchBefore { [self markAndHide:CAObserveMarkerSearchBefore label:@"即将点击搜索对手"]; }
- (void)markSearchResult { [self markAndHide:CAObserveMarkerSearchResultVisible label:@"搜索结果/战场已显示"]; }
- (void)markDeployBefore { [self markAndHide:CAObserveMarkerDeployBefore label:@"即将选择/部署兵力"]; }
- (void)markDeployObserved { [self markAndHide:CAObserveMarkerDeployObserved label:@"已观察到部署结果"]; }
- (void)markEndBefore { [self markAndHide:CAObserveMarkerEndBattleBefore label:@"即将手动结束战斗"]; }
- (void)markSettlement { [self markAndHide:CAObserveMarkerSettlementVisible label:@"结算界面已显示"]; }
- (void)markNextRound { [self markAndHide:CAObserveMarkerNextRoundVisible label:@"下一轮/新对手已显示"]; }
- (void)manualStop { [self stop:@"manual"]; }
- (void)copyLog {
    UIPasteboard.generalPasteboard.string = [@"ClashAssist 0.4.0 UI EVENTS\n" stringByAppendingString:[self.events componentsJoinedByString:@"\n"]];
    self.status.text = @"界面日志已复制；完整报告请使用诊断导出";
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self clampBubble]; }
- (void)clampBubble {
    CGRect r = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets); CGPoint p = self.bubble.center;
    p.x = MAX(CGRectGetMinX(r)+27,MIN(p.x,CGRectGetMaxX(r)-27));
    p.y = MAX(CGRectGetMinY(r)+27,MIN(p.y,CGRectGetMaxY(r)-27)); self.bubble.center = p;
}
- (void)pan:(UIPanGestureRecognizer *)p {
    if (p.state == UIGestureRecognizerStateBegan) { self.dragOrigin = self.bubble.center; self.dragging = YES; }
    CGPoint d = [p translationInView:self.view]; self.bubble.center = CGPointMake(self.dragOrigin.x+d.x,self.dragOrigin.y+d.y); [self clampBubble];
    if (p.state == UIGestureRecognizerStateEnded || p.state == UIGestureRecognizerStateCancelled) self.dragging = NO;
}
- (void)longPress:(UILongPressGestureRecognizer *)p { if (p.state == UIGestureRecognizerStateBegan) [self manualStop]; }
- (void)restoreKey { if (self.previousKey && !self.previousKey.hidden) [self.previousKey makeKeyWindow]; }
- (void)toggle {
    if (self.dragging) return; [self.view endEditing:YES];
    BOOL opening = self.panel.hidden; self.panel.hidden = !opening;
    if (opening) {
        self.scroll.contentOffset = CGPointZero;
        for (UIWindow *w in self.overlay.windowScene.windows) if (w.isKeyWindow && w != self.overlay) self.previousKey = w;
        [self.overlay makeKeyWindow];
    } else [self restoreKey];
}
- (void)inactive:(NSNotification *)n {
    (void)n; [self stop:@"background"]; self.panel.hidden = YES; [self restoreKey]; self.overlay.hidden = YES;
}
- (void)active:(NSNotification *)n { (void)n; [self attach]; }
- (void)attach {
    UIApplication *app = UIApplication.sharedApplication; if (app.applicationState != UIApplicationStateActive) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in app.connectedScenes) if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
    if (!self.overlay) {
        self.overlay = scene ? [[CALabWindow alloc] initWithWindowScene:scene] : [[CALabWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.overlay.rootViewController = self; self.overlay.windowLevel = UIWindowLevelAlert+5;
        self.overlay.backgroundColor = UIColor.clearColor;
    } else if (scene && self.overlay.windowScene != scene) self.overlay.windowScene = scene;
    self.overlay.hidden = NO;
}
@end

static CALabController *CALabInstance;
__attribute__((constructor)) static void CALabInitialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.supercell.magic.china"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            CALabInstance = [CALabController new];
            [NSNotificationCenter.defaultCenter addObserver:CALabInstance selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
            [CALabInstance attach];
        });
    }
}
