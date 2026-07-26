#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"
#import "../Downloads/DownloadCoordinator.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSHashTable<UIView *> *YTKACEReelViews;
static NSMutableDictionary<NSString *, NSValue *> *YTKACEShortsOriginals;
static NSMutableSet<NSString *> *YTKACEShortsInstalledHooks;
static const void *YTKACEShortsTrackAssociation = &YTKACEShortsTrackAssociation;
static const void *YTKACEShortsFillAssociation = &YTKACEShortsFillAssociation;
static const void *YTKACEShortsSkipAssociation = &YTKACEShortsSkipAssociation;
static const void *YTKACEShortsDownloadAssociation = &YTKACEShortsDownloadAssociation;
static const void *YTKACEShortsHiddenAssociation = &YTKACEShortsHiddenAssociation;
static NSInteger const YTKACEShortsDownloadTag = 0x59544B44;
static __weak UIButton *YTKACEActiveShortsDownloadButton;
static BOOL YTKACEViewContains(UIView *ancestor, UIView *view) {
    if (ancestor == nil || view == nil) return NO;
    for (UIView *node = view; node != nil; node = node.superview) {
        if (node == ancestor) return YES;
    }
    return NO;
}

static double YTKACELastShortsTime;
static double YTKACELastShortsDuration;
static id YTKACELatestShortsPlayerResponse;

static void YTKACEReelLayout(UIView *receiver, SEL selector);
static void YTKACEShortsControllerLayout(UIViewController *receiver,
                                         SEL selector);
static void YTKACEPausedLayout(UIView *receiver, SEL selector);
static void YTKACEInteractiveStickerLayout(UIView *receiver, SEL selector);

static void YTKACESetShortsHidden(UIView *view, BOOL hidden) {
    NSNumber *baseline = objc_getAssociatedObject(
        view, YTKACEShortsHiddenAssociation);
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(view, YTKACEShortsHiddenAssociation,
                                     @(view.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        view.hidden = baseline.boolValue;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view, YTKACEShortsHiddenAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSString *YTKACEShortsHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls),
                                      NSStringFromSelector(selector)];
}

static IMP YTKACEShortsOriginal(id receiver, SEL selector,
                                NSUInteger ordinal) {
    NSUInteger candidate = 0;
    for (Class cls = object_getClass(receiver); cls != Nil;
         cls = class_getSuperclass(cls)) {
        IMP original = (IMP)[YTKACEShortsOriginals[
            YTKACEShortsHookKey(cls, selector)] pointerValue];
        if (original != NULL &&
            original != (IMP)YTKACEReelLayout &&
            original != (IMP)YTKACEShortsControllerLayout &&
            original != (IMP)YTKACEPausedLayout &&
            original != (IMP)YTKACEInteractiveStickerLayout) {
            if (candidate == ordinal) {
                return original;
            }
            candidate++;
        }
    }
    return NULL;
}

static void YTKACEInvokeShortsOriginal(id receiver, SEL selector) {
    NSMutableDictionary *threadState = NSThread.currentThread.threadDictionary;
    NSString *depthKey = [NSString stringWithFormat:
        @"YTKACE.Shorts.%p.%@", receiver, NSStringFromSelector(selector)];
    NSUInteger depth = [threadState[depthKey] unsignedIntegerValue];
    IMP original = YTKACEShortsOriginal(receiver, selector, depth);
    if (original == NULL) return;

    threadState[depthKey] = @(depth + 1);
    @try {
        ((void (*)(id, SEL))original)(receiver, selector);
    } @finally {
        if (depth == 0) {
            [threadState removeObjectForKey:depthKey];
        } else {
            threadState[depthKey] = @(depth);
        }
    }
}

static Method YTKACEShortsDirectMethod(Class cls, SEL selector) {
    if (cls == Nil) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            result = methods[index];
            break;
        }
    }
    free(methods);
    return result;
}

