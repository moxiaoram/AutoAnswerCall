#import <Foundation/Foundation.h>
@class AWEAwemeModel;
@interface DYYYOriginalQualityProvider : NSObject
/// Paid, authenticated third-party API. Never called without an explicit user action.
+ (void)saveToken:(NSString *)token;
+ (void)fetchForAweme:(AWEAwemeModel *)aweme download:(BOOL)download;
@end
