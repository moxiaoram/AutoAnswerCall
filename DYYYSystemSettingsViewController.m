#import "DYYYSystemSettingsViewController.h"
#import "DYYYConstants.h"
#import "DYYYSettingsHelper.h"
#import <objc/runtime.h>
#import "DYYYSettingsSearchCatalog.h"

extern void *kViewModelKey;

@interface DYYYSystemSettingsViewController () <UISearchBarDelegate>
@property(nonatomic, strong) UITableView *systemTable;
@property(nonatomic, strong) UIView *systemHeader;
@property(nonatomic, copy) NSArray<AWESettingSectionModel *> *dyyySections;
@property(nonatomic, assign) BOOL previousNavigationHidden;
@property(nonatomic, assign) BOOL capturedNavigationVisibility;
@property(nonatomic, assign) BOOL dyyyMainPage;
@property(nonatomic, strong) UISearchBar *dyyySearchBar;
@property(nonatomic, strong) UIScreenEdgePanGestureRecognizer *dyyyRootExitGesture;
@property(nonatomic, copy) NSArray<NSDictionary *> *dyyySearchResults;
@end

@implementation DYYYSystemSettingsViewController

- (AWESettingBaseViewModel *)viewModel {
    return objc_getAssociatedObject(self, &kViewModelKey);
}

- (UIColor *)surfaceColor {
    if (@available(iOS 13.0, *)) return [UIColor secondarySystemGroupedBackgroundColor];
    return [UIColor whiteColor];
}

- (UIColor *)pageColor {
    if (@available(iOS 13.0, *)) return [UIColor systemGroupedBackgroundColor];
    return [UIColor colorWithWhite:0.94 alpha:1];
}

// 1.10: semantic SF Symbols, ordered by specificity so "隐藏点赞" maps to
// a heart rather than a generic hide/gear glyph. SF Symbols ship with iOS;
// unavailable symbols gracefully fall back to a compatible icon.
- (NSString *)symbolForTitle:(NSString *)title {
    if ([title containsString:@"点赞"] || [title containsString:@"喜欢"]) return @"heart.fill";
    if ([title containsString:@"收藏"]) return @"star.fill";
    if ([title containsString:@"评论"] || [title containsString:@"回复"]) return @"bubble.left.and.bubble.right.fill";
    if ([title containsString:@"分享"] || [title containsString:@"转发"]) return @"square.and.arrow.up.fill";
    if ([title containsString:@"举报"]) return @"exclamationmark.triangle.fill";
    if ([title containsString:@"粉丝"] || [title containsString:@"关注"] || [title containsString:@"用户"]) return @"person.2.fill";
    if ([title containsString:@"图集"] || [title containsString:@"图片"] || [title containsString:@"相册"] || [title containsString:@"封面"]) return @"photo.on.rectangle.angled";
    if ([title containsString:@"音乐"] || [title containsString:@"音频"] || [title containsString:@"声音"]) return @"waveform";
    if ([title containsString:@"弹幕"]) return @"text.bubble.fill";
    if ([title containsString:@"进度"] || [title containsString:@"时间轴"]) return @"slider.horizontal.3";
    if ([title containsString:@"倍速"] || [title containsString:@"速度"]) return @"speedometer";
    if ([title containsString:@"下一条"] || [title containsString:@"连播"]) return @"forward.end.fill";
    if ([title containsString:@"定时"] || [title containsString:@"延时"] || [title containsString:@"时间"]) return @"timer";
    if ([title containsString:@"画质"] || [title containsString:@"清晰度"] || [title containsString:@"分辨率"]) return @"tv.fill";
    if ([title containsString:@"沉浸"] || [title containsString:@"全屏"]) return @"arrow.up.left.and.arrow.down.right";
    if ([title containsString:@"播放"] || [title containsString:@"视频"]) return @"play.rectangle.fill";
    if ([title containsString:@"下载"] || [title containsString:@"保存"]) return @"square.and.arrow.down.fill";
    if ([title containsString:@"解析"] || [title containsString:@"链接"] || [title containsString:@"地址"]) return @"link";
    if ([title containsString:@"复制"]) return @"doc.on.doc.fill";
    if ([title containsString:@"搜索"]) return @"magnifyingglass";
    if ([title containsString:@"长按"] || [title containsString:@"手势"]) return @"hand.tap.fill";
    if ([title containsString:@"面板"] || [title containsString:@"菜单"]) return @"square.grid.2x2.fill";
    if ([title containsString:@"底栏"] || [title containsString:@"导航"] || [title containsString:@"标签"]) return @"rectangle.bottomthird.inset.filled";
    if ([title containsString:@"颜色"] || [title containsString:@"彩虹"] || [title containsString:@"改色"]) return @"paintpalette.fill";
    if ([title containsString:@"透明"] || [title containsString:@"模糊"]) return @"circle.lefthalf.filled";
    if ([title containsString:@"隐藏"] || [title containsString:@"移除"] || [title containsString:@"屏蔽"]) return @"eye.slash.fill";
    if ([title containsString:@"通知"] || [title containsString:@"消息"]) return @"bell.fill";
    if ([title containsString:@"自动"]) return @"arrow.triangle.2.circlepath";
    if ([title containsString:@"界面"] || [title containsString:@"外观"] || [title containsString:@"显示"]) return @"rectangle.3.offgrid.fill";
    if ([title containsString:@"备份"] || [title containsString:@"恢复"] || [title containsString:@"数据"]) return @"externaldrive.fill";
    if ([title containsString:@"清理"] || [title containsString:@"删除"]) return @"trash.fill";
    if ([title containsString:@"过滤"] || [title containsString:@"筛选"]) return @"line.3.horizontal.decrease.circle.fill";
    if ([title containsString:@"广告"]) return @"hand.raised.fill";
    if ([title containsString:@"悬浮"] || [title containsString:@"按钮"]) return @"circle.grid.cross.fill";
    if ([title containsString:@"插件"]) return @"puzzlepiece.extension.fill";
    if ([title containsString:@"关于"] || [title containsString:@"诊断"]) return @"info.circle.fill";
    if ([title containsString:@"基本"]) return @"gearshape.fill";
    return @"slider.horizontal.3";
}

