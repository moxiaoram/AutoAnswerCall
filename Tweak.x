#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import "AACGlobalLogger.h"

// AutoAnswerCall: uses the TelephonyUtilities call-center API dynamically.
// This source is not a claim that the private API has been verified on-device.
static NSString * const kAACDomain = @"com.autoanswer.call";
static NSString * const kAACSharedDir = @"/var/jb/Library/Application Support/AutoAnswerCall";
static NSString *AACLastScheduledToken = nil;
static NSString *AACLastAnsweredToken = nil;
static BOOL AACTimerRunning = NO;
static BOOL AACLoggedCallCenterUnavailable = NO;
static AVAudioPlayer *AACUplinkPlayer = nil;
static NSString * const kAACStopUplinkNotification = @"com.autoanswer.call.stopUplinkPlayback";

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
    AVAudioPlayer *player = AACUplinkPlayer;
    if (!player) { AACLog(@"停止请求收到，但当前没有上行播放器实例"); return; }
    @try {
        [player stop];
        SEL mixSel = NSSelectorFromString(@"setMixToUplink:");
        if ([player respondsToSelector:mixSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, NO);
            AACLog(@"已向 AVAudioPlayer 发送 stop 与 setMixToUplink:NO");
        } else {
            AACLog(@"播放器不支持 setMixToUplink:；已调用 stop，但上行混音状态无法确认");
        }
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"停止上行播放异常：%@", e.reason ?: @"unknown"]);
    }
    AACUplinkPlayer = nil;
}

static void AACStartUplinkAudio(void) {
    if (!AACEnabled() || ![AACPrefs()[@"PlayAudio"] boolValue]) {
        AACLog(@"上行播放未启动：插件或自动播放开关未启用");
        return;
    }
    NSString *path = AACPrefs()[@"AudioFilePath"];
    if (![path isKindOfClass:NSString.class] || path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        AACLog([NSString stringWithFormat:@"上行播放失败：音频文件路径无效：%@", path ?: @"(empty)"]);
        return;
    }
    AACStopUplinkAudio();
    SEL initSel = NSSelectorFromString(@"initWithContentsOfURL:usesSharedAudioSession:error:");
    SEL mixSel = NSSelectorFromString(@"setMixToUplink:");
    if (![AVAudioPlayer instancesRespondToSelector:initSel]) {
        AACLog(@"上行播放未启动：当前系统 AVAudioPlayer 不提供 initWithContentsOfURL:usesSharedAudioSession:error:");
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    AVAudioPlayer *player = ((id (*)(id, SEL, NSURL *, BOOL, NSError **))objc_msgSend)([AVAudioPlayer alloc], initSel, url, YES, &error);
    if (!player || error) {
        AACLog([NSString stringWithFormat:@"创建上行播放器失败：%@", error.localizedDescription ?: @"unknown"]);
        return;
    }
    if (![player respondsToSelector:mixSel]) {
        AACLog(@"上行播放未启动：AVAudioPlayer 实例不响应 setMixToUplink:；不会退化为本机假播放");
        return;
    }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, YES);
        player.numberOfLoops = 0;
        player.volume = 1.0;
        if (![player prepareToPlay]) {
            AACLog(@"上行播放器 prepareToPlay 失败");
            ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, NO);
            return;
        }
        if (![player play]) {
            AACLog(@"上行播放器 play 返回失败");
            ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, NO);
            return;
        }
        AACUplinkPlayer = player;
        AACLog([NSString stringWithFormat:@"已调用私有 setMixToUplink:YES 并启动音频：%@；仍需真机确认对端是否听到", path.lastPathComponent]);
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"启动上行播放异常：%@", e.reason ?: @"unknown"]);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, NO);
    }
}

static void AACStopUplinkNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ AACStopUplinkAudio(); });
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

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACStopUplinkNotificationCallback, (__bridge CFStringRef)kAACStopUplinkNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        AACLog(@"AutoAnswerAudio 已在 SpringBoard 加载；已注册实验性上行播放停止通知。setMixToUplink: 尚未在 iOS 17.3 真机验证。");
        AACStartPolling();
    }
}
