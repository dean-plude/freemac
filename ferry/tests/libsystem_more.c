/* SPDX-License-Identifier: GPL-3.0-or-later
 * The plumbing the nine apps' sources needed before anything else (freemac
 * 1.221, Ferry 0.45.0): the SDK's availability and target macros, BSD
 * types and limits, inttypes, bitstring, zlib's header, Mach-O's, and
 * libSystem's malloc sizes and zones, basename and dirname, extended
 * attributes, scandir and long double maths. */
#include <Availability.h>
#include <AvailabilityMacros.h>
#include <TargetConditionals.h>
#include <sys/cdefs.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/xattr.h>
#include <sys/stat.h>
#include <inttypes.h>
#include <bitstring.h>
#include <libgen.h>
#include <limits.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <malloc/malloc.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <zlib.h>

static int only_txt(const struct dirent *d) { return strstr(d->d_name, ".txt") != NULL; }

static void attributes(const char *dir)
{
    char path[MAXPATHLEN];
    snprintf(path, sizeof path, "%s/attributes", dir);
    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    close(fd);
    const char *value = "blue";
    if (setxattr(path, "org.example.colour", value, 4, 0, 0) != 0) {
        /* a file system without user attributes: say so the same way */
        printf("xattr: unsupported here (%s)\n", errno == ENOTSUP ? "ENOTSUP" : "other");
        return;
    }
    char got[16] = {0};
    ssize_t n = getxattr(path, "org.example.colour", got, sizeof got, 0, 0);
    printf("xattr: set, get %zd \"%s\", size %zd\n", n, got, getxattr(path, "org.example.colour", NULL, 0, 0, 0));
    char names[256];
    ssize_t len = listxattr(path, names, sizeof names, 0);
    printf("xattr list:");
    for (ssize_t i = 0; i < len; i += (ssize_t)strlen(names + i) + 1)
        printf(" %s", names + i);
    printf("\n");
    errno = 0;
    n = getxattr(path, "org.example.none", got, sizeof got, 0, 0);
    printf("xattr missing: %zd, ENOATTR %d (errno %d)\n", n, errno == ENOATTR, errno);
    errno = 0;
    n = getxattr(path, "org.example.colour", got, sizeof got, 4, 0);
    printf("xattr at a position: %zd, EINVAL %d\n", n, errno == EINVAL);
    printf("xattr remove %d, then list %zd\n", removexattr(path, "org.example.colour", 0),
           listxattr(path, names, sizeof names, 0));
    fd = open(path, O_RDWR);
    printf("fxattr: set %d, get %zd\n", fsetxattr(fd, "org.example.f", "x", 1, 0, 0),
           fgetxattr(fd, "org.example.f", got, sizeof got, 0, 0));
    close(fd);
}

