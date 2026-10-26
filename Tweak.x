#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "AACGlobalLogger.h"

// AutoAnswerCall: uses the TelephonyUtilities call-center API dynamically.
// This source is not a claim that the private API has been verified on-device.
static NSString * const kAACDomain = @"com.autoanswer.call";
static NSString * const kAACSharedDir = @"/var/jb/Library/Application Support/AutoAnswerCall";
static NSString *AACLastScheduledToken = nil;
static NSString *AACLastAnsweredToken = nil;
static BOOL AACTimerRunning = NO;
static BOOL AACLoggedCallCenterUnavailable = NO;
static id AACUplinkPlayer = nil; // Must be a TrollRecorder TRAudioPlayer instance, not plain AVAudioPlayer.
static NSString * const kAACStopUplinkNotification = @"com.autoanswer.call.stopUplinkPlayback";
static NSString * const kAACBridgePlayNotification = @"com.autoanswer.call.trBridgePlay";
static NSString * const kAACBridgeStopNotification = @"com.autoanswer.call.trBridgeStop";
static NSString * const kAACBridgeCommandPath = @"/var/mobile/Library/AutoAnswerAudio/tr-bridge-command.plist";
static NSString *AACLastTRBridgeCommandID = nil;

static NSDictionary *AACPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAACDomain);
    CFPropertyListRef value = CFPreferencesCopyMultiple(NULL, (__bridge CFStringRef)kAACDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!value) return @{};
    id obj = CFBridgingRelease(value);
    return [obj isKindOfClass:NSDictionary.class] ? obj : @{};
}
static BOOL AACEnabled(void) {
    NSDictionary *p = AACPrefs();
    return [p[@"Enabled"] respondsToSelector:@selector(boolValue)] ? [p[@"Enabled"] boolValue] : YES;
}
static BOOL AACAutoAnswerEnabled(void) {
    NSDictionary *p = AACPrefs();
    return [p[@"AutoAnswer"] respondsToSelector:@selector(boolValue)] ? [p[@"AutoAnswer"] boolValue] : NO;
}
static NSTimeInterval AACDelay(void) {
    id v = AACPrefs()[@"Delay"];
    return v ? MAX(0.0, MIN([v doubleValue], 60.0)) : 0.5;
}
static id AACSend(id target, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}
static void AACStopUplinkAudio(void) {
    id player = AACUplinkPlayer;
    if (!player) {
        AACLog(@"停止请求收到，但当前没有 TRAudioPlayer 上行播放器实例");
        return;
    }
    @try {
        SEL stopSel = NSSelectorFromString(@"stop");
        SEL mixSel = NSSelectorFromString(@"setMixToUplink:");
        if ([player respondsToSelector:stopSel]) {
            ((void (*)(id, SEL))objc_msgSend)(player, stopSel);
            AACLog(@"已向 TRAudioPlayer 发送 stop");
        } else {
            AACLog(@"停止失败：播放器实例不响应 stop");
        }
        if ([player respondsToSelector:mixSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, NO);
            AACLog(@"已向 TRAudioPlayer 发送 setMixToUplink:NO");
        } else {
            AACLog(@"播放器实例不响应 setMixToUplink:，无法确认上行混音已关闭");
        }
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"停止上行播放异常：%@", e.reason ?: @"unknown"]);
    }
    AACUplinkPlayer = nil;
}

// TrollRecorder bridge based on the recovered in-process call chain:
// TRRecordingManager + sharedManager -> session ->
// playCustomAudioWithContentsOfFile:rate:volume:repeat:
// This runs only inside TRCallMonitor; SpringBoard writes a command file and posts a Darwin notification.
static void AACPostDarwinNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)name, NULL, NULL, true);
}

static BOOL AACWriteTRBridgeCommand(NSString *action, NSString *path) {
    NSString *directory = [kAACBridgeCommandPath stringByDeletingLastPathComponent];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:&error];
    if (error) {
        AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 创建目录失败：%@", error.localizedDescription ?: @"unknown"]);
        return NO;
    }
    NSMutableDictionary *command = [@{
        @"id": [[NSUUID UUID] UUIDString],
        @"action": action ?: @"play",
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"rate": @1.0,
        @"volume": @1.0,
        @"repeat": @NO
    } mutableCopy];
    if (path.length) command[@"path"] = path;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:command
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0 error:&error];
    if (!data || ![data writeToFile:kAACBridgeCommandPath options:NSDataWritingAtomic error:&error]) {
        AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 写入命令失败：%@", error.localizedDescription ?: @"unknown"]);
        return NO;
    }
    return YES;
}

