#import "CAObserve.h"
#import "CAEventLog.h"
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <stdatomic.h>
#import <substrate.h>
#import <string.h>
#import <stdint.h>

#define CA_HOOK_COUNT 3
#define CA_LOG_CAPACITY 8192
#define CA_NO_OFFSET UINT64_MAX

/*
 * Diagnostic design:
 * - Hook wrappers only record primitive metadata and always pass through.
 * - Log only the first one or two C argument words passed to the existing wrapper,
 *   in hexadecimal, without dereferencing them. They may be scalar values or pointers;
 *   their types are unknown and must not be inferred from the hex value alone.
 * - Never read pointed-to memory or record screen data, resource values, account
 *   identifiers, or network traffic. Sequence numbers identify reservation order.
 */
static atomic_bool gActive;
static atomic_uint_fast64_t gHookHits[CA_HOOK_COUNT];
static atomic_uint_fast64_t gMainHits[CA_HOOK_COUNT];
static atomic_uint_fast64_t gHookReturns[CA_HOOK_COUNT];
static atomic_uint_fast64_t gRecordTotal;
static atomic_uint_fast64_t gCallID;
static atomic_uint_fast64_t gRecordSeq[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordTicks[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordCallID[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordThreadID[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordCallerOffset[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordArg1[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordArg2[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gRecordDurationTicks[CA_LOG_CAPACITY];
static atomic_uint gRecordKind[CA_LOG_CAPACITY];
static atomic_uint gRecordPhase[CA_LOG_CAPACITY];
static atomic_uint gRecordDepth[CA_LOG_CAPACITY];
static atomic_uint gRecordFlags[CA_LOG_CAPACITY];
static atomic_uint_fast64_t gStartedTicks;
static atomic_uint_fast64_t gStoppedTicks;
static atomic_uint_fast64_t gGeneration;
static __thread unsigned gHookDepth;
static BOOL gInstalled;
static BOOL gInstallAttempted;
// Serialize whole records and session changes; atomics alone do not protect a slot.
static pthread_mutex_t gRecordLock = PTHREAD_MUTEX_INITIALIZER;
static uintptr_t gTargetHeader;
static uintptr_t gTargetEnd;
static NSString *gLastError;
static NSString *gSessionID;
static NSString *gTargetUUID = @"0A02113F-E020-32D6-A674-E1E8622BBA2D";
static NSDate *gStartedAt;
static NSString *gStopReason = @"not-stopped";
static NSArray<NSDictionary *> *gInstallDiagnostics;

static void (*gOriginalDispatch)(void *, void *);
static void (*gOriginalConfirm)(void *);
static void (*gOriginalSubmit)(void *);

static const char *gHookNames[CA_HOOK_COUNT] = {
    "普通按钮分发", "结束确认候选", "统一命令提交候选"
};

/* record kind: 0..2 hook, 3 manual marker, 4 lifecycle. phase: 0 enter, 1 return, 2 marker. */
static NSString *kindName(unsigned kind) {
    if (kind < CA_HOOK_COUNT) return [NSString stringWithUTF8String:gHookNames[kind]];
    if (kind == 3) return @"人工操作标记";
    if (kind == 4) return @"观测生命周期";
    return @"未知事件";
}
static NSString *phaseName(unsigned phase) {
    switch (phase) {
        case 0: return @"enter";
        case 1: return @"return";
        case 2: return @"marker";
        case 3: return @"start";
        case 4: return @"stop";
        default: return @"unknown";
    }
}
static NSString *markerName(NSUInteger marker) {
    switch (marker) {
        case CAObserveMarkerSearchBefore: return @"即将点击搜索对手";
        case CAObserveMarkerSearchResultVisible: return @"对手战场/搜索结果已显示";
        case CAObserveMarkerDeployBefore: return @"即将选择或部署兵力";
        case CAObserveMarkerDeployObserved: return @"已观察到兵力部署结果";
        case CAObserveMarkerEndBattleBefore: return @"即将手动结束战斗";
        case CAObserveMarkerSettlementVisible: return @"已看到结算界面";
        case CAObserveMarkerNextRoundVisible: return @"已看到下一轮/新对手界面";
        case CAObserveMarkerOther: return @"其他人工标记";
        default: return @"未知人工标记";
    }
}
static NSString *stopReasonName(CAObserveStopReason reason) {
    switch (reason) {
        case CAObserveStopManual: return @"manual";
        case CAObserveStopTimeout: return @"timeout-300s";
        case CAObserveStopRestarted: return @"restarted";
        case CAObserveStopBackground: return @"background";
        default: return @"unknown";
    }
}
static NSString *hexOffset(uint64_t offset) {
    if (offset == CA_NO_OFFSET) return @"outside-target-image";
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)offset];
}
static double ticksToMilliseconds(uint64_t ticks) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&timebase); });
    if (timebase.denom == 0) return 0.0;
    return ((double)ticks * (double)timebase.numer / (double)timebase.denom) / 1000000.0;
}
static uint64_t currentThreadID(void) {
    uint64_t tid = 0;
    (void)pthread_threadid_np(NULL, &tid);
    return tid;
}
static uint64_t targetRelativeOffset(const void *callerAddress) {
    uintptr_t p = (uintptr_t)callerAddress;
    if (gTargetHeader && p >= gTargetHeader && p < gTargetEnd) return (uint64_t)(p - gTargetHeader);
    return CA_NO_OFFSET;
}

static void recordRaw(unsigned kind, unsigned phase, uint64_t callID, unsigned depth,
                      uint64_t callerOffset, unsigned flags, uint64_t durationTicks,
                      uint64_t arg1Raw, uint64_t arg2Raw) {
    uint64_t seq = atomic_fetch_add_explicit(&gRecordTotal, 1, memory_order_relaxed) + 1;
    unsigned slot = (unsigned)((seq - 1) % CA_LOG_CAPACITY);
    uint64_t ticks = mach_absolute_time();
    atomic_store_explicit(&gRecordSeq[slot], 0, memory_order_relaxed);
    atomic_store_explicit(&gRecordTicks[slot], ticks, memory_order_relaxed);
    atomic_store_explicit(&gRecordCallID[slot], callID, memory_order_relaxed);
    atomic_store_explicit(&gRecordThreadID[slot], currentThreadID(), memory_order_relaxed);
    atomic_store_explicit(&gRecordCallerOffset[slot], callerOffset, memory_order_relaxed);
    atomic_store_explicit(&gRecordArg1[slot], arg1Raw, memory_order_relaxed);
    atomic_store_explicit(&gRecordArg2[slot], arg2Raw, memory_order_relaxed);
    atomic_store_explicit(&gRecordDurationTicks[slot], durationTicks, memory_order_relaxed);
    atomic_store_explicit(&gRecordKind[slot], kind, memory_order_relaxed);
    atomic_store_explicit(&gRecordPhase[slot], phase, memory_order_relaxed);
    atomic_store_explicit(&gRecordDepth[slot], depth, memory_order_relaxed);
    atomic_store_explicit(&gRecordFlags[slot], flags, memory_order_relaxed);
    atomic_store_explicit(&gRecordSeq[slot], seq, memory_order_release);
}

/* flags: bit0 main thread, bit1 arg1 nonnull, bit2 arg2 nonnull, bit3 caller in target image. */
static void recordHookEnter(unsigned kind, void *arg1, void *arg2, uint64_t callID,
                            unsigned depth, uint64_t callerOffset) {
    unsigned flags = (pthread_main_np() ? 1u : 0u) | (arg1 ? 2u : 0u) | (arg2 ? 4u : 0u);
    if (callerOffset != CA_NO_OFFSET) flags |= 8u;
    atomic_fetch_add_explicit(&gHookHits[kind], 1, memory_order_relaxed);
    if (flags & 1u) atomic_fetch_add_explicit(&gMainHits[kind], 1, memory_order_relaxed);
    recordRaw(kind, 0, callID, depth, callerOffset, flags, 0,
              (uint64_t)(uintptr_t)arg1, (uint64_t)(uintptr_t)arg2);
}
static void recordHookReturn(unsigned kind, uint64_t callID, unsigned depth,
                             uint64_t callerOffset, uint64_t durationTicks) {
    unsigned flags = pthread_main_np() ? 1u : 0u;
    if (callerOffset != CA_NO_OFFSET) flags |= 8u;
    atomic_fetch_add_explicit(&gHookReturns[kind], 1, memory_order_relaxed);
    recordRaw(kind, 1, callID, depth, callerOffset, flags, durationTicks, 0, 0);
}

static void dispatchHook(void *a, void *b) {
    uint64_t generation=0, callID=0, start=0, callerOffset=CA_NO_OFFSET;
    unsigned depth=0;
    BOOL recording=NO;
    if (atomic_load_explicit(&gActive, memory_order_acquire)) {
        pthread_mutex_lock(&gRecordLock);
        if (atomic_load(&gActive)) {
            recording=YES; generation=atomic_load(&gGeneration); depth=++gHookDepth;
            callID=atomic_fetch_add(&gCallID,1)+1;
            callerOffset=targetRelativeOffset(__builtin_extract_return_addr(__builtin_return_address(0)));
            start=mach_absolute_time();
            recordHookEnter(0,a,b,callID,depth,callerOffset);
        }
        pthread_mutex_unlock(&gRecordLock);
    }
    gOriginalDispatch(a, b);
    if (recording) {
        uint64_t duration=mach_absolute_time()-start;
        pthread_mutex_lock(&gRecordLock);
        // A late return may belong to a stopped session, but never a newer one.
        if (generation==atomic_load(&gGeneration))
            recordHookReturn(0,callID,depth,callerOffset,duration);
        pthread_mutex_unlock(&gRecordLock);
        --gHookDepth;
    }
}

static void confirmHook(void *a) {
    uint64_t generation=0, callID=0, start=0, callerOffset=CA_NO_OFFSET;
    unsigned depth=0;
    BOOL recording=NO;
    if (atomic_load_explicit(&gActive, memory_order_acquire)) {
        pthread_mutex_lock(&gRecordLock);
        if (atomic_load(&gActive)) {
            recording=YES; generation=atomic_load(&gGeneration); depth=++gHookDepth;
            callID=atomic_fetch_add(&gCallID,1)+1;
            callerOffset=targetRelativeOffset(__builtin_extract_return_addr(__builtin_return_address(0)));
            start=mach_absolute_time();
            recordHookEnter(1,a,NULL,callID,depth,callerOffset);
        }
        pthread_mutex_unlock(&gRecordLock);
    }
    gOriginalConfirm(a);
    if (recording) {
        uint64_t duration=mach_absolute_time()-start;
        pthread_mutex_lock(&gRecordLock);
        // A late return may belong to a stopped session, but never a newer one.
        if (generation==atomic_load(&gGeneration))
            recordHookReturn(1,callID,depth,callerOffset,duration);
        pthread_mutex_unlock(&gRecordLock);
        --gHookDepth;
    }
}

static void submitHook(void *a) {
    uint64_t generation=0, callID=0, start=0, callerOffset=CA_NO_OFFSET;
    unsigned depth=0;
    BOOL recording=NO;
    if (atomic_load_explicit(&gActive, memory_order_acquire)) {
        pthread_mutex_lock(&gRecordLock);
        if (atomic_load(&gActive)) {
            recording=YES; generation=atomic_load(&gGeneration); depth=++gHookDepth;
            callID=atomic_fetch_add(&gCallID,1)+1;
            callerOffset=targetRelativeOffset(__builtin_extract_return_addr(__builtin_return_address(0)));
            start=mach_absolute_time();
            recordHookEnter(2,a,NULL,callID,depth,callerOffset);
        }
        pthread_mutex_unlock(&gRecordLock);
    }
    gOriginalSubmit(a);
    if (recording) {
        uint64_t duration=mach_absolute_time()-start;
        pthread_mutex_lock(&gRecordLock);
        // A late return may belong to a stopped session, but never a newer one.
        if (generation==atomic_load(&gGeneration))
            recordHookReturn(2,callID,depth,callerOffset,duration);
        pthread_mutex_unlock(&gRecordLock);
        --gHookDepth;
    }
}

static BOOL readable(const void *address, void *destination, size_t size) {
    vm_size_t actual = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size,
        (vm_address_t)destination, &actual) == KERN_SUCCESS && actual == size;
}
static BOOL prepare(void) {
    if (gInstallAttempted) return gInstalled;
    gInstallAttempted=YES;
    const unsigned char expectedUUID[16] = {0x0a,0x02,0x11,0x3f,0xe0,0x20,0x32,0xd6,0xa6,0x74,0xe1,0xe8,0x62,0x2b,0xba,0x2d};
    const uintptr_t offsets[CA_HOOK_COUNT] = {0x5ddae0, 0x5dfd84, 0xf949f8};
    const uint8_t fingerprint[CA_HOOK_COUNT][16] = {
        {0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9},
        {0xff,0x83,0x00,0xd1,0xfd,0x7b,0x01,0xa9,0xfd,0x43,0x00,0x91,0x68,0x6e,0x01,0x90},
        {0xff,0x03,0x01,0xd1,0xf6,0x57,0x01,0xa9,0xf4,0x4f,0x02,0xa9,0xfd,0x7b,0x03,0xa9}
    };
    const struct mach_header_64 *target = NULL;
    uintptr_t imageEnd = 0;
    NSMutableArray *diagnostics = [NSMutableArray array];
    for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        const struct mach_header *candidate = _dyld_get_image_header(image);
        if (!candidate || candidate->magic != MH_MAGIC_64) continue;
        const struct mach_header_64 *mh = (const struct mach_header_64 *)candidate;
        const uint8_t *p = (const uint8_t *)(mh + 1), *end = p + mh->sizeofcmds;
        BOOL matched = NO;
        uintptr_t candidateEnd = (uintptr_t)mh;
        intptr_t slide = _dyld_get_image_vmaddr_slide(image);
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (p + sizeof(struct load_command) > end) break;
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end - p)) break;
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
                matched = memcmp(((const struct uuid_command *)lc)->uuid, expectedUUID, 16) == 0;
            } else if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                /* __PAGEZERO is a reservation, not part of the mapped image. */
                if (strcmp(seg->segname, "__PAGEZERO") != 0 && seg->vmsize > 0) {
                    uintptr_t segEnd = (uintptr_t)(seg->vmaddr + (uint64_t)slide + seg->vmsize);
                    if (segEnd > candidateEnd) candidateEnd = segEnd;
                }
            }
            p += lc->cmdsize;
        }
        if (matched) { target = mh; imageEnd = candidateEnd; break; }
    }
    if (!target) {
        gLastError = @"未找到 UUID 匹配的游戏镜像；未安装观测 Hook";
        gInstallDiagnostics = @[@{@"status":@"failed", @"reason":gLastError}];
        return NO;
    }
    gTargetHeader = (uintptr_t)target;
    gTargetEnd = imageEnd;
    BOOL allFingerprintsMatch=YES;
    for (unsigned i = 0; i < CA_HOOK_COUNT; i++) {
        void *address = (void *)(gTargetHeader + offsets[i]);
        uint8_t bytes[16] = {0};
        BOOL inImage=gTargetEnd>=gTargetHeader+offsets[i]+sizeof(bytes);
        BOOL canRead = inImage && readable(address, bytes, sizeof(bytes));
        NSMutableString *expectedHex=[NSMutableString new], *observedHex=[NSMutableString new];
        for (unsigned j=0; j<sizeof(bytes); j++) {
            [expectedHex appendFormat:@"%02x",fingerprint[i][j]];
            if (canRead) [observedHex appendFormat:@"%02x",bytes[j]];
        }
        BOOL fingerprintMatches = canRead && memcmp(bytes, fingerprint[i], sizeof(bytes)) == 0;
        [diagnostics addObject:@{@"name":[NSString stringWithUTF8String:gHookNames[i]],
            @"offset":[NSString stringWithFormat:@"0x%llx", (unsigned long long)offsets[i]],
            @"readable":@(canRead), @"fingerprintMatched":@(fingerprintMatches),
            @"expectedCodeHex":expectedHex, @"observedCodeHex":observedHex, @"signatureVerified":@NO,
            @"hookInstalled":@NO}];
        if (!fingerprintMatches) allFingerprintsMatch=NO;
    }
    if (!allFingerprintsMatch) {
        gLastError=@"至少一个候选入口的代码指纹不匹配；未安装 Hook";
        gInstallDiagnostics=[diagnostics copy]; return NO;
    }
    MSHookFunction((void *)(gTargetHeader + offsets[0]), (void *)&dispatchHook, (void **)&gOriginalDispatch);
    MSHookFunction((void *)(gTargetHeader + offsets[1]), (void *)&confirmHook, (void **)&gOriginalConfirm);
    MSHookFunction((void *)(gTargetHeader + offsets[2]), (void *)&submitHook, (void **)&gOriginalSubmit);
    BOOL ok[CA_HOOK_COUNT] = {gOriginalDispatch != NULL, gOriginalConfirm != NULL, gOriginalSubmit != NULL};
    NSMutableArray *finalDiagnostics = [NSMutableArray array];
    for (unsigned i = 0; i < CA_HOOK_COUNT; i++) {
        NSMutableDictionary *d = [diagnostics[i] mutableCopy]; d[@"hookInstalled"] = @(ok[i]);
        [finalDiagnostics addObject:d];
    }
    gInstallDiagnostics = [finalDiagnostics copy];
    gInstalled = ok[0] && ok[1] && ok[2];
    if (!gInstalled) gLastError = @"Hook 安装返回结果不完整；请退出游戏，不要继续推断候选用途";
    else gLastError = nil;
    return gInstalled;
}

