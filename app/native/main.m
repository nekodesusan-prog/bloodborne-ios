/* bloodborne-ios: the native app (scripts/build-native-ipa.sh), in place of bloodborne-launcher's
 * Tauri app: the settings screen first (BBSettingsController), then the game in this process,
 * started the way the launcher started it (bb_ios_start_game in app_main.c, built with
 * BB_IOS_IN_LAUNCHER). No web view, so the game keeps the low address space WebKit used.
 *
 * Scene lifecycle (Info.plist UIApplicationSceneManifest, BBSceneDelegate): apps built with the
 * iOS 27 SDK that make their window in the app delegate are not launched; the first build did
 * that and closed at once on iPadOS 27. The game's window (SDL) joins the same scene. */
#import <UIKit/UIKit.h>
#import "BBSettings.h"
#import "BBSettingsController.h"

int bb_ios_start_game(const char *data_dir); /* app_main.c */

@interface BBAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation BBAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [UISceneConfiguration configurationWithName:@"Default" sessionRole:session.role];
    config.delegateClass = NSClassFromString(@"BBSceneDelegate");
    return config;
}
@end

@interface BBSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation BBSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.tintColor = [UIColor colorWithRed:0.86 green:0.33 blue:0.30 alpha:1];
    BBSettingsController *settings = [BBSettingsController new];
    __weak BBSceneDelegate *weakSelf = self;
    settings.onPlay = ^{ [weakSelf play]; };
    self.window.rootViewController = settings;
    [self.window makeKeyAndVisible];
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
        /* Apple's Metal HUD reads MTL_HUD_ENABLED when Metal starts in this process, which can be
         * before Play: set at launch from the saved overlay choice (BBSettings "overlay"). The game's
         * layer also asks for it (runtime mtl_present.mm). A change applies at the next launch. */
        if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"setting.overlay"] isEqualToString:@"metal"])
            setenv("MTL_HUD_ENABLED", "1", 1);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([BBAppDelegate class]));
    }
}
