#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

static IMP OriginalShowShareSheet;
static IMP OriginalShareButtonSendAction;

static id YTKACEShareValue(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (object == nil || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *YTKACESerializedShareEntity(id receiver,
                                               id onAppear,
                                               id context) {
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"serialized_share_entity: \"([^\"]+)\""
        options:0 error:nil];
    if (expression == nil) return nil;
    for (id object in @[receiver ?: NSNull.null,
                        onAppear ?: NSNull.null,
                        context ?: NSNull.null]) {
        if (object == NSNull.null) continue;
        NSString *description = [object description];
        NSTextCheckingResult *match = [expression
            firstMatchInString:description options:0
            range:NSMakeRange(0, description.length)];
        if (match.numberOfRanges > 1) {
            return [description substringWithRange:[match rangeAtIndex:1]];
        }
    }
    return nil;
}

static BOOL YTKACEShareBool(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return object != nil && [object respondsToSelector:selector] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static id YTKACEShareExtension(id object, id descriptor) {
    if (object == nil || descriptor == nil) return nil;
    SEL has = NSSelectorFromString(@"hasExtension:");
    SEL get = NSSelectorFromString(@"getExtension:");
    if (![object respondsToSelector:has] ||
        ![object respondsToSelector:get] ||
        !((BOOL (*)(id, SEL, id))objc_msgSend)(object, has, descriptor)) {
        return nil;
    }
    return ((id (*)(id, SEL, id))objc_msgSend)(object, get, descriptor);
}

static NSData *YTKACEShareFieldData(id fields, NSInteger number) {
    if (fields == nil) return nil;
    SEL has = NSSelectorFromString(@"hasField:");
    SEL get = NSSelectorFromString(@"getField:");
    if (![fields respondsToSelector:has] ||
        ![fields respondsToSelector:get] ||
        !((BOOL (*)(id, SEL, NSInteger))objc_msgSend)(fields, has, number)) {
        return nil;
    }
    id field = ((id (*)(id, SEL, NSInteger))objc_msgSend)(
        fields, get, number);
    NSArray *values = YTKACEShareValue(field, @"lengthDelimitedList");
    id value = values.count == 1 ? values.firstObject : nil;
    return [value isKindOfClass:NSData.class] ? value : nil;
}

static NSString *YTKACEShareFieldFromDescription(id fields, NSInteger number) {
    if (fields == nil) return nil;
    NSString *pattern = [NSString stringWithFormat:@"\\b%ld: \"([^\"]+)\"",
                         (long)number];
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:pattern options:0 error:nil];
    NSString *description = [fields description];
    NSTextCheckingResult *match = [expression
        firstMatchInString:description options:0
        range:NSMakeRange(0, description.length)];
    return match.numberOfRanges > 1
        ? [description substringWithRange:[match rangeAtIndex:1]] : nil;
}

static NSString *YTKACEShareFieldString(id fields, NSInteger number) {
    NSData *data = YTKACEShareFieldData(fields, number);
    if (data.length != 0) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return YTKACEShareFieldFromDescription(fields, number);
}

static id YTKACEShareUnknownFields(id message) {
    if (message == nil) return nil;
    Class unknownClass = NSClassFromString(@"GPBUnknownFields");
    SEL initializer = NSSelectorFromString(@"initFromMessage:");
    if (unknownClass != Nil &&
        [unknownClass instancesRespondToSelector:initializer]) {
        id unknown = ((id (*)(id, SEL, id))objc_msgSend)(
            [unknownClass alloc], initializer, message);
        if (unknown != nil) return unknown;
    }
    return YTKACEShareValue(message, @"unknownFields");
}

static id YTKACEParseShareMessage(NSData *data) {
    Class messageClass = NSClassFromString(@"GPBMessage");
    SEL parse = NSSelectorFromString(@"parseFromData:error:");
    if (messageClass == Nil || ![messageClass respondsToSelector:parse]) return nil;
    NSError *error = nil;
    return ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
        messageClass, parse, data, &error);
}

