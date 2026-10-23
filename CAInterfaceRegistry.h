#import <Foundation/Foundation.h>

/* Correlates pass-through Hook events and manual screen-state snapshots.
   This analyzer never resolves or invokes game functions. */
NSDictionary *CAAnalyzeObservedInterfaces(NSDictionary *observation, NSDictionary *journal, NSString *validationSessionID);