static id AACTRSharedManager(void) {
    Class cls = objc_getClass("TRRecordingManager");
    if (!cls) return nil;
    SEL shared = NSSelectorFromString(@"sharedManager");
    if (![cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
}

static void AACHandleTRBridgeCommand(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"TRCallMonitor"]) return;
    NSDictionary *command = [NSDictionary dictionaryWithContentsOfFile:kAACBridgeCommandPath];
    if (![command isKindOfClass:NSDictionary.class]) {
        AACLog(@"TRCallMonitor bridge 收到通知，但没有可读命令文件");
        return;
    }
    NSString *commandID = [command[@"id"] isKindOfClass:NSString.class] ? command[@"id"] : nil;
    if (commandID.length && [commandID isEqualToString:AACLastTRBridgeCommandID]) return;
    NSTimeInterval createdAt = [command[@"createdAt"] doubleValue];
    if (createdAt <= 0 || fabs([[NSDate date] timeIntervalSince1970] - createdAt) > 30.0) {
        AACLog(@"TRCallMonitor bridge 忽略超过 30 秒的过期命令");
        return;
    }
    NSString *action = [command[@"action"] isKindOfClass:NSString.class] ? command[@"action"] : @"play";
    id manager = AACTRSharedManager();
    id session = AACSend(manager, @"session");
    if (!session) {
        AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 无活动 session；action=%@ manager=%@，稍后重试", action, manager ? @"present" : @"absent"]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AACHandleTRBridgeCommand(); });
        return;
    }
    if (commandID.length) AACLastTRBridgeCommandID = [commandID copy];
    @try {
        if ([action isEqualToString:@"stop"]) {
            SEL stopSel = NSSelectorFromString(@"terminateBackgroundAudioIfNeeded");
            if ([session respondsToSelector:stopSel]) {
                ((void (*)(id, SEL))objc_msgSend)(session, stopSel);
                AACLog(@"TRCallMonitor bridge 已向活动 session 发送 terminateBackgroundAudioIfNeeded");
            } else {
                AACLog(@"TRCallMonitor bridge session 不响应 terminateBackgroundAudioIfNeeded");
            }
            return;
        }

        NSString *path = [command[@"path"] isKindOfClass:NSString.class] ? command[@"path"] : nil;
        BOOL isDirectory = NO;
        if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 音频路径无效：%@", path ?: @"(empty)"]);
            return;
        }
        SEL playSel = NSSelectorFromString(@"playCustomAudioWithContentsOfFile:rate:volume:repeat:");
        if (![session respondsToSelector:playSel]) {
            AACLog(@"TRCallMonitor bridge 活动 session 不响应已确认的播放 selector");
            return;
        }
        float rate = [command[@"rate"] respondsToSelector:@selector(floatValue)] ? [command[@"rate"] floatValue] : 1.0f;
        float volume = [command[@"volume"] respondsToSelector:@selector(floatValue)] ? [command[@"volume"] floatValue] : 1.0f;
        BOOL repeat = [command[@"repeat"] respondsToSelector:@selector(boolValue)] ? [command[@"repeat"] boolValue] : NO;
        rate = fmaxf(0.1f, fminf(rate, 2.0f));
        volume = fmaxf(0.0f, fminf(volume, 1.0f));
        ((void (*)(id, SEL, id, float, float, BOOL))objc_msgSend)(session, playSel, path, rate, volume, repeat);
        AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 已调用 session 播放入口：%@ rate=%.2f volume=%.2f repeat=%d；仍需真机确认对端可听", path.lastPathComponent, rate, volume, repeat]);
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"TRCallMonitor bridge 调用异常：%@", e.reason ?: @"unknown"]);
    }
}

