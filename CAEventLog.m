#import "CAEventLog.h"
#import <dispatch/dispatch.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <errno.h>
#import <string.h>
#import <stdio.h>
static dispatch_queue_t queue;
static NSMutableArray *events;
static NSString *session, *path, *lastError;
static uint64_t sequence, dropped;
static double started;
static void setup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue=dispatch_queue_create("com.minis.clashassist.journal", DISPATCH_QUEUE_SERIAL);
        events=[NSMutableArray new]; session=NSUUID.UUID.UUIDString;
        started=NSProcessInfo.processInfo.systemUptime;
        NSString *dir=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"ClashAssist"];
        NSError *error=nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) lastError=error.localizedDescription;
        path=[dir stringByAppendingPathComponent:@"events.jsonl"];
    });
}
void CAEvent(NSString *event, NSDictionary *fields) {
    setup();
    double uptime=NSProcessInfo.processInfo.systemUptime;
    NSString *wall=[NSISO8601DateFormatter.new stringFromDate:NSDate.date];
    NSDictionary *payload=[fields copy] ?: @{};
    dispatch_async(queue, ^{
        NSDictionary *entry=@{@"seq":@(++sequence), @"sessionID":session, @"wallTime":wall,
            @"elapsedMs":@((uptime-started)*1000), @"event":event, @"fields":payload};
        [events addObject:entry];
        if (events.count>4096) { [events removeObjectAtIndex:0]; ++dropped; }
        NSError *error=nil;
        NSData *json=[NSJSONSerialization dataWithJSONObject:entry options:0 error:&error];
        if (!json) { lastError=error.localizedDescription; return; }
        NSMutableData *line=[json mutableCopy]; [line appendBytes:"\n" length:1];
        struct stat info;
        if (stat(path.fileSystemRepresentation,&info)==0 && (uint64_t)info.st_size+line.length>4*1024*1024) {
            NSString *previous=[path stringByAppendingString:@".1"];
            if (rename(path.fileSystemRepresentation,previous.fileSystemRepresentation)!=0) { lastError=[NSString stringWithUTF8String:strerror(errno)]; return; }
        }
        int fd=open(path.fileSystemRepresentation,O_CREAT|O_WRONLY|O_APPEND,0600);
        if (fd<0) { lastError=[NSString stringWithUTF8String:strerror(errno)]; return; }
        const uint8_t *bytes=line.bytes; size_t left=line.length;
        while (left) {
            ssize_t n=write(fd,bytes,left);
            if (n<0 && errno==EINTR) continue;
            if (n<=0) { lastError=[NSString stringWithUTF8String:strerror(errno)]; break; }
            bytes+=n; left-=(size_t)n;
        }
        if (close(fd)!=0) lastError=[NSString stringWithUTF8String:strerror(errno)];
    });
}
NSDictionary *CAEventSnapshot(void) {
    setup(); __block NSDictionary *result;
    dispatch_sync(queue, ^{ result=@{@"sessionID":session,@"events":[events copy],@"totalRecords":@(sequence),
        @"droppedOldestRecords":@(dropped),@"diskError":lastError ?: @"",@"diskFile":path ?: @"",
        @"diskPolicy":@"JSONL, 4 MiB current + 4 MiB previous, asynchronous writes; cache may be purged"}; });
    return result;
}
