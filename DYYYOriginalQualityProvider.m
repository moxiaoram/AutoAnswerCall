#import "DYYYOriginalQualityProvider.h"
#import "DYYYManager.h"
#import "DYYYUtils.h"
#import "AwemeHeaders.h"
#import <Security/Security.h>

// Documented by TikHub (https://docs.tikhub.io/312096107e0), NOT a free API.
// Do NOT silently query it: each successful request may consume paid API credits.
static NSString * const AVOriginalProviderURL = @"https://api.tikhub.io/api/v1/douyin/app/v3/fetch_video_high_quality_play_url";

static NSString *AVStringValue(id obj, NSString *key) {
    id value = nil;
    @try { value = [obj valueForKey:key]; } @catch (__unused NSException *e) { }
    return [value isKindOfClass:NSString.class] ? value : nil;
}
static NSString *AVAwemeID(AWEAwemeModel *aweme) {
    for (NSString *key in @[@"awemeID", @"awemeId", @"aweme_id", @"itemID", @"itemId", @"groupId"]) {
        NSString *value = AVStringValue(aweme, key);
        if (value.length && [[NSCharacterSet decimalDigitCharacterSet] isSupersetOfSet:[NSCharacterSet characterSetWithCharactersInString:value]]) return value;
    }
    NSString *share = AVStringValue(aweme, @"shareURL") ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:video/|modal_id=|aweme_id=)([0-9]{12,25})" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:share options:0 range:NSMakeRange(0, share.length)];
    return match.numberOfRanges > 1 ? [share substringWithRange:[match rangeAtIndex:1]] : nil;
}
@implementation DYYYOriginalQualityProvider
// Keep the paid API token in the device Keychain, never in the app's prefs backup.
// Settings identifier DYYYOriginalQualityToken is backed by this Keychain provider.
+ (NSMutableDictionary *)keychainQuery {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.local.awemevision.original-quality",
              (__bridge id)kSecAttrAccount:@"tikhub-token"} mutableCopy];
}
+ (void)saveToken:(NSString *)token {
    NSMutableDictionary *query = [self keychainQuery];
    if (![token isKindOfClass:NSString.class] || !token.length) {
        SecItemDelete((__bridge CFDictionaryRef)query);
        return;
    }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status == errSecItemNotFound) {
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    if (status != errSecSuccess) [DYYYUtils showToast:@"Token 未能写入钥匙串，请检查应用权限"];
}
+ (NSString *)savedToken {
    NSMutableDictionary *query = [self keychainQuery];
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
+ (void)fetchForAweme:(AWEAwemeModel *)aweme download:(BOOL)download {
    NSString *token = [self savedToken];
    if (!token.length) {
        [DYYYUtils showToast:@"请先在下载设置填写 TikHub Token；原画接口按次收费"];
        return;
    }
    if (!aweme) { [DYYYUtils showToast:@"当前未取得视频模型"]; return; }
    NSString *awemeID = AVAwemeID(aweme);
    NSString *share = AVStringValue(aweme, @"shareURL");
    if (!awemeID.length && !share.length) { [DYYYUtils showToast:@"无法获取作品ID或分享链接"]; return; }
    NSURLComponents *url = [NSURLComponents componentsWithString:AVOriginalProviderURL];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    if (awemeID.length) [items addObject:[NSURLQueryItem queryItemWithName:@"aweme_id" value:awemeID]];
    else [items addObject:[NSURLQueryItem queryItemWithName:@"share_url" value:share]];
    NSString *region = [[NSUserDefaults standardUserDefaults] stringForKey:@"DYYYOriginalQualityRegion"];
    if (!region.length) region = @"CN";
    if (region.length == 2 && [[NSCharacterSet letterCharacterSet] isSupersetOfSet:[NSCharacterSet characterSetWithCharactersInString:region]])
        [items addObject:[NSURLQueryItem queryItemWithName:@"region" value:region.uppercaseString]];
    url.queryItems = items;
    if (!url.URL) { [DYYYUtils showToast:@"原画接口地址错误"]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30.0];
    [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { [DYYYUtils showToast:[NSString stringWithFormat:@"原画请求失败: %@", error.localizedDescription]]; return; }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (status != 200 || data.length == 0) { [DYYYUtils showToast:[NSString stringWithFormat:@"原画服务 HTTP %ld（请检查Token/余额）", (long)status]]; return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:NSDictionary.class]) { [DYYYUtils showToast:@"原画服务没有返回JSON"]; return; }
            NSInteger code = [json[@"code"] respondsToSelector:@selector(integerValue)] ? [json[@"code"] integerValue] : 200;
            if (code != 0 && code != 200) { [DYYYUtils showToast:@"原画服务返回失败（请检查额度与作品权限）"]; return; }
            NSDictionary *payload = [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : json;
            NSString *media = [payload[@"original_video_url"] isKindOfClass:NSString.class] ? payload[@"original_video_url"] : nil;
            NSURL *mediaURL = [NSURL URLWithString:media ?: @""];
            if (!([mediaURL.scheme.lowercaseString isEqualToString:@"https"] || [mediaURL.scheme.lowercaseString isEqualToString:@"http"]) || !mediaURL.host.length) {
                [DYYYUtils showToast:@"服务未返回有效原画链接"]; return;
            }
            if (download) {
                // Do not pretend segmented manifests are ordinary MP4 files.
                if ([@[@"m3u8", @"mpd"] containsObject:mediaURL.pathExtension.lowercaseString]) {
                    UIPasteboard.generalPasteboard.string = media;
                    [DYYYUtils showToast:@"原画为分段流，已复制播放链接"]; return;
                }
                [DYYYManager downloadMedia:mediaURL mediaType:MediaTypeVideo audio:nil completion:^(BOOL ok){
                    [DYYYUtils showToast:ok ? @"原画视频已保存" : @"原画地址已返回但下载失败（可能过期）"];
                }];
            } else {
                UIPasteboard.generalPasteboard.string = media;
                [DYYYUtils showToast:@"最高原上传画质地址已复制（签名可能过期）"];
            }
        });
    }] resume];
}
@end
