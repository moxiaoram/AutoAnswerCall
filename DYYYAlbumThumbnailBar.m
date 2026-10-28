#import "DYYYAlbumThumbnailBar.h"
#import "DYYYPhotoGalleryController.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>

// Catch a normal tap on an image feed cell, before waiting for a private
// image-detail viewer to appear. Do not steal clicks from the right-side controls.
@interface DYYYAlbumGalleryTapRelay : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *cell;
@property(nonatomic, strong) AWEAwemeModel *model;
@property(nonatomic, weak) UITapGestureRecognizer *tap;
- (void)openAlbum:(UITapGestureRecognizer *)tap;
@end
@implementation DYYYAlbumGalleryTapRelay
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (!self.cell.window || self.model.albumImages.count < 2) return NO;
    CGPoint p = [touch locationInView:self.cell];
    if (p.x > self.cell.bounds.size.width - 88 || p.y < 90 || p.y > self.cell.bounds.size.height - 170) return NO;
    for (UIView *v = touch.view; v && v != self.cell; v = v.superview)
        if ([v isKindOfClass:UIControl.class]) return NO;
    return YES;
}
- (void)openAlbum:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateRecognized || !self.model.albumImages.count) return;
    NSInteger index = MAX(0, self.model.currentImageIndex - 1);
    DYYYPresentPhotoGallery(self.model, index, self.cell.window);
}
@end
static char kDYYYGalleryTapRelayKey;
static void DYYYRemoveGalleryTap(UIView *cell) {
    DYYYAlbumGalleryTapRelay *relay = objc_getAssociatedObject(cell, &kDYYYGalleryTapRelayKey);
    if (relay.tap) [cell removeGestureRecognizer:relay.tap];
    relay.model = nil;
    objc_setAssociatedObject(cell, &kDYYYGalleryTapRelayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DYYYAttachGalleryTap(UIView *cell, AWEAwemeModel *model) {
    DYYYAlbumGalleryTapRelay *relay = objc_getAssociatedObject(cell, &kDYYYGalleryTapRelayKey);
    if (!relay) {
        relay = [DYYYAlbumGalleryTapRelay new]; relay.cell = cell;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:relay action:@selector(openAlbum:)];
        tap.cancelsTouchesInView = YES;
        tap.delegate = relay;
        [cell addGestureRecognizer:tap]; relay.tap = tap;
        objc_setAssociatedObject(cell, &kDYYYGalleryTapRelayKey, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Feed-level tap gestures must lose to the image-gallery tap in the image area.
        // Pan/long-press recognizers remain independent to preserve feed navigation.
        for (UIGestureRecognizer *original in cell.gestureRecognizers) {
            if (original != tap && [original isKindOfClass:UITapGestureRecognizer.class])
                [original requireGestureRecognizerToFail:tap];
        }
    }
    relay.model = model;
}

static char kDYYYAlbumBarKey;
static NSCache<NSString *, UIImage *> *DYYYPhotoThumbCache(void) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 160; });
    return cache;
}

