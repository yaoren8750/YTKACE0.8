#import "YTKACETabEditorController.h"
#import "YTKACERootOptionsController.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"

#import <objc/runtime.h>

static const void *YTKACETabSwitchKey = &YTKACETabSwitchKey;

static UIImage *YTKACETabEditorIcon(NSString *token, NSString *fallback) {
    NSDictionary *assets = @{
        @"music": @"yt_outline_music_24pt_3x_Normal",
        @"live": @"live_24pt_3x_Normal",
        @"gaming": @"gaming_24pt_3x_Normal",
        @"news": @"news_24pt_3x_Normal",
        @"sports": @"G_sport",
        @"learning": @"G_Learning",
        @"fashion": @"fashion_24pt_3x_Normal",
        @"playlists": @"playlist",
        @"history": @"history",
        @"notifications": @"ic_notifications_none_3x_Normal",
        @"watchlater": @"clock_24pt_3x_Normal"
    };
    return YTKACEAssetImage(assets[token], fallback);
}

@interface YTKACETabEditorController ()
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *activeTabs;
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *inactiveTabs;
@end

@implementation YTKACETabEditorController

- (instancetype)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = YTKACELocalized(@"Tab Bar");
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 40.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [self loadTabs];
    [self setEditing:YES animated:NO];
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor =
        YTKACEInterfaceBackgroundColor(self.traitCollection);
    [self.tableView reloadData];
}

- (NSMutableDictionary *)tab:(NSString *)token
                       title:(NSString *)title
                      symbol:(NSString *)symbol
                         key:(NSString *)key {
    return [@{
        @"token": token,
        @"title": title,
        @"symbol": symbol,
        @"key": key
    } mutableCopy];
}

- (void)loadTabs {
    NSArray *defaults = @[
        [self tab:@"home" title:@"Home" symbol:@"house" key:@"kHideHome"],
        [self tab:@"shorts" title:@"Shorts" symbol:@"bolt" key:@"kHideShorts"],
        [self tab:@"subscriptions" title:@"Subscriptions" symbol:@"rectangle.stack" key:@"kHideSubscriptions"],
        [self tab:@"library" title:@"Library" symbol:@"person.circle" key:@"kHideLibrary"],
        [self tab:@"ytkace" title:@"YTKACE" symbol:@"arrow.down.circle" key:@"kHideYTKACETab"],
        [self tab:@"create" title:@"Create" symbol:@"plus.circle" key:@"kHideCreate"],
        [self tab:@"music" title:@"Music" symbol:@"music.note" key:@"kHideMusic"],
        [self tab:@"live" title:@"Live" symbol:@"dot.radiowaves.left.and.right" key:@"kHideLive"],
        [self tab:@"gaming" title:@"Gaming" symbol:@"gamecontroller" key:@"kHideGaming"],
        [self tab:@"news" title:@"News" symbol:@"newspaper" key:@"kHideNews"],
        [self tab:@"sports" title:@"Sports" symbol:@"trophy" key:@"kHideSports"],
        [self tab:@"learning" title:@"Learning" symbol:@"graduationcap" key:@"kHideLearning"],
        [self tab:@"fashion" title:@"Fashion" symbol:@"tshirt" key:@"kHideFashion"],
        [self tab:@"playlists" title:@"Playlists" symbol:@"music.note.list" key:@"kHidePlaylists"],
        [self tab:@"history" title:@"History" symbol:@"clock.arrow.circlepath" key:@"kHideHistory"],
        [self tab:@"notifications" title:@"Notifs" symbol:@"bell" key:@"kHideNotifs"],
        [self tab:@"watchlater" title:@"WLater" symbol:@"clock" key:@"kHideWatchLater"]
    ];
    self.activeTabs = [NSMutableArray array];
    self.inactiveTabs = [NSMutableArray array];
    for (NSMutableDictionary *tab in defaults) {
        BOOL initiallyInactive = [@[
            @"create", @"music", @"live", @"gaming", @"news", @"sports",
            @"learning", @"fashion", @"playlists", @"history",
            @"notifications", @"watchlater"
        ] containsObject:tab[@"token"]];
        id stored = YTKACEPreferenceObject(tab[@"key"]);
        BOOL hidden = [stored respondsToSelector:@selector(boolValue)] ? [stored boolValue] : initiallyInactive;
        YTKACESetPreference(tab[@"key"], hidden);
        [(hidden ? self.inactiveTabs : self.activeTabs) addObject:tab];
    }
    NSArray *order = [NSUserDefaults.standardUserDefaults arrayForKey:@"kTabOrder"];
    if (order.count != 0) {
        [self.activeTabs sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSUInteger leftIndex = [order indexOfObject:left[@"token"]];
            NSUInteger rightIndex = [order indexOfObject:right[@"token"]];
            leftIndex = leftIndex == NSNotFound ? NSUIntegerMax : leftIndex;
            rightIndex = rightIndex == NSNotFound ? NSUIntegerMax : rightIndex;
            return leftIndex < rightIndex ? NSOrderedAscending : (leftIndex > rightIndex ? NSOrderedDescending : NSOrderedSame);
        }];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 2;
    if (section == 1) return 1;
    if (section == 2) return (NSInteger)self.activeTabs.count;
    return (NSInteger)self.inactiveTabs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"MAIN";
    if (section == 2) return @"ACTIVE TABS";
    if (section == 3) return @"INACTIVE TABS";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 1 ? 24.0 : 38.0;
}

