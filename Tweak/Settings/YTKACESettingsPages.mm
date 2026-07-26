#import "YTKACESettingsPages.h"
#import "YTKACERootOptionsController.h"
#import "YTKACETabEditorController.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"
#import "../UI/Notice.h"
#import "../Features/Downloads/YTKACEBackupManager.h"
#import "../Features/Downloads/YTKACEMediaImporter.h"
#import "../Features/SponsorBlock/SponsorPreferences.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

typedef UIViewController * _Nonnull (^YTKACEControllerBuilder)(void);
typedef void (^YTKACEAction)(UIViewController *controller);

static const void *YTKACEItemAssociation = &YTKACEItemAssociation;
static const void *YTKACEValueLabelAssociation = &YTKACEValueLabelAssociation;

static NSArray<NSString *> *YTKACELocalizedList(NSArray<NSString *> *titles) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:titles.count];
    for (NSString *title in titles) {
        [out addObject:YTKACELocalized(title)];
    }
    return out;
}

static NSDictionary *YTKACEToggle(NSString *title,
                                   NSString *key,
                                   NSString *asset,
                                   NSString *symbol) {
    return @{
        @"type": @"toggle",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"asset": asset ?: @"",
        @"symbol": symbol ?: @""
    };
}

static NSDictionary *YTKACEToggleDetail(NSString *title,
                                         NSString *subtitle,
                                         NSString *key) {
    return @{
        @"type": @"toggle",
        @"title": YTKACELocalized(title),
        @"subtitle": YTKACELocalized(subtitle ?: @""),
        @"key": key,
        @"asset": @"",
        @"symbol": @""
    };
}

static NSDictionary *YTKACEPicker(NSString *title,
                                   NSString *key,
                                   NSArray<NSString *> *titles,
                                   NSArray *values,
                                   NSUInteger defaultIndex,
                                   NSString *asset,
                                   NSString *symbol) {
    return @{
        @"type": @"picker",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"titles": YTKACELocalizedList(titles),
        @"values": values,
        @"default": @(defaultIndex),
        @"asset": asset ?: @"",
        @"symbol": symbol ?: @""
    };
}

static NSDictionary *YTKACEStepper(NSString *title,
                                    NSString *key,
                                    double minimum,
                                    double maximum,
                                    double step,
                                    double fallback) {
    return @{
        @"type": @"stepper",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"minimum": @(minimum),
        @"maximum": @(maximum),
        @"step": @(step),
        @"fallback": @(fallback)
    };
}

static NSDictionary *YTKACESegmented(NSString *title,
                                      NSString *key,
                                      NSArray<NSString *> *titles,
                                      NSArray *values,
                                      NSUInteger defaultIndex) {
    return @{
        @"type": @"segmented",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"titles": YTKACELocalizedList(titles),
        @"values": values,
        @"default": @(defaultIndex)
    };
}

static NSDictionary *YTKACESegmentedStacked(NSString *title,
                                            NSString *key,
                                            NSArray<NSString *> *titles,
                                            NSArray *values,
                                            NSUInteger defaultIndex) {
    return @{
        @"type": @"segmented",
        @"stacked": @YES,
        @"title": YTKACELocalized(title),
        @"key": key,
        @"titles": YTKACELocalizedList(titles),
        @"values": values,
        @"default": @(defaultIndex)
    };
}

static NSDictionary *YTKACESlider(NSString *title,
                                   NSString *key,
                                   double minimum,
                                   double maximum,
                                   double step,
                                   double fallback) {
    return @{
        @"type": @"slider",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"minimum": @(minimum),
        @"maximum": @(maximum),
        @"step": @(step),
        @"fallback": @(fallback)
    };
}

static NSDictionary *YTKACEColor(NSString *title,
                                 NSString *key,
                                 NSString *fallback) {
    return @{
        @"type": @"color",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"fallback": fallback
    };
}

static NSString *YTKACEHexFromColor(UIColor *color) {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"#00D400";
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(red * 255.0), (int)lround(green * 255.0),
            (int)lround(blue * 255.0)];
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

static NSDictionary *YTKACEText(NSString *text) {
    return @{
        @"type": @"text",
        @"title": text
    };
}

static NSDictionary *YTKACEActionDetail(NSString *title,
                                         NSString *subtitle,
                                         YTKACEAction action) {
    return @{
        @"type": @"action",
        @"title": YTKACELocalized(title),
        @"subtitle": YTKACELocalized(subtitle ?: @""),
        @"asset": @"",
        @"symbol": @"",
        @"action": [action copy]
    };
}

static UIColor *YTKACESettingsBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIColor *YTKACESettingsCellBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

BOOL YTKACEPreferenceNeedsRestart(NSString *key) {
    return [@[
        YTKACEOLEDKey,
        @"kEnableUsePremiumLogo",
        @"kEnableHideYTLogo",
        @"kEnableiPadOSMode",
        @"kEnableDisableRTL",
        @"kEnableLegacyQSelection",
        @"kEnableHideStatusBar",
        @"kEnabledStartupPage",
        @"kEnablefixvideoplayback"
    ] containsObject:key];
}

void YTKACEShowRestartNotice(UIViewController *controller) {
    UIView *host = controller.navigationController.view ?: controller.view;
    UIView *old = [host viewWithTag:0x594B524E];
    [old removeFromSuperview];
    UILabel *notice = [UILabel new];
    notice.tag = 0x594B524E;
    notice.text = @"Restart YouTube to apply changes.";
    notice.textColor = UIColor.labelColor;
    notice.backgroundColor = [UIColor colorWithWhite:0.72 alpha:0.96];
    notice.font = [UIFont systemFontOfSize:13.0];
    notice.layer.cornerRadius = 8.0;
    notice.layer.masksToBounds = YES;
    notice.textAlignment = NSTextAlignmentLeft;
    notice.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:notice];
    UILayoutGuide *safe = host.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [notice.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8.0],
        [notice.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
        [notice.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8.0],
        [notice.heightAnchor constraintEqualToConstant:48.0]
    ]];
    notice.alpha = 0.0;
    [UIView animateWithDuration:0.2 animations:^{ notice.alpha = 1.0; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.2 animations:^{ notice.alpha = 0.0; }
                         completion:^(__unused BOOL finished) { [notice removeFromSuperview]; }];
    });
}

