#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../AACGlobalLogger.h"

static NSString * const kAAPrefsDomain = @"com.autoanswer.call";
static NSString * const kAAAudioDirectory = @"/var/mobile/Library/AutoAnswerAudio";

@interface AARootListController : PSListController <UIDocumentPickerDelegate>
@property(nonatomic, strong) AVAudioPlayer *previewPlayer;
@property(nonatomic, strong) NSArray<NSString *> *audioLibrary;
@end

@implementation AARootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    AAPrefsLog(@"AutoAnswerAudio 设置页已打开");
    self.title = @"AutoAnswerAudio";
    [self reloadAudioLibrary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAAPrefsDomain);
    CFPropertyListRef raw = CFPreferencesCopyMultiple(NULL, (__bridge CFStringRef)kAAPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *prefs = raw ? CFBridgingRelease(raw) : @{};
    if (![prefs isKindOfClass:NSDictionary.class]) prefs = @{};
    AAPrefsLog([NSString stringWithFormat:@"设置页显示；Enabled=%@ AutoAnswer=%@ Delay=%@ PlayAudio=%@ AudioFilePath=%@", prefs[@"Enabled"] ?: @"(default)", prefs[@"AutoAnswer"] ?: @"(default)", prefs[@"Delay"] ?: @"(default)", prefs[@"PlayAudio"] ?: @"(default)", prefs[@"AudioFilePath"] ?: @"(empty)"]);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.previewPlayer stop];
    self.previewPlayer = nil;
}

- (NSString *)selectedAudioPath {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAAPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("AudioFilePath"), (__bridge CFStringRef)kAAPrefsDomain);
    if (!value) return @"";
    id object = CFBridgingRelease(value);
    return [object isKindOfClass:NSString.class] ? object : @"";
}

- (void)saveValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kAAPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAAPrefsDomain);
}

- (void)reloadAudioLibrary {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kAAPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("AudioLibrary"), (__bridge CFStringRef)kAAPrefsDomain);
    id object = value ? CFBridgingRelease(value) : nil;
    NSMutableArray *valid = [NSMutableArray array];
    if ([object isKindOfClass:NSArray.class]) {
        for (id path in object) {
            if ([path isKindOfClass:NSString.class] && [[NSFileManager defaultManager] fileExistsAtPath:path]) [valid addObject:path];
        }
    }
    NSString *current = [self selectedAudioPath];
    if (current.length && [[NSFileManager defaultManager] fileExistsAtPath:current] && ![valid containsObject:current]) [valid addObject:current];
    self.audioLibrary = valid.copy;
    [self saveValue:self.audioLibrary forKey:@"AudioLibrary"];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopUplinkPlayback {
    AAPrefsLog(@"用户点击停止上行播放；正在发送 Darwin 通知 com.autoanswer.call.stopUplinkPlayback");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.autoanswer.call.stopUplinkPlayback"), NULL, NULL, true);
    AAPrefsLog(@"停止上行播放通知已发送；等待 SpringBoard 侧日志确认接收情况");
    [self showMessage:@"已发送停止请求。可点击“查看 / 复制全局日志”检查 Preferences 与 SpringBoard 两侧记录。" title:@"停止上行播放（实验）"];
}

- (void)importAudio {
    NSArray *types = @[];
    if (@available(iOS 14.0, *)) {
        types = @[UTTypeAudio, UTTypeMP3, UTTypeWAV, UTTypeMPEG4Audio];
    }
    // 部署目标 iOS 17，旧初始化器已弃用且会触发 -Werror，这里只保留受支持路径。
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) { AAPrefsLog(@"导入音频取消：文档选择器没有返回文件"); return; }
    AAPrefsLog([NSString stringWithFormat:@"用户选择导入音频：%@", source.lastPathComponent]);
    BOOL access = [source startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:kAAAudioDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
    if (error) {
        if (access) [source stopAccessingSecurityScopedResource];
        AAPrefsLog([NSString stringWithFormat:@"创建音频目录失败：%@", error.localizedDescription ?: @"unknown"]);
        [self showMessage:error.localizedDescription title:@"创建音频目录失败"];
        return;
    }
    NSString *base = source.lastPathComponent.length ? source.lastPathComponent : @"audio";
    NSString *destination = [kAAAudioDirectory stringByAppendingPathComponent:base];
    NSString *ext = destination.pathExtension;
    NSString *stem = [destination stringByDeletingPathExtension];
    NSUInteger n = 2;
    while ([fm fileExistsAtPath:destination]) {
        destination = [NSString stringWithFormat:@"%@-%lu%@%@", stem, (unsigned long)n++, ext.length ? @"." : @"", ext];
    }
    BOOL copied = [fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:destination] error:&error];
    if (access) [source stopAccessingSecurityScopedResource];
    if (!copied) {
        AAPrefsLog([NSString stringWithFormat:@"复制音频失败：%@", error.localizedDescription ?: @"unknown"]);
        [self showMessage:error.localizedDescription ?: @"复制失败" title:@"导入音频失败"];
        return;
    }
    NSMutableArray *library = [self.audioLibrary mutableCopy] ?: [NSMutableArray array];
    [library addObject:destination];
    self.audioLibrary = library.copy;
    [self saveValue:self.audioLibrary forKey:@"AudioLibrary"];
    [self chooseAudioPath:destination];
    AAPrefsLog([NSString stringWithFormat:@"音频导入成功并设为当前文件：%@", destination]);
    [self showMessage:[NSString stringWithFormat:@"已导入并选中：%@", base] title:@"导入成功"];
}

