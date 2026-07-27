#import "NavigationVisibility.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>

static IMP OriginalHeaderLogoLayout;
static IMP OriginalLogoViewLayout;
static IMP OriginalQTMButtonLayout;
static IMP OriginalQTMButtonSetTint;
static IMP OriginalQTMButtonSetImage;
static IMP OriginalNavigationImageSetTint;
static IMP OriginalNavigationImageSetImage;
static IMP OriginalYTImageViewLayout;
static IMP OriginalMainWindowTraitChanged;
static IMP OriginalRightNavigationTraitChanged;
static NSMutableDictionary<NSString *, NSValue *> *YTKACENavigationOriginals;
static const void *YTKACENavigationHiddenAssociation = &YTKACENavigationHiddenAssociation;
static BOOL YTKACENavigationObserverInstalled;
static NSHashTable<UIView *> *YTKACENavigationOwners;
static UIUserInterfaceStyle YTKACENavigationStyle = UIUserInterfaceStyleUnspecified;

static void YTKACEApplyNavigationWindows(void);
static void YTKACEApplyNavigationSelectors(id owner);
static BOOL YTKACEInsideRightNavigation(UIView *view);

static NSValue *YTKACENavigationIMPValue(IMP implementation) {
    return [NSValue value:&implementation withObjCType:@encode(IMP)];
}

static IMP YTKACENavigationIMP(NSValue *value) {
    IMP implementation = NULL;
    [value getValue:&implementation];
    return implementation;
}

static NSString *YTKACENavigationHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@",
            NSStringFromClass(cls), NSStringFromSelector(selector)];
}

static IMP YTKACENavigationOriginal(id receiver, SEL selector) {
    for (Class cls = object_getClass(receiver); cls != Nil; cls = class_getSuperclass(cls)) {
        NSValue *value = YTKACENavigationOriginals[
            YTKACENavigationHookKey(cls, selector)
        ];
        if (value != nil) return YTKACENavigationIMP(value);
    }
    return NULL;
}

static void YTKACESetNavigationHidden(UIView *view, BOOL hidden) {
    if (view == nil ||
        [view.accessibilityLabel hasPrefix:@"YTKACE"] ||
        [view.accessibilityIdentifier hasPrefix:@"YTKACE"]) {
        return;
    }
    NSNumber *baseline = objc_getAssociatedObject(
        view,
        YTKACENavigationHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(view,
                                     YTKACENavigationHiddenAssociation,
                                     @(view.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        view.hidden = baseline.boolValue;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view,
                                 YTKACENavigationHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static id YTKACENotificationButton(id receiver, SEL selector) {
    IMP original = YTKACENavigationOriginal(receiver, selector);
    id value = original == NULL
        ? nil
        : ((id (*)(id, SEL))original)(receiver, selector);
    if ([value isKindOfClass:UIView.class]) {
        YTKACESetNavigationHidden(
            value,
            YTKACEFeatureEnabled(@"kEnableHideNotificationBill")
        );
    }
    return value;
}

static BOOL YTKACEHideNotificationButton(id receiver, SEL selector) {
    IMP original = YTKACENavigationOriginal(receiver, selector);
    BOOL hidden = original == NULL
        ? NO
        : ((BOOL (*)(id, SEL))original)(receiver, selector);
    return hidden || YTKACEFeatureEnabled(@"kEnableHideNotificationBill");
}

static void YTKACESetHideNotificationButton(id receiver,
                                             SEL selector,
                                             BOOL hidden) {
    IMP original = YTKACENavigationOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, BOOL))original)(
            receiver,
            selector,
            hidden || YTKACEFeatureEnabled(@"kEnableHideNotificationBill")
        );
    }
}

