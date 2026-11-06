/* bloodborne-ios: where the busiest thread spends its time, in the log (Settings › Performance ›
 * "Busiest thread profile", BB_IOS_PROFILE=1).
 *
 * Every 20 s: the thread with the most CPU time over half a second is sampled 1,000 times a second
 * for 4 s. Each sample suspends the thread, reads its pc and resumes it: no signals (signals to
 * guest threads broke texture streaming on the Mac), and nothing that takes a lock while it is
 * suspended. The pcs are named afterwards: recompiled functions by their symbol in librecomp.dylib
 * (f_<guest offset>), translated code by the guest block it came from (bbcpu), the runtime and
 * system libraries by symbol. The log gets the shares by kind and the 12 busiest places. It holds
 * guest offsets and symbol names only, no game code.
 *
 * While the thread is suspended its frame-pointer chain is read too (walk): for samples where it
 * waits in the kernel, the log names the runtime function it waits in and the game function that
 * called it; for the two busiest recompiled functions, the game functions that call them. */
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

uint64_t bbcpu_jit_guest_offset_at(uintptr_t pc); /* bbcpu (runtime/bbcpu, ios-jit) */

enum { SAMPLES = 4000, PLACES = 1024, KINDS = 4, FRAMES = 12 };
enum { RECOMPILED, TRANSLATED, RUNTIME, SYSTEM };
static const char *const KIND_NAMES[KINDS] = {"recompiled", "JIT", "runtime", "system"};

typedef struct { char name[112]; int kind; unsigned count; } Place;

static uint64_t cpu_us(thread_act_t thread) {
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return (uint64_t)info.user_time.seconds * 1000000 + (uint64_t)info.user_time.microseconds +
           (uint64_t)info.system_time.seconds * 1000000 + (uint64_t)info.system_time.microseconds;
}

static void thread_name(thread_act_t thread, char *out, size_t size) {
    out[0] = 0;
    pthread_t p = pthread_from_mach_thread_np(thread);
    if (p) pthread_getname_np(p, out, size);
    if (!out[0]) snprintf(out, size, "unnamed");
}

/* The thread (not this one) with the most CPU time over half a second, and its share of a core;
 * with BB_IOS_PROFILE_THREAD=TEXT only threads whose name contains TEXT (e.g. Havok). */
static thread_act_t busiest(double *share) {
    const char *only = getenv("BB_IOS_PROFILE_THREAD");
    thread_act_array_t threads;
    mach_msg_type_number_t count;
    if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) return MACH_PORT_NULL;
    uint64_t *before = calloc(count, sizeof(*before));
    for (mach_msg_type_number_t i = 0; i < count && before; ++i) before[i] = cpu_us(threads[i]);
    usleep(500000);
    const thread_act_t self = mach_thread_self();
    thread_act_t best = MACH_PORT_NULL;
    uint64_t best_us = 0;
    for (mach_msg_type_number_t i = 0; i < count && before; ++i) {
        const uint64_t now = cpu_us(threads[i]), used = now > before[i] ? now - before[i] : 0;
        if (threads[i] == self || used <= best_us) continue;
        if (only && *only) {
            char name[64];
            thread_name(threads[i], name, sizeof(name));
            if (!strstr(name, only)) continue;
        }
        best_us = used, best = threads[i];
    }
    mach_port_deallocate(mach_task_self(), self);
    for (mach_msg_type_number_t i = 0; i < count; ++i)
        if (threads[i] != best) mach_port_deallocate(mach_task_self(), threads[i]);
    vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(*threads));
    free(before);
    *share = best_us / 5000.0; /* microseconds in 0.5 s, as a percentage of one core */
    return best;
}

static Place *place(Place *places, const char *name, int kind) {
    uint32_t h = 2166136261u;
    for (const char *c = name; *c; ++c) h = (h ^ (uint8_t)*c) * 16777619u;
    for (unsigned i = 0; i < PLACES; ++i) {
        Place *p = &places[(h + i) % PLACES];
        if (!p->name[0]) { snprintf(p->name, sizeof(p->name), "%s", name); p->kind = kind; return p; }
        if (!strcmp(p->name, name)) return p;
    }
    return NULL;
}

static int by_count(const void *a, const void *b) {
    const unsigned x = ((const Place *)a)->count, y = ((const Place *)b)->count;
    return x < y ? 1 : x > y ? -1 : 0;
}

