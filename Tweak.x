#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <limits.h>
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
// InCallService -> SpringBoard UI state. Darwin notifications are process-wide signals, not UI objects.
static NSString * const kAACIntegratedReadyNotification = @"com.autoanswer.call.inCallStopReady";
static NSString * const kAACKeypadShownNotification = @"com.autoanswer.call.keypadShown";
static NSString * const kAACKeypadHiddenNotification = @"com.autoanswer.call.keypadHidden";
static NSString * const kAACPlaybackStartedNotification = @"com.autoanswer.call.playbackStarted";
static BOOL AACRemoteKeypadShown = NO;
static CFAbsoluteTime AACLastInCallUIReady = 0;
static CFAbsoluteTime AACLastKeypadReport = 0;
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
static volatile BOOL AACUserStopped = NO;     // 当前进程内是否已收到停止请求
// InCallService receives these state transitions through Darwin notifications.
// The native Add->Stop slot is red only while plugin playback is active; after stop,
// its original system-gray appearance is restored.
static volatile BOOL AACPlaybackActive = NO;
static volatile BOOL AACStopPressed = NO;
static NSUInteger AACAudioRouteGeneration = 0;
static void AACRecoverSpeechAfterRouteChange(void);
static void AACScheduleRouteRecovery(void);
static void AACRefreshFloatingStopVisibility(void);
static void AACUpdateStopButtonAppearance(void);
static BOOL AACIntegratedUIFresh(void);
static BOOL AACKeypadConfirmedHidden(void);

@interface AACSpeechDelegate : NSObject <AVSpeechSynthesizerDelegate>
@end
@implementation AACSpeechDelegate
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!AACUplinkLooping || AACUserStopped || synth != AACSpeechSynth) {
        AACLog(@"上行：单次朗读结束、播放器已替换或循环已关闭");
        return;
    }
    NSUInteger generation = AACAudioRouteGeneration;
    // 循环：稍作间隔后重复播放同一段文本
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!AACUplinkLooping || AACUserStopped || synth != AACSpeechSynth ||
            generation != AACAudioRouteGeneration) return;
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
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (AACUplinkLooping && !AACUserStopped) {
        AACLog(@"上行：朗读意外取消，尝试恢复（不视为用户停止）");
        AACScheduleRouteRecovery();
    }
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
    // 探针实测（iOS 17.3）：setMixToTelephonyUplink: 在 AVSpeechSynthesizer 上，
    // 签名 args=3 ret=v arg2=B（BOOL），不在 AVSpeechUtterance 上。
    Class cls = NSClassFromString(@"AVSpeechSynthesizer");
    if (!cls) return NO;
    SEL sel = NSSelectorFromString(@"setMixToTelephonyUplink:");
    return [cls instancesRespondToSelector:sel];
}

static BOOL AACEnableUplinkOnUtterance(AVSpeechUtterance *utterance) {
    if (!AACSpeechSynth) return NO;
    SEL sel = NSSelectorFromString(@"setMixToTelephonyUplink:");
    Method m = class_getInstanceMethod([AACSpeechSynth class], sel);
    if (!m) { AACLog(@"上行：AVSpeechUtterance 没有 setMixToTelephonyUplink:，无法注入上行"); return NO; }
    unsigned int argc = method_getNumberOfArguments(m);
    char argType[16] = {0};
    if (argc >= 3) method_getArgumentType(m, 2, argType, sizeof(argType));
    AACLog([NSString stringWithFormat:@"上行：在 AVSpeechSynthesizer 上调用 setMixToTelephonyUplink: 参数数=%u 类型=%s", argc, argc >= 3 ? argType : "?"]);
    if (argc != 3) { AACLog(@"上行：ABI 不符合预期（期望 2 个隐式参数 + 1 个 BOOL），不调用"); return NO; }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(AACSpeechSynth, sel, YES);
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

static UIButton *AACFloatingStop;
static void AACShowFloatingStop(BOOL show);
static BOOL AACKeypadVisible(void);
static id AACCallCenter(void);
static id AACSend(id target, NSString *selectorName);
static void AACSetUplinkMuted(BOOL muted);
static void AACStartUplinkAudio(void) {
    if (!AACEnabled() || ![AACPrefs()[@"PlayAudio"] boolValue]) {
        AACLog([NSString stringWithFormat:@"上行播放未启动：Enabled=%d PlayAudio=%d", AACEnabled(), [AACPrefs()[@"PlayAudio"] boolValue]]);
        return;
    }

    if (!AACUtteranceSupportsUplink()) {
        AACLog(@"上行：本系统 AVSpeechSynthesizer 不支持 setMixToTelephonyUplink:，放弃上行注入");
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
        AACPlaybackActive = YES;
        AACStopPressed = NO;
        AACUplinkLooping = YES;
        AACAudioRouteGeneration++; // invalidate route-recovery requests from a previous call
        if (!AACSpeechDelegateInstance) AACSpeechDelegateInstance = [AACSpeechDelegate new];
        AACSpeechSynth.delegate = AACSpeechDelegateInstance;
        [AACSpeechSynth speakUtterance:u];
        AACPostDarwinNotification(kAACPlaybackStartedNotification);
        AACLog(@"上行：已调用 speakUtterance（对方是否能听到需实际通话验证）");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (AACUplinkLooping) {
                AACSetUplinkMuted(YES);      // 播放期间静音麦克风
                AACShowFloatingStop(YES);    // 显示悬浮停止按钮
            }
        });
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"上行：朗读异常：%@", e.reason ?: @"unknown"]);
    }
}

