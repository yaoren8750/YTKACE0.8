#import <Foundation/Foundation.h>

@class UIView;
@class CALayer;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const YTKACEVersion;

void YTKACEInstallAdsHooks(void);
void YTKACEInstallSponsorBlockHooks(void);
void YTKACEInstallDownloadHooks(void);
void YTKACEInstallGlobalDownloadMiniPlayer(void);
void YTKACEInstallOLEDHooks(void);
void YTKACEInstallStartupHooks(void);
void YTKACEInstallPremiumLogoHooks(void);
void YTKACEInstallBackgroundPlaybackHooks(void);
void YTKACEInstallPiPHooks(void);
void YTKACEInstallSpeedHooks(void);
void YTKACEInstallLoopHooks(void);
void YTKACEInstallDoubleTapHooks(void);
void YTKACEInstallFixPlaybackHooks(void);
void YTKACEInstallProgressBarHooks(void);
void YTKACEApplyProgressStyleToBar(UIView *bar);
void YTKACEStyleProgressLayer(CALayer *layer, CGFloat trackWidth);
void YTKACEInstallStreamingHooks(void);
void YTKACEInstallShortsHooks(void);
void YTKACEInstallSideloadCompatibilityHooks(void);
void YTKACEInstallCastCompatibilityHooks(void);
void YTKACEStartCastDiscovery(void);
void YTKACEInstallTabBarHooks(void);
void YTKACEInstallNavigationBehaviorHooks(void);
void YTKACEInstallPlayerGestureHooks(void);
void YTKACEInstallSettingsEntryHooks(void);
void YTKACEInstallNativeSettingsHooks(void);
void YTKACEInstallOverlayVisibilityHooks(void);
void YTKACEInstallContentVisibilityHooks(void);
void YTKACEInstallNavigationVisibilityHooks(void);
void YTKACEInstallMiscellaneousHooks(void);
void YTKACEInstallCopyCommentHooks(void);
void YTKACEInstallProfilePictureHooks(void);
void YTKACEScheduleFirstLaunch(void);

NS_ASSUME_NONNULL_END
