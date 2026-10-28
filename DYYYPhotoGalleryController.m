#import "DYYYPhotoGalleryController.h"
#import "AwemeHeaders.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

// Only URLs of the current album are used, and no remote third-party parser is needed.
static NSURL *DYYYGalleryImageURL(id value) {
    if (!value || value == (id)NSNull.null) return nil;
    if ([value isKindOfClass:NSURL.class]) return value;
    if ([value isKindOfClass:NSString.class]) {
        NSURL *u = [NSURL URLWithString:value];
        return [@[@"http", @"https"] containsObject:u.scheme.lowercaseString] ? u : nil;
    }
    if ([value isKindOfClass:NSArray.class]) {
        for (id entry in value) { NSURL *u = DYYYGalleryImageURL(entry); if (u) return u; }
        return nil;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"originURLList", @"url_list", @"urlList", @"url", @"uri"]) {
            NSURL *u = DYYYGalleryImageURL(value[key]); if (u) return u;
        }
        return nil;
    }
    for (NSString *key in @[@"originURLList", @"urlList", @"url_list"]) {
        @try {
            NSURL *u = DYYYGalleryImageURL([value valueForKey:key]);
            if (u) return u;
        } @catch (NSException *exception) { }
    }
    return nil;
}
static NSCache *DYYYGalleryImageCache(void) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new]; cache.countLimit = 32;
        cache.totalCostLimit = 100 * 1024 * 1024;
    });
    return cache;
}

@interface DYYYPhotoGalleryController : UIViewController <UIScrollViewDelegate>
@property(nonatomic, strong) AWEAwemeModel *aweme;
@property(nonatomic, copy) NSArray *images;
@property(nonatomic, strong) UIWindow *overlay;
@property(nonatomic, strong) UIScrollView *pages;
@property(nonatomic, strong) UIScrollView *thumbStrip;
@property(nonatomic, strong) UILabel *counter;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIImageView *> *pageImages;
@property(nonatomic, strong) NSMutableArray<UIButton *> *thumbButtons;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *loadingLarge;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *loadingThumb;
@property(nonatomic) NSInteger selected;
@property(nonatomic) CGFloat lastLayoutWidth;
@end

