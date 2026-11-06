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

    BBSetting *fpsSize = Choice(@"fps_size", BBStoreIni, @"Counter style",
        @"FPS only; the performance bar (FPS, frame time, memory, battery), as Madeira's; or the detailed panel with a frame-time graph.",
        @[@"small", @"bar", @"big"], @[@"FPS only", @"Performance bar", @"Detailed"], @"bar");
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
            [self resolutionSetting],
            Choice(@"BB_LANGUAGE", BBStoreEnv, @"Game language", nil,
                   @[@"1", @"18", @"17", @"7", @"3", @"20", @"2", @"4", @"5", @"6", @"16", @"8", @"19", @"12", @"13", @"14", @"15", @"0", @"9", @"11", @"10"],
                   @[@"English (US)", @"English (UK)", @"Português (Brasil)", @"Português (Portugal)", @"Español (España)",
                     @"Español (Latinoamérica)", @"Français", @"Deutsch", @"Italiano", @"Nederlands", @"Polski", @"Русский",
                     @"Türkçe", @"Suomi", @"Svenska", @"Dansk", @"Norsk", @"日本語", @"한국어", @"简体中文", @"繁體中文"], @"1"),
            Switch(@"skip_intro", BBStoreIni, @"Skip intro videos", nil, YES),
            Switch(@"show_fps", BBStoreIni, @"Performance overlay", nil, YES),
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
            Switch(@"perf_patch", BBStoreIni, @"Performance patch",
                   @"Community patch (Kyo): some of the game's debug settings set for speed. May change some visuals.", NO),
            Switch(@"lower_physics", BBStoreIni, @"Lower object and corpse physics",
                   @"Community patch (Kyo): bodies and objects resist being pushed. Less physics work in crowded fights.", NO),
        ]),
        Section(@"Controls", nil, @[
            Choice(@"BB_TOUCH_CONTROLS", BBStoreEnv, @"On-screen controls",
                   @"Auto shows them while no controller is connected.",
                   @[@"", @"1", @"0"], @[@"Auto", @"Always", @"Never"], @""),
        ]),
        Section(@"Performance",
                @"Built-in JIT needs your pairing file in this app's folder (Files › Bloodborne, any name) and LocalDevVPN on. Without JIT the game's code is interpreted: far too slow to play.", @[
            Switch(@"BB_IOS_JIT", BBStoreEnv, @"Built-in JIT", @"Enabled through StikJIT when you press Play.", YES),
            Choice(@"recomp_threads", BBStoreApp, @"Recompiled game code",
                   @"Only in the private build that carries the recompiled library. The JIT runs the threads named here faster than the recompiled code (vector maths): physics (Havok), then cloth, then character updates. Off: everything on the JIT.",
                   @[@"all", @"not-physics", @"not-physics-cloth", @"not-physics-cloth-chr", @"off"],
                   @[@"On", @"All but physics", @"All but physics and cloth", @"All but physics, cloth, characters", @"Off (JIT only)"],
                   @"not-physics"),
            Switch(@"sema_spin", BBStoreApp, @"Main thread waits awake briefly",
                   @"Test: before the main thread sleeps waiting for a physics or graphics job, it waits up to 40 microseconds awake; most of those jobs finish sooner. Uses a little more power.", NO),
            Switch(@"bigger_render_cache", BBStoreApp, @"Larger render resource cache (512 MB)",
                   @"Test: 512 MB of extra game memory for the game's render resource cache (160 MB otherwise), as on the Mac. If the game does not start, turn it off.", NO),
            Switch(@"hot_on_jit", BBStoreApp, @"Main thread's two busiest functions on the JIT",
                   @"Test: the two game functions the profile finds busiest on the main thread run through the JIT instead of the recompiled code.", NO),
            Choice(@"BB_IOS_PROFILE_THREAD", BBStoreEnv, @"Profile which thread", @"With the profile on: the busiest thread, or the busiest physics (Havok) thread.",
                   @[@"", @"Havok"], @[@"Busiest", @"Physics (Havok)"], @""),
            Switch(@"BB_IOS_PROFILE", BBStoreEnv, @"Busiest thread profile",
                   @"Every 20 s the log names where the busiest thread spends its time, and every 10 s which threads the main thread waited for. Costs a little speed.", NO),
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
        values, labels, @"auto:540");
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
    [self writeIni:ini];
    /* The recompiled library on or off. Off leaves BB_RECOMP_LIB empty (app_main.c sets it only when
     * unset), so bbcpu never loads it. */
    NSString *mode = [self valueFor:@"recomp_threads"];
    const BOOL recomp = ![mode isEqualToString:@"off"];
    /* Parts of host thread names: HavokWorkerThread; SpClothVertexUpdate, CSClothThread*;
     * CSChrThread*, CSChrBackInitialize*. */
    const char *on_jit = [mode isEqualToString:@"not-physics"] ? "Havok"
                       : [mode isEqualToString:@"not-physics-cloth"] ? "Havok,Cloth"
                       : [mode isEqualToString:@"not-physics-cloth-chr"] ? "Havok,Cloth,CSChr" : NULL;
    unsetenv("BB_RECOMP_THREADS"), unsetenv("BB_RECOMP_NOT_THREADS");
    if (recomp) unsetenv("BB_RECOMP_LIB");
    else setenv("BB_RECOMP_LIB", "", 1);
    /* bbcpu (ios-jit 18b8b36 on) runs the filtered threads' calls translated in the same loop. */
    if (recomp && on_jit) setenv("BB_RECOMP_NOT_THREADS", on_jit, 1);
    /* The main thread's two busiest recompiled functions in the in-app profile (Central Yharnam:
     * 11-17% and 6-10% of its samples), by guest offset in the 1.09 executable, left to the JIT
     * (bbcpu's BB_RECOMP_OFF), to see whether the JIT runs them faster as it does physics. */
    const BOOL hot_on_jit = recomp && [[self valueFor:@"hot_on_jit"] boolValue];
    if (hot_on_jit) setenv("BB_RECOMP_OFF", "0x21b89a0,0x21b8710", 1);
    else unsetenv("BB_RECOMP_OFF");
    /* 512 MiB of direct memory past the game's (the runtime's default on the Mac; app_main.c sets
     * 0 on iOS when unset) for the render resource cache's larger backing. It goes inside the
     * guest block at 0x7000000000, where ~640 MiB past the pool is unused: a test of whether it
     * fits with this layout. */
    if ([[self valueFor:@"bigger_render_cache"] boolValue]) {
        setenv("BB_DMEM_EXTRA_MB", "512", 1);
        printf("iOS app: 512 MiB extra direct memory for the render resource cache\n");
    } else unsetenv("BB_DMEM_EXTRA_MB");
    /* The main thread's semaphore waits (about 10,000 per 10 s at 0.02-0.07 ms in Central Yharnam)
     * spin up to 40 us before sleeping (runtime BB_SEMA_SPIN_US). */
    if ([[self valueFor:@"sema_spin"] boolValue]) {
        setenv("BB_SEMA_SPIN_US", "40", 1);
        printf("iOS app: main thread spins up to 40 us before sleeping on a semaphore\n");
    } else unsetenv("BB_SEMA_SPIN_US");
    /* The profile switch also turns on the runtime's record of who wakes the main thread. */
    if ([[self valueFor:@"BB_IOS_PROFILE"] boolValue]) setenv("BB_WAKE_STATS", "1", 1);
    else unsetenv("BB_WAKE_STATS");
    if (hot_on_jit) printf("iOS app: the main thread's two busiest functions on the JIT (BB_RECOMP_OFF)\n");
    printf("iOS app: recompiled game code %s%s%s\n", !recomp ? "off (JIT only)" : "on",
           recomp && on_jit ? "; on the JIT: threads named " : "", recomp && on_jit ? on_jit : "");
    /* The guest memory pool imported in windows, so no binding reaches past 4 GiB in one buffer:
     * the runtime's fix for stretched geometry ("vertex explosions", its docs/STABILITY.md), off on
     * iOS only because the windows' overlap is memory a 3.3 GB app could not spare. */
    if (os_proc_available_memory() >= (8ull << 30)) setenv("BB_POOL_SPLIT", "1", 1);
    /* What bloodborne-launcher set besides (game_environment): its in-game menu in English,
     * trophy notifications on. */
    setenv("BB_UI_LANGUAGE", "en", 0);
    /* The performance bar reads the battery's charge (UIDevice): monitoring on, on the main thread. */
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    setenv("BB_TROPHY_OVERLAY", "1", 0);
}

@end
