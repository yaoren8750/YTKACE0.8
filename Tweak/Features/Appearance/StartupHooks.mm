#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSMutableDictionary<NSString *, NSValue *> *YTKACEStartupOriginals;

static IMP YTKACEStartupOriginal(id receiver, SEL selector) {
    for (Class cls = [receiver class]; cls != Nil; cls = class_getSuperclass(cls)) {
        NSString *key = [NSString stringWithFormat:@"%@|%@",
                         NSStringFromClass(cls),
                         NSStringFromSelector(selector)];
        NSValue *value = YTKACEStartupOriginals[key];
        if (value == nil) continue;
        IMP implementation = NULL;
        [value getValue:&implementation];
        return implementation;
    }
    return NULL;
}

static void YTKACEStartupBlacken(UIView *view) {
    if (view == nil) return;
    UIColor *background = view.backgroundColor;
    if (background != nil && CGColorGetAlpha(background.CGColor) > 0.01) {
        view.backgroundColor = UIColor.blackColor;
    }
    for (UIView *child in view.subviews) {
        YTKACEStartupBlacken(child);
    }
}

static void YTKACEStartupViewDidLoad(UIViewController *receiver,
                                     SEL selector) {
    IMP original = YTKACEStartupOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    if (YTKACEOLEDActive(receiver.traitCollection)) {
        receiver.view.backgroundColor = UIColor.blackColor;
        YTKACEStartupBlacken(receiver.view);
        receiver.view.window.backgroundColor = UIColor.blackColor;
    }
}

static void YTKACEFinishStartup(UIViewController *receiver) {
    SEL delegateSelector = NSSelectorFromString(@"delegate");
    id delegate = [receiver respondsToSelector:delegateSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, delegateSelector)
        : nil;
    SEL completionSelector = NSSelectorFromString(@"startupAnimationDidComplete");
    if ([delegate respondsToSelector:completionSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(delegate, completionSelector);
        return;
    }
    SEL forceSelector =
        NSSelectorFromString(@"forceDismissStartupAnimationAnimated:");
    if ([delegate respondsToSelector:forceSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(delegate, forceSelector, NO);
        return;
    }
    [receiver dismissViewControllerAnimated:NO completion:nil];
}

static void YTKACEStartupViewDidAppear(UIViewController *receiver,
                                       SEL selector,
                                       BOOL animated) {
    IMP original = YTKACEStartupOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, BOOL))original)(receiver, selector, animated);
    }
    if (YTKACEOLEDActive(receiver.traitCollection)) {
        receiver.view.backgroundColor = UIColor.blackColor;
        YTKACEStartupBlacken(receiver.view);
        receiver.view.window.backgroundColor = UIColor.blackColor;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Appearance.LaunchAnimationDisabled")) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEFinishStartup(receiver);
        });
    }
}

static void YTKACEInstallStartupHook(NSString *className,
                                     NSString *selectorName,
                                     IMP replacement) {
    IMP original = NULL;
    if (!YTKACEInstallInstanceHook(className, selectorName,
                                   replacement, &original) ||
        original == NULL || original == replacement) {
        return;
    }
    YTKACEStartupOriginals[
        [NSString stringWithFormat:@"%@|%@", className, selectorName]
    ] = [NSValue value:&original withObjCType:@encode(IMP)];
}

void YTKACEInstallStartupHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACEStartupOriginals = [NSMutableDictionary dictionary];
    });

    for (NSString *className in @[
        @"YTStartupAnimationViewController",
        @"YTRiveStartupAnimationViewController"
    ]) {
        YTKACEInstallStartupHook(className, @"viewDidLoad",
                                 (IMP)YTKACEStartupViewDidLoad);
        YTKACEInstallStartupHook(className, @"viewDidAppear:",
                                 (IMP)YTKACEStartupViewDidAppear);
    }
}
