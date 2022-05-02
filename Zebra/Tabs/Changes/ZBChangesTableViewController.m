//
//  ZBChangesTableViewController.m
//  Zebra
//
//  Created by Thatchapon Unprasert on 2/6/2019
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBChangesTableViewController.h"
#import "ZBRedditPosts.h"

#import "ZBLog.h"
#import "ZBAppDelegate.h"
#import "ZBSettings.h"
#import "ZBDevice.h"
#import "ZBPackagePartitioner.h"
#import "ZBDatabaseManager.h"
#import "ZBPackage.h"
#import "ZBPackageActions.h"
#import "ZBPackageTableViewCell.h"
#import "ZBPackageDepictionViewController.h"
#import "UIColor+GlobalColors.h"

@import SDWebImage;

@interface ZBChangesTableViewController () {
    NSUserDefaults *defaults;
    NSArray *packages;
    NSArray *availableOptions;
    NSMutableArray *sectionIndexTitles;
    int totalNumberOfPackages;
    int numberOfPackages;
    int databaseRow;
}
@property (nonatomic, weak) ZBPackageDepictionViewController *previewPackageDepictionVC;
@property (nonatomic, weak) SFSafariViewController *previewSafariVC;
@end

@implementation ZBChangesTableViewController

- (BOOL)useBatchLoad {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self applyLocalization];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggleNews) name:@"toggleNews" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configureTheme) name:@"darkMode" object:nil];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerNib:[UINib nibWithNibName:@"ZBNewsCollectionViewCell" bundle:nil] forCellWithReuseIdentifier:@"newsCell"];
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 15, 0, 15);
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    self.tableView.contentInset = UIEdgeInsetsMake(5, 0, 0, 0);
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBPackageTableViewCell" bundle:nil] forCellReuseIdentifier:@"packageTableViewCell"];
    
    if (@available(iOS 13.0, *)) {
    } else {
        if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
            [self registerForPreviewingWithDelegate:self sourceView:self.view];
        }
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTable) name:@"ZBDatabaseCompletedUpdate" object:nil];
    self.redditPosts = [NSMutableArray new];
    availableOptions = @[@"release", @"update", @"upcoming", @"news"];
    defaults = [NSUserDefaults standardUserDefaults];
    [self startSettingHeader];
    self.batchLoadCount = 250;
    [self refreshTable];
}

- (void)applyLocalization {
    // This isn't exactly "best practice", but this way the text in IB isn't useless.
    self.navigationItem.title = NSLocalizedString([self.navigationItem.title capitalizedString], @"");
}

- (void)startSettingHeader  {
    self.tableView.tableHeaderView.frame = CGRectMake(self.tableView.tableHeaderView.frame.origin.x, self.tableView.tableHeaderView.frame.origin.y, self.tableView.tableHeaderView.frame.size.width, CGFLOAT_MIN);
    if ([ZBSettings wantsCommunityNews]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // [self retrieveNewsJson];
            [self kickStartReddit];
        });
    }
}

- (void)configureTheme {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadRowsAtIndexPaths:[self.tableView indexPathsForVisibleRows] withRowAnimation:UITableViewRowAnimationNone];
        self.tableView.sectionIndexColor = [UIColor accentColor];
        [self.navigationController.navigationBar setTintColor:[UIColor accentColor]];
        self.tableView.tableHeaderView.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    });
}

- (void)kickStartReddit {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.redditPosts removeAllObjects];
        NSMutableURLRequest *request = [NSMutableURLRequest new];
        [request setURL:[NSURL URLWithString:@"https://www.reddit.com/r/jailbreak/search.json?q=subreddit:jailbreak%20%28flair%3ARelease+OR+flair%3AUpdate+OR+flair%3AUpcoming+OR+flair%3ANews%29&restrict_sr=on&sort=relevance&t=month"]];
        [request setHTTPMethod:@"GET"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (data) {
                NSError *err = nil;
                ZBRedditPosts *redditPosts = [ZBRedditPosts fromData:data error:&err];
                for (ZBChild *child in redditPosts.data.children) {
                    [self.redditPosts addObject:child.data];
                }

                // Re-sort by date, so most recent posts show at the start. We could just ask Reddit
                // to return results sorted by date, but then it won’t take relevancy into account.
                [self.redditPosts sortUsingComparator:^NSComparisonResult (ZBChildData *a, ZBChildData *b) {
                    return [b.created compare:a.created];
                }];
            }
            if (error) {
                NSLog(@"[Zebra] Error retrieving news JSON %@", error);
            } else if (self.redditPosts.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self createHeader];
                });
            }
        }] resume];
    });
}

