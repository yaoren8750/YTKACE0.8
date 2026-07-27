#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../Downloads/DownloadLog.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>

static BOOL YTKACECastYes(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YES;
}

static BOOL YTKACECastNo(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return NO;
}

static NSInteger YTKACECastAllowedStatus(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 1;
}

static void YTKACESkipLocalNetworkPage(id receiver,
                                       SEL selector,
                                       id completion) {
    (void)receiver;
    (void)selector;
    YTKACEDownloadLog(@"cast", @"permission page bypassed");
    YTKACEStartCastDiscovery();
    if (completion == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            ((void (^)(BOOL))completion)(YES);
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"permission completion failed");
        }
    });
}

static BOOL YTKACECastClass(Class cls) {
    NSString *name = NSStringFromClass(cls);
    return [name hasPrefix:@"MDX"] || [name hasPrefix:@"YT"] ||
        [name hasPrefix:@"CADP"] || [name hasPrefix:@"GCK"];
}

static NSString *YTKACECastCacheKey(void) {
    NSString *version = NSBundle.mainBundle
        .infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
    return [@"YTKACECastHookTargets." stringByAppendingString:version];
}

static BOOL YTKACEApplyDirectCastHook(Class cls, SEL selector) {
    if (cls == Nil || selector == NULL) return NO;
    static NSSet<NSString *> *yesSelectors;
    static NSSet<NSString *> *noSelectors;
    static NSSet<NSString *> *statusSelectors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        yesSelectors = [NSSet setWithArray:@[
            @"hasSufficientLocalNetworkPermissions",
            @"isLocalNetworkPermissionAllowed",
            @"wasLocalNetworkPermissionAllowed"
        ]];
        noSelectors = [NSSet setWithArray:@[
            @"shouldShowLocalNetworkPermissionPrompt",
            @"shouldPresentLocalNetworkAccessPermissionDialog"
        ]];
        statusSelectors = [NSSet setWithArray:@[
            @"lastKnownPermissionsStatus",
            @"localNetworkPermissionsStatus"
        ]];
    });
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) return NO;
    NSString *name = NSStringFromSelector(selector);
    IMP replacement = NULL;
    if ([yesSelectors containsObject:name]) replacement = (IMP)YTKACECastYes;
    if ([noSelectors containsObject:name]) replacement = (IMP)YTKACECastNo;
    if ([statusSelectors containsObject:name]) {
        replacement = (IMP)YTKACECastAllowedStatus;
    }
    if (replacement == NULL) return NO;
    method_setImplementation(method, replacement);
    return YES;
}

static void YTKACEApplyCachedCastHooks(void) {
    NSArray<NSString *> *targets = [NSUserDefaults.standardUserDefaults
        arrayForKey:YTKACECastCacheKey()];
    for (NSString *target in targets) {
        NSArray<NSString *> *parts = [target componentsSeparatedByString:@"|"];
        if (parts.count != 2) continue;
        YTKACEApplyDirectCastHook(NSClassFromString(parts[0]),
                                  NSSelectorFromString(parts[1]));
    }
}

static void YTKACEDiscoverCastHooks(void) {
    int classCapacity = objc_getClassList(NULL, 0);
    if (classCapacity <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc(
        (size_t)classCapacity,
        sizeof(Class)
    );
    if (classes == NULL) return;
    int classCount = objc_getClassList(classes, classCapacity);
    if (classCount > classCapacity) classCount = classCapacity;
    NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
    for (int classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        if (cls == Nil || !YTKACECastClass(cls)) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            Method method = methods[methodIndex];
            SEL selector = method_getName(method);
            NSString *selectorName = NSStringFromSelector(selector);
            if ([selectorName isEqualToString:
                    @"hasSufficientLocalNetworkPermissions"] ||
                [selectorName isEqualToString:
                    @"isLocalNetworkPermissionAllowed"] ||
                [selectorName isEqualToString:
                    @"wasLocalNetworkPermissionAllowed"] ||
                [selectorName isEqualToString:
                    @"shouldShowLocalNetworkPermissionPrompt"] ||
                [selectorName isEqualToString:
                    @"shouldPresentLocalNetworkAccessPermissionDialog"] ||
                [selectorName isEqualToString:
                    @"lastKnownPermissionsStatus"] ||
                [selectorName isEqualToString:
                    @"localNetworkPermissionsStatus"]) {
                [targets addObject:[NSString stringWithFormat:@"%@|%@",
                    NSStringFromClass(cls), selectorName]];
            }
        }
        free(methods);
    }
    free(classes);
    NSArray<NSString *> *result = targets.array;
    [NSUserDefaults.standardUserDefaults setObject:result
                                            forKey:YTKACECastCacheKey()];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSString *target in result) {
            NSArray<NSString *> *parts =
                [target componentsSeparatedByString:@"|"];
            if (parts.count != 2) continue;
            YTKACEApplyDirectCastHook(NSClassFromString(parts[0]),
                                      NSSelectorFromString(parts[1]));
        }
    });
}