static void name_pc(uintptr_t pc, char *out, size_t size, int *kind) {
    const uint64_t guest = bbcpu_jit_guest_offset_at(pc);
    if (guest) {
        *kind = TRANSLATED;
        snprintf(out, size, "guest block +%#llx", (unsigned long long)guest);
        return;
    }
    Dl_info info;
    if (!dladdr((const void *)pc, &info) || !info.dli_fname) {
        *kind = SYSTEM;
        snprintf(out, size, "unknown");
        return;
    }
    const char *file = strrchr(info.dli_fname, '/');
    file = file ? file + 1 : info.dli_fname;
    const char *symbol = info.dli_sname ? info.dli_sname : "?";
    if (!strcmp(file, "librecomp.dylib")) {
        *kind = RECOMPILED;
        snprintf(out, size, "%s", symbol);
    } else if (!strcmp(file, "Bloodborne")) {
        *kind = RUNTIME;
        snprintf(out, size, "%s", symbol);
    } else {
        *kind = SYSTEM;
        snprintf(out, size, "%s %s", file, symbol);
    }
}

/* Return addresses up the frame-pointer chain of a suspended thread (lr first): read with
 * vm_read_overwrite, which fails cleanly on a bad pointer and takes no lock the thread could hold. */
static unsigned walk(const arm_thread_state64_t *state, uintptr_t *out) {
    unsigned n = 0;
    out[n++] = (uintptr_t)arm_thread_state64_get_lr(*state);
    uint64_t fp = (uint64_t)arm_thread_state64_get_fp(*state);
    while (n < FRAMES && fp && !(fp & 7)) {
        uint64_t frame[2];
        vm_size_t got = 0;
        if (vm_read_overwrite(mach_task_self(), (vm_address_t)fp, sizeof(frame), (vm_address_t)frame, &got) != KERN_SUCCESS ||
            got != sizeof(frame))
            break;
        const uint64_t ret = frame[1] & 0x0000ffffffffffffull;
        if (!ret) break;
        if (ret != out[n - 1]) out[n++] = (uintptr_t)ret;
        if (frame[0] <= fp) break; /* the chain only goes up the stack */
        fp = frame[0];
    }
    return n;
}

/* Whether a leaf is the thread waiting (a kernel wait), by its name. */
static int is_wait(const char *where) {
    return strstr(where, "psynch_cvwait") || strstr(where, "psynch_mutexwait") || strstr(where, "semwait") ||
           strstr(where, "mach_msg") || strstr(where, "__ulock_wait") || strstr(where, "__workq_kernreturn");
}

static void top(Place *places, unsigned total, unsigned lines, const char *indent) {
    qsort(places, PLACES, sizeof(*places), by_count);
    for (unsigned i = 0; i < lines && places[i].count; ++i)
        printf("%s%5.1f%% %s\n", indent, 100.0 * places[i].count / total, places[i].name);
}

