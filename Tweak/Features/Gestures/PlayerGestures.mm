#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalOverlayDidMoveToWindow;
static const void *YTKACEVolumePanAssociation = &YTKACEVolumePanAssociation;
static const void *YTKACEBrightnessPanAssociation = &YTKACEBrightnessPanAssociation;
static const void *YTKACELongPressAssociation = &YTKACELongPressAssociation;
static const void *YTKACEGestureStartYAssociation = &YTKACEGestureStartYAssociation;
static const void *YTKACEGestureInitialAssociation = &YTKACEGestureInitialAssociation;
static const void *YTKACEIndicatorAssociation = &YTKACEIndicatorAssociation;
static const void *YTKACEIndicatorIconAssociation = &YTKACEIndicatorIconAssociation;
static const void *YTKACEIndicatorFillAssociation = &YTKACEIndicatorFillAssociation;
static const void *YTKACEIndicatorLabelAssociation = &YTKACEIndicatorLabelAssociation;
static const void *YTKACEVolumeViewAssociation = &YTKACEVolumeViewAssociation;
static const void *YTKACESeekIndicatorAssociation = &YTKACESeekIndicatorAssociation;
static const void *YTKACESeekIconAssociation = &YTKACESeekIconAssociation;
static const void *YTKACESeekLabelAssociation = &YTKACESeekLabelAssociation;

@interface YTKACEGestureCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedCoordinator;
@property(nonatomic, strong) NSTimer *seekTimer;
@property(nonatomic, weak) UIResponder *seekTarget;
@property(nonatomic, weak) UIView *seekView;
@property(nonatomic, assign) double seekTime;
@property(nonatomic, assign) NSInteger seekDirection;
- (void)handleVolume:(UIPanGestureRecognizer *)recognizer;
- (void)handleBrightness:(UIPanGestureRecognizer *)recognizer;
- (void)handleHold:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation YTKACEGestureCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACEGestureCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACEGestureCoordinator new];
    });
    return coordinator;
}

- (UISlider *)volumeSliderInView:(UIView *)view {
    MPVolumeView *volumeView =
        objc_getAssociatedObject(view, YTKACEVolumeViewAssociation);
    if (volumeView == nil) {
        volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];
        volumeView.alpha = 0.01;
        [view addSubview:volumeView];
        objc_setAssociatedObject(view,
                                 YTKACEVolumeViewAssociation,
                                 volumeView,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *subview in volumeView.subviews) {
        if ([subview isKindOfClass:UISlider.class]) {
            return (UISlider *)subview;
        }
    }
    return nil;
}

- (UIView *)indicatorInView:(UIView *)view {
    UIView *indicator = objc_getAssociatedObject(view, YTKACEIndicatorAssociation);
    if (indicator != nil) {
        return indicator;
    }

    indicator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, 50.0)];
    indicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
    indicator.layer.cornerRadius = 10.0;
    indicator.clipsToBounds = YES;
    indicator.userInteractionEnabled = NO;
    indicator.alpha = 0.0;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(15.0, 12.0, 26.0, 26.0)];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [indicator addSubview:icon];

    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(50.0, 18.0, 130.0, 3.0)];
    track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    track.layer.cornerRadius = 1.5;
    [indicator addSubview:track];

    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(50.0, 18.0, 0.0, 3.0)];
    fill.backgroundColor = UIColor.whiteColor;
    fill.layer.cornerRadius = 1.5;
    [indicator addSubview:fill];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 25.0, 130.0, 20.0)];
    label.textColor = UIColor.whiteColor;
    label.alpha = 0.8;
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentRight;
    [indicator addSubview:label];

    [view addSubview:indicator];
    objc_setAssociatedObject(view,
                             YTKACEIndicatorAssociation,
                             indicator,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorIconAssociation, icon,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorFillAssociation, fill,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorLabelAssociation, label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return indicator;
}

