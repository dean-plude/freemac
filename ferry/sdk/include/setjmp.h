/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Non-local jumps (freemac 1.238, for FreeType). A Mac's jmp_buf is 37
 * ints on x86-64, its sigjmp_buf one more. */
#ifndef _FERRY_SETJMP_H_
#define _FERRY_SETJMP_H_
#include <_ferry.h>
__FERRY_BEGIN
#define _JBLEN ((9 * 2) + 3 + 16)
typedef int jmp_buf[_JBLEN];
typedef int sigjmp_buf[_JBLEN + 1];
int setjmp(jmp_buf) __attribute__((returns_twice));
int _setjmp(jmp_buf) __attribute__((returns_twice));
int sigsetjmp(sigjmp_buf, int) __attribute__((returns_twice));
void longjmp(jmp_buf, int) __attribute__((noreturn));
void _longjmp(jmp_buf, int) __attribute__((noreturn));
void siglongjmp(sigjmp_buf, int) __attribute__((noreturn));
void longjmperror(void);
__FERRY_END
#endif
