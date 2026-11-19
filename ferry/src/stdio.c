/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * stdio. A Mac program's FILE is a 152-byte structure whose first fields its
 * headers may read directly (the buffer pointer and counts, the flags). Ferry
 * hands the program such a structure for every stream, with both counts at
 * zero so inline code always falls back to __srget/__swbuf, and keeps this
 * system's own FILE in its _cookie field. Every stdio call goes through here.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "ferry.h"

struct mac_sbuf { unsigned char *base; int size; };

struct mac_FILE {
    unsigned char *p;      /* 0 */
    int r, w;              /* 8, 12 */
    short flags, file;     /* 16, 18 */
    struct mac_sbuf bf;    /* 24 */
    int lbfsize;           /* 40 */
    FILE *cookie;          /* 48: this system's FILE */
    void *close, *read, *seek, *write; /* 56..80 */
    struct mac_sbuf ub;    /* 88 */
    void *extra;           /* 104 */
    int ur;                /* 112 */
    unsigned char ubuf[3], nbuf[1];
    struct mac_sbuf lb;    /* 120 */
    int blksize;           /* 136 */
    int64_t offset;        /* 144 */
};
_Static_assert(sizeof(struct mac_FILE) == 152, "Mac FILE is 152 bytes");
_Static_assert(__builtin_offsetof(struct mac_FILE, cookie) == 48, "cookie offset");

#define MAC_SLBF 0x0001
#define MAC_SNBF 0x0002
#define MAC_SRD  0x0004
#define MAC_SWR  0x0008
#define MAC_SRW  0x0010
#define MAC_SEOF 0x0020
#define MAC_SERR 0x0040

static struct mac_FILE mac_stdin_file, mac_stdout_file, mac_stderr_file;
static struct mac_FILE *mac_stdinp = &mac_stdin_file;
static struct mac_FILE *mac_stdoutp = &mac_stdout_file;
static struct mac_FILE *mac_stderrp = &mac_stderr_file;

__attribute__((constructor)) static void setup_std(void)
{
    mac_stdin_file = (struct mac_FILE){.flags = MAC_SRD, .file = 0, .cookie = stdin};
    mac_stdout_file = (struct mac_FILE){.flags = MAC_SWR, .file = 1, .cookie = stdout};
    mac_stderr_file = (struct mac_FILE){.flags = MAC_SWR | MAC_SNBF, .file = 2, .cookie = stderr};
}

static FILE *real(struct mac_FILE *f)
{
    if (!f) {
        fputs("ferry: the program used a missing (NULL) file\n", stderr);
        abort();
    }
    f->r = 0;
    f->w = 0;
    return f->cookie;
}

static void sync_flags(struct mac_FILE *f)
{
    f->flags &= ~(MAC_SEOF | MAC_SERR);
    if (feof(f->cookie))
        f->flags |= MAC_SEOF;
    if (ferror(f->cookie))
        f->flags |= MAC_SERR;
}

static struct mac_FILE *wrap(FILE *fp)
{
    if (!fp)
        return NULL;
    struct mac_FILE *f = calloc(1, sizeof *f);
    if (!f) {
        fclose(fp);
        errno = ENOMEM;
        return NULL;
    }
    f->cookie = fp;
    f->file = fileno(fp);
    f->flags = MAC_SRW;
    return f;
}

static int is_std(struct mac_FILE *f)
{
    return f == &mac_stdin_file || f == &mac_stdout_file || f == &mac_stderr_file;
}

/* ---- opening and closing ------------------------------------------------- */

static struct mac_FILE *mac_fopen(const char *path, const char *mode) { return wrap(fopen(path, mode)); }
static struct mac_FILE *mac_fdopen(int fd, const char *mode) { return wrap(fdopen(fd, mode)); }
static struct mac_FILE *mac_tmpfile(void) { return wrap(tmpfile()); }
static struct mac_FILE *mac_popen(const char *cmd, const char *mode) { return wrap(popen(cmd, mode)); }
static struct mac_FILE *mac_fmemopen(void *buf, size_t size, const char *mode) { return wrap(fmemopen(buf, size, mode)); }
static struct mac_FILE *mac_open_memstream(char **ptr, size_t *size) { return wrap(open_memstream(ptr, size)); }

