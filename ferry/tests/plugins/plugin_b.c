/* SPDX-License-Identifier: GPL-3.0-or-later
 * A second plugin: the same entry point and variable names as plugin_a,
 * and a library of its own (libplugdep.dylib) found through @loader_path. */
#include "core.h"

int dep_square(int x);
const char *module_name = "beta";

static int work(int item) { return dep_square(item); }

int plugin_entry__1_0(const char *path)
{
    core_log("beta: whoami %s, dep_square(7) %d", core_whoami(), dep_square(7));
    return core_register(module_name, work);
}
