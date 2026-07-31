#import "DownloadCoordinator.h"
#import "DownloadLog.h"
#import "SABRDownloader.h"
#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/OverlayButtonHost.h"
#import <objc/message.h>

UIImage *YTKACEDownloadGlyphImage(void) {
    CGSize size = CGSizeMake(28.0, 28.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(context, UIColor.whiteColor.CGColor);
    CGContextSetLineWidth(context, 2.4);
    UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3.0, 3.0, 22.0, 22.0)
                                                   cornerRadius:4.0];
    [box stroke];
    CGContextMoveToPoint(context, 14.0, 7.0);
    CGContextAddLineToPoint(context, 14.0, 15.5);
    CGContextMoveToPoint(context, 10.0, 12.0);
    CGContextAddLineToPoint(context, 14.0, 16.0);
    CGContextAddLineToPoint(context, 18.0, 12.0);
    CGContextMoveToPoint(context, 10.0, 20.0);
    CGContextAddLineToPoint(context, 18.0, 20.0);
    CGContextStrokePath(context);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static IMP OriginalSetPlayerResponse;
static IMP OriginalSetPoToken;
static IMP OriginalMintWithVideoID;
static IMP OriginalMakePlayerRequest;
static IMP OriginalMakePlaybackRequest;
static IMP OriginalMakePrefetchPlayerRequest;
static IMP OriginalFactoryRequest;
static IMP OriginalFactoryRequestExtended;
static IMP OriginalOnesieRequest;
static IMP OriginalOnesieRequestAsync;
static IMP OriginalOnesieRequestCompletion;
static IMP OriginalHAMBuildURLRequest;
static id YTKACELastPlayerService;
static id YTKACELastPlayerRequest;
static id YTKACELastPlaybackRequest;
static id YTKACELastPlayerFactory;
static id YTKACELastRequestProperties;
static NSMutableDictionary<NSString *, NSArray *> *YTKACEPlayerRequests;
static NSMutableDictionary<NSString *, id> *YTKACEPlaybackRequests;
static NSInteger YTKACEPlayerHookAttempts;
static NSString *YTKACELastCapturedVideoID;

NSString *YTKACELastVideoID(void) {
    return [YTKACELastCapturedVideoID copy];
}
static NSString *YTKACERequestVideoID(id request);
static id YTKACECopyObject(id object);

static NSURLRequest *YTKACEURLRequestFromObject(id object) {
    if ([object isKindOfClass:NSURLRequest.class]) return object;
    SEL builder = NSSelectorFromString(@"buildURLRequest");
    if ([object respondsToSelector:builder]) {
        id result = ((id (*)(id, SEL))objc_msgSend)(object, builder);
        if ([result isKindOfClass:NSURLRequest.class]) return result;
    }
    return nil;
}

@interface YTKACEOnesieSessionState : NSObject
@property(nonatomic, strong) id factory;
@property(nonatomic, strong) id playerRequest;
@property(nonatomic, strong, nullable) id authorization;
@property(nonatomic, strong) id dataLoader;
@property(nonatomic, strong) id context;
@property(nonatomic, strong) id cryptor;
@property(nonatomic, copy) NSString *videoID;
@property(nonatomic, assign) NSInteger observedRequestNumber;
@property(nonatomic, assign) NSInteger nextRequestNumber;
@property(nonatomic, assign) BOOL asynchronous;
@property(nonatomic, strong) NSDate *capturedAt;
@end

@implementation YTKACEOnesieSessionState
@end

static NSMutableDictionary<NSString *, YTKACEOnesieSessionState *> *
    YTKACEOnesieSessions;
static YTKACEOnesieSessionState *YTKACELastOnesieSession;

static void YTKACEPruneOnesieSessions(void) {
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-900.0];
    NSMutableArray<NSString *> *expired = [NSMutableArray array];
    for (NSString *key in YTKACEOnesieSessions) {
        YTKACEOnesieSessionState *state = YTKACEOnesieSessions[key];
        if ([state.capturedAt compare:cutoff] == NSOrderedAscending) {
            [expired addObject:key];
        }
    }
    [YTKACEOnesieSessions removeObjectsForKeys:expired];
    if (YTKACEOnesieSessions.count <= 16) return;
    NSArray<NSString *> *keys = [YTKACEOnesieSessions keysSortedByValueUsingComparator:
        ^NSComparisonResult(YTKACEOnesieSessionState *left,
                            YTKACEOnesieSessionState *right) {
            return [left.capturedAt compare:right.capturedAt];
        }];
    NSUInteger removeCount = YTKACEOnesieSessions.count - 16;
    [YTKACEOnesieSessions removeObjectsForKeys:
        [keys subarrayWithRange:NSMakeRange(0, removeCount)]];
}

