#import "DownloadCoordinator.h"
#import "DownloadLog.h"
#import "DownloadProgressView.h"
#import "FFmpegMuxer.h"
#import "SABRDownloader.h"
#import "StreamResolver.h"
#import "../../Runtime/Preferences.h"
#import "../../Settings/YTKACEDownloadsController.h"
#import "../../Settings/YTKACERootOptionsController.h"
#import "../../UI/Assets.h"
#import "../../UI/Notice.h"

#import <AVKit/AVKit.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface YTKACEDownloadJob : NSObject
@property(nonatomic, strong) NSURLSessionDownloadTask *task;
@property(nonatomic, strong) YTKACESABRTask *sabrTask;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *author;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, copy) NSString *category;
@property(nonatomic, copy) NSString *extension;
@property(nonatomic, strong) NSURL *thumbnailURL;
@property(nonatomic, strong) id playerResponse;
@property(nonatomic, strong) YTKACEStreamOption *videoOption;
@property(nonatomic, strong) YTKACEStreamOption *audioOption;
@property(nonatomic, assign) BOOL audioOnly;
@property(nonatomic, assign) NSInteger fallbackCount;
@property(nonatomic, assign) int64_t audioBytes;
@property(nonatomic, assign) int64_t videoBytes;
@property(nonatomic, strong, nullable) NSURL *savedURL;
@end

static const void *YTKACEShortsFullscreenKey = &YTKACEShortsFullscreenKey;
static const void *YTKACEShortsFullscreenAlphaKey =
    &YTKACEShortsFullscreenAlphaKey;
static NSInteger const YTKACEShortsDownloadButtonTag = 0x59544B44;

static BOOL YTKACEContainsShortsDownloadButton(UIView *view) {
    if (view.tag == YTKACEShortsDownloadButtonTag) return YES;
    for (UIView *subview in view.subviews) {
        if (YTKACEContainsShortsDownloadButton(subview)) return YES;
    }
    return NO;
}

static void YTKACESetShortsOverlayFullscreen(UIView *overlay,
                                              BOOL fullscreen) {
    for (UIView *subview in overlay.subviews) {
        if (YTKACEContainsShortsDownloadButton(subview)) continue;
        if (fullscreen) {
            if (objc_getAssociatedObject(
                    subview, YTKACEShortsFullscreenAlphaKey) == nil) {
                objc_setAssociatedObject(subview,
                    YTKACEShortsFullscreenAlphaKey, @(subview.alpha),
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            subview.alpha = 0.0;
        } else {
            NSNumber *alpha = objc_getAssociatedObject(
                subview, YTKACEShortsFullscreenAlphaKey);
            if (alpha != nil) {
                subview.alpha = alpha.doubleValue;
                objc_setAssociatedObject(subview,
                    YTKACEShortsFullscreenAlphaKey, nil,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

@implementation YTKACEDownloadJob
@end

@interface YTKACEDownloadCoordinator () <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, YTKACEDownloadJob *> *jobs;
@property(nonatomic, strong) NSMutableDictionary<NSString *, YTKACEDownloadJob *> *activeJobs;
@property(nonatomic, weak) UIView *downloadSourceView;
- (void)showAudioLanguagesForVideo:(nullable YTKACEStreamOption *)videoOption
                         audioOnly:(BOOL)audioOnly
                          category:(NSString *)category;
- (void)beginSABRDownloadVideo:(nullable YTKACEStreamOption *)videoOption
                         audio:(YTKACEStreamOption *)audioOption
                     audioOnly:(BOOL)audioOnly
                      category:(NSString *)category;
- (void)mergeVideoURL:(NSURL *)videoURL audioURL:(NSURL *)audioURL
                   job:(YTKACEDownloadJob *)job;
- (void)saveCompletedURL:(NSURL *)URL job:(YTKACEDownloadJob *)job
                extension:(NSString *)extension;
- (void)startSABRJob:(YTKACEDownloadJob *)job;
- (nullable YTKACEStreamOption *)fallbackVideoForJob:(YTKACEDownloadJob *)job;
- (NSString *)safeFilename:(NSString *)filename;
- (NSString *)failureMessageForError:(nullable NSError *)error
                                  job:(nullable YTKACEDownloadJob *)job;
@end

@implementation YTKACEDownloadCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACEDownloadCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACEDownloadCoordinator new];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jobs = [NSMutableDictionary dictionary];
        _activeJobs = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *configuration =
            NSURLSessionConfiguration.defaultSessionConfiguration;
        configuration.timeoutIntervalForRequest = 30.0;
        configuration.timeoutIntervalForResource = 60.0 * 60.0;
        NSOperationQueue *queue = [NSOperationQueue new];
        queue.maxConcurrentOperationCount = 3;
        _session = [NSURLSession sessionWithConfiguration:configuration
                                                 delegate:self
                                            delegateQueue:queue];
        __weak YTKACEDownloadCoordinator *weakSelf = self;
        YTKACEDownloadProgressView.sharedView.cancelHandler = ^(NSString *identifier) {
            YTKACEDownloadJob *job = weakSelf.activeJobs[identifier];
            [job.sabrTask cancel];
        };
    }
    return self;
}

- (UIViewController *)topViewController {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).visibleViewController;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }
    return controller;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    NSString *notice = title.length != 0 && message.length != 0
        ? [NSString stringWithFormat:@"%@\n%@", title, message]
        : (title.length != 0 ? title : message);
    [self showCompactNotice:notice];
}

- (NSString *)failureMessageForError:(NSError *)error
                                  job:(YTKACEDownloadJob *)job {
    NSString *detail = error.localizedDescription ?: @"The download did not complete.";
    if (error.code == NSURLErrorCancelled) return @"The download was cancelled.";
    if ([error.domain isEqualToString:@"YTKACESABR"]) {
        switch (error.code) {
            case 1:
            case 2:
                return @"YouTube did not provide a usable download session. Play the video briefly, then retry.";
            case 4:
                return @"YouTube rejected the stream request. Reopen the video, play it briefly, and retry.";
            case 5:
            case 8:
                return @"The stream stopped before it was complete. Retry once, or choose a lower quality.";
            case 6:
                return @"YouTube did not authorize this format for the current device. Choose another quality.";
            case 9:
                return @"YouTube could not refresh this high-resolution stream. Play the video briefly, then retry.";
            case 10:
                return @"YouTube has not prepared this video yet. Tap Play for a moment, then retry.";
            default:
                break;
        }
    }
    if ([error.domain isEqualToString:@"YTKACEFFmpeg"]) {
        NSString *quality = job.videoOption.qualityLabel.length != 0
            ? job.videoOption.qualityLabel : @"selected quality";
        return [NSString stringWithFormat:
            @"%@ downloaded, but its video and audio could not be merged. Try another %@ format.\n%@",
            quality, quality, detail];
    }
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        if (error.code == NSURLErrorNotConnectedToInternet) {
            return @"The network connection is offline. Reconnect and retry.";
        }
        if (error.code == NSURLErrorTimedOut) {
            return @"The download timed out. Retry on a stable connection.";
        }
    }
    return detail;
}

- (id)findPlayerResponseFromObject:(id)object
                           visited:(NSHashTable *)visited
                             depth:(NSUInteger)depth {
    if (object == nil || depth > 9 || [visited containsObject:object]) {
        return nil;
    }
    [visited addObject:object];
    SEL dataSelector = NSSelectorFromString(@"playerData");
    if ([object respondsToSelector:dataSelector]) {
        id data = ((id (*)(id, SEL))objc_msgSend)(object, dataSelector);
        if (data != nil) {
            return object;
        }
    }
    for (NSString *name in @[@"contentPlayerResponse", @"playerResponse",
                              @"_youtubeiOSPlayerViewController",
                              @"parentViewController", @"eventsDelegate",
                              @"parentResponder", @"playbackController"]) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) {
            continue;
        }
        id related = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        id response = [self findPlayerResponseFromObject:related
                                                 visited:visited
                                                   depth:depth + 1];
        if (response != nil) {
            return response;
        }
    }
    if ([object isKindOfClass:UIResponder.class]) {
        return [self findPlayerResponseFromObject:
            ((UIResponder *)object).nextResponder visited:visited depth:depth + 1];
    }
    return nil;
}