static void *profile_loop(void *unused) {
    (void)unused;
    pthread_setname_np("bb:profile");
    static uintptr_t pcs[SAMPLES], stacks[SAMPLES][FRAMES];
    static unsigned depth[SAMPLES];
    static Place places[PLACES], waits[PLACES], callers[2][PLACES];
    sleep(30); /* past the title screen's start */
    for (;;) {
        double share = 0;
        const thread_act_t target = busiest(&share);
        if (target == MACH_PORT_NULL) { sleep(20); continue; }
        char name[64];
        thread_name(target, name, sizeof(name));
        unsigned n = 0;
        const struct timespec tick = {0, 1000000};
        for (unsigned i = 0; i < SAMPLES; ++i) {
            if (thread_suspend(target) != KERN_SUCCESS) break;
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            const kern_return_t got = thread_get_state(target, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
            unsigned frames = 0;
            if (got == KERN_SUCCESS) frames = walk(&state, stacks[n]);
            thread_resume(target);
            if (got == KERN_SUCCESS) pcs[n] = (uintptr_t)arm_thread_state64_get_pc(state), depth[n++] = frames;
            nanosleep(&tick, NULL);
        }
        mach_port_deallocate(mach_task_self(), target);
        if (n) {
            memset(places, 0, sizeof(places));
            unsigned kinds[KINDS] = {0};
            for (unsigned i = 0; i < n; ++i) {
                char where[112];
                int kind;
                name_pc(pcs[i], where, sizeof(where), &kind);
                ++kinds[kind];
                Place *p = place(places, where, kind);
                if (p) ++p->count;
            }
            qsort(places, PLACES, sizeof(*places), by_count);
            char clock[16];
            const time_t now = time(NULL);
            struct tm local;
            strftime(clock, sizeof(clock), "%H:%M:%S", localtime_r(&now, &local));
            printf("Profile %s: busiest thread '%s' (%.0f%% of a core), %u samples: recompiled %.0f%%, JIT %.0f%%, "
                   "runtime %.0f%%, system %.0f%%\n", clock, name, share, n, 100.0 * kinds[RECOMPILED] / n,
                   100.0 * kinds[TRANSLATED] / n, 100.0 * kinds[RUNTIME] / n, 100.0 * kinds[SYSTEM] / n);
            for (unsigned i = 0; i < 12 && places[i].count; ++i)
                printf("  %5.1f%% %-10s %s\n", 100.0 * places[i].count / n, KIND_NAMES[places[i].kind], places[i].name);
            /* Waits: the runtime function waited in (the first frame of the app) and the game
             * function that called it (the first recompiled or translated frame). Callers of the two
             * busiest recompiled functions: the next game function up the stack. */
            char hot[2][112] = {"", ""};
            for (unsigned i = 0, h = 0; i < PLACES && h < 2 && places[i].count; ++i)
                if (places[i].kind == RECOMPILED && strncmp(places[i].name, "rc_", 3))
                    snprintf(hot[h++], sizeof(hot[0]), "%s", places[i].name);
            memset(waits, 0, sizeof(waits));
            memset(callers, 0, sizeof(callers));
            unsigned waited = 0, in_hot[2] = {0, 0};
            for (unsigned i = 0; i < n; ++i) {
                char leaf[112], where[112], runtime[112] = "", game[112] = "";
                int kind;
                name_pc(pcs[i], leaf, sizeof(leaf), &kind);
                const int wait = kind == SYSTEM && is_wait(leaf);
                const int h = kind == RECOMPILED && hot[0][0] && !strcmp(leaf, hot[0]) ? 0
                            : kind == RECOMPILED && hot[1][0] && !strcmp(leaf, hot[1]) ? 1 : -1;
                if (!wait && h < 0) continue;
                for (unsigned f = 0; f < depth[i] && !game[0]; ++f) {
                    name_pc(stacks[i][f] - 4, where, sizeof(where), &kind);
                    if (kind == RUNTIME && !runtime[0]) snprintf(runtime, sizeof(runtime), "%s", where);
                    else if ((kind == RECOMPILED || kind == TRANSLATED) && strncmp(where, "rc_", 3) &&
                             (h < 0 || strcmp(where, hot[h])))
                        snprintf(game, sizeof(game), "%s", where);
                }
                char key[112];
                if (wait) {
                    ++waited;
                    snprintf(key, sizeof(key), "%s in %s, from %s", leaf + (strchr(leaf, ' ') ? strchr(leaf, ' ') - leaf + 1 : 0),
                             runtime[0] ? runtime : "?", game[0] ? game : "?");
                    Place *p = place(waits, key, SYSTEM);
                    if (p) ++p->count;
                } else {
                    ++in_hot[h];
                    Place *p = place(callers[h], game[0] ? game : "?", RECOMPILED);
                    if (p) ++p->count;
                }
            }
            if (waited) {
                printf("  waiting %.0f%% of samples, in (share of the waits):\n", 100.0 * waited / n);
                top(waits, waited, 6, "    ");
            }
            for (int h = 0; h < 2; ++h)
                if (in_hot[h]) {
                    printf("  %s called from (share of its samples):\n", hot[h]);
                    top(callers[h], in_hot[h], 4, "    ");
                }
            fflush(stdout);
        }
        sleep(15);
    }
    return NULL;
}

void bb_ios_profile_start(void) {
    const char *on = getenv("BB_IOS_PROFILE");
    if (!on || strcmp(on, "1")) return;
    pthread_t thread;
    if (!pthread_create(&thread, NULL, profile_loop, NULL)) {
        pthread_detach(thread);
        printf("iOS PoC: busiest-thread profile on (every 20 s in this log)\n");
    }
}
