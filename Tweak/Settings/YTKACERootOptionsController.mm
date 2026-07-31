#import "YTKACERootOptionsController.h"
#import "../YTKACE.h"
#import "YTKACEDownloadsController.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"
#import "../UI/Notice.h"
#import "../Features/Downloads/DownloadLog.h"

#import <objc/runtime.h>
#import <stdlib.h>
#import <sys/utsname.h>

static UIColor *YTKACERootBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIColor *YTKACERootCellBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIImage *YTKACETemplateImage(NSString *asset, NSString *symbol) {
    return [YTKACEAssetImage(asset, symbol)
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *YTKACESponsorIcon(void) {
    return YTKACETemplateImage(@"sponsorblock_shield_template",
                               @"play.shield");
}

static const void *YTKACEDismissTargetKey = &YTKACEDismissTargetKey;

@interface YTKACEDismissTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
- (void)dismiss;
- (void)pop;
@end

@implementation YTKACEDismissTarget
- (void)dismiss {
    [self.controller dismissViewControllerAnimated:YES completion:nil];
}
- (void)pop {
    [self.controller.navigationController popViewControllerAnimated:YES];
}
@end

static const void *YTKACEOwnedNavigationKey = &YTKACEOwnedNavigationKey;

BOOL YTKACEOwnsNavigationController(UINavigationController *navigation) {
    if (navigation == nil) return NO;
    return [objc_getAssociatedObject(navigation, YTKACEOwnedNavigationKey) boolValue];
}

void YTKACEApplyAppearance(UIViewController *controller) {
    controller.view.backgroundColor = YTKACERootBackground();
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    UINavigationController *navigation = controller.navigationController;
    if (!YTKACEOwnsNavigationController(navigation)) {
        if (navigation != nil &&
            controller.navigationItem.leftBarButtonItem == nil &&
            navigation.viewControllers.firstObject != controller) {
            YTKACEDismissTarget *target = [YTKACEDismissTarget new];
            target.controller = controller;
            objc_setAssociatedObject(controller, YTKACEDismissTargetKey, target,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIImageSymbolConfiguration *symbolConfiguration =
                [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                                  weight:UIImageSymbolWeightSemibold];
            UIImage *chevron =
                [UIImage systemImageNamed:@"chevron.backward"
                        withConfiguration:symbolConfiguration];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *configuration =
                [UIButtonConfiguration plainButtonConfiguration];
            configuration.image = chevron;
            configuration.title = YTKACELocalized(@"Back");
            configuration.imagePadding = 4.0;
            configuration.contentInsets =
                NSDirectionalEdgeInsetsMake(0.0, 8.0, 0.0, 4.0);
            button.configuration = configuration;
            [button addTarget:target action:@selector(pop)
                forControlEvents:UIControlEventTouchUpInside];
            UIBarButtonItem *back =
                [[UIBarButtonItem alloc] initWithCustomView:button];
            controller.navigationItem.leftBarButtonItem = back;
            controller.navigationItem.hidesBackButton = YES;
        }
        return;
    }
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = YTKACERootBackground();
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: UIColor.labelColor
        };
        navigation.navigationBar.standardAppearance = appearance;
        navigation.navigationBar.scrollEdgeAppearance = appearance;
        navigation.navigationBar.compactAppearance = appearance;
    }
}

@interface YTKACEDownloadLogController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@end

@implementation YTKACEDownloadLogController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Download Log");
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:13.0
        weight:UIFontWeightRegular];
    self.textView.textContainerInset = UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0);
    [self.view addSubview:self.textView];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain
            target:self action:@selector(clearLog)],
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain
            target:self action:@selector(copyLog)]
    ];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    YTKACEApplyAppearance(self);
    self.textView.backgroundColor = YTKACERootBackground();
    self.textView.textColor = UIColor.labelColor;
    self.textView.text = YTKACEDownloadLogContents();
    NSRange end = NSMakeRange(self.textView.text.length, 0);
    [self.textView scrollRangeToVisible:end];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = self.textView.text;
    YTKACEShowNotice(@"Download log copied");
}

- (void)clearLog {
    YTKACEClearDownloadLog();
    self.textView.text = YTKACEDownloadLogContents();
}

@end