static void YTKACEInstallNavigationMethodHooks(void) {
    if (YTKACENavigationOriginals == nil) {
        YTKACENavigationOriginals = [NSMutableDictionary dictionary];
    }
    NSString *version = NSBundle.mainBundle
        .infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *cacheKey =
        [@"YTKACENavigationHookTargets." stringByAppendingString:version];
    NSDictionary<NSString *, NSValue *> *replacements = @{
        @"notificationButton":
            YTKACENavigationIMPValue((IMP)YTKACENotificationButton),
        @"newNotificationButton":
            YTKACENavigationIMPValue((IMP)YTKACENotificationButton),
        @"hideNotificationButton":
            YTKACENavigationIMPValue((IMP)YTKACEHideNotificationButton),
        @"setHideNotificationButton:":
            YTKACENavigationIMPValue((IMP)YTKACESetHideNotificationButton)
    };
    void (^applyTargets)(NSArray<NSString *> *) =
        ^(NSArray<NSString *> *targets) {
            for (NSString *target in targets) {
                NSArray<NSString *> *parts =
                    [target componentsSeparatedByString:@"|"];
                if (parts.count != 2) continue;
                Class cls = NSClassFromString(parts[0]);
                SEL selector = NSSelectorFromString(parts[1]);
                Method method = class_getInstanceMethod(cls, selector);
                NSValue *replacement = replacements[parts[1]];
                if (method == NULL || replacement == nil) continue;
                IMP hook = YTKACENavigationIMP(replacement);
                IMP original = method_getImplementation(method);
                if (original == hook) continue;
                YTKACENavigationOriginals[
                    YTKACENavigationHookKey(cls, selector)
                ] = YTKACENavigationIMPValue(original);
                method_setImplementation(method, hook);
            }
        };
    applyTargets([NSUserDefaults.standardUserDefaults arrayForKey:cacheKey]);
}

static void YTKACEDiscoverNavigationMethodHooks(void) {
    NSSet<NSString *> *selectors = [NSSet setWithArray:@[
        @"notificationButton",
        @"newNotificationButton",
        @"hideNotificationButton",
        @"setHideNotificationButton:"
    ]];
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
    for (int index = 0; index < count; index++) {
        Class cls = classes[index];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            Method method = methods[methodIndex];
            SEL selector = method_getName(method);
            NSString *selectorName = NSStringFromSelector(selector);
            if (![selectors containsObject:selectorName]) continue;
            [targets addObject:[NSString stringWithFormat:@"%@|%@",
                NSStringFromClass(cls), selectorName]];
        }
        free(methods);
    }
    free(classes);
    NSString *version = NSBundle.mainBundle
        .infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *cacheKey =
        [@"YTKACENavigationHookTargets." stringByAppendingString:version];
    NSArray<NSString *> *result = targets.array;
    [NSUserDefaults.standardUserDefaults setObject:result forKey:cacheKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        YTKACEInstallNavigationMethodHooks();
        YTKACEApplyNavigationWindows();
    });
}

