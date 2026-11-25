/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * glob(3) in the Mac's (BSD's) layout and flag numbers, from its man page
 * (freemac 1.233, Ferry 0.57.0). GLOB_ALTDIRFUNC's own directory calls
 * are not served: the fields are there, and left alone. */
#ifndef _GLOB_H_
#define _GLOB_H_
#include <_ferry.h>
__FERRY_BEGIN
struct dirent;
struct stat;
typedef struct {
    size_t gl_pathc;   /* paths matched */
    int gl_matchc;     /* paths matched by this call */
    size_t gl_offs;    /* NULLs at the start of gl_pathv, with GLOB_DOOFFS */
    int gl_flags;
    char **gl_pathv;
    int (*gl_errfunc)(const char *, int);
    void (*gl_closedir)(void *);
    struct dirent *(*gl_readdir)(void *);
    void *(*gl_opendir)(const char *);
    int (*gl_lstat)(const char *, struct stat *);
    int (*gl_stat)(const char *, struct stat *);
} glob_t;

#define GLOB_APPEND 0x0001
#define GLOB_DOOFFS 0x0002
#define GLOB_ERR 0x0004
#define GLOB_MARK 0x0008
#define GLOB_NOCHECK 0x0010
#define GLOB_NOSORT 0x0020
#define GLOB_ALTDIRFUNC 0x0040
#define GLOB_BRACE 0x0080
#define GLOB_MAGCHAR 0x0100
#define GLOB_NOMAGIC 0x0200
#define GLOB_QUOTE 0x0400
#define GLOB_TILDE 0x0800
#define GLOB_NOESCAPE 0x2000
#define GLOB_LIMIT 0x4000

#define GLOB_NOSPACE (-1)
#define GLOB_ABORTED (-2)
#define GLOB_NOMATCH (-3)
#define GLOB_NOSYS (-4)
#define GLOB_ABEND GLOB_ABORTED

int glob(const char *, int, int (*)(const char *, int), glob_t *);
void globfree(glob_t *);
__FERRY_END
#endif