- (void)tableView:(UITableView *)tableView
willDisplayHeaderView:(UIView *)view
        forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = [UIFont systemFontOfSize:11.0];
    header.textLabel.textColor = UIColor.secondaryLabelColor;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = indexPath.section < 2 ? @"YTKACETabOption" : @"YTKACETabItem";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.backgroundColor = YTKACEInterfaceBackgroundColor(self.traitCollection);
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.indentationLevel = 0;
    cell.indentationWidth = 0.0;

    if (indexPath.section == 0) {
        NSArray *titles = @[@"Hide Tab Labels", @"Prevent Open in Shorts"];
        NSArray *keys = @[@"kHideTabLabels", @"kEnablePreventOpenInShortsTab"];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        UISwitch *toggle = [UISwitch new];
        toggle.transform = CGAffineTransformMakeScale(0.95, 0.95);
        toggle.onTintColor = UIColor.systemBlueColor;
        NSString *key = keys[(NSUInteger)indexPath.row];
        toggle.on = [YTKACEPreferenceObject(key) boolValue];
        objc_setAssociatedObject(toggle, YTKACETabSwitchKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.editingAccessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == 1) {
        cell.textLabel.text = YTKACELocalized(@"Default Startup Tab");
        cell.detailTextLabel.text = YTKACEPickerSummary(@"kEnabledStartupPage", @[@"Home", @"Explore", @"Subscriptions", @"Shorts", @"You"], @[@0, @1, @2, @3, @4], 0);
        cell.detailTextLabel.textColor = UIColor.systemBlueColor;
        return cell;
    }

    NSDictionary *tab = indexPath.section == 2
        ? self.activeTabs[(NSUInteger)indexPath.row]
        : self.inactiveTabs[(NSUInteger)indexPath.row];
    cell.textLabel.text = tab[@"title"];
    NSString *token = tab[@"token"];
    UIImage *image = nil;
    if ([token isEqualToString:@"shorts"]) {
        image = YTKACEAssetImage(@"yt_outline_shorts_black_24pt", @"bolt");
    } else if ([token isEqualToString:@"ytkace"]) {
        image = YTKACEAssetImage(@"dwn_library_outline_24_pt_3x_Normal",
                                 @"arrow.down.square");
    } else {
        image = YTKACETabEditorIcon(token, tab[@"symbol"]);
    }
    cell.imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = UIColor.labelColor;
    cell.showsReorderControl = indexPath.section == 2;
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, YTKACETabSwitchKey);
    YTKACESetPreference(key, sender.isOn);
    YTKACEShowRestartNotice(self);
}