static void AACTRBridgeNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ AACHandleTRBridgeCommand(); });
}

__attribute__((unused)) static void AACRequestTRBridgePlay(NSString *path) {
    if (AACWriteTRBridgeCommand(@"play", path)) {
        AACLog(@"已写入 TRCallMonitor 播放请求并发送 Darwin 通知；等待 helper 处理结果");
        AACPostDarwinNotification(kAACBridgePlayNotification);
    }
}

static void AACRequestTRBridgeStop(void) {
    if (AACWriteTRBridgeCommand(@"stop", nil)) {
        AACLog(@"已写入 TRCallMonitor 停止请求并发送 Darwin 通知");
        AACPostDarwinNotification(kAACBridgeStopNotification);
    }
}

// ---------------------------------------------------------------------------
// 上行音频：使用系统 AVSpeechUtterance 的私有 mixToTelephonyUplink 能力。
// 依据：dyld 共享缓存中确认存在 _mixToTelephonyUplink / setMixToUplink:，
// 归属 AVSpeechUtterance（同区还有 _speechString、_preUtteranceDelay、pitchMultiplier）。
// 该接口把“合成语音”送入通话上行，因此对方听到的是 TTS 朗读内容，
// 而不是原始音频文件字节。这是当前系统实际提供的能力。
// ---------------------------------------------------------------------------
static AVSpeechSynthesizer *AACSpeechSynth = nil;
static AVSpeechUtterance *AACCurrentUtterance = nil;
static volatile BOOL AACUplinkLooping = NO;   // 用户未按停止按钮时保持循环
static volatile BOOL AACUserStopped = NO;     // 用户按下停止按钮

@interface AACSpeechDelegate : NSObject <AVSpeechSynthesizerDelegate>
@end
@implementation AACSpeechDelegate
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!AACUplinkLooping || AACUserStopped) {
        AACLog(@"上行：单次朗读结束，循环已关闭");
        return;
    }
    // 循环：稍作间隔后重复播放同一段文本
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!AACUplinkLooping || AACUserStopped) return;
        @try {
            AVSpeechUtterance *again = [AVSpeechUtterance speechUtteranceWithString:utterance.speechString ?: @""];
            [self applyUplink:again];
            [synth speakUtterance:again];
            AACLog(@"上行：循环播放下一轮");
        } @catch (NSException *e) {
            AACLog([NSString stringWithFormat:@"上行：循环异常 %@", e.reason ?: @""]);
        }
    });
}
- (void)applyUplink:(AVSpeechUtterance *)u {
    SEL sel = NSSelectorFromString(@"setMixToTelephonyUplink:");
    if ([u respondsToSelector:sel]) {
        @try { ((void (*)(id, SEL, BOOL))objc_msgSend)(u, sel, YES); } @catch (NSException *e) {}
    }
}
@end
static AACSpeechDelegate *AACSpeechDelegateInstance = nil;

static BOOL AACUtteranceSupportsUplink(void) {
    Class cls = NSClassFromString(@"AVSpeechUtterance");
    if (!cls) return NO;
    SEL sel = NSSelectorFromString(@"setMixToTelephonyUplink:");
    return [cls instancesRespondToSelector:sel];
}

static BOOL AACEnableUplinkOnUtterance(AVSpeechUtterance *utterance) {
    if (!utterance) return NO;
    SEL sel = NSSelectorFromString(@"setMixToTelephonyUplink:");
    Method m = class_getInstanceMethod([utterance class], sel);
    if (!m) { AACLog(@"上行：AVSpeechUtterance 没有 setMixToTelephonyUplink:，无法注入上行"); return NO; }
    unsigned int argc = method_getNumberOfArguments(m);
    char argType[16] = {0};
    if (argc >= 3) method_getArgumentType(m, 2, argType, sizeof(argType));
    AACLog([NSString stringWithFormat:@"上行：setMixToTelephonyUplink: 参数数=%u 第2参数类型=%s", argc, argc >= 3 ? argType : "?"]);
    if (argc != 3) { AACLog(@"上行：ABI 不符合预期（期望 2 个隐式参数 + 1 个 BOOL），不调用"); return NO; }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(utterance, sel, YES);
        return YES;
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"上行：调用 setMixToTelephonyUplink: 异常：%@", e.reason ?: @"unknown"]);
        return NO;
    }
}

