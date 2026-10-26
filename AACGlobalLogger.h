#import <Foundation/Foundation.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <stdint.h>

// Shared log for SpringBoard tweak and Preferences bundle.
// One file, cross-process append locking, and source location on every entry.
static inline void AACGlobalWriteLog(NSString *component, NSString *message, const char *file, int line, const char *function) {
    @autoreleasepool {
        NSString *directory = @"/var/mobile/Library/AutoAnswerAudio";
        NSString *path = [directory stringByAppendingPathComponent:@"AutoAnswerAudio.log"];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone localTimeZone];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS Z";
        NSString *timestamp = [formatter stringFromDate:[NSDate date]] ?: @"time-unavailable";
        NSString *fileName = file ? [[NSString stringWithUTF8String:file] lastPathComponent] : @"unknown";
        NSString *functionName = function ? [NSString stringWithUTF8String:function] : @"unknown";
        NSString *process = NSProcessInfo.processInfo.processName ?: @"unknown-process";
        NSString *safeMessage = message ?: @"(nil log message)";
        NSString *entry = [NSString stringWithFormat:@"[%@] [pid:%d] [%@] [component:%@] [%@:%d %@] %@\n", timestamp, getpid(), process, component ?: @"Unknown", fileName, line, functionName, safeMessage];
        NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];

        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd >= 0) {
            (void)flock(fd, LOCK_EX);
            const uint8_t *bytes = data.bytes;
            size_t remaining = data.length;
            while (remaining > 0) {
                ssize_t written = write(fd, bytes, remaining);
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) break;
                bytes += written;
                remaining -= (size_t)written;
            }
            (void)fsync(fd);
            (void)flock(fd, LOCK_UN);
            close(fd);
        }
        // Also mirror to the system log so crash/device-console diagnostics can correlate events.
        NSLog(@"[AutoAnswerAudio][%@] %@", component ?: @"Unknown", safeMessage);
    }
}

// 可变参数宏：用 @"%@" 承接整条已格式化字符串，
// 既允许调用点出现逗号，也不会触发 -Wformat-security。
#define AACLog(...) AACGlobalWriteLog(@"Tweak", [NSString stringWithFormat:@"%@", __VA_ARGS__], __FILE__, __LINE__, __PRETTY_FUNCTION__)
#define AAPrefsLog(...) AACGlobalWriteLog(@"Preferences", [NSString stringWithFormat:@"%@", __VA_ARGS__], __FILE__, __LINE__, __PRETTY_FUNCTION__)
