#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL AACEnabled(void) {
    id value=[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.autoanswer.call"] objectForKey:@"Enabled"];
    return value ? [value boolValue] : YES;
}
static NSTimeInterval AACDelay(void) {
    id value=[[[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.autoanswer.call"] objectForKey:@"Delay"];
    return value ? MAX(0.0, MIN([value doubleValue], 10.0)) : 0.5;
}
static BOOL AACIncomingState(id state) {
    if (![state isKindOfClass:NSString.class]) return NO;
    NSString *s=[state lowercaseString];
    return [s containsString:@"incoming"] || [s containsString:@"ring"] || [s containsString:@"alert"] || [s containsString:@"来电"];
}

%hook CTCall
- (void)setCallState:(id)state {
    %orig;
    if (!AACEnabled() || !AACIncomingState(state)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(AACDelay()*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!AACEnabled()) return;
        Class cls=objc_getClass("IOBluetoothHandsFreeDevice");
        if (!cls) return;
        id instance=nil;
        SEL shared=@selector(sharedInstance);
        if ([cls respondsToSelector:shared]) instance=((id(*)(id,SEL))objc_msgSend)((id)cls,shared);
        SEL accept=@selector(acceptCall);
        if (instance && [instance respondsToSelector:accept]) ((void(*)(id,SEL))objc_msgSend)(instance,accept);
    });
}
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobilePhone"]) {
        NSLog(@"[AutoAnswer] loaded");
    }
}
