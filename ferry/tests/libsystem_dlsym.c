/* SPDX-License-Identifier: GPL-3.0-or-later
 * Loading code while the program runs, from the dlopen(3), dlsym(3),
 * dladdr(3) and dyld(3) man pages: the special handles, a library found
 * through @rpath, @executable_path and @loader_path, a bundle opened
 * RTLD_LOCAL, the system frameworks Ferry provides by their Mac paths,
 * dlerror, dladdr and the _dyld calls. The library and bundle are built
 * by run.sh into build/dlfcn_lib. Only file names are printed. */
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The library defines one too (answering 2). */
__attribute__((used)) int shared_name(void) { return 1; }
/* Called by the bundle, which finds it when it is loaded. */
__attribute__((used)) int main_helper(int x) { return x * 2; }

static const char *yes(int ok) { return ok ? "yes" : "NO"; }

static const char *leaf(const char *path)
{
    const char *s = path ? strrchr(path, '/') : NULL;
    return s ? s + 1 : path ? path : "(null)";
}

static int calls_back;
static void added(const struct mach_header *mh, intptr_t slide) { calls_back++; }

static void error_check(const char *what, const char *expect)
{
    const char *e = dlerror();
    printf("  dlerror after %s: %s, mentions \"%s\": %s, cleared after: %s\n", what, e ? "set" : "none", expect,
           yes(e && strstr(e, expect)), yes(dlerror() == NULL));
}