// 从音频文件路径推导一段可朗读的文本：优先读同名 .txt 旁注，否则用文件名。
static NSString *AACSpeechTextForPath(NSString *path) {
    if (!path.length) return nil;
    NSString *sidecar = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"txt"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sidecar]) {
        NSString *t = [NSString stringWithContentsOfFile:sidecar encoding:NSUTF8StringEncoding error:nil];
        if (t.length) { AACLog([NSString stringWithFormat:@"上行：使用旁注文本 %@", sidecar.lastPathComponent]); return t; }
    }
    NSString *fallback = AACPrefs()[@"SpeechText"];
    if ([fallback isKindOfClass:NSString.class] && fallback.length) return fallback;
    return nil;
}

static void AACStartUplinkAudio(void) {
    if (!AACEnabled() || ![AACPrefs()[@"PlayAudio"] boolValue]) {
        AACLog([NSString stringWithFormat:@"上行播放未启动：Enabled=%d PlayAudio=%d", AACEnabled(), [AACPrefs()[@"PlayAudio"] boolValue]]);
        return;
    }

    if (!AACUtteranceSupportsUplink()) {
        AACLog(@"上行：本系统 AVSpeechUtterance 不支持 setMixToTelephonyUplink:，放弃上行注入");
        return;
    }

    NSString *text = AACSpeechTextForPath(AACPrefs()[@"AudioFilePath"]);
    if (!text.length) {
        AACLog(@"上行：没有可朗读的文本。请设置“朗读文本(SpeechText)”或在音频同目录放同名 .txt 旁注文件。");
        return;
    }

    @try {
        AACSpeechSynth = [AVSpeechSynthesizer new];
        AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
        BOOL mixed = AACEnableUplinkOnUtterance(u);
        AACLog([NSString stringWithFormat:@"上行：准备朗读 %lu 字，mixToTelephonyUplink=%d", (unsigned long)text.length, mixed]);
        AACCurrentUtterance = u;
        AACUserStopped = NO;
        AACUplinkLooping = YES;
        if (!AACSpeechDelegateInstance) AACSpeechDelegateInstance = [AACSpeechDelegate new];
        AACSpeechSynth.delegate = AACSpeechDelegateInstance;
        [AACSpeechSynth speakUtterance:u];
        AACLog(@"上行：已调用 speakUtterance（对方是否能听到需实际通话验证）");
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"上行：朗读异常：%@", e.reason ?: @"unknown"]);
    }
}

static void AACStopUplinkAudioTTS(void) {
    AACUserStopped = YES;
    AACUplinkLooping = NO;
    AACLog(@"上行：收到停止请求，结束循环并把麦克风交还人工");
    @try {
        if (AACSpeechSynth && AACSpeechSynth.isSpeaking) {
            [AACSpeechSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
            AACLog(@"上行：已停止朗读");
        }
        AACSpeechSynth = nil;
        AACCurrentUtterance = nil;
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"上行：停止异常：%@", e.reason ?: @"unknown"]);
    }
}


// ---------------------------------------------------------------------------
// 通话界面：把静音按钮替换为“停止”按钮（运行时发现，不写死类名）
// 目标进程：com.apple.InCallService
// 找到 PHInCallRootViewController / PHAudioCallViewController 的视图后，
// 在通话控制按钮行插入一个“停止”按钮；点击后停止上行播放并交还麦克风。
// ---------------------------------------------------------------------------
static UIButton *AACStopButton = nil;

@interface AACStopButtonTarget : NSObject
+ (instancetype)shared;
- (void)tapped;
@end

static void AACStopButtonTapped(void) {
    AACLog(@"通话界面：用户按下停止按钮，停止上行播放并交还麦克风");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kAACStopUplinkNotification, NULL, NULL, true);
    AACStopUplinkAudioTTS();
    dispatch_async(dispatch_get_main_queue(), ^{
        AACStopButton.enabled = NO;
        [AACStopButton setTitle:@"已停止" forState:UIControlStateNormal];
        AACStopButton.alpha = 0.5;
    });
}

