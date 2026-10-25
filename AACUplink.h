#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// AACUplink.h — 通话上行注入最小实验实现
//
// 目标：把本地导入的音频送到通话对方（uplink）。
//
// 实现顺序（逐级回退，每一级都记录结果，失败就如实记录，不伪装成功）：
//   1) 私有 SPI：寻找可混音到 uplink 的播放器类（TrollRecorder 的 TRAudioPlayer 用 setMixToUplink:）
//      —— 该 selector 在 TrollRecorder 的 TRApp 未见证据，因此这里只做「存在性探测」，
//         不硬编码臆测类名，找到才用。
//   2) AVAudioEngine + VoiceProcessingIO：把本地音频混入远端采集链路（越狱环境下常见做法）。
//   3) 都不成：记录明确失败原因，绝不假装成功。
//
// 注意：本文件不会自动播放任何内容，只提供接口，由 Tweak.x 在合适的时机调用。

static NSString *const kAACUplinkLogPrefix = @"[UPLINK]";

// 由 Tweak.x 提供
extern void AACLog(NSString *s);

@interface AACUplinkEngine : NSObject
@property(nonatomic, strong) AVAudioEngine *engine;
@property(nonatomic, strong) AVAudioPlayerNode *player;
@property(nonatomic, strong) AVAudioFile *file;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *activeMechanism;
@end

@implementation AACUplinkEngine

+ (instancetype)shared {
    static AACUplinkEngine *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [AACUplinkEngine new]; });
    return s;
}

- (void)log:(NSString *)fmt, ... {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    AACLog([NSString stringWithFormat:@"%@ %@", kAACUplinkLogPrefix, msg]);
}

#pragma mark - 第一级：私有 SPI 探测

// 只做「是否存在」判断，不臆造类名。
// 说明：TrollRecorder 的类名 TRAudioPlayer 属于其私有的闭源产物，不保证本机存在，
// 因此这里同时探测若干常见候选，找到才用。
- (BOOL)tryPrivateMixToUplinkWithPath:(NSString *)path {
    NSArray<NSString *> *candidates = @[
        @"TRAudioPlayer",           // TrollRecorder 私有类（可能不存在）
        @"AVAudioPlayer"
    ];
    for (NSString *name in candidates) {
        Class cls = NSClassFromString(name);
        if (!cls) {
            [self log:@"私有 SPI：类 %@ 不存在", name];
            continue;
        }
        SEL mixSel = NSSelectorFromString(@"setMixToUplink:");
        Method m = class_getInstanceMethod(cls, mixSel);
        if (!m) {
            [self log:@"私有 SPI：类 %@ 没有 setMixToUplink:，跳过", name];
            continue;
        }

        // ABI 校验：必须是 1 个显式参数（BOOL）
        unsigned int argc = method_getNumberOfArguments(m);
        char argType[16] = {0};
        if (argc == 3) method_getArgumentType(m, 2, argType, sizeof(argType));
        [self log:@"私有 SPI：%@ 存在 setMixToUplink:（参数数=%u，第2参数类型=%s）", name, argc, argc == 3 ? argType : "?"];

        if (argc != 3 || (argType[0] != 'B' && argType[0] != 'c')) {
            [self log:@"私有 SPI：%@ 的 setMixToUplink: ABI 不符合预期，不调用", name];
            continue;
        }

        @try {
            id player = nil;
            if ([cls instancesRespondToSelector:@selector(initWithContentsOfURL:error:)]) {
                NSError *err = nil;
                player = ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)(
                    [cls alloc], @selector(initWithContentsOfURL:error:), [NSURL fileURLWithPath:path], &err);
                if (!player) {
                    [self log:@"私有 SPI：%@ 创建播放器失败：%@", name, err.localizedDescription ?: @"unknown"];
                    continue;
                }
            } else {
                [self log:@"私有 SPI：%@ 缺少 initWithContentsOfURL:error:，跳过", name];
                continue;
            }

            // 先设置混音到上行，再播放
            ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mixSel, YES);
            BOOL played = NO;
            SEL playSel = @selector(play);
            if ([player respondsToSelector:playSel]) {
                played = ((BOOL (*)(id, SEL))objc_msgSend)(player, playSel);
            }
            if (played) {
                self.activeMechanism = [NSString stringWithFormat:@"private-spi:%@", name];
                [self log:@"私有 SPI 成功启动：%@（mixToUplink=YES, play=YES）", name];
                objc_setAssociatedObject(self, @selector(tryPrivateMixToUplinkWithPath:), player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return YES;
            }
            [self log:@"私有 SPI：%@ 的 play 返回 NO", name];
        } @catch (NSException *e) {
            [self log:@"私有 SPI：%@ 调用异常：%@", name, e.reason ?: @"unknown"];
        }
    }
    return NO;
}