- (UIColor *)symbolColorForTitle:(NSString *)title {
    if ([title containsString:@"点赞"] || [title containsString:@"喜欢"] || [title containsString:@"举报"]) return UIColor.systemRedColor;
    if ([title containsString:@"收藏"] || [title containsString:@"时间"] || [title containsString:@"定时"] || [title containsString:@"进度"]) return UIColor.systemOrangeColor;
    if ([title containsString:@"下载"] || [title containsString:@"保存"] || [title containsString:@"备份"] || [title containsString:@"解析"]) return UIColor.systemGreenColor;
    if ([title containsString:@"图集"] || [title containsString:@"图片"] || [title containsString:@"相册"] || [title containsString:@"封面"]) return UIColor.systemTealColor;
    if ([title containsString:@"音乐"] || [title containsString:@"音频"] || [title containsString:@"弹幕"] || [title containsString:@"评论"]) return UIColor.systemPurpleColor;
    if ([title containsString:@"倍速"] || [title containsString:@"速度"]) return UIColor.systemRedColor;
    if ([title containsString:@"沉浸"] || [title containsString:@"全屏"] || [title containsString:@"面板"] || [title containsString:@"手势"]) return UIColor.systemIndigoColor;
    if ([title containsString:@"隐藏"] || [title containsString:@"移除"] || [title containsString:@"透明"]) return UIColor.systemGrayColor;
    if ([title containsString:@"分享"] || [title containsString:@"颜色"]) return UIColor.systemOrangeColor;
    if ([title containsString:@"画质"] || [title containsString:@"清晰度"]) return UIColor.systemTealColor;
    if ([title containsString:@"搜索"]) return UIColor.systemPurpleColor;
    if ([title containsString:@"清理"]) return UIColor.systemRedColor;
    if ([title containsString:@"通知"]) return UIColor.systemRedColor;
    if ([title containsString:@"视频"] || [title containsString:@"播放"]) return UIColor.systemBlueColor;
    if ([title containsString:@"过滤"] || [title containsString:@"广告"]) return UIColor.systemOrangeColor;
    if ([title containsString:@"备份"] || [title containsString:@"数据"]) return UIColor.systemTealColor;
    if ([title containsString:@"界面"] || [title containsString:@"外观"]) return UIColor.systemPurpleColor;
    return UIColor.systemBlueColor;
}