// 麦克风静音控制：播放上行朗读期间静音麦克风，避免对方听到本机环境音。
static BOOL AACMutedUplink = NO;
static void AACSetUplinkMuted(BOOL muted) {
    id center = AACCallCenter();
    id call = AACSend(center, @"currentCall");
    if (!call) { AACLog(@"麦克风：当前无通话对象，无法设置静音状态"); return; }
    SEL sel = NSSelectorFromString(@"setUplinkMuted:");
    if (![call respondsToSelector:sel]) { AACLog(@"麦克风：TUCall 不支持 setUplinkMuted:"); return; }
    @try {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(call, sel, muted);
        AACMutedUplink = muted;
        AACLog([NSString stringWithFormat:@"麦克风：%@（setUplinkMuted:%d）", muted ? @"已静音" : @"已恢复", (int)muted]);
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"麦克风：设置异常 %@", e.reason ?: @""]);
    }
}

static void AACStopUplinkAudioTTS(void) {
    AACUserStopped = YES;
    AACUplinkLooping = NO;
    AACAudioRouteGeneration++;  // cancel pending speaker/route recovery
    if (AACMutedUplink) AACSetUplinkMuted(NO);   // 恢复麦克风
    AACShowFloatingStop(NO);                     // 隐藏悬浮按钮
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


// Speaker/receiver switches may invalidate a private telephony uplink TTS route.
// Keep the user's playback intent and automatically resume when AVSpeech is interrupted.
static void AACRecoverSpeechAfterRouteChange(void) {
    if (!AACUplinkLooping || AACUserStopped) return;
    if (AACSpeechSynth && AACSpeechSynth.isSpeaking) {
        AACLog(@"免提/路由恢复：朗读仍在进行，不主动打断");
        return;
    }
    NSString *text = AACCurrentUtterance.speechString;
    if (!text.length) text = AACSpeechTextForPath(AACPrefs()[@"AudioFilePath"]);
    if (!text.length) return;
    @try {
        if (AACSpeechSynth) AACSpeechSynth.delegate = nil;
        AACSpeechSynth = [AVSpeechSynthesizer new];
        if (!AACSpeechDelegateInstance) AACSpeechDelegateInstance = [AACSpeechDelegate new];
        AACSpeechSynth.delegate = AACSpeechDelegateInstance;
        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
        AACCurrentUtterance = utterance;
        if (!AACEnableUplinkOnUtterance(utterance)) {
            AACLog(@"免提/路由恢复：上行配置失败，本次不重启以避免误放到本机扬声器");
            return;
        }
        [AACSpeechSynth speakUtterance:utterance];
        AACLog(@"免提/路由恢复：检测到音频中断，已恢复上行朗读");
    } @catch (NSException *e) {
        AACLog([NSString stringWithFormat:@"免提/路由恢复失败：%@", e.reason ?: @"unknown"]);
    }
}
static void AACScheduleRouteRecovery(void) {
    NSUInteger gen = ++AACAudioRouteGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != AACAudioRouteGeneration || AACUserStopped || !AACUplinkLooping) return;
        AACRecoverSpeechAfterRouteChange();
    });
}
static void AACAudioRouteChanged(NSNotification *notification) {
    if (!AACUplinkLooping || AACUserStopped) return;
    AACLog([NSString stringWithFormat:@"通话音频路由变化（%@）：继续保持播放意图", notification.name]);
    AACScheduleRouteRecovery();
}

// ---------------------------------------------------------------------------
// 通话界面：将原生“添加/Add call”槽位替换为同尺寸的“停止”按钮
// 目标进程：com.apple.InCallService
// 找到 PHInCallRootViewController / PHAudioCallViewController 的视图后，
// 在通话控制按钮行插入一个“停止”按钮；点击后停止上行播放并交还麦克风。
// ---------------------------------------------------------------------------
static UIButton *AACStopButton = nil;
static UIView *AACStopButtonCircle = nil;
static __weak UIControl *AACOriginalAddControl = nil;
static __weak UILabel *AACOriginalAddLabel = nil;
static BOOL AACOriginalAddControlWasHidden = NO;
static BOOL AACOriginalAddLabelWasHidden = NO;
static BOOL AACLastReportedKeypad = NO;
static BOOL AACInCallScanStarted = NO;

@interface AACStopButtonTarget : NSObject
+ (instancetype)shared;
- (void)tapped;
@end

static void AACResetStopButton(void) {
    if (AACStopButton) {
        [AACStopButton removeFromSuperview];
        AACStopButton = nil;
    }
    AACStopButtonCircle = nil;
    if (AACOriginalAddControl) AACOriginalAddControl.hidden = AACOriginalAddControlWasHidden;
    if (AACOriginalAddLabel) AACOriginalAddLabel.hidden = AACOriginalAddLabelWasHidden;
    AACOriginalAddControl = nil;
    AACOriginalAddLabel = nil;
    AACOriginalAddControlWasHidden = NO;
    AACOriginalAddLabelWasHidden = NO;
}

static void AACStopButtonTapped(void) {
    if (AACStopPressed) {
        AACLog(@"通话界面：插件已经停止，忽略重复点击");
        return;
    }
    AACPlaybackActive = NO;
    AACStopPressed = YES;
    AACLog(@"通话界面：按下插件停止；通知 SpringBoard 停止、恢复麦克风，不挂断电话");
    AACPostDarwinNotification(kAACStopUplinkNotification);
    AACStopUplinkAudioTTS();
    if (AACStopButton) {
        AACStopButton.enabled = NO;
        AACStopButton.alpha = 1.0;
        AACStopButton.accessibilityLabel = @"插件已停止，人工接管通话";
    }
    AACUpdateStopButtonAppearance();
}

@implementation AACStopButtonTarget
+ (instancetype)shared { static AACStopButtonTarget *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [self new]; }); return s; }
- (void)tapped { AACStopButtonTapped(); }
@end