static void YTKACEStorePickerValue(NSString *key, id value, NSUInteger index) {
    YTKACESetPreferenceObject(key, value);
    if ([key isEqualToString:@"kEnabledStartupPage"]) {
        NSArray *browseIDs = @[@"FEwhat_to_watch", @"FEexplore", @"FEsubscriptions",
                               @"FEshorts", @"FElibrary"];
        if (index < browseIDs.count) {
            YTKACESetPreferenceObject(@"kStartupPageID", browseIDs[index]);
        }
    }
}

static UIImage *YTKACEBlankChoiceIcon(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24.0, 24.0), NO, 0.0);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

void YTKACEPresentSelectionMenu(UIViewController *presenter,
                                UIView *sourceView,
                                NSString *title,
                                NSArray<NSString *> *titles,
                                NSUInteger selectedIndex,
                                YTKACEChoiceHandler handler) {
    (void)title;
    if (titles.count == 0) {
        return;
    }
    selectedIndex = MIN(selectedIndex, titles.count - 1);
    Class sheetClass = NSClassFromString(@"YTDefaultSheetController");
    Class actionClass = NSClassFromString(@"YTActionSheetAction");
    SEL makeSheet = NSSelectorFromString(
        @"sheetControllerWithMessage:subMessage:delegate:parentResponder:");
    SEL makeAction = NSSelectorFromString(@"actionWithTitle:iconImage:style:handler:");
    if (sheetClass != Nil && actionClass != Nil &&
        [sheetClass respondsToSelector:makeSheet] &&
        [actionClass respondsToSelector:makeAction]) {
        id sheet = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
            sheetClass, makeSheet, nil, nil, nil, nil);
        UIImage *check = [[UIImage systemImageNamed:@"checkmark"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImage *blank = YTKACEBlankChoiceIcon();
        [titles enumerateObjectsUsingBlock:^(NSString *choice, NSUInteger index, BOOL *stop) {
            (void)stop;
            dispatch_block_t selection = ^{
                if (handler != nil) {
                    handler(index);
                }
            };
            id action = ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)(
                actionClass, makeAction, choice,
                index == selectedIndex ? check : blank, 0, selection);
            SEL addAction = NSSelectorFromString(@"addAction:");
            if ([sheet respondsToSelector:addAction]) {
                ((void (*)(id, SEL, id))objc_msgSend)(sheet, addAction, action);
            }
        }];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
            sourceView != nil &&
            [sheet respondsToSelector:NSSelectorFromString(@"presentFromView:animated:completion:")]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, NSSelectorFromString(@"presentFromView:animated:completion:"),
                sourceView, YES, nil);
        } else if ([sheet respondsToSelector:
                    NSSelectorFromString(@"presentFromViewController:animated:completion:")]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, NSSelectorFromString(@"presentFromViewController:animated:completion:"),
                presenter, YES, nil);
        }
        return;
    }
    YTKACEShowNotice(@"YouTube menu unavailable");
}

void YTKACEPresentChoiceMenu(UIViewController *presenter,
                             UIView *sourceView,
                             NSString *title,
                             NSArray<NSString *> *titles,
                             NSArray *values,
                             NSString *key,
                             NSUInteger defaultIndex,
                             YTKACEChoiceHandler handler) {
    id selected = YTKACEPreferenceObject(key);
    NSUInteger selectedIndex = [values indexOfObject:selected];
    if (selectedIndex == NSNotFound) {
        selectedIndex = MIN(defaultIndex, values.count - 1);
    }
    YTKACEPresentSelectionMenu(presenter, sourceView, title, titles, selectedIndex,
        ^(NSUInteger index) {
            YTKACEStorePickerValue(key, values[index], index);
            if (([key isEqualToString:@"kBrightnessSide"] ||
                 [key isEqualToString:@"kVolumeSide"]) && index < 2) {
                NSString *otherKey = [key isEqualToString:@"kBrightnessSide"]
                    ? @"kVolumeSide" : @"kBrightnessSide";
                id otherValue = YTKACEPreferenceObject(otherKey);
                NSInteger otherSide = otherValue == nil
                    ? ([otherKey isEqualToString:@"kBrightnessSide"] ? 1 : 0)
                    : [otherValue integerValue];
                if (otherSide == [values[index] integerValue]) {
                    YTKACEStorePickerValue(otherKey, @([values[index] integerValue] == 0),
                                           [values[index] integerValue] == 0 ? 1 : 0);
                }
            }
            if (handler != nil) handler(index);
        });
}

NSString *YTKACEPickerSummary(NSString *key,
                              NSArray<NSString *> *titles,
                              NSArray *values,
                              NSUInteger defaultIndex) {
    id selected = YTKACEPreferenceObject(key);
    NSUInteger index = [values indexOfObject:selected];
    if (index == NSNotFound || index >= titles.count) {
        index = MIN(defaultIndex, titles.count - 1);
    }
    return titles.count == 0 ? @"" : titles[index];
}

@interface YTKACEPickerController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title
                           key:(NSString *)key
                        titles:(NSArray<NSString *> *)titles
                        values:(NSArray *)values
                  defaultIndex:(NSUInteger)defaultIndex;
@end

@implementation YTKACEPickerController {
    NSString *_preferenceKey;
    NSArray<NSString *> *_titles;
    NSArray *_values;
    NSUInteger _defaultIndex;
}

