/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* strings.h (freemac 1.223, Ferry 0.47.0): the BSD string calls, as
 * hoedown, MacDown's Markdown library, includes them. Written from their
 * man pages; each is passed through to this system's C library. */
#ifndef _FERRY_STRINGS_H_
#define _FERRY_STRINGS_H_
#include <_ferry.h>
#include <stddef.h>
__FERRY_BEGIN
int bcmp(const void *, const void *, size_t);
void bcopy(const void *, void *, size_t);
void bzero(void *, size_t);
char *index(const char *, int);
char *rindex(const char *, int);
int ffs(int);
int ffsl(long);
int ffsll(long long);
int strcasecmp(const char *, const char *);
int strncasecmp(const char *, const char *, size_t);
__FERRY_END
#endif