static BOOL AACLabelIsAdd(NSString *label) {
    if (![label isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [trimmed isEqualToString:@"添加"] || [trimmed isEqualToString:@"添加通话"] ||
           [trimmed isEqualToString:@"add"] || [trimmed isEqualToString:@"add call"];
}

// ---------------------------------------------------------------------------
// 2.1.4: 原生“添加”槽位 Hook + 播放中红色 / 停止后恢复系统灰色。
// 旧版 InCallService 存在以下方法；较新系统只在运行时确认 ABI 一致才安装。
// 与悬浮 / 覆盖 UIButton 不同：原生 PHAudioControlsButton 保留布局、触控和尺寸，
// 仅替换 add control 的文案 / SF Symbol / 点击行为。
// ---------------------------------------------------------------------------
typedef id (*AACObjectControlIMP)(id, SEL, unsigned long long);
typedef void (*AACTapControlIMP)(id, SEL, unsigned long long, id);
typedef void (*AACShortControlIMP)(id, SEL, unsigned long long);
typedef BOOL (*AACEnabledControlIMP)(id, SEL, unsigned long long);

// Both dylibs use Tweak.x. Resolve Substrate only in InCallService at runtime so the
// optional TRCallMonitor helper has no unnecessary link-time substrate dependency.
typedef void (*AACSubstrateHookFunction)(Class, SEL, IMP, IMP *);
static AACObjectControlIMP AACOriginalNativeTitle = NULL;
static AACObjectControlIMP AACOriginalNativeImage = NULL;
static AACTapControlIMP AACOriginalNativeTap = NULL;
static AACShortControlIMP AACOriginalNativeShortPress = NULL;
static AACEnabledControlIMP AACOriginalNativeEnabled = NULL;
static BOOL AACNativeHooksInstalled = NO;
static unsigned long long AACNativeAddType = ULLONG_MAX;
static __weak UIViewController *AACNativeControlsController = nil;
static UIImage *AACNativeStopSymbol = nil;
static __weak UIView *AACNativeStopCircleView = nil;

static BOOL AACIsNativeAddControl(id controller, unsigned long long controlType) {
    if (!AACNativeHooksInstalled) return NO;
    if (AACNativeAddType != ULLONG_MAX) return AACNativeAddType == controlType;
    if (!AACOriginalNativeTitle) return NO;
    id title = AACOriginalNativeTitle(controller, @selector(titleForControlType:), controlType);
    if (!AACLabelIsAdd(title)) return NO;
    AACNativeAddType = controlType;
    AACLog([NSString stringWithFormat:@"InCallService 原生控制器：识别到添加按钮，controlType=%llu", controlType]);
    return YES;
}

static UIImage *AACNativeStopControlImage(void) {
    if (AACNativeStopSymbol) return AACNativeStopSymbol;
    UIImage *icon = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28
                                                                                              weight:UIImageSymbolWeightMedium];
        icon = [UIImage systemImageNamed:@"stop.fill" withConfiguration:config];
    }
    if (!icon) {
        // 老版本 SF Symbols 不存在时：绘制一个白色实心方块图标，仍使用原生按钮承载。
        CGSize size = CGSizeMake(30, 30);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        [[UIColor whiteColor] setFill];
        UIBezierPath *square = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4, 4, 22, 22)
                                                          cornerRadius:3];
        [square fill];
        icon = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    AACNativeStopSymbol = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return AACNativeStopSymbol;
}

// Runtime callback signatures match the checked Objective-C methods, not guessed class layouts.
static id AACNativeTitleHook(id self, SEL _cmd, unsigned long long controlType) {
    id original = AACOriginalNativeTitle ? AACOriginalNativeTitle(self, _cmd, controlType) : nil;
    if ([self isKindOfClass:UIViewController.class]) AACNativeControlsController = self;
    if (AACLabelIsAdd(original)) {
        if (AACNativeAddType == ULLONG_MAX) {
            AACNativeAddType = controlType;
            AACLog([NSString stringWithFormat:@"原生通话按钮已识别：添加(type=%llu) -> 停止", controlType]);
        }
        return AACEnabled() ? @"停止" : original;
    }
    return (AACEnabled() && AACIsNativeAddControl(self, controlType)) ? @"停止" : original;
}
static id AACNativeImageHook(id self, SEL _cmd, unsigned long long controlType) {
    if ([self isKindOfClass:UIViewController.class]) AACNativeControlsController = self;
    if (AACEnabled() && AACIsNativeAddControl(self, controlType)) return AACNativeStopControlImage();
    return AACOriginalNativeImage ? AACOriginalNativeImage(self, _cmd, controlType) : nil;
}
static void AACNativeTappedHook(id self, SEL _cmd, unsigned long long controlType, id view) {
    if (AACEnabled() && AACIsNativeAddControl(self, controlType)) {
        AACLog(@"原生停止按钮点击：拦截添加通话 action，插件停止并人工接管");
        AACStopButtonTapped(); // 仅发停止通知，不执行系统添加通话或挂断动作。
        return;
    }
    if (AACOriginalNativeTap) AACOriginalNativeTap(self, _cmd, controlType, view);
}
static void AACNativeShortPressedHook(id self, SEL _cmd, unsigned long long controlType) {
    if (AACEnabled() && AACIsNativeAddControl(self, controlType)) {
        AACStopButtonTapped();
        return;
    }
    if (AACOriginalNativeShortPress) AACOriginalNativeShortPress(self, _cmd, controlType);
}
static BOOL AACNativeEnabledHook(id self, SEL _cmd, unsigned long long controlType) {
    // 系统原“添加通话”可能置灰：停止插件必须仍可用。
    if (AACIsNativeAddControl(self, controlType) && AACEnabled()) return YES;
    return AACOriginalNativeEnabled ? AACOriginalNativeEnabled(self, _cmd, controlType) : NO;
}