- (id)playerResponseFromView:(UIView *)view {
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsObjectPointerPersonality];
    return [self findPlayerResponseFromObject:view visited:visited depth:0];
}

- (id)videoOverlayControllerFromView:(UIView *)view {
    UIResponder *current = view;
    Class overlayClass = NSClassFromString(
        @"YTMainAppVideoPlayerOverlayViewController");
    for (NSUInteger depth = 0; current != nil && depth < 24; depth++) {
        if (overlayClass != Nil && [current isKindOfClass:overlayClass]) {
            return current;
        }
        current = current.nextResponder;
    }
    return nil;
}

- (id)videoPlayerResponseFromView:(UIView *)view {
    id overlay = [self videoOverlayControllerFromView:view];
    SEL parentSelector = NSSelectorFromString(@"parentViewController");
    id playerController = [overlay respondsToSelector:parentSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(overlay, parentSelector) : nil;
    for (NSString *name in @[@"contentPlayerResponse", @"playerResponse"]) {
        SEL selector = NSSelectorFromString(name);
        if ([playerController respondsToSelector:selector]) {
            id response = ((id (*)(id, SEL))objc_msgSend)(playerController, selector);
            if (response != nil) {
                return response;
            }
        }
    }
    return [self playerResponseFromView:view];
}

- (UIImage *)menuIcon:(NSString *)symbol {
    NSDictionary<NSString *, NSString *> *assets = @{
        @"play": @"ig_icon_play_outline_24_Normal",
        @"music.note": @"yt_outline_music_24pt",
        @"play.circle": @"play_arrow_circle_24pt_3x_Normal",
        @"photo": @"youtube_outline_image_24pt",
        @"doc.on.doc": @"yt_outline_copy_24pt",
        @"chevron.right": @"yt_outline_chevron_right_24pt_2x_Normal",
        @"arrow.up.left.and.arrow.down.right": @"ic_fullscreen_3x_Normal",
        @"arrow.down.right.and.arrow.up.left": @"ic_fullscreen_exit_3x_Normal",
        @"ytkace.system": @"ig_icon_play_outline_24_Normal",
        @"ytkace.infuse": @"play.tv",
        @"ytkace.vlc": @"play.circle"
    };
    UIImage *image = YTKACEAssetImage(assets[symbol] ?: @"", symbol);
    if (image != nil) {
        if ([symbol isEqualToString:@"ytkace.infuse"])
            return [[UIImage systemImageNamed:@"play.tv"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if ([symbol isEqualToString:@"ytkace.vlc"])
            return [[UIImage systemImageNamed:@"play.circle"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                        weight:UIImageSymbolWeightRegular];
    return [[UIImage systemImageNamed:symbol withConfiguration:configuration]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)presentNativeSheetWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                         sourceView:(UIView *)sourceView
                            actions:(NSArray<NSDictionary *> *)actions {
    id presenter = [self topViewController];
    UIResponder *responder = sourceView;
    id sourceController = nil;
    for (NSUInteger depth = 0; responder != nil && depth < 20; depth++) {
        if ([responder isKindOfClass:UIViewController.class]) {
            sourceController = (UIViewController *)responder;
        }
        SEL eventsSelector = NSSelectorFromString(@"eventsDelegate");
        if ([responder respondsToSelector:eventsSelector]) {
            id events = ((id (*)(id, SEL))objc_msgSend)(responder, eventsSelector);
            if (events != nil) {
                sourceController = events;
                break;
            }
        }
        responder = responder.nextResponder;
    }
    presenter = sourceController ?: presenter;
    Class sheetClass = NSClassFromString(@"YTDefaultSheetController");
    Class actionClass = NSClassFromString(@"YTActionSheetAction");
    SEL makeSheet = NSSelectorFromString(
        @"sheetControllerWithMessage:subMessage:delegate:parentResponder:");
    SEL makeDetailed = NSSelectorFromString(
        @"actionWithTitle:iconImage:secondaryIconImage:accessibilityIdentifier:handler:");
    SEL makeSimple = NSSelectorFromString(@"actionWithTitle:iconImage:style:handler:");
    if (sheetClass != Nil && actionClass != Nil &&
        [sheetClass respondsToSelector:makeSheet]) {
        id sheet = nil;
        SEL makePlain = NSSelectorFromString(@"sheetControllerWithParentResponder:");
        if (title.length == 0 && subtitle.length == 0 &&
            [sheetClass respondsToSelector:makePlain]) {
            sheet = ((id (*)(id, SEL, id))objc_msgSend)(
                sheetClass, makePlain, nil);
        } else {
            sheet = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
                sheetClass, makeSheet, title, subtitle, nil, nil);
        }
        if (title.length != 0 || subtitle.length != 0) {
            @try {
                id header = [sheet valueForKey:@"_headerView"];
                SEL divider = NSSelectorFromString(@"showHeaderDivider");
                if ([header respondsToSelector:divider]) {
                    ((void (*)(id, SEL))objc_msgSend)(header, divider);
                }
            } @catch (__unused NSException *exception) {
            }
        }
        for (NSDictionary *item in actions) {
            dispatch_block_t handler = item[@"handler"];
            UIImage *icon = item[@"icon"];
            UIImage *secondary = item[@"secondary"];
            id action = nil;
            if (secondary != nil && [actionClass respondsToSelector:makeDetailed]) {
                action = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
                    actionClass, makeDetailed, item[@"title"], icon, secondary, nil,
                    handler);
            } else if ([actionClass respondsToSelector:makeSimple]) {
                action = ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)(
                    actionClass, makeSimple, item[@"title"], icon, 0, handler);
            }
            if (action != nil && [sheet respondsToSelector:NSSelectorFromString(@"addAction:")]) {
                ((void (*)(id, SEL, id))objc_msgSend)(
                    sheet, NSSelectorFromString(@"addAction:"), action);
            }
        }
        SEL presentFromView =
            NSSelectorFromString(@"presentFromView:animated:completion:");
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
            sourceView != nil && [sheet respondsToSelector:presentFromView]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, presentFromView, sourceView, YES, nil);
        } else if ([sheet respondsToSelector:
                    NSSelectorFromString(@"presentFromViewController:animated:completion:")]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, NSSelectorFromString(@"presentFromViewController:animated:completion:"),
                presenter, YES, nil);
        }
        return;
    }
    [self showCompactNotice:@"YouTube menu unavailable"];
}

