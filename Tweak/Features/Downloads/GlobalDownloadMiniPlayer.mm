#import "GlobalDownloadMiniPlayer.h"
#import "MediaArtwork.h"
#import "YTKACEAudioPlayerController.h"
#import "YTKACEDownloadPlayerController.h"
#import "../../Runtime/Preferences.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface YTKACEGlobalVideoView : UIView
@property(nonatomic, strong) AVPlayer *player;
@end

@implementation YTKACEGlobalVideoView
+ (Class)layerClass { return AVPlayerLayer.class; }
- (void)setPlayer:(AVPlayer *)player {
    _player = player;
    AVPlayerLayer *layer = (AVPlayerLayer *)self.layer;
    layer.player = player;
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}
@end

static UIWindow *YTKACEGlobalWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && window.alpha > 0.0) return window;
        }
    }
    return nil;
}

static UIViewController *YTKACEGlobalPresenter(void) {
    UIViewController *controller = YTKACEGlobalWindow().rootViewController;
    while (controller != nil) {
        if (controller.presentedViewController != nil) {
            controller = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class]) {
            controller = ((UINavigationController *)controller).visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else {
            break;
        }
    }
    return controller;
}

static BOOL YTKACEIsFullPlayer(UIViewController *controller) {
    return [controller isKindOfClass:YTKACEDownloadPlayerController.class] ||
        [controller isKindOfClass:YTKACEAudioPlayerController.class];
}

static BOOL YTKACEGlobalFullPlayerVisible(void) {
    UIViewController *controller = YTKACEGlobalWindow().rootViewController;
    while (controller != nil) {
        if (YTKACEIsFullPlayer(controller)) return YES;
        if (controller.presentedViewController != nil) {
            controller = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class]) {
            UINavigationController *navigation = (UINavigationController *)controller;
            for (UIViewController *child in navigation.viewControllers) {
                if (YTKACEIsFullPlayer(child)) return YES;
            }
            controller = navigation.visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else {
            break;
        }
    }
    return NO;
}

static CGFloat YTKACEGlobalTabTop(UIWindow *window) {
    __block CGFloat top = CGRectGetHeight(window.bounds) -
        window.safeAreaInsets.bottom;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
    while (stack.count != 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if (view.hidden || view.alpha < 0.05) continue;
        NSString *name = NSStringFromClass(view.class).lowercaseString;
        BOOL tab = [view isKindOfClass:UITabBar.class] ||
            [name containsString:@"pivotbar"];
        if (tab && CGRectGetHeight(view.bounds) >= 35.0) {
            CGRect frame = [view convertRect:view.bounds toView:window];
            if (CGRectGetMinY(frame) > CGRectGetHeight(window.bounds) * 0.55) {
                top = MIN(top, CGRectGetMinY(frame));
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return top;
}

@interface YTKACEGlobalDownloadMiniPlayer : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIView *bar;
@property(nonatomic, strong) YTKACEGlobalVideoView *videoView;
@property(nonatomic, strong) UIImageView *artworkView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) NSTimer *positionTimer;
@end

@implementation YTKACEGlobalDownloadMiniPlayer

+ (instancetype)sharedPlayer {
    static YTKACEGlobalDownloadMiniPlayer *player;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ player = [YTKACEGlobalDownloadMiniPlayer new]; });
    return player;
}

- (instancetype)init {
    self = [super init];
    if (self == nil) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(playbackChanged:)
        name:YTKACEDownloadPlaybackDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(playbackChanged:)
        name:YTKACEDownloadPlaybackDidStopNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(applicationBecameActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)buildUI {
    if (self.bar != nil) return;
    self.bar = [UIView new];
    self.bar.layer.cornerRadius = 12.0;
    self.bar.layer.masksToBounds = YES;
    self.bar.layer.shadowColor = UIColor.blackColor.CGColor;
    self.bar.layer.shadowOpacity = 0.2;
    self.bar.layer.shadowRadius = 8.0;
    self.bar.layer.shadowOffset = CGSizeMake(0.0, 2.0);

    self.videoView = [YTKACEGlobalVideoView new];
    self.videoView.clipsToBounds = YES;
    self.videoView.layer.cornerRadius = 8.0;
    [self.bar addSubview:self.videoView];

    self.artworkView = [UIImageView new];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 8.0;
    [self.bar addSubview:self.artworkView];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.bar addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.font = [UIFont systemFontOfSize:10.5];
    [self.bar addSubview:self.subtitleLabel];

    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playButton addTarget:self action:@selector(togglePlayback)
              forControlEvents:UIControlEventTouchUpInside];
    [self.bar addSubview:self.playButton];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
           forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closePlayback)
      forControlEvents:UIControlEventTouchUpInside];
    close.tag = 9107;
    [self.bar addSubview:close];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(openPlayer)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.bar addGestureRecognizer:tap];
}

- (void)applyTheme {
    UITraitCollection *traits = YTKACEGlobalWindow().traitCollection ?:
        UIScreen.mainScreen.traitCollection;
    self.bar.backgroundColor = YTKACEInterfaceSurfaceColor(traits);
    self.videoView.backgroundColor = YTKACEInterfaceSurfaceColor(traits);
    self.artworkView.backgroundColor = YTKACEInterfaceSurfaceColor(traits);
    self.titleLabel.textColor = UIColor.labelColor;
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.playButton.tintColor = UIColor.labelColor;
    UIButton *close = [self.bar viewWithTag:9107];
    close.tintColor = UIColor.secondaryLabelColor;
}