static BOOL YTKACEShortsIsReplacement(IMP implementation) {
    return implementation == (IMP)YTKACEReelLayout ||
        implementation == (IMP)YTKACEShortsControllerLayout ||
        implementation == (IMP)YTKACEPausedLayout ||
        implementation == (IMP)YTKACEInteractiveStickerLayout;
}

static id YTKACEShortsObject(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static id YTKACEShortsResponseFromObject(id object,
                                         NSHashTable *visited,
                                         NSUInteger depth) {
    if (object == nil || depth > 7 || [visited containsObject:object]) {
        return nil;
    }
    [visited addObject:object];
    id response = YTKACEShortsObject(object, @"contentPlayerResponse") ?:
        YTKACEShortsObject(object, @"playerResponse");
    if (response != nil) {
        return response;
    }
    for (NSString *name in @[@"_youtubeiOSPlayerViewController", @"parentResponder",
                              @"parentViewController", @"eventsDelegate",
                              @"playbackController", @"activeVideoPlayerOverlay"]) {
        id related = YTKACEShortsObject(object, name);
        response = YTKACEShortsResponseFromObject(related, visited, depth + 1);
        if (response != nil) {
            return response;
        }
    }
    if ([object isKindOfClass:UIResponder.class]) {
        return YTKACEShortsResponseFromObject(
            ((UIResponder *)object).nextResponder, visited, depth + 1);
    }
    return nil;
}

static NSMutableDictionary<NSString *, NSNumber *> *YTKACEShortsBarrenClasses;

static id YTKACEShortsPlayerResponseFromObject(id object) {
    if (object == nil) return nil;
    NSString *name = NSStringFromClass([object class]);
    if (YTKACEShortsBarrenClasses == nil) {
        YTKACEShortsBarrenClasses = [NSMutableDictionary dictionary];
    }
    if (YTKACEShortsBarrenClasses[name].integerValue >= 3) return nil;

    NSHashTable *visited = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsObjectPointerPersonality];
    id result = YTKACEShortsResponseFromObject(object, visited, 0);
    if (result != nil) {
        [YTKACEShortsBarrenClasses removeObjectForKey:name];
    } else {
        YTKACEShortsBarrenClasses[name] =
            @(YTKACEShortsBarrenClasses[name].integerValue + 1);
    }
    return result;
}

@interface YTKACEShortsDownloadTarget : NSObject
+ (instancetype)sharedTarget;
- (void)downloadTapped:(UIButton *)sender;
@end

@implementation YTKACEShortsDownloadTarget
+ (instancetype)sharedTarget {
    static YTKACEShortsDownloadTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [YTKACEShortsDownloadTarget new]; });
    return target;
}
- (void)downloadTapped:(UIButton *)sender {
    [YTKACEShortsBarrenClasses removeAllObjects];
    id fromView = YTKACEShortsPlayerResponseFromObject(sender);
    id response = fromView ?: YTKACELatestShortsPlayerResponse;
    YTKACEDownloadCoordinator.sharedCoordinator.playerResponse = response;
    [YTKACEDownloadCoordinator.sharedCoordinator
        showShortsDownloadMenuFromView:sender];
}
@end

static double YTKACEShortsDouble(id receiver, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            return ((double (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    return 0.0;
}

static id YTKACEShortsParent(id receiver) {
    SEL selector = NSSelectorFromString(@"parentViewController");
    return [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
        : nil;
}

static id YTKACEFindShortsController(id receiver) {
    id current = receiver;
    for (NSInteger index = 0; current != nil && index < 10; index++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"shorts"] || [name containsString:@"reel"]) {
            return current;
        }
        id parent = YTKACEShortsParent(current);
        if (parent != nil && parent != current) {
            current = parent;
        } else if ([current isKindOfClass:UIResponder.class]) {
            current = ((UIResponder *)current).nextResponder;
        } else {
            break;
        }
    }
    return nil;
}

static BOOL YTKACEAdvanceShort(id controller, id sender) {
    for (NSString *name in @[
        @"reelContentViewRequestsAdvanceToNextVideo:",
        @"advanceToNextVideo:",
        @"advanceToNextVideo",
        @"scrollToNextVideo"
    ]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([controller class], selector);
        if (method == NULL) {
            continue;
        }
        if (method_getNumberOfArguments(method) == 3) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, sender);
        } else {
            ((void (*)(id, SEL))objc_msgSend)(controller, selector);
        }
        return YES;
    }
    return NO;
}

