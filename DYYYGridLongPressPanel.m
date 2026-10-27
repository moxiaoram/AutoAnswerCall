#import "DYYYGridLongPressPanel.h"
#import "AwemeHeaders.h"
#import "DYYYUtils.h"
#import "DYYYSettingsHelper.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

// 仿照用户提供的参考图：五个圆形快捷项 + 深色分组菜单 + 倍速行。
// 仅使用当前版本返回的原生 ViewModel / 插件已实现的 action；没有绑定的功能不伪造调用。
static char kDYYYGridPanelDisplayedKey;
static char kDYYYGridPanelWindowKey;
static __weak DYYYGridLongPressPanel *gDYYYCurrentlyOpenPanel;
static BOOL DYYYIsNativeLongPressController(UIViewController *controller) {
    return [NSStringFromClass(controller.class) containsString:@"LongPressPanel"];
}

@interface DYYYGridLongPressPanel ()
@property(nonatomic, copy) NSArray<AWELongPressPanelBaseViewModel *> *actions;
@property(nonatomic, weak) UIViewController *originController;
@property(nonatomic, weak) UIViewController *sourceController;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic, strong) UIWindow *overlayWindow;
@property(nonatomic, strong) UIView *sheet;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIView *grabber;
@property(nonatomic, assign) CGFloat renderedWidth;
@property(nonatomic, assign) CGFloat selectedSpeed;
@property(nonatomic, assign) BOOL showingNative;
@end

@implementation DYYYGridLongPressPanel

#pragma mark - Presentation