- (NSDictionary *)sheetAction:(NSString *)title
                          icon:(NSString *)icon
                     secondary:(UIImage *)secondary
                       handler:(dispatch_block_t)handler {
    NSMutableDictionary *item = [@{
        @"title": title,
        @"icon": [self menuIcon:icon] ?: [UIImage new],
        @"handler": [handler copy]
    } mutableCopy];
    if (secondary != nil) {
        item[@"secondary"] = secondary;
    }
    return item;
}

- (void)showDownloadMenu {
    [self showDownloadMenuFromButton:nil];
}

- (void)showDownloadMenuFromButton:(UIButton *)button {
    if (!YTKACEFeatureEnabled(YTKACEDownloadKey)) {
        return;
    }
    id currentResponse = [self videoPlayerResponseFromView:button];
    if (currentResponse != nil) {
        self.playerResponse = currentResponse;
    }
    if (self.playerResponse == nil) {
        [self showAlertWithTitle:@"YTKACE" message:@"No active video was found."];
        return;
    }
    self.downloadSourceView = button;

    __weak YTKACEDownloadCoordinator *weakSelf = self;
    UIImage *chevron = [self menuIcon:@"chevron.right"];
    NSArray *actions = @[
        [self sheetAction:@"Download Video" icon:@"play"
            secondary:chevron handler:^{ [weakSelf startVideoDownloadForCategory:@"Video"]; }],
        [self sheetAction:@"Download Audio" icon:@"music.note"
            secondary:chevron handler:^{ [weakSelf startAudioDownload]; }],
        [self sheetAction:@"Play in External Player" icon:@"play.circle"
            secondary:chevron handler:^{ [weakSelf showExternalPlayerMenuFromView:button]; }],
        [self sheetAction:@"Save Image" icon:@"photo"
            secondary:nil handler:^{ [weakSelf saveThumbnail]; }],
        [self sheetAction:@"Copy Information" icon:@"doc.on.doc"
            secondary:chevron handler:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakSelf showCopyInformationMenuFromView:button];
                    });
            }]
    ];
    [self presentNativeSheetWithTitle:
        [YTKACEStreamResolver authorFromPlayerResponse:self.playerResponse]
        subtitle:[YTKACEStreamResolver titleFromPlayerResponse:self.playerResponse]
        sourceView:button actions:actions];
}

- (void)showCompactNotice:(NSString *)message {
    YTKACEShowNotice(message);
}

- (void)showCopyInformationMenuFromView:(UIView *)sourceView {
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    NSArray *actions = @[
        [self sheetAction:@"Copy Title" icon:@"textformat"
            secondary:nil handler:^{
                UIPasteboard.generalPasteboard.string =
                    [YTKACEStreamResolver titleFromPlayerResponse:weakSelf.playerResponse];
                [weakSelf showCompactNotice:@"Title copied"];
            }],
        [self sheetAction:@"Copy Description" icon:@"line.3.horizontal"
            secondary:nil handler:^{
                NSString *description = [YTKACEStreamResolver
                    descriptionFromPlayerResponse:weakSelf.playerResponse];
                if (description.length == 0) {
                    [weakSelf showCompactNotice:@"No description found"];
                } else {
                    UIPasteboard.generalPasteboard.string = description;
                    [weakSelf showCompactNotice:@"Description copied"];
                }
            }]
    ];
    [self presentNativeSheetWithTitle:nil subtitle:nil
        sourceView:sourceView actions:actions];
}

