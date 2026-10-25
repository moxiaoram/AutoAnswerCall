#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreFoundation/CoreFoundation.h>

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
    self.title = @"AutoAnswerAudio";
    [self reloadAudioLibrary];
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

- (void)importAudio {
    NSArray *types = @[];
    if (@available(iOS 14.0, *)) {
        types = @[UTTypeAudio, UTTypeMP3, UTTypeWAV, UTTypeMPEG4Audio];
    }
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    else picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio", @"public.mp3", @"com.microsoft.waveform-audio", @"public.mpeg-4-audio"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) return;
    BOOL access = [source startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:kAAAudioDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error];
    if (error) {
        if (access) [source stopAccessingSecurityScopedResource];
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
        [self showMessage:error.localizedDescription ?: @"复制失败" title:@"导入音频失败"];
        return;
    }
    NSMutableArray *library = [self.audioLibrary mutableCopy] ?: [NSMutableArray array];
    [library addObject:destination];
    self.audioLibrary = library.copy;
    [self saveValue:self.audioLibrary forKey:@"AudioLibrary"];
    [self chooseAudioPath:destination];
    [self showMessage:[NSString stringWithFormat:@"已导入并选中：%@", base] title:@"导入成功"];
}

- (void)chooseAudioPath:(NSString *)path {
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
        [self showMessage:error.localizedDescription title:@"删除失败"];
        return;
    }
    NSMutableArray *library = [self.audioLibrary mutableCopy];
    [library removeObject:path];
    self.audioLibrary = library.copy;
    [self saveValue:self.audioLibrary forKey:@"AudioLibrary"];
    [self chooseAudioPath:self.audioLibrary.firstObject ?: @""];
    [self showMessage:@"已删除所选音频。" title:@"完成"];
}

- (void)togglePreview {
    if (self.previewPlayer.isPlaying) {
        [self.previewPlayer stop];
        self.previewPlayer = nil;
        [self showMessage:@"试听已停止。" title:@"试听"];
        return;
    }
    NSString *path = [self selectedAudioPath];
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showMessage:@"请先导入并选择一个音频文件。" title:@"没有可试听的音频"];
        return;
    }
    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [session setActive:YES error:nil];
    self.previewPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (!self.previewPlayer || error) {
        [self showMessage:error.localizedDescription ?: @"文件格式无法播放" title:@"试听失败"];
        return;
    }
    self.previewPlayer.numberOfLoops = 0;
    if (![self.previewPlayer prepareToPlay] || ![self.previewPlayer play]) {
        [self showMessage:@"播放器无法启动。" title:@"试听失败"];
        return;
    }
    [self showMessage:[NSString stringWithFormat:@"正在本机试听：%@\n再次点击“试听 / 停止试听”即可停止。", path.lastPathComponent] title:@"试听中"];
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要重新载入" message:@"设置已保存。只有在通话相关 Hook 实现并验证后，才建议在真实通话中启用自动化功能。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