- (void)layoutBar {
    UIWindow *window = YTKACEGlobalWindow();
    if (window == nil || self.bar.superview != window) return;
    BOOL fullPlayer = YTKACEGlobalFullPlayerVisible();
    self.bar.hidden = fullPlayer;
    if (fullPlayer) return;
    CGFloat width = MIN(560.0, CGRectGetWidth(window.bounds) - 20.0);
    CGFloat tabTop = YTKACEGlobalTabTop(window);
    self.bar.frame = CGRectMake((CGRectGetWidth(window.bounds) - width) * 0.5,
        MAX(window.safeAreaInsets.top + 8.0, tabTop - 66.0), width, 58.0);
    self.videoView.frame = CGRectMake(5.0, 5.0, 72.0, 48.0);
    self.artworkView.frame = self.videoView.frame;
    CGFloat controls = 72.0;
    self.titleLabel.frame = CGRectMake(86.0, 10.0,
        MAX(40.0, width - 86.0 - controls), 18.0);
    self.subtitleLabel.frame = CGRectMake(86.0, 31.0,
        MAX(40.0, width - 86.0 - controls), 15.0);
    self.playButton.frame = CGRectMake(width - 66.0, 13.0, 32.0, 32.0);
    [self.bar viewWithTag:9107].frame = CGRectMake(width - 31.0, 17.0, 24.0, 24.0);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    (void)gestureRecognizer;
    return ![touch.view isKindOfClass:UIControl.class];
}

- (void)playbackChanged:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    if (self.bar == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)refresh {
    [self buildUI];
    YTKACEDownloadPlaybackSession *session =
        YTKACEDownloadPlaybackSession.sharedSession;
    NSURL *URL = session.currentURL;
    if (URL == nil) {
        [self.bar removeFromSuperview];
        [self.positionTimer invalidate];
        self.positionTimer = nil;
        self.videoView.player = nil;
        return;
    }
    UIWindow *window = YTKACEGlobalWindow();
    if (window == nil) return;
    if (self.bar.superview != window) {
        [self.bar removeFromSuperview];
        [window addSubview:self.bar];
    }
    [window bringSubviewToFront:self.bar];
    BOOL audio = [URL.path containsString:@"/Downloads/Audio/"];
    self.videoView.hidden = audio;
    self.artworkView.hidden = !audio;
    self.videoView.player = audio ? nil : session.player;
    self.artworkView.image = audio ? YTKACEMediaArtworkImage(URL) : nil;
    self.titleLabel.text = URL.lastPathComponent.stringByDeletingPathExtension;
    self.subtitleLabel.text = audio ? @"Audio" :
        ([URL.path containsString:@"/Downloads/Shorts/"] ? @"Shorts" : @"Video");
    NSString *symbol = session.player.rate == 0.0f ? @"play.fill" : @"pause.fill";
    [self.playButton setImage:[UIImage systemImageNamed:symbol]
                     forState:UIControlStateNormal];
    [self applyTheme];
    [self layoutBar];
    if (self.positionTimer == nil) {
        __weak YTKACEGlobalDownloadMiniPlayer *weakSelf = self;
        self.positionTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
            repeats:YES block:^(__unused NSTimer *timer) {
                [weakSelf layoutBar];
                UIWindow *activeWindow = YTKACEGlobalWindow();
                if (weakSelf.bar.superview != activeWindow) [weakSelf refresh];
                [activeWindow bringSubviewToFront:weakSelf.bar];
            }];
    }
}

- (void)togglePlayback {
    [YTKACEDownloadPlaybackSession.sharedSession togglePlayback];
}

- (void)closePlayback {
    [YTKACEDownloadPlaybackSession.sharedSession stop];
}

- (void)openPlayer {
    YTKACEDownloadPlaybackSession *session =
        YTKACEDownloadPlaybackSession.sharedSession;
    if (session.currentURL == nil) return;
    UIViewController *presenter = YTKACEGlobalPresenter();
    if (presenter == nil || YTKACEGlobalFullPlayerVisible()) {
        return;
    }
    BOOL audio = [session.currentURL.path containsString:@"/Downloads/Audio/"];
    UIViewController *player = audio
        ? [[YTKACEAudioPlayerController alloc] initWithSession:session]
        : [[YTKACEDownloadPlayerController alloc] initWithSession:session];
    __weak YTKACEGlobalDownloadMiniPlayer *weakSelf = self;
    dispatch_block_t minimized = ^{ [weakSelf refresh]; };
    if (audio) {
        ((YTKACEAudioPlayerController *)player).minimizeHandler = minimized;
    } else {
        ((YTKACEDownloadPlayerController *)player).minimizeHandler = minimized;
    }
    [presenter presentViewController:player animated:YES completion:nil];
}

@end

void YTKACEInstallGlobalDownloadMiniPlayer(void) {
    [YTKACEGlobalDownloadMiniPlayer sharedPlayer];
}
