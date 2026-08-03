#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/Assets.h"
#import "../../UI/OverlayButtonHost.h"

#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

static NSMutableDictionary<NSString *, NSNumber *> *YTKACEMaximumRateOriginals;

static NSString *YTKACESpeedText(double rate) {
    if (fabs(rate - round(rate)) < 0.001) {
        return [NSString stringWithFormat:@"%.0fx", rate];
    }
    if (fabs(rate * 2.0 - round(rate * 2.0)) < 0.001) {
        return [NSString stringWithFormat:@"%.1fx", rate];
    }
    return [NSString stringWithFormat:@"%.2fx", rate];
}

static UIImage *YTKACESpeedButtonImage(BOOL plus) {
    CGSize size = CGSizeMake(22.0, 22.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, UIColor.whiteColor.CGColor);
    CGContextSetLineWidth(context, 2.0);
    CGContextAddEllipseInRect(context, CGRectInset((CGRect){CGPointZero, size}, 1.5, 1.5));
    CGContextMoveToPoint(context, 6.5, 11.0);
    CGContextAddLineToPoint(context, 15.5, 11.0);
    if (plus) {
        CGContextMoveToPoint(context, 11.0, 6.5);
        CGContextAddLineToPoint(context, 11.0, 15.5);
    }
    CGContextStrokePath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@interface YTKACESpeedCoordinator : NSObject
+ (instancetype)sharedCoordinator;
@property(nonatomic, weak) UIView *overlay;
@property(nonatomic, weak) UIButton *valueButton;
@property(nonatomic, assign) double observedRate;
- (void)decrease;
- (void)increase;
- (void)reset;
@end

@implementation YTKACESpeedCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACESpeedCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACESpeedCoordinator new];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _observedRate = 0.0;
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(playbackTimeChanged:)
                   name:@"YTKACEPlaybackTimeDidChange"
                 object:nil];
    }
    return self;
}

- (double)rateFromObject:(id)object depth:(NSUInteger)depth {
    if (object == nil || depth > 2) {
        return 0.0;
    }
    for (NSString *name in @[@"playbackRate", @"currentPlaybackRate", @"rate"]) {
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        if (![object respondsToSelector:selector] || signature == nil) {
            continue;
        }
        const char *type = signature.methodReturnType;
        double rate = 0.0;
        if (type[0] == 'd') {
            rate = ((double (*)(id, SEL))objc_msgSend)(object, selector);
        } else if (type[0] == 'f') {
            rate = ((float (*)(id, SEL))objc_msgSend)(object, selector);
        } else if (strchr("cislqCISLQ", type[0]) != NULL) {
            rate = ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
        } else if (type[0] == '@') {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            if ([value respondsToSelector:@selector(doubleValue)]) {
                rate = [value doubleValue];
            }
        }
        if (isfinite(rate) && rate >= 0.25 && rate <= 5.0) {
            return rate;
        }
    }
    for (NSString *name in @[@"eventsDelegate", @"playbackController",
                              @"playerController", @"player"]) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) {
            continue;
        }
        id child = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (child == object) {
            continue;
        }
        double rate = [self rateFromObject:child depth:depth + 1];
        if (rate >= 0.25) {
            return rate;
        }
    }
    return 0.0;
}

- (void)playbackTimeChanged:(NSNotification *)notification {
    double rate = [self rateFromObject:notification.object depth:0];
    if (rate < 0.25) {
        AVPlayer *player = self.activePlayer;
        if (player.rate >= 0.25f) {
            rate = player.rate;
        }
    }
    if (rate < 0.25 || rate > 5.0) {
        return;
    }
    self.observedRate = rate;
    [NSUserDefaults.standardUserDefaults setFloat:(float)rate
                                           forKey:@"YTKACE.Preference.Player.SavedRate"];
    [self.valueButton setTitle:YTKACESpeedText(rate)
                      forState:UIControlStateNormal];
}

