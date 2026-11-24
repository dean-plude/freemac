/* SPDX-License-Identifier: GPL-3.0-or-later
 * A Mac library the libsystem_dlsym test opens with dlopen (built by
 * run.sh with the install name @rpath/libplug.dylib). It has an
 * initializer, a variable, a name the program also defines (for RTLD_NEXT
 * and RTLD_SELF) and a dlopen of itself through @loader_path. */
#include <dlfcn.h>

int plug_initialized;
int plug_counter = 41;

__attribute__((constructor)) static void plug_start(void) { plug_initialized = 1; }

int plug_value(void) { return ++plug_counter; }

/* The program defines one too; this one answers 2. */
int shared_name(void) { return 2; }

/* RTLD_SELF from here finds this library's own; RTLD_NEXT looks only past it. */
int plug_self_shared(void)
{
    int (*f)(void) = (int (*)(void))dlsym(RTLD_SELF, "shared_name");
    return f ? f() : -1;
}
int plug_next_has_shared(void) { return dlsym(RTLD_NEXT, "shared_name") != NULL; }

/* @loader_path is the folder of the image that calls dlopen, which dlopen
 * tells by its return address: kept out of a tail call, so that the call
 * returns here rather than to the program. */
static void *volatile sibling;
void *plug_open_sibling(void)
{
    sibling = dlopen("@loader_path/libplug.dylib", RTLD_NOLOAD);
    return sibling;
}