- (void)createHeader {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView beginUpdates];
        [UIView animateWithDuration:.25f animations:^{
            self.tableView.tableHeaderView.frame = CGRectMake(self.tableView.tableHeaderView.frame.origin.x, self.tableView.tableHeaderView.frame.origin.y, self.tableView.tableHeaderView.frame.size.width, 180);
        }];
        [self.collectionView reloadData];
        [self.tableView endUpdates];
    });
}

- (void)hideHeader {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView beginUpdates];
        [UIView animateWithDuration:.25f animations:^{
            self.tableView.tableHeaderView.frame = CGRectMake(self.tableView.tableHeaderView.frame.origin.x, self.tableView.tableHeaderView.frame.origin.y, self.tableView.tableHeaderView.frame.size.width, 0);
        }];
        [self.collectionView reloadData];
        [self.tableView endUpdates];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ZBDatabaseCompletedUpdate" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"darkMode" object:nil];
}

- (void)updateSections {
    self.tableData = [self partitionObjects:packages collationStringSelector:@selector(lastSeenDate)];
}

- (void)refreshTable {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->packages = [self.databaseManager packagesFromSource:NULL inSection:NULL numberOfPackages:[self useBatchLoad] ? self.batchLoadCount : -1 startingAt:0 enableFiltering:YES];
        self->databaseRow = self.batchLoadCount - 1;
        self->totalNumberOfPackages = [self.databaseManager numberOfPackagesInSource:NULL section:NULL enableFiltering:YES];
        self->numberOfPackages = (int)[self->packages count];
        self.batchLoad = YES;
        self.continueBatchLoad = self.batchLoad;
        [self updateSections];
        [self.tableView reloadData];
    });
}

- (void)loadNextPackages {
    if (!self.continueBatchLoad || self.isPerformingBatchLoad) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->databaseRow < self->totalNumberOfPackages) {
            self.isPerformingBatchLoad = YES;
            NSArray *nextPackages = [self.databaseManager packagesFromSource:NULL inSection:NULL numberOfPackages:self.batchLoadCount startingAt:self->databaseRow enableFiltering:YES];
            if (nextPackages.count == 0) {
                self.continueBatchLoad = self.isPerformingBatchLoad = NO;
                return;
            }
            self->packages = [self->packages arrayByAddingObjectsFromArray:nextPackages];
            self->numberOfPackages = (int)[self->packages count];
            self->databaseRow += self.batchLoadCount;
            [self updateSections];
            [self.tableView reloadData];
            self.isPerformingBatchLoad = NO;
        }
    });
}

#pragma mark - Table view data source

- (NSArray <ZBPackage *> *)objectAtSection:(NSInteger)section {
    if ([self.tableData count] == 0)
        return nil;
    return [self.tableData objectAtIndex:section];
}

- (ZBPackage *)packageAtIndexPath:(NSIndexPath *)indexPath {
    return [self objectAtSection:indexPath.section][indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView numberOfRowsInSection:section] ? 30 : 0;
}

- (NSArray *)partitionObjects:(NSArray *)array collationStringSelector:(SEL)selector {
    sectionIndexTitles = [NSMutableArray array];
    return [ZBPackagePartitioner partitionObjects:array collationStringSelector:selector sectionIndexTitles:sectionIndexTitles packages:packages type:ZBSortingTypeDate];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([[self objectAtSection:section] count]) {
        return [ZBPackagePartitioner titleForHeaderInDateSection:section sectionIndexTitles:sectionIndexTitles dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [sectionIndexTitles count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[self objectAtSection:section] count];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(ZBPackageTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    [cell updateData:package];
    if (self.batchLoad && self.continueBatchLoad && numberOfPackages != totalNumberOfPackages) {
        NSInteger sectionsAmount = [tableView numberOfSections];
        NSInteger rowsAmount = [tableView numberOfRowsInSection:indexPath.section];
        if ((indexPath.section == sectionsAmount - 1) && (indexPath.row == rowsAmount - 1)) {
            [self loadNextPackages];
        }
    }
}

- (ZBPackageTableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackageTableViewCell *cell = (ZBPackageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"packageTableViewCell" forIndexPath:indexPath];
    [cell setColors];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self performSegueWithIdentifier:@"seguePackagesToPackageDepiction" sender:indexPath];
}

#pragma mark - Swipe actions

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return ![[ZBAppDelegate tabBarController] isQueueBarAnimating];
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    return [ZBPackageActions rowActionsForPackage:package inTableView:tableView];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView setEditing:NO animated:YES];
}

