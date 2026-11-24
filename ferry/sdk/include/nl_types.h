/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Message catalogues (catopen), as std::messages names them. */
#ifndef _NL_TYPES_H_
#define _NL_TYPES_H_
#include <_ferry.h>
__FERRY_BEGIN
#define NL_SETD 1
#define NL_CAT_LOCALE 1
typedef struct __nl_cat_d { void *__data; int __size; } *nl_catd;
typedef int nl_item;
nl_catd catopen(const char *, int);
char *catgets(nl_catd, int, int, const char *);
int catclose(nl_catd);
__FERRY_END
#endif