@interface YTKACERootOptionsController ()
@property(nonatomic, strong) UIView *settingsHeader;
@end

@implementation YTKACERootOptionsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = 18.0;
    self.tableView.sectionFooterHeight = 4.0;
    self.settingsHeader = [self makeSettingsHeader];
    self.tableView.tableHeaderView = self.settingsHeader;
    UILongPressGestureRecognizer *developerHold =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleDeveloperHold:)];
    developerHold.minimumPressDuration = 3.0;
    developerHold.cancelsTouchesInView = YES;
    [self.tableView addGestureRecognizer:developerHold];
}

- (void)showDownloadLog {
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    [self.navigationController pushViewController:
        [YTKACEDownloadLogController new] animated:YES];
}

- (void)handleDeveloperHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:
        [recognizer locationInView:self.tableView]];
    if (indexPath.section == 3 && indexPath.row == 0) {
        [self showDownloadLog];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACERootBackground();
    self.settingsHeader.backgroundColor = YTKACERootBackground();
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat difference = CGRectGetWidth(self.settingsHeader.frame) - width;
    difference = difference < 0.0 ? -difference : difference;
    if (width > 0.0 && difference > 0.5) {
        CGRect frame = self.settingsHeader.frame;
        frame.size.width = width;
        self.settingsHeader.frame = frame;
        self.tableView.tableHeaderView = self.settingsHeader;
    }
}

- (UIView *)makeSettingsHeader {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) {
        width = CGRectGetWidth(self.view.bounds);
    }
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 128.0)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(8.0, 8.0, 40.0, 40.0);
    [close setImage:YTKACETemplateImage(@"close_20pt_3x_Normal", @"xmark")
            forState:UIControlStateNormal];
    close.tintColor = UIColor.labelColor;
    close.accessibilityLabel = YTKACELocalized(@"Close");
    [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    UIButton *language = [UIButton buttonWithType:UIButtonTypeSystem];
    language.frame = CGRectMake(width - 88.0, 8.0, 40.0, 40.0);
    language.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [language setImage:YTKACETemplateImage(@"translate_symbol_Normal", @"character.book.closed")
               forState:UIControlStateNormal];
    language.tintColor = UIColor.labelColor;
    language.accessibilityLabel = YTKACELocalized(@"Language");
    [language addTarget:self action:@selector(showLanguageInfo) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:language];

    UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
    apply.frame = CGRectMake(width - 48.0, 8.0, 40.0, 40.0);
    apply.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [apply setImage:YTKACETemplateImage(@"check_24pt_3x_Normal", @"checkmark")
            forState:UIControlStateNormal];
    apply.tintColor = UIColor.labelColor;
    apply.accessibilityLabel = YTKACELocalized(@"Apply Settings");
    [apply addTarget:self action:@selector(applySettings) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:apply];

    UIImageView *logo = [[UIImageView alloc] initWithImage:YTKACEAssetImage(@"YTKIco", @"play.square.fill")];
    logo.frame = CGRectMake((width - 26.0) * 0.5, 11.0, 26.0, 26.0);
    logo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    logo.contentMode = UIViewContentModeScaleAspectFit;
    [header addSubview:logo];

    UIView *topSeparator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 49.5, width, 0.5)];
    topSeparator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topSeparator.backgroundColor = UIColor.separatorColor;
    [header addSubview:topSeparator];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 61.0, width - 96.0, 32.0)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"YTKACE";
    title.font = [UIFont boldSystemFontOfSize:29.0];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.labelColor;
    [header addSubview:title];

    UILabel *version = [[UILabel alloc] initWithFrame:CGRectMake(48.0, 95.0, width - 96.0, 18.0)];
    version.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    version.text = [NSString stringWithFormat:@"v%@", YTKACEVersion];
    version.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    version.textAlignment = NSTextAlignmentCenter;
    version.textColor = UIColor.secondaryLabelColor;
    [header addSubview:version];

    return header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return 1;
        case 1: return 6;
        case 2: return 5;
        case 3: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 3 ? @"DEVELOPER" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"Tap the top-right button to apply changes." : nil;
}

