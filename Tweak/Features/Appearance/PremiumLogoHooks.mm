#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>

static IMP OriginalImageNamedBundleTraits;
static IMP OriginalImageNamedBundle;

static NSBundle *YTKACEInnertubeBundle(void) {
    NSBundle *main = NSBundle.mainBundle;
    NSArray<NSString *> *paths = @[
        [main.resourcePath stringByAppendingPathComponent:@"Innertube_Resources.bundle"],
        [main.resourcePath stringByAppendingPathComponent:@"Frameworks/Module_Framework.framework/Innertube_Resources.bundle"]
    ];
    for (NSString *path in paths) {
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle != nil) {
            return bundle;
        }
    }
    return nil;
}

static NSString *YTKACEPremiumName(NSString *name,
                                    UITraitCollection *traits) {
    BOOL darkName = [name.lowercaseString containsString:@"dark"];
    BOOL darkMode = NO;
    if (@available(iOS 13.0, *)) {
        darkMode = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return darkName || darkMode
        ? @"youtube_premium_logo_white"
        : @"youtube_premium_logo";
}

static BOOL YTKACEShouldReplaceLogo(NSString *name) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.PremiumLogo") ||
        ![name isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *lower = name.lowercaseString;
    return [lower containsString:@"youtube_logo"] &&
        ![lower containsString:@"premium"];
}

static UIImage *YTKACEImageNamedBundleTraits(id receiver,
                                              SEL selector,
                                              NSString *name,
                                              NSBundle *bundle,
                                              UITraitCollection *traits) {
    if (OriginalImageNamedBundleTraits == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *, UITraitCollection *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *, UITraitCollection *))
            OriginalImageNamedBundleTraits;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, traits),
            resources,
            traits
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle, traits);
}

static UIImage *YTKACEImageNamedBundle(id receiver,
                                       SEL selector,
                                       NSString *name,
                                       NSBundle *bundle) {
    if (OriginalImageNamedBundle == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *))OriginalImageNamedBundle;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, UIScreen.mainScreen.traitCollection),
            resources
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle);
}

void YTKACEInstallPremiumLogoHooks(void) {
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:compatibleWithTraitCollection:",
                           (IMP)YTKACEImageNamedBundleTraits,
                           &OriginalImageNamedBundleTraits);
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:",
                           (IMP)YTKACEImageNamedBundle,
                           &OriginalImageNamedBundle);
}
