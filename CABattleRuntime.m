#import "CABattleRuntime.h"
#import "CAEventLog.h"
#import <UIKit/UIKit.h>
#import <math.h>

static NSString *CAActionName(CAAction action) {
    switch (action) {
        case CASearch: return @"searchOpponent";
        case CADeployOne: return @"deployOneUnit";
        case CAEndBattle: return @"endBattle";
        case CAReturnHome: return @"returnHome";
        default: return @"none";
    }
}
static NSString *CAPhaseName(CAPhase phase) {
    switch (phase) {
        case CAIdle: return @"idle"; case CAWaitSearch: return @"waitSearch";
        case CADeploy: return @"deploy"; case CAWaitDeploy: return @"waitDeploy";
        case CAWaitBattle: return @"waitBattle"; case CAWaitEnd: return @"waitEnd";
        case CAWaitHome: return @"waitHome"; case CADone: return @"done"; case CAError: return @"error";
    }
    return @"invalid";
}
static NSArray<NSString *> *CAMissingFieldNames(uint32_t mask) {
    NSMutableArray *names=[NSMutableArray new];
    if (mask & CAWorldHasScene) [names addObject:@"scene"];
    if (mask & CAWorldHasRevision) [names addObject:@"revision"];
    if (mask & CAWorldHasTimestamp) [names addObject:@"observedAtMonotonic"];
    if (mask & CAWorldHasOpponentID) [names addObject:@"opponentID"];
    if (mask & CAWorldHasOpponentResources) [names addObject:@"opponentResources(gold/elixir/dark)"];
    if (mask & CAWorldHasBattleLoot) [names addObject:@"cumulativeBattleLoot(lootGold/lootElixir/lootDark)"];
    if (mask & CAWorldHasTroops) [names addObject:@"troops(remainingUnits/deployedUnits)"];
    return names;
}