- (instancetype)initWithTitle:(NSString *)title
                           key:(NSString *)key
                        titles:(NSArray<NSString *> *)titles
                        values:(NSArray *)values
                  defaultIndex:(NSUInteger)defaultIndex {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self != nil) {
        self.title = title;
        _preferenceKey = [key copy];
        _titles = [titles copy];
        _values = [values copy];
        _defaultIndex = defaultIndex;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (YTKACEOwnsNavigationController(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACESettingsBackground();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_titles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"YTKACEPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }
    id selected = YTKACEPreferenceObject(_preferenceKey);
    NSUInteger selectedIndex = [_values indexOfObject:selected];
    if (selectedIndex == NSNotFound) {
        selectedIndex = MIN(_defaultIndex, _values.count - 1);
    }
    cell.textLabel.text = _titles[(NSUInteger)indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.backgroundColor = YTKACESettingsCellBackground();
    cell.accessoryType = (NSUInteger)indexPath.row == selectedIndex
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id value = _values[(NSUInteger)indexPath.row];
    YTKACEStorePickerValue(_preferenceKey, value, (NSUInteger)indexPath.row);
    [tableView reloadData];
}

@end

@interface YTKACEOptionsController : UITableViewController
    <UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
- (instancetype)initWithTitle:(NSString *)title
                      sections:(NSArray<NSArray<NSDictionary *> *> *)sections
                sectionTitles:(NSArray<NSString *> *)sectionTitles;
@end

@implementation YTKACEOptionsController {
    NSArray<NSArray<NSDictionary *> *> *_sections;
    NSArray<NSString *> *_sectionTitles;
    NSInteger _pickerMode;
    NSString *_importCategory;
    NSString *_colorKey;
    NSIndexPath *_colorPath;
    UIView *_backupOverlay;
    UILabel *_backupOverlayLabel;
    NSURL *_pendingBackupURL;
    BOOL _backupRunning;
    BOOL _restoreRunning;
}

- (instancetype)initWithTitle:(NSString *)title
                      sections:(NSArray<NSArray<NSDictionary *> *> *)sections
                sectionTitles:(NSArray<NSString *> *)sectionTitles {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self != nil) {
        self.title = title;
        _sections = [sections copy];
        _sectionTitles = [sectionTitles copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    self.tableView.rowHeight = 40.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (YTKACEOwnsNavigationController(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACESettingsBackground();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ((NSUInteger)section >= _sectionTitles.count) {
        return nil;
    }
    NSString *title = _sectionTitles[(NSUInteger)section];
    return title.length == 0 ? nil : title;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    NSString *title = (NSUInteger)section < _sectionTitles.count
        ? _sectionTitles[(NSUInteger)section]
        : @"";
    return title.length == 0 ? 18.0 : 38.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"text"]) {
        return 92.0;
    }
    if ([type isEqualToString:@"slider"]) {
        return 58.0;
    }
    if ([type isEqualToString:@"segmented"] && [item[@"stacked"] boolValue]) {
        return 74.0;
    }
    return [item[@"subtitle"] length] == 0 ? 40.0 : 56.0;
}

- (void)tableView:(UITableView *)tableView
willDisplayHeaderView:(UIView *)view
        forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.textLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        header.textLabel.textColor = UIColor.secondaryLabelColor;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    UITableViewCellStyle style = [type isEqualToString:@"picker"]
        ? UITableViewCellStyleValue1
        : ([item[@"subtitle"] length] == 0 ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle);
    NSString *identifier = [NSString stringWithFormat:@"YTKACEOption-%ld", (long)style];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    }

    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"subtitle"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 2;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = YTKACESettingsCellBackground();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.imageView.image = nil;

    if ([type isEqualToString:@"toggle"]) {
        UISwitch *toggle = [UISwitch new];
        toggle.transform = CGAffineTransformMakeScale(0.95, 0.95);
        toggle.onTintColor = UIColor.systemBlueColor;
        id stored = YTKACEPreferenceObject(item[@"key"]);
        toggle.on = [stored respondsToSelector:@selector(boolValue)] && [stored boolValue];
        objc_setAssociatedObject(toggle,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self
                   action:@selector(toggleChanged:)
         forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"segmented"]) {
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:item[@"titles"]];
        id selected = YTKACEPreferenceObject(item[@"key"]);
        NSUInteger selectedIndex = [item[@"values"] indexOfObject:selected];
        control.selectedSegmentIndex = selectedIndex == NSNotFound
            ? [item[@"default"] unsignedIntegerValue]
            : selectedIndex;
        objc_setAssociatedObject(control,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control addTarget:self
                    action:@selector(segmentChanged:)
          forControlEvents:UIControlEventValueChanged];
        if ([item[@"stacked"] boolValue]) {
            for (UIView *existing in cell.contentView.subviews) {
                if (existing.tag == 8801 || existing.tag == 8802) {
                    [existing removeFromSuperview];
                }
            }
            UILabel *caption = [UILabel new];
            caption.tag = 8802;
            caption.text = item[@"title"];
            caption.font = [UIFont systemFontOfSize:16.0];
            caption.textColor = UIColor.labelColor;
            caption.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:caption];
            control.tag = 8801;
            control.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:control];
            UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [caption.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
                [caption.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
                [caption.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                                  constant:8.0],
                [control.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
                [control.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
                [control.topAnchor constraintEqualToAnchor:caption.bottomAnchor
                                                  constant:8.0],
                [control.heightAnchor constraintEqualToConstant:30.0]
            ]];
            cell.textLabel.text = nil;
            cell.accessoryView = nil;
        } else {
            CGFloat width = MAX(128.0, [item[@"titles"] count] * 68.0);
            control.frame = CGRectMake(0.0, 0.0, width, 30.0);
            cell.accessoryView = control;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"stepper"]) {
        double stored = [YTKACEPreferenceObject(item[@"key"]) doubleValue];
        double value = stored > 0.0 ? stored : [item[@"fallback"] doubleValue];
        cell.textLabel.text = [NSString stringWithFormat:@"Seconds: %.0f", value];
        UIStepper *stepper = [UIStepper new];
        stepper.minimumValue = [item[@"minimum"] doubleValue];
        stepper.maximumValue = [item[@"maximum"] doubleValue];
        stepper.stepValue = [item[@"step"] doubleValue];
        stepper.value = value;
        objc_setAssociatedObject(stepper,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(stepper,
                                 YTKACEValueLabelAssociation,
                                 cell,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stepper addTarget:self
                    action:@selector(stepperChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"slider"]) {
        double stored = [YTKACEPreferenceObject(item[@"key"]) doubleValue];
        double value = stored > 0.0 ? stored : [item[@"fallback"] doubleValue];
        UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 158.0, 46.0)];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 158.0, 30.0)];
        slider.minimumValue = [item[@"minimum"] floatValue];
        slider.maximumValue = [item[@"maximum"] floatValue];
        slider.value = (float)value;
        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 28.0, 158.0, 14.0)];
        valueLabel.font = [UIFont systemFontOfSize:10.0];
        valueLabel.textColor = UIColor.tertiaryLabelColor;
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.text = [NSString stringWithFormat:@"%.0f seconds", value];
        objc_setAssociatedObject(slider, YTKACEItemAssociation, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, YTKACEValueLabelAssociation, valueLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [accessory addSubview:slider];
        [accessory addSubview:valueLabel];
        cell.accessoryView = accessory;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"picker"]) {
        cell.detailTextLabel.text = YTKACEPickerSummary(
            item[@"key"],
            item[@"titles"],
            item[@"values"],
            [item[@"default"] unsignedIntegerValue]
        );
        cell.detailTextLabel.textColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if ([type isEqualToString:@"color"]) {
        NSString *stored = YTKACEPreferenceObject(item[@"key"]);
        UIColor *color = YTKACEColorFromHex(
            [stored isKindOfClass:NSString.class] ? stored : item[@"fallback"]);
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 28.0, 28.0)];
        dot.backgroundColor = color;
        dot.layer.cornerRadius = 14.0;
        dot.layer.borderWidth = 2.0;
        dot.layer.borderColor = UIColor.secondaryLabelColor.CGColor;
        cell.accessoryView = dot;
    } else if ([type isEqualToString:@"text"]) {
        cell.textLabel.font = [UIFont systemFontOfSize:10.0];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    NSArray *values = item[@"values"];
    if ((NSUInteger)sender.selectedSegmentIndex < values.count) {
        YTKACESetPreferenceObject(item[@"key"], values[(NSUInteger)sender.selectedSegmentIndex]);
        if (YTKACEPreferenceNeedsRestart(item[@"key"])) {
            YTKACEShowRestartNotice(self);
        }
    }
}

