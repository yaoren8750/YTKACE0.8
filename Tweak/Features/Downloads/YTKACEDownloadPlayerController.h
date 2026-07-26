#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat YTKACEDownloadProgressRatio(NSURL *URL);

@class AVPlayer;

extern NSNotificationName const YTKACEDownloadPlaybackDidChangeNotification;
extern NSNotificationName const YTKACEDownloadPlaybackDidStopNotification;

@interface YTKACEDownloadPlaybackSession : NSObject

+ (instancetype)sharedSession;

@property(nonatomic, strong, readonly) AVPlayer *player;
@property(nonatomic, copy, readonly, nullable) NSURL *currentURL;
@property(nonatomic, copy, readonly) NSArray<NSURL *> *playlist;
@property(nonatomic, assign, readonly) NSInteger currentIndex;
@property(nonatomic, assign) BOOL autoplayEnabled;
@property(nonatomic, assign) BOOL gesturesEnabled;
@property(nonatomic, assign) BOOL repeatEnabled;
@property(nonatomic, assign) BOOL pauseAtEnd;
@property(nonatomic, assign) float playbackRate;

- (void)loadURL:(NSURL *)URL
       playlist:(NSArray<NSURL *> *)playlist
          index:(NSInteger)index;
- (void)updatePlaylist:(NSArray<NSURL *> *)playlist;
- (void)play;
- (void)pause;
- (void)togglePlayback;
- (void)seekBy:(NSTimeInterval)seconds;
- (void)playNext;
- (void)playPrevious;
- (void)stop;

@end

@interface YTKACEDownloadPlayerController : UIViewController

- (instancetype)initWithSession:(YTKACEDownloadPlaybackSession *)session;
@property(nonatomic, copy, nullable) dispatch_block_t minimizeHandler;

@end

NS_ASSUME_NONNULL_END