static void YTKACECaptureOnesieSession(id factory,
                                       id playerRequest,
                                       id authorization,
                                       id dataLoader,
                                       id context,
                                       id cryptor,
                                       NSInteger requestNumber,
                                       BOOL asynchronous) {
    if (factory == nil || playerRequest == nil || dataLoader == nil ||
        context == nil || cryptor == nil) {
        return;
    }
    NSString *videoID = YTKACERequestVideoID(playerRequest);
    if (videoID.length == 0) videoID = YTKACELastCapturedVideoID;
    YTKACEOnesieSessionState *state = [YTKACEOnesieSessionState new];
    state.factory = factory;
    state.playerRequest = YTKACECopyObject(playerRequest);
    state.authorization = YTKACECopyObject(authorization);
    state.dataLoader = dataLoader;
    state.context = context;
    state.cryptor = cryptor;
    state.videoID = videoID ?: @"";
    state.observedRequestNumber = requestNumber;
    state.nextRequestNumber = requestNumber + 1;
    state.asynchronous = asynchronous;
    state.capturedAt = NSDate.date;
    @synchronized (YTKACESABRDownloader.class) {
        if (YTKACEOnesieSessions == nil) {
            YTKACEOnesieSessions = [NSMutableDictionary dictionary];
        }
        YTKACELastOnesieSession = state;
        if (videoID.length != 0) YTKACEOnesieSessions[videoID] = state;
        YTKACEPruneOnesieSessions();
    }
    YTKACEDownloadLog(@"native", @"session video=%@ rn=%ld mode=%@",
        videoID ?: @"unknown", (long)requestNumber,
        asynchronous ? @"async" : @"sync");
}

static YTKACEOnesieSessionState *YTKACEOnesieSessionForVideo(
    NSString *videoID) {
    @synchronized (YTKACESABRDownloader.class) {
        YTKACEPruneOnesieSessions();
        YTKACEOnesieSessionState *state = YTKACEOnesieSessions[videoID];
        if (state != nil) return state;
        if (YTKACELastOnesieSession.videoID.length == 0 ||
            [YTKACELastOnesieSession.videoID isEqualToString:videoID]) {
            return YTKACELastOnesieSession;
        }
        return nil;
    }
}

BOOL YTKACEHasNativeOnesieSession(NSString *videoID) {
    return YTKACEOnesieSessionForVideo(videoID) != nil;
}

void YTKACEBuildNativeOnesieRequest(
    NSString *videoID,
    YTKACENativeRequestCompletion completion) {
    YTKACEOnesieSessionState *state = YTKACEOnesieSessionForVideo(videoID);
    if (state == nil) {
        completion(nil, NSNotFound, [NSError errorWithDomain:@"YTKACEOnesie"
            code:1 userInfo:@{NSLocalizedDescriptionKey:
                @"No native Onesie session is available."}]);
        return;
    }
    NSInteger requestNumber = 0;
    @synchronized (YTKACESABRDownloader.class) {
        requestNumber = MAX(state.nextRequestNumber,
            state.observedRequestNumber + 1);
        state.nextRequestNumber = requestNumber + 1;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (state.asynchronous && OriginalOnesieRequestAsync != NULL) {
            void (^nativeCompletion)(id, NSError *) = ^(id result, NSError *error) {
                NSURLRequest *request = YTKACEURLRequestFromObject(result);
                if (request != nil) YTKACESABRSetNativeRequest(request);
                completion(request, requestNumber, error);
            };
            ((void (*)(id, SEL, id, id, id, id, id, NSInteger, id))
                OriginalOnesieRequestAsync)(
                    state.factory,
                    NSSelectorFromString(
                        @"onesieRequestForPlayerRequest:authorization:dataLoader:"
                         "context:cryptor:requestNumber:completionHandler:"),
                    YTKACECopyObject(state.playerRequest), state.authorization,
                    state.dataLoader, state.context, state.cryptor,
                    requestNumber, nativeCompletion);
            return;
        }
        if (OriginalOnesieRequest != NULL) {
            NSError *error = nil;
            id result = ((id (*)(id, SEL, id, id, id, id, NSInteger, NSError **))
                OriginalOnesieRequest)(
                    state.factory,
                    NSSelectorFromString(
                        @"onesieRequestForPlayerRequest:dataLoader:context:"
                         "cryptor:requestNumber:error:"),
                    YTKACECopyObject(state.playerRequest), state.dataLoader,
                    state.context, state.cryptor, requestNumber, &error);
            NSURLRequest *request = YTKACEURLRequestFromObject(result);
            if (request != nil) YTKACESABRSetNativeRequest(request);
            completion(request, requestNumber, error);
            return;
        }
        completion(nil, requestNumber, [NSError errorWithDomain:@"YTKACEOnesie"
            code:2 userInfo:@{NSLocalizedDescriptionKey:
                @"YouTube's native Onesie factory is unavailable."}]);
    });
}

