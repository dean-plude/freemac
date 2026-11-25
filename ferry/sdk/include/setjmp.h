/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Non-local jumps (freemac 1.232, Ferry 0.56.0), sized as on a Mac: a
 * jmp_buf of 37 ints and a sigjmp_buf of 38. Ferry's own setjmp fills
 * them (src/setjmp.c), since this system's C library needs a bigger
 * buffer. setjmp and sigsetjmp(env, 1) keep the signal mask; _setjmp and
 * sigsetjmp(env, 0) don't. */
#ifndef _SETJMP_H_
#define _SETJMP_H_
#include <_ferry.h>
__FERRY_BEGIN
#define _JBLEN 37
typedef int jmp_buf[_JBLEN];
typedef int sigjmp_buf[_JBLEN + 1];
int setjmp(jmp_buf) __attribute__((returns_twice));
void longjmp(jmp_buf, int) __attribute__((noreturn));
int _setjmp(jmp_buf) __attribute__((returns_twice));
void _longjmp(jmp_buf, int) __attribute__((noreturn));
int sigsetjmp(sigjmp_buf, int) __attribute__((returns_twice));
void siglongjmp(sigjmp_buf, int) __attribute__((noreturn));
void longjmperror(void);
__FERRY_END
#endif