// 避免对新版系统同名但签名变化的方法安装错误的 IMP（可能让 InCallService 崩溃）。
static BOOL AACNativeMethodMatches(Class cls, SEL selector, char resultKind, NSUInteger argCount) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != argCount) return NO;
    char result[16] = {0}, type[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, type, sizeof(type));
    if (resultKind == 'b') {
        if (result[0] != 'B' && result[0] != 'c') return NO;
    } else if (result[0] != resultKind) return NO;
    // 仅 64-bit NSUInteger：arm64e Q（部分头文件可能返回 L）。
    if (type[0] != 'Q' && type[0] != 'L') return NO;
    if (argCount == 4) {
        char view[16] = {0};
        method_getArgumentType(method, 3, view, sizeof(view));
        if (view[0] != '@') return NO;
    }
    return YES;
}
static void AACInstallNativeCallControlsHooks(void) {
    if (AACNativeHooksInstalled) return;
    Class cls = NSClassFromString(@"PHAudioCallControlsViewController");
    if (!cls) {
        static BOOL loggedMissingClass = NO;
        if (!loggedMissingClass) {
            loggedMissingClass = YES;
            AACLog(@"原生按钮类 PHAudioCallControlsViewController 不存在：使用界面扫描兼容模式");
        }
        return;
    } // newer iOS may have renamed this class; legacy fallback then applies.
    if (!AACNativeMethodMatches(cls, @selector(titleForControlType:), '@', 3) ||
        !AACNativeMethodMatches(cls, @selector(imageForControlType:), '@', 3) ||
        !AACNativeMethodMatches(cls, @selector(controlTypeTapped:forView:), 'v', 4)) {
        static BOOL loggedSignature = NO;
        if (!loggedSignature) {
            loggedSignature = YES;
            AACLog(@"原生按钮 Hook 已跳过：PHAudioCallControlsViewController 方法缺失或签名不符，启用兼容模式");
        }
        return;
    }
    AACSubstrateHookFunction hook = (AACSubstrateHookFunction)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) {
        static BOOL loggedSubstrate = NO;
        if (!loggedSubstrate) {
            loggedSubstrate = YES;
            AACLog(@"原生按钮 Hook 已跳过：运行时找不到 MSHookMessageEx；继续使用兼容扫描模式");
        }
        return;
    }
    // Set the flag before installing; hooks can be invoked immediately during UI initialization.
    AACNativeHooksInstalled = YES;
    hook(cls, @selector(titleForControlType:), (IMP)AACNativeTitleHook, (IMP *)&AACOriginalNativeTitle);
    hook(cls, @selector(imageForControlType:), (IMP)AACNativeImageHook, (IMP *)&AACOriginalNativeImage);
    hook(cls, @selector(controlTypeTapped:forView:), (IMP)AACNativeTappedHook, (IMP *)&AACOriginalNativeTap);
    if (AACNativeMethodMatches(cls, @selector(controlTypeShortPressed:), 'v', 3)) {
        hook(cls, @selector(controlTypeShortPressed:), (IMP)AACNativeShortPressedHook, (IMP *)&AACOriginalNativeShortPress);
    }
    if (AACNativeMethodMatches(cls, @selector(controlTypeIsEnabled:), 'b', 3)) {
        hook(cls, @selector(controlTypeIsEnabled:), (IMP)AACNativeEnabledHook, (IMP *)&AACOriginalNativeEnabled);
    }
    AACLog(@"已安装 PHAudioCallControlsViewController 原生控件 Hook：标题/图标/点击/可用状态");
}
static BOOL AACNativeControlsAreVisible(void) {
    UIViewController *controller = AACNativeControlsController;
    if (!AACNativeHooksInstalled || AACNativeAddType == ULLONG_MAX || !controller.isViewLoaded) return NO;
    UIView *view = controller.view;
    return view.window && !view.hidden && view.alpha > 0.05;
}