- (void)chooseAudioPath:(NSString *)path {
    AAPrefsLog([NSString stringWithFormat:@"选择当前播放音频：%@", path.length ? path : @"(none)"]);
    [self saveValue:path forKey:@"AudioFilePath"];
    [self reloadAudioLibrary];
    [self reloadSpecifiers];
}

- (NSString *)displayNameForPath:(NSString *)path {
    return path.lastPathComponent.length ? path.lastPathComponent : path;
}

- (void)manageAudio {
    [self.previewPlayer stop];
    self.previewPlayer = nil;
    [self reloadAudioLibrary];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"音频库" message:[NSString stringWithFormat:@"当前选择：%@", [self displayNameForPath:[self selectedAudioPath]]] preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *path in self.audioLibrary) {
        NSString *name = [self displayNameForPath:path];
        NSString *title = [path isEqualToString:[self selectedAudioPath]] ? [NSString stringWithFormat:@"✓ %@", name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self chooseAudioPath:path]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除当前选中音频" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [self deleteSelectedAudio]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds)-1, 1, 1);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)deleteSelectedAudio {
    NSString *path = [self selectedAudioPath];
    if (!path.length || ![self.audioLibrary containsObject:path]) {
        [self showMessage:@"请先从“管理音频”中选择一个已导入的音频。" title:@"没有可删除的音频"];
        return;
    }
    [self.previewPlayer stop];
    self.previewPlayer = nil;
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        AAPrefsLog([NSString stringWithFormat:@"删除音频失败：%@", error.localizedDescription ?: @"unknown"]);
        [self showMessage:error.localizedDescription title:@"删除失败"];
        return;
    }
    NSMutableArray *library = [self.audioLibrary mutableCopy];
    [library removeObject:path];
    self.audioLibrary = library.copy;
    [self saveValue:self.audioLibrary forKey:@"AudioLibrary"];
    [self chooseAudioPath:self.audioLibrary.firstObject ?: @""];
    AAPrefsLog([NSString stringWithFormat:@"已删除音频：%@", path]);
    [self showMessage:@"已删除所选音频。" title:@"完成"];
}

- (void)togglePreview {
    if (self.previewPlayer.isPlaying) {
        [self.previewPlayer stop];
        self.previewPlayer = nil;
        AAPrefsLog(@"本机试听已停止");
        [self showMessage:@"试听已停止。" title:@"试听"];
        return;
    }
    NSString *path = [self selectedAudioPath];
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        AAPrefsLog(@"本机试听失败：没有有效的当前音频路径");
        [self showMessage:@"请先导入并选择一个音频文件。" title:@"没有可试听的音频"];
        return;
    }
    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [session setActive:YES error:nil];
    self.previewPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (!self.previewPlayer || error) {
        AAPrefsLog([NSString stringWithFormat:@"本机试听创建播放器失败：%@", error.localizedDescription ?: @"unknown"]);
        [self showMessage:error.localizedDescription ?: @"文件格式无法播放" title:@"试听失败"];
        return;
    }
    self.previewPlayer.numberOfLoops = 0;
    if (![self.previewPlayer prepareToPlay] || ![self.previewPlayer play]) {
        AAPrefsLog(@"本机试听失败：prepareToPlay 或 play 返回失败");
        [self showMessage:@"播放器无法启动。" title:@"试听失败"];
        return;
    }
    AAPrefsLog([NSString stringWithFormat:@"开始本机试听：%@", path.lastPathComponent]);
    [self showMessage:[NSString stringWithFormat:@"正在本机试听：%@\n再次点击“试听 / 停止试听”即可停止。", path.lastPathComponent] title:@"试听中"];
}

- (void)viewGlobalLog {
    NSString *path = @"/var/mobile/Library/AutoAnswerAudio/AutoAnswerAudio.log";
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!contents.length) {
        AAPrefsLog([NSString stringWithFormat:@"用户打开全局日志查看器；日志为空或读取失败：%@", error.localizedDescription ?: @"尚无日志"]);
        contents = [NSString stringWithFormat:@"暂时没有日志，或读取失败。\n路径：%@\n错误：%@", path, error.localizedDescription ?: @"无"];
    } else {
        AAPrefsLog(@"用户打开全局日志查看器");
        if (contents.length > 14000) contents = [contents substringFromIndex:contents.length - 14000];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"全局诊断日志" message:contents preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *latest = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"(日志为空)";
        if (latest.length > 60000) latest = [latest substringFromIndex:latest.length - 60000];
        UIPasteboard.generalPasteboard.string = latest;
        AAPrefsLog(@"用户已将全局日志复制到剪贴板（最多最近 60000 字符）");
        [self showMessage:@"日志已复制。你可以直接粘贴到聊天中。" title:@"复制成功"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        AAPrefsLog(@"用户请求清空全局日志");
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        AAPrefsLog(@"全局日志已清空");
        [self showMessage:@"全局日志已清空。" title:@"完成"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要重新载入" message:@"设置已保存。只有在通话相关 Hook 实现并验证后，才建议在真实通话中启用自动化功能。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