static void YTKACEUpdateShortsProgress(void) {
    BOOL enabled = YTKACEFeatureEnabled(@"shortsProgress");
    CGFloat ratio = YTKACELastShortsDuration > 0.0
        ? (CGFloat)MIN(1.0, MAX(0.0, YTKACELastShortsTime / YTKACELastShortsDuration))
        : 0.0;
    for (UIView *view in YTKACEReelViews.allObjects) {
        CALayer *track = objc_getAssociatedObject(view, YTKACEShortsTrackAssociation);
        CALayer *fill = objc_getAssociatedObject(view, YTKACEShortsFillAssociation);
        track.hidden = !enabled;
        fill.hidden = !enabled;
        if (enabled) {
            CGFloat height = 3.0;
            track.frame = CGRectMake(0.0,
                                     MAX(0.0, CGRectGetHeight(view.bounds) - height),
                                     CGRectGetWidth(view.bounds),
                                     height);
            fill.frame = CGRectMake(0.0, 0.0,
                                    CGRectGetWidth(track.bounds) * ratio,
                                    height);
            YTKACEStyleProgressLayer(fill, CGRectGetWidth(track.bounds));
        }
    }
}

static void YTKACEConfigureReelView(UIView *receiver, BOOL showDownload) {
    [YTKACEReelViews addObject:receiver];
    CALayer *track = objc_getAssociatedObject(receiver, YTKACEShortsTrackAssociation);
    CALayer *fill = objc_getAssociatedObject(receiver, YTKACEShortsFillAssociation);
    if (track == nil) {
        track = [CALayer layer];
        track.backgroundColor = [UIColor colorWithWhite:0.45 alpha:0.55].CGColor;
        track.zPosition = 10000.0;
        fill = [CALayer layer];
        fill.backgroundColor = UIColor.redColor.CGColor;
        objc_setAssociatedObject(receiver, YTKACEShortsFillAssociation,
                                 fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [track addSublayer:fill];
        [receiver.layer addSublayer:track];
        objc_setAssociatedObject(receiver, YTKACEShortsTrackAssociation,
                                 track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(receiver, YTKACEShortsFillAssociation,
                                 fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIButton *download =
        objc_getAssociatedObject(receiver, YTKACEShortsDownloadAssociation);
    if (showDownload && download == nil) {
        UIButton *active = YTKACEActiveShortsDownloadButton;
        UIView *activeHost = active.superview;
        if (active != nil && activeHost != nil && activeHost != receiver) {
            if (YTKACEViewContains(receiver, activeHost)) {
                YTKACEUpdateShortsProgress();
                return;
            }
            if (YTKACEViewContains(activeHost, receiver)) {
                [active removeFromSuperview];
                objc_setAssociatedObject(activeHost,
                                         YTKACEShortsDownloadAssociation, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        download = [UIButton buttonWithType:UIButtonTypeSystem];
        download.tag = YTKACEShortsDownloadTag;
        download.accessibilityIdentifier = @"YTKACE Shorts Download";
        download.accessibilityLabel = @"Download Short";
        download.tintColor = UIColor.whiteColor;
        [download setImage:YTKACEDownloadGlyphImage()
                  forState:UIControlStateNormal];
        download.layer.shadowColor = UIColor.blackColor.CGColor;
        download.layer.shadowOpacity = 0.55;
        download.layer.shadowRadius = 4.0;
        download.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        download.translatesAutoresizingMaskIntoConstraints = NO;
        [download addTarget:YTKACEShortsDownloadTarget.sharedTarget
                     action:@selector(downloadTapped:)
           forControlEvents:UIControlEventTouchUpInside];
        [receiver addSubview:download];
        [NSLayoutConstraint activateConstraints:@[
            [download.widthAnchor constraintEqualToConstant:40.0],
            [download.heightAnchor constraintEqualToConstant:40.0],
            [download.trailingAnchor constraintEqualToAnchor:
                receiver.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
            [download.topAnchor constraintEqualToAnchor:
                receiver.safeAreaLayoutGuide.topAnchor constant:65.0]
        ]];
        objc_setAssociatedObject(receiver, YTKACEShortsDownloadAssociation,
            download, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTKACEActiveShortsDownloadButton = download;
    }
    if (download != nil) {
        download.hidden = !YTKACEFeatureEnabled(YTKACEDownloadKey);
        [receiver bringSubviewToFront:download];
    }
    static NSTimeInterval lastResolve = 0.0;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (YTKACELatestShortsPlayerResponse == nil || now - lastResolve > 0.5) {
        lastResolve = now;
        id response = YTKACEShortsPlayerResponseFromObject(receiver);
        if (response != nil) {
            YTKACELatestShortsPlayerResponse = response;
        }
    }
    YTKACEUpdateShortsProgress();
}

static void YTKACEReelLayout(UIView *receiver, SEL selector) {
    YTKACEInvokeShortsOriginal(receiver, selector);
    YTKACEConfigureReelView(receiver, NO);
}

static void YTKACEShortsControllerLayout(UIViewController *receiver,
                                         SEL selector) {
    YTKACEInvokeShortsOriginal(receiver, selector);
    YTKACEConfigureReelView(receiver.view, YES);
}

static void YTKACEPausedLayout(UIView *receiver, SEL selector) {
    YTKACEInvokeShortsOriginal(receiver, selector);
    BOOL hidden = YTKACEFeatureEnabled(@"kEnableBlockShortsOverlays");
    YTKACESetShortsHidden(receiver, hidden);
}

static void YTKACEInteractiveStickerLayout(UIView *receiver, SEL selector) {
    YTKACEInvokeShortsOriginal(receiver, selector);
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
        NSStringFromClass(receiver.class).lowercaseString,
        receiver.accessibilityIdentifier.lowercaseString ?: @"",
        receiver.description.lowercaseString ?: @""];
    BOOL product = YTKACEFeatureEnabled(@"kEnableHideShortsProducts") &&
        ([token containsString:@"product"] ||
         [token containsString:@"shopping"]);
    BOOL stickerAd = YTKACEFeatureEnabled(@"kEnableHideShortsStickerAds") &&
        (([token containsString:@"sticker"] &&
          ([token containsString:@"sponsor"] ||
           [token containsString:@"promot"] ||
           [token containsString:@"brand"] ||
           [token containsString:@"product"])) ||
         [token containsString:@"shorts_ads_shopping"]);
    YTKACESetShortsHidden(receiver, product || stickerAd);
}

static void YTKACEInstallShortsLayout(NSString *className, IMP replacement) {
    Class cls = NSClassFromString(className);
    SEL selector = @selector(layoutSubviews);
    if (YTKACEShortsDirectMethod(cls, selector) == NULL) return;
    NSString *key = YTKACEShortsHookKey(cls, selector);
    if ([YTKACEShortsInstalledHooks containsObject:key]) return;
    IMP current = method_getImplementation(class_getInstanceMethod(cls, selector));
    if (YTKACEShortsIsReplacement(current)) return;
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, @"layoutSubviews",
                                  replacement, &original) &&
        original != NULL && !YTKACEShortsIsReplacement(original)) {
        YTKACEShortsOriginals[key] =
            [NSValue valueWithPointer:(const void *)original];
        [YTKACEShortsInstalledHooks addObject:key];
    }
}

static void YTKACEInstallShortsController(NSString *className) {
    SEL selector = @selector(viewDidLayoutSubviews);
    Class cls = NSClassFromString(className);
    if (YTKACEShortsDirectMethod(cls, selector) == NULL) return;
    NSString *key = YTKACEShortsHookKey(cls, selector);
    if ([YTKACEShortsInstalledHooks containsObject:key]) return;
    IMP current = method_getImplementation(class_getInstanceMethod(cls, selector));
    if (YTKACEShortsIsReplacement(current)) return;
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className,
                                  NSStringFromSelector(selector),
                                  (IMP)YTKACEShortsControllerLayout,
                                  &original) && original != NULL &&
        !YTKACEShortsIsReplacement(original)) {
        YTKACEShortsOriginals[key] =
            [NSValue valueWithPointer:(const void *)original];
        [YTKACEShortsInstalledHooks addObject:key];
    }
}

static void YTKACEShortsTimeChanged(NSNotification *notification) {
    id player = notification.object;
    id shorts = YTKACEFindShortsController(player);
    if (shorts == nil) {
        return;
    }
    static CFTimeInterval lastLookup = 0.0;
    if (YTKACELatestShortsPlayerResponse == nil ||
        CACurrentMediaTime() - lastLookup > 1.0) {
        lastLookup = CACurrentMediaTime();
        id response = YTKACEShortsPlayerResponseFromObject(player) ?:
            YTKACEShortsPlayerResponseFromObject(shorts);
        if (response != nil) {
            YTKACELatestShortsPlayerResponse = response;
        }
    }
    double time = [notification.userInfo[@"time"] doubleValue];
    double duration = YTKACEShortsDouble(player, @[
        @"currentVideoTotalMediaTime",
        @"currentVideoTotalTime",
        @"currentVideoDuration",
        @"totalMediaTime"
    ]);
    YTKACELastShortsTime = time;
    YTKACELastShortsDuration = duration;
    YTKACEUpdateShortsProgress();

    if (!YTKACEFeatureEnabled(@"autoSkipShorts") || duration <= 1.0) {
        return;
    }
    if (time < duration * 0.5) {
        objc_setAssociatedObject(shorts, YTKACEShortsSkipAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (time >= duration - 0.35 &&
        ![objc_getAssociatedObject(shorts, YTKACEShortsSkipAssociation) boolValue]) {
        if (YTKACEAdvanceShort(shorts, player)) {
            objc_setAssociatedObject(shorts, YTKACEShortsSkipAssociation, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

void YTKACEInstallShortsHooks(void) {
    if (YTKACEReelViews == nil) {
        YTKACEReelViews = [NSHashTable weakObjectsHashTable];
        YTKACEShortsOriginals = [NSMutableDictionary dictionary];
        YTKACEShortsInstalledHooks = [NSMutableSet set];
        [NSNotificationCenter.defaultCenter
            addObserverForName:@"YTKACEPlaybackTimeDidChange"
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                YTKACEShortsTimeChanged(notification);
            }];
    }
    for (NSString *className in @[
        @"YTReelContentView",
        @"YTReelPlayerView",
        @"YTShortsPlayerView",
        @"YTShortsPlayerViewControllerView",
        @"YTShortsPlayerViewSwift"
    ]) {
        YTKACEInstallShortsLayout(className, (IMP)YTKACEReelLayout);
    }
    for (NSString *className in @[
        @"YTAppReelWatchRootViewController",
        @"YTReelWatchRootViewController",
        @"YTReelContainerViewController",
        @"YTReelPlaybackViewController",
        @"YTReelPlayerViewController",
        @"YTShortsPlayerViewController"
    ]) {
        YTKACEInstallShortsController(className);
    }
    for (NSString *className in @[
        @"YTReelPausedStateCarouselView",
        @"YTReelPlayerPausedStateView"
    ]) {
        YTKACEInstallShortsLayout(className, (IMP)YTKACEPausedLayout);
    }
    for (NSString *className in @[
        @"YTReelInteractiveStickerView",
        @"YTShortsStickersView",
        @"YTShortsStickersViewSwift"
    ]) {
        YTKACEInstallShortsLayout(className,
                                  (IMP)YTKACEInteractiveStickerLayout);
    }
}
