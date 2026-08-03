#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/OverlayButtonHost.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static const void *YTKACEOverlayHiddenAssociation = &YTKACEOverlayHiddenAssociation;
static const void *YTKACEOverlayForcedAssociation = &YTKACEOverlayForcedAssociation;
static const void *YTKACEOverlayEnabledAssociation = &YTKACEOverlayEnabledAssociation;
static const void *YTKACEOverlayTransformAssociation = &YTKACEOverlayTransformAssociation;
static const void *YTKACEDoubleTapAssociation = &YTKACEDoubleTapAssociation;
static const void *YTKACEPrevNextParentAssociation = &YTKACEPrevNextParentAssociation;
static IMP OriginalVideoOverlayLayout;
static IMP OriginalForceHidePreviousNext;
static IMP OriginalPreviousButtonShouldHide;
static IMP OriginalNextButtonShouldHide;
static IMP OriginalRemoveNextPaddle;
static IMP OriginalRemovePreviousPaddle;

static BOOL YTKACEOverlayPreference(NSString *key) {
    return YTKACEFeatureEnabled(key);
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

static NSArray<NSString *> *YTKACEPreviousNextTokens(void) {
    return @[
        @"id.player.previous.button", @"id.player.next.button",
        @"previous.button", @"next.button",
        @"previousbutton", @"nextbutton", @"previous_button", @"next_button",
        @"previous button", @"next button", @"skipprevious", @"skipnext",
        @"replaynextbutton", @"replay_next_button"
    ];
}

static void YTKACESetPreviousNextContainerEnabled(UIView *view, BOOL enabled) {
    if (view == nil) return;
    NSDictionary *baseline = objc_getAssociatedObject(view,
                                                       YTKACEPrevNextParentAssociation);
    if (!enabled) {
        if (baseline == nil) {
            baseline = @{@"interaction": @(view.userInteractionEnabled),
                         @"alpha": @(view.alpha)};
            objc_setAssociatedObject(view, YTKACEPrevNextParentAssociation,
                                     baseline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.userInteractionEnabled = NO;
        view.alpha = 0.35;
    } else if (baseline != nil) {
        view.userInteractionEnabled = [baseline[@"interaction"] boolValue];
        view.alpha = [baseline[@"alpha"] doubleValue];
        objc_setAssociatedObject(view, YTKACEPrevNextParentAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACESetControlTreeEnabled(UIView *view, BOOL enabled) {
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        control.enabled = enabled;
        control.userInteractionEnabled = enabled;
        control.alpha = enabled ? 1.0 : 0.35;
    }
    for (UIView *subview in view.subviews) {
        YTKACESetControlTreeEnabled(subview, enabled);
    }
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
    if (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.DimmingRemoved") &&
        YTKACEIsDarkOverlayView(view)) {
        return YES;
    }
    if (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.QuickActionsHidden") &&
        YTKACEOverlayTokenMatches(token, @[
            @"quickaction", @"quick_action", @"actionbar", @"action_bar"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ContinueWatchingDisabled") &&
        YTKACEOverlayTokenMatches(token, @[
            @"continuewatching", @"continue_watching"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.RelatedVideosHidden") &&
        YTKACEOverlayTokenMatches(token, @[
            @"relatedvideo", @"related_video", @"morevideos", @"more_videos"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.AutoplayHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"autoplay", @"autonav"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.CaptionsButtonHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"caption", @"subtitle", @"closedcaption"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.CastHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"cast", @"airplay", @"routebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.WatermarkHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"watermark", @"branding"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.InfoCardsHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"infocard", @"info_card", @"cardsbutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.EndScreenHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"endscreen", @"end_screen"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PlayPauseHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"playpause", @"play_pause"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.MoreButtonHidden") &&
        YTKACEOverlayTokenMatches(token, @[@"overflowbutton", @"settingsbutton", @"morebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden") &&
        YTKACEOverlayTokenMatches(token, YTKACEPreviousNextTokens())) {
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
    BOOL force = (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.AlwaysShowPlayPause") && playPause) ||
        (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.AlwaysShowControls") && control) ||
        (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProgressAlwaysVisible") && progress);
    YTKACESetOverlayForcedVisible(view, force);

    BOOL previousNext = YTKACEOverlayTokenMatches(
        token, YTKACEPreviousNextTokens());
    BOOL disablePreviousNext = YTKACEOverlayPreference(
        @"YTKACE.Preference.Overlay.PreviousNextDisabled");
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *controlView = (UIControl *)view;
        NSNumber *baseline = objc_getAssociatedObject(
            view,
            YTKACEOverlayEnabledAssociation
        );
        if (disablePreviousNext && previousNext) {
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
    if (previousNext) {
        UIView *container = view.superview;
        if ([NSStringFromClass(container.class)
                containsString:@"TransportControlsButtonView"]) {
            YTKACESetPreviousNextContainerEnabled(container,
                                                   !disablePreviousNext);
        }
    }

    NSValue *transform = objc_getAssociatedObject(
        view,
        YTKACEOverlayTransformAssociation
    );
    if (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.CompactPreviousNext") && previousNext) {
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
        if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.DoubleTapDisabled")) {
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
        @"autoplaySwitch": @"YTKACE.Preference.Overlay.AutoplayHidden",
        @"autoplayButton": @"YTKACE.Preference.Overlay.AutoplayHidden",
        @"captionsButton": @"YTKACE.Preference.Overlay.CaptionsButtonHidden",
        @"closedCaptionsButton": @"YTKACE.Preference.Overlay.CaptionsButtonHidden",
        @"castButton": @"YTKACE.Preference.Overlay.CastHidden",
        @"infoCardButton": @"YTKACE.Preference.Overlay.InfoCardsHidden",
        @"watermarkView": @"YTKACE.Preference.Overlay.WatermarkHidden",
        @"endscreenView": @"YTKACE.Preference.Overlay.EndScreenHidden",
        @"playPauseButton": @"YTKACE.Preference.Overlay.PlayPauseHidden",
        @"previousButton": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"nextButton": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"previousButtonView": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"nextButtonView": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"minimizedPanelPreviousButton": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"minimizedPanelNextButton": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"replayNextButton": @"YTKACE.Preference.Overlay.PreviousNextHidden",
        @"overflowButton": @"YTKACE.Preference.Overlay.MoreButtonHidden",
        @"settingsButton": @"YTKACE.Preference.Overlay.MoreButtonHidden"
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
            if ([name.lowercaseString containsString:@"previous"] ||
                [name.lowercaseString containsString:@"next"]) {
                BOOL disabled = YTKACEOverlayPreference(
                    @"YTKACE.Preference.Overlay.PreviousNextDisabled");
                YTKACESetControlTreeEnabled(value, !disabled);
            }
        }
    }
}

static void YTKACEVideoOverlayLayout(UIView *receiver, SEL selector) {
    if (OriginalVideoOverlayLayout != NULL) {
        ((void (*)(id, SEL))OriginalVideoOverlayLayout)(receiver, selector);
    }
    YTKACEApplyOverlaySelectors(receiver);
    if (YTKACEOverlayPreference(@"YTKACE.Preference.Overlay.DimmingRemoved")) {
        for (UIView *subview in receiver.subviews) {
            if (YTKACEIsDarkOverlayView(subview)) {
                YTKACESetOverlayHidden(subview, YES);
            }
        }
    }
}

static BOOL YTKACEForceHidePreviousNext(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden")) return YES;
    return OriginalForceHidePreviousNext == NULL
        ? NO
        : ((BOOL (*)(id, SEL))OriginalForceHidePreviousNext)(
            receiver, selector);
}

static BOOL YTKACEPreviousButtonShouldHide(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden")) return YES;
    return OriginalPreviousButtonShouldHide == NULL
        ? NO
        : ((BOOL (*)(id, SEL))OriginalPreviousButtonShouldHide)(
            receiver, selector);
}

static BOOL YTKACENextButtonShouldHide(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden")) return YES;
    return OriginalNextButtonShouldHide == NULL
        ? NO
        : ((BOOL (*)(id, SEL))OriginalNextButtonShouldHide)(
            receiver, selector);
}

static BOOL YTKACERemoveNextPaddle(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden")) return YES;
    return OriginalRemoveNextPaddle != NULL &&
        ((BOOL (*)(id, SEL))OriginalRemoveNextPaddle)(receiver, selector);
}

static BOOL YTKACERemovePreviousPaddle(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PreviousNextHidden")) return YES;
    return OriginalRemovePreviousPaddle != NULL &&
        ((BOOL (*)(id, SEL))OriginalRemovePreviousPaddle)(receiver, selector);
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
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"forceHidePreviousAndNextButtons",
                              (IMP)YTKACEForceHidePreviousNext,
                              &OriginalForceHidePreviousNext);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"previousButtonShouldHide",
                              (IMP)YTKACEPreviousButtonShouldHide,
                              &OriginalPreviousButtonShouldHide);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"nextButtonShouldHide",
                              (IMP)YTKACENextButtonShouldHide,
                              &OriginalNextButtonShouldHide);
    YTKACEInstallInstanceHook(@"YTColdConfig",
                              @"removeNextPaddleForSingletonVideos",
                              (IMP)YTKACERemoveNextPaddle,
                              &OriginalRemoveNextPaddle);
    YTKACEInstallInstanceHook(@"YTColdConfig",
                              @"removePreviousPaddleForSingletonVideos",
                              (IMP)YTKACERemovePreviousPaddle,
                              &OriginalRemovePreviousPaddle);
}
