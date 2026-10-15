#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface AACRootListController : PSListController <UIDocumentPickerDelegate>
@end
static NSString *AACAudioPath(void) { return [[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"] stringForKey:@"AudioPath"]; }
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
 NSString *dir=[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"AutoAnswerCall"];
 [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *name=source.lastPathComponent.length?source.lastPathComponent:@"answer-audio";
 NSURL *dest=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]; [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
 NSError *error=nil; BOOL ok=[[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:&error]; if(scoped)[source stopAccessingSecurityScopedResource];
 if(ok){ NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d setObject:dest.path forKey:@"AudioPath"]; [d synchronize]; [self reloadSpecifiers]; }
 else { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:0 handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
}
- (void)testAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
 AVAudioPlayer *player=[[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil]; [player prepareToPlay]; [player play]; objc_setAssociatedObject(self,@selector(testAudio:),player,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)clearAudio:(PSSpecifier *)specifier {
 NSString *path=AACAudioPath(); if(path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; NSUserDefaults *d=[[NSUserDefaults alloc] initWithSuiteName:@"com.autoanswer.call"]; [d removeObjectForKey:@"AudioPath"]; [d synchronize]; [self reloadSpecifiers];
}
@end