static id YTKACEOnesieRequest(id receiver,
                              SEL selector,
                              id playerRequest,
                              id dataLoader,
                              id context,
                              id cryptor,
                              NSInteger requestNumber,
                              NSError **error) {
    id result = OriginalOnesieRequest != NULL
        ? ((id (*)(id, SEL, id, id, id, id, NSInteger, NSError **))OriginalOnesieRequest)(
            receiver, selector, playerRequest, dataLoader, context, cryptor,
            requestNumber, error)
        : nil;
    NSURLRequest *builtRequest = YTKACEURLRequestFromObject(result);
    if (builtRequest != nil) {
        NSURLRequest *request = builtRequest;
        YTKACESABRSetNativeRequest(request);
        YTKACEDownloadLog(@"native", @"request host=%@ bytes=%lu",
            request.URL.host, (unsigned long)request.HTTPBody.length);
    }
    YTKACECaptureOnesieSession(receiver, playerRequest, nil, dataLoader,
        context, cryptor, requestNumber, NO);
    return result;
}

static void YTKACEOnesieRequestAsync(id receiver,
                                     SEL selector,
                                     id playerRequest,
                                     id authorization,
                                     id dataLoader,
                                     id context,
                                     id cryptor,
                                     NSInteger requestNumber,
                                     void (^completion)(id, NSError *)) {
    void (^wrapped)(id, NSError *) = ^(id result, NSError *error) {
        NSURLRequest *builtRequest = YTKACEURLRequestFromObject(result);
        if (builtRequest != nil) {
            NSURLRequest *request = builtRequest;
            YTKACESABRSetNativeRequest(request);
            YTKACEDownloadLog(@"native", @"request host=%@ bytes=%lu",
                request.URL.host, (unsigned long)request.HTTPBody.length);
        }
        YTKACECaptureOnesieSession(receiver, playerRequest, authorization,
            dataLoader, context, cryptor, requestNumber, YES);
        if (completion != nil) completion(result, error);
    };
    if (OriginalOnesieRequestAsync != NULL) {
        ((void (*)(id, SEL, id, id, id, id, id, NSInteger, id))OriginalOnesieRequestAsync)(
            receiver, selector, playerRequest, authorization, dataLoader, context,
            cryptor, requestNumber, wrapped);
    }
}

static void YTKACEOnesieRequestCompletion(id receiver,
                                          SEL selector,
                                          id request,
                                          id error) {
    YTKACEDownloadLog(@"native", @"completion request=%@ error=%@",
        request ? NSStringFromClass([request class]) : @"nil",
        error ? NSStringFromClass([error class]) : @"nil");
    NSURLRequest *builtRequest = YTKACEURLRequestFromObject(request);
    if (builtRequest != nil) {
        NSURLRequest *URLRequest = builtRequest;
        YTKACESABRSetNativeRequest(URLRequest);
        YTKACEDownloadLog(@"native", @"request host=%@ bytes=%lu",
            URLRequest.URL.host, (unsigned long)URLRequest.HTTPBody.length);
    }
    if (OriginalOnesieRequestCompletion != NULL) {
        ((void (*)(id, SEL, id, id))OriginalOnesieRequestCompletion)(
            receiver, selector, request, error);
    }
}