- (void)toggleChanged:(UISwitch *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    NSString *key = item[@"key"];
    YTKACESetPreference(key, sender.isOn);
    if ([key isEqualToString:@"kEnablefixvideoplayback"] && sender.isOn) {
        NSString *message = @"✅ Playback recovery hooks will install on next launch.\n\n"
            @"📍 What this does:\n• Forces iOS guard attestation off\n• Marks heartbeat policy errors non-fatal\n• Swallows halt / cannot-play / error-overlay paths\n• Forces skip-on-playability-error\n\n"
            @"📍 When to use it:\nEnable if videos error out mid-playback, show \"an error occurred,\" or get killed by heartbeat / attestation failures.\n\n"
            @"⚠️ Restart YouTube for the hooks to take effect. Leave off if playback already works — it bypasses server-side stop signals and can mask real issues.";
        if (!YTKACEShowYouTubeDialog(@"Fix Playback & Account Recovery", message)) {
            YTKACEShowNotice(@"Playback recovery guidance unavailable");
        }
    }
    if ([key isEqualToString:YTKACEOLEDKey]) {
        YTKACEApplyAppearance(self);
        self.tableView.backgroundColor = YTKACESettingsBackground();
        [self.tableView reloadData];
    }
    if (YTKACEPreferenceNeedsRestart(key)) {
        YTKACEShowRestartNotice(self);
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    UITableViewCell *cell = objc_getAssociatedObject(sender, YTKACEValueLabelAssociation);
    YTKACESetPreferenceObject(item[@"key"], @(sender.value));
    cell.textLabel.text = [NSString stringWithFormat:@"Seconds: %.0f", sender.value];
}

- (void)sliderChanged:(UISlider *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    UILabel *label = objc_getAssociatedObject(sender, YTKACEValueLabelAssociation);
    double step = MAX(0.1, [item[@"step"] doubleValue]);
    double value = round(sender.value / step) * step;
    YTKACESetPreferenceObject(item[@"key"], @(value));
    label.text = [NSString stringWithFormat:@"%.0f seconds", value];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    UIViewController *controller = nil;
    if ([type isEqualToString:@"controller"]) {
        YTKACEControllerBuilder builder = item[@"builder"];
        controller = builder();
    } else if ([type isEqualToString:@"picker"]) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        YTKACEPresentChoiceMenu(self, cell, item[@"title"], item[@"titles"],
            item[@"values"], item[@"key"],
            [item[@"default"] unsignedIntegerValue], ^(__unused NSUInteger index) {
                NSString *key = item[@"key"];
                if ([key isEqualToString:@"kBrightnessSide"] ||
                    [key isEqualToString:@"kVolumeSide"]) {
                    [self.tableView reloadData];
                } else {
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                          withRowAnimation:UITableViewRowAnimationNone];
                }
                if (YTKACEPreferenceNeedsRestart(item[@"key"])) {
                    YTKACEShowRestartNotice(self);
                }
            });
    } else if ([type isEqualToString:@"action"]) {
        YTKACEAction action = item[@"action"];
        action(self);
    } else if ([type isEqualToString:@"color"]) {
        NSString *stored = YTKACEPreferenceObject(item[@"key"]);
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.title = item[@"title"];
        picker.supportsAlpha = NO;
        picker.selectedColor = YTKACEColorFromHex(
            [stored isKindOfClass:NSString.class] ? stored : item[@"fallback"]);
        picker.delegate = self;
        _colorKey = [item[@"key"] copy];
        _colorPath = indexPath;
        [self presentViewController:picker animated:YES completion:nil];
    }
    if (controller != nil) {
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (_pickerMode == 3) {
        if (_pendingBackupURL != nil) {
            [NSFileManager.defaultManager removeItemAtURL:_pendingBackupURL error:nil];
        }
        _pendingBackupURL = nil;
        _pickerMode = 0;
        return;
    }
    if (urls.count == 0) return;
    NSMutableArray<NSURL *> *scoped = [NSMutableArray array];
    for (NSURL *URL in urls) {
        if ([URL startAccessingSecurityScopedResource]) [scoped addObject:URL];
    }
    if (_pickerMode == 1) {
        _restoreRunning = YES;
        [self setBackupProgressVisible:YES message:@"Restoring Backup..."];
        [YTKACEBackupManager restoreBackupFromURL:urls.firstObject
            completion:^(NSError *error) {
                for (NSURL *URL in scoped) [URL stopAccessingSecurityScopedResource];
                self->_restoreRunning = NO;
                [self setBackupProgressVisible:NO message:nil];
                [self showResult:error == nil ? @"Backup Restored" : @"Restore Failed"
                          message:error.localizedDescription];
            }];
        _pickerMode = 0;
        return;
    }
    NSString *category = _importCategory ?: @"Video";
    [YTKACEMediaImporter importURLs:urls category:category
        completion:^(NSUInteger count, NSError *error) {
            for (NSURL *URL in scoped) [URL stopAccessingSecurityScopedResource];
            NSString *message = error.localizedDescription ?: [NSString
                stringWithFormat:@"%lu item%@ added to %@.",
                (unsigned long)count, count == 1 ? @"" : @"s", category];
            [self showResult:error == nil ? @"Import Complete" : @"Import Failed"
                      message:message];
        }];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously {
    (void)continuously;
    if (_colorKey.length == 0 || color == nil) return;
    YTKACESetPreferenceObject(_colorKey, YTKACEHexFromColor(color));
    if (_colorPath != nil) {
        [self.tableView reloadRowsAtIndexPaths:@[_colorPath]
                              withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (_colorKey.length != 0) {
        YTKACESetPreferenceObject(_colorKey, YTKACEHexFromColor(viewController.selectedColor));
        if (_colorPath != nil) {
            [self.tableView reloadRowsAtIndexPaths:@[_colorPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    _colorKey = nil;
    _colorPath = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    NSInteger mode = _pickerMode;
    _pickerMode = 0;
    if (mode == 3) {
        if (_pendingBackupURL != nil) {
            [NSFileManager.defaultManager removeItemAtURL:_pendingBackupURL error:nil];
        }
        _pendingBackupURL = nil;
        NSString *message = @"The backup was not saved to the Files app.";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!YTKACEShowYouTubeDialog(@"Backup Not Saved", message)) {
                    YTKACEShowNotice(@"Warning: Backup was not saved to Files app.");
                }
            });
    }
}

- (void)setBackupProgressVisible:(BOOL)visible message:(NSString *)message {
    if (!visible) {
        UIView *overlay = _backupOverlay;
        _backupOverlay = nil;
        _backupOverlayLabel = nil;
        [UIView animateWithDuration:0.18 animations:^{
            overlay.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            [overlay removeFromSuperview];
        }];
        return;
    }
    if (_backupOverlay != nil) {
        _backupOverlayLabel.text = message.length == 0 ? @"Please Wait..." : message;
        return;
    }
    UIView *host = self.navigationController.view ?: self.view;
    UIView *overlay = [UIView new];
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.alpha = 0.0;

    UIView *card = [UIView new];
    card.backgroundColor = YTKACEInterfaceSurfaceColor(self.traitCollection);
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = UIColor.labelColor;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];

    UILabel *label = [UILabel new];
    label.text = message.length == 0 ? @"Please Wait..." : message;
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:spinner];
    [card addSubview:label];
    [overlay addSubview:card];
    [host addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:host.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:190.0],
        [card.heightAnchor constraintEqualToConstant:94.0],
        [spinner.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [spinner.topAnchor constraintEqualToAnchor:card.topAnchor constant:17.0],
        [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-17.0]
    ]];
    _backupOverlay = overlay;
    _backupOverlayLabel = label;
    [UIView animateWithDuration:0.18 animations:^{ overlay.alpha = 1.0; }];
}

- (void)performBackup {
    if (_backupRunning) return;
    _backupRunning = YES;
    [self setBackupProgressVisible:YES message:@"Preparing Backup..."];
    __weak YTKACEOptionsController *weakSelf = self;
    [YTKACEBackupManager createBackupWithCompletion:^(NSURL *URL, NSError *error) {
        YTKACEOptionsController *controller = weakSelf;
        if (controller == nil) return;
        controller->_backupRunning = NO;
        [controller setBackupProgressVisible:NO message:nil];
        if (URL == nil || error != nil) {
            NSString *message = error.localizedDescription ?: @"The backup could not be created.";
            if (!YTKACEShowYouTubeDialog(@"Backup Failed", message)) {
                [controller showResult:@"Backup Failed" message:message];
            }
            return;
        }
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForExportingURLs:@[URL] asCopy:YES];
        controller->_pickerMode = 3;
        controller->_pendingBackupURL = URL;
        picker.delegate = controller;
        [controller presentViewController:picker animated:YES completion:nil];
    }];
}

