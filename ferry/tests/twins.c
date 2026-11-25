/* SPDX-License-Identifier: GPL-3.0-or-later
 * Libraries a Mac has in /usr/lib that are the same open-source libraries
 * Linux has (zlib, bzip2, ICU's regular expressions and libxml2 here): a program
 * linking them gets this system's copy (ICU's under its versioned names).
 * The declarations are written here from the libraries' documented
 * interfaces; the SDK's stubs (sdk/gen-twin-tbd.sh) let the linker find
 * them. A call taking a C library FILE stops the program with its name
 * (bzip2's two are served: see libsystem_older). */
#include <stdio.h>
#include <string.h>

int compress(unsigned char *dest, unsigned long *destLen, const unsigned char *src, unsigned long srcLen);
int uncompress(unsigned char *dest, unsigned long *destLen, const unsigned char *src, unsigned long srcLen);
unsigned long crc32(unsigned long crc, const unsigned char *buf, unsigned len);
const char *zlibVersion(void);
int BZ2_bzBuffToBuffCompress(char *dest, unsigned *destLen, char *source, unsigned sourceLen, int blockSize100k,
                             int verbosity, int workFactor);
int BZ2_bzBuffToBuffDecompress(char *dest, unsigned *destLen, char *source, unsigned sourceLen, int small,
                               int verbosity);
void xmlMemDisplay(FILE *f);
typedef unsigned short UChar;
void *uregex_open(const UChar *pattern, int length, unsigned flags, void *parseError, int *status);
void uregex_setText(void *re, const UChar *text, int length, int *status);
int uregex_findNext(void *re, int *status);
int uregex_start(void *re, int group, int *status);
int uregex_end(void *re, int group, int *status);
void uregex_close(void *re);

int main(void)
{
    const char *text = "Ferry, Ferry, Ferry: the same words again and again compress well. Ferry, Ferry, Ferry.";
    unsigned char packed[256], back[256];
    unsigned long plen = sizeof packed, blen = sizeof back;
    printf("zlib %s\n", zlibVersion()[0] >= '1' ? "found" : "odd version");
    int r = compress(packed, &plen, (const unsigned char *)text, strlen(text) + 1);
    printf("compress %d, smaller: %s\n", r, plen < strlen(text) ? "yes" : "no");
    r = uncompress(back, &blen, packed, plen);
    printf("uncompress %d, same: %s\n", r, !strcmp((char *)back, text) ? "yes" : "no");
    printf("crc32 of \"123456789\": %08lx\n", crc32(0, (const unsigned char *)"123456789", 9));
    char bz[512], bzback[256];
    unsigned bzlen = sizeof bz, bzbacklen = sizeof bzback;
    r = BZ2_bzBuffToBuffCompress(bz, &bzlen, (char *)text, strlen(text) + 1, 9, 0, 0);
    printf("bzip2 %d, starts BZh: %s\n", r, !memcmp(bz, "BZh", 3) ? "yes" : "no");
    r = BZ2_bzBuffToBuffDecompress(bzback, &bzbacklen, bz, bzlen, 0, 0);
    printf("bunzip2 %d, same: %s\n", r, !strcmp(bzback, text) ? "yes" : "no");
    /* ICU: find the numbers in a UTF-16 string */
    UChar pattern[8], subject[64];
    const char *p8 = "[0-9]+", *s8 = "hosts 127 and 10 and 1";
    int plen16 = 0, slen16 = 0, status = 0;
    for (; p8[plen16]; plen16++)
        pattern[plen16] = (UChar)p8[plen16];
    for (; s8[slen16]; slen16++)
        subject[slen16] = (UChar)s8[slen16];
    void *re = uregex_open(pattern, plen16, 0, NULL, &status);
    uregex_setText(re, subject, slen16, &status);
    printf("ICU regex, status %d:", status);
    while (uregex_findNext(re, &status))
        printf(" %d-%d", uregex_start(re, 0, &status), uregex_end(re, 0, &status));
    printf("\n");
    uregex_close(re);
    fflush(stdout);
    xmlMemDisplay(stdout); /* takes a FILE: stops here */
    printf("not reached\n");
    return 0;
}
