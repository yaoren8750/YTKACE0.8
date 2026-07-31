#import "Preferences.h"
#import "Localization.h"

#import <UIKit/UIKit.h>

NSString * const YTKACEMasterEnabledKey = @"YTKACEEnabled";
NSString * const YTKACEOLEDKey = @"kEnableOldDarkTheme";
NSString * const YTKACENoAdsKey = @"kEnableNoAds";
NSString * const YTKACESponsorBlockKey = @"sponsorBlock";
NSString * const YTKACEDownloadKey = @"kEnableDownloadit";
NSString * const YTKACEBackgroundPlaybackKey = @"kEnablePlayInBackgrounds";
NSString * const YTKACEPiPKey = @"kEnableYTKPiP";
NSString * const YTKACESpeedKey = @"kEnableisSpeed";
NSString * const YTKACELoopKey = @"kEnableYTKLoop";
NSString * const YTKACEPreferencesDidChangeNotification =
    @"YTKACEPreferencesDidChangeNotification";

static NSUserDefaults *YTKACEDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

static void YTKACEAnnouncePreferenceChange(NSString *key) {
    if (key.length == 0) return;
    if ([key isEqualToString:@"kYTKACELanguage"]) {
        YTKACEResetLocalizationCache();
    }
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter
            postNotificationName:YTKACEPreferencesDidChangeNotification
                          object:nil
                        userInfo:@{@"key": key}];
    };
    if (NSThread.isMainThread) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

void YTKACERegisterDefaults(void) {
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"kEnableHideOverlayQuickAction": @"kEnableHideQuickActions",
        @"kEnableShowOverlaySmart": @"kEnableAlwaysShowPlayPause",
        @"kEnableShowMediaController": @"kEnableAlwaysShowControls",
        @"kEnableHideDarkOverlayBackground": @"kEnableHideDarkOverlay",
        @"kEnableDisablePreviousNextButton": @"kEnableDisablePreviousNext",
        @"kEnablePreviousNextButtonPadding": @"kEnableCompactPreviousNext"
    };
    NSMutableDictionary *legacy =
        [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    for (NSString *key in aliases) {
        if (legacy[key] != nil || [YTKACEDefaults() objectForKey:key] != nil) {
            continue;
        }
        NSString *alias = aliases[key];
        id value = legacy[alias] ?: [YTKACEDefaults() objectForKey:alias];
        if (value != nil) {
            legacy[key] = value;
            [YTKACEDefaults() setObject:value forKey:key];
        }
    }
    [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
    if ([YTKACEDefaults() objectForKey:@"YTKACESponsorBehavior.sponsor"] == nil) {
        id oldBehavior = legacy[@"sbSkipMode"] ?:
            [YTKACEDefaults() objectForKey:@"sbSkipMode"];
        if ([oldBehavior respondsToSelector:@selector(integerValue)]) {
            [YTKACEDefaults() setObject:@([oldBehavior integerValue] == 1 ? 1 : 0)
                                  forKey:@"YTKACESponsorBehavior.sponsor"];
        }
    }
    [YTKACEDefaults() registerDefaults:@{
        YTKACEMasterEnabledKey: @YES,
        YTKACENoAdsKey: @YES,
        YTKACEOLEDKey: @NO,
        YTKACEDownloadKey: @NO,
        YTKACEBackgroundPlaybackKey: @NO,
        YTKACEPiPKey: @NO,
        YTKACESpeedKey: @NO,
        YTKACELoopKey: @NO,
        @"kEnableCustomDoubleTapToSkipDuration": @NO,
        @"kEnableTapToSeek": @NO,
        @"kEnableNativeShare": @NO,
        @"kEnableHideShortsRemix": @NO,
        @"kEnableHideShortsShare": @NO,
        @"kEnableHideShortsComments": @NO,
        @"kEnableHideShortsLike": @NO,
        @"kEnableHideShortsAudioTrack": @NO,
        @"kShortsDownloadButtonPosition": @0,
        @"kEnableProfilePictureViewer": @YES,
        @"kEnableRemoveLaunchAnimation": @NO,
        @"kEnableCustomDoubleTapToSkipChnges": @10.0,
        @"kSeekDuration": @10.0,
        @"kVolumeSide": @2,
        @"kBrightnessSide": @2,
        @"kEnabledStartupPage": @0,
        @"wiFiPlaybackIndex": @0,
        @"celluarPlaybackIndex": @0,
        @"sbSkipMode": @0,
        @"YTKACESponsorSkipAlertDuration": @4.0,
        @"YTKACESponsorUnskipAlertDuration": @4.0,
        @"clearonstartup": @NO,
        @"kHideCreate": @YES,
        @"kHideMusic": @YES,
        @"kHideLive": @YES,
        @"kHideGaming": @YES,
        @"kHideNews": @YES,
        @"kHideSports": @YES,
        @"kHideLearning": @YES,
        @"kHideFashion": @YES,
        @"kHidePlaylists": @YES,
        @"kHideHistory": @YES,
        @"kHideNotifs": @YES,
        @"kHideWatchLater": @YES,
        @"kTabOrder": @[@"home", @"shorts", @"subscriptions", @"library", @"ytkace"]
    }];
    [YTKACEDefaults() setBool:YES forKey:YTKACEMasterEnabledKey];
    if ([YTKACEDefaults() boolForKey:@"clearonstartup"]) {
        NSDate *lastClear = [YTKACEDefaults() objectForKey:@"YTKACELastCacheClearDate"];
        if (![lastClear isKindOfClass:NSDate.class] ||
            -lastClear.timeIntervalSinceNow >= 86400.0) {
            NSURL *cache = [YTKACEApplicationSupportDirectory()
                URLByAppendingPathComponent:@"Cache"
                                isDirectory:YES];
            [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
            [YTKACEDefaults() setObject:NSDate.date
                                 forKey:@"YTKACELastCacheClearDate"];
        }
    }
}

BOOL YTKACEMasterEnabled(void) {
    return YES;
}

BOOL YTKACEFeatureEnabled(NSString *key) {
    if (!YTKACEMasterEnabled() || key.length == 0) {
        return NO;
    }
    NSDictionary *legacy = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"];
    id legacyValue = legacy[key];
    if ([legacyValue respondsToSelector:@selector(boolValue)]) {
        return [legacyValue boolValue];
    }
    return [YTKACEDefaults() boolForKey:key];
}

BOOL YTKACEOLEDActive(UITraitCollection *traits) {
    if (!YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        return NO;
    }
    UITraitCollection *current = traits;
    if (current == nil) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    current = window.traitCollection;
                    break;
                }
            }
            if (current != nil) break;
        }
    }
    current = current ?: UIScreen.mainScreen.traitCollection;
    return current.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor *YTKACEInterfaceBackgroundColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) return UIColor.blackColor;
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.075 alpha:1.0]
        : UIColor.whiteColor;
}

UIColor *YTKACEInterfaceSurfaceColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) {
        return [UIColor colorWithWhite:0.10 alpha:1.0];
    }
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.16 alpha:1.0]
        : [UIColor colorWithWhite:0.95 alpha:1.0];
}

BOOL YTKACESponsorBlockEnabled(void) {
    if (!YTKACEMasterEnabled()) {
        return NO;
    }

    NSDictionary *legacy = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"];
    NSNumber *nestedValue = [legacy[YTKACESponsorBlockKey] isKindOfClass:NSNumber.class]
        ? legacy[YTKACESponsorBlockKey]
        : nil;
    if (nestedValue != nil) {
        return nestedValue.boolValue;
    }
    return [YTKACEDefaults() boolForKey:YTKACESponsorBlockKey];
}

void YTKACESetPreference(NSString *key, BOOL enabled) {
    if (key.length == 0) {
        return;
    }

    if ([key isEqualToString:YTKACEMasterEnabledKey]) {
        [YTKACEDefaults() setBool:YES forKey:key];
        YTKACEAnnouncePreferenceChange(key);
        return;
    }
    if (![key isEqualToString:YTKACEMasterEnabledKey]) {
        NSMutableDictionary *legacy =
            [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?: [NSMutableDictionary dictionary];
        legacy[key] = @(enabled);
        [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
    }
    [YTKACEDefaults() setBool:enabled forKey:key];
    YTKACEAnnouncePreferenceChange(key);
}

id YTKACEPreferenceObject(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    id legacyValue = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"][key];
    return legacyValue ?: [YTKACEDefaults() objectForKey:key];
}

void YTKACESetPreferenceObject(NSString *key, id value) {
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *legacy =
        [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    if (value == nil) {
        [legacy removeObjectForKey:key];
        [YTKACEDefaults() removeObjectForKey:key];
    } else {
        legacy[key] = value;
        [YTKACEDefaults() setObject:value forKey:key];
    }
    [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
    YTKACEAnnouncePreferenceChange(key);
}

static NSString *YTKACERelativeStoragePath(NSURL *URL, NSURL *baseURL) {
    NSString *path = URL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *base = baseURL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *prefix = [base stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return nil;
    return [path substringFromIndex:prefix.length];
}

static void YTKACERepairDownloads(NSURL *root) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *downloads = [root URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    NSArray<NSURL *> *items = [[manager enumeratorAtURL:downloads
        includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                           options:0 errorHandler:nil] allObjects];
    for (NSURL *source in items) {
        NSNumber *directory = nil;
        [source getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (directory.boolValue) continue;
        NSString *relative = YTKACERelativeStoragePath(source, downloads);
        NSArray<NSString *> *components = relative.pathComponents;
        NSUInteger categoryIndex = NSNotFound;
        NSString *category = nil;
        for (NSUInteger index = 0; index < components.count; index++) {
            for (NSString *candidate in @[@"Video", @"Audio", @"Shorts"]) {
                if ([components[index] caseInsensitiveCompare:candidate] == NSOrderedSame) {
                    categoryIndex = index;
                    category = candidate;
                    break;
                }
            }
            if (categoryIndex != NSNotFound) break;
        }
        if (categoryIndex == NSNotFound || categoryIndex + 1 >= components.count) continue;
        NSURL *target = [downloads URLByAppendingPathComponent:category isDirectory:YES];
        for (NSUInteger index = categoryIndex + 1; index < components.count; index++) {
            target = [target URLByAppendingPathComponent:components[index]];
        }
        if ([source.URLByResolvingSymlinksInPath.path
                isEqualToString:target.URLByResolvingSymlinksInPath.path]) continue;
        [manager createDirectoryAtURL:target.URLByDeletingLastPathComponent
          withIntermediateDirectories:YES attributes:nil error:nil];
        if ([manager fileExistsAtPath:target.path]) {
            [manager removeItemAtURL:source error:nil];
        } else {
            [manager moveItemAtURL:source toURL:target error:nil];
        }
    }
    for (NSString *name in @[@"Downloads", @"ownloads"]) {
        [manager removeItemAtURL:[downloads URLByAppendingPathComponent:name isDirectory:YES]
                           error:nil];
    }
}

NSURL *YTKACEApplicationSupportDirectory(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *documents = [manager URLsForDirectory:NSDocumentDirectory
                                        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"YTKACE"
                                                   isDirectory:YES];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *support = [manager URLsForDirectory:NSApplicationSupportDirectory
                                         inDomains:NSUserDomainMask].firstObject;
        NSURL *legacy = [support URLByAppendingPathComponent:@"YTKACE"
                                                  isDirectory:YES];
        BOOL targetExists = [manager fileExistsAtPath:directory.path];
        if (!targetExists && [manager fileExistsAtPath:legacy.path]) {
            [manager moveItemAtURL:legacy toURL:directory error:nil];
        }
        [manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        if ([manager fileExistsAtPath:legacy.path]) {
            NSDirectoryEnumerator<NSURL *> *items = [manager
                enumeratorAtURL:legacy
     includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                        options:0
                   errorHandler:nil];
            for (NSURL *source in items) {
                NSString *relative = YTKACERelativeStoragePath(source, legacy);
                if (relative.length == 0) continue;
                NSURL *destination = [directory URLByAppendingPathComponent:relative];
                NSNumber *isDirectory = nil;
                [source getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                if (isDirectory.boolValue) {
                    [manager createDirectoryAtURL:destination
                      withIntermediateDirectories:YES attributes:nil error:nil];
                } else if (![manager fileExistsAtPath:destination.path]) {
                    [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                      withIntermediateDirectories:YES attributes:nil error:nil];
                    [manager moveItemAtURL:source toURL:destination error:nil];
                }
            }
            [manager removeItemAtURL:legacy error:nil];
        }
        YTKACERepairDownloads(directory);
    });
    return directory;
}