- (void)showExternalPlayerMenuFromView:(UIView *)sourceView {
    YTKACEStreamOption *option =
        [YTKACEStreamResolver bestPiPVideoFromPlayerResponse:self.playerResponse];
    if (option.URL == nil) {
        [self showAlertWithTitle:@"External Player"
                         message:@"No playable stream is available."];
        return;
    }
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    NSString *escaped = [option.URL.absoluteString
        stringByAddingPercentEncodingWithAllowedCharacters:
            NSCharacterSet.URLQueryAllowedCharacterSet];
    NSArray *actions = @[
        [self sheetAction:@"System Player" icon:@"ytkace.system"
            secondary:nil handler:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakSelf playInSystemPlayer:option.URL sourceView:sourceView];
                    });
            }],
        [self sheetAction:@"Infuse" icon:@"ytkace.infuse"
            secondary:nil handler:^{
                NSURL *url = [NSURL URLWithString:[NSString
                    stringWithFormat:@"infuse://x-callback-url/play?url=%@",
                    escaped ?: @""]];
                [UIApplication.sharedApplication openURL:url options:@{}
                    completionHandler:^(BOOL success) {
                        if (!success) {
                            [weakSelf showAlertWithTitle:@"Infuse"
                                message:@"Infuse is not installed."];
                        }
                    }];
            }],
        [self sheetAction:@"VLC" icon:@"ytkace.vlc"
            secondary:nil handler:^{
                NSURL *url = [NSURL URLWithString:[NSString
                    stringWithFormat:@"vlc-x-callback://x-callback-url/stream?url=%@",
                    escaped ?: @""]];
                [UIApplication.sharedApplication openURL:url options:@{}
                    completionHandler:^(BOOL success) {
                        if (!success) {
                            [weakSelf showAlertWithTitle:@"VLC"
                                message:@"VLC is not installed."];
                        }
                    }];
            }]
    ];
    [self presentNativeSheetWithTitle:@"External Player" subtitle:nil
        sourceView:sourceView actions:actions];
}