static id YTKACEHAMBuildURLRequest(id receiver, SEL selector) {
    id result = OriginalHAMBuildURLRequest != NULL
        ? ((id (*)(id, SEL))OriginalHAMBuildURLRequest)(receiver, selector)
        : nil;
    if ([result isKindOfClass:NSURLRequest.class]) {
        NSURLRequest *request = result;
        NSString *host = request.URL.host.lowercaseString;
        if ([host containsString:@"googlevideo.com"] &&
            [request.HTTPMethod.uppercaseString isEqualToString:@"POST"]) {
            NSData *rawBody = nil;
            SEL bodySelector = NSSelectorFromString(@"HTTPBody");
            if ([receiver respondsToSelector:bodySelector]) {
                rawBody = ((id (*)(id, SEL))objc_msgSend)(receiver, bodySelector);
            }
            NSMutableURLRequest *nativeRequest = [request mutableCopy];
            if ([rawBody isKindOfClass:NSData.class] && rawBody.length != 0) {
                nativeRequest.HTTPBody = rawBody;
                [nativeRequest setValue:nil forHTTPHeaderField:@"Content-Encoding"];
            }
            YTKACESABRSetNativeRequest(nativeRequest);
            YTKACEDownloadLog(@"native-network", @"host=%@ raw=%lu encoded=%lu",
                request.URL.host, (unsigned long)nativeRequest.HTTPBody.length,
                (unsigned long)request.HTTPBody.length);
        }
    }
    return result;
}