// Save the exact original appearance of the native circular control so the stopped
// state restores the system's own gray/material style rather than guessing a gray.
static char kAACStopOriginalAppearanceKey;
static UIColor *AACStopActiveRed(void) {
    return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
}
static BOOL AACIsStopTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class]) return NO;
    NSString *value = [[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [value isEqualToString:@"停止"] || [value isEqualToString:@"stop"];
}
static BOOL AACLooksLikeStopCircle(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.05) return NO;
    CGFloat w = CGRectGetWidth(view.bounds), h = CGRectGetHeight(view.bounds);
    CGFloat side = MIN(w, h);
    if (side < 44.0 || side > 150.0 || fabs(w-h) > 14.0) return NO;
    CGFloat radius = view.layer.cornerRadius;
    BOOL hasVisibleBackground = NO;
    UIColor *bg = view.backgroundColor;
    if (bg) hasVisibleBackground = CGColorGetAlpha(bg.CGColor) > 0.02;
    NSString *className = NSStringFromClass(view.class);
    return radius >= side * 0.22 || hasVisibleBackground || [className containsString:@"EffectView"];
}
static void AACSetStopCircleActive(UIView *view, BOOL active) {
    if (!view) return;
    NSMutableDictionary *saved = objc_getAssociatedObject(view, &kAACStopOriginalAppearanceKey);
    if (!saved) {
        id originalColor = view.backgroundColor ?: (id)NSNull.null;
        saved = [@{ @"backgroundColor": originalColor,
                    @"cornerRadius": @(view.layer.cornerRadius) } mutableCopy];
        objc_setAssociatedObject(view, &kAACStopOriginalAppearanceKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (active) {
        view.backgroundColor = AACStopActiveRed();
        view.layer.cornerRadius = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) / 2.0;
    } else {
        id originalColor = saved[@"backgroundColor"];
        view.backgroundColor = (originalColor == NSNull.null) ? nil : originalColor;
        view.layer.cornerRadius = [saved[@"cornerRadius"] doubleValue];
    }
}
static UIView *AACFindStopCircleInContainer(UIView *container) {
    if (!container) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:container];
    UIView *best = nil;
    CGFloat bestArea = 0;
    NSUInteger visited = 0;
    while (queue.count && visited++ < 600) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || view.alpha < 0.05) continue;
        if (AACLooksLikeStopCircle(view)) {
            CGFloat area = CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds);
            if (area > bestArea) { best = view; bestArea = area; }
        }
        for (UIView *child in view.subviews) [queue addObject:child];
    }
    return best;
}
static BOOL AACViewContainsNativeStopImage(UIView *root) {
    if (!root || !AACNativeStopSymbol) return NO;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 300) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIImageView.class]) {
            UIImage *image = ((UIImageView *)view).image;
            if (image == AACNativeStopSymbol || (image.CGImage && AACNativeStopSymbol.CGImage && image.CGImage == AACNativeStopSymbol.CGImage)) return YES;
        }
        for (UIView *child in view.subviews) [queue addObject:child];
    }
    return NO;
}
static UIControl *AACFindNativeStopControl(UIView *root) {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSMutableArray<UILabel *> *stopLabels = [NSMutableArray array];
    NSMutableArray<UIControl *> *controls = [NSMutableArray array];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 4000) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || view.alpha < 0.05) continue;
        if (view == AACStopButton) continue;
        if ([view isKindOfClass:UILabel.class] && AACIsStopTitle(((UILabel *)view).text))
            [stopLabels addObject:(UILabel *)view];
        if ([view isKindOfClass:UIControl.class]) {
            UIControl *control = (UIControl *)view;
            BOOL titleMatch = AACIsStopTitle(control.accessibilityLabel);
            BOOL imageMatch = NO;
            if ([control isKindOfClass:UIButton.class]) {
                UIButton *button = (UIButton *)control;
                titleMatch = titleMatch || AACIsStopTitle(button.titleLabel.text);
                if (button.imageView.image && AACNativeStopSymbol &&
                    (button.imageView.image == AACNativeStopSymbol ||
                     (button.imageView.image.CGImage && AACNativeStopSymbol.CGImage && button.imageView.image.CGImage == AACNativeStopSymbol.CGImage)))
                    imageMatch = YES;
            }
            NSString *className = NSStringFromClass(control.class);
            if (!imageMatch && ([className containsString:@"BottomBarButton"] ||
                                [className containsString:@"AudioControlsButton"] ||
                                [className containsString:@"CallControlButton"]))
                imageMatch = AACViewContainsNativeStopImage(control);
            if (titleMatch || imageMatch) return control;
            [controls addObject:control];
        }
        for (UIView *child in view.subviews) [queue addObject:child];
    }
    // Prefer the smallest enclosing UIControl for the native "停止" title.
    UIControl *best = nil;
    CGFloat bestArea = CGFLOAT_MAX;
    for (UILabel *label in stopLabels) {
        for (UIView *parent = label.superview; parent && parent != root; parent = parent.superview) {
            if ([parent isKindOfClass:UIControl.class]) {
                CGFloat area = CGRectGetWidth(parent.bounds) * CGRectGetHeight(parent.bounds);
                if (area < bestArea) { best = (UIControl *)parent; bestArea = area; }
            }
        }
        CGRect labelFrame = [root convertRect:label.bounds fromView:label];
        for (UIControl *control in controls) {
            CGRect frame = [root convertRect:control.bounds fromView:control];
            CGFloat w = CGRectGetWidth(frame), h = CGRectGetHeight(frame);
            if (w < 44 || w > 160 || h < 44 || h > 180) continue;
            if (fabs(CGRectGetMidX(frame)-CGRectGetMidX(labelFrame)) > 32) continue;
            if (CGRectGetMinY(labelFrame) < CGRectGetMinY(frame)-5 ||
                CGRectGetMinY(labelFrame) > CGRectGetMaxY(frame)+40) continue;
            CGFloat area = w*h;
            if (area < bestArea) { best = control; bestArea = area; }
        }
    }
    return best;
}
static void AACUpdateStopButtonAppearanceOnMain(void) {
    BOOL active = AACPlaybackActive && !AACStopPressed && AACEnabled();
    if (AACStopButtonCircle) AACStopButtonCircle.backgroundColor = active ? AACStopActiveRed() : [UIColor colorWithWhite:0.85 alpha:0.20];
    if (AACNativeStopCircleView) AACSetStopCircleActive(AACNativeStopCircleView, active);
    if (AACStopButton) {
        AACStopButton.enabled = active;
        AACStopButton.alpha = 1.0;
        AACStopButton.accessibilityLabel = active ? @"停止插件播放，恢复麦克风，人工接管通话" : @"插件已停止或尚未播放";
    }
    UIViewController *controller = AACNativeControlsController;
    if (!controller.isViewLoaded || !controller.view.window) return;
    UIControl *control = AACFindNativeStopControl(controller.view);
    if (!control) return;
    UIView *circle = AACFindStopCircleInContainer(control);
    if (!circle && AACLooksLikeStopCircle(control)) circle = control;
    if (circle) {
        AACNativeStopCircleView = circle;
        AACSetStopCircleActive(circle, active);
    }
}
static void AACUpdateStopButtonAppearance(void) {
    if ([NSThread isMainThread]) AACUpdateStopButtonAppearanceOnMain();
    else dispatch_async(dispatch_get_main_queue(), ^{ AACUpdateStopButtonAppearanceOnMain(); });
}

