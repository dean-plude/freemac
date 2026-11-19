/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#include <_ferry.h>
#undef assert
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
__FERRY_BEGIN
void __assert_rtn(const char *, const char *, int, const char *) __attribute__((noreturn));
__FERRY_END
#define assert(e) ((e) ? (void)0 : __assert_rtn(__func__, __FILE__, __LINE__, #e))
#endif
