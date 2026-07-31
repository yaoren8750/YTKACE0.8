#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalDisplayViewDidMove;
static IMP OriginalDisplayViewSetIdentifier;
static IMP OriginalAddSections;
static IMP OriginalSectionControllers;
static IMP OriginalEnableSubheaderBar;
static IMP OriginalChipBarUpdate;
static IMP OriginalChipCloudSetEntry;
static IMP OriginalSubsChipFilter;
static IMP OriginalChipCloudLayout;
static IMP OriginalFeedHeaderScrollMode;
static IMP OriginalSubsSetChipFilterView;
static IMP OriginalMaximumSubheaderHeight;
static IMP OriginalMaximumSubheaderHeightGetter;
static IMP OriginalSubheaderDefaultHeight;
static IMP OriginalSetHeaderHeights;
static IMP OriginalShouldHideSubheader;
static IMP OriginalPaidContentLayout;
static IMP OriginalPaidContentDidAppear;
static IMP OriginalPaidContentPlaybackStarted;
static IMP OriginalSetPaidContentPlayerData;
static IMP OriginalSetPaidContentRenderer;
static IMP OriginalHasPaidContentOverlay;
static IMP OriginalPaidContentOverlay;
static IMP OriginalOverlayPaidContentPlayerData;
static IMP OriginalInlinePaidContentPlayerData;
static IMP OriginalDidInsertPlayerOverlay;
static const void *YTKACEContentHiddenAssociation = &YTKACEContentHiddenAssociation;
static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles);
static id YTKACEContentValue(id object, NSString *key);
static BOOL YTKACESectionIsShortsShelf(id section);
static BOOL YTKACEHideTopics(void);