static void AACInstallStopButtonInView(UIView *root) {
    if (!root || AACStopButton.superview) return;
    UIControl *add = nil;
    UILabel *label = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 4000) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.isHidden || v.alpha < 0.05) continue;
        if ([v isKindOfClass:UIControl.class]) {
            NSString *ident = v.accessibilityIdentifier ?: @"";
            if (AACLabelIsAdd(v.accessibilityLabel) || [ident.lowercaseString containsString:@"addcall"]) {
                add = (UIControl *)v;
                break;
            }
        }
        if ([v isKindOfClass:UILabel.class] && AACLabelIsAdd(((UILabel *)v).text)) label = (UILabel *)v;
        for (UIView *child in v.subviews) [queue addObject:child];
    }
    if (!add && label) {
        // Some iOS versions expose the caption as UILabel and the button as a sibling.
        UIView *container = label.superview;
        for (NSUInteger level=0; level<3 && container && !add; level++, container=container.superview) {
            for (UIView *v in container.subviews) {
                if ([v isKindOfClass:UIControl.class] && v.bounds.size.width >= 44 && v.bounds.size.height >= 44) {
                    CGRect vf = [root convertRect:v.bounds fromView:v];
                    CGRect lf = [root convertRect:label.bounds fromView:label];
                    if (fabs(CGRectGetMidX(vf)-CGRectGetMidX(lf)) < 35 &&
                        CGRectGetMinY(lf) >= CGRectGetMinY(vf) &&
                        CGRectGetMinY(lf)-CGRectGetMaxY(vf) < 28) {
                        add = (UIControl *)v;
                        break;
                    }
                }
            }
        }
    }
    if (!add || !add.superview || !add.window) return;
    // Control accessibility and title labels are frequently exposed in different sibling views.
    if (!label) {
        NSMutableArray<UIView *> *labels = [NSMutableArray arrayWithObject:root];
        NSUInteger checks = 0;
        while (labels.count && checks++ < 4000) {
            UIView *v = labels.firstObject;
            [labels removeObjectAtIndex:0];
            if ([v isKindOfClass:UILabel.class] && AACLabelIsAdd(((UILabel *)v).text)) {
                CGRect vf = [root convertRect:add.bounds fromView:add];
                CGRect lf = [root convertRect:v.bounds fromView:v];
                if (fabs(CGRectGetMidX(vf)-CGRectGetMidX(lf)) < 35 &&
                    CGRectGetMinY(lf) >= CGRectGetMinY(vf) &&
                    CGRectGetMinY(lf)-CGRectGetMaxY(vf) < 35) {
                    label = (UILabel *)v;
                    break;
                }
            }
            for (UIView *child in v.subviews) [labels addObject:child];
        }
    }
    CGRect frame = add.frame;
    CGFloat side = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame));
    if (side < 44 || side > 150) return;
    // Same coordinates/diameter as the original system button, never a hardcoded 64pt bubble.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.autoresizingMask = add.autoresizingMask;
    button.backgroundColor = UIColor.clearColor;
    button.clipsToBounds = NO;
    CGFloat circleY = 0;
    UIView *circle = [[UIView alloc] initWithFrame:CGRectMake((frame.size.width-side)/2.0, circleY, side, side)];
    circle.backgroundColor = (AACPlaybackActive && !AACStopPressed) ? AACStopActiveRed() : [UIColor colorWithWhite:0.85 alpha:0.20];
    circle.layer.cornerRadius = side/2.0;
    circle.userInteractionEnabled = NO;
    [button addSubview:circle];
    button.accessibilityLabel = @"停止插件播放，恢复麦克风，人工接管通话";
    [button addTarget:[AACStopButtonTarget shared] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    CGFloat iconSide = side * 0.33;
    UIView *icon = [[UIView alloc] initWithFrame:CGRectMake((side-iconSide)/2.0,
                                                           (side-iconSide)/2.0,
                                                           iconSide, iconSide)];
    icon.backgroundColor = UIColor.whiteColor;
    icon.layer.cornerRadius = iconSide * 0.14;
    icon.userInteractionEnabled = NO;
    [circle addSubview:icon];

    // If original label is outside UIControl, reuse its position and typography.
    // Otherwise place our own title below the native-size circle.
    UILabel *title = [[UILabel alloc] init];
    title.text = @"停止";
    title.textColor = UIColor.whiteColor;
    title.font = label.font ?: [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    title.textAlignment = NSTextAlignmentCenter;
    title.userInteractionEnabled = NO;
    [title sizeToFit];
    CGFloat labelOffset = side + 8;
    if (label && label.superview) {
        CGRect labelFrame = [add convertRect:label.bounds fromView:label];
        labelOffset = MAX(side+3, labelFrame.origin.y);
    }
    title.frame = CGRectMake((frame.size.width-MAX(side,title.bounds.size.width))/2.0,
                             labelOffset, MAX(side,title.bounds.size.width), title.bounds.size.height);
    [button addSubview:title];
    [add.superview addSubview:button];
    AACOriginalAddControl = add;
    AACOriginalAddLabel = label;
    AACOriginalAddControlWasHidden = add.hidden;
    AACOriginalAddLabelWasHidden = label.hidden;
    add.hidden = YES;
    if (label && ![label isDescendantOfView:add]) label.hidden = YES;
    AACStopButton = button;
    AACStopButtonCircle = circle;
    AACLog([NSString stringWithFormat:@"通话界面：原生“添加”已替换为同尺寸停止按钮，size=%.1f", side]);
    AACUpdateStopButtonAppearance();
}

static void AACScanForInCallUI(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"InCallService"]) return;
    AACInstallNativeCallControlsHooks();
    BOOL keypad = AACKeypadVisible();
    if (keypad != AACLastReportedKeypad) {
        AACLastReportedKeypad = keypad;
        AACLog([NSString stringWithFormat:@"拨号盘%@；通知 SpringBoard 避免遮挡数字", keypad ? @"显示" : @"隐藏"]);
    }
    // 心跳包括拨号盘显示和隐藏；无心跳时禁止备用悬浮按钮出现。
    // 这样即使 InCallService 注入失败也不会遮挡拨号盘的数字 8。
    AACPostDarwinNotification(keypad ? kAACKeypadShownNotification : kAACKeypadHiddenNotification);
    if (keypad) {
        if (AACStopButton) AACResetStopButton();
        return; // 禁止通过按钮扫描强行关闭系统拨号盘。
    }
    if (AACNativeHooksInstalled && AACNativeAddType != ULLONG_MAX) {
        // 原生按钮直接由系统管理；按播放状态将圆形背景切换为红色/系统原始灰色。
        if (AACStopButton) AACResetStopButton();
        AACUpdateStopButtonAppearance();
        if (AACNativeControlsAreVisible()) AACPostDarwinNotification(kAACIntegratedReadyNotification);
        return;
    }
    if (AACStopButton && (!AACStopButton.superview || !AACStopButton.window)) AACResetStopButton();
    if (!AACStopButton) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isHidden || !window.rootViewController) continue;
                AACInstallStopButtonInView(window.rootViewController.view);
                if (AACStopButton) break;
            }
            if (AACStopButton) break;
        }
    }
    if (AACStopButton && AACStopButton.window && !AACStopButton.hidden) {
        // Heartbeat allows SpringBoard to suppress fallback overlay only while the system slot works.
        AACPostDarwinNotification(kAACIntegratedReadyNotification);
    }
}

