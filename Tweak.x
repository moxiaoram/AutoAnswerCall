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

static void AACRequestTRBridgePlay(NSString *path) {
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

static void AACStartUplinkAudio(void) {
    if (!AACEnabled() || ![AACPrefs()[@"PlayAudio"] boolValue]) {
        AACLog([NSString stringWithFormat:@"上行播放未启动：Enabled=%d PlayAudio=%d", AACEnabled(), [AACPrefs()[@"PlayAudio"] boolValue]]);
        return;
    }

    NSString *path = AACPrefs()[@"AudioFilePath"];
    BOOL isDirectory = NO;
    BOOL exists = [path isKindOfClass:NSString.class] && path.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (!exists || isDirectory) {
        AACLog([NSString stringWithFormat:@"上行播放失败：音频文件不存在或不是文件；path=%@", path ?: @"(empty)"]);
        return;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
    AACLog([NSString stringWithFormat:@"上行音频文件检查：path=%@ size=%llu bytes readable=%d", path, fileSize,
            [[NSFileManager defaultManager] isReadableFileAtPath:path]]);
    if (fileSize == 0 || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        AACLog(@"上行播放失败：音频文件大小为 0 或当前进程无读取权限");
        return;
    }
    AACRequestTRBridgePlay(path);
}

static void AACStopUplinkNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AACStopUplinkAudio();
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

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName ?: @"";
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([process isEqualToString:@"TRCallMonitor"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACTRBridgeNotificationCallback, (__bridge CFStringRef)kAACBridgePlayNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACTRBridgeNotificationCallback, (__bridge CFStringRef)kAACBridgeStopNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            AACLog(@"AutoAnswerAudio v1.8.0 实验桥已在 TRCallMonitor 加载；使用已反汇编确认的 TRRecordingManager/session 播放入口");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AACHandleTRBridgeCommand(); });
            return;
        }
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACStopUplinkNotificationCallback, (__bridge CFStringRef)kAACStopUplinkNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        AACLog(@"AutoAnswerAudio v1.8.0 已在 SpringBoard 加载；音频播放请求将转发给 TRCallMonitor 实验桥。该路径尚未编译/真机验证。");
        AACStartPolling();
    }
}
