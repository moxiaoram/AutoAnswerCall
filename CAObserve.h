#import <Foundation/Foundation.h>
// Hooks pass original arguments through unchanged. No game action invocation API.
BOOL CAObserveStart(NSString **error);
void CAObserveStop(void);
NSDictionary *CAObserveSnapshot(void);
