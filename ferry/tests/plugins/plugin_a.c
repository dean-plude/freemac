/* SPDX-License-Identifier: GPL-3.0-or-later
 * A plugin for the plugins test, linked against libplugcore.dylib: the
 * entry point every plugin defines under the same name, a constructor,
 * thread-local state used from the core's threads, and a pthread_once. */
#include "core.h"
#include <pthread.h>

static int constructed;
__attribute__((constructor)) static void start(void) { constructed = 1; }

static __thread int calls_here;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static int once_ran;
static void first_time(void) { once_ran++; }

/* odd items count 3, even ones 1; each thread's count of calls is its own */
static int work(int item)
{
    pthread_once(&once, first_time);
    int before = calls_here++;
    return before >= 0 && calls_here == before + 1 ? (item % 2 ? 3 : 1) : -1000;
}

/* A name the core has too: called from inside this image, its own is used. */
__attribute__((visibility("hidden"))) const char *core_whoami(void) { return "alpha"; }
const char *module_name = "alpha";

int plugin_entry__1_0(const char *path)
{
    core_log("alpha: constructed %s, whoami %s", constructed ? "yes" : "no", core_whoami());
    return core_register(module_name, work);
}

int alpha_once_count(void) { return once_ran; }
