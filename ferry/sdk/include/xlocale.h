/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Per-thread locales and the _l calls that take one. As on macOS, a NULL
 * locale_t means the C locale and LC_GLOBAL_LOCALE the program's own.
 * Ferry serves them from this system's locales (src/xlocale.c). */
#ifndef _XLOCALE_H_
#define _XLOCALE_H_
#include <_ferry.h>
#include <locale.h>
#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>
__FERRY_BEGIN
struct _xlocale;
typedef struct _xlocale *locale_t;
#define LC_GLOBAL_LOCALE ((locale_t)-1)
#define LC_C_LOCALE ((locale_t)0)
#define LC_COLLATE_MASK (1 << 0)
#define LC_CTYPE_MASK (1 << 1)
#define LC_MESSAGES_MASK (1 << 2)
#define LC_MONETARY_MASK (1 << 3)
#define LC_NUMERIC_MASK (1 << 4)
#define LC_TIME_MASK (1 << 5)
#define LC_ALL_MASK (LC_COLLATE_MASK | LC_CTYPE_MASK | LC_MESSAGES_MASK | LC_MONETARY_MASK | LC_NUMERIC_MASK | LC_TIME_MASK)
locale_t newlocale(int, const char *, locale_t);
locale_t duplocale(locale_t);
int freelocale(locale_t);
locale_t uselocale(locale_t);
const char *querylocale(int, locale_t);
struct lconv *localeconv_l(locale_t);
int ___mb_cur_max_l(locale_t);
#define MB_CUR_MAX_L(x) (___mb_cur_max_l(x))
int isalnum_l(int, locale_t);
int isalpha_l(int, locale_t);
int isblank_l(int, locale_t);
int iscntrl_l(int, locale_t);
int isdigit_l(int, locale_t);
int isgraph_l(int, locale_t);
int islower_l(int, locale_t);
int isprint_l(int, locale_t);
int ispunct_l(int, locale_t);
int isspace_l(int, locale_t);
int isupper_l(int, locale_t);
int isxdigit_l(int, locale_t);
int tolower_l(int, locale_t);
int toupper_l(int, locale_t);
int strcoll_l(const char *, const char *, locale_t);
size_t strxfrm_l(char *, const char *, size_t, locale_t);
size_t strftime_l(char *, size_t, const char *, const struct tm *, locale_t);
long strtol_l(const char *, char **, int, locale_t);
unsigned long strtoul_l(const char *, char **, int, locale_t);
long long strtoll_l(const char *, char **, int, locale_t);
unsigned long long strtoull_l(const char *, char **, int, locale_t);
double strtod_l(const char *, char **, locale_t);
float strtof_l(const char *, char **, locale_t);
long double strtold_l(const char *, char **, locale_t);
int snprintf_l(char *, size_t, locale_t, const char *, ...);
int asprintf_l(char **, locale_t, const char *, ...);
int sscanf_l(const char *, locale_t, const char *, ...);
wint_t btowc_l(int, locale_t);
int wctob_l(wint_t, locale_t);
size_t mbrtowc_l(wchar_t *, const char *, size_t, mbstate_t *, locale_t);
size_t wcrtomb_l(char *, wchar_t, mbstate_t *, locale_t);
size_t mbrlen_l(const char *, size_t, mbstate_t *, locale_t);
int mbtowc_l(wchar_t *, const char *, size_t, locale_t);
size_t mbsrtowcs_l(wchar_t *, const char **, size_t, mbstate_t *, locale_t);
size_t mbsnrtowcs_l(wchar_t *, const char **, size_t, size_t, mbstate_t *, locale_t);
size_t wcsnrtombs_l(char *, const wchar_t **, size_t, size_t, mbstate_t *, locale_t);
int iswalpha_l(wint_t, locale_t);
int iswspace_l(wint_t, locale_t);
int iswupper_l(wint_t, locale_t);
int iswlower_l(wint_t, locale_t);
int iswdigit_l(wint_t, locale_t);
int iswxdigit_l(wint_t, locale_t);
int iswpunct_l(wint_t, locale_t);
int iswcntrl_l(wint_t, locale_t);
int iswprint_l(wint_t, locale_t);
int iswblank_l(wint_t, locale_t);
wint_t towlower_l(wint_t, locale_t);
wint_t towupper_l(wint_t, locale_t);
__FERRY_END
#endif