- (UIView *)seekIndicatorInView:(UIView *)view {
    UIView *indicator = objc_getAssociatedObject(view, YTKACESeekIndicatorAssociation);
    if (indicator != nil) return indicator;
    indicator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 120.0, 120.0)];
    indicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    indicator.layer.cornerRadius = 12.0;
    indicator.clipsToBounds = YES;
    indicator.userInteractionEnabled = NO;
    indicator.alpha = 0.0;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(35.0, 25.0, 50.0, 50.0)];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [indicator addSubview:icon];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 80.0, 120.0, 30.0)];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:18.0];
    label.textAlignment = NSTextAlignmentCenter;
    [indicator addSubview:label];
    [view addSubview:indicator];
    objc_setAssociatedObject(view, YTKACESeekIndicatorAssociation, indicator,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACESeekIconAssociation, icon,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACESeekLabelAssociation, label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return indicator;
}

- (BOOL)isVolumePan:(UIGestureRecognizer *)recognizer {
    return recognizer == objc_getAssociatedObject(recognizer.view,
                                                   YTKACEVolumePanAssociation);
}

- (BOOL)isBrightnessPan:(UIGestureRecognizer *)recognizer {
    return recognizer == objc_getAssociatedObject(recognizer.view,
                                                   YTKACEBrightnessPanAssociation);
}

- (BOOL)isCustomPan:(UIGestureRecognizer *)recognizer {
    return [self isVolumePan:recognizer] || [self isBrightnessPan:recognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (gestureRecognizer == objc_getAssociatedObject(gestureRecognizer.view,
                                                       YTKACELongPressAssociation)) {
        return NO;
    }
    if ([self isCustomPan:gestureRecognizer]) {
        return NO;
    }
    return !([self isCustomPan:other] &&
             [gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([self isCustomPan:gestureRecognizer]) {
        if (!YTKACEMasterEnabled()) {
            return NO;
        }
        UIView *view = gestureRecognizer.view;
        CGPoint location = [gestureRecognizer locationInView:view];
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer
            velocityInView:view];
        if (fabs(velocity.y) <= fabs(velocity.x) * 1.5) {
            return NO;
        }
        NSString *key = [self isVolumePan:gestureRecognizer]
            ? @"YTKACE.Preference.Gestures.VolumeSide" : @"YTKACE.Preference.Gestures.BrightnessSide";
        id value = YTKACEPreferenceObject(key);
        NSInteger side = value == nil
            ? ([key isEqualToString:@"YTKACE.Preference.Gestures.VolumeSide"] ? 0 : 1)
            : [value integerValue];
        CGFloat edge = CGRectGetWidth(view.bounds) * 0.15;
        BOOL inEdge = side == 0
            ? location.x > CGRectGetWidth(view.bounds) - edge
            : location.x < edge;
        return side != 2 && inEdge;
    }
    if (![gestureRecognizer isKindOfClass:UILongPressGestureRecognizer.class]) {
        return YES;
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HoldToSeek")) {
        return NO;
    }
    UIView *view = gestureRecognizer.view;
    CGPoint location = [gestureRecognizer locationInView:view];
    CGRect bounds = view.bounds;
    return location.x > CGRectGetWidth(bounds) * 0.2 &&
        location.x < CGRectGetWidth(bounds) * 0.8 &&
        location.y > CGRectGetHeight(bounds) * 0.15 &&
        location.y < CGRectGetHeight(bounds) * 0.85;
}

- (void)updateIndicatorInView:(UIView *)view value:(double)value volume:(BOOL)volume {
    UIView *indicator = [self indicatorInView:view];
    UIImageView *icon = objc_getAssociatedObject(view, YTKACEIndicatorIconAssociation);
    UIView *fill = objc_getAssociatedObject(view, YTKACEIndicatorFillAssociation);
    UILabel *label = objc_getAssociatedObject(view, YTKACEIndicatorLabelAssociation);
    NSString *symbol = nil;
    if (volume) {
        if (value <= 0.01) symbol = @"speaker.slash.fill";
        else if (value <= 0.33) symbol = @"speaker.1.fill";
        else if (value <= 0.66) symbol = @"speaker.2.fill";
        else symbol = @"speaker.3.fill";
    } else {
        symbol = value <= 0.4 ? @"sun.min.fill" : @"sun.max.fill";
    }
    icon.image = [[UIImage systemImageNamed:symbol]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    CGRect frame = fill.frame;
    frame.size.width = 130.0 * value;
    fill.frame = frame;
    label.text = [NSString stringWithFormat:@"%d%%", (int)lround(value * 100.0)];
    indicator.center = CGPointMake(CGRectGetMidX(view.bounds), 50.0);
    [view bringSubviewToFront:indicator];
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer volume:(BOOL)volume {
    UIView *view = recognizer.view;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [recognizer locationInView:view];
        double start = volume
            ? AVAudioSession.sharedInstance.outputVolume
            : UIScreen.mainScreen.brightness;
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureStartYAssociation,
                                 @(location.y),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureInitialAssociation,
                                 @(start),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self updateIndicatorInView:view value:start volume:volume];
        UIView *indicator = [self indicatorInView:view];
        [UIView animateWithDuration:0.2 animations:^{ indicator.alpha = 1.0; }];
    }
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint location = [recognizer locationInView:view];
        double startY = [objc_getAssociatedObject(recognizer,
            YTKACEGestureStartYAssociation) doubleValue];
        double start = [objc_getAssociatedObject(recognizer,
            YTKACEGestureInitialAssociation) doubleValue];
        double value = MIN(1.0, MAX(0.0, start + (startY - location.y) * 0.0015));
        if (volume) {
            UISlider *slider = [self volumeSliderInView:view];
            [slider setValue:(float)value animated:NO];
            [slider sendActionsForControlEvents:UIControlEventValueChanged];
        } else {
            UIScreen.mainScreen.brightness = value;
        }
        [self updateIndicatorInView:view value:value volume:volume];
    }
    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        UIView *indicator = [self indicatorInView:view];
        [UIView animateWithDuration:0.3
                              delay:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ indicator.alpha = 0.0; }
                         completion:nil];
    }
}