static void AACInstallStopButtonInView(UIView *root) {
    if (!root || AACStopButton.superview) return;
    // 找一个合适的容器：优先通话控制按钮所在的 UIStackView
    __block UIStackView *target = nil;
    __block NSUInteger best = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (queue.count && visited < 3000) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0]; visited++;
        if ([v isKindOfClass:UIStackView.class]) {
            UIStackView *sv = (UIStackView *)v;
            NSUInteger controls = 0;
            for (UIView *c in sv.arrangedSubviews) if ([c isKindOfClass:UIControl.class]) controls++;
            if (controls >= 2 && controls > best) { best = controls; target = sv; }
        }
        for (UIView *c in v.subviews) [queue addObject:c];
    }
    if (!target) { AACLog(@"通话界面：未找到按钮容器，跳过停止按钮注入"); return; }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"停止" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0];
    btn.layer.cornerRadius = 32;
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [btn.widthAnchor constraintEqualToConstant:64].active = YES;
    [btn.heightAnchor constraintEqualToConstant:64].active = YES;
    [btn addTarget:[AACStopButtonTarget shared] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [target addArrangedSubview:btn];
    AACStopButton = btn;
    AACLog([NSString stringWithFormat:@"通话界面：已插入停止按钮（容器控件数=%lu，遍历节点=%lu）", (unsigned long)best, (unsigned long)visited]);
}

@implementation AACStopButtonTarget
+ (instancetype)shared { static AACStopButtonTarget *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [self new]; }); return s; }
- (void)tapped { AACStopButtonTapped(); }
@end

static void AACScanForInCallUI(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.isKeyWindow) continue;
            UIViewController *vc = w.rootViewController;
            NSMutableArray *stack = [NSMutableArray arrayWithObject:vc];
            NSUInteger n = 0;
            while (stack.count && n++ < 500) {
                UIViewController *c = stack.firstObject; [stack removeObjectAtIndex:0];
                NSString *cls = NSStringFromClass(c.class);
                if ([cls containsString:@"InCall"] || [cls containsString:@"CallView"]) {
                    if (c.viewIfLoaded && !AACStopButton.superview) {
                        AACInstallStopButtonInView(c.viewIfLoaded);
                    }
                }
                for (UIViewController *ch in c.childViewControllers) [stack addObject:ch];
                if (c.presentedViewController) [stack addObject:c.presentedViewController];
            }
        }
    }
}

static void AACStopUplinkNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AACStopUplinkAudio();
        AACStopUplinkAudioTTS();
        if ([NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) AACRequestTRBridgeStop();
    });
}