- (double)mediaTimeFromObject:(id)object {
    for (NSString *name in @[@"currentVideoMediaTime", @"currentVideoTime",
                              @"currentMediaTime", @"mediaTime"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([object class], selector);
        if (method == NULL) {
            continue;
        }
        char type[16] = {};
        method_getReturnType(method, type, sizeof(type));
        if (strcmp(type, @encode(double)) == 0) {
            return ((double (*)(id, SEL))objc_msgSend)(object, selector);
        }
        if (strcmp(type, @encode(float)) == 0) {
            return ((float (*)(id, SEL))objc_msgSend)(object, selector);
        }
    }
    return 0.0;
}

- (void)playInSystemPlayer:(NSURL *)URL sourceView:(UIView *)sourceView {
    if (URL == nil) {
        return;
    }
    double mediaTime = 0.0;
    UIViewController *presenter = nil;
    UIResponder *current = sourceView;
    for (NSUInteger depth = 0; current != nil && depth < 20; depth++) {
        if (mediaTime <= 0.0) {
            mediaTime = [self mediaTimeFromObject:current];
        }
        for (NSString *name in @[@"pauseVideo", @"pausePlayback", @"pause"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getInstanceMethod([current class], selector);
            if (method != NULL && method_getNumberOfArguments(method) == 2) {
                ((void (*)(id, SEL))objc_msgSend)(current, selector);
                break;
            }
        }
        SEL eventsSelector = NSSelectorFromString(@"eventsDelegate");
        if ([current respondsToSelector:eventsSelector]) {
            id events = ((id (*)(id, SEL))objc_msgSend)(current, eventsSelector);
            if (mediaTime <= 0.0) {
                mediaTime = [self mediaTimeFromObject:events];
                SEL parentSelector = NSSelectorFromString(@"parentResponder");
                if ([events respondsToSelector:parentSelector]) {
                    id parent = ((id (*)(id, SEL))objc_msgSend)(events, parentSelector);
                    mediaTime = MAX(mediaTime, [self mediaTimeFromObject:parent]);
                }
            }
            if ([events isKindOfClass:UIViewController.class]) {
                presenter = events;
            }
        }
        if (presenter == nil && [current isKindOfClass:UIViewController.class]) {
            presenter = (UIViewController *)current;
        }
        current = current.nextResponder;
    }
    presenter = presenter ?: [self topViewController];
    AVPlayer *player = [AVPlayer playerWithURL:URL];
    AVPlayerViewController *controller = [AVPlayerViewController new];
    controller.player = player;
    controller.showsPlaybackControls = YES;
    controller.allowsPictureInPicturePlayback = YES;
    if (mediaTime > 0.0) {
        [player seekToTime:CMTimeMakeWithSeconds(mediaTime, NSEC_PER_SEC)
           toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    [presenter presentViewController:controller animated:YES completion:^{
        [player play];
    }];
}

- (void)saveThumbnail {
    NSURL *url = [YTKACEStreamResolver thumbnailURLFromPlayerResponse:self.playerResponse];
    if (url == nil) {
        [self showAlertWithTitle:@"Save Image" message:@"No thumbnail is available."];
        return;
    }
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            (void)response;
            UIImage *image = error == nil ? [UIImage imageWithData:data] : nil;
            if (image == nil) {
                [weakSelf showAlertWithTitle:@"Save Image"
                    message:error.localizedDescription ?: @"The image could not be loaded."];
                return;
            }
            [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            } completionHandler:^(BOOL success, NSError *saveError) {
                if (success) {
                    [weakSelf showCompactNotice:@"Image saved"];
                } else {
                    [weakSelf showAlertWithTitle:@"Save Image"
                        message:saveError.localizedDescription ?:
                            @"The image could not be saved."];
                }
            }];
        }];
    [task resume];
}

- (UIViewController *)shortsControllerFromView:(UIView *)sourceView {
    UIResponder *responder = sourceView.nextResponder;
    UIViewController *controller = nil;
    while (responder != nil) {
        if ([responder isKindOfClass:UIViewController.class]) {
            controller = (UIViewController *)responder;
            break;
        }
        responder = responder.nextResponder;
    }
    Class shortsClass = NSClassFromString(@"YTShortsPlayerViewController");
    while (controller != nil) {
        if (shortsClass != Nil && [controller isKindOfClass:shortsClass]) {
            return controller;
        }
        controller = controller.parentViewController;
    }
    return nil;
}

- (void)toggleShortsFullscreenFromView:(UIView *)sourceView {
    UIViewController *controller = [self shortsControllerFromView:sourceView];
    if (controller != nil) {
            BOOL fullscreen = [objc_getAssociatedObject(
                controller, YTKACEShortsFullscreenKey) boolValue];
            id pivotController = controller.navigationController.parentViewController;
            SEL pivotSelector = NSSelectorFromString(
                fullscreen ? @"showPivotBar" : @"hidePivotBar");
            if ([pivotController respondsToSelector:pivotSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(pivotController, pivotSelector);
            }
            id shortsView = controller.view;
            SEL overlaySelector = NSSelectorFromString(@"playbackOverlay");
            id overlay = [shortsView respondsToSelector:overlaySelector]
                ? ((id (*)(id, SEL))objc_msgSend)(shortsView, overlaySelector) : nil;
            [UIView animateWithDuration:0.3 animations:^{
                if ([overlay isKindOfClass:UIView.class]) {
                    YTKACESetShortsOverlayFullscreen(
                        (UIView *)overlay, !fullscreen);
                }
            }];
            objc_setAssociatedObject(controller, YTKACEShortsFullscreenKey, @(!fullscreen),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (NSNumber *delay in @[@0.05, @0.20]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
                        [controller.view setNeedsLayout];
                        [controller.view layoutIfNeeded];
                    });
            }
            return;
    }
}

- (void)showShortsDownloadMenuFromView:(UIView *)sourceView {
    id currentResponse = [self playerResponseFromView:sourceView];
    if (currentResponse != nil) {
        self.playerResponse = currentResponse;
    }
    if (!YTKACEFeatureEnabled(YTKACEDownloadKey) || self.playerResponse == nil) {
        [self showAlertWithTitle:@"YTKACE" message:@"No active Short was found."];
        return;
    }
    self.downloadSourceView = sourceView;
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    UIImage *chevron = [self menuIcon:@"chevron.right"];
    BOOL autoSkip = YTKACEFeatureEnabled(@"autoSkipShorts");
    UIViewController *shortsController = [self shortsControllerFromView:sourceView];
    BOOL fullscreen = [objc_getAssociatedObject(
        shortsController, YTKACEShortsFullscreenKey) boolValue];
    NSString *fullscreenTitle = fullscreen ? @"Exit Fullscreen" : @"Fullscreen";
    NSString *fullscreenIcon = fullscreen
        ? @"arrow.down.right.and.arrow.up.left"
        : @"arrow.up.left.and.arrow.down.right";
    NSArray *actions = @[
        [self sheetAction:@"Download Video" icon:@"play"
            secondary:chevron handler:^{ [weakSelf startVideoDownloadForCategory:@"Shorts"]; }],
        [self sheetAction:@"Download Audio" icon:@"music.note"
            secondary:chevron handler:^{ [weakSelf startAudioDownload]; }],
        [self sheetAction:fullscreenTitle icon:fullscreenIcon
            secondary:chevron handler:^{
                [weakSelf toggleShortsFullscreenFromView:sourceView];
            }],
        [self sheetAction:@"Auto-Skip" icon:@"forward.end.fill"
            secondary:[self menuIcon:autoSkip ? @"checkmark.square" : @"square"]
            handler:^{ YTKACESetPreference(@"autoSkipShorts", !autoSkip); }]
    ];
    [self presentNativeSheetWithTitle:
        [YTKACEStreamResolver authorFromPlayerResponse:self.playerResponse]
        subtitle:[YTKACEStreamResolver titleFromPlayerResponse:self.playerResponse]
        sourceView:sourceView actions:actions];
}

- (void)startVideoDownloadForCategory:(NSString *)category {
    NSArray<YTKACEStreamOption *> *options =
        [YTKACEStreamResolver videoOptionsFromPlayerResponse:self.playerResponse];
    YTKACEDownloadLog(@"resolver", @"video menu count=%lu category=%@",
        (unsigned long)options.count, category);
    if (options.count == 0) {
        [self showAlertWithTitle:@"Download unavailable"
                         message:@"No compatible video formats were found."];
        return;
    }
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (YTKACEStreamOption *option in options) {
        NSString *size = option.contentLength > 0
            ? [NSByteCountFormatter stringFromByteCount:option.contentLength
                countStyle:NSByteCountFormatterCountStyleFile] : @"Unknown size";
        NSString *title = [NSString stringWithFormat:@"%@ (mp4) · %@",
            option.qualityLabel.length != 0 ? option.qualityLabel : @"Video", size];
        [actions addObject:[self sheetAction:title icon:@"play"
            secondary:nil handler:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [weakSelf showAudioLanguagesForVideo:option audioOnly:NO
                            category:category];
                    });
            }]];
    }
    [self presentNativeSheetWithTitle:@"Video Quality"
        subtitle:[YTKACEStreamResolver titleFromPlayerResponse:self.playerResponse]
        sourceView:self.downloadSourceView actions:actions];
}

- (void)startAudioDownload {
    [self showAudioLanguagesForVideo:nil audioOnly:YES category:@"Audio"];
}

