/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The group database (freemac 1.232, Ferry 0.56.0). A group record is laid
 * out the same on a Mac and on Linux, so these are this system's own. */
#ifndef _GRP_H_
#define _GRP_H_
#include <_ferry.h>
__FERRY_BEGIN
struct group {
    char *gr_name;
    char *gr_passwd;
    gid_t gr_gid;
    char **gr_mem;
};
struct group *getgrgid(gid_t);
struct group *getgrnam(const char *);
int getgrgid_r(gid_t, struct group *, char *, size_t, struct group **);
int getgrnam_r(const char *, struct group *, char *, size_t, struct group **);
struct group *getgrent(void);
void setgrent(void);
void endgrent(void);
int getgrouplist(const char *, int, int *, int *);
int initgroups(const char *, int);
__FERRY_END
#endif
