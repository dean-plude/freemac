/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _CTYPE_H_
#define _CTYPE_H_
#include <_ferry.h>
__FERRY_BEGIN
int isalnum(int);
int isalpha(int);
int isblank(int);
int iscntrl(int);
int isdigit(int);
int isgraph(int);
int islower(int);
int isprint(int);
int ispunct(int);
int isspace(int);
int isupper(int);
int isxdigit(int);
int isascii(int);
int tolower(int);
int toupper(int);
__FERRY_END
#endif