BOOL CAObserveIsActive(void) { return atomic_load_explicit(&gActive, memory_order_acquire); }

// Periodic recoverable checkpoint. Hook callbacks never serialize JSON or do disk I/O.
static void saveCheckpoint(void) {
    NSDictionary *snapshot=CAObserveSnapshot();
    static dispatch_queue_t writer; static dispatch_once_t once;
    dispatch_once(&once, ^{ writer=dispatch_queue_create("com.minis.clashassist.checkpoint", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(writer, ^{
        NSError *error=nil;
        NSString *dir=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"ClashAssist"];
        BOOL ok=[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
        NSData *data=ok ? [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error] : nil;
        NSString *path=[dir stringByAppendingPathComponent:@"observation-latest.json"];
        if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error])
            CAEvent(@"observation.checkpoint.failed",@{@"error":error.localizedDescription ?: @"unknown"});
    });
}
static void scheduleCheckpoint(uint64_t generation) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if (generation!=atomic_load(&gGeneration) || !CAObserveIsActive()) return;
        saveCheckpoint(); scheduleCheckpoint(generation);
    });
}

BOOL CAObserveStart(NSString **error) {
    if (!NSThread.isMainThread) { if (error) *error = @"请在主线程开启观测"; return NO; }
    if (!gInstalled && !prepare()) { if (error) *error = gLastError; CAEvent(@"observation.install.failed",@{@"error":gLastError ?: @"unknown",@"installDiagnostics":gInstallDiagnostics ?: @[]}); return NO; }
    if (atomic_load_explicit(&gActive, memory_order_relaxed)) CAObserveStopWithReason(CAObserveStopRestarted);
    pthread_mutex_lock(&gRecordLock);
    atomic_store_explicit(&gActive, false, memory_order_relaxed);
    for (unsigned i = 0; i < CA_HOOK_COUNT; i++) {
        atomic_store(&gHookHits[i], 0); atomic_store(&gMainHits[i], 0); atomic_store(&gHookReturns[i], 0);
    }
    atomic_store(&gRecordTotal, 0); atomic_store(&gCallID, 0); atomic_store(&gStoppedTicks, 0);
    for (unsigned i = 0; i < CA_LOG_CAPACITY; i++) {
        atomic_store(&gRecordSeq[i], 0); atomic_store(&gRecordTicks[i], 0);
        atomic_store(&gRecordCallID[i], 0); atomic_store(&gRecordThreadID[i], 0);
        atomic_store(&gRecordCallerOffset[i], CA_NO_OFFSET); atomic_store(&gRecordArg1[i], 0);
        atomic_store(&gRecordArg2[i], 0); atomic_store(&gRecordDurationTicks[i], 0);
        atomic_store(&gRecordKind[i], 0); atomic_store(&gRecordPhase[i], 0);
        atomic_store(&gRecordDepth[i], 0); atomic_store(&gRecordFlags[i], 0);
    }
    gSessionID = NSUUID.UUID.UUIDString;
    gStartedAt = [NSDate date]; gStopReason = @"active"; gLastError = nil;
    atomic_store(&gStartedTicks, mach_absolute_time());
    uint64_t generation = atomic_fetch_add(&gGeneration, 1) + 1;
    atomic_store_explicit(&gActive, true, memory_order_release);
    recordRaw(4, 3, 0, 0, CA_NO_OFFSET, pthread_main_np() ? 1u : 0u, 0, 0, 0);
    pthread_mutex_unlock(&gRecordLock);
    CAEvent(@"observation.start",@{@"sessionID":gSessionID});
    scheduleCheckpoint(generation);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (atomic_load(&gGeneration) == generation && atomic_load(&gActive)) CAObserveStopWithReason(CAObserveStopTimeout);
    });
    return YES;
}
void CAObserveStopWithReason(CAObserveStopReason reason) {
    NSCAssert(NSThread.isMainThread,@"main thread required");
    pthread_mutex_lock(&gRecordLock);
    BOOL wasActive = atomic_exchange_explicit(&gActive, false, memory_order_acq_rel);
    if (!wasActive) { pthread_mutex_unlock(&gRecordLock); return; }
    gStopReason = stopReasonName(reason);
    atomic_store(&gStoppedTicks, mach_absolute_time());
    recordRaw(4, 4, 0, 0, CA_NO_OFFSET, pthread_main_np() ? 1u : 0u, 0, 0, 0);
    pthread_mutex_unlock(&gRecordLock);
    CAEvent(@"observation.stop",@{@"sessionID":gSessionID ?: @"",@"reason":gStopReason});
    saveCheckpoint();
}
void CAObserveStop(void) { CAObserveStopWithReason(CAObserveStopManual); }
void CAObserveMark(CAObserveMarker marker) {
    pthread_mutex_lock(&gRecordLock);
    if (!atomic_load_explicit(&gActive, memory_order_relaxed)) { pthread_mutex_unlock(&gRecordLock); return; }
    recordRaw(3, 2, (uint64_t)marker, 0, CA_NO_OFFSET, pthread_main_np() ? 1u : 0u, 0, 0, 0);
    pthread_mutex_unlock(&gRecordLock);
    CAEvent(@"observation.marker",@{@"marker":markerName(marker)});
}