static id YTKACEContentValue(id object, NSString *key) {
    if (object == nil || key.length == 0) {
        return nil;
    }
    @try {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL YTKACEItemIsShorts(id item) {
    NSString *description = [[[item description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    return YTKACEContentContains(description, @[
        @"shorts_shelf_eml", @"shorts_shelf", @"reel_shelf",
        @"shorts_lockup_shelf", @"shortsshelfrenderer", @"reelshelfrenderer",
        @"shortslockupviewmodel", @"shorts_video_cell", @"reelitemrenderer",
        @"shortslockup"
    ]);
}

static BOOL YTKACESectionIsShortsShelf(id section) {
    if (section == nil) {
        return NO;
    }

    NSArray *entries = YTKACEContentValue(section, @"contentsArray");
    if ([entries isKindOfClass:NSArray.class] && entries.count != 0) {
        for (id entry in entries) {
            if (!YTKACEItemIsShorts(entry)) {
                return NO;
            }
        }
        return YES;
    }

    NSString *description = [[[section description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if (YTKACEContentContains(description, @[
        @"shorts_shelf_eml", @"shorts_shelf", @"reel_shelf",
        @"shorts_lockup_shelf", @"shortsshelfrenderer",
        @"reelshelfrenderer", @"shortslockupviewmodel"
    ])) {
        return YES;
    }
    NSString *className = NSStringFromClass([section class]).lowercaseString;
    if (![className containsString:@"shelfrenderer"] &&
        ![className containsString:@"richsectionrenderer"]) {
        return NO;
    }
    id content = YTKACEContentValue(section, @"content");
    id list = YTKACEContentValue(content, @"horizontalListRenderer") ?:
        YTKACEContentValue(content, @"richShelfRenderer") ?:
        content;
    NSArray *items = YTKACEContentValue(list, @"itemsArray") ?:
        YTKACEContentValue(list, @"contentsArray");
    for (id item in items) {
        NSString *itemDescription = [[item description] lowercaseString];
        if (YTKACEContentContains(itemDescription, @[
            @"shorts_video_cell", @"reelitemrenderer", @"shortslockup"
        ])) {
            return YES;
        }
    }
    return NO;
}

static NSArray *YTKACEFilteredFeedSections(NSArray *sections) {
    BOOL hideShorts = YTKACEFeatureEnabled(@"kEnableHideYTShorts");
    if (!hideShorts || ![sections isKindOfClass:NSArray.class]) {
        return sections;
    }
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (hideShorts && YTKACESectionIsShortsShelf(section)) continue;
        [filtered addObject:section];
    }
    return filtered;
}

static id YTKACESectionControllers(id receiver, SEL selector,
                                   NSArray *sections, id reloadMap) {
    if (OriginalSectionControllers == NULL) return nil;
    NSArray *filtered = YTKACEFilteredFeedSections(sections);
    return ((id (*)(id, SEL, id, id))OriginalSectionControllers)(
        receiver, selector, filtered, reloadMap);
}

static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([token containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTKACEContentShouldHide(UIView *view, BOOL *hideSuperview) {
    NSString *identifier = [view.accessibilityIdentifier.lowercaseString
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
                       identifier ?: @"",
                       view.accessibilityLabel.lowercaseString ?: @"",
                       NSStringFromClass(view.class).lowercaseString];

    if (YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        YTKACEContentContains(token, @[
            @"eml_ad_",
            @"eml_expandable_metadata_vpp",
            @"feed_ad_metadata",
            @"paid_content_overlay",
            @"promoted_video",
            @"companion_ad"
        ])) {
        return YES;
    }

    if (YTKACEFeatureEnabled(@"kEnableHideComments")) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"]) {
            if (hideSuperview != NULL) {
                *hideSuperview = YES;
            }
            return YES;
        }
        if (YTKACEContentContains(token, @[
            @"id_ui_comments_composite_entry_point_teaser",
            @"id_ui_comments_entry_point_teaser",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
            return YES;
        }
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCommentReview") &&
        [identifier isEqualToString:@"id_ui_comments_entry_point_teaser"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCommentGuidlines") &&
        YTKACEContentContains(token, @[
            @"id_comment_guidelines_text",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"] &&
            hideSuperview != NULL) {
            *hideSuperview = YES;
        }
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoTopics") &&
        YTKACEContentContains(token, @[@"topic_chip", @"feed_filter", @"chip_cloud"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoSearchedHistory") &&
        YTKACEContentContains(token, @[@"search_history", @"history_suggestion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        YTKACEContentContains(token, @[@"paid_promotion", @"paidpromotion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoPremiumpopup") &&
        YTKACEContentContains(token, @[@"premium_upsell", @"premium_promo"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoYTUpdate") &&
        YTKACEContentContains(token, @[@"update_dialog", @"upgrade_dialog"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideSuggestedVideo") &&
        YTKACEContentContains(token, @[@"suggested_video", @"related_video"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideRelatedVideos") &&
        YTKACEContentContains(token, @[
            @"related_video", @"relatedvideo", @"more_videos", @"watch_next"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableDisableContinueWatching") &&
        YTKACEContentContains(token, @[
            @"continue_watching", @"continuewatching", @"resume_watching"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableBlockShortsOverlays") &&
        YTKACEContentContains(token, @[
            @"shorts_pause", @"reel_pause", @"pause_card", @"pausecard",
            @"paused_state_carousel", @"reelpausedstatecarousel"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideShortsProducts") &&
        YTKACEContentContains(token, @[
            @"shorts_product", @"product_sticker", @"shopping_carousel",
            @"shopping_destination", @"tagged_product", @"creator_product"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideShortsStickerAds") &&
        YTKACEContentContains(token, @[
            @"brand_link_sticker", @"product_sticker", @"promoted_sticker",
            @"sponsored_sticker", @"shorts_ads_shopping"
        ])) {
        return YES;
    }
    return NO;
}

static void YTKACEApplyContentVisibility(UIView *view) {
    BOOL hideSuperview = NO;
    BOOL hidden = YTKACEContentShouldHide(view, &hideSuperview);

    UIView *target = hideSuperview ? view.superview : view;
    if (target == nil) {
        return;
    }

    NSNumber *baseline = objc_getAssociatedObject(
        target,
        YTKACEContentHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(target,
                                     YTKACEContentHiddenAssociation,
                                     @(target.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        target.hidden = YES;
        target.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        target.hidden = baseline.boolValue;
        target.userInteractionEnabled = YES;
        objc_setAssociatedObject(target,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEDisplayViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalDisplayViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalDisplayViewDidMove)(receiver, selector);
    }
    YTKACEApplyContentVisibility(receiver);
}

static void YTKACEDisplayViewSetIdentifier(UIView *receiver,
                                           SEL selector,
                                           NSString *identifier) {
    if (OriginalDisplayViewSetIdentifier != NULL) {
        ((void (*)(id, SEL, id))OriginalDisplayViewSetIdentifier)(
            receiver,
            selector,
            identifier
        );
    }
    YTKACEApplyContentVisibility(receiver);
}

static BOOL YTKACEHideTopics(void) {
    return YTKACEFeatureEnabled(@"kEnableNoTopics");
}

static void YTKACECollapseSubheader(id receiver) {
    SEL height = NSSelectorFromString(@"setMaximumSubheaderHeight:");
    if ([receiver respondsToSelector:height]) {
        ((void (*)(id, SEL, double))objc_msgSend)(receiver, height, 0.0);
    }
    for (NSString *name in @[@"hideSubheaderBar", @"disableSubheaderBar",
                             @"setSubheaderHeightToZero",
                             @"resetScrollViewInsetOffset"]) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    SEL enabled = NSSelectorFromString(@"setSubheaderBarEnabled:");
    if ([receiver respondsToSelector:enabled]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, enabled, NO);
    }
}

static double YTKACEMaximumSubheaderHeightGetter(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalMaximumSubheaderHeightGetter == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalMaximumSubheaderHeightGetter)(
            receiver, selector);
}

static double YTKACESubheaderDefaultHeight(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalSubheaderDefaultHeight == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalSubheaderDefaultHeight)(
            receiver, selector);
}

static void YTKACEPaidContentLayout(UIView *receiver, SEL selector) {
    if (OriginalPaidContentLayout != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentLayout)(receiver, selector);
    }
    BOOL hide = YTKACEFeatureEnabled(@"kEnableNoPaidPromotion");
    NSNumber *baseline = objc_getAssociatedObject(
        receiver, YTKACEContentHiddenAssociation);
    if (hide) {
        if (baseline == nil) {
            objc_setAssociatedObject(receiver,
                                     YTKACEContentHiddenAssociation,
                                     @(receiver.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        receiver.hidden = YES;
        receiver.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        receiver.hidden = baseline.boolValue;
        receiver.userInteractionEnabled = YES;
        objc_setAssociatedObject(receiver,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEPaidContentDidAppear(UIViewController *receiver,
                                       SEL selector,
                                       BOOL animated) {
    if (OriginalPaidContentDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPaidContentDidAppear)(
            receiver, selector, animated);
    }
    if (!YTKACEFeatureEnabled(@"kEnableNoPaidPromotion")) return;
    receiver.view.hidden = YES;
    receiver.view.userInteractionEnabled = NO;
    for (NSString *name in @[@"hidePaidContent",
                             @"removePaidContentViewController"]) {
        SEL action = NSSelectorFromString(name);
        if ([receiver respondsToSelector:action]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, action);
        }
    }
}

static void YTKACEPaidContentPlaybackStarted(id receiver, SEL selector) {
    if (!YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        OriginalPaidContentPlaybackStarted != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentPlaybackStarted)(receiver, selector);
    }
}

static void YTKACESetPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        OriginalSetPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACESetPaidContentRenderer(id receiver, SEL selector, id renderer) {
    if (OriginalSetPaidContentRenderer != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentRenderer)(
            receiver, selector,
            YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") ? nil : renderer);
    }
}

static BOOL YTKACEHasPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableNoPaidPromotion")) return NO;
    return OriginalHasPaidContentOverlay != NULL &&
        ((BOOL (*)(id, SEL))OriginalHasPaidContentOverlay)(receiver, selector);
}

static id YTKACEPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableNoPaidPromotion")) return nil;
    return OriginalPaidContentOverlay == NULL ? nil :
        ((id (*)(id, SEL))OriginalPaidContentOverlay)(receiver, selector);
}

static void YTKACEOverlayPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        OriginalOverlayPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalOverlayPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEInlinePaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        OriginalInlinePaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalInlinePaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEDidInsertPlayerOverlay(id receiver, SEL selector,
                                         id provider, id overlay) {
    NSString *identifier = YTKACEContentValue(overlay, @"overlayIdentifier");
    if (YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        [identifier isEqualToString:@"player_overlay_paid_content"]) {
        return;
    }
    if (OriginalDidInsertPlayerOverlay != NULL) {
        ((void (*)(id, SEL, id, id))OriginalDidInsertPlayerOverlay)(
            receiver, selector, provider, overlay);
    }
}

static void YTKACEEnableSubheaderBar(__unsafe_unretained id receiver, SEL selector,
                                     __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) {
        YTKACECollapseSubheader(receiver);
        return;
    }
    if (OriginalEnableSubheaderBar != NULL) {
        ((void (*)(id, SEL, id))OriginalEnableSubheaderBar)(receiver, selector, view);
    }
}

static void YTKACEChipBarUpdate(__unsafe_unretained id receiver, SEL selector,
                                __unsafe_unretained id collectionViewController,
                                __unsafe_unretained id host,
                                __unsafe_unretained id renderer,
                                __unsafe_unretained id browseIdentifier,
                                __unsafe_unretained id sectionList) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalChipBarUpdate != NULL) {
        ((void (*)(id, SEL, id, id, id, id, id))OriginalChipBarUpdate)(
            receiver, selector, collectionViewController, host, renderer,
            browseIdentifier, sectionList);
    }
}

static void YTKACEChipCloudSetEntry(__unsafe_unretained id receiver, SEL selector,
                                    __unsafe_unretained id entry) {
    if (OriginalChipCloudSetEntry != NULL) {
        ((void (*)(id, SEL, id))OriginalChipCloudSetEntry)(receiver, selector, entry);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if ([receiver isKindOfClass:UIView.class]) {
        UIView *cell = (UIView *)receiver;
        cell.hidden = YES;
        cell.userInteractionEnabled = NO;
    }
}

static void YTKACEChipCloudLayout(__unsafe_unretained id receiver, SEL selector) {
    if (OriginalChipCloudLayout != NULL) {
        ((void (*)(id, SEL))OriginalChipCloudLayout)(receiver, selector);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if (![receiver isKindOfClass:UIView.class]) return;
    UIView *cell = (UIView *)receiver;
    cell.hidden = YES;
    cell.userInteractionEnabled = NO;
    CGRect frame = cell.frame;
    if (frame.size.height != 0.0) {
        frame.size.height = 0.0;
        cell.frame = frame;
    }
    for (UIView *subview in cell.subviews) {
        subview.hidden = YES;
    }
}

static void YTKACEFeedHeaderScrollMode(__unsafe_unretained id receiver, SEL selector,
                                       NSInteger mode) {
    if (OriginalFeedHeaderScrollMode != NULL) {
        ((void (*)(id, SEL, NSInteger))OriginalFeedHeaderScrollMode)(
            receiver, selector, mode);
    }
}

static void YTKACESubsSetChipFilterView(__unsafe_unretained id receiver, SEL selector,
                                        __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsSetChipFilterView != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsSetChipFilterView)(receiver, selector, view);
    }
}

static void YTKACESubsChipFilter(__unsafe_unretained id receiver, SEL selector,
                                 __unsafe_unretained id model) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsChipFilter != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsChipFilter)(receiver, selector, model);
    }
}

static void YTKACEMaximumSubheaderHeight(__unsafe_unretained id receiver,
                                        SEL selector, double height) {
    BOOL hide = YTKACEHideTopics();
    if (hide) height = 0.0;
    if (OriginalMaximumSubheaderHeight != NULL) {
        ((void (*)(id, SEL, double))OriginalMaximumSubheaderHeight)(
            receiver, selector, height);
    }
}

static void YTKACESetHeaderHeights(id receiver, SEL selector,
                                    double headerHeight,
                                    double subheaderHeight,
                                    double topOffset,
                                    BOOL animated) {
    if (YTKACEHideTopics()) {
        subheaderHeight = 0.0;
    }
    if (OriginalSetHeaderHeights != NULL) {
        ((void (*)(id, SEL, double, double, double, BOOL))OriginalSetHeaderHeights)(
            receiver, selector, headerHeight, subheaderHeight, topOffset, animated);
    }
}

static BOOL YTKACEShouldHideSubheader(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return YES;
    return OriginalShouldHideSubheader != NULL &&
        ((BOOL (*)(id, SEL))OriginalShouldHideSubheader)(receiver, selector);
}

static void YTKACEAddSections(id receiver, SEL selector, NSArray *sections) {
    if (OriginalAddSections != NULL) {
        NSArray *filtered = YTKACEFilteredFeedSections(sections);
        ((void (*)(id, SEL, id))OriginalAddSections)(
            receiver, selector, filtered);
    }
}

void YTKACEInstallContentVisibilityHooks(void) {
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEDisplayViewDidMove,
                              &OriginalDisplayViewDidMove);
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"setAccessibilityIdentifier:",
                              (IMP)YTKACEDisplayViewSetIdentifier,
                              &OriginalDisplayViewSetIdentifier);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"addSectionsFromArray:",
                              (IMP)YTKACEAddSections,
                              &OriginalAddSections);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"sectionControllersForSectionRenderers:reloadingSectionControllerByRenderer:",
                              (IMP)YTKACESectionControllers,
                              &OriginalSectionControllers);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"enableSubheaderBarWithView:",
                              (IMP)YTKACEEnableSubheaderBar,
                              &OriginalEnableSubheaderBar);
    YTKACEInstallInstanceHook(@"YTFeedFilterChipBarController",
                              @"updateWithCollectionViewController:feedFilterChipBarHost:feedFilterChipBarRenderer:browseIdentifier:sectionList:",
                              (IMP)YTKACEChipBarUpdate,
                              &OriginalChipBarUpdate);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"setEntry:",
                              (IMP)YTKACEChipCloudSetEntry,
                              &OriginalChipCloudSetEntry);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderViewController",
                              @"loadChipFilterFromModel:",
                              (IMP)YTKACESubsChipFilter,
                              &OriginalSubsChipFilter);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"layoutSubviews",
                              (IMP)YTKACEChipCloudLayout,
                              &OriginalChipCloudLayout);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setFeedHeaderScrollMode:",
                              (IMP)YTKACEFeedHeaderScrollMode,
                              &OriginalFeedHeaderScrollMode);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setMaximumSubheaderHeight:",
                              (IMP)YTKACEMaximumSubheaderHeight,
                              &OriginalMaximumSubheaderHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"maximumSubheaderHeight",
                              (IMP)YTKACEMaximumSubheaderHeightGetter,
                              &OriginalMaximumSubheaderHeightGetter);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"subheaderDefaultHeight",
                              (IMP)YTKACESubheaderDefaultHeight,
                              &OriginalSubheaderDefaultHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setHeaderHeight:subheaderHeight:topOffset:animated:",
                              (IMP)YTKACESetHeaderHeights,
                              &OriginalSetHeaderHeights);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"shouldHideSubHeader",
                              (IMP)YTKACEShouldHideSubheader,
                              &OriginalShouldHideSubheader);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderView",
                              @"setChipFilterView:",
                              (IMP)YTKACESubsSetChipFilterView,
                              &OriginalSubsSetChipFilterView);
    YTKACEInstallInstanceHook(@"YTPaidContentOverlayView",
                              @"layoutSubviews",
                              (IMP)YTKACEPaidContentLayout,
                              &OriginalPaidContentLayout);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEPaidContentDidAppear,
                              &OriginalPaidContentDidAppear);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"playbackDidStart",
                              (IMP)YTKACEPaidContentPlaybackStarted,
                              &OriginalPaidContentPlaybackStarted);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACESetPaidContentPlayerData,
                              &OriginalSetPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"setPaidContentRenderer:",
                              (IMP)YTKACESetPaidContentRenderer,
                              &OriginalSetPaidContentRenderer);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"hasPaidContentOverlay",
                              (IMP)YTKACEHasPaidContentOverlay,
                              &OriginalHasPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"paidContentOverlay",
                              (IMP)YTKACEPaidContentOverlay,
                              &OriginalPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEOverlayPaidContentPlayerData,
                              &OriginalOverlayPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTInlineMutedPlaybackPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEInlinePaidContentPlayerData,
                              &OriginalInlinePaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"playerOverlayProvider:didInsertPlayerOverlay:",
                              (IMP)YTKACEDidInsertPlayerOverlay,
                              &OriginalDidInsertPlayerOverlay);
}
