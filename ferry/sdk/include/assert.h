/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#include <_ferry.h>
#undef assert
#if !defined(__cplusplus) && !defined(static_assert)
#define static_assert _Static_assert
#endif
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
__FERRY_BEGIN
void __assert_rtn(const char *, const char *, int, const char *) __attribute__((noreturn));
__FERRY_END
#define assert(e) ((e) ? (void)0 : __assert_rtn(__func__, __FILE__, __LINE__, #e))
#endif
/* C11's static_assert, as a Mac's <assert.h> defines it for C (C++ has its
   own keyword, and C23 makes it one too). */
#if !defined(__cplusplus) && !defined(static_assert) && \
    (!defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L)
#define static_assert _Static_assert
#endif
