#import "BKGPApplicationListSubcontrollerController.h"
#import "BKGPAppEntryController.h"
#import "../BKGShared.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>

// LSApplicationProxy 私有 API 声明
@interface LSApplicationProxy : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (UIImage *)iconImageWithFormat:(int)format;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)allApplications;
@end

// 自定义 Cell：图标 + 名称 + BundleID + 状态
@interface BKGAppCell : UITableViewCell
@property (nonatomic, strong) UIImageView *appIconView;
@property (nonatomic, strong) UILabel *appNameLabel;
@property (nonatomic, strong) UILabel *bundleIdLabel;
@property (nonatomic, strong) UILabel *statusLabel;
- (void)configureWithName:(NSString *)name bundleId:(NSString *)bundleId icon:(UIImage *)icon isEnabled:(BOOL)enabled;
@end

@implementation BKGAppCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // 图标
        _appIconView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 8, 44, 44)];
        _appIconView.layer.cornerRadius = 10;
        _appIconView.layer.masksToBounds = YES;
        _appIconView.contentMode = UIViewContentModeScaleAspectFill;
        [self.contentView addSubview:_appIconView];

        // App 名称
        _appNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(68, 10, 200, 22)];
        _appNameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [self.contentView addSubview:_appNameLabel];

        // BundleID
        _bundleIdLabel = [[UILabel alloc] initWithFrame:CGRectMake(68, 32, 200, 16)];
        _bundleIdLabel.font = [UIFont systemFontOfSize:11];
        _bundleIdLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_bundleIdLabel];

        // 状态标签
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.backgroundColor = [UIColor systemGreenColor];
        _statusLabel.layer.cornerRadius = 8;
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.text = @" 已启用 ";
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_statusLabel];

        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;

    _appIconView.frame = CGRectMake(12, 8, 44, 44);

    CGSize statusSize = [_statusLabel sizeThatFits:CGSizeMake(80, 18)];
    CGFloat statusWidth = statusSize.width + 12;
    CGFloat statusHeight = 18;
    _statusLabel.frame = CGRectMake(width - statusWidth - 36, 19, statusWidth, statusHeight);
    _statusLabel.layer.cornerRadius = statusHeight / 2.0;

    CGFloat labelRight = _statusLabel.hidden ? (width - 36) : (_statusLabel.frame.origin.x - 6);
    _appNameLabel.frame = CGRectMake(68, 10, labelRight - 68, 22);
    _bundleIdLabel.frame = CGRectMake(68, 32, labelRight - 68, 16);
}

- (void)configureWithName:(NSString *)name bundleId:(NSString *)bundleId icon:(UIImage *)icon isEnabled:(BOOL)enabled {
    _appNameLabel.text = name;
    _bundleIdLabel.text = bundleId;
    _appIconView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    _statusLabel.hidden = !enabled;
    [self setNeedsLayout];
}

@end

// -------------------------------------------------------

@implementation BKGPApplicationListSubcontrollerController

#pragma mark - Init / Notification

static void refreshSpecifiers_appList() {
    [[NSNotificationCenter defaultCenter] postNotificationName:RELOAD_SPECIFIERS_LOCAL_NOTIFICATION_NAME object:nil];
}

- (instancetype)init {
    if ((self = [super init])) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshSpecifiers_appList, (CFStringRef)RELOAD_SPECIFIERS_NOTIFICATION_NAME, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshSpecifiers:) name:RELOAD_SPECIFIERS_LOCAL_NOTIFICATION_NAME object:nil];
    }
    return self;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    if ((self = [super init])) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshSpecifiers_appList, (CFStringRef)RELOAD_SPECIFIERS_NOTIFICATION_NAME, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshSpecifiers:) name:RELOAD_SPECIFIERS_LOCAL_NOTIFICATION_NAME object:nil];
    }
    return self;
}

- (void)refreshSpecifiers:(NSNotification *)notification {
    [self updateIvars];
    [_appTableView reloadData];
}

