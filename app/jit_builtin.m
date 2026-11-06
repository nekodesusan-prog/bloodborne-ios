/* bloodborne-ios: JIT enabled at Play, inside the app (the launcher's app).
 *
 * The game's code runs through bbcpu's translator only while iOS lets the app make code at run
 * time, which a sideloaded app gets from a debugger (CS_DEBUGGED). A process cannot debug itself,
 * so the app starts its own helper, PlugIns/BloodborneJITHelper.appex (app/JITHelper/), with the
 * private NSExtension calls (the ones LiveContainer and Madeira use). The helper runs StikJIT
 * (StikDebug/StikJIT, MPL-2.0) through LocalDevVPN with the player's pairing file: it mounts the
 * Developer Disk Image when needed, attaches as a debugger and, on devices with TXM, runs StikJIT's
 * universal script, which answers bbcpu's breakpoint calls (prepare its code buffer, then detach).
 *
 * bb_ios_enable_jit waits on the main run loop until the process is debugged, then has bbcpu set
 * its translator up at once (bbcpu_jit_start), so the debugger detaches before the game starts.
 * Nothing here is fatal: without JIT the game's code is interpreted, as before.
 *   the pairing file                       in Documents or Documents/StikJIT, under any name
 *                                         (pairingFile.plist, *.mobiledevicepairing)
 *   BB_IOS_JIT=0                          do not start the helper
 * Log lines start with "iOS JIT:". */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <unistd.h>

int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
int bbcpu_jit_start(void); /* bbcpu (runtime/bbcpu, ios-jit) */

enum { CS_OPS_STATUS = 0 };
#define CS_DEBUGGED 0x10000000u

/* NSExtension (ExtensionFoundation): private, so declared here. */
@protocol BBExtensionClass
+ (id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
@end
@protocol BBExtension
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *identifier))completion;
- (int)pidForRequestIdentifier:(NSUUID *)identifier;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *identifier, NSArray *items))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *identifier, NSError *error))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *identifier))block;
@end

static int debugged(void) {
    uint32_t flags = 0;
    return csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) == 0 && (flags & CS_DEBUGGED);
}

static int traced(void) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    memset(&info, 0, sizeof(info));
    return sysctl(mib, 4, &info, &size, NULL, 0) == 0 && (info.kp_proc.p_flag & P_TRACED);
}

/* The helper's bundle ID in this installation: sideloading tools rename it with the app's. */
static NSString *helper_identifier(void) {
    NSURL *plugins = [[NSBundle mainBundle] builtInPlugInsURL];
    NSArray<NSURL *> *items = plugins ? [[NSFileManager defaultManager] contentsOfDirectoryAtURL:plugins
        includingPropertiesForKeys:nil options:0 error:nil] : nil;
    for (NSURL *item in items) {
        if (![item.lastPathComponent hasPrefix:@"BloodborneJITHelper"]) continue;
        NSString *identifier = [NSBundle bundleWithURL:item].bundleIdentifier;
        if (identifier.length) return identifier;
    }
    return nil;
}

/* The pairing file: a lockdown pair record (a property list with HostID and HostPrivateKey),
 * under whatever name it has (pairingFile.plist, *.mobiledevicepairing, ...) in Documents or
 * Documents/StikJIT. What was looked at goes into *seen for the log. */
static NSData *pairing_file(NSString *documents, NSMutableString *seen) {
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *dir in @[documents, [documents stringByAppendingPathComponent:@"StikJIT"]]) {
        NSArray<NSString *> *names = [files contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *name in names) {
            [seen appendFormat:@"%s%@", seen.length ? ", " : "", name];
            NSString *lower = name.lowercaseString;
            if (![lower hasSuffix:@".plist"] && ![lower hasSuffix:@".mobiledevicepairing"] &&
                ![lower hasPrefix:@"pairingfile"]) continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data.length) continue;
            id record = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
            if ([record isKindOfClass:[NSDictionary class]] && record[@"HostID"] && record[@"HostPrivateKey"]) {
                printf("iOS JIT: pairing file %s\n", path.UTF8String);
                return data;
            }
        }
    }
    return nil;
}