- (id)eventsDelegate {
    SEL selector = NSSelectorFromString(@"eventsDelegate");
    if ([self.overlay respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(self.overlay, selector);
    }
    return nil;
}

- (double)currentRate {
    if (isfinite(self.observedRate) && self.observedRate >= 0.25 &&
        self.observedRate <= 5.0) {
        return self.observedRate;
    }
    float saved =
        [NSUserDefaults.standardUserDefaults floatForKey:@"YTKACE.Preference.Player.SavedRate"];
    return isfinite(saved) && saved >= 0.25f && saved <= 5.0f
        ? saved
        : 1.0;
}

- (AVPlayer *)activePlayerInLayer:(CALayer *)layer {
    if ([layer isKindOfClass:AVPlayerLayer.class]) {
        AVPlayer *player = ((AVPlayerLayer *)layer).player;
        if (player != nil) {
            return player;
        }
    }
    for (CALayer *child in layer.sublayers) {
        AVPlayer *player = [self activePlayerInLayer:child];
        if (player != nil) {
            return player;
        }
    }
    return nil;
}

- (AVPlayer *)activePlayer {
    UIView *root = self.overlay;
    while (root.superview != nil) {
        root = root.superview;
    }
    return [self activePlayerInLayer:root.layer];
}

- (void)setRate:(double)rate {
    rate = MIN(5.0, MAX(0.25, round(rate * 4.0) / 4.0));
    id delegate = self.eventsDelegate;
    for (NSString *name in @[@"setPlaybackRate:", @"setRate:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([delegate respondsToSelector:selector]) {
            ((void (*)(id, SEL, double))objc_msgSend)(delegate, selector, rate);
            break;
        }
    }
    [NSUserDefaults.standardUserDefaults setFloat:(float)rate
                                           forKey:@"YTKACE.Preference.Player.SavedRate"];
    self.observedRate = rate;
    [self.valueButton setTitle:YTKACESpeedText(rate)
                      forState:UIControlStateNormal];
}

- (void)decrease {
    [self setRate:self.currentRate - 0.25];
}

- (void)increase {
    [self setRate:self.currentRate + 0.25];
}

- (void)reset {
    [self setRate:1.0];
}

@end

static IMP YTKACEMaximumOriginal(id receiver, SEL selector) {
    NSString *key = [NSString stringWithFormat:@"%@|%@",
        NSStringFromClass([receiver class]), NSStringFromSelector(selector)];
    return (IMP)(uintptr_t)YTKACEMaximumRateOriginals[key].unsignedLongLongValue;
}

static double YTKACEMaximumPlaybackRateDouble(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACESpeedKey)) {
        return 5.0;
    }
    IMP original = YTKACEMaximumOriginal(receiver, selector);
    return original == NULL
        ? 2.0
        : ((double (*)(id, SEL))original)(receiver, selector);
}

static float YTKACEMaximumPlaybackRateFloat(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACESpeedKey)) {
        return 5.0f;
    }
    IMP original = YTKACEMaximumOriginal(receiver, selector);
    return original == NULL
        ? 2.0f
        : ((float (*)(id, SEL))original)(receiver, selector);
}

static NSInteger YTKACEMaximumPlaybackRateInteger(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACESpeedKey)) {
        return 500;
    }
    IMP original = YTKACEMaximumOriginal(receiver, selector);
    return original == NULL
        ? 2
        : ((NSInteger (*)(id, SEL))original)(receiver, selector);
}

static NSUInteger YTKACEMaximumPlaybackRateUnsigned(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACESpeedKey)) {
        return 500;
    }
    IMP original = YTKACEMaximumOriginal(receiver, selector);
    return original == NULL
        ? 2
        : ((NSUInteger (*)(id, SEL))original)(receiver, selector);
}

