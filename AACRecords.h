#import <Foundation/Foundation.h>
/* Foundation-only model, shared by MobilePhone and Settings. No preview writes. */
static NSString *const AACRecordDomain=@"com.autoanswer.call.phone";
static NSUInteger const AACRecordLimit=200;
static inline NSArray *AACValidRecords(id value){
 if(![value isKindOfClass:NSArray.class])return @[];
 NSMutableDictionary *unique=[NSMutableDictionary new];
 for(id r in value){
  if(![r isKindOfClass:NSDictionary.class]||![r[@"id"] isKindOfClass:NSString.class]||![[NSUUID alloc] initWithUUIDString:r[@"id"]]||![r[@"timestamp"] isKindOfClass:NSDate.class]||![r[@"events"] isKindOfClass:NSArray.class])continue;
  unique[r[@"id"]]=r;
 }
 NSArray *sorted=[unique.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult c=[b[@"timestamp"] compare:a[@"timestamp"]];return c==NSOrderedSame?[a[@"id"] compare:b[@"id"]]:c;}];
 return sorted.count>AACRecordLimit?[sorted subarrayWithRange:NSMakeRange(0,AACRecordLimit)]:sorted;
}
static NSString *AACRecordResult(NSDictionary *r){
 if([r[@"connected"] boolValue]&&[r[@"beforeRequest"] boolValue])return [r[@"ended"] boolValue]?@"提交前已连接（手动/系统/其他），现已结束":@"提交前已连接（手动/系统/其他）；已取消自动接听和自动播放";
 if([r[@"connected"] boolValue])return [r[@"ended"] boolValue]?@"曾观察到连接，现已结束（归因未确认）":@"观察到连接（不能确定由插件接听）";
 if([r[@"ended"] boolValue]){
  if([r[@"button"] boolValue])return @"已结束，已尝试按钮动作但未观察到连接";
  if([r[@"submitted"] boolValue])return @"已结束，已提交请求但未观察到连接";
  if([r[@"attempted"] boolValue])return @"已结束，未完成有效接听动作（查看详情）";
  return @"已结束，未触发自动接听（查看详情）";
 }
 if([r[@"failed"] boolValue])return @"请求失败，未确认连接";
 if([r[@"timedOut"] boolValue])return @"观察超时，未确认连接";
 if([r[@"accepted"] boolValue])return @"事务已接受，未确认连接";
 if([r[@"submitted"] boolValue])return @"已提交接听请求，未确认连接";
 return [r[@"status"] isKindOfClass:NSString.class]?r[@"status"]:@"观察到来电";
}
static inline NSArray *AACRecordUpdate(NSArray *items,NSString *ident,NSString *caller,NSString *status,NSDictionary *flags,NSDate *now){
 NSMutableArray *all=[AACValidRecords(items) mutableCopy];NSMutableDictionary *row=nil;NSUInteger index=NSNotFound;
 for(NSUInteger i=0;i<all.count;i++)if([all[i][@"id"] isEqual:ident]){row=[all[i] mutableCopy];index=i;break;}
 if(!row)row=[@{@"id":ident,@"timestamp":now,@"events":@[]} mutableCopy];
 if(caller.length)row[@"caller"]=caller;
 [row addEntriesFromDictionary:flags?:@{}];row[@"status"]=status;row[@"updated"]=now;
 NSMutableArray *events=[row[@"events"] mutableCopy];
 if(![events.lastObject[@"status"] isEqual:status]){
  [events addObject:@{@"timestamp":now,@"status":status}];
  if(events.count>24)[events removeObjectsInRange:NSMakeRange(0,events.count-24)];
 }
 row[@"events"]=events;row[@"result"]=AACRecordResult(row);
 if(index==NSNotFound)[all addObject:row];else all[index]=row;
 return AACValidRecords(all);
}
static inline NSArray *AACReadRecords(BOOL *synced,BOOL *present){
 BOOL ok=CFPreferencesAppSynchronize((__bridge CFStringRef)AACRecordDomain);
 id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Records"),(__bridge CFStringRef)AACRecordDomain));
 if(synced)*synced=ok;if(present)*present=[value isKindOfClass:NSArray.class];return AACValidRecords(value);
}
static inline BOOL AACWriteRecords(NSArray *records){
 CFPreferencesSetAppValue(CFSTR("Records"),(__bridge CFPropertyListRef)records,(__bridge CFStringRef)AACRecordDomain);
 return CFPreferencesAppSynchronize((__bridge CFStringRef)AACRecordDomain);
}