static BOOL YTKACENavigationShouldHide(UIView *view) {
    NSString *token = [[NSString stringWithFormat:@"%@ %@ %@",
                        NSStringFromClass(view.class),
                        view.accessibilityIdentifier ?: @"",
                        view.accessibilityLabel ?: @""] lowercaseString];
    if (YTKACEFeatureEnabled(@"kEnableHideAccount") &&
        ([token containsString:@"account"] ||
         [token containsString:@"avatar"] ||
         [token containsString:@"profile"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideSearch") &&
        [token containsString:@"search"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCastButton") &&
        ([token containsString:@"cast"] ||
         [token containsString:@"airplay"] ||
         [token containsString:@"routebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideNotificationBill") &&
        ([token containsString:@"notification"] ||
         [token containsString:@"bell"])) {
        return YES;
    }
    return NO;
}

static BOOL YTKACEIsNavigationIcon(UIView *view) {
    NSString *token = [[NSString stringWithFormat:@"%@ %@ %@",
                        NSStringFromClass(view.class),
                        view.accessibilityIdentifier ?: @"",
                        view.accessibilityLabel ?: @""] lowercaseString];
    if ([token containsString:@"account"] ||
        [token containsString:@"avatar"] ||
        [token containsString:@"profile"] ||
        [token containsString:@"logo"]) return NO;
    if ([token containsString:@"notification"] ||
        [token containsString:@"bell"] ||
        [token containsString:@"search"] ||
        [token containsString:@"cast"] ||
        [token containsString:@"airplay"] ||
        [token containsString:@"routebutton"]) return YES;
    if (![view isKindOfClass:UIButton.class] &&
        ![view isKindOfClass:UIImageView.class]) return NO;
    for (UIView *ancestor = view.superview; ancestor != nil;
         ancestor = ancestor.superview) {
        NSString *name = NSStringFromClass(ancestor.class).lowercaseString;
        if ([name containsString:@"rightnavigation"] ||
            [name containsString:@"headernavigation"] ||
            [name containsString:@"topbar"]) return YES;
    }
    return NO;
}

static UIColor *YTKACENavigationForeground(UIView *view) {
    if (YTKACEInsideRightNavigation(view)) {
        UIUserInterfaceStyle style = YTKACENavigationStyle;
        if (style == UIUserInterfaceStyleUnspecified) {
            style = view.window.traitCollection.userInterfaceStyle;
        }
        if (style == UIUserInterfaceStyleUnspecified) {
            style = view.traitCollection.userInterfaceStyle;
        }
        return style == UIUserInterfaceStyleDark
            ? UIColor.whiteColor : UIColor.blackColor;
    }
    for (UIView *current = view.superview; current != nil;
         current = current.superview) {
        UIColor *resolved = [current.backgroundColor
            resolvedColorWithTraitCollection:view.traitCollection];
        CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
        if ([resolved getRed:&red green:&green blue:&blue alpha:&alpha] &&
            alpha > 0.5) {
            CGFloat luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
            return luminance < 0.5 ? UIColor.whiteColor : UIColor.blackColor;
        }
    }
    return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
        ? UIColor.whiteColor : UIColor.blackColor;
}

static BOOL YTKACEInsideRightNavigation(UIView *view) {
    for (UIView *current = view; current != nil; current = current.superview) {
        if ([NSStringFromClass(current.class)
                isEqualToString:@"YTRightNavigationButtons"]) return YES;
    }
    return NO;
}

static void YTKACEApplyNavigationTint(UIView *view, UIColor *color) {
    view.tintColor = color;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        for (NSNumber *stateValue in @[@(UIControlStateNormal),
                                        @(UIControlStateHighlighted),
                                        @(UIControlStateSelected)]) {
            UIControlState state = (UIControlState)stateValue.unsignedIntegerValue;
            UIImage *image = [button imageForState:state];
            if (image != nil) {
                [button setImage:[image imageWithRenderingMode:
                    UIImageRenderingModeAlwaysTemplate] forState:state];
            }
        }
    } else if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image != nil) {
            imageView.image = [imageView.image imageWithRenderingMode:
                UIImageRenderingModeAlwaysTemplate];
        }
    }
    for (UIView *subview in view.subviews) {
        YTKACEApplyNavigationTint(subview, color);
    }
}

static void YTKACEApplyNavigationTree(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"YTRightNavigationButtons"]) {
        YTKACEApplyNavigationSelectors(view);
    }
    YTKACESetNavigationHidden(view, YTKACENavigationShouldHide(view));
    if (YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEIsNavigationIcon(view)) {
        YTKACEApplyNavigationTint(view, YTKACENavigationForeground(view));
    }
    for (UIView *subview in view.subviews) {
        YTKACEApplyNavigationTree(subview);
    }
}

void YTKACERefreshNavigationAppearance(void) {
    if (!YTKACEFeatureEnabled(YTKACEOLEDKey)) return;
    YTKACEApplyNavigationWindows();
    for (UIView *owner in YTKACENavigationOwners.allObjects) {
        YTKACEApplyNavigationSelectors(owner);
    }
}

static void YTKACEApplyNavigationWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden) YTKACEApplyNavigationTree(window);
        }
    }
}