static struct mac_FILE *mac_freopen(const char *path, const char *mode, struct mac_FILE *f)
{
    FILE *fp = freopen(path, mode, real(f));
    if (!fp)
        return NULL;
    f->cookie = fp;
    f->file = fileno(fp);
    f->flags &= ~(MAC_SEOF | MAC_SERR);
    return f;
}

static int mac_fclose(struct mac_FILE *f)
{
    int rc = fclose(real(f));
    free(f->lb.base);
    f->lb.base = NULL;
    if (!is_std(f))
        free(f);
    else
        f->cookie = NULL;
    return rc;
}

static int mac_pclose(struct mac_FILE *f)
{
    int rc = pclose(real(f));
    if (!is_std(f))
        free(f);
    return rc;
}

/* ---- writing --------------------------------------------------------------- */

static int mac_vfprintf(struct mac_FILE *f, const char *fmt, va_list ap)
{
    int rc = vfprintf(real(f), fmt, ap);
    sync_flags(f);
    return rc;
}

static int mac_fprintf(struct mac_FILE *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int rc = mac_vfprintf(f, fmt, ap);
    va_end(ap);
    return rc;
}

static int mac_fputc(int c, struct mac_FILE *f) { int rc = fputc(c, real(f)); sync_flags(f); return rc; }
static int mac_fputs(const char *s, struct mac_FILE *f) { int rc = fputs(s, real(f)); sync_flags(f); return rc; }

static size_t mac_fwrite(const void *p, size_t size, size_t n, struct mac_FILE *f)
{
    size_t rc = fwrite(p, size, n, real(f));
    sync_flags(f);
    return rc;
}

static int mac_swbuf(int c, struct mac_FILE *f) { return mac_fputc(c, f); }

static int mac_fflush(struct mac_FILE *f) { return fflush(f ? real(f) : NULL); }

/* ---- reading --------------------------------------------------------------- */

static int mac_fgetc(struct mac_FILE *f) { int c = fgetc(real(f)); sync_flags(f); return c; }
static int mac_srget(struct mac_FILE *f) { return mac_fgetc(f); }
static int mac_ungetc(int c, struct mac_FILE *f) { int rc = ungetc(c, real(f)); sync_flags(f); return rc; }

static char *mac_fgets(char *buf, int n, struct mac_FILE *f)
{
    char *rc = fgets(buf, n, real(f));
    sync_flags(f);
    return rc;
}

static size_t mac_fread(void *p, size_t size, size_t n, struct mac_FILE *f)
{
    size_t rc = fread(p, size, n, real(f));
    sync_flags(f);
    return rc;
}

static ssize_t mac_getdelim(char **line, size_t *cap, int delim, struct mac_FILE *f)
{
    ssize_t rc = getdelim(line, cap, delim, real(f));
    sync_flags(f);
    return rc;
}

static ssize_t mac_getline(char **line, size_t *cap, struct mac_FILE *f) { return mac_getdelim(line, cap, '\n', f); }

static int mac_vfscanf(struct mac_FILE *f, const char *fmt, va_list ap)
{
    int rc = vfscanf(real(f), fmt, ap);
    sync_flags(f);
    return rc;
}

static int mac_fscanf(struct mac_FILE *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int rc = mac_vfscanf(f, fmt, ap);
    va_end(ap);
    return rc;
}

/* fgetln returns a line that stays valid until the next read; keep one buffer per FILE. */
static char *mac_fgetln(struct mac_FILE *f, size_t *len)
{
    char **line = (char **)&f->lb.base;
    size_t cap = (size_t)f->lb.size;
    ssize_t n = getline(line, &cap, real(f));
    f->lb.size = (int)cap;
    sync_flags(f);
    if (n < 0)
        return NULL;
    *len = (size_t)n;
    return *line;
}

/* ---- position and state ----------------------------------------------------- */

