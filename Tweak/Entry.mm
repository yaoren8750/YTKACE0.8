#import "YTKACE.h"
#import "Features/Downloads/DownloadLog.h"
#import "Features/SponsorBlock/DeArrow.h"
#import "Runtime/Preferences.h"

#import <UIKit/UIKit.h>

#ifndef YTKACE_COMBINED_SABR
#define YTKACE_COMBINED_SABR 0
#endif

NSString * const YTKACEVersion = @"0.7.2";

static void YTKACEInstallModules(void) {
    YTKACEInstallSideloadCompatibilityHooks();
    YTKACEInstallCastCompatibilityHooks();
    YTKACEInstallAdsHooks();
    YTKACEInstallSponsorBlockHooks();
    YTKACEInstallDeArrow();
    YTKACEInstallOLEDHooks();
    YTKACEInstallStartupHooks();
    YTKACEInstallPremiumLogoHooks();
    YTKACEInstallBackgroundPlaybackHooks();
    YTKACEInstallSpeedHooks();
    YTKACEInstallLoopHooks();
    YTKACEInstallPiPHooks();
    YTKACEInstallDownloadHooks();
    YTKACEInstallGlobalDownloadMiniPlayer();
    YTKACEInstallDoubleTapHooks();
    YTKACEInstallFixPlaybackHooks();
    YTKACEInstallProgressBarHooks();
    YTKACEInstallStreamingHooks();
    YTKACEInstallShortsHooks();
    YTKACEInstallTabBarHooks();
    YTKACEInstallNavigationBehaviorHooks();
    YTKACEInstallPlayerGestureHooks();
    YTKACEInstallOverlayVisibilityHooks();
    YTKACEInstallContentVisibilityHooks();
    YTKACEInstallNavigationVisibilityHooks();
    YTKACEInstallMiscellaneousHooks();
    YTKACEInstallCopyCommentHooks();
    YTKACEInstallProfilePictureHooks();
    YTKACEInstallSettingsEntryHooks();
    YTKACEInstallNativeSettingsHooks();
}

__attribute__((constructor))
static void YTKACEEntryPoint(void) {
    @autoreleasepool {
        YTKACEClearDownloadLog();
        YTKACERegisterDefaults();
        YTKACEScheduleFirstLaunch();
        YTKACEInstallModules();
    }
}