static NSString *AACCallToken(id call) {
    id uuid = AACSend(call, @"callUUID");
    if ([uuid respondsToSelector:@selector(UUIDString)]) return [uuid UUIDString];
    if ([uuid isKindOfClass:NSString.class] && [uuid length]) return uuid;
    return [NSString stringWithFormat:@"ptr:%p", call];
}
static BOOL AACShouldSkipNumber(id call) {
    NSString *number = nil;
    for (NSString *key in @[@"phoneNumber", @"address", @"remoteAddress", @"callerNumber", @"destinationID"]) {
        id value = AACSend(call, key);
        if ([value isKindOfClass:NSString.class] && [value length]) { number = value; break; }
    }
    if (!number.length) return NO;
    id raw = AACPrefs()[@"ExcludedNumbers"];
    if (![raw isKindOfClass:NSString.class]) raw = AACPrefs()[@"Whitelist"]; // backward compatibility
    if (![raw isKindOfClass:NSString.class] || ![raw length]) return NO;
    for (NSString *item in [raw componentsSeparatedByString:@","]) {
        NSString *needle = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (needle.length && [number containsString:needle]) return YES;
    }
    return NO;
}
static id AACCallCenter(void) {
    Class cls = objc_getClass("TUCallCenter");
    if (!cls) {
        // SpringBoard normally has TelephonyUtilities loaded. Avoid hard-linking a private framework.
        dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_LAZY | RTLD_LOCAL);
        cls = objc_getClass("TUCallCenter");
    }
    if (!cls) { if (!AACLoggedCallCenterUnavailable) { AACLog(@"TUCallCenter 类不存在；暂时停止接听尝试"); AACLoggedCallCenterUnavailable = YES; } return nil; }
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (![cls respondsToSelector:shared]) { if (!AACLoggedCallCenterUnavailable) { AACLog(@"TUCallCenter.sharedInstance 不存在；暂时停止接听尝试"); AACLoggedCallCenterUnavailable = YES; } return nil; }
    id center = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (center) AACLoggedCallCenterUnavailable = NO;
    return center;
}
static void AACPollIncomingCall(void);
static void AACStartPolling(void) {
    if (AACTimerRunning) return;
    AACTimerRunning = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ AACPollIncomingCall(); });
}
static void AACPollIncomingCall(void) {
    @autoreleasepool {
        if (!AACEnabled() || !AACAutoAnswerEnabled()) {
            AACLastScheduledToken = nil;
            AACLastAnsweredToken = nil;
        } else {
            id center = AACCallCenter();
            id call = AACSend(center, @"incomingCall");
            if (!call) {
                AACLastScheduledToken = nil;
                AACLastAnsweredToken = nil;
            } else {
                NSString *token = AACCallToken(call);
                if (![token isEqualToString:AACLastScheduledToken] && ![token isEqualToString:AACLastAnsweredToken]) {
                    if (AACShouldSkipNumber(call)) {
                        AACLog([NSString stringWithFormat:@"来电号码命中排除列表，跳过自动接听：%@", token]);
                        AACLastScheduledToken = token;
                    } else {
                        AACLastScheduledToken = [token copy];
                        NSTimeInterval delay = AACDelay();
                        AACLog([NSString stringWithFormat:@"检测到 TUCallCenter.incomingCall，%.2f 秒后尝试 answerCall:", delay]);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            if (!AACEnabled() || !AACAutoAnswerEnabled()) return;
                            id freshCenter = AACCallCenter();
                            id freshCall = AACSend(freshCenter, @"incomingCall");
                            if (!freshCall || ![[AACCallToken(freshCall) description] isEqualToString:token]) {
                                AACLog(@"延迟结束时来电已变化，取消接听");
                                return;
                            }
                            SEL answer = NSSelectorFromString(@"answerCall:");
                            if (![freshCenter respondsToSelector:answer]) {
                                AACLog(@"当前 TUCallCenter 不支持 answerCall:，未调用其他猜测接口");
                                return;
                            }
                            ((void (*)(id, SEL, id))objc_msgSend)(freshCenter, answer, freshCall);
                            AACLastAnsweredToken = [token copy];
                            AACLog([NSString stringWithFormat:@"已向 TUCallCenter 发送 answerCall:，等待设备验证：%@", token]);
                            if ([AACPrefs()[@"PlayAudio"] boolValue]) {
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    AACStartUplinkAudio();
                                });
                            }
                        });
                    }
                }
            }
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AACPollIncomingCall(); });
}