static UIView *YTKACENavigationValue(id owner, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if ([owner respondsToSelector:selector]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(owner, selector);
        if ([value isKindOfClass:UIView.class]) return value;
    }
    @try {
        id value = [owner valueForKey:name];
        return [value isKindOfClass:UIView.class] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void YTKACEApplyNavigationSelectors(id owner) {
    NSDictionary<NSString *, NSArray<NSString *> *> *groups = @{
        @"kEnableHideNotificationBill": @[
            @"notificationButton", @"newNotificationButton",
            @"notificationBellButton", @"notificationBellView"
        ],
        @"kEnableHideSearch": @[@"searchButton"],
        @"kEnableHideCastButton": @[@"castButton"],
        @"kEnableHideAccount": @[@"accountButton", @"avatarButton"]
    };
    for (NSString *key in groups) {
        BOOL hidden = YTKACEFeatureEnabled(key);
        for (NSString *name in groups[key]) {
            UIView *target = YTKACENavigationValue(owner, name);
            YTKACESetNavigationHidden(target, hidden);
            if (target != nil && !hidden &&
                YTKACEFeatureEnabled(YTKACEOLEDKey)) {
                YTKACEApplyNavigationTint(
                    target, YTKACENavigationForeground(target));
            }
        }
    }
}

void YTKACEApplyRightNavigationVisibility(UIView *view) {
    if (YTKACENavigationOwners == nil) {
        YTKACENavigationOwners = [NSHashTable weakObjectsHashTable];
    }
    [YTKACENavigationOwners addObject:view];
    YTKACEApplyNavigationSelectors(view);
    YTKACEApplyNavigationTree(view);
}

static void YTKACEHeaderLogoLayout(UIView *receiver, SEL selector) {
    if (OriginalHeaderLogoLayout != NULL) {
        ((void (*)(id, SEL))OriginalHeaderLogoLayout)(receiver, selector);
    }
    YTKACESetNavigationHidden(
        receiver,
        YTKACEFeatureEnabled(@"kEnableHideYTLogo")
    );
}

static void YTKACELogoViewLayout(UIView *receiver, SEL selector) {
    if (OriginalLogoViewLayout != NULL) {
        ((void (*)(id, SEL))OriginalLogoViewLayout)(receiver, selector);
    }
    YTKACESetNavigationHidden(
        receiver,
        YTKACEFeatureEnabled(@"kEnableHideYTLogo")
    );
}

static void YTKACEQTMButtonLayout(UIView *receiver, SEL selector) {
    if (OriginalQTMButtonLayout != NULL) {
        ((void (*)(id, SEL))OriginalQTMButtonLayout)(receiver, selector);
    }
    NSString *label = receiver.accessibilityLabel.lowercaseString;
    if ([label isEqualToString:@"notifications"] ||
        [label isEqualToString:@"notification"]) {
        YTKACESetNavigationHidden(
            receiver,
            YTKACEFeatureEnabled(@"kEnableHideNotificationBill")
        );
    } else if ([label isEqualToString:@"search"] ||
               [receiver.accessibilityIdentifier
                   isEqualToString:@"id.ui.navigation.search.button"]) {
        YTKACESetNavigationHidden(
            receiver,
            YTKACEFeatureEnabled(@"kEnableHideSearch")
        );
    }
    if (YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEIsNavigationIcon(receiver)) {
        YTKACEApplyNavigationTint(receiver,
                                  YTKACENavigationForeground(receiver));
    }
}

static void YTKACEQTMButtonSetTint(UIView *receiver,
                                   SEL selector,
                                   UIColor *color) {
    if (YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEInsideRightNavigation(receiver)) {
        color = YTKACENavigationForeground(receiver);
    }
    if (OriginalQTMButtonSetTint != NULL) {
        ((void (*)(id, SEL, id))OriginalQTMButtonSetTint)(
            receiver, selector, color);
    }
}

static void YTKACENavigationImageSetTint(UIView *receiver,
                                         SEL selector,
                                         UIColor *color) {
    if (YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEInsideRightNavigation(receiver)) {
        color = YTKACENavigationForeground(receiver);
    }
    if (OriginalNavigationImageSetTint != NULL) {
        ((void (*)(id, SEL, id))OriginalNavigationImageSetTint)(
            receiver, selector, color);
    }
}

static void YTKACEQTMButtonSetImage(UIButton *receiver,
                                    SEL selector,
                                    UIImage *image,
                                    UIControlState state) {
    BOOL styled = YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEInsideRightNavigation(receiver);
    if (styled && image != nil) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (OriginalQTMButtonSetImage != NULL) {
        ((void (*)(id, SEL, id, UIControlState))OriginalQTMButtonSetImage)(
            receiver, selector, image, state);
    }
    if (styled && OriginalQTMButtonSetTint != NULL) {
        ((void (*)(id, SEL, id))OriginalQTMButtonSetTint)(
            receiver, @selector(setTintColor:),
            YTKACENavigationForeground(receiver));
    }
}

static void YTKACENavigationImageSetImage(UIImageView *receiver,
                                          SEL selector,
                                          UIImage *image) {
    BOOL styled = YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        YTKACEInsideRightNavigation(receiver);
    if (styled && image != nil) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (OriginalNavigationImageSetImage != NULL) {
        ((void (*)(id, SEL, id))OriginalNavigationImageSetImage)(
            receiver, selector, image);
    }
    if (styled && OriginalNavigationImageSetTint != NULL) {
        ((void (*)(id, SEL, id))OriginalNavigationImageSetTint)(
            receiver, @selector(setTintColor:),
            YTKACENavigationForeground(receiver));
    }
}

static void YTKACEMainWindowTraitChanged(UIWindow *receiver,
                                         SEL selector,
                                         UITraitCollection *previous) {
    if (OriginalMainWindowTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalMainWindowTraitChanged)(
            receiver, selector, previous);
    }
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified ||
        style == previous.userInterfaceStyle) return;
    YTKACENavigationStyle = style;
    if (YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        YTKACERefreshNavigationAppearance();
    }
}

