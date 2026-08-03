#import "Assets.h"

NSBundle *YTKACEAssetsBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"YTKACE"
                                                       ofType:@"bundle"];
        if (path.length != 0) {
            bundle = [NSBundle bundleWithPath:path];
        }
    });
    return bundle;
}

UIImage *YTKACEAssetImage(NSString *name, NSString *fallbackSymbol) {
    UIImage *image = nil;
    NSBundle *bundle = YTKACEAssetsBundle();
    if (bundle != nil && name.length != 0) {
        image = [UIImage imageNamed:name
                           inBundle:bundle
      compatibleWithTraitCollection:nil];
    }
    if (image == nil && fallbackSymbol.length != 0) {
        if (@available(iOS 13.0, *)) {
            image = [UIImage systemImageNamed:fallbackSymbol];
        }
    }
    return image;
}

UIImage *YTKACEYouTubeImage(NSArray<NSString *> *names, NSString *fallbackSymbol) {
    for (NSString *name in names) {
        UIImage *image = [UIImage imageNamed:name];
        if (image != nil) return image;
    }
    return fallbackSymbol.length == 0 ? nil : [UIImage systemImageNamed:fallbackSymbol];
}

UIImage *YTKACEGearImage(void) {
    return YTKACEYouTubeImage(@[
        @"yt_outline_gear_24pt",
        @"yt_outline_gear_vd_theme_24",
        @"yt_outline_experimental_gear_vd_theme_24"
    ], @"gearshape");
}

UIImage *YTKACEShortsImage(BOOL selected) {
    return selected
        ? YTKACEYouTubeImage(@[
            @"yt_fill_youtube_shorts_24pt",
            @"yt_fill_youtube_shorts_vd_theme_24"
        ], @"play.rectangle.fill")
        : YTKACEYouTubeImage(@[
            @"yt_outline_youtube_shorts_24pt",
            @"yt_outline_youtube_shorts_vd_theme_24"
        ], @"play.rectangle");
}

UIImage *YTKACEDownloadTabImage(BOOL selected) {
    return [UIImage systemImageNamed:selected
        ? @"arrow.down.square.fill" : @"arrow.down.square"];
}
