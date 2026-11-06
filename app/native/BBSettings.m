/* bloodborne-ios: the native settings screen's model (BBSettings.h). The defaults are the ones the
 * game was tested with on an iPad Pro M4 (2026-11-06: the Hunter's Dream at 46-60 FPS, render
 * 720x540, built-in JIT). Keys and values are the runtime's and bloodborne-launcher's
 * (src/lib/data/options.ts, src-tauri/src/lib.rs game_environment). */
#import "BBSettings.h"
#include <stdlib.h>

static NSString *const BBPrefix = @"setting.";

@implementation BBSetting
- (BOOL)isSwitch { return self.values == nil; }
- (NSString *)labelFor:(NSString *)value {
    if (self.isSwitch) return value.boolValue ? @"On" : @"Off";
    NSUInteger i = [self.values indexOfObject:value];
    return i == NSNotFound ? value : self.labels[i];
}
@end

@implementation BBSettingsSection
@end

static BBSetting *Switch(NSString *key, BBStore store, NSString *title, NSString *detail, BOOL on) {
    BBSetting *s = [BBSetting new];
    s.key = key; s.store = store; s.title = title; s.detail = detail;
    s.defaultValue = on ? @"1" : @"0";
    return s;
}

static BBSetting *Choice(NSString *key, BBStore store, NSString *title, NSString *detail,
                         NSArray<NSString *> *values, NSArray<NSString *> *labels, NSString *fallback) {
    BBSetting *s = [BBSetting new];
    s.key = key; s.store = store; s.title = title; s.detail = detail;
    s.values = values; s.labels = labels; s.defaultValue = fallback;
    return s;
}

static BBSettingsSection *Section(NSString *title, NSString *footer, NSArray<BBSetting *> *settings) {
    BBSettingsSection *s = [BBSettingsSection new];
    s.title = title; s.footer = footer; s.settings = settings;
    return s;
}

@implementation BBSettings {
    NSDictionary<NSString *, BBSetting *> *_byKey;
}

+ (instancetype)shared {
    static BBSettings *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [BBSettings new]; });
    return settings;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;

    BBSetting *fpsSize = Choice(@"fps_size", BBStoreIni, @"Counter size", nil, @[@"small", @"big"], @[@"Small", @"Big"], @"small");
    fpsSize.parent = @"show_fps";
    BBSetting *fpsPosition = Choice(@"fps_position", BBStoreIni, @"Counter position", nil,
        @[@"top_left", @"top_center", @"top_right", @"bottom_left", @"bottom_center", @"bottom_right"],
        @[@"Top left", @"Top center", @"Top right", @"Bottom left", @"Bottom center", @"Bottom right"], @"top_left");
    fpsPosition.parent = @"show_fps";

    _sections = @[
        Section(@"Game", nil, @[
            Choice(@"BB_FPS", BBStoreEnv, @"Frame rate",
                   @"Unlocked follows each frame's real time, so the game keeps its speed when the frame rate varies.",
                   @[@"60", @"30", @"uncap"], @[@"60 FPS", @"30 FPS (the PS4's, cooler)", @"Unlocked"], @"60"),
            Choice(@"BB_FPS_LIMIT", BBStoreEnv, @"Frame rate limit", nil,
                   @[@"", @"30", @"40", @"45", @"60"], @[@"None", @"30", @"40", @"45", @"60"], @""),
            Choice(@"upscale", BBStoreApp, @"Upscaling",
                   @"MetalFX draws the game at the render resolution and scales it up: sharper, at a small GPU cost.",
                   @[@"off", @"1", @"2", @"3", @"4"],
                   @[@"Off", @"MetalFX ×1.5 (Quality)", @"MetalFX ×1.7 (Balanced)", @"MetalFX ×2 (Performance)",
                     @"MetalFX ×3 (Ultra Performance)"], @"off"),
            Choice(@"render_height", BBStoreApp, @"Render resolution",
                   @"The size the game draws at, in the screen's shape. 540 lines at most: a larger picture does not fit in what iOS gives an app.",
                   @[@"540", @"480", @"432", @"360"], @[@"540 lines", @"480 lines", @"432 lines", @"360 lines (lightest)"], @"540"),
            Choice(@"aspect_ratio", BBStoreIni, @"Aspect ratio",
                   @"Auto fills this screen. 16:9 shows the game as on a TV, with bars.",
                   @[@"auto", @"4:3", @"16:10", @"16:9", @"21:9"], @[@"Auto (this screen)", @"4:3", @"16:10", @"16:9", @"21:9"], @"auto"),
            Choice(@"BB_LANGUAGE", BBStoreEnv, @"Game language", nil,
                   @[@"1", @"18", @"17", @"7", @"3", @"20", @"2", @"4", @"5", @"6", @"16", @"8", @"19", @"12", @"13", @"14", @"15", @"0", @"9", @"11", @"10"],
                   @[@"English (US)", @"English (UK)", @"Português (Brasil)", @"Português (Portugal)", @"Español (España)",
                     @"Español (Latinoamérica)", @"Français", @"Deutsch", @"Italiano", @"Nederlands", @"Polski", @"Русский",
                     @"Türkçe", @"Suomi", @"Svenska", @"Dansk", @"Norsk", @"日本語", @"한국어", @"简体中文", @"繁體中文"], @"1"),
            Switch(@"skip_intro", BBStoreIni, @"Skip intro videos", nil, YES),
            Switch(@"show_fps", BBStoreIni, @"Frame-rate counter", nil, YES),
            fpsSize, fpsPosition,
        ]),
        Section(@"Graphics", @"Turning effects off is lighter on the GPU. Takes effect at the next Play.", @[
            Choice(@"model_lod", BBStoreIni, @"Model detail", nil,
                   @[@"-2", @"0", @"1", @"2"], @[@"Highest", @"As in the game", @"Lower", @"Lowest"], @"0"),
            Switch(@"effect_dynamic_shadows", BBStoreIni, @"Dynamic light shadows", nil, YES),
            Switch(@"effect_ssao", BBStoreIni, @"Ambient occlusion (SSAO)", nil, YES),
            Switch(@"effect_game_aa", BBStoreIni, @"Game anti-aliasing", nil, YES),
            Switch(@"effect_bloom", BBStoreIni, @"Bloom", nil, NO),
            Switch(@"effect_dof", BBStoreIni, @"Depth of field", nil, NO),
            Switch(@"effect_motion_blur", BBStoreIni, @"Motion blur", nil, NO),
            Switch(@"effect_chromatic_aberration", BBStoreIni, @"Chromatic aberration", nil, NO),
            Switch(@"effect_ssr", BBStoreIni, @"Screen-space reflections", @"Not in the original game.", NO),
        ]),
        Section(@"Controls", nil, @[
            Choice(@"BB_TOUCH_CONTROLS", BBStoreEnv, @"On-screen controls",
                   @"Auto shows them while no controller is connected.",
                   @[@"", @"1", @"0"], @[@"Auto", @"Always", @"Never"], @""),
        ]),
        Section(@"Performance",
                @"Built-in JIT needs your pairing file in this app's folder (Files › Bloodborne, any name) and LocalDevVPN on. Without JIT the game's code is interpreted: far too slow to play.", @[
            Switch(@"BB_IOS_JIT", BBStoreEnv, @"Built-in JIT", @"Enabled through StikJIT when you press Play.", YES),
            Switch(@"MTL_HUD_ENABLED", BBStoreEnv, @"Metal performance HUD", @"Apple's overlay: frame time, GPU time, memory.", NO),
            Switch(@"BB_FRAME_STATS", BBStoreEnv, @"Performance lines in the log",
                   @"Frame statistics in bb-ios.log every few seconds, for reports.", YES),
        ]),
    ];
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (BBSettingsSection *section in _sections)
        for (BBSetting *s in section.settings) byKey[s.key] = s;
    _byKey = byKey;
    return self;
}

