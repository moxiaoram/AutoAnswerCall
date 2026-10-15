#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface AACRootListController : PSListController <UIDocumentPickerDelegate>
@end
@implementation AACRootListController
- (NSArray *)specifiers {
 if (!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];
 return _specifiers;
}
- (void)pickAudio:(PSSpecifier *)specifier {
 UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType audio]]];
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
@end
