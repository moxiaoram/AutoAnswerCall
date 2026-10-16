#import <Foundation/Foundation.h>
#import "../AACRecords.h"
#import "../AACCallLifecycle.h"
#include <assert.h>
#include <stdio.h>
int main(void){@autoreleasepool{
 NSString *a=NSUUID.UUID.UUIDString,*b=NSUUID.UUID.UUIDString;NSDate *first=[NSDate dateWithTimeIntervalSince1970:100];
 NSArray *rows=AACRecordUpdate(@[],a,nil,@"等待",nil,first);
 rows=AACRecordUpdate(rows,a,nil,@"等待",nil,[first dateByAddingTimeInterval:1]);
 assert(rows.count==1&&[rows[0][@"events"] count]==1);assert([rows[0][@"timestamp"] isEqual:first]);assert(rows[0][@"caller"]==nil);
 rows=AACRecordUpdate(rows,a,nil,@"提交",@{@"submitted":@YES},first);assert([AACRecordResult(rows[0]) containsString:@"未确认连接"]);
 rows=AACRecordUpdate(rows,a,nil,@"接受",@{@"accepted":@YES},first);assert(![rows[0][@"connected"] boolValue]);assert([AACRecordResult(rows[0]) containsString:@"未确认连接"]);
 rows=AACRecordUpdate(rows,a,nil,@"连接",@{@"connected":@YES},first);
 rows=AACRecordUpdate(rows,a,nil,@"迟到的失败回调",@{@"failed":@YES},first);assert([AACRecordResult(rows[0]) containsString:@"不能确定"]);
 rows=AACRecordUpdate(rows,a,nil,@"结束",@{@"ended":@YES},first);assert([AACRecordResult(rows[0]) containsString:@"归因未确认"]);
 rows=AACRecordUpdate(rows,b,@"+861234",@"跳过",nil,[first dateByAddingTimeInterval:2]);assert([rows[0][@"id"] isEqual:b]);assert([rows[0][@"caller"] isEqual:@"+861234"]);
 for(int i=0;i<40;i++)rows=AACRecordUpdate(rows,b,nil,[NSString stringWithFormat:@"event %d",i],nil,first);assert([rows[0][@"events"] count]==24);
 for(int i=0;i<250;i++)rows=AACRecordUpdate(rows,NSUUID.UUID.UUIDString,nil,@"跳过",nil,[first dateByAddingTimeInterval:i+3]);assert(rows.count==200);
 NSData *data=[NSPropertyListSerialization dataWithPropertyList:rows format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];assert(data.length);assert(AACValidRecords([NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil]).count==200);
 assert(AACValidRecords(@"corrupt").count==0);assert(AACValidRecords(@[@{@"id":@"bad",@"timestamp":first,@"events":@[]}]).count==0);
 NSArray *empty=AACValidRecords(@[]);assert(!empty.count);
 NSMutableDictionary *waiting=[@{@"scheduled":@YES,@"pending":@NO} mutableCopy];NSUInteger gen=[waiting[@"callGeneration"] unsignedIntegerValue];
 assert(AACMaySubmit(waiting,gen,YES,NO,NO));AACCancelForObservedConnection(waiting);
 assert(![waiting[@"scheduled"] boolValue]&&![waiting[@"pending"] boolValue]);assert(!AACMaySubmit(waiting,gen,YES,NO,NO));assert(!AACMayAutoplay(waiting));
 waiting[@"accepted"]=@YES;assert(!AACMayAutoplay(waiting)); /* late completion never reverses manual/system suppression */
 for(int order=0;order<2;order++){
  NSMutableDictionary *race=[@{@"submitted":@YES,@"pending":@YES} mutableCopy];
  if(order==0)race[@"accepted"]=@YES;AACCancelForObservedConnection(race);if(order==1)race[@"accepted"]=@YES;
  assert(!AACMayAutoplay(race));assert(!AACMaySubmit(race,0,YES,YES,NO));
 }
 assert(!AACMaySubmit(@{},0,YES,YES,NO));assert(!AACMaySubmit(@{},0,YES,NO,YES));assert(!AACMaySubmit(@{},0,NO,NO,NO));
 puts("PASS: pending timer -> observed manual/system connection -> cancelled UUID; live connected/ended/absent requery; accepted-before/after-connection ambiguity never autoplays; selected/imported audio untouched");
 puts("PASS: Foundation records UUID upsert, duplicate-event suppression, first timestamp, unknown caller, accepted != connected, late callback truth, sort, 200-record/24-event bounds, plist roundtrip, invalid data rejection (macOS model; NOT device runtime)");
 }return 0;}