- (void)handleVolume:(UIPanGestureRecognizer *)recognizer {
    [self handlePan:recognizer volume:YES];
}

- (void)handleBrightness:(UIPanGestureRecognizer *)recognizer {
    [self handlePan:recognizer volume:NO];
}

- (double)seekStep {
    double value = [NSUserDefaults.standardUserDefaults
        doubleForKey:@"YTKACE.Preference.Gestures.HoldSeekSeconds"];
    return MIN(60.0, MAX(1.0, value > 0.0 ? value : 10.0));
}

- (UIResponder *)seekResponderForView:(UIView *)view {
    UIResponder *responder = view;
    while (responder != nil) {
        BOOL hasTime =
            [responder respondsToSelector:NSSelectorFromString(@"currentVideoMediaTime")] ||
            [responder respondsToSelector:NSSelectorFromString(@"mediaTime")];
        BOOL canSeek =
            [responder respondsToSelector:NSSelectorFromString(@"seekToTime:")] ||
            [responder respondsToSelector:
                NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:")];
        if (hasTime && canSeek) {
            return responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (double)doubleFromResponder:(id)responder selectors:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([responder respondsToSelector:selector]) {
            return ((double (*)(id, SEL))objc_msgSend)(responder, selector);
        }
    }
    return 0.0;
}

- (void)performSeek {
    id target = self.seekTarget;
    if (target == nil) {
        [self.seekTimer invalidate];
        self.seekTimer = nil;
        return;
    }

    self.seekTime += self.seekStep * self.seekDirection;
    double minimum = [self doubleFromResponder:target
                                     selectors:@[@"minimumSeekableTime"]];
    double maximum = [self doubleFromResponder:target
                                     selectors:@[
                                         @"maximumSeekableTime",
                                         @"currentVideoTotalTime",
                                         @"currentVideoDuration"
                                     ]];
    self.seekTime = MAX(minimum, self.seekTime);
    if (maximum > minimum) {
        self.seekTime = MIN(maximum, self.seekTime);
    }

    SEL detailed =
        NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:");
    SEL simple = NSSelectorFromString(@"seekToTime:");
    if ([target respondsToSelector:detailed]) {
        ((void (*)(id, SEL, double, double, double))objc_msgSend)(
            target, detailed, self.seekTime, 0.0, 0.0
        );
    } else if ([target respondsToSelector:simple]) {
        ((void (*)(id, SEL, double))objc_msgSend)(
            target, simple, self.seekTime
        );
    }

    UIView *indicator = [self seekIndicatorInView:self.seekView];
    UIImageView *icon = objc_getAssociatedObject(self.seekView, YTKACESeekIconAssociation);
    UILabel *label = objc_getAssociatedObject(self.seekView, YTKACESeekLabelAssociation);
    NSString *symbol = self.seekDirection < 0 ? @"gobackward" : @"goforward";
    icon.image = [[UIImage systemImageNamed:symbol]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    NSInteger seconds = MAX(0, (NSInteger)llround(self.seekTime));
    label.text = [NSString stringWithFormat:@"%ld:%02ld",
                  (long)(seconds / 60), (long)(seconds % 60)];
    indicator.center = CGPointMake(CGRectGetMidX(self.seekView.bounds),
                                   CGRectGetMidY(self.seekView.bounds));
    [self.seekView bringSubviewToFront:indicator];
    [UIView animateWithDuration:0.2 animations:^{ indicator.alpha = 1.0; }];
}

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        UIView *view = recognizer.view;
        self.seekTarget = [self seekResponderForView:view];
        if (self.seekTarget == nil) {
            return;
        }
        self.seekView = view;
        CGPoint location = [recognizer locationInView:view];
        self.seekDirection =
            location.x < CGRectGetMidX(view.bounds) ? -1 : 1;
        self.seekTime = [self doubleFromResponder:self.seekTarget
                                       selectors:@[
                                           @"currentVideoMediaTime",
                                           @"mediaTime"
                                       ]];
        [self performSeek];
        __weak YTKACEGestureCoordinator *weakSelf = self;
        self.seekTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.1
                                           repeats:YES
                                             block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf performSeek];
        }];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled ||
               recognizer.state == UIGestureRecognizerStateFailed) {
        [self.seekTimer invalidate];
        self.seekTimer = nil;
        UIView *indicator = [self seekIndicatorInView:self.seekView];
        [UIView animateWithDuration:0.3
                              delay:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            indicator.alpha = 0.0;
        } completion:nil];
        self.seekTarget = nil;
        self.seekView = nil;
    }
}

