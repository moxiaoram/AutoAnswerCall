#import "DYYYImmersivePlaybackManager.h"
#import "DYYYUtils.h"
#import "DYYYFloatClearButton.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>

static NSString *const kDYYYTimedImmersiveEnabledKey = @"DYYYAutoImmersivePlayback";
static NSString *const kDYYYTimedImmersiveDelayKey = @"DYYYImmersiveDelaySeconds";
static const NSTimeInterval kDYYYImmersiveFadeSeconds = 1.25;

@interface DYYYImmersivePlaybackManager ()
@property(nonatomic, assign, readwrite, getter=isImmersive) BOOL immersive;
@property(nonatomic, weak) UIViewController *feedController;
@property(nonatomic, weak) id progressSource;
@property(nonatomic, assign) NSTimeInterval watchedSeconds;
@property(nonatomic, assign) NSTimeInterval previousProgressUptime;
@property(nonatomic, assign) NSTimeInterval lastProgressCallbackUptime;
@property(nonatomic, assign) NSTimeInterval lastUIRefreshUptime;
@property(nonatomic, assign) CGFloat previousVideoTime;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *originalAlphas;
@end

@implementation DYYYImmersivePlaybackManager

+ (instancetype)sharedManager {
    static DYYYImmersivePlaybackManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _originalAlphas = [NSMapTable weakToStrongObjectsMapTable];
        _previousVideoTime = -1;
        __weak typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [weakSelf feedDidChange];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [weakSelf feedDidChange];
        }];
    }
    return self;
}

- (BOOL)featureEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDYYYTimedImmersiveEnabledKey];
}

- (NSTimeInterval)configuredDelay {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kDYYYTimedImmersiveDelayKey];
    double interval = value ? [value doubleValue] : 60.0;
    if (!isfinite(interval) || interval < 5) interval = 60.0;
    return MIN(interval, 3600.0);
}

- (void)attachToFeedController:(UIViewController *)controller {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self attachToFeedController:controller]; });
        return;
    }
    if (self.feedController != controller) {
        [self feedDidChange];
        self.feedController = controller;
    }
    if (![self featureEnabled] || !controller.isViewLoaded) return;

    UIView *view = controller.view;
    static const void *kDYYYImmersiveGesturesInstalledKey = &kDYYYImmersiveGesturesInstalledKey;
    if ([objc_getAssociatedObject(view, kDYYYImmersiveGesturesInstalledKey) boolValue]) return;
    objc_setAssociatedObject(view, kDYYYImmersiveGesturesInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dyyyTap:)];
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesBegan = NO;
    tap.delegate = self;
    [view addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dyyyPan:)];
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delegate = self;
    [view addGestureRecognizer:pan];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 不截断抖音原有的点击暂停、长按操作及上下滑切换视频。
    return YES;
}

- (void)dyyyTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateRecognized) [self userDidInteract];
}

- (void)dyyyPan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) [self userDidInteract];
}

- (void)detachFromFeedController:(UIViewController *)controller {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self detachFromFeedController:controller]; });
        return;
    }
    if (self.feedController == controller) {
        [self feedDidChange];
        self.feedController = nil;
    }
}

- (void)resetCounters {
    self.watchedSeconds = 0;
    self.previousProgressUptime = 0;
    self.lastProgressCallbackUptime = 0;
    self.previousVideoTime = -1;
    self.progressSource = nil;
}

- (void)feedDidChange {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self feedDidChange]; });
        return;
    }
    [self leaveImmersive];
    [self resetCounters];
}

- (void)userDidInteract {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self userDidInteract]; });
        return;
    }
    [self leaveImmersive];
    [self resetCounters];
}

- (BOOL)canCountPlayback {
    if (![self featureEnabled]) return NO;
    UIViewController *feed = self.feedController;
    if (!feed || !feed.isViewLoaded || !feed.view.window) return NO;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive || isAppInTransition) return NO;
    // 评论页、设置页和其他模态浮层出现时不要突然进入沉浸式。
    if (feed.presentedViewController || feed.navigationController.presentedViewController) return NO;
    return YES;
}

