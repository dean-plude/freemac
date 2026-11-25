/* SPDX-License-Identifier: GPL-3.0-or-later
 * The host's core library for the plugins test (built by run.sh as
 * libplugcore.dylib, install name @rpath/libplugcore.dylib), standing for
 * libvlccore or libobs: the program and every plugin link it, plugins
 * register what they do with it, and it calls them back on its own threads. */
#ifndef PLUGCORE_H
#define PLUGCORE_H
typedef int (*core_work_fn)(int item);
/* the versioned entry point each plugin defines, as VLC's vlc_entry__3_0_0ft64 */
typedef int (*plugin_entry_fn)(const char *path);
#define PLUGIN_ENTRY "plugin_entry__1_0"

int core_register(const char *module, core_work_fn work);
int core_count(void);
/* runs every registered module's work over items 0..items-1 on "threads"
 * threads of its own and gives each module's total, in order */
int core_run(int threads, int items, long *totals);
const char *core_module_name(int i);
const char *core_whoami(void);
int core_log(const char *format, ...);
#endif
