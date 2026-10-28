#import "DYYYAutoNextManager.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface DYYYAutoNextManager ()
@property(nonatomic, weak) UIViewController *feed;
@property(nonatomic, assign) BOOL pending;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) NSTimeInterval lastAdvanceUptime;
@property(nonatomic, assign) CGFloat lastTime;
@property(nonatomic, assign) CGFloat lastDuration;
@property(nonatomic, weak) id lastSource;
@end

@implementation DYYYAutoNextManager
+ (instancetype)sharedManager {
    static DYYYAutoNextManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; m.lastTime = -1; });
    return m;
}
- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableAutoPlay"];
}
- (void)attachFeed:(UIViewController *)feed {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self attachFeed:feed]; }); return; }
    if (self.feed == feed) return;
    // Detail/table feed directly owns the actual list; prefer it over an outer container.
    BOOL existingInner = [NSStringFromClass(self.feed.class) containsString:@"FeedTableViewController"];
    BOOL incomingOuter = [NSStringFromClass(feed.class) containsString:@"FeedContainerViewController"];
    if (existingInner && incomingOuter && self.feed.view.window) return;
    self.feed = feed; [self feedDidSwitch];
}
- (void)detachFeed:(UIViewController *)feed {
    if (self.feed == feed) { self.feed = nil; [self feedDidSwitch]; }
}
- (void)feedDidSwitch {
    self.generation++;
    self.pending = NO;
    self.lastTime = -1;
    self.lastDuration = 0;
    self.lastSource = nil;
}
// 只查找推荐流中的垂直可见列表；不触碰评论、搜索结果和图集横向滑条。
- (UIScrollView *)visibleFeedList {
    UIView *root = self.feed.view;
    if (!root.window || self.feed.presentedViewController || self.feed.navigationController.presentedViewController) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    UIScrollView *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSUInteger i = 0; i < queue.count && i < 1500; i++) {
        UIView *view = queue[i];
        if ([view isKindOfClass:UITableView.class] || [view isKindOfClass:UICollectionView.class]) {
            UIScrollView *list = (UIScrollView *)view;
            if (list.hidden || list.alpha < 0.1 || !list.window || list.window != root.window ||
                list.bounds.size.height < root.bounds.size.height * .48 ||
                list.bounds.size.height < list.bounds.size.width * .8) continue;
            NSInteger visibleCount = 0;
            if ([list isKindOfClass:UITableView.class]) visibleCount = [(UITableView *)list indexPathsForVisibleRows].count;
            else visibleCount = [(UICollectionView *)list indexPathsForVisibleItems].count;
            if (!visibleCount) continue;
            NSString *name = NSStringFromClass(list.class);
            NSString *parent = NSStringFromClass(list.superview.class);
            BOOL feedNamed = ([name localizedCaseInsensitiveContainsString:@"feed"] ||
                              [parent localizedCaseInsensitiveContainsString:@"feed"]);
            NSInteger score = (feedNamed ? 100 : 0) + (NSInteger)(list.bounds.size.height / 40.0) +
                (list.contentSize.height > list.bounds.size.height * 1.15 ? 20 : 0) +
                (visibleCount <= 3 ? 30 : 0);
            if (score > bestScore) { bestScore = score; best = list; }
        }
        for (UIView *sub in view.subviews) [queue addObject:sub];
    }
    return best;
}
- (NSIndexPath *)visibleIndexForList:(UIScrollView *)list {
    NSArray<NSIndexPath *> *paths = nil;
    if ([list isKindOfClass:UITableView.class]) paths = [(UITableView *)list indexPathsForVisibleRows];
    else if ([list isKindOfClass:UICollectionView.class]) paths = [(UICollectionView *)list indexPathsForVisibleItems];
    if (!paths.count) return nil;
    CGPoint center = CGPointMake(CGRectGetMidX(list.bounds), CGRectGetMidY(list.bounds));
    NSIndexPath *atCenter = nil;
    if ([list isKindOfClass:UITableView.class]) atCenter = [(UITableView *)list indexPathForRowAtPoint:center];
    else atCenter = [(UICollectionView *)list indexPathForItemAtPoint:center];
    return atCenter ?: paths.firstObject;
}
- (BOOL)nextIndex:(NSIndexPath *)current isValidForList:(UIScrollView *)list {
    if ([list isKindOfClass:UITableView.class]) return current.row + 1 < [(UITableView *)list numberOfRowsInSection:current.section];
    return current.item + 1 < [(UICollectionView *)list numberOfItemsInSection:current.section];
}
- (void)recordCurrentTime:(CGFloat)current duration:(CGFloat)duration source:(id)source {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self recordCurrentTime:current duration:duration source:source]; }); return; }
    if (![self enabled] || !self.feed || !self.feed.view.window || self.pending) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!isfinite(current) || !isfinite(duration) || duration < 1.0 || current < 0) return;
    if (self.lastSource && self.lastSource != source && self.lastTime > 0 &&
        CACurrentMediaTime() - self.lastAdvanceUptime < 1.0) return;
    self.lastSource = source;
    // 已经翻到下一视频，新的进度从接近 0 开始。
    if (self.lastTime > 0 && current + .6 < self.lastTime) self.lastDuration = 0;
    self.lastTime = current;
    self.lastDuration = duration;
    if (duration - current > .85 || CACurrentMediaTime() - self.lastAdvanceUptime < 2.0) return;
    UIScrollView *list = [self visibleFeedList];
    NSIndexPath *position = [self visibleIndexForList:list];
    if (!position || ![self nextIndex:position isValidForList:list]) return;
    NSLog(@"[DYYY18] Near end %.2f/%.2f; scheduling feed advance", current, duration);
    self.pending = YES;
    NSUInteger startGeneration = self.generation;
    __weak typeof(self) weakSelf = self;
    __weak UIScrollView *weakList = list;
    __weak UIViewController *weakFeed = self.feed;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.72 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.pending = NO;
        if (![strongSelf enabled] || strongSelf.feed != weakFeed || !weakFeed.view.window ||
            strongSelf.generation != startGeneration) return;
        UIScrollView *currentList = [strongSelf visibleFeedList];
        if (currentList != weakList) return;
        NSIndexPath *nowPosition = [strongSelf visibleIndexForList:currentList];
        // 抖音若已经自动跳转，就不要二次翻页。
        if (![nowPosition isEqual:position]) return;
        if (![strongSelf nextIndex:position isValidForList:currentList]) return;
        // 自动翻页只在列表稳定时触发，不能跟用户正在滑动的手势竞争。
        if (currentList.dragging || currentList.tracking || currentList.decelerating) return;
        NSIndexPath *next = [NSIndexPath indexPathForRow:position.row + 1 inSection:position.section];
        CGRect targetRect = CGRectNull;
        if ([currentList isKindOfClass:UITableView.class]) {
            targetRect = [(UITableView *)currentList rectForRowAtIndexPath:next];
        } else if ([currentList isKindOfClass:UICollectionView.class]) {
            UICollectionView *collection = (UICollectionView *)currentList;
            [collection layoutIfNeeded];
            targetRect = [collection layoutAttributesForItemAtIndexPath:next].frame;
        }
        // 不是全屏 Feed Cell 时禁止滚动，避免误选其他嵌套列表。
        if (CGRectIsNull(targetRect) || CGRectIsEmpty(targetRect) ||
            CGRectGetHeight(targetRect) < CGRectGetHeight(currentList.bounds) * 0.78) return;
        CGFloat topInset = currentList.adjustedContentInset.top;
        CGFloat bottomInset = currentList.adjustedContentInset.bottom;
        CGFloat minY = -topInset;
        CGFloat maxY = MAX(minY, currentList.contentSize.height - CGRectGetHeight(currentList.bounds) + bottomInset);
        CGFloat snappedY = MIN(maxY, MAX(minY, CGRectGetMinY(targetRect) - topInset));
        // 旧版的 UITableViewScrollPositionMiddle 会把两个视频各露出半屏。
        strongSelf.lastAdvanceUptime = CACurrentMediaTime();
        strongSelf.lastTime = -1;
        [currentList setContentOffset:CGPointMake(currentList.contentOffset.x, snappedY) animated:YES];
        NSLog(@"[DYYY19] Auto-next aligned to item top: %.1f", snappedY);
    });
}
@end