- (void)showAudioLanguagesForVideo:(YTKACEStreamOption *)videoOption
                         audioOnly:(BOOL)audioOnly
                          category:(NSString *)category {
    NSArray<YTKACEStreamOption *> *options =
        [YTKACEStreamResolver audioOptionsFromPlayerResponse:self.playerResponse];
    if (options.count == 0) {
        [self showAlertWithTitle:@"Download unavailable"
                         message:@"No compatible audio formats were found."];
        return;
    }
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (YTKACEStreamOption *option in options) {
        NSString *size = option.contentLength > 0
            ? [NSByteCountFormatter stringFromByteCount:option.contentLength
                countStyle:NSByteCountFormatterCountStyleFile] : @"Unknown size";
        NSString *defaultText = option.isDefaultAudio ? @" (Default)" : @"";
        NSString *title = [NSString stringWithFormat:@"%@%@ · %@",
            option.languageLabel, defaultText, size];
        [actions addObject:[self sheetAction:title icon:@"music.note"
            secondary:nil handler:^{
                [weakSelf beginSABRDownloadVideo:videoOption
                    audio:option audioOnly:audioOnly category:category];
            }]];
    }
    [self presentNativeSheetWithTitle:@"Audio Language"
        subtitle:[YTKACEStreamResolver titleFromPlayerResponse:self.playerResponse]
        sourceView:self.downloadSourceView actions:actions];
}

- (void)beginSABRDownloadVideo:(YTKACEStreamOption *)videoOption
                         audio:(YTKACEStreamOption *)audioOption
                     audioOnly:(BOOL)audioOnly
                      category:(NSString *)category {
    if (videoOption == nil) {
        videoOption = [YTKACEStreamResolver
            videoOptionsFromPlayerResponse:self.playerResponse].firstObject;
    }
    if (videoOption == nil || audioOption == nil) {
        [self showAlertWithTitle:@"Download unavailable"
                         message:@"The selected formats are unavailable."];
        return;
    }
    id response = self.playerResponse;
    YTKACEDownloadJob *job = [YTKACEDownloadJob new];
    job.identifier = NSUUID.UUID.UUIDString;
    job.title = [self safeFilename:
        [YTKACEStreamResolver titleFromPlayerResponse:response]];
    job.author = [YTKACEStreamResolver authorFromPlayerResponse:response];
    job.videoID = [YTKACEStreamResolver videoIDFromPlayerResponse:response] ?: @"";
    job.thumbnailURL = [YTKACEStreamResolver thumbnailURLFromPlayerResponse:response];
    job.category = audioOnly ? @"Audio" : category;
    job.playerResponse = response;
    job.videoOption = videoOption;
    job.audioOption = audioOption;
    job.audioOnly = audioOnly;
    self.activeJobs[job.identifier] = job;
    [YTKACEDownloadProgressView.sharedView beginJob:job.identifier
        title:job.title thumbnailURL:job.thumbnailURL];
    YTKACEDownloadLog(job.identifier,
        @"queued title=%@ author=%@ category=%@ audioOnly=%d active=%lu",
        job.title, job.author, job.category, job.audioOnly,
        (unsigned long)self.activeJobs.count);
    [YTKACEDownloadProgressView.sharedView updateJob:job.identifier
        stage:@"Preparing download" progress:0.0 downloadedBytes:0 totalBytes:0];
    [self startSABRJob:job];
}

- (YTKACEStreamOption *)fallbackVideoForJob:(YTKACEDownloadJob *)job {
    if (job.fallbackCount >= 3) return nil;
    NSArray<YTKACEStreamOption *> *options =
        [YTKACEStreamResolver videoOptionsFromPlayerResponse:job.playerResponse];
    NSInteger currentIndex = NSNotFound;
    for (NSUInteger index = 0; index < options.count; index++) {
        YTKACEStreamOption *option = options[index];
        if (option.itag == job.videoOption.itag &&
            [option.xtags isEqualToString:job.videoOption.xtags]) {
            currentIndex = (NSInteger)index;
            break;
        }
    }
    if (currentIndex == NSNotFound) return nil;
    for (NSUInteger index = (NSUInteger)currentIndex + 1; index < options.count; index++) {
        YTKACEStreamOption *option = options[index];
        if (option.itag != job.videoOption.itag) return option;
    }
    return nil;
}