/* The helper's answer: "ok" 0/1, "message", "txm" ("1", "0" or "?"). */
static NSDictionary *answer_of(NSArray *items) {
    NSData *data = ((NSExtensionItem *)items.firstObject).userInfo[@"BBJITResponse"];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

void bb_ios_enable_jit(const char *documents_path) {
    @autoreleasepool {
        const char *env = getenv("BB_IOS_JIT");
        if (env && env[0] == '0') { printf("iOS JIT: off (BB_IOS_JIT=0)\n"); return; }
        if (debugged()) {
            /* StikDebug or Xcode already did it. */
            printf("iOS JIT: already enabled; translator %s\n", bbcpu_jit_start() ? "on" : "off");
            return;
        }
        NSString *documents = [NSString stringWithUTF8String:documents_path];
        NSMutableString *seen = [NSMutableString string];
        NSData *pairing = pairing_file(documents, seen);
        if (!pairing) {
            printf("iOS JIT: no pairing file in %s or its StikJIT folder (a property list with HostID and "
                   "HostPrivateKey); found: %s. The game's code is interpreted\n", documents_path,
                   seen.length ? seen.UTF8String : "nothing");
            return;
        }
        NSString *identifier = helper_identifier();
        if (!identifier) { printf("iOS JIT: the helper is missing from the app (PlugIns)\n"); return; }
        if (!NSClassFromString(@"NSExtension"))
            dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
        Class<BBExtensionClass> factory = (Class<BBExtensionClass>)NSClassFromString(@"NSExtension");
        NSError *error = nil;
        id<BBExtension> helper = factory ? [factory extensionWithIdentifier:identifier error:&error] : nil;
        if (!helper) {
            printf("iOS JIT: the helper %s could not be opened: %s\n", identifier.UTF8String,
                   error.localizedDescription.UTF8String ?: "no NSExtension");
            return;
        }
        __block NSDictionary *answer = nil;
        __block int ended = 0, started = 0;
        __block NSString *stopped = nil;
        [helper setRequestCompletionBlock:^(NSUUID *request, NSArray *items) {
            NSDictionary *result = answer_of(items);
            dispatch_async(dispatch_get_main_queue(), ^{ answer = result; ended = 1; });
        }];
        [helper setRequestCancellationBlock:^(NSUUID *request, NSError *cancelled) {
            NSString *why = cancelled.localizedDescription ?: @"cancelled";
            dispatch_async(dispatch_get_main_queue(), ^{ stopped = why; ended = 1; });
        }];
        [helper setRequestInterruptionBlock:^(NSUUID *request) {
            dispatch_async(dispatch_get_main_queue(), ^{ stopped = @"the helper stopped"; ended = 1; });
        }];
        NSDictionary *request = @{@"pid": @(getpid()), @"pairing": [pairing base64EncodedStringWithOptions:0]};
        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{@"BBJITRequest": [NSJSONSerialization dataWithJSONObject:request options:0 error:nil]};
        [helper beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *uuid) {
            const int pid = uuid ? [helper pidForRequestIdentifier:uuid] : 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!uuid) { stopped = @"the helper did not start"; ended = 1; return; }
                started = 1;
                printf("iOS JIT: helper started (pid %d); mounting the disk image and attaching\n", pid);
            });
        }];
        /* Up to 3 minutes: the first time, the Developer Disk Image is downloaded. */
        const CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
        while (!debugged() && !ended && CFAbsoluteTimeGetCurrent() - begin < 180)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        if (!debugged()) {
            printf("iOS JIT: not enabled (%s); the game's code is interpreted\n",
                   stopped ? stopped.UTF8String : answer ? [answer[@"message"] UTF8String] ?: "no reason"
                   : started ? "timed out" : "the helper did not answer");
            fflush(stdout);
            return;
        }
        /* Debugged. Without TXM the helper detaches at once and its request ends; with TXM
         * StikJIT's script stays attached, waiting for bbcpu's breakpoint calls. */
        const CFAbsoluteTime attached = CFAbsoluteTimeGetCurrent();
        while (!ended && CFAbsoluteTimeGetCurrent() - attached < 3)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        const int txm = !ended && traced();
        setenv("BB_JIT_TXM", txm ? "1" : "0", 1);
        printf("iOS JIT: enabled in %.1f s (%s)\n", attached - begin,
               txm ? "TXM: preparing the code buffer through StikJIT's script" : "debugger detached");
        fflush(stdout);
        const int on = bbcpu_jit_start();
        printf("iOS JIT: translator %s\n", on ? "on" : "off; the game's code is interpreted");
        if (txm) {
            /* The helper's request ends once the script has detached. */
            const CFAbsoluteTime prepared = CFAbsoluteTimeGetCurrent();
            while (!ended && CFAbsoluteTimeGetCurrent() - prepared < 10)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
            printf("iOS JIT: debugger %s\n", traced() ? "still attached" : "detached");
        }
        if (answer && ![answer[@"ok"] boolValue])
            printf("iOS JIT: the helper reported: %s\n", [answer[@"message"] UTF8String] ?: "");
        fflush(stdout);
        (void)helper; /* kept until here: the request lives as long as the NSExtension */
    }
}