static NSURL *DYYYPhotoURL(id model) {
    if (!model || model == [NSNull null]) return nil;
    if ([model isKindOfClass:NSURL.class]) return model;
    if ([model isKindOfClass:NSString.class]) {
        NSURL *u = [NSURL URLWithString:model];
        return ([@[@"https", @"http"] containsObject:u.scheme.lowercaseString]) ? u : nil;
    }
    if ([model isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = model;
        for (NSString *key in @[@"url_list", @"urlList", @"originURLList", @"uri", @"url"]) {
            if (d[key]) { NSURL *found = DYYYPhotoURL(d[key]); if (found) return found; }
        }
        return nil;
    }
    if ([model isKindOfClass:NSArray.class]) {
        for (id elem in (NSArray *)model) { NSURL *found = DYYYPhotoURL(elem); if (found) return found; }
        return nil;
    }
    for (NSString *key in @[@"originURLList", @"urlList", @"url_list"]) {
        @try {
            id value = [model valueForKey:key];
            NSURL *url = DYYYPhotoURL(value);
            if (url) return url;
        } @catch (NSException *e) { }
    }
    return nil;
}

@interface DYYYAlbumThumbnailBar () <UIScrollViewDelegate>
@property(nonatomic, weak) UIView *feedCell;
@property(nonatomic, strong) AWEAwemeModel *aweme;
@property(nonatomic, strong) UIScrollView *strip;
@property(nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property(nonatomic, strong) UILabel *counter;
@property(nonatomic, strong) UIImageView *fallbackPreview;
@property(nonatomic) NSInteger selected;
@property(nonatomic) BOOL polling;
@end

@implementation DYYYAlbumThumbnailBar
+ (void)clearFeedCell:(UIView *)cell {
    DYYYRemoveGalleryTap(cell);
    DYYYAlbumThumbnailBar *bar = objc_getAssociatedObject(cell, &kDYYYAlbumBarKey);
    [bar removeFromSuperview];
    objc_setAssociatedObject(cell, &kDYYYAlbumBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
+ (void)configureFeedCell:(UIView *)cell model:(AWEAwemeModel *)model {
    if (![NSThread isMainThread]) return;
    BOOL valid = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAlbumThumbnailStrip"] == nil ||
                 [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYAlbumThumbnailStrip"];
    NSArray *images = nil;
    @try { if ([model respondsToSelector:@selector(albumImages)]) images = [(id)model albumImages]; } @catch (NSException *e) { }
    if (![images isKindOfClass:NSArray.class]) images = nil;
    DYYYAlbumThumbnailBar *bar = objc_getAssociatedObject(cell, &kDYYYAlbumBarKey);
    if (!valid || images.count < 2 || ![model respondsToSelector:@selector(currentImageIndex)]) {
        DYYYRemoveGalleryTap(cell);
        [bar removeFromSuperview];
        objc_setAssociatedObject(cell, &kDYYYAlbumBarKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    DYYYAttachGalleryTap(cell, model);
    if (!bar) {
        bar = [[self alloc] initWithFrame:CGRectZero];
        bar.feedCell = cell;
        objc_setAssociatedObject(cell, &kDYYYAlbumBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell addSubview:bar];
    }
    if (bar.aweme != model || bar.buttons.count != images.count) [bar configureModel:model];
    [self layoutFeedCell:cell];
}
+ (void)layoutFeedCell:(UIView *)cell {
    DYYYAlbumThumbnailBar *bar = objc_getAssociatedObject(cell, &kDYYYAlbumBarKey);
    if (!bar) return;
    if (![cell.subviews containsObject:bar]) [cell addSubview:bar];
    CGFloat safeBottom = cell.safeAreaInsets.bottom;
    CGFloat bottom = MAX(76.0, safeBottom + 59.0);
    bar.frame = CGRectMake(10, MAX(0, cell.bounds.size.height - bottom - 61), MAX(0, cell.bounds.size.width - 20), 61);
    bar.strip.frame = CGRectMake(0, 0, bar.bounds.size.width, 50);
    bar.counter.frame = CGRectMake(0, 48, bar.bounds.size.width, 13);
    [bar syncSelectedAnimated:NO];
    [bar beginPollingIfNecessary];
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.backgroundColor = [UIColor clearColor];
    self.strip = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.strip.showsHorizontalScrollIndicator = NO;
    self.strip.alwaysBounceHorizontal = YES;
    self.strip.delegate = self;
    [self addSubview:self.strip];
    self.counter = [UILabel new];
    self.counter.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.counter.textColor = UIColor.whiteColor;
    self.counter.textAlignment = NSTextAlignmentCenter;
    self.counter.layer.shadowColor = UIColor.blackColor.CGColor;
    self.counter.layer.shadowOpacity = .8;
    self.counter.layer.shadowRadius = 2;
    [self addSubview:self.counter];
    self.buttons = [NSMutableArray array];
    return self;
}
- (void)configureModel:(AWEAwemeModel *)model {
    self.aweme = model;
    [self.fallbackPreview removeFromSuperview]; self.fallbackPreview = nil;
    for (UIView *view in self.strip.subviews) [view removeFromSuperview];
    [self.buttons removeAllObjects];
    NSInteger count = model.albumImages.count;
    for (NSInteger i = 0; i < count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(4 + i * 44, 4, 36, 42);
        button.tag = i;
        button.backgroundColor = [UIColor colorWithWhite:.25 alpha:.82];
        button.layer.cornerRadius = 4;
        button.layer.masksToBounds = YES;
        button.layer.borderWidth = 1;
        button.layer.borderColor = [UIColor colorWithWhite:1 alpha:.4].CGColor;
        UIImageView *placeholder = [[UIImageView alloc] initWithFrame:button.bounds];
        placeholder.tag = 8866;
        placeholder.contentMode = UIViewContentModeScaleAspectFill;
        placeholder.clipsToBounds = YES;
        placeholder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [button addSubview:placeholder];
        [button addTarget:self action:@selector(tappedThumb:) forControlEvents:UIControlEventTouchUpInside];
        [self.strip addSubview:button]; [self.buttons addObject:button];
    }
    self.strip.contentSize = CGSizeMake(8 + 44 * count, 50);
    self.selected = NSNotFound;
    [self syncSelectedAnimated:NO];
    [self loadVisibleThumbs];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self loadVisibleThumbs]; }
- (void)loadVisibleThumbs {
    if (!self.aweme) return;
    CGFloat start = MAX(0, self.strip.contentOffset.x - 110);
    CGFloat end = self.strip.contentOffset.x + self.strip.bounds.size.width + 110;
    for (NSInteger i = 0; i < self.buttons.count; i++) {
        UIButton *button = self.buttons[i];
        if (CGRectGetMaxX(button.frame) < start || CGRectGetMinX(button.frame) > end) continue;
        UIImageView *imageView = [button viewWithTag:8866];
        if (imageView.image || objc_getAssociatedObject(button, @selector(loadVisibleThumbs))) continue;
        NSURL *url = DYYYPhotoURL(self.aweme.albumImages[i]);
        if (!url) continue;
        NSString *key = url.absoluteString;
        UIImage *cached = [DYYYPhotoThumbCache() objectForKey:key];
        if (cached) { imageView.image = cached; continue; }
        objc_setAssociatedObject(button, @selector(loadVisibleThumbs), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIButton *weakButton = button;
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!data.length || error || data.length > 18 * 1024 * 1024) return;
            CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (!imageSource) return;
            NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                   (id)kCGImageSourceThumbnailMaxPixelSize:@180,
                                   (id)kCGImageSourceCreateThumbnailWithTransform:@YES};
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)opts);
            CFRelease(imageSource);
            if (!thumbnail) return;
            UIImage *img = [UIImage imageWithCGImage:thumbnail]; CGImageRelease(thumbnail);
            if (!img) return;
            [DYYYPhotoThumbCache() setObject:img forKey:key cost:img.size.width * img.size.height * 4];
            dispatch_async(dispatch_get_main_queue(), ^{
                UIButton *strongButton = weakButton;
                if (!strongButton || strongButton.tag != i || ![self.buttons containsObject:strongButton]) return;
                ((UIImageView *)[strongButton viewWithTag:8866]).image = img;
            });
        }];
        [task resume];
    }
}
- (void)syncSelectedAnimated:(BOOL)animated {
    if (!self.aweme || !self.buttons.count) return;
    NSInteger index = MAX(0, MIN((NSInteger)self.buttons.count - 1, self.aweme.currentImageIndex > 0 ? self.aweme.currentImageIndex - 1 : 0));
    if (index == self.selected) return;
    self.selected = index;
    self.counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(index + 1), (long)self.buttons.count];
    for (UIButton *b in self.buttons) {
        BOOL active = b.tag == index;
        b.layer.borderWidth = active ? 2.5 : 1;
        b.layer.borderColor = active ? UIColor.whiteColor.CGColor : [UIColor colorWithWhite:1 alpha:.38].CGColor;
        [UIView animateWithDuration:animated ? .24 : 0 delay:0 usingSpringWithDamping:.8 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            b.transform = active ? CGAffineTransformMakeScale(1.11, 1.08) : CGAffineTransformIdentity;
        } completion:nil];
    }
    UIButton *button = self.buttons[index];
    CGFloat centerX = CGRectGetMidX(button.frame) - self.strip.bounds.size.width * .5;
    centerX = MAX(0, MIN(centerX, MAX(0, self.strip.contentSize.width - self.strip.bounds.size.width)));
    [self.strip setContentOffset:CGPointMake(centerX, 0) animated:animated];
}
- (UIScrollView *)findNativePagingView:(UIView *)root count:(NSInteger)count {
    if (!root) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 250; i++) {
        UIView *view = queue[i];
        if (view == self || [view isDescendantOfView:self]) continue;
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.bounds.size.width > root.bounds.size.width * .65 && scroll.bounds.size.width > 100 &&
                scroll.contentSize.width >= scroll.bounds.size.width * (count - .4) &&
                scroll.contentSize.width > scroll.contentSize.height * 1.5) return scroll;
            if ([scroll isKindOfClass:UICollectionView.class]) {
                UICollectionView *cv = (UICollectionView *)scroll;
                if ([cv numberOfSections] > 0 && [cv numberOfItemsInSection:0] == count && cv.bounds.size.width > root.bounds.size.width * .65) return cv;
            }
        }
        for (UIView *sub in view.subviews) [queue addObject:sub];
    }
    return nil;
}
- (void)tappedThumb:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.buttons.count || !self.aweme) return;
    // Fullscreen viewer owns the actual horizontal paging and thumbnail strip.
    DYYYPresentPhotoGallery(self.aweme, index, self.feedCell.window);
}
- (void)swipePreview:(UISwipeGestureRecognizer *)gesture {
    NSInteger delta = gesture.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1;
    NSInteger target = MAX(0, MIN(self.buttons.count - 1, self.selected + delta));
    if (target != self.selected) [self tappedThumb:self.buttons[target]];
}
- (void)loadFullPreviewForIndex:(NSInteger)idx {
    if (idx < 0 || idx >= self.aweme.albumImages.count) return;
    NSURL *url = DYYYPhotoURL(self.aweme.albumImages[idx]);
    if (!url) return;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length || data.length > 32 * 1024 * 1024) return;
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) return;
        NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                               (id)kCGImageSourceThumbnailMaxPixelSize:@2400,
                               (id)kCGImageSourceCreateThumbnailWithTransform:@YES};
        CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)opts);
        CFRelease(source);
        if (!imageRef) return;
        UIImage *large = [UIImage imageWithCGImage:imageRef]; CGImageRelease(imageRef);
        dispatch_async(dispatch_get_main_queue(), ^{
            DYYYAlbumThumbnailBar *bar = weakSelf;
            if (!bar || bar.selected != idx || !bar.fallbackPreview || !bar.fallbackPreview.superview) return;
            [UIView transitionWithView:bar.fallbackPreview duration:.30 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                bar.fallbackPreview.image = large;
            } completion:nil];
        });
    }] resume];
}
- (void)closePreview:(UITapGestureRecognizer *)gesture {
    [UIView animateWithDuration:.22 animations:^{ self.fallbackPreview.alpha = 0; } completion:^(BOOL finished) {
        [self.fallbackPreview removeFromSuperview]; self.fallbackPreview = nil;
    }];
}
- (void)beginPollingIfNecessary {
    if (self.polling || !self.window) return;
    self.polling = YES;
    __weak typeof(self) weakSelf = self;
    __block void (^tick)(void) = nil;
    tick = ^{
        __strong typeof(self) bar = weakSelf;
        if (!bar || !bar.superview || !bar.window) { if (bar) bar.polling = NO; tick = nil; return; }
        [bar syncSelectedAnimated:YES];
        [bar loadVisibleThumbs];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), tick);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), tick);
}
@end