static void YTKACEInstallMaximumRateHook(NSString *className,
                                         NSString *selectorName) {
    Class cls = NSClassFromString(className);
    Method method = class_getInstanceMethod(
        cls,
        NSSelectorFromString(selectorName)
    );
    if (method == NULL) {
        return;
    }
    char returnType[16] = {};
    method_getReturnType(method, returnType, sizeof(returnType));
    IMP replacement = NULL;
    if (strcmp(returnType, @encode(float)) == 0) {
        replacement = (IMP)YTKACEMaximumPlaybackRateFloat;
    } else if (strcmp(returnType, @encode(double)) == 0) {
        replacement = (IMP)YTKACEMaximumPlaybackRateDouble;
    } else if (strcmp(returnType, @encode(NSInteger)) == 0 ||
               strcmp(returnType, @encode(int)) == 0) {
        replacement = (IMP)YTKACEMaximumPlaybackRateInteger;
    } else if (strcmp(returnType, @encode(NSUInteger)) == 0 ||
               strcmp(returnType, @encode(unsigned int)) == 0) {
        replacement = (IMP)YTKACEMaximumPlaybackRateUnsigned;
    }
    if (replacement != NULL) {
        IMP original = NULL;
        if (YTKACEInstallInstanceHook(className,
                                      selectorName,
                                      replacement,
                                      &original)) {
            NSString *key = [NSString stringWithFormat:@"%@|%@",
                className, selectorName];
            YTKACEMaximumRateOriginals[key] = @((uintptr_t)original);
        }
    }
}

static void YTKACEInstallMaximumRateHooks(void) {
    YTKACEMaximumRateOriginals = [NSMutableDictionary dictionary];
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return;
    }
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count,
                                                          sizeof(Class));
    count = objc_getClassList(classes, count);
    for (int index = 0; index < count; index++) {
        NSString *name = NSStringFromClass(classes[index]);
        BOOL candidate = [name containsString:@"GranularVariableSpeedConfig"] ||
            [name containsString:@"PlayerHotConfig"];
        if (!candidate) {
            continue;
        }
        for (NSString *selector in @[@"maximumPlaybackRate", @"maxPlaybackRate"]) {
            if (class_getInstanceMethod(classes[index],
                                        NSSelectorFromString(selector)) != NULL) {
                YTKACEInstallMaximumRateHook(name, selector);
            }
        }
    }
    free(classes);
}

void YTKACEInstallSpeedHooks(void) {
    if (YTKACEFeatureEnabled(YTKACESpeedKey)) {
        YTKACEInstallMaximumRateHooks();
    }

    YTKACERegisterOverlayConfigurator(@"speed", ^(UIView *overlay, UIStackView *stack) {
        YTKACESpeedCoordinator *coordinator = YTKACESpeedCoordinator.sharedCoordinator;
        coordinator.overlay = overlay;

        UIButton *minus = YTKACEOverlayButton(
            stack,
            @"YTKACE Slower",
            @"minus.circle",
            coordinator,
            @selector(decrease)
        );
        UIButton *value = YTKACEOverlayButton(
            stack,
            @"YTKACE Speed",
            @"speedometer",
            coordinator,
            @selector(reset)
        );
        UIButton *plus = YTKACEOverlayButton(
            stack,
            @"YTKACE Faster",
            @"plus.circle",
            coordinator,
            @selector(increase)
        );
        [minus setImage:YTKACESpeedButtonImage(NO) forState:UIControlStateNormal];
        [plus setImage:YTKACESpeedButtonImage(YES) forState:UIControlStateNormal];
        coordinator.valueButton = value;
        [value setTitle:YTKACESpeedText(coordinator.currentRate)
               forState:UIControlStateNormal];
        [value setImage:nil forState:UIControlStateNormal];
        [value setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        value.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        for (NSLayoutConstraint *constraint in value.constraints) {
            if (constraint.firstAttribute == NSLayoutAttributeWidth) {
                constraint.active = NO;
            }
        }
        [value.widthAnchor constraintGreaterThanOrEqualToConstant:52.0].active = YES;
        value.titleLabel.adjustsFontSizeToFitWidth = NO;
        value.titleLabel.lineBreakMode = NSLineBreakByClipping;
        [value sizeToFit];

        BOOL hidden = !YTKACEFeatureEnabled(YTKACESpeedKey);
        minus.hidden = hidden;
        value.hidden = hidden;
        plus.hidden = hidden;
    });
}
