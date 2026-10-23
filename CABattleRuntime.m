#import "CABattleRuntime.h"
#import "CAEventLog.h"
#import <UIKit/UIKit.h>
#import <math.h>

@interface CABattleRuntime ()
@property(nonatomic,strong) id<CAVerifiedGameBackend> backend;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) CABattle battle;
@property(nonatomic,assign) uint64_t runGeneration;
@property(nonatomic,copy) NSString *runID;
@property(nonatomic,copy) NSString *pendingActionID;
@end
@implementation CABattleRuntime
+ (instancetype)shared { static CABattleRuntime *value; static dispatch_once_t once; dispatch_once(&once, ^{ value=[self new]; }); return value; }
- (BOOL)running { return CABattleRunning(&_battle); }
- (NSString *)statusText { return [NSString stringWithFormat:@"后端：%@ · 阶段 %u · %@ · 搜索 %u · 已确认下兵 %u",self.backend.backendName ?: @"未接入",(unsigned)_battle.phase,_battle.reason ? [NSString stringWithUTF8String:_battle.reason] : @"就绪",_battle.searches,_battle.deployed]; }
- (BOOL)fail:(NSString *)message error:(NSError **)error {
    if (error) *error=[NSError errorWithDomain:@"ClashAssist.Battle" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    CAEvent(@"runtime.error",@{@"message":message,@"runID":self.runID ?: @""}); return NO;
}
- (BOOL)registerBackend:(id<CAVerifiedGameBackend>)backend error:(NSError **)error {
    if (!NSThread.isMainThread || self.running) return [self fail:@"注册后端须在主线程且任务已停止" error:error];
    if (!backend || ![backend conformsToProtocol:@protocol(CAVerifiedGameBackend)]) return [self fail:@"后端不符合接口" error:error];
    self.backend=backend; CAEvent(@"backend.registered",@{@"name":backend.backendName ?: @""}); return YES;
}
- (BOOL)read:(CAWorld *)world error:(NSError **)error {
    *world=(CAWorld){0};
    if (![self.backend readWorld:world error:error]) return NO;
    if (!world->revision || world->scene>CASettlement || world->scene<CAUnknown) return [self fail:@"后端返回了无效状态或版本号" error:error];
    return YES;
}
- (NSDictionary *)worldFields:(CAWorld)w {
    return @{@"scene":@(w.scene),@"revision":@(w.revision),@"opponentID":@(w.opponentID),@"gold":@(w.gold),@"elixir":@(w.elixir),@"dark":@(w.dark),@"remainingUnits":@(w.remainingUnits),@"deployedUnits":@(w.deployedUnits)};
}
- (void)perform:(CAAction)action {
    if (action==CANoAction) return;
    NSString *actionID=NSUUID.UUID.UUIDString; self.pendingActionID=actionID;
    CAEvent(@"action.request",@{@"runID":self.runID,@"actionID":actionID,@"action":@(action),@"revision":@(_battle.commandRevision)});
    NSError *error=nil; BOOL accepted=NO;
    switch (action) {
        case CASearch: accepted=[self.backend searchOpponent:&error]; break;
        case CADeployOne: accepted=[self.backend deployOneUnit:&error]; break;
        case CAEndBattle: accepted=[self.backend endBattle:&error]; break;
        default: break;
    }
    CAEvent(@"action.result",@{@"runID":self.runID,@"actionID":actionID,@"accepted":@(accepted),@"error":error.localizedDescription ?: @"",@"errorDomain":error.domain ?: @"",@"errorCode":@(error.code)});
    if (!accepted) { [self.backend cancelPendingActions]; CABattleFail(&_battle,"backend-action-rejected"); [self.timer invalidate]; self.timer=nil; }
}
- (BOOL)start:(CABattleConfig)config error:(NSError **)error {
    if (!NSThread.isMainThread || self.running) return [self fail:@"任务已运行或当前不在主线程" error:error];
    self.runID=NSUUID.UUID.UUIDString;
    if (!self.backend) return [self fail:@"未接入真实游戏后端：需要准确构建版本、已验证函数签名及状态读取接口；不会运行模拟" error:error];
    if (UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return [self fail:@"游戏须在前台" error:error];
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier, *build=NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"];
    if (!self.backend.expectedBuildVersion.length || ![bundle isEqual:self.backend.expectedBundleID] || ![build isEqual:self.backend.expectedBuildVersion]) return [self fail:@"游戏构建版本与后端不匹配" error:error];
    if (![self.backend validate:error]) { CAEvent(@"backend.validation.failed",@{@"error":(error && *error) ? (*error).localizedDescription : @"validation failed"}); return NO; }
    CAWorld world;
    if (![self read:&world error:error]) return [self fail:(error && *error) ? (*error).localizedDescription : @"读取游戏状态失败" error:error];
    double now=NSProcessInfo.processInfo.systemUptime;
    CAAction action=CABattleStart(&_battle,config,world,now);
    CAEvent(@"run.start",@{@"runID":self.runID,@"world":[self worldFields:world],@"config":@{@"minGold":@(config.minGold),@"minElixir":@(config.minElixir),@"minDark":@(config.minDark),@"maxSearch":@(config.maxSearch),@"maxUnits":@(config.maxUnits),@"actionTimeout":@(config.actionTimeout),@"battleTimeout":@(config.battleTimeout)}});
    [self perform:action];
    if (!self.running) return [self fail:self.statusText error:error];
    uint64_t generation=++self.runGeneration;
    __weak CABattleRuntime *weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        CABattleRuntime *owner=weakSelf;
        if (!owner || owner.runGeneration!=generation) { [timer invalidate]; return; }
        [owner tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes]; return YES;
}
- (void)tick {
    if (UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) { [self stop:@"background"]; return; }
    CAWorld world; NSError *error=nil;
    if (![self read:&world error:&error]) { CABattleFail(&_battle,"backend-read-failed"); CAEvent(@"state.read.failed",@{@"runID":self.runID,@"error":error.localizedDescription ?: @"unknown"}); }
    else {
        CAPhase previous=_battle.phase; uint64_t revision=_battle.lastRevision;
        CAAction action=CABattleTick(&_battle,world,NSProcessInfo.processInfo.systemUptime);
        if (world.revision!=revision || previous!=_battle.phase) CAEvent(@"state.observed",@{@"runID":self.runID,@"actionID":self.pendingActionID ?: @"",@"fromPhase":@(previous),@"toPhase":@(_battle.phase),@"reason":[NSString stringWithUTF8String:_battle.reason ?: ""],@"world":[self worldFields:world]});
        [self perform:action];
    }
    if (!self.running) { [self.backend cancelPendingActions]; [self.timer invalidate]; self.timer=nil; CAEvent(@"run.finished",[self snapshot]); }
}
- (void)stop:(NSString *)reason {
    NSAssert(NSThread.isMainThread,@"main thread required");
    ++self.runGeneration; [self.timer invalidate]; self.timer=nil;
    if (self.running) { [self.backend cancelPendingActions]; _battle.phase=CAIdle; _battle.reason="stopped"; CAEvent(@"run.stopped",@{@"runID":self.runID ?: @"",@"reason":reason}); }
}
- (NSDictionary *)snapshot { return @{@"backend":self.backend.backendName ?: @"not-connected",@"runID":self.runID ?: @"",@"running":@(self.running),@"phase":@(_battle.phase),@"reason":[NSString stringWithUTF8String:_battle.reason ?: "idle"],@"searches":@(_battle.searches),@"confirmedDeployed":@(_battle.deployed)}; }
@end
