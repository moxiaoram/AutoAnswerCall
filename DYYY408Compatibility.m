#import "DYYY408Compatibility.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

// Only view *class names and counts* are collected; no text, account data,
// images, captions, messages or other user content are read or recorded.
static void DYYY408AppendViewClasses(NSMutableString *report) {
    NSMutableDictionary<NSString *, NSNumber *> *classes = [NSMutableDictionary dictionary];
    NSMutableArray<UIView *> *pending = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [pending addObject:window];
    }
    NSUInteger scanned = 0;
    while (pending.count && scanned < 6000) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        scanned++;
        NSString *name = NSStringFromClass([view class]);
        if ([name hasPrefix:@"AWE"] || [name hasPrefix:@"AWED"] ||
            [name hasPrefix:@"ACC"] || [name hasPrefix:@"DDanmaku"] ||
            [name hasPrefix:@"XIGDanmaku"]) {
            classes[name] = @([classes[name] unsignedIntegerValue] + 1);
        }
        [pending addObjectsFromArray:view.subviews];
    }
    [report appendFormat:@"\nVisible view class summary (class/count only, scanned up to 6000): %lu views\n",
        (unsigned long)scanned];
    NSArray<NSString *> *names = [[classes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        [report appendFormat:@"  %@ : %@\n", name, classes[name]];
    }
}

static void DYYY408WriteRuntimeReport(void) {
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    if (![bundle isEqualToString:@"com.ss.iphone.ugc.Aweme"] || ![version isEqualToString:@"40.8.0"]) {
        return;
    }

    // Candidate symbols from upstream DYYY. Presence means *only* that a symbol
    // exists at the time of inspection, not that its original semantics are unchanged.
    NSArray<NSDictionary<NSString *, id> *> *checks = @[
        @{@"class": @"AWESettingBaseViewController", @"methods": @[@"viewModel", @"useCardUIStyle"]},
        @{@"class": @"AWELeftSideBarTopIconHorizontalView", @"methods": @[@"didMoveToSuperview"]},
        @{@"class": @"AWELeftSideBarTopRightLayoutView", @"methods": @[@"didMoveToSuperview"]},
        @{@"class": @"AWEFeedTableViewController", @"methods": @[@"viewDidAppear:", @"viewWillDisappear:"]},
        @{@"class": @"AWEFeedContainerViewController", @"methods": @[@"viewDidAppear:", @"aweme:currentIndexDidChange:"]},
        @{@"class": @"AWEFeedTableViewCell", @"methods": @[@"setModel:", @"layoutSubviews"]},
        @{@"class": @"AWEFeedViewCell", @"methods": @[@"setModel:", @"layoutSubviews"]},
        @{@"class": @"AWEPlayInteractionProgressController", @"methods": @[@"updateProgressSliderWithTime:totalDuration:"]},
        @{@"class": @"AWEDProgressCoreContainer", @"methods": @[@"updateProgressSliderWithTime:totalDuration:"]},
        @{@"class": @"AWEModernLongPressPanelTableViewController", @"methods": @[@"dataArray", @"viewDidLoad"]},
        @{@"class": @"AWELongPressPanelTableViewController", @"methods": @[@"dataArray", @"viewDidLoad"]},
        @{@"class": @"AWEFeedTopBarContainer", @"methods": @[@"setAlpha:"]},
        @{@"class": @"AWEHPTopTabItemTextContentView", @"methods": @[@"layoutSubviews"]},
        @{@"class": @"AWEFeedProgressSlider", @"methods": @[@"setAlpha:"]},
        @{@"class": @"AWEFeedVideoButton", @"methods": @[@"touchUpInsideBlock"]},
        @{@"class": @"AWEElementStackView", @"methods": @[@"setAlpha:"]},
        @{@"class": @"AWEIMCustomMenuComponent", @"methods": @[]},
        @{@"class": @"AWEDPlayerProgressContainerView", @"methods": @[@"layoutSubviews"]},
        @{@"class": @"AWECommentInputViewSwiftImpl.CommentInputContainerView", @"methods": @[]},
        @{@"class": @"AWECommentPanelHeaderSwiftImpl.CommentHeaderGeneralView", @"methods": @[]}
    ];

    NSMutableString *report = [NSMutableString stringWithFormat:
        @"DYYY 40.8.0 runtime compatibility snapshot\nBundle: %@\nApp version: %@\n"
        @"Note: 'missing' may indicate a renamed or not-yet-loaded class; "
        @"'present' does not establish functional compatibility.\n\n", bundle, version];
    for (NSDictionary<NSString *, id> *item in checks) {
        NSString *name = item[@"class"];
        Class cls = objc_getClass(name.UTF8String);
        [report appendFormat:@"[%@] %@\n", cls ? @"present" : @"missing", name];
        if (cls) {
            for (NSString *method in item[@"methods"]) {
                BOOL found = class_getInstanceMethod(cls, NSSelectorFromString(method)) != NULL;
                [report appendFormat:@"  [%@] -%@\n", found ? @"present" : @"missing", method];
            }
        }
    }
    DYYY408AppendViewClasses(report);
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (caches.length == 0) { return; }
    NSString *path = [caches stringByAppendingPathComponent:@"DYYY-40.8.0-compat.txt"];
    NSError *error = nil;
    BOOL saved = [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    NSLog(@"[DYYY408] %@: %@", saved ? @"compatibility report" : @"could not save report", saved ? path : error);
}

void DYYY408ScheduleRuntimeCompatibilityReport(void) {
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    if (![bundle isEqualToString:@"com.ss.iphone.ugc.Aweme"] || ![version isEqualToString:@"40.8.0"]) {
        return;
    }
    // Run after app startup because some private classes are loaded lazily.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DYYY408WriteRuntimeReport();
    });
}