#pragma mark - Navigation

- (void)setDestinationVC:(NSIndexPath *)indexPath destination:(ZBPackageDepictionViewController *)destination {
    
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    ZBPackage *candidate = [package installableCandidate];
    
    destination.package = candidate ? candidate : package;
    destination.parent = self;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"seguePackagesToPackageDepiction"]) {
        ZBPackageDepictionViewController *destination = (ZBPackageDepictionViewController *)[segue destinationViewController];
        NSIndexPath *indexPath = sender;
        [self setDestinationVC:indexPath destination:destination];
        destination.view.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    }
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point  API_AVAILABLE(ios(13.0)){
    typeof(self) __weak weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:^UIViewController * _Nullable{
        ZBChildData *post = [weakSelf.redditPosts objectAtIndex:indexPath.row];
        
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://reddit.com/%@", post.identifier]];
        weakSelf.previewSafariVC = (SFSafariViewController *)[[SFSafariViewController alloc] initWithURL:url];
        
        return weakSelf.previewSafariVC;
    } actionProvider:nil];
}

- (void)collectionView:(UICollectionView *)collectionView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator  API_AVAILABLE(ios(13.0)){
    typeof(self) __weak weakSelf = self;
    [animator addCompletion:^{
        [weakSelf.navigationController presentViewController:weakSelf.previewSafariVC animated:YES completion:nil];
    }];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point  API_AVAILABLE(ios(13.0)){
    typeof(self) __weak weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:^UIViewController * _Nullable{
        return weakSelf.previewPackageDepictionVC;
    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        weakSelf.previewPackageDepictionVC = (ZBPackageDepictionViewController*)[weakSelf.storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
        [weakSelf setDestinationVC:indexPath destination:weakSelf.previewPackageDepictionVC];
        return [UIMenu menuWithTitle:@"" children:[weakSelf.previewPackageDepictionVC contextMenuActionItemsInTableView:tableView]];
    }];
}

- (void)tableView:(UITableView *)tableView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator  API_AVAILABLE(ios(13.0)){
    typeof(self) __weak weakSelf = self;
    [animator addCompletion:^{
        [weakSelf.navigationController pushViewController:weakSelf.previewPackageDepictionVC animated:YES];
    }];
}

- (UIViewController *)previewingContext:(id <UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    if (indexPath != nil) {
        ZBPackageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        previewingContext.sourceRect = cell.frame;
        ZBPackageDepictionViewController *packageDepictionVC = (ZBPackageDepictionViewController*)[self.storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
        
        [self setDestinationVC:indexPath destination:packageDepictionVC];
        return packageDepictionVC;
    }
    else {
        CGPoint locationCell = [self.collectionView convertPoint:location fromView:self.view];
        NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:locationCell];
        if ([self.redditPosts count] && indexPath.row < [self.redditPosts count]) {
            ZBChildData *post = [self.redditPosts objectAtIndex:indexPath.row];
            
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://reddit.com/%@", post.identifier]];
            SFSafariViewController *sfVC = [[SFSafariViewController alloc] initWithURL:url];
            
            return sfVC;
        }
        return NULL;
    }
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit {
    
    if ([viewControllerToCommit isKindOfClass:[SFSafariViewController class]]) {
        [self.navigationController presentViewController:viewControllerToCommit animated:YES completion:nil];
    }
    else {
        [self.navigationController pushViewController:viewControllerToCommit animated:YES];
    }
}

#pragma mark News
- (UICollectionViewCell *)collectionView:(nonnull UICollectionView *)collectionView cellForItemAtIndexPath:(nonnull NSIndexPath *)indexPath {
    ZBNewsCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"newsCell" forIndexPath:indexPath];
    ZBChildData *post = [self.redditPosts objectAtIndex:indexPath.row];
    NSURL *url;
    if (post.title != nil) {
        NSString *text = post.title;
        text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        text = [text stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
        text = [text stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];

        NSString *tag = post.linkFlairCSSClass;

        cell.postTitle.text = [self stripTagsAndWhitespacesFromTitle:text];
        cell.postTag.text = [tag capitalizedString];
    } else {
        cell.postTitle.text = NSLocalizedString(@"Error", @"");
    }
    if (post.url != nil) {
        [cell setRedditLink:[NSURL URLWithString:[NSString stringWithFormat:@"https://reddit.com/%@", post.identifier]]];
        [cell setRedditID:post.identifier];
    } else {
        [cell setRedditLink:[NSURL URLWithString:@"https://reddit.com/r/jailbreak"]];
    }
    
    if (post.preview.images.count) {
        ZBImage *first = post.preview.images[0];
        if (first.source != nil) {
            NSString *link = first.source.url;
            link = [link stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
            url = [NSURL URLWithString:link];
        }
    } else if (post.mediaMetadata.count) {
        for (ZBMediaMetadatum *item in post.mediaMetadata.allValues) {
            if ([item.type isEqualToString:@"Image"] && item.source != nil) {
                NSString *link = item.source.url;
                link = [link stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
                url = [NSURL URLWithString:link];
                break;
            }
        }
    }

    if ([post.thumbnail isEqualToString:@"nsfw"]) {
        [cell.backgroundImage setImage:[UIImage imageNamed:@"banner"]];
    } else if (url) {
        [cell.backgroundImage sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"Unknown"]];
    }else if (post.thumbnail != nil && ([post.thumbnail isEqualToString:@"self"] || [post.thumbnail isEqualToString:@"default"])) {
        [cell.backgroundImage setImage:[UIImage imageNamed:@"banner"]];
    } else {
        [cell.backgroundImage sd_setImageWithURL:[NSURL URLWithString:post.thumbnail] placeholderImage:[UIImage imageNamed:@"Unknown"]];
    }
    return cell;
}

- (NSString *)stripTagsAndWhitespacesFromTitle:(NSString *)title {
    NSUInteger lastCloseTagIndex = [title rangeOfString:@"]" options:NSBackwardsSearch].location;
    if (lastCloseTagIndex != NSNotFound) {
        title = [title substringFromIndex:lastCloseTagIndex + 1];
    }
    title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return title;
}

//- (NSArray *)getTags:(NSString *)body {
//    body = [body lowercaseString];
//    NSArray *tokens = [body componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
//    NSMutableArray *cleanedStrings = [NSMutableArray new];
//    for (NSString *cut in tokens) {
//        if ([cut hasPrefix:@"["] && [cut hasSuffix:@"]"]) {
//            NSString *cutCopy = [cut copy];
//            cutCopy = [cut substringFromIndex:1];
//            cutCopy = [cutCopy substringWithRange:NSMakeRange(0, cutCopy.length - 1)];
//            if ([cutCopy containsString:@"]["]) {
//                [cleanedStrings addObjectsFromArray:[cutCopy componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
//            } else {
//                [cleanedStrings addObject:cutCopy];
//            }
//        }
//    }
//    return cleanedStrings;
//}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(263, 148);
}

- (NSInteger)collectionView:(nonnull UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.redditPosts.count;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    UIApplication *application = [UIApplication sharedApplication];
    ZBNewsCollectionViewCell *cell = (ZBNewsCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
    if ([application canOpenURL:[NSURL URLWithString:[NSString stringWithFormat:@"apollo://reddit.com/%@", cell.redditID]]]) {
        [application openURL:[NSURL URLWithString:[NSString stringWithFormat:@"apollo://reddit.com/%@", cell.redditID]]];
    } else {
        SFSafariViewController *safariVC = [[SFSafariViewController alloc] initWithURL:cell.redditLink entersReaderIfAvailable:NO];
        safariVC.delegate = self;
        if (@available(iOS 10.0, *)) {
            [safariVC setPreferredBarTintColor:[UIColor groupedTableViewBackgroundColor]];
            [safariVC setPreferredControlTintColor:[UIColor accentColor]];
        } else {
            [safariVC.view setTintColor:[UIColor accentColor]];
        }
        [self presentViewController:safariVC animated:YES completion:nil];
    }
}

- (void)toggleNews {
    if ([ZBSettings wantsCommunityNews]) {
        [self kickStartReddit];
    } else {
        [self.redditPosts removeAllObjects];
        [self hideHeader];
    }
}

#pragma mark - SFSafariViewController delegate methods
- (void)safariViewController:(SFSafariViewController *)controller didCompleteInitialLoad:(BOOL)didLoadSuccessfully {
    // Load finished
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    // Done button pressed
}

- (void)scrollToTop {
    [self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];
}

@end
