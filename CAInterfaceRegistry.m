#import "CAInterfaceRegistry.h"

static NSArray<NSDictionary *> *CAOperationWindows(void) {
    return @[
      @{ @"operation": @"search", @"startMarker": @"即将点击搜索对手", @"endMarker": @"对手战场/搜索结果已显示", @"interpretation": @"搜索前到搜索结果出现之间的时间关联" },
      @{ @"operation": @"deploy", @"startMarker": @"即将选择或部署兵力", @"endMarker": @"已观察到兵力部署结果", @"interpretation": @"选择/部署前到人工观察到结果之间的时间关联" },
      @{ @"operation": @"endBattle", @"startMarker": @"即将手动结束战斗", @"endMarker": @"已看到结算界面", @"interpretation": @"手动结束前到结算界面出现之间的时间关联" },
      @{ @"operation": @"nextRound", @"startMarker": @"已看到结算界面", @"endMarker": @"已看到下一轮/新对手界面", @"interpretation": @"结算界面到下一轮/新对手界面之间的时间关联" }
    ];
}

static NSString *CAKey(NSString *kind, NSString *caller) {
    return [NSString stringWithFormat:@"%@|%@", kind ?: @"unknown", caller ?: @"unknown"];
}

NSDictionary *CAAnalyzeObservedInterfaces(NSDictionary *observation, NSDictionary *journal, NSString *validationSessionID) {
    NSArray *timeline = [observation[@"timeline"] isKindOfClass:NSArray.class] ? observation[@"timeline"] : @[];
    NSMutableArray *windows = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSDictionary *> *firstMarker = [NSMutableDictionary new];
    for (NSDictionary *event in timeline) {
        if (![event[@"phase"] isEqual:@"marker"]) continue;
        NSString *marker = [event[@"marker"] isKindOfClass:NSString.class] ? event[@"marker"] : @"";
        if (marker.length && !firstMarker[marker]) firstMarker[marker] = event;
    }
    for (NSDictionary *definition in CAOperationWindows()) {
        NSDictionary *start = firstMarker[definition[@"startMarker"]];
        NSDictionary *end = firstMarker[definition[@"endMarker"]];
        BOOL complete = start && end && [end[@"elapsedMs"] doubleValue] >= [start[@"elapsedMs"] doubleValue];
        NSMutableDictionary *window = [@{ @"operation": definition[@"operation"],
            @"interpretation": definition[@"interpretation"], @"complete": @(complete),
            @"calls": @[], @"candidateCount": @0,
            @"semanticProof": @NO, @"signatureVerified": @NO, @"invocationAllowed": @NO } mutableCopy];
        if (complete) {
            double begin = [start[@"elapsedMs"] doubleValue], finish = [end[@"elapsedMs"] doubleValue];
            window[@"startElapsedMs"] = @(begin); window[@"endElapsedMs"] = @(finish);
            window[@"windowDurationMs"] = @(finish - begin);
            NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary new];
            for (NSDictionary *event in timeline) {
                if (![event[@"phase"] isEqual:@"enter"]) continue;
                double t = [event[@"elapsedMs"] doubleValue];
                if (t < begin || t > finish) continue;
                NSString *kind = [event[@"kind"] isKindOfClass:NSString.class] ? event[@"kind"] : @"unknown";
                NSString *caller = [event[@"callerOffset"] isKindOfClass:NSString.class] ? event[@"callerOffset"] : @"unknown";
                NSString *key = CAKey(kind, caller);
                NSMutableDictionary *g = groups[key];
                if (!g) { g = [@{ @"hook": kind, @"callerOffset": caller, @"calls": @0, @"mainThreadCalls": @0, @"callIDs": [NSMutableArray new] } mutableCopy]; groups[key] = g; }
                g[@"calls"] = @([g[@"calls"] unsignedIntegerValue] + 1);
                if ([event[@"mainThread"] boolValue]) g[@"mainThreadCalls"] = @([g[@"mainThreadCalls"] unsignedIntegerValue] + 1);
                if (event[@"callID"] && ![g[@"callIDs"] containsObject:event[@"callID"]]) [g[@"callIDs"] addObject:event[@"callID"]];
            }
            NSArray *sorted = [[groups allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"calls"] compare:a[@"calls"]]; }];
            NSMutableArray *safeGroups = [NSMutableArray new];
            for (NSDictionary *g in sorted) [safeGroups addObject:@{ @"hook": g[@"hook"], @"callerOffset": g[@"callerOffset"], @"calls": g[@"calls"], @"mainThreadCalls": g[@"mainThreadCalls"], @"callIDs": g[@"callIDs"] }];
            window[@"calls"] = safeGroups; window[@"candidateCount"] = @(safeGroups.count);
        } else {
            NSMutableArray *missingMarkers = [NSMutableArray new];
            if (!start) [missingMarkers addObject:definition[@"startMarker"]];
            if (!end) [missingMarkers addObject:definition[@"endMarker"]];
            window[@"missingMarkers"] = missingMarkers;
        }
        [windows addObject:window];
    }
    NSArray *hooks = [observation[@"installDiagnostics"] isKindOfClass:NSArray.class] ? observation[@"installDiagnostics"] : @[];
    NSMutableArray *registered = [NSMutableArray new];
    for (NSDictionary *hook in hooks) {
        [registered addObject:@{ @"name": hook[@"name"] ?: @"unknown", @"targetOffset": hook[@"offset"] ?: @"unknown",
            @"hookInstalled": hook[@"hookInstalled"] ?: @NO, @"fingerprintMatched": hook[@"fingerprintMatched"] ?: @NO,
            @"signatureVerified": hook[@"signatureVerified"] ?: @NO, @"invocationAllowed": @NO,
            @"reason": @"指纹匹配和 Hook 安装不等于 ABI/参数/语义已验证；仅保留透传观测" }];
    }
    NSDictionary *observedBaseline = @{
        @"sourceFile": @"部落4.json",
        @"purpose": @"read-only observed correlation fixture; never an executable API table",
        @"observedSessionDurationMs": @79338.3955,
        @"markersAndCalls": @[
            @{@"operation":@"search", @"marker":@"即将点击搜索对手", @"elapsedMs":@2349.4564},
            @{@"operation":@"search", @"hook":@"统一命令提交候选", @"callerOffset":@"0xba1fe8", @"elapsedMs":@7069.3787, @"durationMs":@2.7096},
            @{@"operation":@"search", @"marker":@"对手战场/搜索结果已显示", @"elapsedMs":@16661.1807},
            @{@"operation":@"deploy", @"marker":@"即将选择或部署兵力", @"elapsedMs":@24350.5382},
            @{@"operation":@"deploy", @"hook":@"统一命令提交候选", @"callerOffset":@"0x69ab9c", @"elapsedMs":@26168.7980, @"durationMs":@0.0643},
            @{@"operation":@"deploy", @"hook":@"统一命令提交候选", @"callerOffset":@"0xf9aac4", @"elapsedMs":@26269.3188, @"durationMs":@0.0020},
            @{@"operation":@"deploy", @"marker":@"已观察到兵力部署结果", @"elapsedMs":@33465.8767},
            @{@"operation":@"endBattle", @"marker":@"即将手动结束战斗", @"elapsedMs":@42465.0149},
            @{@"operation":@"endBattle", @"hook":@"普通按钮分发", @"callerOffset":@"0xc153e4", @"elapsedMs":@43765.4790, @"durationMs":@6.7979},
            @{@"operation":@"endBattle", @"hook":@"结束确认候选", @"callerOffset":@"0xc6a17c", @"elapsedMs":@44833.0393, @"durationMs":@0.0043},
            @{@"operation":@"endBattle", @"hook":@"统一命令提交候选", @"callerOffset":@"0x5dfde0", @"elapsedMs":@44833.0408, @"depth":@2, @"durationMs":@0.0018},
            @{@"operation":@"endBattle", @"marker":@"结算界面已显示", @"elapsedMs":@51864.2009},
            @{@"operation":@"nextRound", @"hook":@"统一命令提交候选", @"callerOffset":@"0xba1fe8", @"elapsedMs":@64823.8840, @"durationMs":@0.0008},
            @{@"operation":@"nextRound", @"marker":@"下一轮/新对手已显示", @"elapsedMs":@74957.4144}
        ],
        @"signatureVerified": @NO,
        @"semanticProof": @NO,
        @"invocationAllowed": @NO
    };
    NSArray *journalEvents = [journal[@"events"] isKindOfClass:NSArray.class] ? journal[@"events"] : @[];
    NSMutableArray<NSDictionary *> *manualSnapshots = [NSMutableArray new];
    for (NSDictionary *event in journalEvents) {
        if (![event[@"event"] isEqual:@"validation.manualStateSnapshot"]) continue;
        NSDictionary *fields = [event[@"fields"] isKindOfClass:NSDictionary.class] ? event[@"fields"] : @{};
        if (!validationSessionID.length || ![fields[@"validationSessionID"] isEqual:validationSessionID]) continue;
        [manualSnapshots addObject:@{@"seq":event[@"seq"] ?: @0,
            @"wallTime":event[@"wallTime"] ?: @"unknown",
            @"elapsedMs":event[@"elapsedMs"] ?: NSNull.null,
            @"snapshotID":fields[@"snapshotID"] ?: @"unknown",
            @"scene":fields[@"scene"] ?: @"unknown",
            @"opponentLoot":fields[@"opponentLoot"] ?: @{},
            @"cumulativeLoot":fields[@"cumulativeLoot"] ?: @{},
            @"remainingTroops":fields[@"remainingTroops"] ?: NSNull.null,
            @"deployedTroops":fields[@"deployedTroops"] ?: NSNull.null,
            @"dataSource":fields[@"dataSource"] ?: @"unknown",
            @"authoritativeGameAPI":fields[@"authoritativeGameAPI"] ?: @NO}];
    }
    NSMutableArray<NSDictionary *> *stateDeltas = [NSMutableArray new];
    NSDictionary *previous = nil;
    for (NSDictionary *current in manualSnapshots) {
        if (previous) {
            NSMutableDictionary *delta = [@{@"fromSnapshotID":previous[@"snapshotID"],
                @"toSnapshotID":current[@"snapshotID"], @"sceneChanged":@(![previous[@"scene"] isEqual:current[@"scene"]]),
                @"source":@"manual-visible-screen-entry", @"authoritative":@NO} mutableCopy];
            for (NSString *groupKey in @[@"opponentLoot", @"cumulativeLoot"]) {
                NSDictionary *beforeGroup = previous[groupKey]; NSDictionary *afterGroup = current[groupKey];
                NSMutableDictionary *groupDelta = [NSMutableDictionary new];
                for (NSString *resourceKey in @[@"gold", @"elixir", @"dark"]) {
                    id before = beforeGroup[resourceKey]; id after = afterGroup[resourceKey];
                    if ([before isKindOfClass:NSNumber.class] && [after isKindOfClass:NSNumber.class])
                        groupDelta[resourceKey] = @([after longLongValue] - [before longLongValue]);
                    else groupDelta[resourceKey] = NSNull.null;
                }
                delta[[groupKey stringByAppendingString:@"Delta"]] = groupDelta;
            }
            id beforeRemaining = previous[@"remainingTroops"], afterRemaining = current[@"remainingTroops"];
            id beforeDeployed = previous[@"deployedTroops"], afterDeployed = current[@"deployedTroops"];
            delta[@"remainingTroopsDelta"] = ([beforeRemaining isKindOfClass:NSNumber.class] && [afterRemaining isKindOfClass:NSNumber.class])
                ? @([afterRemaining longLongValue] - [beforeRemaining longLongValue]) : NSNull.null;
            delta[@"deployedTroopsDelta"] = ([beforeDeployed isKindOfClass:NSNumber.class] && [afterDeployed isKindOfClass:NSNumber.class])
                ? @([afterDeployed longLongValue] - [beforeDeployed longLongValue]) : NSNull.null;
            [stateDeltas addObject:delta];
        }
        previous = current;
    }
    NSDictionary *manualStateAnalysis = @{@"snapshotCount":@(manualSnapshots.count),
        @"snapshots":manualSnapshots, @"adjacentStateDeltas":stateDeltas,
        @"source":@"manual-visible-screen-entry", @"validationSessionID":validationSessionID ?: @"",
        @"authoritativeGameAPI":@NO,
        @"note":@"这些值由操作者按真实画面手动录入，用于真机状态变化核对；不是插件直接读取的游戏内状态，不得用于自动化决策。空值表示未知，不等于零。"};
    return @{@"schemaVersion": @2, @"mode": @"real-device-passive-validation", @"operationWindows": windows,
        @"hookRegistry": registered, @"observedBaseline": observedBaseline,
        @"manualStateAnalysis":manualStateAnalysis, @"invocationAllowed": @NO,
        @"safetyGate": @"所有候选均为只读观测；在 ABI、对象生命周期、线程约束及语义均被独立验证前，禁止调用或重放原始参数",
        @"sourceNote": @"时间相关性不证明函数语义；callerOffset 是调用来源位置，不是被 Hook 函数本身的地址。人工画面快照也不是权威游戏 API 数据。"};
}