#pragma mark - Preferences Data

- (void)updateIvars {
    _prefs = [getPrefs() ?: @{} mutableCopy];
    _allEntriesIdentifier = [_prefs[@"enabledIdentifier"] valueForKey:@"identifier"] ?: @[];
}

- (void)loadPreferences {
    [self updateIvars];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadPreferences];
    self.title = @"管理应用";

    // 加载 App 列表
    _allApps = [self loadInstalledApplications];
    _filteredApps = _allApps;

    // 搜索控制器
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"搜索应用";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;

    // TableView
    _appTableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _appTableView.delegate = self;
    _appTableView.dataSource = self;
    _appTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _appTableView.rowHeight = 60;
    [_appTableView registerClass:[BKGAppCell class] forCellReuseIdentifier:@"BKGAppCell"];
    [self.view addSubview:_appTableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateIvars];
    [_appTableView reloadData];
}

#pragma mark - App Data Loading

- (NSArray *)loadInstalledApplications {
    NSMutableArray *apps = [NSMutableArray array];
    Class LSWorkspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!LSWorkspaceClass) return @[];
    id workspace = [LSWorkspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return @[];

    NSArray *proxies = nil;
    if ([workspace respondsToSelector:@selector(allApplications)]) {
        proxies = [workspace performSelector:@selector(allApplications)];
    }
    if (!proxies.count && [workspace respondsToSelector:@selector(allInstalledApplications)]) {
        proxies = [workspace performSelector:@selector(allInstalledApplications)];
    }

    for (id proxy in proxies) {
        NSString *bundleId = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy bundleIdentifier] : nil;
        NSString *name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : nil;
        UIImage *icon = nil;
        if ([proxy respondsToSelector:@selector(iconImageWithFormat:)]) {
            @try { icon = [proxy iconImageWithFormat:10]; } @catch (NSException *e) {}
        }
        if (bundleId.length > 0 && name.length > 0) {
            [apps addObject:@{ @"bundleId": bundleId, @"name": name, @"icon": icon ?: [NSNull null] }];
        }
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return [apps copy];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *keyword = searchController.searchBar.text;
    if (keyword.length == 0) {
        _filteredApps = _allApps;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundleId CONTAINS[cd] %@", keyword, keyword];
        _filteredApps = [_allApps filteredArrayUsingPredicate:pred];
    }
    [_appTableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)_filteredApps.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BKGAppCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BKGAppCell" forIndexPath:indexPath];
    NSDictionary *appInfo = _filteredApps[indexPath.row];
    NSString *bundleId = appInfo[@"bundleId"];
    NSString *name = appInfo[@"name"];
    id iconObj = appInfo[@"icon"];
    UIImage *icon = [iconObj isKindOfClass:[UIImage class]] ? iconObj : nil;
    BOOL isEnabled = [_allEntriesIdentifier containsObject:bundleId];
    [cell configureWithName:name bundleId:bundleId icon:icon isEnabled:isEnabled];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *appInfo = _filteredApps[indexPath.row];
    NSString *bundleId = appInfo[@"bundleId"];
    NSString *name = appInfo[@"name"];

    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
    specifier.identifier = bundleId;
    [specifier setProperty:name forKey:@"label"];
    [specifier setProperty:bundleId forKey:@"id"];

    BKGPAppEntryController *entryController = [[BKGPAppEntryController alloc] initWithSpecifier:specifier];
    entryController.specifier = specifier;
    entryController.title = name;
    [self.navigationController pushViewController:entryController animated:YES];
}

#pragma mark - PSListController overrides

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    [self updateIvars];
    [_appTableView reloadData];
}

#pragma mark - Entry Callbacks

-(NSArray *)getAllEntries:(NSString *)keyName keyIdentifier:(NSString *)keyIdentifier {
    return [_prefs[keyName] valueForKey:keyIdentifier];
}

@end
