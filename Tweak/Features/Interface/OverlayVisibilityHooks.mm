#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"
#import "../../UI/OverlayButtonHost.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static const void *YTKACEOverlayHiddenAssociation = &YTKACEOverlayHiddenAssociation;
static const void *YTKACEOverlayForcedAssociation = &YTKACEOverlayForcedAssociation;
static const void *YTKACEOverlayEnabledAssociation = &YTKACEOverlayEnabledAssociation;
static const void *YTKACEOverlayTransformAssociation = &YTKACEOverlayTransformAssociation;
static const void *YTKACEDoubleTapAssociation = &YTKACEDoubleTapAssociation;
static IMP OriginalVideoOverlayLayout;

static BOOL YTKACEOverlayPreference(NSString *primary, NSString *legacy) {
    return YTKACEFeatureEnabled(primary) ||
        (legacy.length != 0 && YTKACEFeatureEnabled(legacy));
}

static NSString *YTKACEOverlayToken(UIView *view) {
    return [[NSString stringWithFormat:@"%@ %@ %@",
             NSStringFromClass(view.class),
             view.accessibilityIdentifier ?: @"",
             view.accessibilityLabel ?: @""] lowercaseString];
}

static BOOL YTKACEOverlayTokenMatches(NSString *token,
                                      NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([token containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static void YTKACESetOverlayHidden(UIView *view, BOOL hidden) {
    if (view == nil ||
        [view.accessibilityIdentifier hasPrefix:@"YTKACE"]) {
        return;
    }

    NSNumber *baseline = objc_getAssociatedObject(
        view,
        YTKACEOverlayHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(view,
                                     YTKACEOverlayHiddenAssociation,
                                     @(view.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        view.hidden = baseline.boolValue;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view,
                                 YTKACEOverlayHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL YTKACEIsDarkOverlayView(UIView *view) {
    UIView *root = view.superview;
    if (view.class != UIView.class ||
        ![NSStringFromClass(root.class)
            isEqualToString:@"YTMainAppVideoPlayerOverlayView"] ||
        fabs(CGRectGetWidth(view.bounds) - CGRectGetWidth(root.bounds)) >= 2.0 ||
        fabs(CGRectGetHeight(view.bounds) - CGRectGetHeight(root.bounds)) >= 2.0) {
        return NO;
    }
    NSUInteger index = [root.subviews indexOfObjectIdenticalTo:view];
    if (index == NSNotFound || index + 1 >= root.subviews.count) return NO;
    return [NSStringFromClass(root.subviews[index + 1].class)
        isEqualToString:@"YTMainAppVideoOverlayAccessibilityGlassContainerView"];
}

static BOOL YTKACEOverlayShouldHide(UIView *view) {
    NSString *token = YTKACEOverlayToken(view);
    if (YTKACEOverlayPreference(@"kEnableHideDarkOverlay",
                                @"kEnableHideDarkOverlayBackground") &&
        YTKACEIsDarkOverlayView(view)) {
        return YES;
    }
    if (YTKACEOverlayPreference(@"kEnableHideQuickActions",
                                @"kEnableHideOverlayQuickAction") &&
        YTKACEOverlayTokenMatches(token, @[
            @"quickaction", @"quick_action", @"actionbar", @"action_bar"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableDisableContinueWatching") &&
        YTKACEOverlayTokenMatches(token, @[
            @"continuewatching", @"continue_watching"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideRelatedVideos") &&
        YTKACEOverlayTokenMatches(token, @[
            @"relatedvideo", @"related_video", @"morevideos", @"more_videos"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideAutoplayToggle") &&
        YTKACEOverlayTokenMatches(token, @[@"autoplay", @"autonav"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCaptionsToggle") &&
        YTKACEOverlayTokenMatches(token, @[@"caption", @"subtitle", @"closedcaption"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCastButtonOverlay") &&
        YTKACEOverlayTokenMatches(token, @[@"cast", @"airplay", @"routebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideWaterMark") &&
        YTKACEOverlayTokenMatches(token, @[@"watermark", @"branding"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideInfoCard") &&
        YTKACEOverlayTokenMatches(token, @[@"infocard", @"info_card", @"cardsbutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideEndScreenVideos") &&
        YTKACEOverlayTokenMatches(token, @[@"endscreen", @"end_screen"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHidePlayPuase") &&
        YTKACEOverlayTokenMatches(token, @[@"playpause", @"play_pause"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideMoreGearIcon") &&
        YTKACEOverlayTokenMatches(token, @[@"overflowbutton", @"settingsbutton", @"morebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHidePreviousNextButton") &&
        YTKACEOverlayTokenMatches(token, @[@"previousbutton", @"nextbutton"])) {
        return YES;
    }
    return NO;
}

static void YTKACESetOverlayForcedVisible(UIView *view, BOOL forced) {
    NSDictionary *baseline = objc_getAssociatedObject(
        view,
        YTKACEOverlayForcedAssociation
    );
    if (forced) {
        if (baseline == nil) {
            baseline = @{@"hidden": @(view.hidden), @"alpha": @(view.alpha)};
            objc_setAssociatedObject(view,
                                     YTKACEOverlayForcedAssociation,
                                     baseline,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = NO;
        view.alpha = 1.0;
    } else if (baseline != nil) {
        view.hidden = [baseline[@"hidden"] boolValue];
        view.alpha = [baseline[@"alpha"] doubleValue];
        objc_setAssociatedObject(view,
                                 YTKACEOverlayForcedAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEApplyOverlayBehavior(UIView *view) {
    NSString *token = YTKACEOverlayToken(view);
    BOOL playPause = YTKACEOverlayTokenMatches(token, @[
        @"playpause", @"play_pause", @"playbackbutton"
    ]);
    BOOL progress = YTKACEOverlayTokenMatches(token, @[
        @"progress", @"scrubber", @"playerbar", @"player_bar"
    ]);
    BOOL control = [view isKindOfClass:UIControl.class] ||
        YTKACEOverlayTokenMatches(token, @[@"control", @"button"]);
    BOOL force = (YTKACEOverlayPreference(@"kEnableShowOverlaySmart",
                                          @"kEnableAlwaysShowPlayPause") && playPause) ||
        (YTKACEOverlayPreference(@"kEnableShowMediaController",
                                 @"kEnableAlwaysShowControls") && control) ||
        (YTKACEFeatureEnabled(@"kEnableShowProgressBar") && progress);
    YTKACESetOverlayForcedVisible(view, force);

    BOOL previousNext = YTKACEOverlayTokenMatches(token, @[
        @"previousbutton", @"nextbutton", @"previous_button", @"next_button"
    ]);
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *controlView = (UIControl *)view;
        NSNumber *baseline = objc_getAssociatedObject(
            view,
            YTKACEOverlayEnabledAssociation
        );
        if (YTKACEOverlayPreference(@"kEnableDisablePreviousNextButton",
                                    @"kEnableDisablePreviousNext") && previousNext) {
            if (baseline == nil) {
                objc_setAssociatedObject(view,
                                         YTKACEOverlayEnabledAssociation,
                                         @(controlView.enabled),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            controlView.enabled = NO;
            controlView.alpha = 0.35;
        } else if (baseline != nil) {
            controlView.enabled = baseline.boolValue;
            controlView.alpha = 1.0;
            objc_setAssociatedObject(view,
                                     YTKACEOverlayEnabledAssociation,
                                     nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    NSValue *transform = objc_getAssociatedObject(
        view,
        YTKACEOverlayTransformAssociation
    );
    if (YTKACEOverlayPreference(@"kEnablePreviousNextButtonPadding",
                                @"kEnableCompactPreviousNext") && previousNext) {
        if (transform == nil) {
            objc_setAssociatedObject(view,
                                     YTKACEOverlayTransformAssociation,
                                     [NSValue valueWithCGAffineTransform:view.transform],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.transform = CGAffineTransformScale(
            transform != nil ? transform.CGAffineTransformValue : view.transform,
            0.78,
            0.78
        );
    } else if (transform != nil) {
        view.transform = transform.CGAffineTransformValue;
        objc_setAssociatedObject(view,
                                 YTKACEOverlayTransformAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] ||
            ((UITapGestureRecognizer *)recognizer).numberOfTapsRequired < 2) {
            continue;
        }
        NSNumber *baseline = objc_getAssociatedObject(
            recognizer,
            YTKACEDoubleTapAssociation
        );
        if (YTKACEFeatureEnabled(@"kEnableDisableDoubleTap")) {
            if (baseline == nil) {
                objc_setAssociatedObject(recognizer,
                                         YTKACEDoubleTapAssociation,
                                         @(recognizer.enabled),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            recognizer.enabled = NO;
        } else if (baseline != nil) {
            recognizer.enabled = baseline.boolValue;
            objc_setAssociatedObject(recognizer,
                                     YTKACEDoubleTapAssociation,
                                     nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void YTKACEApplyOverlayTree(UIView *view) {
    YTKACEApplyOverlayBehavior(view);
    YTKACESetOverlayHidden(view, YTKACEOverlayShouldHide(view));
    for (UIView *subview in view.subviews) {
        YTKACEApplyOverlayTree(subview);
    }
}

static void YTKACEApplyOverlaySelectors(id overlay) {
    NSDictionary<NSString *, NSString *> *selectors = @{
        @"autoplaySwitch": @"kEnableHideAutoplayToggle",
        @"autoplayButton": @"kEnableHideAutoplayToggle",
        @"captionsButton": @"kEnableHideCaptionsToggle",
        @"closedCaptionsButton": @"kEnableHideCaptionsToggle",
        @"castButton": @"kEnableHideCastButtonOverlay",
        @"infoCardButton": @"kEnableHideInfoCard",
        @"watermarkView": @"kEnableHideWaterMark",
        @"endscreenView": @"kEnableHideEndScreenVideos",
        @"playPauseButton": @"kEnableHidePlayPuase",
        @"previousButton": @"kEnableHidePreviousNextButton",
        @"nextButton": @"kEnableHidePreviousNextButton",
        @"overflowButton": @"kEnableHideMoreGearIcon",
        @"settingsButton": @"kEnableHideMoreGearIcon"
    };
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if (![overlay respondsToSelector:selector]) {
            continue;
        }
        id value = ((id (*)(id, SEL))objc_msgSend)(overlay, selector);
        if ([value isKindOfClass:UIView.class]) {
            YTKACESetOverlayHidden(value,
                                   YTKACEFeatureEnabled(selectors[name]));
        }
    }
}

static void YTKACEVideoOverlayLayout(UIView *receiver, SEL selector) {
    if (OriginalVideoOverlayLayout != NULL) {
        ((void (*)(id, SEL))OriginalVideoOverlayLayout)(receiver, selector);
    }
    YTKACEApplyOverlaySelectors(receiver);
    if (YTKACEOverlayPreference(@"kEnableHideDarkOverlay",
                                @"kEnableHideDarkOverlayBackground")) {
        for (UIView *subview in receiver.subviews) {
            if (YTKACEIsDarkOverlayView(subview)) {
                YTKACESetOverlayHidden(subview, YES);
            }
        }
    }
}

void YTKACEInstallOverlayVisibilityHooks(void) {
    YTKACERegisterOverlayConfigurator(@"visibility", ^(UIView *overlay,
                                                        UIStackView *stack) {
        for (UIView *subview in overlay.subviews) {
            if (subview != stack) {
                YTKACEApplyOverlayTree(subview);
            }
        }
        YTKACEApplyOverlaySelectors(overlay);
    });
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayView",
                              @"layoutSubviews",
                              (IMP)YTKACEVideoOverlayLayout,
                              &OriginalVideoOverlayLayout);
}