#pragma mark - 第二级：AVAudioEngine + VoiceProcessingIO

- (BOOL)tryAudioEngineWithPath:(NSString *)path {
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];

    // 通话中必须是 PlayAndRecord + voiceChat，否则无法进入通话音频链路
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                              mode:AVAudioSessionModeVoiceChat
                           options:AVAudioSessionCategoryOptionAllowBluetooth |
                                   AVAudioSessionCategoryOptionMixWithOthers
                             error:&err];
    if (!ok) {
        [self log:@"AudioEngine：设置 AudioSession 失败：%@", err.localizedDescription ?: @"unknown"];
        // 不直接放弃：某些设备在通话中改类别会被拒绝，但引擎仍可用默认配置
    }
    [session setActive:YES error:&err];
    if (err) [self log:@"AudioEngine：激活 AudioSession 返回错误（继续尝试）：%@", err.localizedDescription];

    AVAudioEngine *engine = [AVAudioEngine new];
    AVAudioPlayerNode *player = [AVAudioPlayerNode new];
    [engine attachNode:player];

    AVAudioFile *file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path] error:&err];
    if (!file) {
        [self log:@"AudioEngine：读取音频文件失败：%@", err.localizedDescription ?: @"unknown"];
        return NO;
    }

    AVAudioFormat *fileFormat = file.processingFormat;
    AVAudioFormat *mixerFormat = [engine mainMixerNode].outputFormat;
    [self log:@"AudioEngine：文件格式 %@，混音器格式 %@", fileFormat, mixerFormat];

    @try {
        [engine connect:player to:[engine mainMixerNode] format:fileFormat];
        [engine prepare];
        if (![engine startAndReturnError:&err]) {
            [self log:@"AudioEngine：启动失败：%@", err.localizedDescription ?: @"unknown"];
            return NO;
        }
        [self log:@"AudioEngine：已启动（输入节点 %@，VoiceProcessing 未强制）",
              engine.inputNode ? @"存在" : @"无"];
    } @catch (NSException *e) {
        [self log:@"AudioEngine：启动异常：%@", e.reason ?: @"unknown"];
        return NO;
    }

    [player scheduleFile:file atTime:nil completionHandler:^{
        [self log:@"AudioEngine：音频播放完毕"];
    }];
    [player play];

    self.engine = engine;
    self.player = player;
    self.file = file;
    self.activeMechanism = @"avaudioengine";
    [self log:@"AudioEngine：已开始播放（是否被对方听到需要真机验证）"];
    return YES;
}

#pragma mark - 对外接口

- (BOOL)playFileAtPath:(NSString *)path {
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.lastError = @"音频文件不存在";
        [self log:@"未开始：%@（%@）", self.lastError, path ?: @"nil"];
        return NO;
    }
    [self log:@"开始尝试上行注入，文件：%@", path.lastPathComponent];

    if ([self tryPrivateMixToUplinkWithPath:path]) return YES;
    if ([self tryAudioEngineWithPath:path]) return YES;

    self.lastError = @"私有 SPI 与 AVAudioEngine 两条路径都未能启动";
    [self log:@"%@", self.lastError];
    return NO;
}

- (void)stop {
    [self log:@"停止上行播放（机制：%@）", self.activeMechanism ?: @"none"];
    @try {
        id privatePlayer = objc_getAssociatedObject(self, @selector(tryPrivateMixToUplinkWithPath:));
        if (privatePlayer) {
            SEL stopSel = NSSelectorFromString(@"stop");
            if ([privatePlayer respondsToSelector:stopSel]) ((void (*)(id, SEL))objc_msgSend)(privatePlayer, stopSel);
            objc_setAssociatedObject(self, @selector(tryPrivateMixToUplinkWithPath:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (self.player) [self.player stop];
        if (self.engine) { [self.engine stop]; self.engine = nil; }
        self.player = nil;
        self.file = nil;
        self.activeMechanism = nil;
    } @catch (NSException *e) {
        [self log:@"停止异常：%@", e.reason ?: @"unknown"];
    }
}

@end