NSDictionary *CAObserveSnapshot(void) {
    NSCAssert(NSThread.isMainThread,@"main thread required");
    pthread_mutex_lock(&gRecordLock);
    uint64_t total = atomic_load_explicit(&gRecordTotal, memory_order_acquire);
    uint64_t first = total > CA_LOG_CAPACITY ? total - CA_LOG_CAPACITY + 1 : 1;
    NSUInteger expectedCount = total ? (NSUInteger)(total - first + 1) : 0;
    NSMutableArray *timeline = [NSMutableArray arrayWithCapacity:expectedCount];
    double previousMs = 0.0;
    BOOL hasPrevious = NO;
    for (uint64_t seq = first; seq <= total && total > 0; seq++) {
        unsigned slot = (unsigned)((seq - 1) % CA_LOG_CAPACITY);
        uint64_t before = atomic_load_explicit(&gRecordSeq[slot], memory_order_acquire);
        if (before != seq) continue;
        uint64_t ticks = atomic_load_explicit(&gRecordTicks[slot], memory_order_relaxed);
        uint64_t callID = atomic_load_explicit(&gRecordCallID[slot], memory_order_relaxed);
        uint64_t tid = atomic_load_explicit(&gRecordThreadID[slot], memory_order_relaxed);
        uint64_t caller = atomic_load_explicit(&gRecordCallerOffset[slot], memory_order_relaxed);
        uint64_t arg1Raw = atomic_load_explicit(&gRecordArg1[slot], memory_order_relaxed);
        uint64_t arg2Raw = atomic_load_explicit(&gRecordArg2[slot], memory_order_relaxed);
        uint64_t duration = atomic_load_explicit(&gRecordDurationTicks[slot], memory_order_relaxed);
        unsigned kind = atomic_load_explicit(&gRecordKind[slot], memory_order_relaxed);
        unsigned phase = atomic_load_explicit(&gRecordPhase[slot], memory_order_relaxed);
        unsigned depth = atomic_load_explicit(&gRecordDepth[slot], memory_order_relaxed);
        unsigned flags = atomic_load_explicit(&gRecordFlags[slot], memory_order_relaxed);
        uint64_t after = atomic_load_explicit(&gRecordSeq[slot], memory_order_acquire);
        if (after != seq || kind > 4) continue;
        double elapsed = ticksToMilliseconds(ticks - atomic_load(&gStartedTicks));
        NSMutableDictionary *entry = [@{@"seq":@(seq), @"elapsedMs":@(elapsed),
            @"kind":kindName(kind), @"phase":phaseName(phase), @"threadID":@(tid),
            @"mainThread":@((flags & 1u) != 0), @"depth":@(depth),
            @"callerOffset":hexOffset(caller), @"callerInsideTargetImage":@((flags & 8u) != 0)} mutableCopy];
        if (kind < CA_HOOK_COUNT) {
            entry[@"callID"] = @(callID);
            if (phase == 0) {
                entry[@"arg1Present"] = @((flags & 2u) != 0);
                entry[@"arg2Present"] = @((flags & 4u) != 0);
                entry[@"arg1RawHex"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)arg1Raw];
                entry[@"arg2RawHex"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)arg2Raw];
            }
            if (phase == 1) entry[@"durationMs"] = @(ticksToMilliseconds(duration));
        } else if (kind == 3) {
            entry[@"markerCode"] = @(callID);
            entry[@"marker"] = markerName((NSUInteger)callID);
        }
        double delta = hasPrevious ? elapsed - previousMs : 0.0;
        entry[@"deltaFromPreviousRecordMs"] = @(delta);
        previousMs = elapsed; hasPrevious = YES;
        [timeline addObject:entry];
    }
    uint64_t started = atomic_load(&gStartedTicks);
    uint64_t stopTick = atomic_load(&gStoppedTicks);
    uint64_t endTick = atomic_load(&gActive) || !stopTick ? mach_absolute_time() : stopTick;
    double durationMs = started && endTick >= started ? ticksToMilliseconds(endTick - started) : 0.0;
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSMutableArray *hooks = [NSMutableArray arrayWithCapacity:CA_HOOK_COUNT];
    for (unsigned i = 0; i < CA_HOOK_COUNT; i++) {
        [hooks addObject:@{@"name":[NSString stringWithUTF8String:gHookNames[i]],
            @"hits":@(atomic_load(&gHookHits[i])), @"mainThreadHits":@(atomic_load(&gMainHits[i])),
            @"returnedFromOriginal":@(atomic_load(&gHookReturns[i]))}];
    }
    NSDictionary *deviceContext = @{@"bundleID":NSBundle.mainBundle.bundleIdentifier ?: @"unknown",
        @"bundleVersion":NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown",
        @"buildVersion":NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"unknown",
        @"osVersion":NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown"};
    NSMutableDictionary<NSString *, NSMutableDictionary *> *callerBuckets = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in timeline) {
        if (![entry[@"phase"] isEqual:@"enter"] || ![entry[@"callID"] isKindOfClass:NSNumber.class]) continue;
        NSString *hook = entry[@"kind"] ?: @"unknown";
        NSString *offset = entry[@"callerOffset"] ?: @"unknown";
        NSString *key = [NSString stringWithFormat:@"%@|%@", hook, offset];
        NSMutableDictionary *bucket = callerBuckets[key];
        if (!bucket) {
            bucket = [@{@"hook":hook, @"callerOffset":offset, @"calls":@0, @"mainThreadCalls":@0} mutableCopy];
            callerBuckets[key] = bucket;
        }
        bucket[@"calls"] = @([bucket[@"calls"] unsignedLongLongValue] + 1);
        if ([entry[@"mainThread"] boolValue]) bucket[@"mainThreadCalls"] = @([bucket[@"mainThreadCalls"] unsignedLongLongValue] + 1);
    }
    NSArray *callerSummary = [[callerBuckets allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"calls"] compare:a[@"calls"]];
    }];
    uint64_t retained = MIN(total, (uint64_t)CA_LOG_CAPACITY);
    NSDictionary *report = @{@"schemaVersion":@3, @"scope":@"manual-action-observation-only",
        @"sessionID":gSessionID ?: @"not-started", @"active":@(atomic_load(&gActive)),
        @"installed":@(gInstalled), @"hookSignaturesVerified":@NO, @"startedAt":gStartedAt ? [formatter stringFromDate:gStartedAt] : @"unknown",
        @"durationMs":@(durationMs), @"stopReason":gStopReason ?: @"unknown",
        @"environment":deviceContext, @"targetImage":@{@"expectedUUID":gTargetUUID, @"offsetBase":@"target Mach-O header; diagnostic only"},
        @"hooks":hooks, @"installDiagnostics":gInstallDiagnostics ?: @[], @"callerSummary":callerSummary,
        @"timeline":timeline, @"timelineInfo":@{@"clock":@"mach monotonic clock; elapsedMs is relative to observation start",
            @"sequence":@"serialized record commit order; complete records and session resets are mutex-protected",
            @"durationIncludesInstrumentation":@YES,
            @"capacity":@(CA_LOG_CAPACITY), @"totalRecords":@(total), @"retainedRecords":@(timeline.count), @"expectedRetainedRecords":@(retained),
            @"droppedOldestRecords":@(total > CA_LOG_CAPACITY ? total - CA_LOG_CAPACITY : 0),
            @"fields":@[@"seq",@"elapsedMs",@"deltaFromPreviousRecordMs",@"kind",@"phase",@"callID",@"threadID",@"mainThread",@"depth",@"callerOffset",@"callerInsideTargetImage",@"durationMs",@"arg1Present",@"arg2Present",@"arg1RawHex",@"arg2RawHex",@"marker"]},
        @"error":gLastError ?: @"", @"privacy":@{@"rawArgumentWordsLogged":@YES, @"rawPointerValuesMayBePresent":@YES,
            @"memoryDereferenced":@NO, @"screenCaptured":@NO, @"networkCaptured":@NO},
        @"note":@"日志用于关联手动操作与候选 Hook 调用。arg1RawHex/arg2RawHex 是当前 C 包装器收到的前一至两个机器字，可能是整数或指针，类型未知；不会解引用。它们不证明函数语义、参数类型或操作成功。Hook 仅透传原调用；不自动搜索、部署或结束。"};
    pthread_mutex_unlock(&gRecordLock);
    return report;
}