- (void)startSABRJob:(YTKACEDownloadJob *)job {
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    job.sabrTask = [YTKACESABRDownloader downloadPlayerResponse:job.playerResponse
        videoOption:job.videoOption audioOption:job.audioOption audioOnly:job.audioOnly
        videoID:job.videoID identifier:job.identifier
        progress:^(double audioProgress, double videoProgress,
                   int64_t audioBytes, int64_t videoBytes,
                   NSInteger mediaPhase) {
            job.audioBytes = audioBytes;
            job.videoBytes = videoBytes;
            int64_t audioTotal = MAX((int64_t)job.audioOption.contentLength, 0);
            int64_t videoTotal = job.audioOnly ? 0 :
                MAX((int64_t)job.videoOption.contentLength, 0);
            int64_t downloaded = audioBytes + (job.audioOnly ? 0 : videoBytes);
            int64_t total = audioTotal + videoTotal;
            double transferProgress = 0.0;
            if (total > 0) {
                transferProgress = (double)downloaded / (double)total;
            } else if (job.audioOnly) {
                transferProgress = audioProgress;
            } else {
                transferProgress = audioProgress * 0.08 + videoProgress * 0.92;
            }
            transferProgress = MIN(MAX(transferProgress, 0.0), 1.0);
            NSString *stage = job.audioOnly || mediaPhase == 1
                ? @"Downloading audio" : @"Downloading video";
            [YTKACEDownloadProgressView.sharedView updateJob:job.identifier
                stage:stage progress:transferProgress * 0.95
                downloadedBytes:downloaded totalBytes:total];
        }
        completion:^(NSURL *videoURL, NSURL *audioURL, NSError *error) {
            if (error != nil || audioURL == nil || (!job.audioOnly && videoURL == nil)) {
                YTKACEStreamOption *fallback = nil;
                if ([error.domain isEqualToString:@"YTKACESABR"] &&
                    error.code == 8) {
                    fallback = [weakSelf fallbackVideoForJob:job];
                }
                if (fallback != nil) {
                    NSInteger previous = job.videoOption.itag;
                    job.videoOption = fallback;
                    job.fallbackCount += 1;
                    YTKACEDownloadLog(job.identifier,
                        @"fallback video itag=%ld to=%ld attempt=%ld",
                        (long)previous, (long)fallback.itag,
                        (long)job.fallbackCount);
                    [YTKACEDownloadProgressView.sharedView updateJob:job.identifier
                        stage:@"Retrying lower quality" progress:0.0
                        downloadedBytes:0 totalBytes:job.audioOption.contentLength +
                            (job.audioOnly ? 0 : job.videoOption.contentLength)];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [weakSelf startSABRJob:job];
                        });
                    return;
                }
                NSString *message = error.code == NSURLErrorCancelled
                    ? @"Cancelled" : @"Failed";
                [YTKACEDownloadProgressView.sharedView finishJob:job.identifier
                    success:NO message:message];
                YTKACEDownloadLog(job.identifier, @"job failed error=%@",
                    error.localizedDescription ?: @"incomplete stream");
                if (error.code != NSURLErrorCancelled) {
                    [weakSelf showAlertWithTitle:@"Download failed"
                        message:[weakSelf failureMessageForError:error job:job]];
                }
                [weakSelf.activeJobs removeObjectForKey:job.identifier];
                return;
            }
            if (job.audioOnly) {
                if (videoURL != nil) {
                    [NSFileManager.defaultManager removeItemAtURL:videoURL error:nil];
                }
                [YTKACEDownloadProgressView.sharedView updateJob:job.identifier
                    stage:@"Finalizing" progress:0.96
                    downloadedBytes:job.audioBytes totalBytes:job.audioBytes];
                NSURL *output = [audioURL.URLByDeletingLastPathComponent
                    URLByAppendingPathComponent:@"final.m4a"];
                YTKACEDownloadLog(job.identifier, @"audio remux start");
                [YTKACEFFmpegMuxer remuxAudioURL:audioURL outputURL:output
                    completion:^(NSError *remuxError) {
                        if (remuxError != nil) {
                            [YTKACEDownloadProgressView.sharedView
                                finishJob:job.identifier success:NO message:@"Failed"];
                            YTKACEDownloadLog(job.identifier,
                                @"audio remux failed error=%@",
                                remuxError.localizedDescription);
                            [NSFileManager.defaultManager
                                removeItemAtURL:audioURL.URLByDeletingLastPathComponent
                                error:nil];
                            [weakSelf showAlertWithTitle:@"Download failed"
                                message:[weakSelf failureMessageForError:remuxError
                                    job:job]];
                            [weakSelf.activeJobs removeObjectForKey:job.identifier];
                            return;
                        }
                        [NSFileManager.defaultManager removeItemAtURL:audioURL error:nil];
                        YTKACEDownloadLog(job.identifier, @"audio remux complete");
                        [weakSelf saveCompletedURL:output job:job extension:@"m4a"];
                    }];
                return;
            }
            [YTKACEDownloadProgressView.sharedView updateJob:job.identifier
                stage:@"Merging" progress:0.96
                downloadedBytes:job.audioBytes + job.videoBytes
                totalBytes:job.audioBytes + job.videoBytes];
            [weakSelf mergeVideoURL:videoURL audioURL:audioURL job:job];
        }];
}