int main(void)
{
    /* the SDK's macros, as a Mac's headers give them */
    printf("mac %d, iphone %d, x86_64 %d, little endian %d\n", TARGET_OS_MAC && TARGET_OS_OSX, TARGET_OS_IPHONE,
           TARGET_CPU_X86_64, TARGET_RT_LITTLE_ENDIAN);
    printf("min required >= 10.13 %d, max allowed >= 14.0 %d, 10.15 is %d\n",
           __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_13, MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_14_0,
           MAC_OS_X_VERSION_10_15);
    __unused int unused_but_quiet = 1;
    u_int32_t u32 = 7;
    u_char uc = 200;
    quad_t q = -5;
    printf("bsd types %u %u %lld, PATH_MAX %d, MAXPATHLEN %d, NAME_MAX %d, howmany %d\n", u32, uc, (long long)q,
           PATH_MAX, MAXPATHLEN, NAME_MAX, howmany(10, 4));
    int64_t big = -1234567890123LL;
    uint32_t hex = 0xbeef;
    printf("inttypes %" PRId64 " %" PRIx32 " %" PRIu8 " %jd\n", big, hex, (uint8_t)255, imaxabs(-42));
    intmax_t parsed = strtoimax("-77", NULL, 10);
    printf("strtoimax %jd\n", parsed);

    bitstr_t bit_decl(bits, 20) = {0};
    bit_set(bits, 3);
    bit_set(bits, 17);
    int first = -1;
    bit_ffs(bits, 20, &first);
    printf("bitstring: 3 %d, 4 %d, 17 %d, first %d\n", bit_test(bits, 3) != 0, bit_test(bits, 4) != 0,
           bit_test(bits, 17) != 0, first);

    /* malloc's sizes and zones */
    printf("good sizes %zu %zu %zu %zu\n", malloc_good_size(1), malloc_good_size(17), malloc_good_size(1000),
           malloc_good_size(5000));
    void *p = malloc(40);
    printf("malloc_size >= 40 %d\n", malloc_size(p) >= 40);
    free(p);
    malloc_zone_t *zone = malloc_create_zone(0, 0);
    malloc_set_zone_name(zone, "test zone");
    char *z = malloc_zone_calloc(zone, 4, 8);
    printf("zone %s, calloc zeroed %d, default zone %s\n", malloc_get_zone_name(zone), z[0] == 0 && z[31] == 0,
           malloc_default_zone() ? "yes" : "no");
    z = malloc_zone_realloc(zone, z, 64);
    malloc_zone_free(zone, z);
    malloc_destroy_zone(zone);

    /* basename and dirname leave their argument alone, as a Mac's do */
    char path[] = "/usr/local/lib/";
    printf("basename %s, dirname %s, path still %s\n", basename(path), dirname(path), path);
    char out[MAXPATHLEN];
    printf("basename_r %s, dirname_r %s, of \"\" %s and %s\n", basename_r("a/b.txt", out),
           dirname_r("a/b.txt", (char[MAXPATHLEN]){0}), basename(""), dirname("file"));

    /* scandir with a filter and alphasort, in a directory of the test's own */
    char dir[] = "/tmp/ferry-scandir-XXXXXX";
    const char *tmp = getenv("TMPDIR");
    char dirbuf[MAXPATHLEN];
    snprintf(dirbuf, sizeof dirbuf, "%s/ferry-scandir-XXXXXX", tmp && *tmp ? tmp : "/tmp");
    char *made = mkdtemp(dirbuf) ? dirbuf : mkdtemp(dir);
    const char *names[] = {"c.txt", "a.txt", "b.dat", "b.txt"};
    for (int i = 0; i < 4; i++) {
        char f[MAXPATHLEN];
        snprintf(f, sizeof f, "%s/%s", made, names[i]);
        close(open(f, O_CREAT | O_WRONLY, 0644));
    }
    struct dirent **list = NULL;
    int count = scandir(made, &list, only_txt, alphasort);
    printf("scandir %d:", count);
    for (int i = 0; i < count; i++) {
        printf(" %s", list[i]->d_name);
        free(list[i]);
    }
    free(list);
    printf("\n");
    attributes(made);

    /* zlib, through this system's own */
    const char *text = "Ferry Ferry Ferry Ferry Ferry Ferry Ferry Ferry Ferry Ferry";
    unsigned char packed[128], unpacked[128];
    uLongf packed_len = sizeof packed, unpacked_len = sizeof unpacked;
    int zr = compress(packed, &packed_len, (const Bytef *)text, strlen(text) + 1);
    int ur = uncompress(unpacked, &unpacked_len, packed, packed_len);
    printf("zlib %d %d, smaller %d, same %d, crc32 %08lx, version %c\n", zr, ur, packed_len < strlen(text),
           strcmp((char *)unpacked, text) == 0, crc32(0, (const Bytef *)"abc", 3), zlibVersion()[0]);

    /* the program's own Mach-O header */
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
    printf("mach-o: magic ok %d, executable %d, x86_64 %d\n", mh && mh->magic == MH_MAGIC_64,
           mh && mh->filetype == MH_EXECUTE, mh && mh->cputype == CPU_TYPE_X86_64);

    /* long double maths, which HexFiend uses for its sizes */
    long double x = 2.0L;
    volatile long double nine = 9.0L;
    printf("long double: sqrt %.6Lf, pow %.1Lf, log2 %.1Lf, floor %.1Lf, fabs %.1Lf\n", sqrtl(x), powl(x, 10),
           log2l(1024.0L), floorl(-nine / 2), fabsl(-nine));
    return 0;
}
