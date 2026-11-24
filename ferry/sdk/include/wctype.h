/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Wide character classes. On macOS wctype_t is a mask of the same _CTYPE_
 * bits the narrow tables use (ctype.h). */
#ifndef _WCTYPE_H_
#define _WCTYPE_H_
#include <_ferry.h>
#include <ctype.h>
__FERRY_BEGIN
#ifndef _FERRY_WINT_T
#define _FERRY_WINT_T
typedef int wint_t;
#endif
typedef uint32_t wctype_t;
typedef int wctrans_t;
#ifndef WEOF
#define WEOF ((wint_t)-1)
#endif
int iswalnum(wint_t);
int iswalpha(wint_t);
int iswblank(wint_t);
int iswcntrl(wint_t);
int iswdigit(wint_t);
int iswgraph(wint_t);
int iswlower(wint_t);
int iswprint(wint_t);
int iswpunct(wint_t);
int iswspace(wint_t);
int iswupper(wint_t);
int iswxdigit(wint_t);
wint_t towlower(wint_t);
wint_t towupper(wint_t);
int iswctype(wint_t, wctype_t);
wctype_t wctype(const char *);
__FERRY_END
#endif
