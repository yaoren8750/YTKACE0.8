#import "YTKACESettingsPages.h"
#import "../Runtime/Localization.h"
#import "YTKACERootOptionsController.h"
#import "YTKACEDownloadsController.h"
#import "../Runtime/Hooking.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

static const NSUInteger YTKACENativeSettingsCategory = 789;
static const NSUInteger YTKACENativeSettingsGroup = 0x796b6163;
static IMP OriginalSettingsCategoryOrder;
static IMP OriginalUpdateSettingsSection;
static IMP OriginalOrderedSettingsGroups;
static IMP OriginalSettingsGroupTitle;
static IMP OriginalOrderedGroupCategories;

typedef UIViewController * _Nonnull (^YTKACENativeBuilder)(void);

static NSArray *YTKACESettingsCategoryOrder(id receiver, SEL selector) {
    NSArray *order = OriginalSettingsCategoryOrder == NULL ? @[] :
        ((id (*)(id, SEL))OriginalSettingsCategoryOrder)(receiver, selector);
    if ([order containsObject:@(YTKACENativeSettingsCategory)]) return order;
    NSMutableArray *updated = [order mutableCopy] ?: [NSMutableArray array];
    NSUInteger index = [updated indexOfObject:@1];
    [updated insertObject:@(YTKACENativeSettingsCategory)
                  atIndex:index == NSNotFound ? updated.count : index + 1];
    return updated;
}

static NSArray *YTKACEOrderedSettingsGroups(id receiver, SEL selector) {
    NSArray *groups = OriginalOrderedSettingsGroups == NULL ? @[] :
        ((id (*)(id, SEL))OriginalOrderedSettingsGroups)(receiver, selector);
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL initializer = NSSelectorFromString(@"initWithGroupType:");
    if (groupClass == Nil || ![groupClass instancesRespondToSelector:initializer]) return groups;
    id group = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
        [groupClass alloc], initializer, YTKACENativeSettingsGroup);
    if (group == nil) return groups;
    NSMutableArray *updated = [groups mutableCopy] ?: [NSMutableArray array];
    [updated insertObject:group atIndex:0];
    return updated;
}

static NSString *YTKACESettingsGroupTitle(id receiver, SEL selector, NSUInteger type) {
    if (type == YTKACENativeSettingsGroup) return @"YTKACE";
    return OriginalSettingsGroupTitle == NULL ? nil :
        ((id (*)(id, SEL, NSUInteger))OriginalSettingsGroupTitle)(receiver, selector, type);
}

static NSArray *YTKACEOrderedGroupCategories(id receiver, SEL selector, NSUInteger type) {
    if (type == YTKACENativeSettingsGroup) return @[@(YTKACENativeSettingsCategory)];
    return OriginalOrderedGroupCategories == NULL ? @[] :
        ((id (*)(id, SEL, NSUInteger))OriginalOrderedGroupCategories)(receiver, selector, type);
}

static NSString *YTKACENativeSettingsSubtitle(NSString *title) {
    static NSDictionary<NSString *, NSString *> *subtitles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        subtitles = @{
            @"Downloads": @"Saved videos, audio and Shorts",
            @"Player Controls": @"Speed, loop, gestures and overlay buttons",
            @"SponsorBlock": @"Skip sponsors and swap clickbait with DeArrow",
            @"Tab Bar": @"Choose and reorder the bottom tabs",
            @"Gestures": @"Double tap, hold to seek and pinch",
            @"itzzace": @"Developer"
        };
    });
    NSString *value = subtitles[title];
    return value != nil ? YTKACELocalized(value) : nil;
}

static id YTKACENativeSettingsItem(NSString *title,
                                   id settingsController,
                                   YTKACENativeBuilder builder) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL selector = NSSelectorFromString(
        @"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (itemClass == Nil || ![itemClass respondsToSelector:selector]) return nil;
    NSString *(^detail)(void) = ^NSString *{ return @"›"; };
    BOOL (^select)(id, NSUInteger) = ^BOOL(__unused id cell, __unused NSUInteger index) {
        UIViewController *controller = builder == nil ? nil : builder();
        if (controller == nil) return NO;
        SEL push = NSSelectorFromString(@"pushViewController:");
        if ([settingsController respondsToSelector:push]) {
            ((void (*)(id, SEL, id))objc_msgSend)(settingsController, push, controller);
            return YES;
        }
        UINavigationController *navigation =
            [settingsController isKindOfClass:UIViewController.class]
                ? ((UIViewController *)settingsController).navigationController : nil;
        [navigation pushViewController:controller animated:YES];
        return navigation != nil;
    };
    SEL described = NSSelectorFromString(
        @"itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:"
         "selectBlock:");
    NSString *subtitle = YTKACENativeSettingsSubtitle(title);
    if (subtitle.length != 0 && [itemClass respondsToSelector:described]) {
        return ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
            itemClass, described, title, subtitle, @"YTKACENativeSettingsItem",
            detail, select);
    }
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
        itemClass, selector, title, @"YTKACENativeSettingsItem", detail, select);
}