- (BOOL)tableView:(UITableView *)tableView
shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section >= 2;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 2) return UITableViewCellEditingStyleDelete;
    if (indexPath.section == 3) return UITableViewCellEditingStyleInsert;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 2;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    (void)tableView;
    if (proposedDestinationIndexPath.section != 2) {
        return [NSIndexPath indexPathForRow:MAX(0, (NSInteger)self.activeTabs.count - 1) inSection:2];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
      toIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView;
    NSMutableDictionary *tab = self.activeTabs[(NSUInteger)sourceIndexPath.row];
    [self.activeTabs removeObjectAtIndex:(NSUInteger)sourceIndexPath.row];
    [self.activeTabs insertObject:tab atIndex:(NSUInteger)destinationIndexPath.row];
    [self saveOrder];
    YTKACEShowRestartNotice(self);
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableDictionary *tab = editingStyle == UITableViewCellEditingStyleDelete
        ? self.activeTabs[(NSUInteger)indexPath.row]
        : self.inactiveTabs[(NSUInteger)indexPath.row];
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.activeTabs removeObjectAtIndex:(NSUInteger)indexPath.row];
        [self.inactiveTabs addObject:tab];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        [self.inactiveTabs removeObjectAtIndex:(NSUInteger)indexPath.row];
        [self.activeTabs addObject:tab];
    }
    YTKACESetPreference(tab[@"key"], editingStyle == UITableViewCellEditingStyleDelete);
    [self saveOrder];
    [tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)]
             withRowAnimation:UITableViewRowAnimationAutomatic];
    YTKACEShowRestartNotice(self);
}

- (void)saveOrder {
    NSMutableArray *order = [NSMutableArray array];
    for (NSDictionary *tab in self.activeTabs) {
        [order addObject:tab[@"token"]];
    }
    [NSUserDefaults.standardUserDefaults setObject:order forKey:@"kTabOrder"];
    [NSNotificationCenter.defaultCenter postNotificationName:@"YTKACETabConfigDidChange" object:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSArray *titles = @[@"Home", @"Explore", @"Subscriptions", @"Shorts", @"You"];
        NSArray *values = @[@0, @1, @2, @3, @4];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        YTKACEPresentChoiceMenu(self, cell, @"Default Startup Tab", titles, values,
            @"kEnabledStartupPage", 0, ^(__unused NSUInteger position) {
                [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationNone];
                YTKACEShowRestartNotice(self);
            });
    } else if (indexPath.section == 2) {
        NSMutableDictionary *tab = self.activeTabs[(NSUInteger)indexPath.row];
        NSString *token = tab[@"token"];
        NSDictionary *names = [NSUserDefaults.standardUserDefaults
            dictionaryForKey:@"YTKACETabNames"];
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:YTKACELocalized(@"Rename Tab")
            message:YTKACELocalized(@"Leave blank to restore the default name.")
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = tab[@"title"];
            field.text = names[token];
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:YTKACELocalized(@"Cancel")
            style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction
            actionWithTitle:YTKACELocalized(@"Save")
            style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) {
                NSMutableDictionary *updated = [names mutableCopy] ?:
                    [NSMutableDictionary dictionary];
                NSString *value = [alert.textFields.firstObject.text
                    stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (value.length == 0) {
                    [updated removeObjectForKey:token];
                } else {
                    updated[token] = value;
                }
                [NSUserDefaults.standardUserDefaults setObject:updated
                                                        forKey:@"YTKACETabNames"];
                [NSNotificationCenter.defaultCenter
                    postNotificationName:@"YTKACETabConfigDidChange"
                    object:nil];
                [self.tableView reloadData];
            }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
