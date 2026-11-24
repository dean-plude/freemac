/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Wide characters, with the macOS types: wint_t is an int and mbstate_t
 * a 128-byte union. Calls that take a FILE are left out. */
#ifndef _WCHAR_H_
#define _WCHAR_H_
#include <_ferry.h>
#include <stdarg.h>
#include <stdio.h>
#include <time.h>
__FERRY_BEGIN
#ifndef _FERRY_WINT_T
#define _FERRY_WINT_T
typedef int wint_t;
#endif
#ifndef _FERRY_MBSTATE_T
#define _FERRY_MBSTATE_T
typedef union { char __mbstate8[128]; long long _mbstateL; } __mbstate_t;
typedef __mbstate_t mbstate_t;
#endif
#ifndef WEOF
#define WEOF ((wint_t)-1)
#endif
#ifndef WCHAR_MIN
#define WCHAR_MIN __WCHAR_MIN__
#define WCHAR_MAX __WCHAR_MAX__
#endif
size_t wcslen(const wchar_t *);
size_t wcsnlen(const wchar_t *, size_t);
wchar_t *wcscpy(wchar_t *, const wchar_t *);
wchar_t *wcsncpy(wchar_t *, const wchar_t *, size_t);
wchar_t *wcscat(wchar_t *, const wchar_t *);
wchar_t *wcsncat(wchar_t *, const wchar_t *, size_t);
int wcscmp(const wchar_t *, const wchar_t *);
int wcsncmp(const wchar_t *, const wchar_t *, size_t);
int wcscoll(const wchar_t *, const wchar_t *);
size_t wcsxfrm(wchar_t *, const wchar_t *, size_t);
wchar_t *wcschr(const wchar_t *, wchar_t);
wchar_t *wcsrchr(const wchar_t *, wchar_t);
wchar_t *wcsstr(const wchar_t *, const wchar_t *);
wchar_t *wcspbrk(const wchar_t *, const wchar_t *);
size_t wcsspn(const wchar_t *, const wchar_t *);
size_t wcscspn(const wchar_t *, const wchar_t *);
wchar_t *wcstok(wchar_t *, const wchar_t *, wchar_t **);
wchar_t *wcsdup(const wchar_t *);
wchar_t *wmemcpy(wchar_t *, const wchar_t *, size_t);
wchar_t *wmemmove(wchar_t *, const wchar_t *, size_t);
wchar_t *wmemset(wchar_t *, wchar_t, size_t);
int wmemcmp(const wchar_t *, const wchar_t *, size_t);
wchar_t *wmemchr(const wchar_t *, wchar_t, size_t);
long wcstol(const wchar_t *, wchar_t **, int);
unsigned long wcstoul(const wchar_t *, wchar_t **, int);
long long wcstoll(const wchar_t *, wchar_t **, int);
unsigned long long wcstoull(const wchar_t *, wchar_t **, int);
double wcstod(const wchar_t *, wchar_t **);
float wcstof(const wchar_t *, wchar_t **);
long double wcstold(const wchar_t *, wchar_t **);
int swprintf(wchar_t *, size_t, const wchar_t *, ...);
int vswprintf(wchar_t *, size_t, const wchar_t *, va_list);
int swscanf(const wchar_t *, const wchar_t *, ...);
size_t wcsftime(wchar_t *, size_t, const wchar_t *, const struct tm *);
wint_t btowc(int);
int wctob(wint_t);
int mbsinit(const mbstate_t *);
size_t mbrlen(const char *, size_t, mbstate_t *);
size_t mbrtowc(wchar_t *, const char *, size_t, mbstate_t *);
size_t wcrtomb(char *, wchar_t, mbstate_t *);
size_t mbsrtowcs(wchar_t *, const char **, size_t, mbstate_t *);
size_t wcsrtombs(char *, const wchar_t **, size_t, mbstate_t *);
size_t mbsnrtowcs(wchar_t *, const char **, size_t, size_t, mbstate_t *);
size_t wcsnrtombs(char *, const wchar_t **, size_t, size_t, mbstate_t *);
int wcwidth(wchar_t);
__FERRY_END
#endif
