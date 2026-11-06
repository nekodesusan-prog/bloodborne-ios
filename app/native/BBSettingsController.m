/* bloodborne-ios: the screen before the game (as nxnative's): what the app found (the game's
 * files, the pairing file for JIT, the memory iOS allows), Play, and every setting on one
 * scrollable page in Game, Graphics, Controls and Performance. A menu or a switch changes a
 * setting at once; a setting that depends on a switch shows only while it is on. */
#import <UIKit/UIKit.h>
#include <os/proc.h>
#import "BBSettings.h"
#import "BBSettingsController.h"

@implementation BBSettingsController {
    BBSettings *_settings;
    NSArray<NSArray<BBSetting *> *> *_rows; /* visible settings per settings section */
    NSArray<NSArray<NSString *> *> *_status; /* title, value, ok ("1"/"0") */
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _settings = [BBSettings shared];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = [self header];
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload]; /* files may have been copied in while the app was in the background */
}

#pragma mark - What the app found

static NSString *PairingFile(NSString *documents) {
    for (NSString *dir in @[documents, [documents stringByAppendingPathComponent:@"StikJIT"]]) {
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
            NSString *lower = name.lowercaseString;
            if (![lower hasSuffix:@".plist"] && ![lower hasSuffix:@".txt"] && ![lower hasSuffix:@".mobiledevicepairing"] &&
                ![lower hasPrefix:@"pairingfile"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
            id record = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil] : nil;
            if ([record isKindOfClass:[NSDictionary class]] && record[@"HostID"] && record[@"HostPrivateKey"]) return name;
        }
    }
    return nil;
}

- (NSArray<NSArray<NSString *> *> *)findStatus {
    NSString *docs = _settings.documents;
    BOOL game = [[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:@"game/eboot.bin"]];
    NSString *pairing = PairingFile(docs);
    double gb = os_proc_available_memory() / 1073741824.0;
    return @[
        @[@"Game files", game ? @"Found" : @"Missing: copy your dump to Files › Bloodborne › game", game ? @"1" : @"0"],
        @[@"Pairing file (JIT)", pairing ?: @"Missing: copy it to Files › Bloodborne", pairing ? @"1" : @"0"],
        @[@"Memory", [NSString stringWithFormat:@"%.1f GB available%@", gb,
                      gb < 8 ? @" (add Increased Memory Limit with GetMoreRam)" : @""], gb >= 8 ? @"1" : @"0"],
    ];
}

- (void)reload {
    NSMutableArray *rows = [NSMutableArray array];
    for (BBSettingsSection *section in _settings.sections) {
        NSMutableArray *visible = [NSMutableArray array];
        for (BBSetting *s in section.settings)
            if ([_settings isVisible:s]) [visible addObject:s];
        [rows addObject:visible];
    }
    _rows = rows;
    _status = [self findStatus];
    [self.tableView reloadData];
}

#pragma mark - Header and Play

- (UIView *)header {
    UILabel *title = [UILabel new];
    title.text = @"Bloodborne";
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Your own copy of the game, run natively. Settings apply when you press Play.";
    subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.numberOfLines = 0;
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = @"Play";
    config.image = [UIImage systemImageNamed:@"play.fill"];
    config.imagePadding = 8;
    config.buttonSize = UIButtonConfigurationSizeLarge;
    config.baseBackgroundColor = [UIColor colorWithRed:0.55 green:0.12 blue:0.12 alpha:1];
    UIButton *play = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
        [self play];
    }]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle, play]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    [stack setCustomSpacing:18 afterView:subtitle];
    stack.layoutMarginsRelativeArrangement = YES;
    stack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(24, 20, 8, 20);
    CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(self.view.bounds.size.width ?: 390, 0)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    stack.frame = CGRectMake(0, 0, size.width, size.height);
    return stack;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height - size.height) > 0.5 || fabs(header.frame.size.width - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = header;
    }
}

- (void)play {
    [_settings apply];
    if (self.onPlay) self.onPlay();
}

#pragma mark - Table

/* Sections: 0 what the app found, 1..n the settings, n+1 reset. */
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)_rows.count + 2; }

- (BOOL)isReset:(NSInteger)section { return section == (NSInteger)_rows.count + 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)_status.count;
    if ([self isReset:section]) return 1;
    return (NSInteger)_rows[section - 1].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Ready to play";
    if ([self isReset:section]) return nil;
    return _settings.sections[section - 1].title;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Files go in Files › On My iPad › Bloodborne (or the Apple Devices app's file sharing).";
    if ([self isReset:section]) return @"Sets every setting back to the defaults this build was tested with.";
    return _settings.sections[section - 1].footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.textToSecondaryTextVerticalPadding = 3;

    if (indexPath.section == 0) {
        NSArray<NSString *> *row = _status[indexPath.row];
        BOOL ok = row[2].boolValue;
        content.text = row[0];
        content.secondaryText = row[1];
        content.image = [UIImage systemImageNamed:ok ? @"checkmark.circle.fill" : @"exclamationmark.triangle.fill"];
        content.imageProperties.tintColor = ok ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
        cell.contentConfiguration = content;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if ([self isReset:indexPath.section]) {
        content = [UIListContentConfiguration cellConfiguration];
        content.text = @"Reset to tested defaults";
        content.textProperties.color = _settings.anyChanged ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
        content.textProperties.alignment = UIListContentTextAlignmentCenter;
        cell.contentConfiguration = content;
        return cell;
    }

    BBSetting *s = _rows[indexPath.section - 1][indexPath.row];
    NSString *value = [_settings valueFor:s.key];
    content.text = s.title;
    content.secondaryText = s.detail;
    if (s.parent) content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 32, 8, 8);
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (s.isSwitch) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = value.boolValue;
        __weak UISwitch *weakToggle = toggle;
        [toggle addAction:[UIAction actionWithHandler:^(UIAction *a) {
            [self->_settings setString:weakToggle.on ? @"1" : @"0" forKey:s.key];
            [self reload];
        }] forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < s.values.count; ++i) {
        NSString *choice = s.values[i];
        UIAction *action = [UIAction actionWithTitle:s.labels[i] image:nil identifier:nil handler:^(UIAction *a) {
            [self->_settings setString:choice forKey:s.key];
            [self reload];
        }];
        action.state = [choice isEqualToString:value] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    /* Grouped menus (Resolution): a titled inline section per group, as Madeira's. */
    NSMutableArray<UIMenuElement *> *items = actions;
    if (s.groups) {
        items = [NSMutableArray array];
        NSUInteger at = 0;
        for (NSArray *group in s.groups) {
            const NSUInteger count = MIN([group[1] unsignedIntegerValue], actions.count - at);
            [items addObject:[UIMenu menuWithTitle:group[0] image:nil identifier:nil
                                           options:UIMenuOptionsDisplayInline
                                          children:[actions subarrayWithRange:NSMakeRange(at, count)]]];
            at += count;
        }
    }
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = [s labelFor:value];
    config.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall]];
    config.imagePlacement = NSDirectionalRectEdgeTrailing;
    config.imagePadding = 4;
    config.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 0);
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.menu = [UIMenu menuWithChildren:items];
    button.showsMenuAsPrimaryAction = YES;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    [button sizeToFit];
    CGRect frame = button.frame;
    frame.size.width = MIN(frame.size.width, 300);
    button.frame = frame;
    cell.accessoryView = button;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self isReset:indexPath.section] || !_settings.anyChanged) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset to tested defaults?"
        message:@"Every setting goes back to the defaults this build was tested with." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self->_settings resetToDefaults];
        [self reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
