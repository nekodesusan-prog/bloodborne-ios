/* bloodborne-ios: the native settings screen's model (BBSettings.h). The defaults are the ones the
 * game was tested with on an iPad Pro M4 (2026-11-06: the Hunter's Dream at 46-60 FPS, render
 * 720x540, built-in JIT). Keys and values are the runtime's and bloodborne-launcher's
 * (src/lib/data/options.ts, src-tauri/src/lib.rs game_environment). */
#import "BBSettings.h"
#import <UIKit/UIKit.h>
#include <os/proc.h>
#include <stdio.h>
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
                     @"MetalFX ×3 (Ultra Performance)"], @"1"),
            [self resolutionSetting],
            Choice(@"BB_LANGUAGE", BBStoreEnv, @"Game language", nil,
                   @[@"1", @"18", @"17", @"7", @"3", @"20", @"2", @"4", @"5", @"6", @"16", @"8", @"19", @"12", @"13", @"14", @"15", @"0", @"9", @"11", @"10"],
                   @[@"English (US)", @"English (UK)", @"Português (Brasil)", @"Português (Portugal)", @"Español (España)",
                     @"Español (Latinoamérica)", @"Français", @"Deutsch", @"Italiano", @"Nederlands", @"Polski", @"Русский",
                     @"Türkçe", @"Suomi", @"Svenska", @"Dansk", @"Norsk", @"日本語", @"한국어", @"简体中文", @"繁體中文"], @"1"),
            Switch(@"skip_intro", BBStoreIni, @"Skip intro videos", nil, YES),
            Choice(@"overlay", BBStoreApp, @"Performance overlay",
                   @"FPS only: a small counter in the corner. Detailed: the game's own panel with FPS, frame time, memory and a frame-time graph. Metal HUD: Apple's overlay with GPU time too; after choosing it, close the app once (app switcher) so it starts with it.",
                   @[@"off", @"fps", @"detailed", @"metal"], @[@"Off", @"FPS only", @"Detailed", @"Metal HUD"], @"fps"),
        ]),
        Section(@"Graphics", @"Turning effects off is lighter on the GPU. Takes effect at the next Play.", @[
            Choice(@"model_lod", BBStoreIni, @"Model detail", nil,
                   @[@"-2", @"0", @"1", @"2"], @[@"Highest", @"As in the game", @"Lower", @"Lowest"], @"2"),
            Switch(@"effect_dynamic_shadows", BBStoreIni, @"Dynamic light shadows", nil, NO),
            Switch(@"effect_ssao", BBStoreIni, @"Ambient occlusion (SSAO)", nil, NO),
            Switch(@"effect_game_aa", BBStoreIni, @"Game anti-aliasing", nil, YES),
            Switch(@"effect_bloom", BBStoreIni, @"Bloom", nil, NO),
            Switch(@"effect_dof", BBStoreIni, @"Depth of field", nil, NO),
            Switch(@"effect_motion_blur", BBStoreIni, @"Motion blur", nil, NO),
            Switch(@"effect_chromatic_aberration", BBStoreIni, @"Chromatic aberration", nil, NO),
            Switch(@"effect_ssr", BBStoreIni, @"Screen-space reflections", @"Not in the original game.", NO),
            Switch(@"perf_patch", BBStoreIni, @"Performance patch",
                   @"Community patch (Kyo): some of the game's debug settings set for speed. May change some visuals.", YES),
            Switch(@"lower_physics", BBStoreIni, @"Lower object and corpse physics",
                   @"Community patch (Kyo): bodies and objects resist being pushed. Less physics work in crowded fights.", YES),
        ]),
        Section(@"Controls", nil, @[
            Choice(@"BB_TOUCH_CONTROLS", BBStoreEnv, @"On-screen controls",
                   @"Auto shows them while no controller is connected.",
                   @[@"", @"1", @"0"], @[@"Auto", @"Always", @"Never"], @""),
        ]),
        Section(@"Testing", @"For measuring only: the defaults are the best settings for playing.", @[
            Choice(@"recomp_mode", BBStoreApp, @"Recompiled game code",
                   @"All but physics is the fastest: the physics threads (Havok) run on the JIT.",
                   @[@"not-physics", @"all"], @[@"All but physics", @"On (physics recompiled too)"], @"not-physics"),
            Choice(@"profile", BBStoreApp, @"Thread profile",
                   @"Every 20 s the log names where the chosen threads spend their time. Costs a little speed.",
                   @[@"off", @"main", @"render", @"physics"],
                   @[@"Off", @"Main thread", @"Render threads (ours)", @"Physics threads"], @"off"),
            Switch(@"physics_wait_log", BBStoreApp, @"Physics wait log",
                   @"Every 10 s the log lists how often the physics threads sleep and wake, and which threads wake them.", NO),
        ]),
        Section(@"Performance",
                @"Built-in JIT needs your pairing file in this app's folder (Files › Bloodborne, any name) and LocalDevVPN on. Without JIT the game's code is interpreted: far too slow to play.", @[
            Switch(@"BB_IOS_JIT", BBStoreEnv, @"Built-in JIT", @"Enabled through StikJIT when you press Play.", YES),
            Switch(@"efficiency_threads", BBStoreApp, @"Background threads on efficiency cores",
                   @"Audio mixing, file loading, network and saving run on the iPad's low-power cores: less heat. If sound crackles or loading gets slow, turn it off.", NO),
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

/* Resolution, as Madeira's: the size the game draws at, by shape. Values are "aspect:height"
 * (bbport.ini aspect_ratio and output_res; app_main.c ios_output takes the width from the shape).
 * MetalFX scales the result up. Above 540 lines needs the increased memory limit. */
- (BBSetting *)resolutionSetting {
    CGSize native = CGSizeMake(4, 3);
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) native = ((UIWindowScene *)scene).screen.nativeBounds.size;
    const double ratio = MAX(native.width, native.height) / MAX(1.0, MIN(native.width, native.height));
    NSMutableArray *values = [NSMutableArray array], *labels = [NSMutableArray array], *groups = [NSMutableArray array];
    void (^add)(NSString *, double, NSArray *, NSDictionary *) = ^(NSString *aspect, double r, NSArray *heights, NSDictionary *notes) {
        for (NSNumber *h in heights) {
            const int height = h.intValue, width = (int)(height * r / 2.0 + 0.5) * 2;
            NSString *note = notes[h];
            [values addObject:[NSString stringWithFormat:@"%@:%d", aspect, height]];
            [labels addObject:note ? [NSString stringWithFormat:@"%d×%d · %@", width, height, note]
                                   : [NSString stringWithFormat:@"%d×%d", width, height]];
        }
    };
    add(@"auto", ratio, @[@480, @540, @648, @720, @810, @1080],
        @{@480: @"light", @540: @"default", @810: @"heavier", @1080: @"≈1080p, heaviest"});
    [groups addObject:@[@"This screen's shape", @6]];
    add(@"16:9", 16.0 / 9.0, @[@540, @720, @900, @1080], @{@1080: @"1080p"});
    [groups addObject:@[@"16:9 widescreen · bars", @4]];
    if (fabs(ratio - 4.0 / 3.0) > 0.05) {
        add(@"4:3", 4.0 / 3.0, @[@480, @600, @720], @{});
        [groups addObject:@[@"4:3 classic · bars", @3]];
    }
    BBSetting *s = Choice(@"resolution", BBStoreApp, @"Resolution",
        @"The size the game draws at. Larger is sharper and heavier; above 540 lines needs the increased memory limit (GetMoreRam). MetalFX scales it up.",
        values, labels, @"16:9:540");
    s.groups = groups;
    return s;
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
    /* Resolution: the shape and the height (app_main.c ios_output takes the width from the shape). */
    /* "aspect:height", split at the last colon: the aspect has one of its own ("16:9:720"). */
    NSString *resolution = [self valueFor:@"resolution"];
    const NSRange last = [resolution rangeOfString:@":" options:NSBackwardsSearch];
    NSString *aspect = last.location != NSNotFound ? [resolution substringToIndex:last.location] : @"auto";
    int height = last.location != NSNotFound ? [resolution substringFromIndex:last.location + 1].intValue : 540;
    if (height < 360 || height > 1080) height = 540;
    ini[@"aspect_ratio"] = aspect;
    ini[@"output_res"] = [NSString stringWithFormat:@"%dx%d", height * 4 / 3, height];
    /* The overlay: off, the runtime's small FPS counter, or Apple's Metal HUD (MTL_HUD_ENABLED,
     * which the runtime sets on the game's layer). */
    NSString *overlay = [self valueFor:@"overlay"];
    const BOOL own = [overlay isEqualToString:@"fps"] || [overlay isEqualToString:@"detailed"];
    ini[@"show_fps"] = own ? @"1" : @"0";
    ini[@"fps_size"] = [overlay isEqualToString:@"detailed"] ? @"big" : @"small";
    ini[@"fps_position"] = @"top_left";
    if ([overlay isEqualToString:@"metal"]) setenv("MTL_HUD_ENABLED", "1", 1);
    else unsetenv("MTL_HUD_ENABLED");
    [self writeIni:ini];
    /* The recompiled library (private build) on every thread but the physics ones (Havok), which
     * run on the JIT: in Central Yharnam 38-46 FPS against 19-24 with physics recompiled, where the
     * Havok threads woke and slept over and over. Without the library the variable does nothing.
     * The test switches of 2026-11-06 (render cache, short spin, hot functions, profile) are gone;
     * their variables are cleared in case an older session left them. */
    static const char *const cleared[] = {"BB_RECOMP_THREADS", "BB_RECOMP_OFF", "BB_SEMA_SPIN_US", "BB_DMEM_EXTRA_MB",
                                          "BB_WAKE_STATS", "BB_IOS_PROFILE", "BB_IOS_PROFILE_THREAD"};
    for (size_t i = 0; i < sizeof(cleared) / sizeof(cleared[0]); ++i) unsetenv(cleared[i]);
    const BOOL physics_recompiled = [[self valueFor:@"recomp_mode"] isEqualToString:@"all"];
    if (physics_recompiled) unsetenv("BB_RECOMP_NOT_THREADS");
    else setenv("BB_RECOMP_NOT_THREADS", "Havok", 1);
    printf("iOS app: recompiled game code on %s\n", physics_recompiled ? "every thread (physics too)" : "every thread but physics (Havok)");
    /* Game threads off the frame's critical path at utility QoS (runtime BB_EFFICIENCY_THREADS):
     * FMOD's mixer used 19-26% of a performance core in Central Yharnam. */
    if ([[self valueFor:@"efficiency_threads"] boolValue]) {
        setenv("BB_EFFICIENCY_THREADS", "FMOD,Core.Res,NexusRevolution,CSTrophy,Core.Logging,DLUserPreference,SLSession,FrpgSaveLoadMan,FaceGenMan", 1);
        printf("iOS app: background game threads on the efficiency cores\n");
    } else unsetenv("BB_EFFICIENCY_THREADS");
    /* The in-app profile (app/profile.c): the busiest thread of the chosen group every 20 s. The
     * render threads are the runtime's (DrawRec, the GPU command processor, the Vulkan recorders):
     * 60-75% of a core together in Central Yharnam. */
    NSString *profile = [self valueFor:@"profile"];
    if (![profile isEqualToString:@"off"]) {
        setenv("BB_IOS_PROFILE", "1", 1);
        if ([profile isEqualToString:@"render"]) setenv("BB_IOS_PROFILE_THREAD", "DrawRec,GpuCommandProcessor,VkRecorder", 1);
        else if ([profile isEqualToString:@"physics"]) setenv("BB_IOS_PROFILE_THREAD", "Havok", 1);
        /* "main": no filter, the busiest thread (the game's main thread has no host name) */
    }
    /* The runtime's wake log, following the physics threads (BB_WAKE_THREAD=Havok). */
    if ([[self valueFor:@"physics_wait_log"] boolValue]) {
        setenv("BB_WAKE_STATS", "1", 1);
        setenv("BB_WAKE_THREAD", "Havok", 1);
        printf("iOS app: physics wait log on\n");
    } else unsetenv("BB_WAKE_THREAD");
    /* The guest memory pool imported in windows, so no binding reaches past 4 GiB in one buffer:
     * the runtime's fix for stretched geometry ("vertex explosions", its docs/STABILITY.md), off on
     * iOS only because the windows' overlap is memory a 3.3 GB app could not spare. */
    if (os_proc_available_memory() >= (8ull << 30)) setenv("BB_POOL_SPLIT", "1", 1);
    /* What bloodborne-launcher set besides (game_environment): its in-game menu in English,
     * trophy notifications on. */
    setenv("BB_UI_LANGUAGE", "en", 0);
    setenv("BB_TROPHY_OVERLAY", "1", 0);
}

@end