- (UIImage *)iconForItem:(AWESettingItemModel *)item {
    NSString *symbol = [self symbolForTitle:item.title ?: @""];
    UIImageSymbolConfiguration *conf = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    return [UIImage systemImageNamed:symbol withConfiguration:conf] ?:
           [UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:conf];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    AWESettingsViewModel *model = objc_getAssociatedObject(self, &kViewModelKey);
    self.dyyySections = [model.sectionDataArray isKindOfClass:NSArray.class] ? model.sectionDataArray : @[];
    self.view.backgroundColor = [self pageColor];
    self.dyyyMainPage = [self.dyyyPageTitle isEqualToString:DYYY_NAME];

    // 不依赖抖音内部 UITableView 样式；但仍使用现有模型与处理 block。

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = [self pageColor];
    self.systemHeader = header;

    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.frame = CGRectMake(13, 7, 80, 40);
    [back setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [back setTitle:@"返回" forState:UIControlStateNormal];
    back.tintColor = [UIColor systemBlueColor];
    back.titleLabel.font = [UIFont systemFontOfSize:17];
    [back addTarget:self action:@selector(dyyyBack) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:back];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(90, 7, self.view.bounds.size.width - 180, 40)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.textAlignment = NSTextAlignmentCenter;
    title.text = self.dyyyPageTitle.length ? self.dyyyPageTitle : DYYY_NAME;
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    [header addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.view.bounds.size.width - 75, 7, 65, 40);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [close addTarget:self action:@selector(dyyyClose) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];
    // The home page has its own search/profile card. Do not show a second
    // text navigation bar (the old “返回” and duplicated “影流助手” title).
    // Subpages still use their normal back navigation.
    header.hidden = self.dyyyMainPage;
    [self.view addSubview:header];
    // Root page can be dismissed with a single left-edge swipe. Subpages use the
    // navigation controller's standard back gesture instead.
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dyyyHandleRootEdgePan:)];
    edge.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:edge];
    self.dyyyRootExitGesture = edge;

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:(self.dyyyMainPage ? 0.0 : 54.0)]
    ]];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.delegate = self;
    table.dataSource = self;
    table.backgroundColor = [self pageColor];
    table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    table.estimatedRowHeight = 54;
    table.rowHeight = UITableViewAutomaticDimension;
    if (@available(iOS 15.0, *)) table.sectionHeaderTopPadding = 8;
    table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:table];
    [NSLayoutConstraint activateConstraints:@[
        [table.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.systemTable = table;
    if (self.dyyyMainPage) [self dyyyBuildSearchAndProfileHeader];
}

- (void)dyyyBuildSearchAndProfileHeader {
    CGFloat width = MAX(320, self.view.bounds.size.width);
    UIView *intro = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 178)];
    intro.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    intro.backgroundColor = [self pageColor];
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(18, 9, width - 36, 48)];
    search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.placeholder = @"搜索插件设置项";
    search.delegate = self;
    search.accessibilityLabel = @"搜索插件设置项";
    [intro addSubview:search]; self.dyyySearchBar = search;

    UIView *profile = [[UIView alloc] initWithFrame:CGRectMake(18, 66, width - 36, 98)];
    profile.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    profile.backgroundColor = [self surfaceColor];
    profile.layer.cornerRadius = 18;
    [intro addSubview:profile];
    UIView *iconTile = [[UIView alloc] initWithFrame:CGRectMake(18, 17, 64, 64)];
    iconTile.backgroundColor = [UIColor colorWithRed:.20 green:.45 blue:.94 alpha:1];
    iconTile.layer.cornerRadius = 18;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 32, 32)];
    icon.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"] ?: [UIImage systemImageNamed:@"gearshape.fill"];
    icon.tintColor = UIColor.whiteColor;
    [iconTile addSubview:icon]; [profile addSubview:iconTile];
    UILabel *pluginName = [[UILabel alloc] initWithFrame:CGRectMake(96, 34, profile.bounds.size.width - 115, 30)];
    pluginName.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    pluginName.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    pluginName.text = DYYY_NAME;
    [profile addSubview:pluginName];
    // Root profile card intentionally has no X button. Exit via the existing
    // single-swipe gesture; subpages retain their normal Back navigation.
    self.systemTable.tableHeaderView = intro;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSString *q = [searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!q.length) self.dyyySearchResults = @[];
    else {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSDictionary *record in DYYYSearchCatalog()) {
            if ([record[@"title"] localizedCaseInsensitiveContainsString:q] ||
                [record[@"desc"] localizedCaseInsensitiveContainsString:q] ||
                [record[@"category"] localizedCaseInsensitiveContainsString:q]) [matched addObject:record];
        }
        self.dyyySearchResults = matched;
    }
    [self.systemTable reloadData];
}