static NSURL *YTKACEShareURL(id fields) {
    NSData *clipData = YTKACEShareFieldData(fields, 8);
    if (clipData.length != 0) {
        id clip = YTKACEParseShareMessage(clipData);
        NSString *clipID = YTKACEShareFieldString(
            YTKACEShareUnknownFields(clip), 1);
        if (clipID.length != 0) {
            return [NSURL URLWithString:
                [NSString stringWithFormat:@"https://youtube.com/clip/%@",
                                                   clipID]];
        }
    }
    NSString *channelID = YTKACEShareFieldString(fields, 3);
    if (channelID.length != 0) {
        return [NSURL URLWithString:
            [NSString stringWithFormat:@"https://youtube.com/channel/%@",
                                               channelID]];
    }
    NSString *playlistID = YTKACEShareFieldString(fields, 2);
    if (playlistID.length != 0) {
        NSString *suffix = ([playlistID hasPrefix:@"PL"] ||
                            [playlistID hasPrefix:@"FL"])
            ? @"" : @"&playnext=1";
        return [NSURL URLWithString:
            [NSString stringWithFormat:@"https://youtube.com/playlist?list=%@%@",
                                               playlistID, suffix]];
    }
    NSString *videoID = YTKACEShareFieldString(fields, 1);
    if (videoID.length != 0) {
        return [NSURL URLWithString:
            [NSString stringWithFormat:@"https://youtube.com/watch?v=%@",
                                               videoID]];
    }
    return nil;
}

static NSArray<NSData *> *YTKACEShareLengthDelimitedValues(id field) {
    NSMutableArray<NSData *> *result = [NSMutableArray array];
    for (NSString *selectorName in @[@"lengthDelimitedList",
                                     @"lengthDelimited"]) {
        id value = YTKACEShareValue(field, selectorName);
        if ([value isKindOfClass:NSData.class]) {
            [result addObject:value];
        } else if ([value isKindOfClass:NSArray.class]) {
            for (id item in value) {
                if ([item isKindOfClass:NSData.class]) [result addObject:item];
            }
        }
    }
    return result;
}

static NSArray *YTKACEShareFieldsArray(id unknown) {
    id fields = YTKACEShareValue(unknown, @"fields");
    if ([fields isKindOfClass:NSArray.class]) return fields;
    return [unknown isKindOfClass:NSArray.class] ? unknown : @[];
}

static NSURL *YTKACEShareRecursiveURL(id message, NSUInteger depth) {
    if (message == nil || depth > 4) return nil;
    id unknown = YTKACEShareUnknownFields(message);
    NSURL *URL = YTKACEShareURL(unknown);
    if (URL != nil) return URL;

    for (id field in YTKACEShareFieldsArray(unknown)) {
        for (NSData *data in YTKACEShareLengthDelimitedValues(field)) {
            id nested = YTKACEParseShareMessage(data);
            URL = YTKACEShareRecursiveURL(nested, depth + 1);
            if (URL != nil) return URL;
        }
    }
    return nil;
}

static UIViewController *YTKACESharePresenter(void) {
    Class utils = NSClassFromString(@"YTUIUtils");
    SEL top = NSSelectorFromString(@"topViewControllerForPresenting");
    if ([utils respondsToSelector:top]) {
        UIViewController *native =
            ((id (*)(id, SEL))objc_msgSend)(utils, top);
        if (native != nil) return native;
    }
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
        if (window != nil) break;
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).visibleViewController;
    } else if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }
    return controller;
}

static void YTKACEPresentNativeShare(NSURL *URL) {
    if (URL == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = YTKACESharePresenter();
        if (presenter == nil) return;
        UIActivityViewController *sheet =
            [[UIActivityViewController alloc] initWithActivityItems:@[URL]
                                              applicationActivities:nil];
        sheet.excludedActivityTypes = @[
            UIActivityTypeAssignToContact,
            UIActivityTypePrint
        ];
        UIPopoverPresentationController *popover = sheet.popoverPresentationController;
        if (popover != nil) {
            popover.sourceView = presenter.view;
            popover.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds),
                CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
            popover.permittedArrowDirections = 0;
        }
        [presenter presentViewController:sheet animated:YES completion:nil];
    });
}

