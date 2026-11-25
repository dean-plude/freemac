/* SPDX-License-Identifier: GPL-3.0-or-later
 * Loading plugins as VLC and OBS do (freemac 1.233, Ferry 0.57.0): the
 * program links a core library (libplugcore.dylib, through @rpath), lists
 * a folder of plugins, opens each with dlopen(RTLD_NOW | RTLD_LOCAL), finds
 * the entry point that every plugin defines under the same name, lets it
 * register with the core, and has the core call every plugin on four
 * threads of its own. One plugin brings a library of its own through
 * @loader_path; one is a bundle that calls back into the program; one
 * links a library that isn't there, and one has no entry point. run.sh
 * builds them all into build/plugins_app. Only file names are printed. */
#include "core.h"
#include <dirent.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* What the bundle plugin calls back, and a name the core has too. */
__attribute__((used)) int host_version(void) { return 7; }
__attribute__((used)) const char *core_whoami(void) { return "program"; }

static const char *yes(int ok) { return ok ? "yes" : "NO"; }

static const char *leaf(const char *path)
{
    const char *s = path ? strrchr(path, '/') : NULL;
    return s ? s + 1 : path ? path : "(null)";
}

static int by_name(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

static int is_plugin_file(const char *name)
{
    size_t n = strlen(name);
    return (n > 6 && !strcmp(name + n - 6, ".dylib")) || (n > 3 && !strcmp(name + n - 3, ".so"));
}

int main(int argc, char **argv)
{
    /* the plugin folder beside the program, as VLC finds its "plugins" */
    char dir[4096];
    snprintf(dir, sizeof dir, "%s", argv[0]);
    char *slash = strrchr(dir, '/');
    snprintf(slash ? slash + 1 : dir, sizeof dir - (slash ? (size_t)(slash + 1 - dir) : 0), "plugins_app/modules");

    char *names[32];
    int n = 0;
    DIR *d = opendir(dir);
    printf("the plugin folder: %s\n", d ? "opened" : "MISSING");
    struct dirent *e;
    while (d && (e = readdir(d)) && n < 32)
        if (e->d_name[0] != '.')
            names[n++] = strdup(e->d_name);
    if (d)
        closedir(d);
    qsort(names, n, sizeof *names, by_name);

    void *handles[32];
    plugin_entry_fn entries[32];
    int loaded = 0;
    for (int i = 0; i < n; i++) {
        if (!is_plugin_file(names[i])) {
            printf("%s: not a plugin's name, left alone\n", names[i]);
            continue;
        }
        char path[4096 + 256];
        snprintf(path, sizeof path, "%s/%s", dir, names[i]);
        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            const char *err = dlerror();
            printf("%s: dlopen failed, error names the missing library: %s\n", names[i],
                   yes(err && strstr(err, "libgone.dylib")));
            continue;
        }
        plugin_entry_fn entry = (plugin_entry_fn)dlsym(h, PLUGIN_ENTRY);
        if (!entry) {
            const char *err = dlerror();
            printf("%s: opened, no entry point, error names it: %s; closed: %d\n", names[i],
                   yes(err && strstr(err, PLUGIN_ENTRY)), dlclose(h));
            continue;
        }
        Dl_info info;
        int found = dladdr((void *)entry, &info);
        printf("%s: opened, entry point is its own: %s, a new one: %s\n", names[i],
               yes(found && !strcmp(leaf(info.dli_fname), names[i]) && !strcmp(info.dli_sname, PLUGIN_ENTRY)),
               yes(loaded == 0 || entry != entries[loaded - 1]));
        int slot = entry(path);
        printf("  registered as module %d\n", slot);
        const char **name = (const char **)dlsym(h, "module_name");
        if (name)
            printf("  its module_name: %s\n", *name);
        handles[loaded] = h;
        entries[loaded++] = entry;
    }

    printf("plugins loaded: %d, modules registered: %d\n", loaded, core_count());
    printf("the entry point is hidden from RTLD_DEFAULT: %s\n", yes(dlsym(RTLD_DEFAULT, PLUGIN_ENTRY) == NULL));
    dlerror();
    printf("the program's core_whoami: %s\n", core_whoami());

    long totals[16];
    int threads = core_run(4, 1000, totals);
    printf("the core ran %d threads\n", threads);
    for (int m = 0; m < core_count(); m++)
        printf("  %s: %ld\n", core_module_name(m), totals[m]);
    int (*once)(void) = (int (*)(void))dlsym(handles[0], "alpha_once_count");
    printf("alpha's pthread_once ran once: %s\n", yes(once && once() == 1));

    /* opened again: the same handle; then every handle closed */
    char again[4096 + 256];
    snprintf(again, sizeof again, "%s/%s", dir, "alpha.dylib");
    void *h2 = dlopen(again, RTLD_NOW | RTLD_LOCAL);
    printf("alpha opened again gives the same handle: %s\n", yes(h2 == handles[0]));
    int closed = dlclose(h2) == 0;
    for (int i = 0; i < loaded; i++)
        closed &= dlclose(handles[i]) == 0;
    printf("every handle closed: %s\n", yes(closed));
    for (int i = 0; i < n; i++)
        free(names[i]);
    return 0;
}
