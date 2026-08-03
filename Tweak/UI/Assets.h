#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSBundle * _Nullable YTKACEAssetsBundle(void);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEAssetImage(
    NSString *name,
    NSString * _Nullable fallbackSymbol
);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEYouTubeImage(
    NSArray<NSString *> *names,
    NSString * _Nullable fallbackSymbol
);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEGearImage(void);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEShortsImage(BOOL selected);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEDownloadTabImage(BOOL selected);

NS_ASSUME_NONNULL_END