static void YTKACERightNavigationTraitChanged(UIView *receiver,
                                              SEL selector,
                                              UITraitCollection *previous) {
    if (OriginalRightNavigationTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalRightNavigationTraitChanged)(
            receiver, selector, previous);
    }
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    if (style != UIUserInterfaceStyleUnspecified) {
        YTKACENavigationStyle = style;
    }
    if (YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        YTKACEApplyRightNavigationVisibility(receiver);
    }
}

static void YTKACEYTImageViewLayout(UIView *receiver, SEL selector) {
    if (OriginalYTImageViewLayout != NULL) {
        ((void (*)(id, SEL))OriginalYTImageViewLayout)(receiver, selector);
    }
    NSString *label = receiver.accessibilityLabel;
    if ([receiver.accessibilityIdentifier isEqualToString:@"id.youtube.logo"] ||
        (label.length != 0 &&
         [label caseInsensitiveCompare:@"YouTube"] == NSOrderedSame)) {
        YTKACESetNavigationHidden(
            receiver,
            YTKACEFeatureEnabled(@"kEnableHideYTLogo")
        );
    }
}

void YTKACEInstallNavigationVisibilityHooks(void) {
    YTKACEInstallNavigationMethodHooks();
    YTKACEInstallInstanceHook(@"YTHeaderLogoView",
                              @"layoutSubviews",
                              (IMP)YTKACEHeaderLogoLayout,
                              &OriginalHeaderLogoLayout);
    YTKACEInstallInstanceHook(@"YTLogoView",
                              @"layoutSubviews",
                              (IMP)YTKACELogoViewLayout,
                              &OriginalLogoViewLayout);
    YTKACEInstallInstanceHook(@"YTQTMButton",
                              @"layoutSubviews",
                              (IMP)YTKACEQTMButtonLayout,
                              &OriginalQTMButtonLayout);
    YTKACEInstallInstanceHook(@"YTQTMButton",
                              @"setTintColor:",
                              (IMP)YTKACEQTMButtonSetTint,
                              &OriginalQTMButtonSetTint);
    YTKACEInstallInstanceHook(@"YTQTMButton",
                              @"setImage:forState:",
                              (IMP)YTKACEQTMButtonSetImage,
                              &OriginalQTMButtonSetImage);
    YTKACEInstallInstanceHook(@"UIImageView",
                              @"setTintColor:",
                              (IMP)YTKACENavigationImageSetTint,
                              &OriginalNavigationImageSetTint);
    YTKACEInstallInstanceHook(@"UIImageView",
                              @"setImage:",
                              (IMP)YTKACENavigationImageSetImage,
                              &OriginalNavigationImageSetImage);
    YTKACEInstallInstanceHook(@"YTImageView",
                              @"layoutSubviews",
                              (IMP)YTKACEYTImageViewLayout,
                              &OriginalYTImageViewLayout);
    YTKACEInstallInstanceHook(@"YTMainWindow",
                              @"traitCollectionDidChange:",
                              (IMP)YTKACEMainWindowTraitChanged,
                              &OriginalMainWindowTraitChanged);
    YTKACEInstallInstanceHook(@"YTRightNavigationButtons",
                              @"traitCollectionDidChange:",
                              (IMP)YTKACERightNavigationTraitChanged,
                              &OriginalRightNavigationTraitChanged);
    YTKACEApplyNavigationWindows();
    if (!YTKACENavigationObserverInstalled) {
        YTKACENavigationObserverInstalled = YES;
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *notification) {
                NSString *version = NSBundle.mainBundle
                    .infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
                NSString *cacheKey = [@"YTKACENavigationHookTargets."
                    stringByAppendingString:version];
                if ([NSUserDefaults.standardUserDefaults
                        arrayForKey:cacheKey].count == 0) {
                    static dispatch_once_t discoveryToken;
                    dispatch_once(&discoveryToken, ^{
                        dispatch_async(
                            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                                YTKACEDiscoverNavigationMethodHooks();
                            }
                        );
                    });
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        YTKACEApplyNavigationWindows();
                    });
            }];
    }
}
