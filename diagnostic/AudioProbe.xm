#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <substrate.h>
#import <stdatomic.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>

// Diagnostic-only probe. It never edits audio buffers; it forwards all six
// AudioUnitRender arguments unchanged and records each AU instance once.
typedef OSStatus (*AACAudioUnitRenderFn)(AudioUnit,
                                         AudioUnitRenderActionFlags *,
                                         const AudioTimeStamp *,
                                         UInt32,
                                         UInt32,
                                         AudioBufferList *);
static AACAudioUnitRenderFn gOriginalAudioUnitRender = NULL;
static _Atomic(uintptr_t) gSeenUnits[128];
static _Atomic(uintptr_t) gRecordedUnits[128];
static dispatch_queue_t gProbeQueue = nil;
static dispatch_source_t gProbeTimer = nil;
static const char *gProbePath = "/var/jb/Library/Application Support/AutoAnswerCall/AudioProbe.log";

static void AACProbeLog(NSString *message) {
    @autoreleasepool {
        NSString *dir = @"/var/jb/Library/Application Support/AutoAnswerCall";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *line = [NSString stringWithFormat:@"[%@] pid=%d %@\n", [NSDate date], getpid(), message ?: @""];
        int fd = open(gProbePath, O_CREAT | O_WRONLY | O_APPEND, 0644);
        if (fd >= 0) {
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            const uint8_t *bytes = data.bytes;
            size_t left = data.length;
            while (left) {
                ssize_t n = write(fd, bytes, left);
                if (n <= 0) break;
                bytes += n; left -= (size_t)n;
            }
            close(fd);
        }
    }
}

static NSString *AACFourCC(UInt32 value) {
    char s[5] = {(char)(value >> 24), (char)(value >> 16), (char)(value >> 8), (char)value, 0};
    for (int i = 0; i < 4; i++) if (s[i] < 32 || s[i] > 126) s[i] = '.';
    return [NSString stringWithFormat:@"%s (0x%08x)", s, (unsigned)value];
}

static BOOL AACClaimUnitOnce(uintptr_t key) {
    if (!key) return NO;
    for (size_t i = 0; i < sizeof(gSeenUnits) / sizeof(gSeenUnits[0]); i++) {
        uintptr_t current = atomic_load_explicit(&gSeenUnits[i], memory_order_relaxed);
        if (current == key) return NO;
        if (current == 0) {
            uintptr_t expected = 0;
            if (atomic_compare_exchange_strong_explicit(&gSeenUnits[i], &expected, key,
                                                        memory_order_relaxed, memory_order_relaxed)) return YES;
            if (expected == key) return NO;
        }
    }
    return NO; // fixed table full; avoid logging on every render call
}

// The render callback must not do Objective-C work, filesystem I/O, or query
// AudioUnit properties. It only records the AU pointer in a fixed atomic table;
// a timer on a separate utility queue performs the expensive inspection.
static void AACRecordUnitFromRealtimeCallback(AudioUnit unit) {
    uintptr_t key = (uintptr_t)unit;
    if (!key) return;
    size_t count = sizeof(gRecordedUnits) / sizeof(gRecordedUnits[0]);
    size_t start = ((key >> 4) ^ (key >> 11)) % count;
    for (size_t step = 0; step < count; step++) {
        size_t i = (start + step) % count;
        uintptr_t current = atomic_load_explicit(&gRecordedUnits[i], memory_order_relaxed);
        if (current == key) return;
        if (current == 0) {
            uintptr_t expected = 0;
            if (atomic_compare_exchange_strong_explicit(&gRecordedUnits[i], &expected, key,
                                                        memory_order_relaxed, memory_order_relaxed)) return;
            if (expected == key) return;
        }
    }
}