// ---------------------------------------------------------------------------
// 上行接口探针：枚举全系统类，找出真正响应上行混音 selector 的类。
// 目的：一次运行就能确定 iOS 17.3 上是否存在可用的第三方上行注入能力，
// 而不是靠猜 selector 归属。结果写入日志，同时输出到独立文件便于取证。
// ---------------------------------------------------------------------------
static void AACUplinkProbe(void) {
    NSArray<NSString *> *selectors = @[
        @"setMixToTelephonyUplink:",
        @"setMixToUplink:",
        @"mixToTelephonyUplink",
        @"mixToUplink"
    ];

    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"===== 上行接口探针 %@ =====\n", NSDate.date];
    [report appendFormat:@"进程=%@ bundle=%@\n", NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleIdentifier ?: @"?"];

    int totalClasses = objc_getClassList(NULL, 0);
    if (totalClasses <= 0) { AACLog(@"探针：objc_getClassList 返回 0，无法枚举"); return; }
    Class *classes = (Class *)malloc(sizeof(Class) * totalClasses);
    totalClasses = objc_getClassList(classes, totalClasses);
    [report appendFormat:@"枚举类总数=%d\n", totalClasses];

    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (int i = 0; i < totalClasses; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        NSString *name = NSStringFromClass(cls);
        if (!name.length) continue;

        for (NSString *selName in selectors) {
            SEL sel = NSSelectorFromString(selName);
            if (!sel) continue;
            // 实例方法
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                unsigned int argc = method_getNumberOfArguments(m);
                char rt[32] = {0};
                method_getReturnType(m, rt, sizeof(rt));
                char a2[16] = {0};
                if (argc >= 3) method_getArgumentType(m, 2, a2, sizeof(a2));
                NSString *line = [NSString stringWithFormat:@"[实例] %@ - %@ args=%u ret=%s arg2=%s",
                                  name, selName, argc, rt, argc >= 3 ? a2 : "-"];
                [hits addObject:line];
                AACLog([NSString stringWithFormat:@"探针命中：%@", line]);
                break;
            }
            // 类方法
            Method cm = class_getClassMethod(cls, sel);
            if (cm) {
                NSString *line = [NSString stringWithFormat:@"[类] %@ + %@", name, selName];
                [hits addObject:line];
                AACLog([NSString stringWithFormat:@"探针命中：%@", line]);
                break;
            }
        }
    }
    free(classes);

    if (hits.count == 0) {
        [report appendString:@"结果：全系统无任何类响应上述 selector。\n"];
        [report appendString:@"结论：iOS 17.3 未向第三方提供可用的上行注入 selector（或需要私有 entitlement）。\n"];
        AACLog(@"探针：全系统无任何类响应上行 selector —— 第三方上行注入不可用");
    } else {
        [report appendFormat:@"结果：命中 %lu 个：\n", (unsigned long)hits.count];
        for (NSString *h in hits) [report appendFormat:@"  %@\n", h];
        AACLog([NSString stringWithFormat:@"探针：共命中 %lu 个类", (unsigned long)hits.count]);
    }

    // 同时检查 AVSpeechUtterance 实际可用方法（便于对照）
    Class ut = NSClassFromString(@"AVSpeechUtterance");
    if (ut) {
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(ut, &mc);
        [report appendFormat:@"\nAVSpeechUtterance 方法数=%u，含 mix/speech/uplink 的：\n", mc];
        for (unsigned int i = 0; i < mc; i++) {
            NSString *sn = NSStringFromSelector(method_getName(ms[i]));
            NSString *low = sn.lowercaseString;
            if ([low containsString:@"mix"] || [low containsString:@"uplink"] || [low containsString:@"speech"]) {
                [report appendFormat:@"  %@\n", sn];
            }
        }
        free(ms);
    }

    NSString *path = [kAACSharedDir stringByAppendingPathComponent:@"uplink-probe.txt"];
    [[NSFileManager defaultManager] createDirectoryAtPath:kAACSharedDir withIntermediateDirectories:YES attributes:nil error:nil];
    [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    AACLog([NSString stringWithFormat:@"探针报告已写入 %@", path]);
}

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName ?: @"";
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([process isEqualToString:@"TRCallMonitor"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACTRBridgeNotificationCallback, (__bridge CFStringRef)kAACBridgePlayNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACTRBridgeNotificationCallback, (__bridge CFStringRef)kAACBridgeStopNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            AACLog(@"AutoAnswerAudio v1.9.2 实验桥已在 TRCallMonitor 加载；使用已反汇编确认的 TRRecordingManager/session 播放入口");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AACHandleTRBridgeCommand(); });
            return;
        }
        // 通话界面进程：负责接管通话界面按钮
        if ([bundle isEqualToString:@"com.apple.InCallService"] || [process isEqualToString:@"InCallService"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACStopUplinkNotificationCallback, (__bridge CFStringRef)kAACStopUplinkNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            AACLog(@"AutoAnswerAudio 已在 InCallService 加载：将把通话界面按钮替换为停止按钮");
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { AACScanForInCallUI(); }];
            });
            return;
        }
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACStopUplinkNotificationCallback, (__bridge CFStringRef)kAACStopUplinkNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        AACLog(@"AutoAnswerAudio v1.9.2 已在 SpringBoard 加载");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AACUplinkProbe(); });
        AACStartPolling();
    }
}
