#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface AACRootListController : PSListController <UIDocumentPickerDelegate>
@end
static NSString *AACSharedDir(void) { return @"/var/jb/Library/Application Support/AutoAnswerCall"; }
static NSString *AACAudioPath(void) { NSString *p=[[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"] stringForKey:@"AudioPath"]; return p.length?p:[AACSharedDir() stringByAppendingPathComponent:@"answer-audio"]; }
static NSString *AACLogPath(void) { return [AACSharedDir() stringByAppendingPathComponent:@"AutoAnswerCall.log"]; }
static void AACLog(NSString *s) { NSString *line=[NSString stringWithFormat:@"[%@] %@\n",[NSDate date],s]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d setObject:line forKey:@"LastStatus"]; NSString *old=[d stringForKey:@"LastLog"]?:@""; NSString *all=[old stringByAppendingString:line]; if(all.length>12000) all=[all substringFromIndex:all.length-12000]; [d setObject:all forKey:@"LastLog"]; [d synchronize]; [[NSFileManager defaultManager] createDirectoryAtPath:AACSharedDir() withIntermediateDirectories:YES attributes:nil error:nil]; NSString *p=[AACSharedDir() stringByAppendingPathComponent:@"AutoAnswerCall.log"]; NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:p]; if(!h){[line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];}else{[h seekToEndOfFile];[h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];} }
@implementation AACRootListController
- (NSArray *)specifiers {
 if (!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];
 return _specifiers;
}
- (void)pickAudio:(PSSpecifier *)specifier {
 UTType *audioType=[UTType typeWithIdentifier:@"public.audio"];
 UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[audioType]];
 picker.delegate=self; picker.allowsMultipleSelection=NO; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
 NSURL *source=urls.firstObject; if (!source) return;
 BOOL scoped=[source startAccessingSecurityScopedResource];
 NSString *dir=AACSharedDir();
 [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *name=source.lastPathComponent.length?source.lastPathComponent:@"answer-audio";
 NSURL *dest=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]; [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
 NSError *error=nil; NSData *data=[NSData dataWithContentsOfURL:source options:NSDataReadingMappedIfSafe error:&error]; BOOL ok=data.length>0 && [data writeToURL:dest options:NSDataWritingAtomic error:&error]; if(scoped)[source stopAccessingSecurityScopedResource];
 if(ok){ NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d setObject:dest.path forKey:@"AudioPath"]; [d synchronize]; AACLog([NSString stringWithFormat:@"音频导入成功：%@",dest.lastPathComponent]); [self reloadSpecifiers]; }
 else { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:0 handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
}
- (void)testAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { AACLog(@"试听失败：共享音频不存在"); return; }
 NSError *error=nil; AVAudioPlayer *player=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error]; if(error){AACLog([NSString stringWithFormat:@"试听失败：%@",error.localizedDescription]);return;} [player prepareToPlay]; [player play]; AACLog(@"试听开始"); objc_setAssociatedObject(self,@selector(testAudio:),player,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)showLog:(PSSpecifier *)specifier { NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; NSString *text=[d stringForKey:@"LastLog"]; if(!text.length) text=[NSString stringWithContentsOfFile:AACLogPath() encoding:NSUTF8StringEncoding error:nil]; if(!text.length) text=@"暂无日志：请先点击测试播放或接听一次电话。\n当前设置进程无法看到电话进程日志时，最近状态会仍显示在配置域。"; UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero]; v.text=text; v.editable=NO; v.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; UIViewController *c=[UIViewController new]; c.view.backgroundColor=UIColor.systemBackgroundColor; v.frame=c.view.bounds; v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [c.view addSubview:v]; c.title=@"自动接听运行日志"; [self.navigationController pushViewController:c animated:YES]; }
- (void)showCallRecords:(PSSpecifier *)specifier { NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; NSString *text=[d stringForKey:@"CallRecords"]?:@"暂无自动接听记录"; UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero]; v.text=text; v.editable=NO; v.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]; UIViewController *c=[UIViewController new]; c.view.backgroundColor=UIColor.systemBackgroundColor; v.frame=c.view.bounds; v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [c.view addSubview:v]; c.title=@"自动接听记录"; [self.navigationController pushViewController:c animated:YES]; }
- (void)clearLog:(PSSpecifier *)specifier { [[NSFileManager defaultManager] removeItemAtPath:AACLogPath() error:nil]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d removeObjectForKey:@"LastLog"]; [d removeObjectForKey:@"LastStatus"]; [d synchronize]; }
- (void)clearAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d removeObjectForKey:@"AudioPath"]; [d synchronize]; [self reloadSpecifiers];
}
@end