static void AACDescribeAudioUnit(AudioUnit unit) {
    if (!AACClaimUnitOnce((uintptr_t)unit)) return;
    @autoreleasepool {
        AudioComponent component = AudioComponentInstanceGetComponent(unit);
        AudioComponentDescription desc = {0};
        OSStatus descStatus = component ? AudioComponentGetDescription(component, &desc) : -1;
        CFStringRef nick = NULL;
        UInt32 size = sizeof(nick);
        // 54 is kAudioUnitProperty_NickName on the target CoreAudio API.
        OSStatus nickStatus = AudioUnitGetProperty(unit, (AudioUnitPropertyID)54,
                                                   kAudioUnitScope_Global, 0, &nick, &size);
        NSString *nickString = (nick && CFGetTypeID(nick) == CFStringGetTypeID())
            ? [(__bridge NSString *)nick copy] : @"<unavailable>";
        if (nick) CFRelease(nick); // AudioUnitGetProperty returns a retained CF object for CF properties.
        NSString *descText = descStatus == noErr
            ? [NSString stringWithFormat:@"type=%@ subtype=%@ manufacturer=%@ flags=0x%x mask=0x%x",
               AACFourCC(desc.componentType), AACFourCC(desc.componentSubType),
               AACFourCC(desc.componentManufacturer), (unsigned)desc.componentFlags,
               (unsigned)desc.componentFlagsMask]
            : [NSString stringWithFormat:@"description_status=%d", (int)descStatus];
        AACProbeLog([NSString stringWithFormat:@"AudioUnitRender AU=%p %@ nickname=%@ nicknameStatus=%d size=%u",
                     unit, descText, nickString, (int)nickStatus, (unsigned)size]);
        // Snapshot common stream-format scopes once per unit; this is diagnostic only.
        const AudioUnitScope scopes[] = { kAudioUnitScope_Input, kAudioUnitScope_Output };
        for (size_t si = 0; si < sizeof(scopes) / sizeof(scopes[0]); si++) {
            for (UInt32 element = 0; element <= 1; element++) {
                AudioStreamBasicDescription asbd = {0};
                UInt32 asbdSize = sizeof(asbd);
                OSStatus fmtStatus = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                                          scopes[si], element, &asbd, &asbdSize);
                if (fmtStatus == noErr) {
                    AACProbeLog([NSString stringWithFormat:@"AU=%p stream scope=%u element=%u rate=%.3f format=%@ flags=0x%x bytesPerPacket=%u framesPerPacket=%u bytesPerFrame=%u channels=%u bits=%u",
                                 unit, (unsigned)scopes[si], (unsigned)element, asbd.mSampleRate,
                                 AACFourCC(asbd.mFormatID), (unsigned)asbd.mFormatFlags,
                                 (unsigned)asbd.mBytesPerPacket, (unsigned)asbd.mFramesPerPacket,
                                 (unsigned)asbd.mBytesPerFrame, (unsigned)asbd.mChannelsPerFrame,
                                 (unsigned)asbd.mBitsPerChannel]);
                }
            }
        }
    }
}

static OSStatus AACAudioUnitRenderHook(AudioUnit unit,
                                       AudioUnitRenderActionFlags *flags,
                                       const AudioTimeStamp *timeStamp,
                                       UInt32 outputBus,
                                       UInt32 numberFrames,
                                       AudioBufferList *ioData) {
    AACAudioUnitRenderFn original = gOriginalAudioUnitRender;
    if (!original) return kAudio_ParamError;
    // Keep the real-time path minimal and preserve all six public ABI arguments.
    OSStatus result = original(unit, flags, timeStamp, outputBus, numberFrames, ioData);
    AACRecordUnitFromRealtimeCallback(unit);
    return result;
}

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName ?: @"unknown";
        AACProbeLog([NSString stringWithFormat:@"Audio probe loaded in %@; diagnostic only, buffers unchanged", process]);
        gProbeQueue = dispatch_queue_create("com.autoanswer.call.audioprobe", DISPATCH_QUEUE_SERIAL);
        gProbeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gProbeQueue);
        if (gProbeTimer) {
            dispatch_source_set_timer(gProbeTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(gProbeTimer, ^{
                for (size_t i = 0; i < sizeof(gRecordedUnits) / sizeof(gRecordedUnits[0]); i++) {
                    uintptr_t key = atomic_load_explicit(&gRecordedUnits[i], memory_order_relaxed);
                    if (key) AACDescribeAudioUnit((AudioUnit)key);
                }
            });
            dispatch_resume(gProbeTimer);
        } else {
            AACProbeLog(@"Could not create background diagnostic timer");
        }
        void *symbol = dlsym(RTLD_DEFAULT, "AudioUnitRender");
        if (!symbol) {
            AACProbeLog(@"dlsym(AudioUnitRender) failed; probe not installed");
            return;
        }
        MSHookFunction(symbol, (void *)&AACAudioUnitRenderHook, (void **)&gOriginalAudioUnitRender);
        AACProbeLog([NSString stringWithFormat:@"AudioUnitRender diagnostic hook installed at %p original=%p", symbol, gOriginalAudioUnitRender]);
    }
}
