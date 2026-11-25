/* SPDX-License-Identifier: GPL-3.0-or-later
 * A plugin that links a library which isn't there (run.sh deletes
 * libgone.dylib after linking it), so its dlopen fails and the host goes
 * on without it. The same file, built without the library, is the plugin
 * that has no entry point. */
#ifdef WITH_GONE
int gone_value(void);
int plugin_entry__1_0(const char *path) { return gone_value(); }
#else
int gone_value(void) { return 1; }
int not_a_plugin(void) { return 0; }
#endif