static void AACScheduleInCallScan(void) {
    if (!AACInCallScanStarted) return;
    AACScanForInCallUI();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ AACScheduleInCallScan(); });
}

static void AACPlaybackStartedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AACPlaybackActive = YES;
        AACStopPressed = NO;
        AACUserStopped = NO;
        AACUpdateStopButtonAppearance();
    });
}

static void AACStopUplinkNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *process = NSProcessInfo.processInfo.processName ?: @"";
        if ([process isEqualToString:@"InCallService"]) {
            AACPlaybackActive = NO;
            AACStopPressed = YES;
            AACUserStopped = YES;
            AACUpdateStopButtonAppearance();
        }
        AACStopUplinkAudio();
        AACStopUplinkAudioTTS();
        if ([process isEqualToString:@"SpringBoard"]) AACRequestTRBridgeStop();
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
__attribute__((unused)) static NSUInteger callsCountSafe(id center);
static void AACPollIncomingCall(void);
static void AACStartPolling(void) {
    if (AACTimerRunning) return;
    AACTimerRunning = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ AACPollIncomingCall(); });
}
static NSUInteger callsCountSafe(id center) {
    if (!center) return 0;
    id calls = AACSend(center, @"calls");
    if ([calls respondsToSelector:@selector(count)]) return [calls count];
    return 0;
}
static void AACPollIncomingCall(void) {
    @autoreleasepool {
        if (!AACEnabled() || !AACAutoAnswerEnabled()) {
            AACLastScheduledToken = nil;
            AACLastAnsweredToken = nil;
        } else {
            id center = AACCallCenter();
            id call = AACSend(center, @"incomingCall");
            // The actual call keypad belongs to InCallService, not SpringBoard.
            // Respect its IPC state, falling back only if InCallService stops reporting.
            if (AACUplinkLooping) {
                if (!AACFloatingStop && !AACIntegratedUIFresh() && AACKeypadConfirmedHidden()) AACShowFloatingStop(YES);
                AACRefreshFloatingStopVisibility();
            }
            // 通话结束检测：改用 CallKit 的 CXCall 状态，而不是轮询 incomingCall/currentCall。
            // 之前用轮询判断会在接听后误判（incomingCall 变空），导致播放一次就被停。
            if (AACUplinkLooping && !call) {
                Class obsCls = NSClassFromString(@"CXCallObserver");
                if (obsCls) {
                    id obs = AACSend((id)obsCls, @"new") ?: ((id (*)(id, SEL))objc_msgSend)((id)obsCls, @selector(new));
                    NSArray *calls = AACSend(obs, @"calls");
                    BOOL anyLive = NO;
                    if ([calls isKindOfClass:NSArray.class]) {
                        for (id c in calls) {
                            SEL endSel = NSSelectorFromString(@"hasEnded");
                            BOOL ended = [c respondsToSelector:endSel] ? ((BOOL (*)(id, SEL))objc_msgSend)(c, endSel) : NO;
                            if (!ended) { anyLive = YES; break; }
                        }
                    }
                    static NSInteger liveMiss = 0;
                    if (anyLive) liveMiss = 0; else liveMiss++;
                    if (liveMiss >= 10) {   // 约 5 秒确实没有活动通话
                        AACLog(@"CallKit 确认无活动通话，停止上行朗读并同步通话界面停止状态");
                        AACPostDarwinNotification(kAACStopUplinkNotification);
                        AACStopUplinkAudioTTS();
                        liveMiss = 0;
                    }
                }
            }
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
__attribute__((unused)) static void AACUplinkProbe(void) {
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


// ---------------------------------------------------------------------------
// Fall-back SpringBoard stop button (only when the actual InCallService slot cannot be installed).
// Keypad state is supplied by InCallService via Darwin notifications, not by scanning SpringBoard.
// ---------------------------------------------------------------------------
@interface AACFloatingTarget : NSObject
+ (instancetype)shared;
- (void)stopTapped;
@end
@implementation AACFloatingTarget
+ (instancetype)shared { static AACFloatingTarget *t; static dispatch_once_t o; dispatch_once(&o, ^{ t = [self new]; }); return t; }
- (void)stopTapped {
    AACLog(@"备用停止按钮：停止插件朗读并恢复麦克风，不结束通话");
    AACStopUplinkAudioTTS();
    AACPostDarwinNotification(kAACStopUplinkNotification);
}
@end

// Check the actual phone application's UI, including a keypad visible when the call is active.
static BOOL AACKeypadVisible(void) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"InCallService"]) return NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isHidden) continue;
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
            NSUInteger visited = 0, numericKeys = 0;
            while (queue.count && visited++ < 3500) {
                UIView *view = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if (view.hidden || view.alpha < 0.05 || !view.window) continue;
                NSString *type = NSStringFromClass(view.class);
                if ([type containsString:@"Keypad"] || [type containsString:@"Dialer"] ||
                    [type containsString:@"DialPad"]) return YES;
                if ([view isKindOfClass:UILabel.class]) {
                    NSString *t = ((UILabel *)view).text;
                    if (t.length == 1 && [@"0123456789*#" containsString:t]) numericKeys++;
                }
                for (UIView *child in view.subviews) [queue addObject:child];
            }
            if (numericKeys >= 8) return YES;
        }
    }
    return NO;
}