- (void)beginBackup {
    if (_backupRunning) return;
    __weak YTKACEOptionsController *weakSelf = self;
    BOOL shown = YTKACEShowYouTubeConfirmation(
        @"YTKACE",
        @"Do you want to create a backup?",
        @"Create",
        ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf performBackup];
            });
        }
    );
    if (!shown) {
        YTKACEShowNotice(@"Backup confirmation unavailable");
    }
}

- (void)beginRestore {
    if (_restoreRunning) return;
    _pickerMode = 1;
    UTType *zip = [UTType typeWithFilenameExtension:@"zip"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[zip] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)beginImportForCategory:(NSString *)category {
    _pickerMode = 2;
    _importCategory = [category copy];
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:
        UTTypeMovie, UTTypeAudio, UTTypeImage, nil];
    UTType *srt = [UTType typeWithFilenameExtension:@"srt"];
    UTType *vtt = [UTType typeWithFilenameExtension:@"vtt"];
    if (srt != nil) [types addObject:srt];
    if (vtt != nil) [types addObject:vtt];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseImportCategory {
    YTKACEPresentChoiceMenu(self, self.view, @"Import Media",
        @[@"Video", @"Audio", @"Shorts"],
        @[@"Video", @"Audio", @"Shorts"],
        @"YTKACEImportMediaType", 0, ^(NSUInteger index) {
            NSArray *categories = @[@"Video", @"Audio", @"Shorts"];
            [self beginImportForCategory:categories[index]];
        });
}

- (void)showResult:(NSString *)title message:(NSString *)message {
    NSString *notice = message.length != 0
        ? [NSString stringWithFormat:@"%@\n%@", title, message] : title;
    YTKACEShowNotice(notice);
}

@end

static YTKACEOptionsController *YTKACEPage(NSString *title,
                                           NSArray *sections,
                                           NSArray *sectionTitles) {
    return [[YTKACEOptionsController alloc] initWithTitle:title
                                                 sections:sections
                                           sectionTitles:sectionTitles];
}

static NSArray<NSString *> *YTKACEQualityTitles(void) {
    return @[@"Auto", @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60",
             @"1080p", @"720p60", @"720p", @"480p", @"360p", @"240p", @"144p"];
}

static NSArray *YTKACEQualityValues(void) {
    return @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12];
}