@implementation DYYYPhotoGalleryController
- (instancetype)initWithAweme:(AWEAwemeModel *)aweme index:(NSInteger)index {
    if (!(self = [super init])) return nil;
    self.aweme = aweme;
    self.images = [aweme.albumImages copy];
    self.selected = MAX(0, MIN((NSInteger)self.images.count - 1, index));
    self.pageImages = [NSMutableDictionary dictionary];
    self.thumbButtons = [NSMutableArray array];
    self.loadingLarge = [NSMutableSet set];
    self.loadingThumb = [NSMutableSet set];
    return self;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UIScrollView *pages = [UIScrollView new];
    pages.pagingEnabled = YES;
    pages.delegate = self;
    pages.showsHorizontalScrollIndicator = NO;
    pages.showsVerticalScrollIndicator = NO;
    pages.bounces = YES;
    pages.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    pages.accessibilityLabel = @"图片左右滑动浏览";
    [self.view addSubview:pages]; self.pages = pages;

    UIView *bottom = [UIView new];
    bottom.tag = 340041;
    bottom.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    [self.view addSubview:bottom];
    UIScrollView *strip = [UIScrollView new];
    strip.delegate = self;
    strip.showsHorizontalScrollIndicator = NO;
    strip.alwaysBounceHorizontal = YES;
    strip.accessibilityLabel = @"底部图片缩略图";
    [bottom addSubview:strip]; self.thumbStrip = strip;
    for (NSInteger i = 0; i < self.images.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        button.layer.cornerRadius = 7;
        button.clipsToBounds = YES;
        button.layer.borderWidth = 1;
        button.layer.borderColor = UIColor.whiteColor.CGColor;
        button.backgroundColor = [UIColor colorWithWhite:.25 alpha:1];
        button.accessibilityLabel = [NSString stringWithFormat:@"第%ld张图片", (long)i+1];
        UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectZero];
        thumb.tag = 6606;
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.userInteractionEnabled = NO;
        [button addSubview:thumb];
        [button addTarget:self action:@selector(chooseThumbnail:) forControlEvents:UIControlEventTouchUpInside];
        [strip addSubview:button]; [self.thumbButtons addObject:button];
    }
    UILabel *counter = [UILabel new];
    counter.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    counter.textColor = UIColor.whiteColor;
    counter.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:counter]; self.counter = counter;
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.tag = 340042;
    close.tintColor = UIColor.whiteColor;
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:0 alpha:.3];
    close.layer.cornerRadius = 22;
    [close addTarget:self action:@selector(closeViewer) forControlEvents:UIControlEventTouchUpInside];
    close.accessibilityLabel = @"关闭图片浏览";
    [self.view addSubview:close];
    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleControls)];
    [pages addGestureRecognizer:single];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    if (width <= 0 || height <= 0) return;
    self.pages.frame = self.view.bounds;
    if (fabs(width - self.lastLayoutWidth) > 0.5) {
        self.lastLayoutWidth = width;
        self.pages.contentSize = CGSizeMake(width * self.images.count, height);
        for (NSNumber *key in self.pageImages) self.pageImages[key].frame = CGRectMake(key.integerValue * width, 0, width, height);
        [self.pages setContentOffset:CGPointMake(self.selected * width, 0) animated:NO];
    }
    CGFloat safeBottom = MAX(20, self.view.safeAreaInsets.bottom);
    UIView *bottom = [self.view viewWithTag:340041];
    bottom.frame = CGRectMake(0, height - safeBottom - 83, width, 83 + safeBottom);
    self.thumbStrip.frame = CGRectMake(0, 8, width, 67);
    for (NSInteger i = 0; i < self.thumbButtons.count; ++i) {
        UIButton *button = self.thumbButtons[i];
        button.frame = CGRectMake(10 + i * 62, 5, 52, 56);
        UIImageView *img = [button viewWithTag:6606]; img.frame = button.bounds;
    }
    self.thumbStrip.contentSize = CGSizeMake(20 + 62 * self.images.count, 67);
    self.counter.frame = CGRectMake(width / 2 - 64, MAX(self.view.safeAreaInsets.top, 30) + 9, 128, 28);
    UIView *close = [self.view viewWithTag:340042];
    close.frame = CGRectMake(width - 62, MAX(self.view.safeAreaInsets.top, 30) + 1, 44, 44);
    [self updateSelectedAnimated:NO];
    [self preloadAroundSelected];
}
- (void)toggleControls {
    UIView *bar = [self.view viewWithTag:340041];
    UIView *button = [self.view viewWithTag:340042];
    CGFloat target = bar.alpha > .5 ? 0 : 1;
    [UIView animateWithDuration:.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        bar.alpha = target; button.alpha = target; self.counter.alpha = target;
    } completion:nil];
}
- (void)chooseThumbnail:(UIButton *)button { [self showImageAtIndex:button.tag animated:YES]; }
- (void)showImageAtIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= self.images.count) return;
    self.selected = index;
    self.aweme.currentImageIndex = index + 1;
    [self preloadAroundSelected];
    [self.pages setContentOffset:CGPointMake(index * self.pages.bounds.size.width, 0) animated:animated];
    [self updateSelectedAnimated:animated];
}
- (void)scrollViewDidScroll:(UIScrollView *)scroll {
    if (scroll == self.thumbStrip) { [self loadVisibleThumbnails]; return; }
    if (scroll != self.pages || scroll.bounds.size.width < 1) return;
    NSInteger page = (NSInteger)lround(scroll.contentOffset.x / scroll.bounds.size.width);
    page = MAX(0, MIN((NSInteger)self.images.count - 1, page));
    if (page == self.selected) return;
    self.selected = page;
    self.aweme.currentImageIndex = page + 1;
    [self preloadAroundSelected];
    [self updateSelectedAnimated:YES];
}
- (void)updateSelectedAnimated:(BOOL)animated {
    if (self.images.count < 1) return;
    self.counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(self.selected + 1), (long)self.images.count];
    for (UIButton *button in self.thumbButtons) {
        BOOL selected = button.tag == self.selected;
        button.layer.borderWidth = selected ? 3 : 1;
        button.layer.borderColor = (selected ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:.4]).CGColor;
        [UIView animateWithDuration:animated ? .23 : 0 delay:0
             usingSpringWithDamping:.83 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState
             animations:^{ button.transform = selected ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity; }
             completion:nil];
    }
    UIButton *button = self.thumbButtons[self.selected];
    CGFloat x = CGRectGetMidX(button.frame) - self.thumbStrip.bounds.size.width / 2;
    x = MAX(0, MIN(x, MAX(0, self.thumbStrip.contentSize.width - self.thumbStrip.bounds.size.width)));
    [self.thumbStrip setContentOffset:CGPointMake(x, 0) animated:animated];
    [self loadVisibleThumbnails];
}
- (void)preloadAroundSelected {
    NSInteger count = self.images.count;
    for (NSInteger i = MAX(0, self.selected - 1); i < MIN(count, self.selected + 2); ++i) {
        NSNumber *number = @(i);
        UIImageView *imageView = self.pageImages[number];
        if (!imageView) {
            imageView = [[UIImageView alloc] initWithFrame:CGRectMake(i * self.pages.bounds.size.width, 0,
                                                self.pages.bounds.size.width, self.pages.bounds.size.height)];
            imageView.backgroundColor = UIColor.blackColor;
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            imageView.accessibilityLabel = [NSString stringWithFormat:@"第%ld张图片", (long)i + 1];
            [self.pages addSubview:imageView]; self.pageImages[number] = imageView;
        }
        [self loadImageAtIndex:i into:imageView];
    }
    // Only three adjacent images stay decoded as UIViews.
    for (NSNumber *index in [self.pageImages.allKeys copy]) {
        if (labs(index.integerValue - self.selected) > 2) {
            [self.pageImages[index] removeFromSuperview]; [self.pageImages removeObjectForKey:index];
        }
    }
}
- (void)loadImageAtIndex:(NSInteger)index into:(UIImageView *)view {
    if (view.image || [self.loadingLarge containsObject:@(index)]) return;
    NSURL *url = DYYYGalleryImageURL(self.images[index]);
    if (!url) return;
    NSString *key = [@"full:" stringByAppendingString:url.absoluteString];
    UIImage *cached = [DYYYGalleryImageCache() objectForKey:key];
    if (cached) { view.image = cached; return; }
    [self.loadingLarge addObject:@(index)];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length || data.length > 40 * 1024 * 1024) return;
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) return;
        NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                               (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                               (id)kCGImageSourceThumbnailMaxPixelSize:@2800};
        CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)opts);
        CFRelease(source);
        if (!cg) return;
        UIImage *image = [UIImage imageWithCGImage:cg]; CGImageRelease(cg);
        if (!image) return;
        [DYYYGalleryImageCache() setObject:image forKey:key cost:image.size.width * image.size.height * 4];
        dispatch_async(dispatch_get_main_queue(), ^{
            DYYYPhotoGalleryController *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.loadingLarge removeObject:@(index)];
            UIImageView *target = strongSelf.pageImages[@(index)];
            if (!target) return;
            [UIView transitionWithView:target duration:.23 options:UIViewAnimationOptionTransitionCrossDissolve
                           animations:^{ target.image = image; } completion:nil];
        });
    }] resume];
}
- (void)loadVisibleThumbnails {
    CGFloat lo = self.thumbStrip.contentOffset.x - 90;
    CGFloat hi = self.thumbStrip.contentOffset.x + self.thumbStrip.bounds.size.width + 90;
    for (NSInteger index = 0; index < self.images.count; ++index) {
        UIButton *button = self.thumbButtons[index];
        if (CGRectGetMaxX(button.frame) < lo || CGRectGetMinX(button.frame) > hi) continue;
        UIImageView *thumb = [button viewWithTag:6606];
        if (thumb.image || [self.loadingThumb containsObject:@(index)]) continue;
        NSURL *url = DYYYGalleryImageURL(self.images[index]);
        if (!url) continue;
        NSString *key = [@"small:" stringByAppendingString:url.absoluteString];
        UIImage *cached = [DYYYGalleryImageCache() objectForKey:key];
        if (cached) { thumb.image = cached; continue; }
        [self.loadingThumb addObject:@(index)];
        __weak typeof(self) weakSelf = self;
        [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data.length || data.length > 40 * 1024 * 1024) return;
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (!source) return;
            NSDictionary *opts = @{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                   (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                   (id)kCGImageSourceThumbnailMaxPixelSize:@150};
            CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)opts);
            CFRelease(source);
            if (!cg) return;
            UIImage *image = [UIImage imageWithCGImage:cg]; CGImageRelease(cg);
            if (!image) return;
            [DYYYGalleryImageCache() setObject:image forKey:key cost:image.size.width * image.size.height * 4];
            dispatch_async(dispatch_get_main_queue(), ^{
                DYYYPhotoGalleryController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf.loadingThumb removeObject:@(index)];
                if (index < strongSelf.thumbButtons.count)
                    ((UIImageView *)[strongSelf.thumbButtons[index] viewWithTag:6606]).image = image;
            });
        }] resume];
    }
}
- (void)closeViewer {
    UIWindow *overlay = self.overlay;
    [UIView animateWithDuration:.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL done) {
        overlay.hidden = YES;
        overlay.rootViewController = nil;
        self.overlay = nil;
    }];
}
@end

