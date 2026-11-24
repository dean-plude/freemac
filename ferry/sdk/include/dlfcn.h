/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Loading code at run time, from the dlopen(3), dlsym(3) and dladdr(3)
 * man pages. */
#ifndef _DLFCN_H_
#define _DLFCN_H_
#include <_ferry.h>
__FERRY_BEGIN
#define RTLD_LAZY 0x1
#define RTLD_NOW 0x2
#define RTLD_LOCAL 0x4
#define RTLD_GLOBAL 0x8
#define RTLD_NOLOAD 0x10
#define RTLD_NODELETE 0x80
#define RTLD_FIRST 0x100
#define RTLD_NEXT ((void *)-1)
#define RTLD_DEFAULT ((void *)-2)
#define RTLD_SELF ((void *)-3)
#define RTLD_MAIN_ONLY ((void *)-5)
typedef struct dl_info {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
} Dl_info;
void *dlopen(const char *path, int mode);
int dlopen_preflight(const char *path);
void *dlsym(void *handle, const char *symbol);
int dlclose(void *handle);
char *dlerror(void);
int dladdr(const void *addr, Dl_info *info);
__FERRY_END
#endif