- (BOOL)dyyyIsSearching { return self.dyyyMainPage && self.dyyySearchBar.text.length > 0; }

- (void)dyyyOpenSearchResult:(NSDictionary *)result {
    NSString *category = result[@"category"];
    NSString *focus = result[@"title"];
    for (AWESettingSectionModel *section in self.dyyySections) {
        for (AWESettingItemModel *item in section.itemArray) {
            if (![item.title isEqualToString:category] || !item.cellTappedBlock) continue;
            [self.dyyySearchBar resignFirstResponder];
            item.cellTappedBlock();
            UIViewController *top = self.navigationController.topViewController;
            if ([top isKindOfClass:DYYYSystemSettingsViewController.class] && top != self) {
                ((DYYYSystemSettingsViewController *)top).dyyyFocusTitle = focus;
            }
            return;
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.dyyyFocusTitle.length) return;
    for (NSUInteger s = 0; s < self.dyyySections.count; s++) {
        NSArray *items = self.dyyySections[s].itemArray;
        for (NSUInteger r = 0; r < items.count; r++) {
            AWESettingItemModel *item = items[r];
            if ([item.title isEqualToString:self.dyyyFocusTitle]) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:r inSection:s];
                [self.systemTable scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
                self.dyyyFocusTitle = nil;
                return;
            }
        }
    }
    self.dyyyFocusTitle = nil;
}

