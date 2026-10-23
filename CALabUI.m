#import <UIKit/UIKit.h>
#import "CALabCore.h"
#import "CAObserve.h"

static NSString * const CAPrefs = @"ClashAssist.settings.v1";
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
@property(nonatomic,strong) UISwitch *loop;
@property(nonatomic,strong) UIButton *startButton;
@property(nonatomic,strong) UIButton *saveButton;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) CALab lab;
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
    self.bubble.accessibilityLabel = @"本地模拟实验，点击面板，长按停止";
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
    UILabel *heading = [self label:@"调用观测 0.3.1 · 模拟功能独立" size:16];
    UIButton *close = [self button:@"收起" action:@selector(toggle) color:UIColor.darkGrayColor];
    [close.widthAnchor constraintEqualToConstant:66].active = YES;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[heading,close]]; header.spacing = 8;
    [root addArrangedSubview:header];
    self.status = [self label:@"就绪 · 所有资源和战斗均为本地生成" size:12];
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
    NSArray *rows = @[@[@"gold",@"模拟最低金币",@500000],@[@"elixir",@"模拟最低圣水",@500000],
        @[@"dark",@"模拟最低黑水",@0],@[@"maxSearch",@"总搜索上限",@50],
        @[@"maxBattles",@"战斗次数上限",@10],@[@"timeout",@"每场超时（模拟秒）",@180]];
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
    self.loop = [UISwitch new]; self.loop.on = [saved[@"loop"] boolValue];
    UIStackView *loopRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"结算后继续模拟搜索" size:14],self.loop]];
    [content addArrangedSubview:loopRow];
    [content addArrangedSubview:[self label:@"固定模拟兵力：8；每 0.7 秒推进一个模拟秒。状态及收益仅存在本工具内。" size:12]];
    [content addArrangedSubview:[self button:@"观测手动操作 60 秒（不自动战斗）" action:@selector(observe) color:UIColor.systemOrangeColor]];
    [content addArrangedSubview:[self button:@"复制调用计数报告" action:@selector(copyObservation) color:UIColor.darkGrayColor]];
    [content addArrangedSubview:[self label:@"观测只统计三处候选调用；开启后请收起面板手动操作。停止按钮停止计数，Hook 透传至游戏退出。" size:12]];
    self.logView = [UITextView new]; self.logView.editable = NO; self.logView.scrollEnabled = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1]; self.logView.textColor = UIColor.whiteColor;
    [self.logView.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [content addArrangedSubview:self.logView];
    self.saveButton = [self button:@"保存配置" action:@selector(save) color:UIColor.systemBlueColor];
    self.startButton = [self button:@"开始模拟" action:@selector(start) color:UIColor.systemGreenColor];
    UIButton *stop = [self button:@"立即停止" action:@selector(manualStop) color:UIColor.systemRedColor];
    UIButton *copy = [self button:@"复制日志" action:@selector(copyLog) color:UIColor.darkGrayColor];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.saveButton,self.startButton,stop,copy]];
    actions.distribution = UIStackViewDistributionFillEqually; actions.spacing = 6; [root addArrangedSubview:actions];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [self record:@"就绪：仅运行本地模拟，无游戏输入或网络调用"];
}
- (BOOL)running { return self.lab.phase != CALabIdle && self.lab.phase != CALabStopped; }
- (void)record:(NSString *)text {
    [self.events addObject:text];
    if (self.events.count > 80) [self.events removeObjectAtIndex:0];
    self.logView.text = [self.events componentsJoinedByString:@"\n"];
}
- (BOOL)readConfig:(CALabConfig *)out {
    NSMutableDictionary *values = [NSMutableDictionary new];
    for (NSString *key in self.fields) {
        NSString *text = self.fields[key].text ?: @"";
        if (!text.length || text.length > 9 || [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) {
            self.status.text = @"配置错误：请输入 0–999999999 的整数"; return NO;
        }
        uint32_t n = (uint32_t)text.longLongValue;
        if ([@[@"maxSearch",@"maxBattles",@"timeout"] containsObject:key] && (n<1 || n>10000)) {
            self.status.text = @"次数和超时必须在 1–10000 之间"; return NO;
        }
        values[key] = @(n);
    }
    values[@"loop"] = @(self.loop.on);
    *out = (CALabConfig){[values[@"gold"] unsignedIntValue],[values[@"elixir"] unsignedIntValue],
        [values[@"dark"] unsignedIntValue],[values[@"maxSearch"] unsignedIntValue],
        [values[@"maxBattles"] unsignedIntValue],[values[@"timeout"] unsignedIntValue],self.loop.on};
    [NSUserDefaults.standardUserDefaults setObject:values forKey:CAPrefs];
    [self.view endEditing:YES]; return YES;
}
- (void)save { CALabConfig c; if ([self readConfig:&c]) self.status.text = @"配置已保存 · 数据来源：本地模拟"; }
- (void)setRunningControls:(BOOL)running {
    self.startButton.enabled = !running; self.saveButton.enabled = !running;
    self.startButton.alpha = running ? 0.5 : 1; self.saveButton.alpha = running ? 0.5 : 1;
    for (UITextField *f in self.fields.allValues) f.enabled = !running;
    self.loop.enabled = !running;
    [self.bubble setTitle:running ? @"模拟中" : @"实验" forState:UIControlStateNormal];
}
- (void)start {
    if ([self running]) return;
    CALabConfig c; if (![self readConfig:&c]) return;
    [self.timer invalidate]; CALab s; CALabStart(&s,c); self.lab = s;
    [self.events removeAllObjects]; [self record:@"本地模拟开始；无真实搜索/部署/攻击"];
    [self setRunningControls:[self running]]; [self updateStatus];
    if (![self running]) return;
    __weak CALabController *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) {
        CALabController *controller = weakSelf;
        if (!controller) { [t invalidate]; return; }
        [controller tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (NSString *)phaseName {
    switch(self.lab.phase) {
        case CALabSearching:return @"模拟搜索"; case CALabDeploying:return @"模拟部署";
        case CALabFighting:return @"模拟战斗"; case CALabSettling:return @"模拟结算";
        case CALabStopped:return @"已停止"; default:return @"就绪";
    }
}
- (NSString *)reasonName {
    NSDictionary *names = @{@"search-limit":@"达到搜索上限",@"battle-limit":@"达到战斗上限",
        @"single-complete":@"单次流程完成",@"battle-timeout":@"模拟战斗超时",@"battle-complete":@"模拟战斗完成",
        @"filtered":@"资源不达标",@"matched":@"资源筛选通过",@"manual":@"手动停止",
        @"background":@"离开前台停止",@"invalid-config":@"配置错误",@"deploying":@"逐个部署模拟单位",
        @"fighting":@"模拟收益变化",@"searching":@"寻找模拟样本"};
    NSString *key = self.lab.reason ? [NSString stringWithUTF8String:self.lab.reason] : @"";
    return names[key] ?: key;
}
- (void)updateStatus {
    CALab s = self.lab;
    self.status.text = [NSString stringWithFormat:@"仅本地模拟 · %@ · %@\n搜索 %u/%u  结算 %u/%u  模拟单位 %u/8  模拟时间 %u 秒\n模拟累计收益：金币 %llu / 圣水 %llu / 黑水 %llu",
        [self phaseName],[self reasonName],s.searches,s.config.maxSearch,s.battles,s.config.maxBattles,s.units,s.elapsed,
        (unsigned long long)s.earnedGold,(unsigned long long)s.earnedElixir,(unsigned long long)s.earnedDark];
}
- (void)tick {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { [self stop:@"background"]; return; }
    CALab s = self.lab; CALabTick(&s); self.lab = s;
    [self record:[NSString stringWithFormat:@"[%u/%u] %@：%@；样本 金%u 水%u 黑%u；单位%u；时间%u",
        s.searches,s.battles,[self phaseName],[self reasonName],s.gold,s.elixir,s.dark,s.units,s.elapsed]];
    [self updateStatus];
    if (![self running]) { [self.timer invalidate]; self.timer = nil; [self setRunningControls:NO]; }
}
- (void)stop:(NSString *)reason {
    CAObserveStop();
    [self.timer invalidate]; self.timer = nil;
    CALab s = self.lab; CALabStop(&s,[reason isEqualToString:@"background"] ? "background" : "manual"); self.lab = s;
    [self setRunningControls:NO]; [self.view endEditing:YES];
    [self record:[self reasonName]]; [self updateStatus];
}
- (void)observe {
    [self stop:@"manual"];
    NSString *error=nil;
    if(CAObserveStart(&error)) {
        self.status.text=@"手动操作观测中（60秒）· 收起面板手动操作，随后复制调用计数报告";
        [self record:@"已开启真实调用计数：未执行任何自动游戏操作"];
    } else { self.status.text=error?:@"观测启动失败"; [self record:self.status.text]; }
}
- (void)copyObservation {
    NSData *data=[NSJSONSerialization dataWithJSONObject:CAObserveSnapshot() options:NSJSONWritingPrettyPrinted error:nil];
    UIPasteboard.generalPasteboard.string=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.status.text=@"真实调用计数报告已复制（候选命中不等于接口验证通过）";
}
- (void)manualStop { CAObserveStop(); [self stop:@"manual"]; }
- (void)copyLog {
    UIPasteboard.generalPasteboard.string = [@"ClashAssist 0.2.0 LOCAL SYNTHETIC ONLY\n" stringByAppendingString:[self.events componentsJoinedByString:@"\n"]];
    self.status.text = @"本地模拟日志已复制";
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
