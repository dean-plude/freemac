/* SPDX-License-Identifier: GPL-3.0-or-later
 * A third plugin, a bundle (MH_BUNDLE) built with -undefined
 * dynamic_lookup and linked against nothing, as some hosts build theirs:
 * every call it makes is looked up in the flat namespace when it is
 * loaded. It calls the core and the program's own host_version, and
 * weakly imports a call nobody has, which must come out NULL rather than
 * as a call that stops it. */
#include "core.h"

int host_version(void);
extern int no_such_call_anywhere(int) __attribute__((weak_import));

static int work(int item) { return host_version(); }

int plugin_entry__1_0(const char *path)
{
    /* looked up flat, core_whoami is the first image's that has one: the program's */
    core_log("gamma: host_version %d, whoami %s, the missing weak call is %s", host_version(), core_whoami(),
             no_such_call_anywhere ? "there" : "NULL");
    return core_register("gamma", work);
}
