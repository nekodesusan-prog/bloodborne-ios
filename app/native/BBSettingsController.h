/* bloodborne-ios: the screen before the game (BBSettingsController.m). */
#import <UIKit/UIKit.h>

@interface BBSettingsController : UITableViewController
/* Called on the main thread after Play wrote the settings. */
@property(nonatomic, copy) void (^onPlay)(void);
@end
