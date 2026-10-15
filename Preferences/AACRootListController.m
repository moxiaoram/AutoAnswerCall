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
static void AACLog(NSString *s) { [[NSFileManager defaultManager] createDirectoryAtPath:AACSharedDir() withIntermediateDirectories:YES attributes:nil error:nil]; NSString *line=[NSString stringWithFormat:@"[%@] %@\n",[NSDate date],s]; NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:AACLogPath()]; if(!h){[line writeToFile:AACLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];}else{[h seekToEndOfFile];[h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[h closeFile];} }
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
 NSError *error=nil; BOOL ok=[[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:&error]; if(scoped)[source stopAccessingSecurityScopedResource];
 if(ok){ NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d setObject:dest.path forKey:@"AudioPath"]; [d synchronize]; AACLog([NSString stringWithFormat:@"音频导入成功：%@",dest.lastPathComponent]); [self reloadSpecifiers]; }
 else { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:0 handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
}
- (void)testAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { AACLog(@"试听失败：共享音频不存在"); return; }
 NSError *error=nil; AVAudioPlayer *player=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error]; if(error){AACLog([NSString stringWithFormat:@"试听失败：%@",error.localizedDescription]);return;} [player prepareToPlay]; [player play]; AACLog(@"试听开始"); objc_setAssociatedObject(self,@selector(testAudio:),player,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)showLog:(PSSpecifier *)specifier { NSString *text=[NSString stringWithContentsOfFile:AACLogPath() encoding:NSUTF8StringEncoding error:nil] ?: @"暂无日志"; UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero]; v.text=text; v.editable=NO; v.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; UIViewController *c=[UIViewController new]; c.view.backgroundColor=UIColor.systemBackgroundColor; v.frame=c.view.bounds; v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [c.view addSubview:v]; c.title=@"自动接听运行日志"; [self.navigationController pushViewController:c animated:YES]; }
- (void)clearLog:(PSSpecifier *)specifier { [[NSFileManager defaultManager] removeItemAtPath:AACLogPath() error:nil]; }
- (void)clearAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d removeObjectForKey:@"AudioPath"]; [d synchronize]; [self reloadSpecifiers];
}
@end
