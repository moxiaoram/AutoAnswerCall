// Minimal, independent load probe for debugging non-injection.
// The marker confirms the dylib entered Aweme; it DOES NOT prove individual hooks work.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <syslog.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

#if defined(DYYY_PROBE_ONLY)
#define DYYY_PROBE_MODE @"minimal-probe-only"
#elif defined(AWEMEVISION_COMPAT_BOOT) && AWEMEVISION_COMPAT_BOOT
#define DYYY_PROBE_MODE @"compat-safe-startup"
#else
#define DYYY_PROBE_MODE @"full-hooks"
#endif

static void DYYYWriteInjectionMarker(void) {
    @autoreleasepool {
        @try {
            NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
            NSString *executable = [[[NSBundle mainBundle] executablePath] lastPathComponent] ?: @"unknown";
            NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
            if (cache.length == 0) return;

            NSString *marker = [cache stringByAppendingPathComponent:@"AwemeVision-injection-2.0.7.txt"];
            NSString *contents = [NSString stringWithFormat:
                @"AwemeVision version: 2.0.7\nmode: %@\nloaded: %@\npid: %d\nbundle: %@\nexecutable: %@\nstatus: library entered process; hooks not yet verified\n",
                DYYY_PROBE_MODE, [NSDate date], getpid(), bundle, executable];
            NSError *error = nil;
            BOOL success = [contents writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:&error];
            [[NSUserDefaults standardUserDefaults] setObject:@"2.0.7" forKey:@"AwemeVisionInjectionVersion"];
            if (!success) syslog(LOG_ERR, "[AWEMEVISION-INJECT] marker write failed: %s", error.localizedDescription.UTF8String ?: "unknown");
            syslog(LOG_NOTICE, "[AWEMEVISION-INJECT] marker %s; bundle=%s", success ? "written" : "failed", bundle.UTF8String);
        } @catch (NSException *exception) {
            syslog(LOG_ERR, "[AWEMEVISION-INJECT] marker exception: %s", exception.name.UTF8String ?: "unknown");
        }
    }
}

// Use plain POSIX I/O before dispatching onto the main queue. This records
// whether dyld entered the tweak even if UIKit later fails to start.
static void AVWriteEarlyLoadMarker(void) {
    const char *home = getenv("HOME");
    if (!home || !*home) return;
    char filepath[1024];
    int len = snprintf(filepath, sizeof(filepath), "%s/Library/Caches/AwemeVision-early-load-2.0.7.log", home);
    if (len <= 0 || (size_t)len >= sizeof(filepath)) return;
    int fd = open(filepath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    const char *line = "dyld entered AwemeVision 2.0.7 before UIKit startup\n";
    (void)write(fd, line, strlen(line));
    (void)close(fd);
}

__attribute__((constructor))
static void DYYYInjectionProbeConstructor(void) {
    AVWriteEarlyLoadMarker();
    syslog(LOG_NOTICE, "[AWEMEVISION-INJECT] dylib constructor called, pid=%d", getpid());
    dispatch_async(dispatch_get_main_queue(), ^{ DYYYWriteInjectionMarker(); });
}