static void YTKACEUpdateNativeSettingsSection(id receiver, SEL selector,
                                              NSUInteger category, id entry) {
    if (category != YTKACENativeSettingsCategory) {
        if (OriginalUpdateSettingsSection != NULL) {
            ((void (*)(id, SEL, NSUInteger, id))OriginalUpdateSettingsSection)(
                receiver, selector, category, entry);
        }
        return;
    }

    id settingsController = nil;
    @try {
        settingsController = [receiver valueForKey:@"_settingsViewControllerDelegate"];
    } @catch (__unused NSException *exception) {
        return;
    }
    NSArray<NSDictionary *> *definitions = @[
        @{@"title": @"Downloads", @"builder": [^UIViewController *{
            YTKACEDownloadsController *controller = [YTKACEDownloadsController new];
            controller.hidesSettingsButton = YES;
            return controller;
        } copy]},
        @{@"title": @"Player Controls", @"builder": [^UIViewController *{ return YTKACEMakePlayerControlsController(); } copy]},
        @{@"title": @"SponsorBlock", @"builder": [^UIViewController *{ return YTKACEMakeSponsorBlockController(); } copy]},
        @{@"title": @"Tab Bar", @"builder": [^UIViewController *{ return YTKACEMakeTabBarOptionsController(); } copy]},
        @{@"title": @"Wi-Fi Quality", @"builder": [^UIViewController *{ return YTKACEMakeWiFiQualityController(); } copy]},
        @{@"title": @"Cellular Quality", @"builder": [^UIViewController *{ return YTKACEMakeCellularQualityController(); } copy]},
        @{@"title": @"Gestures", @"builder": [^UIViewController *{ return YTKACEMakeGestureOptionsController(); } copy]},
        @{@"title": @"Overlay", @"builder": [^UIViewController *{ return YTKACEMakeOverlayOptionsController(); } copy]},
        @{@"title": @"Streaming", @"builder": [^UIViewController *{ return YTKACEMakeStreamingOptionsController(); } copy]},
        @{@"title": @"Navigation Bar", @"builder": [^UIViewController *{ return YTKACEMakeNavigationOptionsController(); } copy]},
        @{@"title": @"Shorts", @"builder": [^UIViewController *{ return YTKACEMakeShortsOptionsController(); } copy]},
        @{@"title": @"Miscellaneous", @"builder": [^UIViewController *{ return YTKACEMakeMiscOptionsController(); } copy]},
        @{@"title": @"itzzace", @"builder": [^UIViewController *{ return YTKACEMakeCreditsController(); } copy]}
    ];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *definition in definitions) {
        id item = YTKACENativeSettingsItem(definition[@"title"], settingsController,
                                           definition[@"builder"]);
        if (item != nil) [items addObject:item];
    }

    SEL modern = NSSelectorFromString(
        @"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:");
    SEL legacy = NSSelectorFromString(
        @"setSectionItems:forCategory:title:titleDescription:headerHidden:");
    if ([settingsController respondsToSelector:modern]) {
        id icon = [NSClassFromString(@"YTIIcon") new];
        SEL setIconType = NSSelectorFromString(@"setIconType:");
        if ([icon respondsToSelector:setIconType]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, setIconType, 44);
        }
        ((void (*)(id, SEL, id, NSUInteger, id, id, id, BOOL))objc_msgSend)(
            settingsController, modern, items, category, @"YTKACE", icon, nil, NO);
    } else if ([settingsController respondsToSelector:legacy]) {
        ((void (*)(id, SEL, id, NSUInteger, id, id, BOOL))objc_msgSend)(
            settingsController, legacy, items, category, @"YTKACE", nil, NO);
    }
}

void YTKACEInstallNativeSettingsHooks(void) {
    YTKACEInstallClassHook(@"YTAppSettingsPresentationData", @"settingsCategoryOrder",
                           (IMP)YTKACESettingsCategoryOrder,
                           &OriginalSettingsCategoryOrder);
    YTKACEInstallInstanceHook(@"YTSettingsSectionItemManager",
                              @"updateSectionForCategory:withEntry:",
                              (IMP)YTKACEUpdateNativeSettingsSection,
                              &OriginalUpdateSettingsSection);
    YTKACEInstallClassHook(@"YTAppSettingsGroupPresentationData", @"orderedGroups",
                           (IMP)YTKACEOrderedSettingsGroups,
                           &OriginalOrderedSettingsGroups);
    YTKACEInstallInstanceHook(@"YTSettingsGroupData", @"titleForSettingGroupType:",
                              (IMP)YTKACESettingsGroupTitle,
                              &OriginalSettingsGroupTitle);
    YTKACEInstallInstanceHook(@"YTSettingsGroupData", @"orderedCategoriesForGroupType:",
                              (IMP)YTKACEOrderedGroupCategories,
                              &OriginalOrderedGroupCategories);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (NSUInteger attempt = 1; attempt <= 60; attempt++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(attempt * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                YTKACEInstallNativeSettingsHooks();
            });
        }
    });
}
