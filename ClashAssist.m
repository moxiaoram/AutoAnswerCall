#import <UIKit/UIKit.h>
#import <math.h>

static NSString * const CAPrefs = @"ClashAssist.settings.v1";
@class CAController;
@interface CAWindow : UIWindow
@end
@implementation CAWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return v == self.rootViewController.view || v == self ? nil : v;
}
@end

@interface CAController : UIViewController
@property(nonatomic,strong) CAWindow *overlay;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSMutableDictionary *settings;
@property(nonatomic,strong) NSMutableDictionary<NSString *,UITextField *> *fields;
@property(nonatomic,strong) UISwitch *loopSwitch;
@property(nonatomic,strong) UIButton *startButton;
@property(nonatomic,assign) CGPoint dragStart;
@property(nonatomic,assign) BOOL dragged;
@property(nonatomic,assign) BOOL stopped;
- (void)attach;
@end

@implementation CAController
- (void)loadView {
    self.view = [UIView new];
    self.view.backgroundColor = UIColor.clearColor;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:CAPrefs];
    self.settings = [@{@"gold":@500000, @"elixir":@500000, @"dark":@0,
                         @"maxSearch":@50, @"maxBattles":@10, @"timeout":@180, @"loop":@NO} mutableCopy];
    for (NSString *key in self.settings.allKeys) {
        id value = saved[key];
        if ([value isKindOfClass:NSNumber.class]) self.settings[key] = value;
    }
    self.stopped = YES;
    self.fields = [NSMutableDictionary new];
    self.bubble = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubble.frame = CGRectMake(20, 80, 56, 56);
    self.bubble.backgroundColor = [UIColor colorWithRed:0.08 green:0.36 blue:0.78 alpha:0.95];
    self.bubble.layer.cornerRadius = 28;
    self.bubble.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.bubble setTitle:@"辅助" forState:UIControlStateNormal];
    [self.bubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.bubble.accessibilityLabel = @"部落辅助；轻点设置，长按停止";
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self.bubble addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    [self.view addSubview:self.bubble];
    self.panel = [UIView new];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
    self.panel.layer.cornerRadius = 16;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];
    self.scroll = [UIScrollView new];
    self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.panel addSubview:self.scroll];
    UILabel *title = [UILabel new];
    title.text = @"部落辅助 · 诊断版 0.1.1";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:18];
    title.frame = CGRectMake(16, 14, 290, 28);
    [self.scroll addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(276, 12, 42, 30);
    [close setTitle:@"收起" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:close];
    self.status = [UILabel new];
    self.status.textColor = [UIColor colorWithRed:1 green:0.75 blue:0.25 alpha:1];
    self.status.font = [UIFont systemFontOfSize:13];
    self.status.numberOfLines = 0;
    self.status.frame = CGRectMake(16, 48, 302, 104);
    [self.scroll addSubview:self.status];
    NSArray *rows = @[@[@"gold",@"最低金币"], @[@"elixir",@"最低圣水"], @[@"dark",@"最低黑水"],
        @[@"maxSearch",@"最多搜索次数"], @[@"maxBattles",@"最多战斗次数"], @[@"timeout",@"战斗超时（秒）"]];
    CGFloat y = 160;
    for (NSArray *row in rows) {
        UILabel *label = [UILabel new];
        label.frame = CGRectMake(16, y, 165, 38);
        label.text = row[1]; label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:14];
        [self.scroll addSubview:label];
        UITextField *field = [UITextField new];
        field.frame = CGRectMake(185, y + 2, 130, 34);
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [self.settings[row[0]] stringValue];
        field.accessibilityLabel = row[1];
        self.fields[row[0]] = field;
        [self.scroll addSubview:field];
        y += 44;
    }
    UILabel *loop = [UILabel new]; loop.text = @"战后继续搜索";
    loop.textColor = UIColor.whiteColor; loop.font = [UIFont systemFontOfSize:14];
    loop.frame = CGRectMake(16, y, 180, 36); [self.scroll addSubview:loop];
    self.loopSwitch = [UISwitch new]; self.loopSwitch.frame = CGRectMake(260, y, 52, 32);
    self.loopSwitch.on = [self.settings[@"loop"] boolValue]; [self.scroll addSubview:self.loopSwitch];
    y += 48;
    NSArray *actions = @[@"保存配置",@"开始（接口未验证）",@"立即停止"];
    SEL selectors[] = {@selector(save), @selector(start), @selector(manualStop)};
    for (NSUInteger i = 0; i < actions.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(16, y, 300, 42); b.layer.cornerRadius = 8;
        b.backgroundColor = i == 2 ? UIColor.systemRedColor : UIColor.systemBlueColor;
        [b setTitle:actions[i] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [b addTarget:self action:selectors[i] forControlEvents:UIControlEventTouchUpInside];
        if (i == 2) { b.tag = 700; [self.panel addSubview:b]; }
        else { [self.scroll addSubview:b]; }
        if (i == 1) { self.startButton = b; b.enabled = NO; b.alpha = 0.45; }
        y += 50;
    }
    UILabel *note = [UILabel new]; note.frame = CGRectMake(16, y, 300, 94);
    note.numberOfLines = 0; note.font = [UIFont systemFontOfSize:12]; note.textColor = UIColor.lightGrayColor;
    note.text = @"此版本只提供悬浮设置和注入诊断。资源监测、搜索、下兵、战斗结束接口尚未验证，自动战斗不可启动。长按悬浮球或切到后台均停止。";
    [self.scroll addSubview:note]; self.scroll.contentSize = CGSizeMake(332, y + 110);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(inactive:) name:UIApplicationWillResignActiveNotification object:nil];
    [self refreshStatus:@"已停止"];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