int main(int argc, char **argv)
{
    printf("dlerror at the start: %s\n", dlerror() ? "set" : "none");

    printf("special handles\n");
    printf("  RTLD_DEFAULT finds printf as the program has it: %s\n", yes(dlsym(RTLD_DEFAULT, "printf") == (void *)printf));
    printf("  RTLD_DEFAULT finds the program's own main_helper: %s\n",
           yes(dlsym(RTLD_DEFAULT, "main_helper") == (void *)main_helper));
    printf("  RTLD_MAIN_ONLY finds main_helper: %s, but not printf: %s\n",
           yes(dlsym(RTLD_MAIN_ONLY, "main_helper") == (void *)main_helper), yes(dlsym(RTLD_MAIN_ONLY, "printf") == NULL));
    error_check("a name the program lacks", "printf");
    printf("  RTLD_DEFAULT of a name nobody has: %s\n", dlsym(RTLD_DEFAULT, "no_such_symbol_anywhere") ? "found" : "NULL");
    error_check("that", "no_such_symbol_anywhere");
    void *self = dlopen(NULL, RTLD_LAZY);
    printf("  dlopen(NULL) finds main_helper: %s\n", yes(self && dlsym(self, "main_helper") == (void *)main_helper));

    typedef struct { uint32_t platform, version; } build_version;
    bool (*check)(uint32_t, const build_version *) =
        (bool (*)(uint32_t, const build_version *))dlsym(RTLD_DEFAULT, "_availability_version_check");
    build_version v147 = {1, (14 << 16) | (7 << 8)}, v15 = {1, 15 << 16}, ios = {2, 1 << 16};
    printf("  _availability_version_check: %s, 14.7: %s, 15.0: %s, an iOS version: %s\n", check ? "found" : "missing",
           check && check(1, &v147) ? "true" : "false", check && check(1, &v15) ? "true" : "false",
           check && check(1, &ios) ? "true" : "false");

    printf("the _dyld calls\n");
    uint32_t before = _dyld_image_count();
    printf("  image 0 is the program: %s, has a header: %s\n", yes(!strcmp(leaf(_dyld_get_image_name(0)), leaf(argv[0]))),
           yes(_dyld_get_image_header(0) != NULL));
    _dyld_register_func_for_add_image(added);
    printf("  add-image callback ran for each image already loaded: %s\n", yes(calls_back == (int)before));
    char exe[4096];
    uint32_t size = 4;
    int rc = _NSGetExecutablePath(exe, &size);
    printf("  _NSGetExecutablePath with too little room: %d, size needed is right: %s\n", rc,
           yes(size > 4 && size < sizeof exe));
    size = sizeof exe;
    _NSGetExecutablePath(exe, &size);
    printf("  _NSGetExecutablePath names this program: %s\n", yes(!strcmp(leaf(exe), leaf(argv[0]))));

    printf("a library through @rpath\n");
    void *plug = dlopen("@rpath/libplug.dylib", RTLD_NOW);
    printf("  dlopen: %s, a new image: %s, callback ran for it: %s\n", plug ? "ok" : dlerror(),
           yes(_dyld_image_count() == before + 1), yes(calls_back == (int)before + 1));
    printf("  last image is libplug.dylib: %s\n", yes(!strcmp(leaf(_dyld_get_image_name(_dyld_image_count() - 1)), "libplug.dylib")));
    int *initialized = (int *)dlsym(plug, "plug_initialized");
    printf("  its initializer ran: %s\n", yes(initialized && *initialized == 1));
    int (*value)(void) = (int (*)(void))dlsym(plug, "plug_value");
    printf("  plug_value(): %d, through RTLD_DEFAULT too: %s\n", value ? value() : -1,
           yes(dlsym(RTLD_DEFAULT, "plug_value") == (void *)value));
    printf("  @executable_path gives the same handle: %s\n",
           yes(dlopen("@executable_path/dlfcn_lib/libplug.dylib", RTLD_NOW) == plug));
    void *(*sibling)(void) = (void *(*)(void))dlsym(plug, "plug_open_sibling");
    printf("  @loader_path from inside it gives the same handle: %s\n", yes(sibling && sibling() == plug));
    printf("  RTLD_NOLOAD of it: %s\n", yes(dlopen("@rpath/libplug.dylib", RTLD_NOLOAD) == plug));

    printf("RTLD_NEXT and RTLD_SELF\n");
    int (*f)(void) = (int (*)(void))dlsym(RTLD_DEFAULT, "shared_name");
    printf("  RTLD_DEFAULT shared_name: %d\n", f ? f() : -1);
    f = (int (*)(void))dlsym(RTLD_NEXT, "shared_name");
    printf("  RTLD_NEXT from the program: %d\n", f ? f() : -1);
    f = (int (*)(void))dlsym(RTLD_SELF, "shared_name");
    printf("  RTLD_SELF from the program: %d\n", f ? f() : -1);
    int (*g)(void) = (int (*)(void))dlsym(plug, "plug_self_shared");
    printf("  RTLD_SELF from the library: %d\n", g ? g() : -1);
    g = (int (*)(void))dlsym(plug, "plug_next_has_shared");
    printf("  RTLD_NEXT from the library finds one: %s\n", g && g() ? "yes" : "no");

    printf("dladdr\n");
    Dl_info info;
    memset(&info, 0, sizeof info);
    rc = dladdr((void *)value, &info);
    printf("  library function: %d, file %s, symbol %s, exact: %s, base is its header: %s\n", rc, leaf(info.dli_fname),
           info.dli_sname, yes(info.dli_saddr == (void *)value),
           yes(info.dli_fbase == (void *)_dyld_get_image_header(_dyld_image_count() - 1)));
    memset(&info, 0, sizeof info);
    rc = dladdr((char *)main_helper + 1, &info);
    printf("  inside the program's main_helper: %d, file is the program: %s, symbol %s, start: %s\n", rc,
           yes(!strcmp(leaf(info.dli_fname), leaf(argv[0]))), info.dli_sname,
           yes(info.dli_saddr == (void *)main_helper));
    memset(&info, 0, sizeof info);
    rc = dladdr((void *)dlsym(RTLD_DEFAULT, "strlen"), &info);
    printf("  libSystem's strlen: %d, file %s, symbol %s\n", rc, info.dli_fname, info.dli_sname);
    rc = dladdr((void *)16, &info);
    printf("  an address in nothing: %d\n", rc);

    printf("a bundle, RTLD_LOCAL\n");
    void *bundle = dlopen("@executable_path/dlfcn_lib/extra.bundle", RTLD_NOW | RTLD_LOCAL);
    printf("  dlopen: %s\n", bundle ? "ok" : dlerror());
    int (*bv)(void) = (int (*)(void))dlsym(bundle, "bundle_value");
    printf("  bundle_value(), through the program's main_helper: %d\n", bv ? bv() : -1);
    printf("  hidden from RTLD_DEFAULT: %s\n", yes(dlsym(RTLD_DEFAULT, "bundle_value") == NULL));
    dlerror();

    printf("libSystem and the frameworks\n");
    void *sys = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
    printf("  /usr/lib/libSystem.B.dylib: %s, printf: %s\n", sys ? "ok" : "failed",
           yes(sys && dlsym(sys, "printf") == (void *)printf));
    printf("  libSystem.dylib by leaf name is the same: %s\n", yes(dlopen("libSystem.dylib", RTLD_LAZY) == sys));
    void *fw = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
    printf("  Foundation by its Mac path: %s, NSLog: %s, CFStringCreateWithCString: %s\n", fw ? "ok" : dlerror(),
           yes(fw && dlsym(fw, "NSLog")), yes(fw && dlsym(fw, "CFStringCreateWithCString")));
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
    printf("  CoreFoundation by its Mac path: %s, CFRelease: %s\n", cf ? "ok" : dlerror(), yes(cf && dlsym(cf, "CFRelease")));
    void *missing = dlopen("/System/Library/Frameworks/Imaginary.framework/Imaginary", RTLD_LAZY);
    printf("  a framework Ferry doesn't have: %s\n", missing ? "opened" : "NULL");
    error_check("it", "doesn't provide");
    printf("  a library that isn't there: %s\n", dlopen("@rpath/libnothing.dylib", RTLD_LAZY) ? "opened" : "NULL");
    error_check("it", "libnothing.dylib");
    printf("  a file that isn't a Mac library: %s\n", dlopen("/dev/null", RTLD_LAZY) ? "opened" : "NULL");
    error_check("it", "/dev/null");
    printf("  still loading after that: %s\n", yes(dlopen("@rpath/libplug.dylib", RTLD_NOLOAD) == plug));
    printf("  dlopen_preflight: the library %s, a missing one %s\n",
           dlopen_preflight("@executable_path/dlfcn_lib/libplug.dylib") ? "yes" : "no",
           dlopen_preflight("/no/such/libthing.dylib") ? "yes" : "no");

    printf("dlclose\n");
    printf("  each open closed: %d %d %d\n", dlclose(plug), dlclose(plug), dlclose(bundle));
    printf("  a handle that isn't one: %d\n", dlclose((void *)&info));
    error_check("it", "invalid");
    return 0;
}
