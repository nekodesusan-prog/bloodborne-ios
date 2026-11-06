/* bloodborne-ios: the native app (scripts/build-native-ipa.sh), in place of bloodborne-launcher's
 * Tauri app: the settings screen first (BBSettingsController), then the game in this process,
 * started the way the launcher started it (bb_ios_start_game in app_main.c, built with
 * BB_IOS_IN_LAUNCHER). No web view, so the game keeps the low address space WebKit used. */
#import <UIKit/UIKit.h>
#import "BBSettings.h"
#import "BBSettingsController.h"

int bb_ios_start_game(const char *data_dir); /* app_main.c */

@interface BBAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation BBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.tintColor = [UIColor colorWithRed:0.86 green:0.33 blue:0.30 alpha:1];
    BBSettingsController *settings = [BBSettingsController new];
    __weak BBAppDelegate *weakSelf = self;
    settings.onPlay = ^{ [weakSelf play]; };
    self.window.rootViewController = settings;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)play {
    /* The game makes its own window (SDL): this one goes, with its views, before it starts. */
    self.window.hidden = YES;
    self.window.rootViewController = nil;
    self.window = nil;
    NSString *documents = [BBSettings shared].documents;
    /* Returns at once: the game starts from a run-loop timer on the main thread. */
    if (bb_ios_start_game(documents.fileSystemRepresentation) != 0)
        NSLog(@"Bloodborne: the game could not start");
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([BBAppDelegate class]));
    }
}