- (void)recordPlaybackTime:(CGFloat)seconds duration:(CGFloat)duration source:(id)source {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self recordPlaybackTime:seconds duration:duration source:source]; });
        return;
    }
    if (![self canCountPlayback]) {
        if (self.immersive || self.watchedSeconds > 0 || self.previousProgressUptime > 0) {
            [self feedDidChange];
        }
        return;
    }
    if (!isfinite(seconds) || seconds < 0 || !isfinite(duration) || duration <= 0) return;

    NSTimeInterval now = CACurrentMediaTime();
    if (self.progressSource && self.progressSource != source) {
        // 同一帧可能经过新、旧两个进度组件；只取当前活跃的一个。
        if (now - self.lastProgressCallbackUptime < 2.0) return;
        self.previousProgressUptime = 0;
        self.previousVideoTime = -1;
    }
    self.progressSource = source;
    self.lastProgressCallbackUptime = now;

    if (self.previousProgressUptime > 0 && self.previousVideoTime >= 0) {
        CGFloat movement = seconds - self.previousVideoTime;
        NSTimeInterval wallDelta = now - self.previousProgressUptime;
        if (movement > 4.0 && wallDelta < 2.0) {
            // 拖动进度条的跳播不算观看时间。
            [self userDidInteract];
        } else if (movement > 0.0005 && wallDelta > 0 && wallDelta <= 2.5) {
            // 只累积视频真实推进的墙上时间；暂停/卡顿时计数不变。
            // 避免页面切换或回调停顿产生的巨大一次性跳变。
            self.watchedSeconds += MIN(wallDelta, 1.25);
        }
        // movement < 0 可能是正常循环播放：保留累积观看时长。
    }
    self.previousProgressUptime = now;
    self.previousVideoTime = seconds;

    if (!self.immersive && self.watchedSeconds >= [self configuredDelay]) {
        [self enterImmersive];
    } else if (self.immersive && now - self.lastUIRefreshUptime >= 1.5) {
        self.lastUIRefreshUptime = now;
        [self refreshImmersiveElements];
    }
}

- (BOOL)matchesImmersiveUI:(UIView *)view {
    // 仅隐藏控件容器；绝不隐藏播放器/视频渲染层、视频 cell 或整块 feed。
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[
            @"AWENormalModeTabBar", @"AWEHPTopBarCTAContainer", @"AWEHPSegmentControlScrollView",
            @"AWEHPDiscoverFeedEntranceView", @"AWELeftSideBarEntranceView", @"AWEFeedTopBarContainer",
            @"AWEBaseElementView", @"AWEElementStackView", @"AWEPlayInteractionDescriptionLabel",
            @"AWEUserNameLabel", @"AWEFeedProgressSlider", @"AWEStoryProgressContainerView",
            @"AWEPlayInteractionProgressContainerView", @"AWEHotSearchInnerBottomView",
            @"AWESearchFeedTagView", @"AWEPlayInteractionSearchAnchorView",
            @"AWEFeedAnchorContainerView", @"AWELandscapeFeedEntryView"
        ]];
    });
    return [names containsObject:NSStringFromClass(view.class)];
}

- (void)captureAndFadeViewsFrom:(UIView *)root depth:(NSInteger)depth {
    if (!root || depth > 30) return;
    if ([self matchesImmersiveUI:root]) {
        if (![self.originalAlphas objectForKey:root]) {
            [self.originalAlphas setObject:@(root.alpha) forKey:root];
        }
        root.alpha = 0;
        // 该容器的子控件一起淡出，不必重复记录。
        return;
    }
    for (UIView *subview in root.subviews) [self captureAndFadeViewsFrom:subview depth:depth + 1];
}

- (void)refreshImmersiveElements {
    if (!self.immersive || !self.feedController.view.window) return;
    UIWindow *window = self.feedController.view.window;
    [UIView animateWithDuration:0.35 animations:^{
        [self captureAndFadeViewsFrom:window depth:0];
    }];
}

- (void)invalidateVideoAndTabLayoutsInView:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 25) return;
    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"AWEFeedTableView"] ||
        [className isEqualToString:@"AWENormalModeTabBar"]) {
        [view setNeedsLayout];
        [view.superview setNeedsLayout];
    }
    for (UIView *subview in view.subviews) {
        [self invalidateVideoAndTabLayoutsInView:subview depth:depth + 1];
    }
}

- (void)refreshStatusBarAndLayout {
    UIViewController *controller = self.feedController;
    if (!controller) return;
    UIWindow *window = controller.view.window;
    [controller setNeedsStatusBarAppearanceUpdate];
    [window.rootViewController setNeedsStatusBarAppearanceUpdate];
    [self invalidateVideoAndTabLayoutsInView:window depth:0];
    [controller.view setNeedsLayout];
    [controller.view.superview setNeedsLayout];
    [window setNeedsLayout];
    [window layoutIfNeeded];
}

- (void)enterImmersive {
    if (self.immersive || ![self canCountPlayback]) return;
    self.immersive = YES;
    self.lastUIRefreshUptime = CACurrentMediaTime();
    [UIView animateWithDuration:kDYYYImmersiveFadeSeconds
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        [self captureAndFadeViewsFrom:self.feedController.view.window depth:0];
        [self refreshStatusBarAndLayout];
    } completion:nil];
}

- (void)leaveImmersive {
    if (!self.immersive) return;
    self.immersive = NO;
    NSMapTable<UIView *, NSNumber *> *saved = self.originalAlphas;
    self.originalAlphas = [NSMapTable weakToStrongObjectsMapTable];
    [UIView animateWithDuration:0.23
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        for (UIView *view in saved.keyEnumerator) {
            NSNumber *original = [saved objectForKey:view];
            if (view && original) view.alpha = original.doubleValue;
        }
        [self refreshStatusBarAndLayout];
    } completion:nil];
}

@end
