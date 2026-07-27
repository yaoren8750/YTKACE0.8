#import "SponsorPreferences.h"
#import "../../Runtime/Preferences.h"

NSArray<NSDictionary<NSString *, NSString *> *> *YTKACESponsorCategoryDefinitions(void) {
    static NSArray *definitions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definitions = @[
            @{@"id": @"sponsor", @"title": @"Sponsor", @"color": @"#00D400"},
            @{@"id": @"selfpromo", @"title": @"Self Promotion", @"color": @"#FFFF00"},
            @{@"id": @"interaction", @"title": @"Interaction Reminder", @"color": @"#CC00FF"},
            @{@"id": @"intro", @"title": @"Intermission / Intro", @"color": @"#00FFFF"},
            @{@"id": @"outro", @"title": @"Endcards / Credits", @"color": @"#0202ED"},
            @{@"id": @"preview", @"title": @"Preview / Recap", @"color": @"#008FD6"},
            @{@"id": @"music_offtopic", @"title": @"Non-Music Section", @"color": @"#FF9900"},
            @{@"id": @"filler", @"title": @"Filler", @"color": @"#7300FF"},
            @{@"id": @"poi_highlight", @"title": @"Highlight", @"color": @"#FF1684"}
        ];
    });
    return definitions;
}

NSString *YTKACESponsorBehaviorKey(NSString *category) {
    return [@"YTKACESponsorBehavior." stringByAppendingString:category ?: @""];
}

NSString *YTKACESponsorColorKey(NSString *category) {
    return [@"YTKACESponsorColor." stringByAppendingString:category ?: @""];
}

static NSDictionary<NSString *, NSString *> *YTKACESponsorDefinition(NSString *category) {
    for (NSDictionary *definition in YTKACESponsorCategoryDefinitions()) {
        if ([definition[@"id"] isEqualToString:category]) return definition;
    }
    return nil;
}

NSInteger YTKACESponsorCategoryBehavior(NSString *category) {
    id stored = YTKACEPreferenceObject(YTKACESponsorBehaviorKey(category));
    if ([stored respondsToSelector:@selector(integerValue)]) {
        return MAX(0, MIN([stored integerValue], 3));
    }
    if ([category isEqualToString:@"sponsor"]) {
        id legacy = YTKACEPreferenceObject(@"sbSkipMode");
        return [legacy respondsToSelector:@selector(integerValue)] &&
            [legacy integerValue] == 1 ? 1 : 0;
    }
    return 2;
}

NSArray<NSString *> *YTKACESponsorEnabledCategories(void) {
    NSMutableArray *categories = [NSMutableArray array];
    for (NSDictionary *definition in YTKACESponsorCategoryDefinitions()) {
        NSString *category = definition[@"id"];
        if (YTKACESponsorCategoryBehavior(category) != 2) {
            [categories addObject:category];
        }
    }
    return categories;
}

static UIColor *YTKACEColorFromHex(NSString *hex) {
    NSString *value = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#"
                                                              withString:@""] uppercaseString];
    if (value.length != 6) return UIColor.systemGreenColor;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

UIColor *YTKACESponsorCategoryColor(NSString *category) {
    NSDictionary *definition = YTKACESponsorDefinition(category);
    NSString *stored = YTKACEPreferenceObject(YTKACESponsorColorKey(category));
    NSString *hex = [stored isKindOfClass:NSString.class] && stored.length != 0
        ? stored : definition[@"color"];
    return YTKACEColorFromHex(hex);
}

NSInteger YTKACESponsorNotificationMode(void) {
    id stored = YTKACEPreferenceObject(@"YTKACESponsorNotificationMode");
    return [stored respondsToSelector:@selector(integerValue)]
        ? MAX(0, MIN([stored integerValue], 2)) : 0;
}

static NSTimeInterval YTKACESponsorDuration(NSString *key) {
    id stored = YTKACEPreferenceObject(key);
    double value = [stored respondsToSelector:@selector(doubleValue)]
        ? [stored doubleValue] : 4.0;
    return MAX(1.0, MIN(value, 10.0));
}

NSTimeInterval YTKACESponsorSkipAlertDuration(void) {
    return YTKACESponsorDuration(@"YTKACESponsorSkipAlertDuration");
}

NSTimeInterval YTKACESponsorUnskipAlertDuration(void) {
    return YTKACESponsorDuration(@"YTKACESponsorUnskipAlertDuration");
}
