#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <Foundation/Foundation.h>

static IMP OriginalMealbarPromo;
static IMP OriginalPromosheet;
static IMP OriginalUpgradeDialog;
static IMP OriginalOldUpgradeDialog;
static IMP OriginalShouldShowUpgrade;
static IMP OriginalShouldShowUpgradeDialog;
static IMP OriginalYouTherePrompt;
static IMP OriginalThrottleInterstitial;

static BOOL YTKACEHidePromos(void) {
    return YTKACEFeatureEnabled(@"kEnableNoPremiumpopup");
}

static void YTKACEMealbarPromo(id receiver, SEL selector, id event) {
    if (!YTKACEHidePromos() && OriginalMealbarPromo != NULL) {
        ((void (*)(id, SEL, id))OriginalMealbarPromo)(receiver, selector, event);
    }
}

static void YTKACEPromosheet(id receiver, SEL selector, id event) {
    if (!YTKACEHidePromos() && OriginalPromosheet != NULL) {
        ((void (*)(id, SEL, id))OriginalPromosheet)(receiver, selector, event);
    }
}

static void YTKACEUpgradeDialog(id receiver, SEL selector) {
    if (!YTKACEHidePromos() && OriginalUpgradeDialog != NULL) {
        ((void (*)(id, SEL))OriginalUpgradeDialog)(receiver, selector);
    }
}

static void YTKACEOldUpgradeDialog(id receiver, SEL selector) {
    if (!YTKACEHidePromos() && OriginalOldUpgradeDialog != NULL) {
        ((void (*)(id, SEL))OriginalOldUpgradeDialog)(receiver, selector);
    }
}

static BOOL YTKACEShouldShowUpgrade(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalShouldShowUpgrade != NULL &&
         ((BOOL (*)(id, SEL))OriginalShouldShowUpgrade)(receiver, selector));
}

static BOOL YTKACEShouldShowUpgradeDialog(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalShouldShowUpgradeDialog != NULL &&
         ((BOOL (*)(id, SEL))OriginalShouldShowUpgradeDialog)(receiver, selector));
}

static BOOL YTKACEShouldShowYouThere(id receiver, SEL selector) {
    return YTKACEHidePromos() ? NO :
        (OriginalYouTherePrompt != NULL &&
         ((BOOL (*)(id, SEL))OriginalYouTherePrompt)(receiver, selector));
}

static BOOL YTKACEShouldThrottleInterstitial(id receiver, SEL selector) {
    return YTKACEHidePromos() ? YES :
        (OriginalThrottleInterstitial != NULL &&
         ((BOOL (*)(id, SEL))OriginalThrottleInterstitial)(receiver, selector));
}

void YTKACEInstallPromoHooks(void) {
    YTKACEInstallInstanceHook(@"YTMealbarPromoController",
                              @"showMealbarPromoWithEvent:",
                              (IMP)YTKACEMealbarPromo,
                              &OriginalMealbarPromo);
    YTKACEInstallInstanceHook(@"YTPromosheetController",
                              @"presentPromosheetWithEvent:",
                              (IMP)YTKACEPromosheet,
                              &OriginalPromosheet);
    YTKACEInstallInstanceHook(@"YTUpgradeController", @"showUpgradeDialog",
                              (IMP)YTKACEUpgradeDialog,
                              &OriginalUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTUpgradeController", @"showOldUpgradeDialog",
                              (IMP)YTKACEOldUpgradeDialog,
                              &OriginalOldUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTGlobalConfig", @"shouldShowUpgrade",
                              (IMP)YTKACEShouldShowUpgrade,
                              &OriginalShouldShowUpgrade);
    YTKACEInstallInstanceHook(@"YTGlobalConfig", @"shouldShowUpgradeDialog",
                              (IMP)YTKACEShouldShowUpgradeDialog,
                              &OriginalShouldShowUpgradeDialog);
    YTKACEInstallInstanceHook(@"YTYouThereControllerImpl",
                              @"shouldShowYouTherePrompt",
                              (IMP)YTKACEShouldShowYouThere,
                              &OriginalYouTherePrompt);
    YTKACEInstallInstanceHook(@"YTIShowFullscreenInterstitialCommand",
                              @"shouldThrottleInterstitial",
                              (IMP)YTKACEShouldThrottleInterstitial,
                              &OriginalThrottleInterstitial);
}