static void YTKACERefreshCastHooks(void) {
    YTKACEApplyCachedCastHooks();
    YTKACEInstallInstanceHook(@"MDXRoutePresentationController",
                              @"hasSufficientLocalNetworkPermissions",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"lastKnownPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"isAuthorized",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalStorage",
                              @"localNetworkPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(
        @"MDXPermissionsController",
        @"showLocalNetworkPermissionsRequiredPageWithCompletion:",
        (IMP)YTKACESkipLocalNetworkPage,
        NULL
    );
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"isLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"wasLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(
        @"CADPLocalNetworkPermissionInfo",
        @"shouldPresentLocalNetworkAccessPermissionDialog",
        (IMP)YTKACECastNo,
        NULL
    );
    YTKACEInstallInstanceHook(
        @"YTBAMediaHubUiDeviceItemsResult",
        @"shouldShowLocalNetworkPermissionPrompt",
        (IMP)YTKACECastNo,
        NULL
    );
}

void YTKACEStartCastDiscovery(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class contextClass = NSClassFromString(@"GCKCastContext");
            SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
            if (contextClass == Nil ||
                ![contextClass respondsToSelector:sharedSelector]) {
                YTKACEDownloadLog(@"cast", @"context unavailable");
                return;
            }
            id context = ((id (*)(id, SEL))objc_msgSend)(contextClass,
                                                         sharedSelector);
            SEL managerSelector = NSSelectorFromString(@"discoveryManager");
            if (context == nil || ![context respondsToSelector:managerSelector]) {
                YTKACEDownloadLog(@"cast", @"manager unavailable");
                return;
            }
            id manager = ((id (*)(id, SEL))objc_msgSend)(context,
                                                         managerSelector);
            SEL startSelector = NSSelectorFromString(@"startDiscovery");
            if (manager != nil && [manager respondsToSelector:startSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(manager, startSelector);
                YTKACEDownloadLog(@"cast", @"discovery started");
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                    dispatch_get_main_queue(), ^{
                        SEL countSelector = NSSelectorFromString(@"deviceCount");
                        if ([manager respondsToSelector:countSelector]) {
                            NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
                                manager,
                                countSelector
                            );
                            YTKACEDownloadLog(@"cast", @"devices=%lu",
                                             (unsigned long)count);
                        }
                    }
                );
            }
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"discovery exception");
        }
    });
}

void YTKACEInstallCastCompatibilityHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACERefreshCastHooks();

        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        YTKACERefreshCastHooks();
                        YTKACEStartCastDiscovery();
                        if ([NSUserDefaults.standardUserDefaults
                                arrayForKey:YTKACECastCacheKey()].count != 0) {
                            return;
                        }
                        static dispatch_once_t discoveryToken;
                        dispatch_once(&discoveryToken, ^{
                            for (NSNumber *delay in @[@0.5, @4.0]) {
                                dispatch_after(
                                    dispatch_time(DISPATCH_TIME_NOW,
                                      (int64_t)(delay.doubleValue *
                                                NSEC_PER_SEC)),
                                    dispatch_get_global_queue(
                                      QOS_CLASS_UTILITY, 0), ^{
                                        YTKACEDiscoverCastHooks();
                                    }
                                );
                            }
                        });
                    }];
    });
}