static BOOL AACIntegratedUIFresh(void) {
    return AACLastInCallUIReady > 0 && CFAbsoluteTimeGetCurrent() - AACLastInCallUIReady < 2.0;
}
static BOOL AACKeypadConfirmedHidden(void) {
    // 故障安全：只在接到 InCallService 最新的“拨号盘隐藏”信号后才显示悬浮备用按钮。
    // 如果 InCallService 退出/未被注入，悬浮层保持隐藏，不会盖住数字键。
    return !AACRemoteKeypadShown && AACLastKeypadReport > 0 &&
           CFAbsoluteTimeGetCurrent() - AACLastKeypadReport < 2.5;
}
static void AACRefreshFloatingStopVisibility(void) {
    if (!AACFloatingStop) return;
    BOOL visible = AACUplinkLooping && !AACUserStopped && !AACIntegratedUIFresh() && AACKeypadConfirmedHidden();
    AACFloatingStop.hidden = !visible;
}
static void AACShowFloatingStop(BOOL show) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!show) {
            if (AACFloatingStop) AACFloatingStop.hidden = YES;
            return;
        }
        // A native-size integrated stop button takes precedence over any overlay.
        if (AACIntegratedUIFresh() || !AACKeypadConfirmedHidden()) {
            AACRefreshFloatingStopVisibility();
            return;
        }
        if (!AACFloatingStop) {
            UIWindow *window = nil;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
                    if (candidate.isKeyWindow) { window = candidate; break; }
                if (window) break;
            }
            if (!window) return;
            // Fallback uses a system-control-sized circle instead of the former 64pt button.
            // Users should normally see the integrated Add->Stop replacement, not this fallback.
            CGFloat side = 82.0;
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake((window.bounds.size.width-side)/2.0,
                                      window.bounds.size.height*0.585, side, side);
            button.backgroundColor = [UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:1];
            button.layer.cornerRadius = side/2.0;
            button.layer.shadowColor = UIColor.blackColor.CGColor;
            button.layer.shadowOpacity = 0.25;
            button.layer.shadowRadius = 5;
            button.accessibilityLabel = @"停止插件播放，恢复麦克风";
            CGFloat iconSide = side*0.33;
            UIView *icon = [[UIView alloc] initWithFrame:CGRectMake((side-iconSide)/2.0, (side-iconSide)/2.0, iconSide, iconSide)];
            icon.backgroundColor = UIColor.whiteColor;
            icon.layer.cornerRadius = iconSide*0.16;
            icon.userInteractionEnabled = NO;
            [button addSubview:icon];
            [button addTarget:[AACFloatingTarget shared] action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];
            [window addSubview:button];
            AACFloatingStop = button;
            AACLog(@"InCallService 尚未报告集成停止按钮，启用备用浮层");
        }
        AACRefreshFloatingStopVisibility();
    });
}
static void AACIntegratedReadyCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AACLastInCallUIReady = CFAbsoluteTimeGetCurrent();
        AACRefreshFloatingStopVisibility();
    });
}
static void AACKeypadStateCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    BOOL shown = CFStringCompare(name, (__bridge CFStringRef)kAACKeypadShownNotification, 0) == kCFCompareEqualTo;
    dispatch_async(dispatch_get_main_queue(), ^{
        AACRemoteKeypadShown = shown;
        AACLastKeypadReport = CFAbsoluteTimeGetCurrent();
        AACRefreshFloatingStopVisibility();
    });
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
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACPlaybackStartedCallback, (__bridge CFStringRef)kAACPlaybackStartedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            AACLog(@"InCallService 已加载：优先 Hook 原生添加按钮（标题/图标/点击），失效时使用旧版视图兼容模式");
            AACInCallScanStarted = YES;
            AACInstallNativeCallControlsHooks();
            dispatch_async(dispatch_get_main_queue(), ^{ AACScheduleInCallScan(); });
            return;
        }
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACStopUplinkNotificationCallback, (__bridge CFStringRef)kAACStopUplinkNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACIntegratedReadyCallback, (__bridge CFStringRef)kAACIntegratedReadyNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACKeypadStateCallback, (__bridge CFStringRef)kAACKeypadShownNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AACKeypadStateCallback, (__bridge CFStringRef)kAACKeypadHiddenNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionRouteChangeNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *n){ AACAudioRouteChanged(n); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *n){
            NSNumber *type = n.userInfo[AVAudioSessionInterruptionTypeKey];
            if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) AACAudioRouteChanged(n);
        }];
        AACLog(@"AutoAnswerAudio v2.1.4：停止按钮播放时红色、停止后恢复系统灰色");
        // 探针已关闭（回退版）：确认接听恢复正常后再单独启用
        AACStartPolling();
    }
}
