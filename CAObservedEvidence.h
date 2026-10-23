#import <Foundation/Foundation.h>

/* Sanitized facts from the supplied report. This is diagnostic evidence only;
   it deliberately contains no raw pointer values, caller offsets, or inferred action mappings. */
static inline NSDictionary *CAObservedEvidenceSummary(void) {
    return @{
        @"sourceReport": @"部落冲突日志.json",
        @"captureTimeUTC": @"2026-10-23T16:21:05Z",
        @"sourcePluginVersion": @"0.4.0",
        @"targetBuildVersion": @"18.116.1",
        @"osVersion": @"iOS 17.3 (21D50)",
        @"observationDurationMs": @186866.03875,
        @"timelineRecords": @135,
        @"droppedRecords": @0,
        @"hookHits": @{ @"普通按钮分发": @0, @"结束确认候选": @0, @"统一命令提交候选": @67 },
        @"allCandidateSignaturesVerified": @NO,
        @"manualActionMarkersPresent": @NO,
        @"realWorldStateSamplesPresent": @NO,
        @"cumulativeLootSamplesPresent": @NO,
        @"backendAtCapture": @"not-connected",
        @"conclusion": @"仅确认候选调用发生；未确认搜索、部署、结束或资源读取语义。"
    };
}
