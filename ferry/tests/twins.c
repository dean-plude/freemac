/* SPDX-License-Identifier: GPL-3.0-or-later
 * Libraries a Mac has in /usr/lib that are the same open-source libraries
 * Linux has (zlib and bzip2 here): a program linking them gets this
 * system's copy. The declarations are written here from the libraries'
 * documented interfaces; tools/twins.tbd lets the linker find them. A call
 * taking a C library FILE stops the program with its name. */
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
void *BZ2_bzReadOpen(int *bzerror, FILE *f, int verbosity, int small, void *unused, int nUnused);

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
    fflush(stdout);
    int err;
    BZ2_bzReadOpen(&err, stdin, 0, 0, NULL, 0); /* takes a FILE: stops here */
    printf("not reached\n");
    return 0;
}