@interface CABattleRuntime ()
@property(nonatomic,strong) id<CAVerifiedGameBackend> backend;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) CABattle battle;
@property(nonatomic,assign) uint64_t runGeneration;
@property(nonatomic,copy) NSString *runID;
@property(nonatomic,copy) NSString *pendingActionID;
@property(nonatomic,assign) CAWorld lastWorld;
@property(nonatomic,assign) BOOL hasLastWorld;
@property(nonatomic,assign) uint64_t sampleCount;
@property(nonatomic,assign) uint64_t duplicateRevisionCount;
@property(nonatomic,assign) double runStartedMonotonic;
@property(nonatomic,assign) BOOL backendValidationPassed;
@property(nonatomic,copy) NSString *backendValidationError;
@end
@implementation CABattleRuntime
+ (instancetype)shared { static CABattleRuntime *value; static dispatch_once_t once; dispatch_once(&once, ^{ value=[self new]; }); return value; }
- (BOOL)running { return CABattleRunning(&_battle); }
- (NSString *)statusText {
    return [NSString stringWithFormat:@"后端：%@ · 阶段 %@ · %@ · 搜索 %u · 已完成战斗 %u · 已确认下兵 %u",
        self.backend.backendName ?: @"未接入",CAPhaseName(_battle.phase),_battle.reason ? [NSString stringWithUTF8String:_battle.reason] : @"就绪",
        _battle.searches,_battle.completedBattles,_battle.deployed];
}
- (BOOL)fail:(NSString *)message error:(NSError **)error {
    if (error) *error=[NSError errorWithDomain:@"ClashAssist.Battle" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    CAEvent(@"runtime.error",@{@"message":message,@"runID":self.runID ?: @"",@"phase":CAPhaseName(_battle.phase)}); return NO;
}
- (BOOL)registerBackend:(id<CAVerifiedGameBackend>)backend error:(NSError **)error {
    if (!NSThread.isMainThread || self.running) return [self fail:@"注册后端须在主线程且任务已停止" error:error];
    if (!backend || ![backend conformsToProtocol:@protocol(CAVerifiedGameBackend)]) return [self fail:@"后端不符合 CAVerifiedGameBackend 契约" error:error];
    self.backend=backend;
    self.backendValidationPassed=NO;
    self.backendValidationError=@"尚未运行后端 validate:；注册本身不代表接口已验证";
    CAEvent(@"backend.registered",@{@"name":backend.backendName ?: @"",@"expectedBundleID":backend.expectedBundleID ?: @"",@"expectedBuildVersion":backend.expectedBuildVersion ?: @"",@"returnHomeSupported":@([backend respondsToSelector:@selector(returnHome:)])});
    return YES;
}
- (NSDictionary *)worldFields:(CAWorld)w {
    uint32_t missing=CAWorldMissingFields(w);
    double now=NSProcessInfo.processInfo.systemUptime;
    id opponent=(w.validFields & CAWorldHasOpponentID) ? @(w.opponentID) : NSNull.null;
    id gold=(w.validFields & CAWorldHasOpponentResources) ? @(w.gold) : NSNull.null;
    id elixir=(w.validFields & CAWorldHasOpponentResources) ? @(w.elixir) : NSNull.null;
    id dark=(w.validFields & CAWorldHasOpponentResources) ? @(w.dark) : NSNull.null;
    id lootGold=(w.validFields & CAWorldHasBattleLoot) ? @(w.lootGold) : NSNull.null;
    id lootElixir=(w.validFields & CAWorldHasBattleLoot) ? @(w.lootElixir) : NSNull.null;
    id lootDark=(w.validFields & CAWorldHasBattleLoot) ? @(w.lootDark) : NSNull.null;
    id remaining=(w.validFields & CAWorldHasTroops) ? @(w.remainingUnits) : NSNull.null;
    id deployed=(w.validFields & CAWorldHasTroops) ? @(w.deployedUnits) : NSNull.null;
    return @{@"scene":@(w.scene),@"revision":@(w.revision),@"observedAtMonotonic":@(w.observedAtMonotonic),
        @"observationAgeMs":@(w.observedAtMonotonic>0 ? (now-w.observedAtMonotonic)*1000.0 : -1),
        @"validFields":@(w.validFields),@"missingFields":CAMissingFieldNames(missing),@"evidenceFlags":@(w.evidenceFlags),
        @"opponentID":opponent,@"opponentRemainingGold":gold,@"opponentRemainingElixir":elixir,@"opponentRemainingDark":dark,
        @"battleLootGold":lootGold,@"battleLootElixir":lootElixir,@"battleLootDark":lootDark,
        @"remainingUnits":remaining,@"deployedUnits":deployed};
}
- (BOOL)read:(CAWorld *)world error:(NSError **)error {
    *world=(CAWorld){0};
    double started=NSProcessInfo.processInfo.systemUptime;
    NSError *backendError=nil;
    if (![self.backend readWorld:world error:&backendError]) {
        if (error) *error=backendError ?: [NSError errorWithDomain:@"ClashAssist.Backend" code:10 userInfo:@{NSLocalizedDescriptionKey:@"readWorld 返回失败但没有 NSError"}];
        CAEvent(@"state.read.failed",@{@"runID":self.runID ?: @"",@"readDurationMs":@((NSProcessInfo.processInfo.systemUptime-started)*1000.0),@"error":backendError.localizedDescription ?: @"backend returned NO without NSError",@"errorDomain":backendError.domain ?: @"",@"errorCode":@(backendError.code)});
        return NO;
    }
    double now=NSProcessInfo.processInfo.systemUptime;
    uint32_t missing=CAWorldMissingFields(*world);
    if (world->scene<CAUnknown || world->scene>CASettlement || !world->revision || missing) {
        NSString *message=[NSString stringWithFormat:@"世界状态不完整：scene=%u revision=%llu missing=%@",(unsigned)world->scene,world->revision,CAMissingFieldNames(missing)];
        if (error) *error=[NSError errorWithDomain:@"ClashAssist.Backend" code:11 userInfo:@{NSLocalizedDescriptionKey:message}];
        CAEvent(@"state.read.invalid",@{@"runID":self.runID ?: @"",@"world":[self worldFields:*world],@"error":message}); return NO;
    }
    if (!(world->observedAtMonotonic>0) || world->observedAtMonotonic>now+0.1 || now-world->observedAtMonotonic>1.5) {
        NSString *message=[NSString stringWithFormat:@"状态快照时间戳无效或过期：ageMs=%.3f",(now-world->observedAtMonotonic)*1000.0];
        if (error) *error=[NSError errorWithDomain:@"ClashAssist.Backend" code:12 userInfo:@{NSLocalizedDescriptionKey:message}];
        CAEvent(@"state.read.stale",@{@"runID":self.runID ?: @"",@"world":[self worldFields:*world],@"error":message}); return NO;
    }
    if (self.hasLastWorld && world->revision<=self.lastWorld.revision) {
        BOOL duplicate=(world->revision==self.lastWorld.revision);
        if (duplicate) ++self.duplicateRevisionCount;
        NSString *message=[NSString stringWithFormat:@"revision 必须对每次新鲜采样严格递增：previous=%llu current=%llu",self.lastWorld.revision,world->revision];
        if (error) *error=[NSError errorWithDomain:@"ClashAssist.Backend" code:13 userInfo:@{NSLocalizedDescriptionKey:message}];
        CAEvent(@"state.read.revision-invalid",@{@"runID":self.runID ?: @"",@"previousRevision":@(self.lastWorld.revision),@"currentRevision":@(world->revision),@"duplicate":@(duplicate)});
        return NO;
    }
    ++self.sampleCount;
    double sampleNow=NSProcessInfo.processInfo.systemUptime;
    double growthAgeMs=self.battle.lootBaselineSet ? MAX(0,(sampleNow-self.battle.lastLootGrowthAt)*1000.0) : -1;
    CAEvent(@"state.sample",@{@"runID":self.runID ?: @"",@"sampleIndex":@(self.sampleCount),@"runElapsedMs":@(self.runStartedMonotonic>0 ? (sampleNow-self.runStartedMonotonic)*1000.0 : -1),@"readDurationMs":@((sampleNow-started)*1000.0),@"phaseAtSample":CAPhaseName(self.battle.phase),@"searches":@(self.battle.searches),@"completedBattles":@(self.battle.completedBattles),@"confirmedDeployed":@(self.battle.deployed),@"lootGrowthAgeMsBeforeDecision":@(growthAgeMs),@"lastLootGrowthAtMonotonic":@(self.battle.lastLootGrowthAt),@"actionDeadlineMonotonic":@(self.battle.deadline),@"battleDeadlineMonotonic":@(self.battle.battleDeadline),@"pendingActionID":self.pendingActionID ?: @"",@"backend":self.backend.backendName ?: @"",@"world":[self worldFields:*world]});
    self.lastWorld=*world; self.hasLastWorld=YES;
    return YES;
}
- (void)logDecision:(CAAction)action {
    double now=NSProcessInfo.processInfo.systemUptime;
    CAEvent(@"scheduler.decision",@{@"runID":self.runID ?: @"",@"action":CAActionName(action),@"phase":CAPhaseName(_battle.phase),@"reason":[NSString stringWithUTF8String:_battle.reason ?: ""],@"searches":@(_battle.searches),@"completedBattles":@(_battle.completedBattles),@"confirmedDeployed":@(_battle.deployed),@"commandRevision":@(_battle.commandRevision),@"lastRevision":@(_battle.lastRevision),@"lastLootGrowthAtMonotonic":@(_battle.lastLootGrowthAt),@"lootGrowthAgeMs":@(_battle.lootBaselineSet ? MAX(0,(now-_battle.lastLootGrowthAt)*1000.0) : -1),@"actionDeadlineMonotonic":@(_battle.deadline),@"battleDeadlineMonotonic":@(_battle.battleDeadline),@"noLootGrowthTimeoutSeconds":@(_battle.config.noLootGrowthTimeout)});
}
- (void)perform:(CAAction)action {
    if (action==CANoAction) return;
    NSString *actionID=NSUUID.UUID.UUIDString; self.pendingActionID=actionID;
    NSString *actionName=CAActionName(action);
    CAEvent(@"action.request",@{@"runID":self.runID ?: @"",@"actionID":actionID,@"action":actionName,@"phase":CAPhaseName(_battle.phase),@"revision":@(_battle.commandRevision),@"searches":@(_battle.searches),@"completedBattles":@(_battle.completedBattles),@"confirmedDeployed":@(_battle.deployed)});
    NSError *error=nil; BOOL accepted=NO;
    switch (action) {
        case CASearch: accepted=[self.backend searchOpponent:&error]; break;
        case CADeployOne: accepted=[self.backend deployOneUnit:&error]; break;
        case CAEndBattle: accepted=[self.backend endBattle:&error]; break;
        case CAReturnHome:
            if ([self.backend respondsToSelector:@selector(returnHome:)]) accepted=[self.backend returnHome:&error];
            else error=[NSError errorWithDomain:@"ClashAssist.Backend" code:20 userInfo:@{NSLocalizedDescriptionKey:@"后端未实现 returnHome:，拒绝假装已返回家园"}];
            break;
        default: break;
    }
    CAEvent(@"action.result",@{@"runID":self.runID ?: @"",@"actionID":actionID,@"action":actionName,@"accepted":@(accepted),@"acceptedIsNotSuccess":@(YES),@"phase":CAPhaseName(_battle.phase),@"error":error.localizedDescription ?: @"",@"errorDomain":error.domain ?: @"",@"errorCode":@(error.code)});
    if (!accepted) {
        [self.backend cancelPendingActions]; CABattleFail(&_battle,"backend-action-rejected");
        [self.timer invalidate]; self.timer=nil;
    }
}
- (BOOL)start:(CABattleConfig)config error:(NSError **)error {
    if (!NSThread.isMainThread || self.running) return [self fail:@"任务已运行或当前不在主线程" error:error];
    self.runID=NSUUID.UUID.UUIDString; self.runStartedMonotonic=NSProcessInfo.processInfo.systemUptime; self.sampleCount=0; self.duplicateRevisionCount=0; self.hasLastWorld=NO;
    if (!self.backend) return [self fail:@"未接入真实游戏后端；没有真实状态读取或动作接口，不会运行模拟" error:error];
    if (UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return [self fail:@"游戏须在前台" error:error];
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier, *build=NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"];
    CAEvent(@"backend.compatibility",@{@"runID":self.runID,@"actualBundleID":bundle ?: @"",@"expectedBundleID":self.backend.expectedBundleID ?: @"",@"actualBuildVersion":build ?: @"",@"expectedBuildVersion":self.backend.expectedBuildVersion ?: @"",@"exactMatch":@([bundle isEqual:self.backend.expectedBundleID] && [build isEqual:self.backend.expectedBuildVersion])});
    if (!self.backend.expectedBuildVersion.length || ![bundle isEqual:self.backend.expectedBundleID] || ![build isEqual:self.backend.expectedBuildVersion]) return [self fail:@"游戏构建版本与后端不匹配" error:error];
    NSError *validationError=nil;
    if (![self.backend validate:&validationError]) {
        self.backendValidationPassed=NO;
        self.backendValidationError=validationError.localizedDescription ?: @"validation failed without NSError";
        if (error) *error=validationError ?: [NSError errorWithDomain:@"ClashAssist.Backend" code:21 userInfo:@{NSLocalizedDescriptionKey:@"后端验证失败但没有 NSError"}];
        CAEvent(@"backend.validation.failed",@{@"runID":self.runID,@"error":validationError.localizedDescription ?: @"validation failed",@"errorDomain":validationError.domain ?: @"",@"errorCode":@(validationError.code)}); return NO;
    }
    self.backendValidationPassed=YES; self.backendValidationError=@"";
    CAEvent(@"backend.validation.passed",@{@"runID":self.runID,@"name":self.backend.backendName ?: @"",@"requiredWorldFieldsByScene":@{@"home":@(CAWorldRequiredFields(CAHome)),@"opponent":@(CAWorldRequiredFields(CAOpponent)),@"fighting":@(CAWorldRequiredFields(CAFighting)),@"settlement":@(CAWorldRequiredFields(CASettlement))}});
    CAWorld world; NSError *readError=nil;
    if (![self read:&world error:&readError]) { if (error) *error=readError; return [self fail:readError.localizedDescription ?: @"读取游戏状态失败" error:error]; }
    double now=NSProcessInfo.processInfo.systemUptime;
    CAAction action=CABattleStart(&_battle,config,world,now);
    CAEvent(@"run.start",@{@"runID":self.runID,@"world":[self worldFields:world],@"config":@{@"minGold":@(config.minGold),@"minElixir":@(config.minElixir),@"minDark":@(config.minDark),@"maxSearch":@(config.maxSearch),@"maxUnits":@(config.maxUnits),@"actionTimeout":@(config.actionTimeout),@"battleTimeout":@(config.battleTimeout),@"noLootGrowthTimeout":@(config.noLootGrowthTimeout)}});
    [self logDecision:action];
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
    if (![self read:&world error:&error]) {
        CABattleFail(&_battle,"backend-read-failed");
        CAEvent(@"runtime.fail-closed",@{@"runID":self.runID ?: @"",@"reason":@"backend-read-failed",@"error":error.localizedDescription ?: @"unknown"});
    } else {
        CAPhase previous=_battle.phase; uint64_t revision=_battle.lastRevision;
        CAAction action=CABattleTick(&_battle,world,NSProcessInfo.processInfo.systemUptime);
        if (previous!=_battle.phase) CAEvent(@"state.transition",@{@"runID":self.runID ?: @"",@"actionID":self.pendingActionID ?: @"",@"fromPhase":CAPhaseName(previous),@"toPhase":CAPhaseName(_battle.phase),@"reason":[NSString stringWithUTF8String:_battle.reason ?: ""],@"fromRevision":@(revision),@"toRevision":@(world.revision),@"world":[self worldFields:world]});
        [self logDecision:action];
        [self perform:action];
    }
    if (!self.running) {
        [self.backend cancelPendingActions]; [self.timer invalidate]; self.timer=nil;
        CAEvent(@"run.finished",@{@"runID":self.runID ?: @"",@"snapshot":[self snapshot]});
    }
}
- (void)stop:(NSString *)reason {
    NSAssert(NSThread.isMainThread,@"main thread required");
    ++self.runGeneration; [self.timer invalidate]; self.timer=nil;
    if (self.running) { [self.backend cancelPendingActions]; _battle.phase=CAIdle; _battle.reason="stopped"; CAEvent(@"run.stopped",@{@"runID":self.runID ?: @"",@"reason":reason ?: @"manual",@"lastWorld":self.hasLastWorld ? [self worldFields:self.lastWorld] : @{},@"sampleCount":@(self.sampleCount),@"duplicateRevisionCount":@(self.duplicateRevisionCount)}); }
}
- (NSDictionary *)backendReadiness {
    NSString *actualBundle=NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *actualBuild=NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"";
    BOOL connected=(self.backend!=nil);
    BOOL bundleMatch=connected && self.backend.expectedBundleID.length && [actualBundle isEqual:self.backend.expectedBundleID];
    BOOL buildMatch=connected && self.backend.expectedBuildVersion.length && [actualBuild isEqual:self.backend.expectedBuildVersion];
    NSDictionary *methods=@{
        @"validate":@(connected && [self.backend respondsToSelector:@selector(validate:)]),
        @"readWorld":@(connected && [self.backend respondsToSelector:@selector(readWorld:error:)]),
        @"searchOpponent":@(connected && [self.backend respondsToSelector:@selector(searchOpponent:)]),
        @"deployOneUnit":@(connected && [self.backend respondsToSelector:@selector(deployOneUnit:)]),
        @"endBattle":@(connected && [self.backend respondsToSelector:@selector(endBattle:)]),
        @"returnHome":@(connected && [self.backend respondsToSelector:@selector(returnHome:)]),
        @"cancelPendingActions":@(connected && [self.backend respondsToSelector:@selector(cancelPendingActions)])
    };
    NSMutableArray *blockers=[NSMutableArray new];
    if (!connected) [blockers addObject:@"backend-not-registered"];
    if (connected && !bundleMatch) [blockers addObject:@"bundle-id-mismatch"];
    if (connected && !buildMatch) [blockers addObject:@"build-version-mismatch"];
    if (connected && !self.backendValidationPassed) [blockers addObject:@"backend-validation-not-passed"];
    for (NSString *method in methods) if (![methods[method] boolValue]) [blockers addObject:[@"missing-method:" stringByAppendingString:method]];
    uint32_t missing=self.hasLastWorld ? CAWorldMissingFields(self.lastWorld) : CAWorldBaseFields;
    BOOL fresh=self.hasLastWorld && self.lastWorld.observedAtMonotonic>0 && (NSProcessInfo.processInfo.systemUptime-self.lastWorld.observedAtMonotonic)<=1.5;
    if (!self.hasLastWorld) [blockers addObject:@"no-successful-live-world-snapshot"];
    else if (missing) [blockers addObject:@"live-world-snapshot-missing-required-fields"];
    if (self.hasLastWorld && !fresh) [blockers addObject:@"live-world-snapshot-stale"];
    return @{@"connected":@(connected), @"backendName":self.backend.backendName ?: @"not-connected",
        @"actualBundleID":actualBundle, @"expectedBundleID":self.backend.expectedBundleID ?: @"",
        @"bundleIDMatches":@(bundleMatch), @"actualBuildVersion":actualBuild,
        @"expectedBuildVersion":self.backend.expectedBuildVersion ?: @"", @"buildVersionMatches":@(buildMatch),
        @"backendValidationPassed":@(self.backendValidationPassed), @"backendValidationError":self.backendValidationError ?: @"not-run",
        @"requiredMethods":methods, @"hasSuccessfulWorldSnapshot":@(self.hasLastWorld),
        @"worldSnapshotFresh":@(fresh), @"worldSnapshotMissingFields":CAMissingFieldNames(missing),
        @"automaticBattleReady":@(blockers.count==0), @"blockers":blockers,
        @"note":@"该报告只检查后端接线、构建匹配、validate 结果和最近状态快照。它不会验证游戏函数语义，也不会把调用来源偏移转换成 API。"};
}
- (NSDictionary *)snapshot {
    return @{@"backend":self.backend.backendName ?: @"not-connected",@"backendConnected":@(self.backend!=nil),@"backendReadiness":[self backendReadiness],@"runID":self.runID ?: @"",@"running":@(self.running),@"phase":@(_battle.phase),@"phaseName":CAPhaseName(_battle.phase),@"reason":[NSString stringWithUTF8String:_battle.reason ?: "idle"],@"searches":@(_battle.searches),@"completedBattles":@(_battle.completedBattles),@"confirmedDeployed":@(_battle.deployed),@"sampleCount":@(self.sampleCount),@"duplicateRevisionCount":@(self.duplicateRevisionCount),@"runStartedMonotonic":@(self.runStartedMonotonic),@"lastWorld":self.hasLastWorld ? [self worldFields:self.lastWorld] : @{},@"noLootGrowthTimeoutSeconds":@(_battle.config.noLootGrowthTimeout),@"lastLootGrowthAtMonotonic":@(_battle.lastLootGrowthAt),@"lootGrowthAgeMs":@(_battle.lootBaselineSet ? MAX(0,(NSProcessInfo.processInfo.systemUptime-_battle.lastLootGrowthAt)*1000.0) : -1)};
}
@end