- (NSString *)deviceInformationText {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *model = [NSString stringWithUTF8String:systemInfo.machine] ?: @"iOS Device";
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *youtubeVersion = info[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"com.google.ios.youtube";
    return [NSString stringWithFormat:@"v%@ - v%@ ✓ (Compatible)\n%@\n%@ - iOS %@",
        YTKACEVersion, youtubeVersion, bundleID, model,
        UIDevice.currentDevice.systemVersion];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) {
        return 70.0;
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return 62.0;
    }
    if (indexPath.section == 3 && indexPath.row == 1) {
        return 92.0;
    }
    return 46.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 0.01;
    if (section == 3) return 30.0;
    return 12.0;
}

- (UITableViewCell *)baseCellForTableView:(UITableView *)tableView
                                    style:(UITableViewCellStyle)style {
    NSString *identifier = [NSString stringWithFormat:@"YTKACERoot-%ld", (long)style];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    }
    cell.backgroundColor = YTKACERootCellBackground();
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.textLabel.font = [UIFont systemFontOfSize:18.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.tintColor = UIColor.labelColor;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)configureImageForCell:(UITableViewCell *)cell
                         asset:(NSString *)asset
                         symbol:(NSString *)symbol {
    cell.imageView.image = YTKACETemplateImage(asset, symbol);
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleSubtitle];
        cell.textLabel.text = YTKACELocalized(@"Enable");
        cell.textLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"YTKACE features";
        [self configureImageForCell:cell asset:@"on_off" symbol:@"power"];
        UILabel *state = [UILabel new];
        state.frame = CGRectMake(0.0, 0.0, 58.0, 40.0);
        state.text = YTKACEMasterEnabled() ? @"Active" : @"Inactive";
        state.textColor = YTKACEMasterEnabled() ? UIColor.systemGreenColor : UIColor.systemRedColor;
        state.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
        state.textAlignment = NSTextAlignmentRight;
        UISwitch *toggle = [UISwitch new];
        toggle.transform = CGAffineTransformMakeScale(0.95, 0.95);
        toggle.onTintColor = UIColor.systemBlueColor;
        toggle.frame = CGRectMake(68.0, 4.5, toggle.intrinsicContentSize.width,
                                  toggle.intrinsicContentSize.height);
        toggle.on = YES;
        toggle.enabled = NO;
        UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 126.0, 40.0)];
        [accessory addSubview:state];
        [accessory addSubview:toggle];
        cell.accessoryView = accessory;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == 1) {
        NSArray *titles = @[@"Player Controls", @"SponsorBlock", @"Tab Bar", @"Wi-Fi Quality", @"Cellular Quality", @"Gestures"];
        NSArray *assets = @[@"play_square_stack_24pt_3x_Normal", @"", @"tab_bar_Google", @"wifi_symbol_Normal", @"hd_24pt_3x_Normal", @"gesture_swipe_left_24pt_3x_Normal"];
        NSArray *symbols = @[@"play.rectangle", @"shield", @"list.bullet", @"wifi", @"antenna.radiowaves.left.and.right", @"hand.draw"];
        UITableViewCellStyle style = indexPath.row == 0 ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
        UITableViewCell *cell = [self baseCellForTableView:tableView style:style];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        [self configureImageForCell:cell asset:assets[(NSUInteger)indexPath.row] symbol:symbols[(NSUInteger)indexPath.row]];
        if (indexPath.row == 1) cell.imageView.image = YTKACESponsorIcon();
        if (indexPath.row == 0) {
            cell.detailTextLabel.text = YTKACELocalized(@"Downloads, background play, and more");
        } else if (indexPath.row == 3) {
            cell.detailTextLabel.text = YTKACEPickerSummary(@"wiFiPlaybackIndex", @[@"Auto", @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p", @"240p", @"144p"], @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12], 0);
        } else if (indexPath.row == 4) {
            cell.detailTextLabel.text = YTKACEPickerSummary(@"celluarPlaybackIndex", @[@"Auto", @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p", @"240p", @"144p"], @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12], 0);
        }
        cell.detailTextLabel.textColor = indexPath.row >= 3 && indexPath.row <= 4
            ? UIColor.systemBlueColor
            : UIColor.secondaryLabelColor;
        cell.accessoryType = (indexPath.row == 3 || indexPath.row == 4)
            ? UITableViewCellAccessoryNone
            : UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 2) {
        NSArray *titles = @[@"Overlay", @"Streaming", @"Navigation Bar", @"Shorts", @"Miscellaneous"];
        NSArray *assets = @[@"play_square_stack_24pt_3x_Normal", @"clapperboard_24pt_3x_Normal", @"nav_bar_google", @"shorts_24pt_3x_Normal", @"shuffle_24pt_3x_Normal"];
        NSArray *symbols = @[@"rectangle.on.rectangle", @"film", @"rectangle.topthird.inset.filled", @"bolt", @"ellipsis"];
        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleDefault];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        [self configureImageForCell:cell asset:assets[(NSUInteger)indexPath.row] symbol:symbols[(NSUInteger)indexPath.row]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.row == 1) {
        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleDefault];
        cell.textLabel.text = [self deviceInformationText];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        cell.textLabel.numberOfLines = 3;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleValue1];
    cell.textLabel.text = YTKACELocalized(@"itzzace");
    cell.detailTextLabel.text = @"YTKACE";
    cell.imageView.image = YTKACEAssetImage(@"YTKIco", @"person.crop.circle");
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3 && indexPath.row == 0) {
        NSURL *URL = [NSURL URLWithString:@"https://github.com/Epic0001/YTKACE"];
        [UIApplication.sharedApplication openURL:URL options:@{}
                               completionHandler:nil];
        return;
    }
    UIViewController *controller = nil;
    if (indexPath.section == 1) {
        if (indexPath.row == 3 || indexPath.row == 4) {
            NSString *title = indexPath.row == 3 ? @"Wi-Fi Quality" : @"Cellular Quality";
            NSString *key = indexPath.row == 3 ? @"wiFiPlaybackIndex" : @"celluarPlaybackIndex";
            NSArray *titles = @[@"Auto", @"2160p60", @"2160p", @"1440p60", @"1440p",
                                @"1080p60", @"1080p", @"720p60", @"720p", @"480p",
                                @"360p", @"240p", @"144p"];
            NSArray *values = @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12];
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            YTKACEPresentChoiceMenu(self, cell, title, titles, values, key, 0,
                ^(__unused NSUInteger position) {
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                          withRowAnimation:UITableViewRowAnimationNone];
                });
            return;
        }
        NSArray *builders = @[
            [^UIViewController *{ return YTKACEMakePlayerControlsController(); } copy],
            [^UIViewController *{ return YTKACEMakeSponsorBlockController(); } copy],
            [^UIViewController *{ return YTKACEMakeTabBarOptionsController(); } copy],
            [^UIViewController *{ return nil; } copy],
            [^UIViewController *{ return nil; } copy],
            [^UIViewController *{ return YTKACEMakeGestureOptionsController(); } copy]
        ];
        UIViewController *(^builder)(void) = builders[(NSUInteger)indexPath.row];
        controller = builder();
    } else if (indexPath.section == 2) {
        NSArray *builders = @[
            [^UIViewController *{ return YTKACEMakeOverlayOptionsController(); } copy],
            [^UIViewController *{ return YTKACEMakeStreamingOptionsController(); } copy],
            [^UIViewController *{ return YTKACEMakeNavigationOptionsController(); } copy],
            [^UIViewController *{ return YTKACEMakeShortsOptionsController(); } copy],
            [^UIViewController *{ return YTKACEMakeMiscOptionsController(); } copy]
        ];
        UIViewController *(^builder)(void) = builders[(NSUInteger)indexPath.row];
        controller = builder();
    }
    if (controller != nil) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)masterChanged:(UISwitch *)sender {
    (void)sender;
    YTKACESetPreference(YTKACEMasterEnabledKey, YES);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:UITableViewRowAnimationNone];
}

- (void)applySettings {
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:@"YTKACEPreferencesDidChange"
                                                      object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"YTKACETabConfigDidChange"
                                                      object:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

- (void)showLanguageInfo {
    YTKACEShowNotice(@"YTKACE follows your YouTube language.");
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

UINavigationController *YTKACEMakeSettingsNavigationController(void) {
    YTKACERootOptionsController *root = [YTKACERootOptionsController new];
    UINavigationController *navigation = [[UINavigationController alloc]
        initWithRootViewController:root];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    objc_setAssociatedObject(navigation, YTKACEOwnedNavigationKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return navigation;
}
