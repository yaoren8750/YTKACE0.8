#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const YTKACELanguageKey;

FOUNDATION_EXPORT NSString *YTKACELocalized(NSString *key);
FOUNDATION_EXPORT NSArray<NSString *> *YTKACEAvailableLanguages(void);
FOUNDATION_EXPORT NSString *YTKACELanguageDisplayName(NSString *code);
FOUNDATION_EXPORT void YTKACEResetLocalizationCache(void);

NS_ASSUME_NONNULL_END