UIViewController *YTKACEMakeStartupPickerController(void) {
    return [[YTKACEPickerController alloc]
        initWithTitle:@"Startup Page"
                   key:@"kEnabledStartupPage"
                titles:@[@"Home", @"Explore", @"Subscriptions", @"Shorts", @"You"]
                values:@[@0, @1, @2, @3, @4]
          defaultIndex:0];
}

UIViewController *YTKACEMakeWiFiQualityController(void) {
    return [[YTKACEPickerController alloc] initWithTitle:@"Wi-Fi Quality"
                                                    key:@"wiFiPlaybackIndex"
                                                 titles:YTKACEQualityTitles()
                                                 values:YTKACEQualityValues()
                                           defaultIndex:0];
}

UIViewController *YTKACEMakeCellularQualityController(void) {
    return [[YTKACEPickerController alloc] initWithTitle:@"Cellular Quality"
                                                    key:@"celluarPlaybackIndex"
                                                 titles:YTKACEQualityTitles()
                                                 values:YTKACEQualityValues()
                                           defaultIndex:0];
}

UIViewController *YTKACEMakeSponsorBlockController(void) {
    NSMutableArray *sections = [NSMutableArray arrayWithObject:@[
        YTKACEToggle(@"Enable", YTKACESponsorBlockKey, @"", @""),
        YTKACEToggle(@"Audio Notification", @"AudioNotificationOnSkip", @"", @""),
        YTKACESlider(@"Skip Alert Duration", @"YTKACESponsorSkipAlertDuration",
                     1.0, 10.0, 1.0, 4.0),
        YTKACESlider(@"Unskip Alert Duration", @"YTKACESponsorUnskipAlertDuration",
                     1.0, 10.0, 1.0, 4.0)
    ]];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"MAIN"];
    for (NSDictionary<NSString *, NSString *> *definition in
         YTKACESponsorCategoryDefinitions()) {
        NSString *category = definition[@"id"];
        [sections addObject:@[
            YTKACESegmented(@"Behavior", YTKACESponsorBehaviorKey(category),
                            @[@"Skip", @"Ask", @"Show", @"Off"],
                            @[@0, @1, @3, @2],
                            [category isEqualToString:@"sponsor"] ? 0 : 2),
            YTKACEColor(@"Segment Color", YTKACESponsorColorKey(category),
                        definition[@"color"])
        ]];
        [titles addObject:[definition[@"title"] uppercaseString]];
    }
    return YTKACEPage(YTKACELocalized(@"SponsorBlock"), sections, titles);
}

UIViewController *YTKACEMakePlayerControlsController(void) {
    YTKACEAction backup = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller beginBackup];
    };
    YTKACEAction restore = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller beginRestore];
    };
    YTKACEAction importMedia = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller chooseImportCategory];
    };
    YTKACEAction clearCache = ^(UIViewController *controller) {
        NSURL *cache = [YTKACEApplicationSupportDirectory()
            URLByAppendingPathComponent:@"Cache"
                            isDirectory:YES];
        [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
        [(YTKACEOptionsController *)controller showResult:@"Cache Cleared" message:nil];
    };
    NSArray *progressSection = @[
        YTKACESegmentedStacked(@"Progress bar style", @"kYTKACEProgressBarStyle",
                               @[@"Default", @"Solid color", @"Gradient"], @[@0, @1, @2], 0),
        YTKACEColor(@"Main color", @"kYTKACEProgressMainColor", @"#FF0000"),
        YTKACEColor(@"Gradient highlight", @"kYTKACEProgressGradientColor", @"#8E8EFF"),
        YTKACEColor(@"Scrubber color", @"kYTKACEProgressScrubberColor", @"#FF0000")
    ];
    return YTKACEPage(YTKACELocalized(@"Player Controls"), @[
        progressSection,
        @[
            YTKACEToggle(@"Enable Download Feature", YTKACEDownloadKey, @"", @""),
            YTKACEToggle(@"Enable PiP", YTKACEPiPKey, @"", @""),
            YTKACEToggle(@"Add Loop Toggle", YTKACELoopKey, @"", @""),
            YTKACEToggle(@"Play in Background", YTKACEBackgroundPlaybackKey, @"", @""),
            YTKACEToggle(@"Remove Advertisements", YTKACENoAdsKey, @"", @"")
        ],
        @[
            YTKACEToggle(@"Playback Speed toggles", YTKACESpeedKey, @"", @""),
            YTKACEToggleDetail(@"🔧 Fix Playback & Account Recovery",
                @"🧰 Fixes playback guidance for sideloaded apps.",
                @"kEnablefixvideoplayback")
        ],
        @[
            YTKACEActionDetail(@"Create Backup", @"Export settings and all media as a ZIP file.", backup),
            YTKACEActionDetail(@"Restore Backup", @"Choose a YTKACE ZIP backup from Files.", restore)
        ],
        @[YTKACEActionDetail(@"Import Media", @"Choose Video, Audio, or Shorts, then select media, artwork, and subtitles.", importMedia)],
        @[
            YTKACEPicker(@"Clear on Startup", @"clearonstartup", @[@"Off", @"On"], @[@NO, @YES], 0, @"", @""),
            YTKACEActionDetail(@"Clear Cache", @"Remove downloaded cache files.", clearCache)
        ]
    ], @[@"PROGRESS BAR", @"OVERLAY PLAYER", @"PLAYBACK", @"BACKUP & RESTORE",
         @"IMPORT MEDIA", @"CLEAR CACHE"]);
}