@end

static void YTKACEOverlayDidMoveToWindow(UIView *receiver, SEL selector) {
    if (OriginalOverlayDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalOverlayDidMoveToWindow)(receiver, selector);
    }
    if (objc_getAssociatedObject(receiver, YTKACEVolumePanAssociation) != nil) {
        return;
    }

    UIPanGestureRecognizer *volume =
        [[UIPanGestureRecognizer alloc] initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                                                action:@selector(handleVolume:)];
    volume.maximumNumberOfTouches = 1;
    volume.cancelsTouchesInView = YES;
    volume.delegate = YTKACEGestureCoordinator.sharedCoordinator;

    UIPanGestureRecognizer *brightness =
        [[UIPanGestureRecognizer alloc] initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                                                action:@selector(handleBrightness:)];
    brightness.maximumNumberOfTouches = 1;
    brightness.cancelsTouchesInView = YES;
    brightness.delegate = YTKACEGestureCoordinator.sharedCoordinator;

    [receiver addGestureRecognizer:volume];
    [receiver addGestureRecognizer:brightness];
    objc_setAssociatedObject(receiver,
                             YTKACEVolumePanAssociation,
                             volume,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(receiver,
                             YTKACEBrightnessPanAssociation,
                             brightness,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSArray<NSString *> *selectors = @[
            @"fullscreenExitGestureRecognizer",
            @"fullscreenEnterGestureRecognizer",
            @"verticalPanGestureRecognizer"
        ];
        for (NSString *name in selectors) {
            SEL selector = NSSelectorFromString(name);
            if (![receiver respondsToSelector:selector]) continue;
            UIGestureRecognizer *native =
                ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
            if (![native isKindOfClass:UIGestureRecognizer.class]) continue;
            [native requireGestureRecognizerToFail:volume];
            [native requireGestureRecognizerToFail:brightness];
        }
        for (UIGestureRecognizer *native in [receiver.gestureRecognizers copy]) {
            if (native != volume && native != brightness &&
                [native isKindOfClass:UIPanGestureRecognizer.class]) {
                [native requireGestureRecognizerToFail:volume];
                [native requireGestureRecognizerToFail:brightness];
            }
        }
    });

    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                    action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.5;
    hold.cancelsTouchesInView = YES;
    hold.delegate = YTKACEGestureCoordinator.sharedCoordinator;
    [receiver addGestureRecognizer:hold];
    objc_setAssociatedObject(receiver,
                             YTKACELongPressAssociation,
                             hold,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void YTKACEInstallPlayerGestureHooks(void) {
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEOverlayDidMoveToWindow,
                              &OriginalOverlayDidMoveToWindow);
}