static id YTKACEGetValue(id object, NSArray<NSString *> *keys) {
    if (object == nil) return nil;
    for (NSString *key in keys) {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            if (value != nil) return value;
        }
        @try {
            id value = [object valueForKey:key];
            if (value != nil) return value;
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static BOOL YTKACESetValue(id object, NSString *key, id value) {
    if (object == nil || key.length == 0) return NO;
    NSString *first = [[key substringToIndex:1] uppercaseString];
    NSString *setterName = [NSString stringWithFormat:@"set%@%@:", first,
        [key substringFromIndex:1]];
    SEL setter = NSSelectorFromString(setterName);
    if ([object respondsToSelector:setter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(object, setter, value);
        return YES;
    }
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static id YTKACECopyObject(id object) {
    if ([object respondsToSelector:@selector(copyWithZone:)]) {
        return [object copy];
    }
    return object;
}

static NSString *YTKACERequestVideoID(id request) {
    id value = YTKACEGetValue(request, @[@"videoId", @"videoID", @"videoIdString"]);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static void YTKACECaptureService(id receiver, id request) {
    NSString *videoID = YTKACERequestVideoID(request);
    if (videoID.length != 0) YTKACELastCapturedVideoID = videoID;
    YTKACESABRSetCurrentVideoID(videoID);
    id requestCopy = YTKACECopyObject(request);
    @synchronized (YTKACESABRDownloader.class) {
        YTKACELastPlayerService = receiver;
        YTKACELastPlayerRequest = requestCopy;
        if (YTKACEPlayerRequests == nil) YTKACEPlayerRequests = [NSMutableDictionary dictionary];
        if (videoID.length != 0) {
            YTKACEPlayerRequests[videoID] = @[receiver, requestCopy ?: request];
        }
    }
    YTKACEDownloadLog(@"reload", @"captured request video=%@ class=%@",
        videoID ?: @"unknown", NSStringFromClass([request class]));
}

static void YTKACEMakePlayerRequest(id receiver,
                                    SEL selector,
                                    id request,
                                    id responseBlock,
                                    id errorBlock) {
    YTKACECaptureService(receiver, request);
    if (OriginalMakePlayerRequest != NULL) {
        ((void (*)(id, SEL, id, id, id))OriginalMakePlayerRequest)(
            receiver, selector, request, responseBlock, errorBlock
        );
    }
}

static id YTKACEMakePlaybackRequest(id receiver,
                                    SEL selector,
                                    id request,
                                    id responseBlock,
                                    id errorBlock) {
    YTKACECaptureService(receiver, request);
    @synchronized (YTKACESABRDownloader.class) {
        YTKACELastPlaybackRequest = YTKACECopyObject(request);
        NSString *videoID = YTKACERequestVideoID(request);
        if (YTKACEPlaybackRequests == nil) {
            YTKACEPlaybackRequests = [NSMutableDictionary dictionary];
        }
        if (videoID.length != 0) {
            YTKACEPlaybackRequests[videoID] = YTKACECopyObject(request);
        }
    }
    return OriginalMakePlaybackRequest != NULL
        ? ((id (*)(id, SEL, id, id, id))OriginalMakePlaybackRequest)(
            receiver, selector, request, responseBlock, errorBlock)
        : nil;
}

static void YTKACEMakePrefetchPlayerRequest(id receiver,
                                            SEL selector,
                                            id request,
                                            id responseBlock,
                                            id errorBlock) {
    YTKACECaptureService(receiver, request);
    if (OriginalMakePrefetchPlayerRequest != NULL) {
        ((void (*)(id, SEL, id, id, id))OriginalMakePrefetchPlayerRequest)(
            receiver, selector, request, responseBlock, errorBlock
        );
    }
}

static void YTKACECaptureFactory(id receiver, id request, id properties, id result) {
    NSString *videoID = YTKACERequestVideoID(request);
    if (videoID.length != 0) YTKACELastCapturedVideoID = videoID;
    YTKACESABRSetCurrentVideoID(videoID);
    @synchronized (YTKACESABRDownloader.class) {
        YTKACELastPlayerFactory = receiver;
        YTKACELastPlayerRequest = YTKACECopyObject(request);
        YTKACELastRequestProperties = properties;
        if (videoID.length != 0 && YTKACELastPlayerService != nil) {
            if (YTKACEPlayerRequests == nil) {
                YTKACEPlayerRequests = [NSMutableDictionary dictionary];
            }
            YTKACEPlayerRequests[videoID] = @[
                YTKACELastPlayerService, YTKACECopyObject(request)
            ];
            if (YTKACELastPlaybackRequest != nil) {
                if (YTKACEPlaybackRequests == nil) {
                    YTKACEPlaybackRequests = [NSMutableDictionary dictionary];
                }
                YTKACEPlaybackRequests[videoID] =
                    YTKACECopyObject(YTKACELastPlaybackRequest);
            }
        }
    }
    YTKACEDownloadLog(@"reload", @"factory request video=%@ request=%@ result=%@",
        videoID ?: @"unknown", NSStringFromClass([request class]),
        NSStringFromClass([result class]));
}

static id YTKACEFactoryRequest(id receiver, SEL selector, id request, id properties) {
    YTKACESABRSetCurrentVideoID(YTKACERequestVideoID(request));
    id result = OriginalFactoryRequest != NULL
        ? ((id (*)(id, SEL, id, id))OriginalFactoryRequest)(receiver, selector, request, properties)
        : nil;
    YTKACECaptureFactory(receiver, request, properties, result);
    return result;
}

static id YTKACEFactoryRequestExtended(id receiver,
                                       SEL selector,
                                       id request,
                                       id properties,
                                       BOOL relaxation,
                                       id cacheToken,
                                       BOOL skipCache) {
    YTKACESABRSetCurrentVideoID(YTKACERequestVideoID(request));
    id result = OriginalFactoryRequestExtended != NULL
        ? ((id (*)(id, SEL, id, id, BOOL, id, BOOL))OriginalFactoryRequestExtended)(
            receiver, selector, request, properties, relaxation, cacheToken, skipCache)
        : nil;
    YTKACECaptureFactory(receiver, request, properties, result);
    return result;
}

static void YTKACEInstallPlayerServiceHook(void) {
    BOOL serviceInstalled = YTKACEInstallInstanceHook(
        @"YTPlayerService",
        @"makePlayerRequest:responseBlock:errorBlock:",
        (IMP)YTKACEMakePlayerRequest,
        &OriginalMakePlayerRequest
    );
    BOOL playbackInstalled = YTKACEInstallInstanceHook(
        @"YTPlayerService",
        @"makePlaybackRequest:responseBlock:errorBlock:",
        (IMP)YTKACEMakePlaybackRequest,
        &OriginalMakePlaybackRequest
    );
    BOOL prefetchInstalled = YTKACEInstallInstanceHook(
        @"YTPlayerService",
        @"makePrefetchPlayerRequest:responseBlock:errorBlock:",
        (IMP)YTKACEMakePrefetchPlayerRequest,
        &OriginalMakePrefetchPlayerRequest
    );
    BOOL factoryInstalled = YTKACEInstallInstanceHook(
        @"YTPlayerRequestFactoryImpl",
        @"requestForPlayerWithPlayerRequest:URLRequestProperties:",
        (IMP)YTKACEFactoryRequest,
        &OriginalFactoryRequest
    );
    BOOL extendedInstalled = YTKACEInstallInstanceHook(
        @"YTPlayerRequestFactoryImpl",
        @"requestForPlayerWithPlayerRequest:URLRequestProperties:enablePlayerResponseCacheKeyRelaxation:playerResponseCacheToken:skipInnertubeCacheLookup:",
        (IMP)YTKACEFactoryRequestExtended,
        &OriginalFactoryRequestExtended
    );
    BOOL onesieInstalled = YTKACEInstallInstanceHook(
        @"MLOnesieRequestFactory",
        @"onesieRequestForPlayerRequest:dataLoader:context:cryptor:requestNumber:error:",
        (IMP)YTKACEOnesieRequest,
        &OriginalOnesieRequest
    );
    BOOL onesieAsyncInstalled = YTKACEInstallInstanceHook(
        @"MLOnesieRequestFactory",
        @"onesieRequestForPlayerRequest:authorization:dataLoader:context:cryptor:requestNumber:completionHandler:",
        (IMP)YTKACEOnesieRequestAsync,
        &OriginalOnesieRequestAsync
    );
    BOOL onesieCompletionInstalled = YTKACEInstallInstanceHook(
        @"MLOnesieUMPFetcherTask",
        @"onRequestFactoryCompletionWithRequest:error:",
        (IMP)YTKACEOnesieRequestCompletion,
        &OriginalOnesieRequestCompletion
    );
    BOOL HAMRequestInstalled = YTKACEInstallInstanceHook(
        @"HAMDataLoadRequest",
        @"buildURLRequest",
        (IMP)YTKACEHAMBuildURLRequest,
        &OriginalHAMBuildURLRequest
    );
    if (serviceInstalled && playbackInstalled && prefetchInstalled &&
        factoryInstalled && extendedInstalled && onesieInstalled &&
        onesieAsyncInstalled && onesieCompletionInstalled && HAMRequestInstalled) {
        YTKACEDownloadLog(@"reload", @"player path hooked");
        return;
    }
    YTKACEPlayerHookAttempts += 1;
    if (YTKACEPlayerHookAttempts >= 30) {
        YTKACEDownloadLog(@"reload", @"player path unavailable service=%d playback=%d prefetch=%d factory=%d extended=%d onesie=%d async=%d completion=%d ham=%d",
            serviceInstalled, playbackInstalled, prefetchInstalled,
            factoryInstalled, extendedInstalled, onesieInstalled,
            onesieAsyncInstalled, onesieCompletionInstalled, HAMRequestInstalled);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{ YTKACEInstallPlayerServiceHook(); });
}

void YTKACEPreparePlayer(NSString *videoID,
                         YTKACEPlayerReloadCompletion completion) {
    id service = nil;
    id request = nil;
    id playbackRequest = nil;
    @synchronized (YTKACESABRDownloader.class) {
        NSArray *pair = YTKACEPlayerRequests[videoID];
        service = pair.count > 0 ? pair[0] : nil;
        request = pair.count > 1 ? pair[1] : nil;
        playbackRequest = YTKACEPlaybackRequests[videoID];
        if (service == nil &&
            [YTKACERequestVideoID(YTKACELastPlayerRequest) isEqualToString:videoID]) {
            service = YTKACELastPlayerService;
            request = YTKACELastPlayerRequest;
            playbackRequest = YTKACELastPlaybackRequest;
        }
    }
    if (service == nil || request == nil) {
        NSError *error = [NSError errorWithDomain:@"YTKACEPlayerPrepare" code:1
            userInfo:@{NSLocalizedDescriptionKey:
                @"YouTube has not created a player request for this video."}];
        completion(nil, error);
        return;
    }
    YTKACESABRSetCurrentVideoID(videoID);
    YTKACEDownloadLog(@"prepare", @"native request video=%@ route=%@", videoID,
        playbackRequest != nil && OriginalMakePlaybackRequest != NULL
            ? @"playback" : @"player");
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^response)(id, id) = ^(id playerResponse, __unused id cacheContext) {
            completion(playerResponse, nil);
        };
        void (^failure)(NSError *) = ^(NSError *error) {
            completion(nil, error);
        };
        if (playbackRequest != nil && OriginalMakePlaybackRequest != NULL) {
            ((id (*)(id, SEL, id, id, id))OriginalMakePlaybackRequest)(
                service,
                NSSelectorFromString(@"makePlaybackRequest:responseBlock:errorBlock:"),
                YTKACECopyObject(playbackRequest), response, failure);
        } else if (OriginalMakePlayerRequest != NULL) {
            ((void (*)(id, SEL, id, id, id))OriginalMakePlayerRequest)(
                service,
                NSSelectorFromString(@"makePlayerRequest:responseBlock:errorBlock:"),
                YTKACECopyObject(request), response, failure);
        } else {
            NSError *error = [NSError errorWithDomain:@"YTKACEPlayerPrepare" code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    @"YouTube's player service is unavailable."}];
            completion(nil, error);
        }
    });
}

void YTKACEReloadPlayer(NSString * _Nullable videoID,
                        NSString *token,
                        YTKACEPlayerReloadCompletion completion) {
    id service = nil;
    id request = nil;
    id playbackRequest = nil;
    @synchronized (YTKACESABRDownloader.class) {
        NSArray *pair = videoID.length != 0 ? YTKACEPlayerRequests[videoID] : nil;
        service = pair.count > 0 ? pair[0] : YTKACELastPlayerService;
        request = pair.count > 1 ? pair[1] : YTKACELastPlayerRequest;
        playbackRequest = YTKACELastPlaybackRequest;
    }
    if ((OriginalMakePlayerRequest == NULL && OriginalMakePlaybackRequest == NULL) ||
        service == nil || request == nil || token.length == 0) {
        NSError *error = [NSError errorWithDomain:@"YTKACEPlayerReload" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"No matching YouTube player request is available."}];
        completion(nil, error);
        return;
    }
    id mutableRequest = YTKACECopyObject(request);
    id playback = YTKACECopyObject(YTKACEGetValue(mutableRequest, @[@"playbackContext"]));
    if (playback == nil) playback = [NSClassFromString(@"YTIPlaybackContext") new];
    id params = [NSClassFromString(@"YTIReloadPlaybackParams") new];
    id reload = [NSClassFromString(@"YTIReloadPlaybackContext") new];
    BOOL configured = YTKACESetValue(params, @"token", token) &&
        YTKACESetValue(reload, @"reloadPlaybackParams", params) &&
        YTKACESetValue(playback, @"reloadPlaybackContext", reload) &&
        YTKACESetValue(mutableRequest, @"playbackContext", playback);
    if (!configured) {
        NSError *error = [NSError errorWithDomain:@"YTKACEPlayerReload" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"YouTube's reload request could not be configured."}];
        completion(nil, error);
        return;
    }
    id routedRequest = nil;
    if (playbackRequest != nil && OriginalMakePlaybackRequest != NULL) {
        Class playbackClass = NSClassFromString(@"YTPlaybackRequest");
        SEL initializer = NSSelectorFromString(
            @"initWithProtoRequest:URLRequestProperties:CPN:QOEController:latencyLogger:streamingWatchEnabled:enablePlayerResponseCacheKeyRelaxation:playerResponseCacheToken:streamingWatchHandlers:");
        id allocated = [playbackClass alloc];
        if ([allocated respondsToSelector:initializer]) {
            BOOL streaming = ((BOOL (*)(id, SEL))objc_msgSend)(
                playbackRequest, NSSelectorFromString(@"streamingWatchEnabled"));
            BOOL relaxation = ((BOOL (*)(id, SEL))objc_msgSend)(
                playbackRequest, NSSelectorFromString(@"enablePlayerResponseCacheKeyRelaxation"));
            routedRequest = ((id (*)(id, SEL, id, id, id, id, id, BOOL, BOOL, id, id))objc_msgSend)(
                allocated,
                initializer,
                mutableRequest,
                YTKACEGetValue(playbackRequest, @[@"URLRequestProperties"]),
                YTKACEGetValue(playbackRequest, @[@"CPN"]),
                YTKACEGetValue(playbackRequest, @[@"QOEController"]),
                YTKACEGetValue(playbackRequest, @[@"latencyLogger"]),
                streaming,
                relaxation,
                YTKACEGetValue(playbackRequest, @[@"playerResponseCacheToken"]),
                YTKACEGetValue(playbackRequest, @[@"streamingWatchHandlers"])
            );
        }
    }
    YTKACEDownloadLog(@"reload", @"native request video=%@ token=%lu route=%@",
        videoID ?: @"unknown", (unsigned long)token.length,
        routedRequest != nil ? @"playback" : @"player");
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^response)(id, id) = ^(id playerResponse, __unused id cacheContext) {
            YTKACEDownloadLog(@"reload", @"native response video=%@ class=%@",
                videoID ?: @"unknown", NSStringFromClass([playerResponse class]));
            completion(playerResponse, nil);
        };
        void (^failure)(NSError *) = ^(NSError *error) {
            YTKACEDownloadLog(@"reload", @"native error video=%@ error=%@",
                videoID ?: @"unknown", error.localizedDescription ?: @"unknown");
            completion(nil, error);
        };
        if (routedRequest != nil && OriginalMakePlaybackRequest != NULL) {
            ((id (*)(id, SEL, id, id, id))OriginalMakePlaybackRequest)(
                service, NSSelectorFromString(@"makePlaybackRequest:responseBlock:errorBlock:"),
                routedRequest, response, failure
            );
        } else {
            ((void (*)(id, SEL, id, id, id))OriginalMakePlayerRequest)(
                service, NSSelectorFromString(@"makePlayerRequest:responseBlock:errorBlock:"),
                mutableRequest, response, failure
            );
        }
    });
}

