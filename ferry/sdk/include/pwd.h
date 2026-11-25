/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _PWD_H_
#define _PWD_H_
#include <_ferry.h>
__FERRY_BEGIN
struct passwd {
    char *pw_name, *pw_passwd;
    uid_t pw_uid;
    gid_t pw_gid;
    time_t pw_change;
    char *pw_class, *pw_gecos, *pw_dir, *pw_shell;
    time_t pw_expire;
};
struct passwd *getpwuid(uid_t);
struct passwd *getpwnam(const char *);
/* freemac 1.NEXT (VLC) */
int getpwuid_r(uid_t, struct passwd *, char *, size_t, struct passwd **);
int getpwnam_r(const char *, struct passwd *, char *, size_t, struct passwd **);
__FERRY_END
#endif