- (void)refreshStatus:(NSString *)reason {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    self.status.text = [NSString stringWithFormat:@"注入成功 · 游戏 %@\n%@ · 战斗接口未验证\n当前未采集资源或战斗状态；自动化未启用。", version, reason];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat w = MIN(500, MAX(1, safe.size.width - 32));
    CGFloat h = MIN(500, MAX(1, safe.size.height - 16));
    self.panel.frame = CGRectMake(CGRectGetMidX(safe)-w/2, CGRectGetMidY(safe)-h/2, w, h);
    CGFloat bottomHeight = 52;
    self.scroll.frame = CGRectMake(0, 0, w, MAX(1,h-bottomHeight));
    UIButton *stop = (UIButton *)[self.panel viewWithTag:700];
    stop.frame = CGRectMake(16, MAX(0,h-bottomHeight), MAX(1,w-32), 44);
    CGFloat contentW = MAX(1,w-32);
    self.status.frame = CGRectMake(16, 48, contentW, 104);
    for (UIView *sub in self.scroll.subviews) {
        if ([sub isKindOfClass:UITextField.class]) {
            CGRect f = sub.frame;
            f.origin.x = MAX(16,w-146);
            f.size.width = MIN(130, MAX(1,w-32));
            sub.frame = f;
        } else if ([sub isKindOfClass:UISwitch.class]) {
            CGRect f = sub.frame; f.origin.x = MAX(16,w-72); sub.frame = f;
        } else if ([sub isKindOfClass:UIButton.class] && sub != self.bubble) {
            UIButton *button = (UIButton *)sub;
            if (button == self.startButton || [button.currentTitle isEqualToString:@"保存配置"]) {
                CGRect f = button.frame; f.size.width = contentW; button.frame = f;
            } else if ([button.currentTitle isEqualToString:@"收起"]) {
                CGRect f = button.frame; f.origin.x = MAX(16,w-56); button.frame = f;
            }
        } else if ([sub isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)sub;
            if (label != self.status && label.numberOfLines != 1) {
                CGRect f = label.frame; f.size.width = contentW; label.frame = f;
            }
        }
    }
    self.scroll.contentSize = CGSizeMake(w, 700);
    [self clampBubble];
}
- (void)clampBubble {
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGPoint c = self.bubble.center;
    c.x = MAX(CGRectGetMinX(safe)+28, MIN(c.x, CGRectGetMaxX(safe)-28));
    c.y = MAX(CGRectGetMinY(safe)+28, MIN(c.y, CGRectGetMaxY(safe)-28));
    self.bubble.center = c;
}
- (void)pan:(UIPanGestureRecognizer *)p {
    if (p.state == UIGestureRecognizerStateBegan) { self.dragStart = self.bubble.center; self.dragged = YES; }
    CGPoint delta = [p translationInView:self.view];
    self.bubble.center = CGPointMake(self.dragStart.x+delta.x,self.dragStart.y+delta.y);
    [self clampBubble];
    if (p.state == UIGestureRecognizerStateEnded || p.state == UIGestureRecognizerStateCancelled) {
        self.dragged = NO;
    }
}
- (void)longPress:(UILongPressGestureRecognizer *)p {
    if (p.state == UIGestureRecognizerStateBegan) [self manualStop];
}
- (void)togglePanel {
    if (self.dragged) return;
    [self.view endEditing:YES];
    BOOL opening = self.panel.hidden;
    self.panel.hidden = !opening;
    if (opening) {
        for (UIWindow *window in self.overlay.windowScene.windows) {
            if (window.isKeyWindow && window != self.overlay) { self.previousKeyWindow = window; break; }
        }
        [self.overlay makeKeyWindow];
    } else if (self.previousKeyWindow && !self.previousKeyWindow.hidden) {
        [self.previousKeyWindow makeKeyWindow];
    }
}
- (void)save {
    NSMutableDictionary *next = [self.settings mutableCopy];
    for (NSString *key in self.fields) {
        NSString *text = self.fields[key].text ?: @"";
        NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        if (!text.length || [text rangeOfCharacterFromSet:nonDigits].location != NSNotFound || text.length > 9) {
            [self refreshStatus:@"配置未保存：请输入 0–999999999 整数"]; return;
        }
        long long value = text.longLongValue;
        BOOL bounded = [@[@"maxSearch",@"maxBattles",@"timeout"] containsObject:key];
        if (bounded && (value < 1 || value > 10000)) {
            [self refreshStatus:@"配置未保存：次数和秒数需为 1–10000"]; return;
        }
        next[key] = @(value);
    }
    next[@"loop"] = @(self.loopSwitch.on); self.settings = next;
    [NSUserDefaults.standardUserDefaults setObject:next forKey:CAPrefs];
    [self.view endEditing:YES]; [self refreshStatus:@"配置已保存，自动化未启用"];
}
- (void)start { self.stopped = YES; [self refreshStatus:@"无法启动：资源/部署/状态接口未验证"]; }
- (void)manualStop { self.stopped = YES; [self.view endEditing:YES]; [self refreshStatus:@"手动停止"]; }
- (void)inactive:(NSNotification *)notification {
    (void)notification; self.stopped = YES; [self.view endEditing:YES]; self.panel.hidden = YES;
    self.overlay.hidden = YES; [self refreshStatus:@"应用失去前台，已停止"];
}
- (void)active:(NSNotification *)notification { (void)notification; [self attach]; }
- (void)attach {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (!self.overlay) {
        self.overlay = scene ? [[CAWindow alloc] initWithWindowScene:scene] : [[CAWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.overlay.rootViewController = self; self.overlay.windowLevel = UIWindowLevelAlert + 5;
        self.overlay.backgroundColor = UIColor.clearColor;
    } else if (scene && self.overlay.windowScene != scene) { self.overlay.windowScene = scene; }
    self.overlay.hidden = NO;
}
@end

static CAController *CAInstance;
__attribute__((constructor)) static void CAInitialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.supercell.magic.china"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            CAInstance = [CAController new];
            [NSNotificationCenter.defaultCenter addObserver:CAInstance selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
            [CAInstance attach];
            NSLog(@"[ClashAssist] 0.1.1 loaded; battle adapter unavailable");
        });
    }
}