// 在原生抽屉动画开始前，直接覆盖到当前窗口；不再等待 viewDidAppear 或抽屉被拖到顶。
// 原生 action/awemeModel 仍由原控制器提供，不对抖音的私有弹出选择器做假设。
+ (BOOL)showFromController:(UIViewController *)controller groups:(NSArray *)groups {
    if (!controller) return NO;
    DYYYGridLongPressPanel *existing = objc_getAssociatedObject(controller, &kDYYYGridPanelDisplayedKey);
    // Reconcile the immediate feed gesture and delayed native controller even when
    // Douyin presents its native drawer in an entirely different UIWindow.
    if (!existing && gDYYYCurrentlyOpenPanel.overlayWindow && !gDYYYCurrentlyOpenPanel.overlayWindow.hidden)
        existing = gDYYYCurrentlyOpenPanel;
    UIWindow *window = controller.view.window ?: [DYYYUtils getActiveWindow];
    if (!window) return NO;
    DYYYGridLongPressPanel *onWindow = objc_getAssociatedObject(window, &kDYYYGridPanelWindowKey);
    // The feed recognizer may have already opened the sheet. Do not let a second
    // native long-press controller draw over it or dismiss the earlier overlay.
    if (!existing && onWindow && onWindow.overlayWindow && !onWindow.overlayWindow.hidden) {
        existing = onWindow;
        objc_setAssociatedObject(controller, &kDYYYGridPanelDisplayedKey, existing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        existing.originController = controller;
        controller.view.hidden = YES;
    }

    NSMutableArray *all = [NSMutableArray array];
    NSMutableSet *seenNames = [NSMutableSet set];
    for (id group in groups) {
        if (![group isKindOfClass:NSClassFromString(@"AWELongPressPanelViewGroupModel")]) continue;
        NSArray *items = [(AWELongPressPanelViewGroupModel *)group groupArr];
        if (![items isKindOfClass:[NSArray class]]) continue;
        for (id object in items) {
            if (![object isKindOfClass:NSClassFromString(@"AWELongPressPanelBaseViewModel")]) continue;
            AWELongPressPanelBaseViewModel *model = object;
            NSString *name = model.describeString;
            if (![name isKindOfClass:[NSString class]] || !name.length || [seenNames containsObject:name]) continue;
            [seenNames addObject:name];
            [all addObject:model];
        }
    }
    // 有些原生分组直到抽屉展开后才填充，首次长按也必须直接呈现。
    if (existing) {
        objc_setAssociatedObject(controller, &kDYYYGridPanelDisplayedKey, existing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (DYYYIsNativeLongPressController(controller)) {
            existing.originController = controller;
            controller.view.hidden = YES;
        }
        if (all.count && ![existing.actions isEqualToArray:all]) {
            existing.actions = [all copy];
            [existing rebuildMenu];
        }
        return YES;
    }

    DYYYGridLongPressPanel *panel = [[DYYYGridLongPressPanel alloc] init];
    panel.actions = [all copy];
    panel.originController = DYYYIsNativeLongPressController(controller) ? controller : nil;
    panel.sourceController = controller;
    panel.hostWindow = window;
    panel.selectedSpeed = 1.0;
    // 原生菜单可能在另外一个更高层的 window 呈现；单纯 addSubview 会被盖住。
    // 独立的非 key 窗口优先于原生抽屉绘制，且不触发自己的 present 转场动画。
    UIWindow *overlay = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) overlay = [[UIWindow alloc] initWithWindowScene:scene];
    }
    if (!overlay) overlay = [[UIWindow alloc] initWithFrame:window.bounds];
    if (!overlay) return NO;
    overlay.windowLevel = UIWindowLevelAlert + 20;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.rootViewController = panel;
    panel.overlayWindow = overlay;
    objc_setAssociatedObject(controller, &kDYYYGridPanelDisplayedKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &kDYYYGridPanelWindowKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    overlay.hidden = NO;
    gDYYYCurrentlyOpenPanel = panel;
    if (DYYYIsNativeLongPressController(controller)) controller.view.hidden = YES;
    [panel.view setNeedsLayout];
    [panel.view layoutIfNeeded];
    return YES;
}

+ (void)clearFromController:(UIViewController *)controller {
    if (!controller) return;
    DYYYGridLongPressPanel *panel = objc_getAssociatedObject(controller, &kDYYYGridPanelDisplayedKey);
    if (panel) [panel removeOverlay];
}

- (void)removeOverlay {
    UIWindow *window = self.hostWindow;
    UIViewController *origin = self.originController;
    UIViewController *source = self.sourceController;
    if (gDYYYCurrentlyOpenPanel == self) gDYYYCurrentlyOpenPanel = nil;
    // 彻底释放独立窗口，确保关闭后不会挡住原视频的点击与滑动。
    self.overlayWindow.hidden = YES;
    self.overlayWindow.rootViewController = nil;
    self.overlayWindow = nil;
    [self.view removeFromSuperview];
    if (window && objc_getAssociatedObject(window, &kDYYYGridPanelWindowKey) == self) {
        objc_setAssociatedObject(window, &kDYYYGridPanelWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (origin && objc_getAssociatedObject(origin, &kDYYYGridPanelDisplayedKey) == self) {
        objc_setAssociatedObject(origin, &kDYYYGridPanelDisplayedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (source && objc_getAssociatedObject(source, &kDYYYGridPanelDisplayedKey) == self) {
        objc_setAssociatedObject(source, &kDYYYGridPanelDisplayedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (UIColor *)sheetColor { return [UIColor colorWithRed:0.104 green:0.099 blue:0.123 alpha:1]; }
- (UIColor *)cardColor { return [UIColor colorWithRed:0.174 green:0.168 blue:0.193 alpha:1]; }
- (UIColor *)circleColor { return [UIColor colorWithRed:0.259 green:0.254 blue:0.283 alpha:1]; }
- (UIColor *)subtleColor { return [UIColor colorWithRed:0.70 green:0.69 blue:0.73 alpha:1]; }
- (UIColor *)accentColor { return [UIColor colorWithRed:0.96 green:0.17 blue:0.38 alpha:1]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIButton *shade = [UIButton buttonWithType:UIButtonTypeCustom];
    shade.frame = self.view.bounds;
    shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
    [shade addTarget:self action:@selector(closeAll) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:shade];

    UIView *sheet = [[UIView alloc] initWithFrame:CGRectZero];
    sheet.backgroundColor = [self sheetColor];
    sheet.layer.cornerRadius = 22;
    if (@available(iOS 11.0, *)) {
        sheet.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    sheet.clipsToBounds = YES;
    [self.view addSubview:sheet];
    self.sheet = sheet;

    UIView *grabber = [[UIView alloc] initWithFrame:CGRectZero];
    grabber.backgroundColor = [UIColor colorWithWhite:0.42 alpha:1];
    grabber.layer.cornerRadius = 2.5;
    [sheet addSubview:grabber];
    self.grabber = grabber;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [sheet addSubview:scroll];
    self.scroll = scroll;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragHandle:)];
    [sheet addGestureRecognizer:pan];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 只在顶部拖拽条响应下拉关闭，不抢夺面板内的滑动与点击。
    CGPoint p = [touch locationInView:self.sheet];
    return p.y <= 25;
}

- (void)dragHandle:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateEnded) return;
    if ([pan translationInView:self.sheet].y > 55 || [pan velocityInView:self.sheet].y > 700) [self closeAll];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat sheetHeight = MIN(height * 0.68, 750);
    self.sheet.frame = CGRectMake(0, height - sheetHeight, width, sheetHeight);
    self.grabber.frame = CGRectMake((width - 38) * 0.5, 8, 38, 5);
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    self.scroll.frame = CGRectMake(0, 22, width, sheetHeight - 22);
    self.scroll.contentInset = UIEdgeInsetsMake(0, 0, safeBottom + 12, 0);
    if (fabs(width - self.renderedWidth) > 1) {
        self.renderedWidth = width;
        [self rebuildMenu];
    }
}

#pragma mark - Action discovery

- (AWELongPressPanelBaseViewModel *)findAction:(NSArray<NSString *> *)terms used:(NSMutableSet<NSNumber *> *)used {
    // 先精确匹配，再部分匹配；尽量沿用原生 action block。
    for (NSInteger pass = 0; pass < 2; pass++) {
        for (NSUInteger i = 0; i < self.actions.count; i++) {
            if ([used containsObject:@(i)]) continue;
            AWELongPressPanelBaseViewModel *model = self.actions[i];
            for (NSString *term in terms) {
                BOOL hit = pass == 0 ? [model.describeString isEqualToString:term] : [model.describeString containsString:term];
                if (hit) { [used addObject:@(i)]; return model; }
            }
        }
    }
    return nil;
}

- (NSInteger)indexForModel:(AWELongPressPanelBaseViewModel *)model {
    if (!model) return -1;
    NSUInteger idx = [self.actions indexOfObjectIdenticalTo:model];
    return idx == NSNotFound ? -1 : (NSInteger)idx;
}

- (NSString *)symbolForName:(NSString *)name {
    if ([name containsString:@"赞赏"] || [name containsString:@"打赏"]) return @"gift";
    if ([name containsString:@"推荐"] || [name containsString:@"点赞"]) return @"hand.thumbsup";
    if ([name containsString:@"稍后"] || [name containsString:@"再看"]) return @"play.rectangle.on.rectangle";
    if ([name containsString:@"听视频"] || [name containsString:@"听音频"]) return @"headphones";
    if ([name containsString:@"下载"] || [name containsString:@"保存视频"]) return @"arrow.down.to.line";
    if ([name containsString:@"封面"] || [name containsString:@"图片"]) return @"photo";
    if ([name containsString:@"音频"] || [name containsString:@"音乐"]) return @"waveform";
    if ([name containsString:@"地址"] || [name containsString:@"链接"]) return @"link";
    if ([name containsString:@"复制"]) return @"doc.on.doc";
    if ([name containsString:@"倍速"]) return @"forward.end.alt";
    if ([name containsString:@"举报"]) return @"exclamationmark.triangle";
    if ([name containsString:@"不感兴趣"]) return @"heart.slash";
    if ([name containsString:@"弹幕"]) return @"text.bubble";
    if ([name containsString:@"自动上滑"]) return @"arrow.up.square";
    if ([name containsString:@"后台播放"]) return @"play.rectangle";
    if ([name containsString:@"合拍"]) return @"person.2";
    if ([name containsString:@"过滤"]) return @"line.3.horizontal.decrease.circle";
    return @"square.grid.2x2";
}

#pragma mark - UI builders

- (UILabel *)label:(NSString *)text font:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.8;
    return label;
}

- (UIImageView *)icon:(NSString *)symbol point:(CGFloat)size color:(UIColor *)color {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightRegular];
    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    image.tintColor = color;
    image.contentMode = UIViewContentModeScaleAspectFit;
    return image;
}

- (void)addSeparatorAt:(CGFloat)y in:(UIView *)card {
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(48, y, card.bounds.size.width - 60, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    [card addSubview:line];
}

- (void)addQuickAction:(NSString *)name symbol:(NSString *)symbol model:(AWELongPressPanelBaseViewModel *)model column:(NSUInteger)i total:(NSUInteger)count atY:(CGFloat)y {
    CGFloat width = self.scroll.bounds.size.width;
    CGFloat slot = (width - 16) / MAX(count, 1);
    CGFloat diameter = MIN(53, slot - 15);
    CGFloat centerX = 8 + slot * (i + 0.5);

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(centerX - diameter * 0.5, y, diameter, diameter);
    button.layer.cornerRadius = diameter * 0.5;
    button.backgroundColor = [self circleColor];
    button.tag = [self indexForModel:model] + 1000; // 缺失为 999
    button.accessibilityLabel = name;
    [button addTarget:self action:@selector(quickTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *image = [self icon:symbol point:23 color:UIColor.whiteColor];
    image.frame = CGRectMake((diameter - 26) / 2, (diameter - 26) / 2, 26, 26);
    [button addSubview:image];
    if (!model) { button.alpha = 0.45; button.accessibilityHint = @"当前视频没有对应操作"; }
    [self.scroll addSubview:button];

    UILabel *text = [self label:name font:12 color:[UIColor colorWithWhite:0.85 alpha:1]];
    text.frame = CGRectMake(8 + slot * i, y + diameter + 8, slot, 18);
    [self.scroll addSubview:text];
}

- (UIView *)newCardAtY:(CGFloat)y height:(CGFloat)height {
    CGFloat width = self.scroll.bounds.size.width;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(15, y, width - 30, height)];
    card.layer.cornerRadius = 12;
    card.clipsToBounds = YES;
    card.backgroundColor = [self cardColor];
    [self.scroll addSubview:card];
    return card;
}

- (void)addRow:(NSString *)name symbol:(NSString *)symbol model:(AWELongPressPanelBaseViewModel *)model y:(CGFloat)y inCard:(UIView *)card trailing:(BOOL)trailing {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, y, card.bounds.size.width, 52);
    button.tag = [self indexForModel:model] + 1000;
    button.accessibilityLabel = name;
    if (!model) button.alpha = 0.50;
    [button addTarget:self action:@selector(modelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:button];

    UIImageView *image = [self icon:symbol point:18 color:[UIColor colorWithWhite:0.9 alpha:1]];
    image.frame = CGRectMake(16, 14, 24, 24);
    [button addSubview:image];
    UILabel *text = [self label:name font:16 color:UIColor.whiteColor];
    text.textAlignment = NSTextAlignmentLeft;
    text.frame = CGRectMake(46, 0, card.bounds.size.width - 78, 52);
    [button addSubview:text];
    if (trailing) {
        UIImageView *chevron = [self icon:@"chevron.right" point:14 color:[self subtleColor]];
        chevron.frame = CGRectMake(card.bounds.size.width - 31, 17, 16, 18);
        [button addSubview:chevron];
    }
}

- (void)addToggleRow:(NSString *)name symbol:(NSString *)symbol key:(NSString *)key y:(CGFloat)y inCard:(UIView *)card tag:(NSInteger)tag {
    UIImageView *image = [self icon:symbol point:18 color:UIColor.whiteColor];
    image.frame = CGRectMake(16, y + 14, 24, 24);
    [card addSubview:image];
    UILabel *text = [self label:name font:16 color:UIColor.whiteColor];
    text.textAlignment = NSTextAlignmentLeft;
    text.frame = CGRectMake(46, y, card.bounds.size.width - 118, 52);
    [card addSubview:text];
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    toggle.onTintColor = [UIColor colorWithRed:0.34 green:0.51 blue:0.98 alpha:1];
    toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);
    toggle.tag = tag;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    CGRect frame = toggle.frame;
    frame.origin.x = card.bounds.size.width - frame.size.width - 12;
    frame.origin.y = y + (52 - frame.size.height) * 0.5;
    toggle.frame = frame;
    [card addSubview:toggle];
}

- (void)addSpeedRowAt:(CGFloat)y inCard:(UIView *)card {
    UIImageView *image = [self icon:@"forward.end.alt" point:18 color:UIColor.whiteColor];
    image.frame = CGRectMake(16, y + 14, 24, 24);
    [card addSubview:image];
    UILabel *title = [self label:@"倍速" font:16 color:UIColor.whiteColor];
    title.textAlignment = NSTextAlignmentLeft;
    title.frame = CGRectMake(46, y, 54, 52);
    [card addSubview:title];

    NSArray<NSNumber *> *speeds = @[@0.5, @1.0, @1.5, @2.0];
    CGFloat available = card.bounds.size.width - 108;
    CGFloat slot = available / speeds.count;
    for (NSUInteger i = 0; i < speeds.count; i++) {
        CGFloat rate = [speeds[i] floatValue];
        NSString *label = [NSString stringWithFormat:@"%gx", rate];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(108 + slot * i, y, slot, 52);
        button.tag = 5000 + i;
        [button setTitle:label forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [button addTarget:self action:@selector(speedTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:button];
    }
    [self updateSpeedHighlight];
}

- (void)updateSpeedHighlight {
    for (NSUInteger i = 0; i < 4; i++) {
        UIButton *button = [self.scroll viewWithTag:5000 + i];
        if (![button isKindOfClass:UIButton.class]) continue;
        CGFloat values[] = {0.5, 1.0, 1.5, 2.0};
        [button setTitleColor:fabs(self.selectedSpeed - values[i]) < 0.001 ? [self accentColor] : [self subtleColor]
                    forState:UIControlStateNormal];
    }
}

- (void)addExtensionCard:(AWELongPressPanelBaseViewModel *)model column:(NSUInteger)column row:(NSUInteger)row baseY:(CGFloat)baseY {
    CGFloat width = self.scroll.bounds.size.width;
    CGFloat gap = 11;
    CGFloat inset = 15;
    CGFloat cellWidth = (width - inset * 2 - gap) * 0.5;
    CGFloat x = inset + column * (cellWidth + gap);
    CGFloat y = baseY + row * 81;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(x, y, cellWidth, 71);
    button.layer.cornerRadius = 12;
    button.backgroundColor = [self cardColor];
    button.tag = [self indexForModel:model] + 1000;
    [button addTarget:self action:@selector(modelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:button];
    UIImageView *image = [self icon:[self symbolForName:model.describeString] point:21 color:UIColor.whiteColor];
    image.frame = CGRectMake(13, 11, 27, 27);
    [button addSubview:image];
    UILabel *label = [self label:model.describeString font:13 color:UIColor.whiteColor];
    label.textAlignment = NSTextAlignmentLeft;
    label.frame = CGRectMake(12, 43, cellWidth - 24, 20);
    [button addSubview:label];
}

- (void)rebuildMenu {
    for (UIView *sub in [self.scroll.subviews copy]) [sub removeFromSuperview];
    CGFloat width = self.scroll.bounds.size.width;
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];

    NSArray<NSDictionary *> *quick = @[
        @{@"text":@"推荐一下", @"icon":@"hand.thumbsup", @"matches":@[@"推荐",@"点赞"]},
        @{@"text":@"赞赏", @"icon":@"gift", @"matches":@[@"赞赏",@"打赏"]},
        @{@"text":@"下载", @"icon":@"arrow.down.to.line", @"matches":@[@"保存视频",@"下载"]},
        @{@"text":@"稍后再看", @"icon":@"play.rectangle.on.rectangle", @"matches":@[@"稍后再看"]},
        @{@"text":@"听视频", @"icon":@"headphones", @"matches":@[@"听视频",@"听音频"]}
    ];
    CGFloat y = 5;
    for (NSUInteger i = 0; i < quick.count; i++) {
        NSDictionary *spec = quick[i];
        AWELongPressPanelBaseViewModel *model = [self findAction:spec[@"matches"] used:used];
        [self addQuickAction:spec[@"text"] symbol:spec[@"icon"] model:model column:i total:quick.count atY:y];
    }
    y += 105;

    // 原生「不感兴趣」「举报」保留原始入口，倍速使用已在插件中验证过的播放控制方法。
    AWELongPressPanelBaseViewModel *dislike = [self findAction:@[@"不感兴趣"] used:used];
    AWELongPressPanelBaseViewModel *report = [self findAction:@[@"举报"] used:used];
    UIView *primary = [self newCardAtY:y height:156];
    [self addRow:@"不感兴趣" symbol:@"heart.slash" model:dislike y:0 inCard:primary trailing:NO];
    [self addSeparatorAt:52 in:primary];
    [self addRow:@"举报" symbol:@"exclamationmark.triangle" model:report y:52 inCard:primary trailing:YES];
    [self addSeparatorAt:104 in:primary];
    [self addSpeedRowAt:104 inCard:primary];
    y += 168;

    // 视频原生菜单已有的选项继续复用对应 model；自动连播与后台播放使用本插件真实设置键。
    NSArray<NSDictionary *> *secondarySpecs = @[
        @{@"text":@"弹幕开关", @"matches":@[@"弹幕开关"]},
        @{@"text":@"弹幕设置", @"matches":@[@"弹幕设置"]},
        @{@"text":@"保存视频到相册", @"matches":@[@"保存视频到相册",@"保存视频"]}
    ];
    NSMutableArray *secondary = [NSMutableArray array];
    for (NSDictionary *spec in secondarySpecs) {
        BOOL duplicateSave = [spec[@"text"] isEqualToString:@"保存视频到相册"];
        AWELongPressPanelBaseViewModel *model = [self findAction:spec[@"matches"] used:duplicateSave ? [NSMutableSet set] : used];
        if (model) {
            [secondary addObject:@{@"title":spec[@"text"], @"model":model}];
            [used addObject:@([self indexForModel:model])];
        }
    }
    NSUInteger groupCount = secondary.count + 2;
    UIView *card = [self newCardAtY:y height:groupCount * 52];
    NSUInteger position = 0;
    for (NSDictionary *record in secondary) {
        NSString *title = record[@"title"];
        [self addRow:title symbol:[self symbolForName:title] model:record[@"model"] y:position * 52 inCard:card trailing:YES];
        [self addSeparatorAt:(++position) * 52 in:card];
    }
    [self addToggleRow:@"自动上滑" symbol:@"arrow.up.square" key:@"DYYYEnableAutoPlay" y:position * 52 inCard:card tag:6001];
    [self addSeparatorAt:(++position) * 52 in:card];
    [self addToggleRow:@"后台播放" symbol:@"play.rectangle" key:@"DYYYEnableBackgroundListen" y:position * 52 inCard:card tag:6002];
    y += groupCount * 52 + 13;

    // 兼容旧版功能：未被参考图顶栏/分组占用的动作，放进两列扩展区。
    NSMutableArray<AWELongPressPanelBaseViewModel *> *extra = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.actions.count; i++) {
        if ([used containsObject:@(i)]) continue;
        AWELongPressPanelBaseViewModel *model = self.actions[i];
        if ([model.describeString containsString:@"倍速"]) continue;
        [extra addObject:model];
    }
    if (extra.count) {
        UILabel *title = [self label:@"更多操作" font:13 color:[self subtleColor]];
        title.textAlignment = NSTextAlignmentLeft;
        title.frame = CGRectMake(19, y + 1, width - 38, 21);
        [self.scroll addSubview:title];
        y += 28;
        for (NSUInteger i = 0; i < extra.count; i++) {
            [self addExtensionCard:extra[i] column:i % 2 row:i / 2 baseY:y];
        }
        y += ((extra.count + 1) / 2) * 81 + 10;
    }

    // 原生面板兜底：部分原生 action 没有暴露公开 block，点击后可由原生 cell 执行。
    UIButton *native = [UIButton buttonWithType:UIButtonTypeSystem];
    native.frame = CGRectMake(20, y, width - 40, 38);
    [native setTitle:@"查看原生面板中的其他操作  ›" forState:UIControlStateNormal];
    native.titleLabel.font = [UIFont systemFontOfSize:13];
    [native setTitleColor:[self subtleColor] forState:UIControlStateNormal];
    [native addTarget:self action:@selector(showOriginal) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:native];
    self.scroll.contentSize = CGSizeMake(width, y + 44);
}

#pragma mark - UI actions

- (void)quickTapped:(UIButton *)sender { [self modelTapped:sender]; }

- (void)modelTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 1000;
    if (index < 0 || index >= (NSInteger)self.actions.count) {
        [DYYYUtils showToast:@"当前视频未提供此操作"];
        return;
    }
    AWELongPressPanelBaseViewModel *model = self.actions[index];
    if (!model.action) {
        [self showOriginal];
        return;
    }
    void (^action)(void) = [model.action copy];
    [self removeOverlay];
    {
        // 宿主私有类静态引用会在链接期变成未定义符号，改为运行时查找
        Class dyyyPMC = NSClassFromString(@"AWELongPressPanelManager");
        id dyyyPM = [dyyyPMC performSelector:@selector(shareInstance)];
        SEL dyyySel = NSSelectorFromString(@"dismissWithAnimation:completion:");
        if ([dyyyPM respondsToSelector:dyyySel]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(dyyyPM, dyyySel, NO, nil);
        }
    }
    if (action) action();
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = sender.tag == 6001 ? @"DYYYEnableAutoPlay" : sender.tag == 6002 ? @"DYYYEnableBackgroundListen" : nil;
    if (!key) return;
    [DYYYSettingsHelper setUserDefaults:@(sender.on) forKey:key];
    [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:key isEnabled:sender.on];
}

- (void)speedTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 5000;
    NSArray<NSNumber *> *speeds = @[@0.5, @1.0, @1.5, @2.0];
    if (index < 0 || index >= (NSInteger)speeds.count) return;
    double speed = [speeds[index] doubleValue];

    // 与现有 DYYY.xm 的倍速按钮使用相同的播放控制器接口。
    // 不假定所有抖音版本都存在此私有方法。
    UIWindow *win = self.hostWindow;
    UIViewController *root = win.rootViewController;
    if (!root) { [DYYYUtils showToast:@"无法获取播放页面"]; return; }
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:root];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    BOOL applied = NO;
    NSUInteger scan = 0;
    while (scan < queue.count && scan < 400) {
        UIViewController *vc = queue[scan++];
        NSValue *key = [NSValue valueWithNonretainedObject:vc];
        if ([visited containsObject:key]) continue;
        [visited addObject:key];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
        if (vc.childViewControllers.count) [queue addObjectsFromArray:vc.childViewControllers];
        BOOL supportedClass = [vc isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] ||
                              [vc isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] ||
                              [vc isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")];
        SEL setRate = NSSelectorFromString(@"setVideoControllerPlaybackRate:");
        if (supportedClass && [vc respondsToSelector:setRate] && vc.isViewLoaded && vc.view.window) {
            ((void (*)(id, SEL, double))objc_msgSend)(vc, setRate, speed);
            applied = YES;
        }
    }
    if (!applied) {
        [DYYYUtils showToast:@"当前页面无法直接调速，请使用原生面板"];
        return;
    }
    self.selectedSpeed = speed;
    [self updateSpeedHighlight];
}

- (void)restoreNativeVisibility {
    if (self.originController) self.originController.view.hidden = NO;
}

- (void)showOriginal {
    if (self.showingNative) return;
    self.showingNative = YES;
    [self restoreNativeVisibility];
    [self removeOverlay];
}

- (void)closeAll {
    // 关掉覆盖面板和底层原生控制器，不让原生面板在退场时又闪一下。
    [self removeOverlay];
    {
        // 宿主私有类静态引用会在链接期变成未定义符号，改为运行时查找
        Class dyyyPMC = NSClassFromString(@"AWELongPressPanelManager");
        id dyyyPM = [dyyyPMC performSelector:@selector(shareInstance)];
        SEL dyyySel = NSSelectorFromString(@"dismissWithAnimation:completion:");
        if ([dyyyPM respondsToSelector:dyyySel]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(dyyyPM, dyyySel, NO, nil);
        }
    }
}

@end