static id YTKACEMintWithVideoID(id receiver, SEL selector, id videoID) {
    if ([videoID isKindOfClass:NSString.class]) YTKACESABRSetCurrentVideoID(videoID);
    id result = nil;
    if (OriginalMintWithVideoID != NULL) {
        result = ((id (*)(id, SEL, id))OriginalMintWithVideoID)(receiver, selector, videoID);
    }
    YTKACEDownloadLog(@"token", @"media mint video=%@ result=%@",
        videoID, result ? NSStringFromClass([result class]) : @"nil");
    YTKACESABRSetPoToken(result);
    return result;
}

static void YTKACESetPlayerResponse(id receiver,
                                    SEL selector,
                                    id playerResponse,
                                    id cpn) {
    if (OriginalSetPlayerResponse != NULL) {
        ((void (*)(id, SEL, id, id))OriginalSetPlayerResponse)(
            receiver, selector, playerResponse, cpn
        );
    }
    YTKACEDownloadCoordinator.sharedCoordinator.playerResponse = playerResponse;
}

static void YTKACESetPoToken(id receiver, SEL selector, NSData *token) {
    if (OriginalSetPoToken != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPoToken)(receiver, selector, token);
    }
    YTKACESABRSetPoToken(token);
}

void YTKACEInstallDownloadHooks(void) {
    YTKACEInstallInstanceHook(@"YTProofOfOriginTokenManager",
                              @"mintWithVideoID:",
                              (IMP)YTKACEMintWithVideoID,
                              &OriginalMintWithVideoID);
    YTKACEInstallInstanceHook(@"YTIServiceIntegrityDimensions",
                              @"setPoToken:",
                              (IMP)YTKACESetPoToken,
                              &OriginalSetPoToken);
    YTKACEInstallPlayerServiceHook();
    YTKACEInstallInstanceHook(@"MLOnesieRequestFactory",
                              @"onesieRequestForPlayerRequest:dataLoader:context:cryptor:requestNumber:error:",
                              (IMP)YTKACEOnesieRequest,
                              &OriginalOnesieRequest);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"setPlayerResponse:CPN:",
                              (IMP)YTKACESetPlayerResponse,
                              &OriginalSetPlayerResponse);

    YTKACERegisterOverlayConfigurator(@"downloads", ^(UIView *overlay, UIStackView *stack) {
        (void)overlay;
        UIButton *button = YTKACEOverlayButton(
            stack,
            @"YTKACE Download",
            @"arrow.down.circle.fill",
            YTKACEDownloadCoordinator.sharedCoordinator,
            @selector(showDownloadMenuFromButton:)
        );
        [button setImage:YTKACEDownloadGlyphImage()
                forState:UIControlStateNormal];
        button.hidden = !YTKACEFeatureEnabled(YTKACEDownloadKey);
    });
}