- (NSString *)valueFor:(NSString *)key {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:[BBPrefix stringByAppendingString:key]];
    return stored ?: _byKey[key].defaultValue ?: @"";
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *name = [BBPrefix stringByAppendingString:key];
    /* A value equal to the default is not stored: it follows the build's defaults. */
    if ([value isEqualToString:_byKey[key].defaultValue]) [defaults removeObjectForKey:name];
    else [defaults setObject:value forKey:name];
}

- (BOOL)isVisible:(BBSetting *)setting {
    return !setting.parent || [self valueFor:setting.parent].boolValue;
}

- (BOOL)anyChanged {
    for (NSString *key in _byKey)
        if ([[NSUserDefaults standardUserDefaults] objectForKey:[BBPrefix stringByAppendingString:key]]) return YES;
    return NO;
}

- (void)resetToDefaults {
    for (NSString *key in _byKey)
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[BBPrefix stringByAppendingString:key]];
}

/* bbport.ini: its other lines (the runtime's own, and the in-game menu's) are kept; the keys set
 * here replace theirs. Written through a temporary file, so a crash keeps the old one. */
- (void)writeIni:(NSDictionary<NSString *, NSString *> *)values {
    NSString *path = [_documents stringByAppendingPathComponent:@"bbport.ini"];
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableString *out = [NSMutableString string];
    for (NSString *line in [old componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (!line.length || (eq.location != NSNotFound && values[[line substringToIndex:eq.location]])) continue;
        [out appendFormat:@"%@\n", line];
    }
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [out appendFormat:@"%@=%@\n", key, values[key]];
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)apply {
    NSMutableDictionary<NSString *, NSString *> *ini = [NSMutableDictionary dictionary];
    for (BBSettingsSection *section in _sections) {
        for (BBSetting *s in section.settings) {
            NSString *value = [self valueFor:s.key];
            if (s.store == BBStoreIni) ini[s.key] = value;
            else if (s.store == BBStoreEnv) {
                if (value.length && !(s.isSwitch && !value.boolValue && ![s.key isEqualToString:@"BB_IOS_JIT"]))
                    setenv(s.key.UTF8String, value.UTF8String, 1);
                else unsetenv(s.key.UTF8String);
            }
        }
    }
    /* Upscaling: the runtime's upscaler and quality preset (the iOS app scales the output by it). */
    NSString *upscale = [self valueFor:@"upscale"];
    ini[@"upscaler"] = [upscale isEqualToString:@"off"] ? @"off" : @"metalfx";
    if (![upscale isEqualToString:@"off"]) ini[@"preset"] = upscale;
    /* The render height (app_main.c ios_output takes the width from the screen's shape). */
    ini[@"output_res"] = [NSString stringWithFormat:@"%dx%@", [self valueFor:@"render_height"].intValue * 4 / 3,
                          [self valueFor:@"render_height"]];
    [self writeIni:ini];
    /* What bloodborne-launcher set besides (game_environment): its in-game menu in English,
     * trophy notifications on. */
    setenv("BB_UI_LANGUAGE", "en", 0);
    setenv("BB_TROPHY_OVERLAY", "1", 0);
}

@end