UIViewController *YTKACEMakeTabBarOptionsController(void) {
    return [YTKACETabEditorController new];
}

UIViewController *YTKACEMakeOverlayOptionsController(void) {
    return YTKACEPage(YTKACELocalized(@"Overlay"), @[
        @[
            YTKACEToggle(@"Hide Suggested Videos", @"kEnableHideSuggestedVideo", @"", @""),
            YTKACEToggle(@"Hide Comments", @"kEnableHideComments", @"", @""),
            YTKACEToggle(@"Hide Comment Previews", @"kEnableHideCommentReview", @"", @""),
            YTKACEToggle(@"Hide Comment Guidelines", @"kEnableHideCommentGuidlines", @"", @"")
        ],
        @[
            YTKACEToggle(@"Show Status Bar in Overlay", @"kEnableShowStatusBarInOverlay", @"", @""),
            YTKACEToggle(@"Disable Double Tap", @"kEnableDisableDoubleTap", @"", @""),
            YTKACEToggle(@"Disable Continue Watching", @"kEnableDisableContinueWatching", @"", @""),
            YTKACEToggle(@"Hide Quick Actions", @"kEnableHideOverlayQuickAction", @"", @"")
        ],
        @[
            YTKACEToggle(@"Always Show Play/Pause Button", @"kEnableShowOverlaySmart", @"", @""),
            YTKACEToggle(@"Always Show All Controls", @"kEnableShowMediaController", @"", @""),
            YTKACEToggle(@"Hide Dark Overlay Background", @"kEnableHideDarkOverlayBackground", @"", @""),
            YTKACEToggle(@"Keep Captions On", @"kEnableKeepCaptionOn", @"", @""),
            YTKACEToggle(@"Keep Progress Bar Visible", @"kEnableShowProgressBar", @"", @"")
        ],
        @[
            YTKACEToggle(@"Disable Previous & Next", @"kEnableDisablePreviousNextButton", @"", @""),
            YTKACEToggle(@"Compact Previous & Next", @"kEnablePreviousNextButtonPadding", @"", @""),
            YTKACEToggle(@"Hide Previous & Next", @"kEnableHidePreviousNextButton", @"", @"")
        ],
        @[
            YTKACEToggle(@"Hide Info Card", @"kEnableHideInfoCard", @"", @""),
            YTKACEToggle(@"Hide Watermark", @"kEnableHideWaterMark", @"", @""),
            YTKACEToggle(@"Hide Autoplay Button", @"kEnableHideAutoplayToggle", @"", @""),
            YTKACEToggle(@"Hide Captions Button", @"kEnableHideCaptionsToggle", @"", @""),
            YTKACEToggle(@"Hide Play/Pause", @"kEnableHidePlayPuase", @"", @""),
            YTKACEToggle(@"Hide More/Gear Icon", @"kEnableHideMoreGearIcon", @"", @""),
            YTKACEToggle(@"Hide Cast Button", @"kEnableHideCastButtonOverlay", @"", @""),
            YTKACEToggle(@"Hide Endscreen Videos", @"kEnableHideEndScreenVideos", @"", @""),
            YTKACEToggle(@"Hide Related Videos", @"kEnableHideRelatedVideos", @"", @"")
        ]
    ], @[@"VIDEO PLAYER", @"OVERLAY", @"OVERLAY CONTROLLER", @"PREVIOUS & NEXT BUTTONS", @"HIDE ITEMS"]);
}

UIViewController *YTKACEMakeStreamingOptionsController(void) {
    return YTKACEPage(YTKACELocalized(@"Streaming"), @[
        @[YTKACEToggle(@"Enable Legacy Quality Mode", @"kEnableLegacyQSelection", @"", @"")],
        @[
            YTKACEToggle(@"Custom Skip Duration", @"kEnableCustomDoubleTapToSkipDuration", @"", @""),
            YTKACEStepper(@"Seconds: 10", @"kEnableCustomDoubleTapToSkipChnges", 5.0, 60.0, 5.0, 10.0)
        ],
        @[
            YTKACEToggle(@"Disable Autoplay Videos", @"kEnableDisableAutoplayVideos", @"", @""),
            YTKACEToggle(@"Play HD Videos over 3G/4G/5G", @"kEnablePlayHDVideosOverCellur", @"", @"")
        ]
    ], @[@"", @"DOUBLE TAP OPTIONS", @"STREAMING"]);
}

