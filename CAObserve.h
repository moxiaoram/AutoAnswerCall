#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, CAObserveMarker) {
    CAObserveMarkerSearchBefore = 1,
    CAObserveMarkerSearchResultVisible = 2,
    CAObserveMarkerDeployBefore = 3,
    CAObserveMarkerDeployObserved = 4,
    CAObserveMarkerEndBattleBefore = 5,
    CAObserveMarkerSettlementVisible = 6,
    CAObserveMarkerNextRoundVisible = 7,
    CAObserveMarkerOther = 8,
};

typedef NS_ENUM(NSUInteger, CAObserveStopReason) {
    CAObserveStopManual = 1,
    CAObserveStopTimeout = 2,
    CAObserveStopRestarted = 3,
    CAObserveStopBackground = 4,
};

// Observation only: original calls are passed through unchanged; no game action API.
BOOL CAObserveStart(NSString **error);
BOOL CAObserveIsActive(void);
void CAObserveStop(void);
void CAObserveStopWithReason(CAObserveStopReason reason);
void CAObserveMark(CAObserveMarker marker);
NSDictionary *CAObserveSnapshot(void);
