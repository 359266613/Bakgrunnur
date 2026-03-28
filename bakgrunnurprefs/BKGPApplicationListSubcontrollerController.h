#import "../common.h"

@interface BKGPApplicationListSubcontrollerController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
{
    NSMutableDictionary *_prefs;
    NSArray *_allEntriesIdentifier;
    NSArray *_allApps;           // 所有 App 数据（字典数组）
    NSArray *_filteredApps;      // 搜索过滤后的 App 数据
    UITableView *_appTableView;
    UISearchController *_searchController;
}
- (void)updateIvars;
- (void)loadPreferences;
@end