static int mac_fseek(struct mac_FILE *f, long off, int whence) { int rc = fseek(real(f), off, whence); sync_flags(f); return rc; }
static int mac_fseeko(struct mac_FILE *f, off_t off, int whence) { int rc = fseeko(real(f), off, whence); sync_flags(f); return rc; }
static long mac_ftell(struct mac_FILE *f) { return ftell(real(f)); }
static off_t mac_ftello(struct mac_FILE *f) { return ftello(real(f)); }
static void mac_rewind(struct mac_FILE *f) { rewind(real(f)); sync_flags(f); }
static int mac_fgetpos(struct mac_FILE *f, int64_t *pos) { off_t o = ftello(real(f)); if (o < 0) return -1; *pos = o; return 0; }
static int mac_fsetpos(struct mac_FILE *f, const int64_t *pos) { return mac_fseeko(f, *pos, SEEK_SET); }
static int mac_feof(struct mac_FILE *f) { return feof(real(f)); }
static int mac_ferror(struct mac_FILE *f) { return ferror(real(f)); }
static void mac_clearerr(struct mac_FILE *f) { clearerr(real(f)); sync_flags(f); }
static int mac_fileno(struct mac_FILE *f) { return fileno(real(f)); }
static void mac_flockfile(struct mac_FILE *f) { flockfile(real(f)); }
static void mac_funlockfile(struct mac_FILE *f) { funlockfile(real(f)); }
static int mac_ftrylockfile(struct mac_FILE *f) { return ftrylockfile(real(f)); }

/* The buffering modes have the same numbers on both systems. */
static int mac_setvbuf(struct mac_FILE *f, char *buf, int mode, size_t size) { return setvbuf(real(f), buf, mode, size); }
static void mac_setbuf(struct mac_FILE *f, char *buf) { setbuf(real(f), buf); }
static void mac_setbuffer(struct mac_FILE *f, char *buf, int size) { setbuffer(real(f), buf, size); }
static int mac_setlinebuf(struct mac_FILE *f) { setlinebuf(real(f)); return 0; }

const struct ferry_symbol ferry_stdio_symbols[] = {
    {"__stdinp", &mac_stdinp},
    {"__stdoutp", &mac_stdoutp},
    {"__stderrp", &mac_stderrp},
    {"fopen", mac_fopen},
    {"fdopen", mac_fdopen},
    {"freopen", mac_freopen},
    {"tmpfile", mac_tmpfile},
    {"popen", mac_popen},
    {"fmemopen", mac_fmemopen},
    {"open_memstream", mac_open_memstream},
    {"fclose", mac_fclose},
    {"pclose", mac_pclose},
    {"fprintf", mac_fprintf},
    {"vfprintf", mac_vfprintf},
    {"fputc", mac_fputc},
    {"putc", mac_fputc},
    {"putc_unlocked", mac_fputc},
    {"fputs", mac_fputs},
    {"fwrite", mac_fwrite},
    {"__swbuf", mac_swbuf},
    {"fflush", mac_fflush},
    {"fgetc", mac_fgetc},
    {"getc", mac_fgetc},
    {"getc_unlocked", mac_fgetc},
    {"__srget", mac_srget},
    {"ungetc", mac_ungetc},
    {"fgets", mac_fgets},
    {"fread", mac_fread},
    {"getline", mac_getline},
    {"getdelim", mac_getdelim},
    {"fgetln", mac_fgetln},
    {"fscanf", mac_fscanf},
    {"vfscanf", mac_vfscanf},
    {"fseek", mac_fseek},
    {"fseeko", mac_fseeko},
    {"ftell", mac_ftell},
    {"ftello", mac_ftello},
    {"rewind", mac_rewind},
    {"fgetpos", mac_fgetpos},
    {"fsetpos", mac_fsetpos},
    {"feof", mac_feof},
    {"ferror", mac_ferror},
    {"clearerr", mac_clearerr},
    {"fileno", mac_fileno},
    {"flockfile", mac_flockfile},
    {"funlockfile", mac_funlockfile},
    {"ftrylockfile", mac_ftrylockfile},
    {"setvbuf", mac_setvbuf},
    {"setbuf", mac_setbuf},
    {"setbuffer", mac_setbuffer},
    {"setlinebuf", mac_setlinebuf},
    {NULL, NULL},
};
