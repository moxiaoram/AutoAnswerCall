#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import "AACUplink.h"

// AutoAnswerCall: uses the TelephonyUtilities call-center API dynamically.
// This source is not a claim that the private API has been verified on-device.
static NSString * const kAACDomain = @"com.autoanswer.call";
static NSString * const kAACSharedDir = @"/var/jb/Library/Application Support/AutoAnswerCall";
static NSString *AACLastScheduledToken = nil;
static NSString *AACLastAnsweredToken = nil;
static BOOL AACTimerRunning = NO;
static BOOL AACLoggedCallCenterUnavailable = NO;

static void AACLog(NSString *s) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:kAACSharedDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p = [kAACSharedDir stringByAppendingPathComponent:@"AutoAnswerCall.log"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", NSDate.date, s];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!h) [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else { [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
}

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
                                NSString *audioPath = [AACPrefs()[@"AudioFilePath"] isKindOfClass:NSString.class] ? AACPrefs()[@"AudioFilePath"] : nil;
                                if (!audioPath.length) {
                                    AACLog(@"已启用接听后播放，但未选择音频文件（设置里导入并选择后再试）。");
                                } else {
                                    // 等到通话真正接通再注入：answerCall: 只是发起，接通是异步的。
                                    AACLog([NSString stringWithFormat:@"将在检测到接通后尝试上行注入：%@", audioPath.lastPathComponent]);
                                    __block NSInteger tries = 0;
                                    __weak __block void (^weakCheck)(void) = nil;
                                    void (^checkAnswered)(void) = nil;
                                    __block void (^strongCheck)(void) = nil;
                                    strongCheck = ^{
                                        tries++;
                                        id c = AACCallCenter();
                                        id live = AACSend(c, @"incomingCall");
                                        BOOL connected = NO;
                                        if (live && [live respondsToSelector:NSSelectorFromString(@"isConnected")]) {
                                            connected = ((BOOL (*)(id, SEL))objc_msgSend)(live, NSSelectorFromString(@"isConnected"));
                                        }
                                        if (connected) {
                                            AACLog(@"检测到通话已接通，开始上行注入。");
                                            BOOL started = [[AACUplinkEngine shared] playFileAtPath:audioPath];
                                            AACLog(started ? @"上行注入已启动（对方是否能听到需实测）" : @"上行注入未能启动，详见 UPLINK 日志。");
                                            strongCheck = nil;
                                        } else if (tries < 20) {
                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), strongCheck);
                                        } else {
                                            AACLog(@"等待接通超时（10 秒），未启动上行注入。");
                                            strongCheck = nil;
                                        }
                                    };
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), strongCheck);
                                    (void)weakCheck; (void)checkAnswered;
                                }
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
        AACLog(@"AutoAnswerAudio 已在 SpringBoard 加载；开始检查 TUCallCenter 接听接口。注意：answerCall: 尚未在 iOS 17.3 真机验证。");
        AACStartPolling();
    }
}