UIViewController *YTKACEMakeNavigationOptionsController(void) {
    return YTKACEPage(YTKACELocalized(@"Navigation Bar"), @[
        @[YTKACEToggle(@"Hide Status Bar", @"kEnableHideStatusBar", @"", @"")],
        @[
            YTKACEToggle(@"Use Premium Logo", @"kEnableUsePremiumLogo", @"", @""),
            YTKACEToggle(@"Cast Confirmation", @"kEnableCastconfirm", @"", @"")
        ],
        @[
            YTKACEToggle(@"Hide YouTube Logo", @"kEnableHideYTLogo", @"", @""),
            YTKACEToggle(@"Hide Notifications", @"kEnableHideNotificationBill", @"", @""),
            YTKACEToggle(@"Hide Account", @"kEnableHideAccount", @"", @""),
            YTKACEToggle(@"Hide Search", @"kEnableHideSearch", @"", @""),
            YTKACEToggle(@"Hide Cast Button", @"kEnableHideCastButton", @"", @"")
        ]
    ], @[@"STATUS BAR", @"", @"HIDE ITEMS"]);
}

UIViewController *YTKACEMakeShortsOptionsController(void) {
    return YTKACEPage(YTKACELocalized(@"Shorts"), @[
        @[
            YTKACEToggle(@"Enable Bottom Progress Bar", @"shortsProgress", @"", @""),
            YTKACEToggle(@"Auto Skip Shorts", @"autoSkipShorts", @"", @"")
        ],
        @[
            YTKACEToggle(@"Hide Shorts from Feed", @"kEnableHideYTShorts", @"", @""),
            YTKACEToggle(@"Hide Pause Card", @"kEnableBlockShortsOverlays", @"", @""),
            YTKACEToggle(@"Hide Product Recommendations", @"kEnableHideShortsProducts", @"", @""),
            YTKACEToggle(@"Hide Sticker Ads", @"kEnableHideShortsStickerAds", @"", @"")
        ]
    ], @[@"SHORTS", @"HIDE ELEMENTS"]);
}

UIViewController *YTKACEMakeMiscOptionsController(void) {
    NSArray<NSString *> *languageCodes = YTKACEAvailableLanguages();
    NSMutableArray<NSString *> *languageNames =
        [NSMutableArray arrayWithCapacity:languageCodes.count];
    for (NSString *code in languageCodes) {
        [languageNames addObject:YTKACELanguageDisplayName(code)];
    }
    return YTKACEPage(YTKACELocalized(@"Miscellaneous"), @[
        @[
            YTKACEPicker(@"Language", YTKACELanguageKey, languageNames,
                         languageCodes, 0, @"", @"")
        ],
        @[
            YTKACEToggle(@"Enable iPadOS Mode", @"kEnableiPadOSMode", @"", @""),
            YTKACEToggle(@"Disable Drag & Drop", @"kEnableDisableDragDrop", @"", @"")
        ],
        @[
            YTKACEToggle(@"Hide Search History", @"kEnableNoSearchedHistory", @"", @""),
            YTKACEToggle(@"Hide Topic Section", @"kEnableNoTopics", @"", @""),
            YTKACEToggle(@"Hide Premium Popup", @"kEnableNoPremiumpopup", @"", @""),
            YTKACEToggle(@"Hide YouTube Update Popup", @"kEnableNoYTUpdate", @"", @""),
            YTKACEToggle(@"Remove Launch Animation", @"kEnableRemoveLaunchAnimation",
                         @"Starts YouTube faster", @""),
            YTKACEToggle(@"Profile Picture Preview", @"kEnableProfilePictureViewer", @"", @""),
            YTKACEToggle(@"Enable Mini Player for All Videos", @"kEnableMiniPlayerAllVideos", @"", @""),
            YTKACEToggle(@"Hide HUD Alerts", @"kEnableHideHudeAlerts", @"", @""),
            YTKACEToggle(@"Hide Paid Promotion Notice", @"kEnableNoPaidPromotion", @"", @""),
            YTKACEToggle(@"Disable RTL Languages", @"kEnableDisableRTL", @"", @""),
            YTKACEToggle(@"OLED Dark Mode", YTKACEOLEDKey, @"", @""),
            YTKACEToggle(@"Bypass Age Restriction", @"kEnableAgeRestriction", @"", @""),
            YTKACEToggle(@"Disable Captions", @"kEnableDisableCaptions", @"", @"")
        ]
    ], @[YTKACELocalized(@"Language"), @"IPAD MODE", @"MISCELLANEOUS"]);
}

UIViewController *YTKACEMakeGestureOptionsController(void) {
    NSArray *sideTitles = @[@"Right", @"Left", @"Disabled"];
    NSArray *sideValues = @[@0, @1, @2];
    return YTKACEPage(YTKACELocalized(@"Gestures"), @[
        @[
            YTKACEPicker(@"Brightness", @"kBrightnessSide", sideTitles, sideValues, 1, @"", @""),
            YTKACEPicker(@"Volume", @"kVolumeSide", sideTitles, sideValues, 0, @"", @""),
            YTKACEText(@"Set which side controls brightness and volume.\n\nTips:\n1. In portrait mode, swipe down on either side of the player.\n2. In fullscreen, swipe from the bottom area due to YouTube’s gesture handling.")
        ],
        @[
            YTKACEToggle(@"Hold to Seek", @"kEnableHoldToSeek", @"", @""),
            YTKACESlider(@"Seek Duration", @"kSeekDuration", 1.0, 60.0, 1.0, 10.0)
        ]
    ], @[@"VOLUME & BRIGHTNESS GESTURES", @"SEEK SETTINGS"]);
}

UIViewController *YTKACEMakeCreditsController(void) {
    UILabel *label = [UILabel new];
    label.text = @"YTKACE\nClean-room implementation\nMIT licensed code\nBuilt by Epic";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    UIViewController *controller = [UIViewController new];
    controller.title = @"Credits";
    controller.view.backgroundColor = YTKACESettingsBackground();
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:controller.view.leadingAnchor constant:24.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:controller.view.trailingAnchor constant:-24.0]
    ]];
    return controller;
}