- (NSString *)safeFilename:(NSString *)filename {
    NSCharacterSet *invalid =
        [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    NSArray<NSString *> *parts = [filename componentsSeparatedByCharactersInSet:invalid];
    NSString *safe = [parts componentsJoinedByString:@"-"];
    if (safe.length > 120) {
        safe = [safe substringToIndex:120];
    }
    return safe.length == 0 ? @"YouTube Video" : safe;
}

- (NSURL *)destinationForTitle:(NSString *)title
                       category:(NSString *)category
                      extension:(NSString *)extension {
    NSURL *downloads = [YTKACEApplicationSupportDirectory()
        URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    NSURL *directory = [downloads URLByAppendingPathComponent:category isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *destination = [directory URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.%@", title, extension]];
    NSInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
        destination = [directory URLByAppendingPathComponent:
            [NSString stringWithFormat:@"%@ %ld.%@", title, (long)suffix++, extension]];
    }
    return destination;
}

- (void)writeMetadataForJob:(YTKACEDownloadJob *)job
                destination:(NSURL *)destination {
    NSURL *base = [destination URLByDeletingPathExtension];
    if (job.thumbnailURL == nil) return;
    NSURL *imageURL = [base URLByAppendingPathExtension:@"jpg"];
    NSString *identifier = job.identifier;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession
        dataTaskWithURL:job.thumbnailURL completionHandler:^(NSData *data,
            NSURLResponse *response, NSError *error) {
        (void)response;
        if (error == nil && data.length != 0) {
            UIImage *image = [UIImage imageWithData:data];
            NSData *artwork = image == nil ? data : UIImageJPEGRepresentation(image, 0.9);
            [artwork writeToURL:imageURL atomically:YES];
            YTKACEDownloadLog(identifier, @"thumbnail saved bytes=%lu",
                (unsigned long)artwork.length);
            [YTKACEFFmpegMuxer embedArtworkData:artwork mediaURL:destination
                completion:^(NSError *embedError) {
                    if (embedError == nil) {
                        [NSFileManager.defaultManager removeItemAtURL:imageURL error:nil];
                        YTKACEDownloadLog(identifier, @"thumbnail embedded");
                    } else {
                        YTKACEDownloadLog(identifier, @"thumbnail sidecar kept error=%@",
                            embedError.localizedDescription);
                    }
                    [NSNotificationCenter.defaultCenter
                        postNotificationName:@"YTKACEDownloadLibraryChanged" object:nil];
                }];
        } else {
            YTKACEDownloadLog(identifier, @"thumbnail failed error=%@",
                error.localizedDescription ?: @"empty response");
        }
    }];
    [task resume];
}

- (void)saveCompletedURL:(NSURL *)URL
                      job:(YTKACEDownloadJob *)job
                extension:(NSString *)extension {
    NSURL *destination = [self destinationForTitle:job.title
        category:job.category extension:extension];
    NSError *error = nil;
    [NSFileManager.defaultManager moveItemAtURL:URL toURL:destination error:&error];
    NSURL *temporaryDirectory = URL.URLByDeletingLastPathComponent;
    [NSFileManager.defaultManager removeItemAtURL:temporaryDirectory error:nil];
    if (error != nil) {
        [YTKACEDownloadProgressView.sharedView finishJob:job.identifier
            success:NO message:@"Failed"];
        YTKACEDownloadLog(job.identifier, @"save failed error=%@",
            error.localizedDescription);
        [self showAlertWithTitle:@"Save failed"
            message:[self failureMessageForError:error job:job]];
    } else {
        [self writeMetadataForJob:job destination:destination];
        [YTKACEDownloadProgressView.sharedView finishJob:job.identifier
            success:YES message:@"Complete"];
        YTKACEDownloadLog(job.identifier, @"saved path=%@", destination.path);
        [NSNotificationCenter.defaultCenter
            postNotificationName:@"YTKACEDownloadLibraryChanged" object:nil];
    }
    [self.activeJobs removeObjectForKey:job.identifier];
}

- (void)mergeVideoURL:(NSURL *)videoURL
              audioURL:(NSURL *)audioURL
                   job:(YTKACEDownloadJob *)job {
    NSURL *output = [videoURL.URLByDeletingLastPathComponent
        URLByAppendingPathComponent:@"merged.mp4"];
    YTKACEDownloadLog(job.identifier, @"merge start video=%@ audio=%@",
        videoURL.lastPathComponent, audioURL.lastPathComponent);
    __weak YTKACEDownloadCoordinator *weakSelf = self;
    [YTKACEFFmpegMuxer remuxVideoURL:videoURL audioURL:audioURL
        outputURL:output completion:^(NSError *error) {
            if (error != nil) {
                [YTKACEDownloadProgressView.sharedView finishJob:job.identifier
                    success:NO message:@"Failed"];
                YTKACEDownloadLog(job.identifier, @"merge failed error=%@",
                    error.localizedDescription);
                [weakSelf showAlertWithTitle:@"Merge failed"
                    message:[weakSelf failureMessageForError:error job:job]];
                [NSFileManager.defaultManager removeItemAtURL:output error:nil];
                [NSFileManager.defaultManager
                    removeItemAtURL:videoURL.URLByDeletingLastPathComponent error:nil];
                [weakSelf.activeJobs removeObjectForKey:job.identifier];
                return;
            }
            [NSFileManager.defaultManager removeItemAtURL:videoURL error:nil];
            [NSFileManager.defaultManager removeItemAtURL:audioURL error:nil];
            YTKACEDownloadLog(job.identifier, @"merge complete");
            [weakSelf saveCompletedURL:output job:job extension:@"mp4"];
        }];
}

- (void)startDownload:(NSURL *)url
              category:(NSString *)category
             extension:(NSString *)extension {
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    YTKACEDownloadJob *job = [YTKACEDownloadJob new];
    job.task = task;
    job.title = [self safeFilename:
        [YTKACEStreamResolver titleFromPlayerResponse:self.playerResponse]];
    job.category = category;
    job.extension = extension;
    @synchronized (self.jobs) {
        self.jobs[@(task.taskIdentifier)] = job;
    }

    [self showCompactNotice:@"Download started"];
    [task resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)session;
    (void)bytesWritten;
    YTKACEDownloadJob *job = nil;
    @synchronized (self.jobs) {
        job = self.jobs[@(downloadTask.taskIdentifier)];
    }
    if (job == nil || totalBytesExpectedToWrite <= 0) {
        return;
    }
    (void)totalBytesWritten;
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    (void)session;
    YTKACEDownloadJob *job = nil;
    @synchronized (self.jobs) {
        job = self.jobs[@(downloadTask.taskIdentifier)];
    }
    if (job == nil) {
        return;
    }

    NSURL *downloads = [YTKACEApplicationSupportDirectory()
        URLByAppendingPathComponent:@"Downloads"
                        isDirectory:YES];
    NSURL *directory = [downloads URLByAppendingPathComponent:job.category isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];

    NSString *filename =
        [NSString stringWithFormat:@"%@.%@", job.title, job.extension];
    NSURL *destination = [directory URLByAppendingPathComponent:filename];
    NSInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
        filename = [NSString stringWithFormat:@"%@ %ld.%@",
                    job.title,
                    (long)suffix++,
                    job.extension];
        destination = [directory URLByAppendingPathComponent:filename];
    }

    NSError *error = nil;
    [NSFileManager.defaultManager moveItemAtURL:location
                                         toURL:destination
                                         error:&error];
    if (error == nil) {
        job.savedURL = destination;
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    (void)session;
    YTKACEDownloadJob *job = nil;
    @synchronized (self.jobs) {
        job = self.jobs[@(task.taskIdentifier)];
    }
    if (job == nil) {
        return;
    }
    @synchronized (self.jobs) {
        [self.jobs removeObjectForKey:@(task.taskIdentifier)];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (error != nil) {
            if (error.code != NSURLErrorCancelled) {
                [self showAlertWithTitle:@"Download failed"
                                 message:error.localizedDescription ?: @"Unknown error"];
            }
        } else if (job.savedURL != nil) {
            [self showAlertWithTitle:@"Download complete"
                             message:job.savedURL.lastPathComponent];
        } else {
            [self showAlertWithTitle:@"Download failed"
                             message:@"The file could not be saved."];
        }
    });
}

@end
