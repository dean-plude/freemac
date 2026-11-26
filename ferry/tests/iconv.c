/* SPDX-License-Identifier: GPL-3.0-or-later */
/* GNU libiconv's calls, as a Mac's /usr/lib/libiconv.2.dylib has them
 * (freemac 1.238; VLC's subtitle decoder converts Windows-1252 text). */
#include <errno.h>
#include <iconv.h>
#include <stdio.h>
#include <string.h>

static void show(const char *label, const char *s, size_t n)
{
    printf("%s:", label);
    for (size_t i = 0; i < n; i++)
        printf(" %02x", (unsigned char)s[i]);
    printf("\n");
}

int main(void)
{
    iconv_t cd = iconv_open("UTF-8", "CP1252");
    printf("opened: %d\n", cd != (iconv_t)-1);
    char in[] = "caf\xe9 \x80", out[32];
    char *ip = in, *op = out;
    size_t il = strlen(in), ol = sizeof out;
    size_t r = iconv(cd, &ip, &il, &op, &ol);
    printf("converted: %zu, left %zu\n", r, il);
    show("utf-8", out, sizeof out - ol);
    iconv(cd, NULL, NULL, NULL, NULL);

    /* too little room: E2BIG, with what fitted written */
    ip = in, il = strlen(in), op = out, ol = 4;
    r = iconv(cd, &ip, &il, &op, &ol);
    printf("small: %d, E2BIG %d, wrote %zu\n", r == (size_t)-1, errno == E2BIG, 4 - ol);
    printf("closed: %d\n", iconv_close(cd));

    /* bad input: EILSEQ in the Mac's number */
    cd = libiconv_open("UTF-16LE", "UTF-8");
    char bad[] = "a\xff", wide[8];
    ip = bad, il = 2, op = wide, ol = sizeof wide;
    r = libiconv(cd, &ip, &il, &op, &ol);
    printf("bad: %d, EILSEQ %d (%d), stopped at %td\n", r == (size_t)-1, errno == EILSEQ, EILSEQ, ip - bad);
    show("utf-16le", wide, sizeof wide - ol);
    int trivial = -1;
    printf("trivial: %d %d\n", iconvctl(cd, ICONV_TRIVIALP, &trivial), trivial);
    libiconv_close(cd);

    printf("unknown set: %d, EINVAL %d\n", iconv_open("UTF-8", "NO-SUCH-SET") == (iconv_t)-1, errno == EINVAL);
    return 0;
}
