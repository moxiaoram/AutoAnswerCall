#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <assert.h>
#include <stdio.h>
static NSString *TestDir;
static NSString *TestSuite;
static NSString *LocalDir(NSError **e){return TestDir;}
static NSUserDefaults *Defaults(void){return [[NSUserDefaults alloc] initWithSuiteName:TestSuite];}
static NSString *ErrorText(NSError *e,NSString *fallback){return e.localizedDescription?:fallback;}
#define AAC_LIBRARY_MODEL_ONLY 1
#import "../Preferences/AACAudioLibrary.h"
static NSDictionary *Entry(NSString *ident,NSString *path){return @{@"id":ident,@"path":path,@"name":ident,@"size":@3,@"duration":@1.25};}
int main(void){@autoreleasepool{
 TestDir=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"aac-library-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
 TestSuite=[@"aac-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
 assert([[NSFileManager defaultManager] createDirectoryAtPath:TestDir withIntermediateDirectories:YES attributes:nil error:nil]);
 NSString *oldPath=[TestDir stringByAppendingPathComponent:@"legacy.mp3"];assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:oldPath atomically:YES]);
 NSDictionary *old=@{@"AudioPath":oldPath,@"AudioName":@"legacy.mp3",@"AudioSize":@3};assert([old writeToFile:[TestDir stringByAppendingPathComponent:@"audio.plist"] atomically:YES]);
 AACAudioLibrary *lib=[AACAudioLibrary new];assert(!lib.failure);assert(lib.items.count==1);assert([lib.selected isEqual:lib.items.firstObject[@"id"]]);assert([lib.items.firstObject[@"path"] isEqual:oldPath]);assert([[NSFileManager defaultManager] fileExistsAtPath:oldPath]);
 NSString *migrated=lib.selected;AACAudioLibrary *reload=[AACAudioLibrary new];assert(reload.items.count==1&&[reload.selected isEqual:migrated]);
 NSString *second=[TestDir stringByAppendingPathComponent:@"second.mp3"];assert([[@"def" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:second atomically:YES]);
 NSDictionary *two=Entry(@"two",second);[lib.items addObject:two];assert([lib save]);assert([lib.selected isEqual:migrated]);assert([[NSFileManager defaultManager] fileExistsAtPath:oldPath]);
 assert([lib select:two]);assert([[Defaults() stringForKey:@"AudioPath"] isEqual:second]);assert([[Defaults() stringForKey:@"SelectedAudioID"] isEqual:@"two"]);
 NSDictionary *metadata=[NSDictionary dictionaryWithContentsOfFile:[TestDir stringByAppendingPathComponent:@"audio.plist"]];assert([metadata[@"AudioPath"] isEqual:second]);assert(metadata[@"Items"]==nil);
 NSDictionary *shared=Entry(@"shared",second);[lib.items addObject:shared];assert([lib save]);assert([lib remove:two]);assert([[NSFileManager defaultManager] fileExistsAtPath:second]);assert([lib.selected isEqual:migrated]);
 assert([lib remove:shared]);assert(![[NSFileManager defaultManager] fileExistsAtPath:second]);assert([[NSFileManager defaultManager] fileExistsAtPath:oldPath]);
 assert([lib remove:lib.items.firstObject]);assert(lib.items.count==0&&!lib.selected);assert([Defaults() objectForKey:@"AudioPath"]==nil);assert(![[NSFileManager defaultManager] fileExistsAtPath:[TestDir stringByAppendingPathComponent:@"audio.plist"]]);assert(![[NSFileManager defaultManager] fileExistsAtPath:oldPath]);
 NSString *missing=[TestDir stringByAppendingPathComponent:@"missing.mp3"];[lib.items addObject:Entry(@"missing",missing)];assert([lib save]);assert([lib remove:lib.items.firstObject]);
 assert([@{@"Items":@"corrupt"} writeToFile:[TestDir stringByAppendingPathComponent:@"audio-library.plist"] atomically:YES]);AACAudioLibrary *bad=[AACAudioLibrary new];assert(bad.failure&&![bad save]);
 [Defaults() removePersistentDomainForName:TestSuite];[[NSFileManager defaultManager] removeItemAtPath:TestDir error:nil];
 puts("PASS: real ObjC library migration-in-place, UUID selection persistence, append preserves selection/files, selected-only metadata, shared-path retention, next selection, last deletion cleanup, missing removal, corrupt-library fail-closed (macOS model; NOT iOS UI/import runtime)");
 }return 0;}