void DYYYPresentPhotoGallery(AWEAwemeModel *aweme, NSInteger index, UIWindow *sourceWindow) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ DYYYPresentPhotoGallery(aweme, index, sourceWindow); });
        return;
    }
    NSArray *images = aweme.albumImages;
    if (![images isKindOfClass:NSArray.class] || images.count < 2) return;
    UIWindow *window = sourceWindow;
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    if (!window) return;
    DYYYPhotoGalleryController *gallery = [[DYYYPhotoGalleryController alloc] initWithAweme:aweme index:index];
    UIWindow *overlay = nil;
    if (@available(iOS 13.0, *)) {
        if (window.windowScene) overlay = [[UIWindow alloc] initWithWindowScene:window.windowScene];
    }
    if (!overlay) overlay = [[UIWindow alloc] initWithFrame:window.bounds];
    overlay.windowLevel = UIWindowLevelAlert + 15;
    overlay.backgroundColor = UIColor.blackColor;
    overlay.rootViewController = gallery;
    gallery.overlay = overlay;
    overlay.hidden = NO;
    [gallery.view setNeedsLayout]; [gallery.view layoutIfNeeded];
    gallery.view.alpha = 0;
    [UIView animateWithDuration:.25 animations:^{ gallery.view.alpha = 1; }];
}
