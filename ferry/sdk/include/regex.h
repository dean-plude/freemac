/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * POSIX regular expressions with the Mac's layout and numbers, from its
 * regex(3) man page (freemac 1.264, Ferry 0.87.0): Ferry's libc keeps the
 * compiled pattern itself, behind re_g. */
#ifndef _REGEX_H_
#define _REGEX_H_
#include <_ferry.h>
#include <stddef.h>
__FERRY_BEGIN
typedef long long regoff_t;
typedef struct {
    int re_magic;
    size_t re_nsub; /* the parenthesized groups */
    const char *re_endp;
    void *re_g;
} regex_t;
typedef struct {
    regoff_t rm_so, rm_eo;
} regmatch_t;
/* regcomp */
#define REG_BASIC 0000
#define REG_EXTENDED 0001
#define REG_ICASE 0002
#define REG_NOSUB 0004
#define REG_NEWLINE 0010
#define REG_NOSPEC 0020
#define REG_PEND 0040
/* errors */
#define REG_NOMATCH 1
#define REG_BADPAT 2
#define REG_ECOLLATE 3
#define REG_ECTYPE 4
#define REG_EESCAPE 5
#define REG_ESUBREG 6
#define REG_EBRACK 7
#define REG_EPAREN 8
#define REG_EBRACE 9
#define REG_BADBR 10
#define REG_ERANGE 11
#define REG_ESPACE 12
#define REG_BADRPT 13
#define REG_EMPTY 14
#define REG_ASSERT 15
#define REG_INVARG 16
#define REG_ILLSEQ 17
/* regexec */
#define REG_NOTBOL 00001
#define REG_NOTEOL 00002
#define REG_STARTEND 00004
int regcomp(regex_t *preg, const char *pattern, int cflags);
int regexec(const regex_t *preg, const char *string, size_t nmatch, regmatch_t pmatch[], int eflags);
size_t regerror(int errcode, const regex_t *preg, char *errbuf, size_t errbuf_size);
void regfree(regex_t *preg);
__FERRY_END
#endif