// The dedicated plugin UINavigationController must have exactly one root when
// dismissed. Never pop to an unrelated Douyin controller (that caused blank pages).
- (void)dyyyClose {
    UINavigationController *nav = self.navigationController;
    DYYYSystemSettingsViewController *pluginRoot = nil;
    for (UIViewController *controller in nav.viewControllers) {
        if ([controller isKindOfClass:DYYYSystemSettingsViewController.class] &&
            [((DYYYSystemSettingsViewController *)controller).dyyyPageTitle isEqualToString:DYYY_NAME]) {
            pluginRoot = (DYYYSystemSettingsViewController *)controller;
            break;
        }
    }

    if (pluginRoot.dyyyUsesDedicatedModalNavigation && nav.presentingViewController) {
        [nav dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    if (pluginRoot && self != pluginRoot) {
        [nav popToViewController:pluginRoot animated:YES];
    } else if (nav.viewControllers.count > 1 && nav.topViewController == self) {
        // Remove only the plugin page, returning to the Douyin page that opened it.
        [nav popViewControllerAnimated:YES];
    } else if (nav.presentingViewController) {
        [nav dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)dyyyBack {
    UINavigationController *nav = self.navigationController;
    if (self.dyyyUsesDedicatedModalNavigation && nav.presentingViewController &&
        nav.viewControllers.firstObject == self) {
        [nav dismissViewControllerAnimated:YES completion:nil];
    } else if (nav.viewControllers.count > 1) {
        [nav popViewControllerAnimated:YES];
    } else {
        [self dyyyClose];
    }
}

- (void)dyyyHandleRootEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    if (self.navigationController.viewControllers.count != 1) return;
    if ([gesture translationInView:self.view].x > 85 ||
        [gesture velocityInView:self.view].x > 550) [self dyyyClose];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.capturedNavigationVisibility) {
        self.previousNavigationHidden = self.navigationController.navigationBarHidden;
        self.capturedNavigationVisibility = YES;
    }
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    self.dyyyRootExitGesture.enabled = (self.navigationController.viewControllers.count == 1);
    self.navigationController.interactivePopGestureRecognizer.enabled = (self.navigationController.viewControllers.count > 1);
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    for (AWESettingSectionModel *section in self.dyyySections) {
        for (AWESettingItemModel *item in section.itemArray) {
            if (item.cellType == 6 || item.cellType == 37) {
                id stored = [prefs objectForKey:item.identifier];
                if (stored) item.isSwitchOn = [stored boolValue];
            }
            [DYYYSettingsHelper applyDependencyRulesForItem:item];
        }
    }
    [self.systemTable reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 子页面同样为系统设置时保持隐藏，退出设置后恢复原来的导航条。
    UIViewController *next = self.navigationController.topViewController;
    if (![next isKindOfClass:[DYYYSystemSettingsViewController class]])
        [self.navigationController setNavigationBarHidden:self.previousNavigationHidden animated:NO];
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self dyyyIsSearching] ? 1 : self.dyyySections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self dyyyIsSearching] ? self.dyyySearchResults.count : self.dyyySections[section].itemArray.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self dyyyIsSearching] ? @"搜索结果" : self.dyyySections[section].sectionHeaderTitle;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [self dyyyIsSearching] ? nil : self.dyyySections[section].sectionFooterTitle;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self dyyyIsSearching]) return 65;
    AWESettingItemModel *item = self.dyyySections[indexPath.section].itemArray[indexPath.row];
    return item.subTitle.length ? 76 : 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *match = [self dyyyIsSearching] ? self.dyyySearchResults[path.row] : nil;
    AWESettingItemModel *item = match ? nil : self.dyyySections[path.section].itemArray[path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [self surfaceColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.text = match ? match[@"title"] : item.title;
    cell.textLabel.textColor = (match || item.isEnable) ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = match ? match[@"category"] : (item.subTitle.length ? item.subTitle : item.detail);

    // 每个大选项有独立的、类似系统设置的彩色方块图标。
    UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 31, 31)];
    tile.backgroundColor = [self symbolColorForTitle:match ? match[@"title"] : item.title ?: @""];
    tile.layer.cornerRadius = 7;
    UIImageView *image = [[UIImageView alloc] initWithImage:match ? ([UIImage systemImageNamed:[self symbolForTitle:match[@"title"]]] ?: [UIImage systemImageNamed:@"slider.horizontal.3"]) : [self iconForItem:item]];
    image.frame = CGRectMake(6, 6, 19, 19);
    image.tintColor = [UIColor whiteColor];
    [tile addSubview:image];
    // UITableViewCell 内用 imageView 显示固定背景的组合图片。
    UIGraphicsBeginImageContextWithOptions(tile.bounds.size, NO, 0);
    [tile.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *tileImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    cell.imageView.image = tileImage;

    if (match) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (item.cellType == 6 || item.cellType == 37) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = item.isSwitchOn;
        toggle.enabled = item.isEnable;
        toggle.onTintColor = [UIColor systemGreenColor];
        toggle.accessibilityLabel = item.title;
        toggle.tag = path.section * 10000 + path.row;
        [toggle addTarget:self action:@selector(dyyySwitch:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        BOOL editable = (item.cellType == 20 || item.cellType == 26) && [item.identifier hasPrefix:@"DYYY"];
        cell.accessoryType = (item.cellTappedBlock || editable) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)dyyySwitch:(UISwitch *)sender {
    NSIndexPath *path = [NSIndexPath indexPathForRow:sender.tag % 10000 inSection:sender.tag / 10000];
    if (path.section >= self.dyyySections.count || path.row >= self.dyyySections[path.section].itemArray.count) return;
    AWESettingItemModel *item = self.dyyySections[path.section].itemArray[path.row];
    if (!item.isEnable) { sender.on = item.isSwitchOn; return; }
    if (item.switchChangedBlock) {
        item.switchChangedBlock();
    } else {
        item.isSwitchOn = sender.on;
        [DYYYSettingsHelper setUserDefaults:@(sender.on) forKey:item.identifier];
        [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:item.identifier isEnabled:sender.on];
    }
    sender.on = item.isSwitchOn;
    [self.systemTable reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if ([self dyyyIsSearching]) {
        [self dyyyOpenSearchResult:self.dyyySearchResults[path.row]];
        return;
    }
    AWESettingItemModel *item = self.dyyySections[path.section].itemArray[path.row];
    if (!item.isEnable) return;
    if (item.cellTappedBlock) {
        item.cellTappedBlock();
    } else if ((item.cellType == 20 || item.cellType == 26) && [item.identifier hasPrefix:@"DYYY"]) {
        // 兼容原控制器默认提供的文本输入行为。
        [DYYYSettingsHelper showTextInputAlert:item.title
                                   defaultText:item.detail
                                  placeholder:item.subTitle
                                    onConfirm:^(NSString *text) {
            [DYYYSettingsHelper setUserDefaults:text forKey:item.identifier];
            item.detail = text;
            [DYYYSettingsHelper handleConflictsAndDependenciesForSetting:item.identifier isEnabled:text.length > 0];
            [self.systemTable reloadData];
        } onCancel:nil];
    }
}
@end
