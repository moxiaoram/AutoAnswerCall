// Minimal, independent load probe for debugging non-injection.
// The marker confirms the dylib entered Aweme; it DOES NOT prove individual hooks work.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <syslog.h>
#import <unistd.h>

#if defined(DYYY_PROBE_ONLY)
#define DYYY_PROBE_MODE @"minimal-probe-only"
#else
#define DYYY_PROBE_MODE @"full-plugin"
#endif

static void DYYYWriteInjectionMarker(void) {
    @autoreleasepool {
        @try {
            NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
            NSString *executable = [[[NSBundle mainBundle] executablePath] lastPathComponent] ?: @"unknown";
            NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
            if (cache.length == 0) return;

            NSString *marker = [cache stringByAppendingPathComponent:@"AwemeVision-injection-2.0.0.txt"];
            NSString *contents = [NSString stringWithFormat:
                @"AwemeVision version: 2.0.0\nmode: %@\nloaded: %@\npid: %d\nbundle: %@\nexecutable: %@\nstatus: library entered process; hooks not yet verified\n",
                DYYY_PROBE_MODE, [NSDate date], getpid(), bundle, executable];
            NSError *error = nil;
            BOOL success = [contents writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:&error];
            [[NSUserDefaults standardUserDefaults] setObject:@"2.0.0" forKey:@"AwemeVisionInjectionVersion"];
            if (!success) syslog(LOG_ERR, "[AWEMEVISION-INJECT] marker write failed: %s", error.localizedDescription.UTF8String ?: "unknown");
            syslog(LOG_NOTICE, "[AWEMEVISION-INJECT] marker %s; bundle=%s", success ? "written" : "failed", bundle.UTF8String);
        } @catch (NSException *exception) {
            syslog(LOG_ERR, "[AWEMEVISION-INJECT] marker exception: %s", exception.name.UTF8String ?: "unknown");
        }
    }
}

__attribute__((constructor))
static void DYYYInjectionProbeConstructor(void) {
    syslog(LOG_NOTICE, "[AWEMEVISION-INJECT] dylib constructor called, pid=%d", getpid());
    dispatch_async(dispatch_get_main_queue(), ^{ DYYYWriteInjectionMarker(); });
}
