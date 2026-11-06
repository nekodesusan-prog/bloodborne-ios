/* bloodborne-ios: the native settings screen's model (app/native/). Each setting has a tested
 * default; only values the player changed are stored (NSUserDefaults), so a later build's
 * defaults reach everyone who left a setting alone. Play writes them where the game reads them:
 * bbport.ini (the runtime's settings file) or the environment, as bloodborne-launcher did. */
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, BBStore) {
    BBStoreIni,   /* a bbport.ini key */
    BBStoreEnv,   /* an environment variable (empty value: unset) */
    BBStoreApp,   /* the app's own (turned into ini keys or variables by -apply) */
};

@interface BBSetting : NSObject
@property(nonatomic, copy) NSString *key;          /* ini key, variable or app key */
@property(nonatomic) BBStore store;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;       /* a line under the title, or nil */
@property(nonatomic, copy) NSArray<NSString *> *values; /* nil: a switch ("1"/"0") */
@property(nonatomic, copy) NSArray<NSString *> *labels;
@property(nonatomic, copy) NSString *defaultValue;
@property(nonatomic, copy) NSString *parent;       /* shown only while this switch is on */
@property(nonatomic, readonly) BOOL isSwitch;
- (NSString *)labelFor:(NSString *)value;
@end

@interface BBSettingsSection : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *footer;
@property(nonatomic, copy) NSArray<BBSetting *> *settings;
@end

@interface BBSettings : NSObject
@property(nonatomic, readonly) NSArray<BBSettingsSection *> *sections;
@property(nonatomic, readonly) NSString *documents;
+ (instancetype)shared;
- (NSString *)valueFor:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key; /* not -setValue:forKey: (KVC) */
- (BOOL)isVisible:(BBSetting *)setting;
- (BOOL)anyChanged;
- (void)resetToDefaults;
/* Writes bbport.ini and sets the environment for the game (call just before it starts). */
- (void)apply;
@end
