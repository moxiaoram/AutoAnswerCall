#import "CAObserve.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import <substrate.h>
#import <string.h>

static atomic_bool active;
static atomic_uint counts[3], mains[3];
static BOOL installed;
static void (*originalDispatch)(void *,void *);
static void (*originalConfirm)(void *);
static void (*originalSubmit)(void *);
static NSString *lastError;
static NSTimeInterval started;
static void hit(unsigned i) {
    if (!atomic_load_explicit(&active,memory_order_relaxed)) return;
    atomic_fetch_add_explicit(&counts[i],1,memory_order_relaxed);
    if (NSThread.isMainThread) atomic_fetch_add_explicit(&mains[i],1,memory_order_relaxed);
}
static void dispatchHook(void *a,void *b) { hit(0); originalDispatch(a,b); }
static void confirmHook(void *a) { hit(1); originalConfirm(a); }
static void submitHook(void *a) { hit(2); originalSubmit(a); }
static BOOL readable(const void *address, void *destination, size_t size) {
    vm_size_t actual=0;
    return vm_read_overwrite(mach_task_self(),(vm_address_t)address,(vm_size_t)size,(vm_address_t)destination,&actual)==KERN_SUCCESS && actual==size;
}
static BOOL prepare(void) {
    const struct mach_header_64 *h=(const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!h || h->magic!=MH_MAGIC_64) { lastError=@"主模块格式不支持"; return NO; }
    const unsigned char expectedUUID[16]={0x0a,0x02,0x11,0x3f,0xe0,0x20,0x32,0xd6,0xa6,0x74,0xe1,0xe8,0x62,0x2b,0xba,0x2d};
    const uint8_t *cmd=(const uint8_t *)(h+1); BOOL matched=NO;
    const uint8_t *end=cmd+h->sizeofcmds;
    for(uint32_t i=0;i<h->ncmds;i++) {
        if (cmd+sizeof(struct load_command)>end) break;
        const struct load_command *lc=(const struct load_command *)cmd;
        if(lc->cmdsize<sizeof(*lc) || lc->cmdsize>(size_t)(end-cmd)) break;
        if(lc->cmd==LC_UUID && lc->cmdsize>=sizeof(struct uuid_command)) matched=!memcmp(((const struct uuid_command *)lc)->uuid,expectedUUID,16);
        cmd+=lc->cmdsize;
    }
    if(!matched) { lastError=@"游戏 UUID 不匹配，未安装观测 Hook";return NO; }
    const uintptr_t offsets[3]={0x5ddae0,0x5dfd84,0xf949f8};
    const uint8_t fingerprint[3][16]={
      {0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9},
      {0xff,0x83,0x00,0xd1,0xfd,0x7b,0x01,0xa9,0xfd,0x43,0x00,0x91,0x68,0x6e,0x01,0x90},
      {0xff,0x03,0x01,0xd1,0xf6,0x57,0x01,0xa9,0xf4,0x4f,0x02,0xa9,0xfd,0x7b,0x03,0xa9}};
    void *addresses[3];
    for(unsigned i=0;i<3;i++) {
        addresses[i]=(void *)((uintptr_t)h+offsets[i]); uint8_t bytes[16];
        if(!readable(addresses[i],bytes,sizeof(bytes)) || memcmp(bytes,fingerprint[i],16)) {
            lastError=@"代码指纹不匹配，未安装观测 Hook";return NO;
        }
    }
    MSHookFunction(addresses[0],(void *)&dispatchHook,(void **)&originalDispatch);
    MSHookFunction(addresses[1],(void *)&confirmHook,(void **)&originalConfirm);
    MSHookFunction(addresses[2],(void *)&submitHook,(void **)&originalSubmit);
    installed=originalDispatch && originalConfirm && originalSubmit;
    if(!installed)lastError=@"Hook 后端未返回全部原函数，停止观测并退出游戏";
    return installed;
}
BOOL CAObserveStart(NSString **error) {
    if(!NSThread.isMainThread) { if(error)*error=@"请在主线程开启";return NO; }
    if(!installed && !prepare()) { if(error)*error=lastError;return NO; }
    for(unsigned i=0;i<3;i++) { atomic_store(&counts[i],0);atomic_store(&mains[i],0); }
    started=NSDate.timeIntervalSinceReferenceDate;atomic_store(&active,true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(NSDate.timeIntervalSinceReferenceDate-started>=59)CAObserveStop();
    });return YES;
}
void CAObserveStop(void) { atomic_store(&active,false); }
NSDictionary *CAObserveSnapshot(void) {
    return @{@"scope":@"manual-action-observation-only",@"active":@(atomic_load(&active)),@"installed":@(installed),
      @"events":@[@{@"name":@"普通按钮分发",@"hits":@(atomic_load(&counts[0])),@"mainThreadHits":@(atomic_load(&mains[0]))},
        @{@"name":@"结束确认候选",@"hits":@(atomic_load(&counts[1])),@"mainThreadHits":@(atomic_load(&mains[1]))},
        @{@"name":@"统一命令提交候选",@"hits":@(atomic_load(&counts[2])),@"mainThreadHits":@(atomic_load(&mains[2]))}],
      @"error":lastError?:@"",@"note":@"命中仅证明调用发生；不会自动搜索/部署/结束，不记录指针或游戏内容。停止仅停止计数，重启游戏移除Hook。"};
}