static void YTKACEShareButtonSendAction(UIControl *receiver, SEL selector,
                                        SEL action, id target, UIEvent *event) {
    NSString *identifier = receiver.accessibilityIdentifier.lowercaseString;
    if (YTKACEFeatureEnabled(@"kEnableNativeShare") &&
        [identifier containsString:@"share.button"]) {
        NSString *videoID = YTKACELastVideoID();
        if (videoID.length != 0) {
            NSURL *URL = [NSURL URLWithString:[NSString stringWithFormat:
                @"https://youtube.com/watch?v=%@", videoID]];
            YTKACEPresentNativeShare(URL);
            return;
        }
    }
    if (OriginalShareButtonSendAction != NULL) {
        ((void (*)(id, SEL, SEL, id, id))OriginalShareButtonSendAction)(
            receiver, selector, action, target, event);
    }
}

static void YTKACEShowShareSheet(id receiver, SEL selector,
                                 id context, id handler) {
    BOOL enabled = YTKACEFeatureEnabled(@"kEnableNativeShare");
    BOOL hasOnAppear = YTKACEShareBool(receiver, @"hasOnAppear");
    if (!enabled || !hasOnAppear) {
        if (OriginalShowShareSheet != NULL) {
            ((void (*)(id, SEL, id, id))OriginalShowShareSheet)(
                receiver, selector, context, handler);
        }
        return;
    }
    id onAppear = YTKACEShareValue(receiver, @"onAppear");
    Class rootClass = NSClassFromString(@"YTIInnertubeCommandExtensionRoot");
    Class updateClass = NSClassFromString(@"YTIUpdateShareSheetCommand");
    SEL rootSelector = NSSelectorFromString(@"innertubeCommand");
    SEL updateSelector = NSSelectorFromString(@"updateShareSheetCommand");
    id rootDescriptor = [rootClass respondsToSelector:rootSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(rootClass, rootSelector) : nil;
    id updateDescriptor = [updateClass respondsToSelector:updateSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(updateClass, updateSelector) : nil;
    id command = YTKACEShareExtension(onAppear, rootDescriptor);
    id update = YTKACEShareExtension(command, updateDescriptor);
    NSString *serialized = YTKACEShareValue(update, @"serializedShareEntity");
    if (serialized.length == 0) {
        serialized = YTKACESerializedShareEntity(receiver, onAppear, context);
    }
    Class messageClass = NSClassFromString(@"GPBMessage");
    SEL deserialize = NSSelectorFromString(@"deserializeFromString:");
    id message = (serialized.length != 0 &&
                  [messageClass respondsToSelector:deserialize])
        ? ((id (*)(id, SEL, id))objc_msgSend)(
            messageClass, deserialize, serialized) : nil;
    NSURL *URL = YTKACEShareRecursiveURL(message, 0);
    if (URL == nil) {
        NSString *videoID = YTKACELastVideoID();
        if (videoID.length != 0) {
            URL = [NSURL URLWithString:[NSString stringWithFormat:
                @"https://youtube.com/watch?v=%@", videoID]];
        }
    }
    if (URL == nil) {
        if (OriginalShowShareSheet != NULL) {
            ((void (*)(id, SEL, id, id))OriginalShowShareSheet)(
                receiver, selector, context, handler);
        }
        return;
    }
    YTKACEPresentNativeShare(URL);
}

void YTKACEInstallNativeShareHooks(void) {
    YTKACEInstallInstanceHook(
        @"ELMPBShowActionSheetCommand",
        @"executeWithCommandContext:handler:",
        (IMP)YTKACEShowShareSheet,
        &OriginalShowShareSheet);
    YTKACEInstallInstanceHook(@"YTQTMButton", @"sendAction:to:forEvent:",
                              (IMP)YTKACEShareButtonSendAction,
                              &OriginalShareButtonSendAction);
}
