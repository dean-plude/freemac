/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Character set conversion, as a Mac's libiconv (GNU libiconv 1.11) has it
 * (freemac 1.NEXT, VLC). Link with -liconv. */
#ifndef _FERRY_ICONV_H_
#define _FERRY_ICONV_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN
#define _LIBICONV_VERSION 0x010B
extern int _libiconv_version;
typedef void *iconv_t;
iconv_t iconv_open(const char *tocode, const char *fromcode);
size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
int iconv_close(iconv_t cd);
#define ICONV_TRIVIALP 0
#define ICONV_GET_TRANSLITERATE 1
#define ICONV_SET_TRANSLITERATE 2
#define ICONV_GET_DISCARD_ILSEQ 3
#define ICONV_SET_DISCARD_ILSEQ 4
int iconvctl(iconv_t cd, int request, void *argument);
/* The same calls under GNU libiconv's own names. */
iconv_t libiconv_open(const char *tocode, const char *fromcode);
size_t libiconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
int libiconv_close(iconv_t cd);
int libiconvctl(iconv_t cd, int request, void *argument);
__FERRY_END
#endif
