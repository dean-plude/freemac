/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Walking a file tree, as fts(3) describes it (freemac 1.223, Ferry 0.47.0):
 * the entry for each file in turn, directories before (FTS_D) and after
 * (FTS_DP) their contents. Laid out as a Mac program for Intel expects, with
 * 64-bit inode numbers. */
#ifndef _FTS_H_
#define _FTS_H_
#include <_ferry.h>
#include <sys/stat.h>
__FERRY_BEGIN

typedef struct _ftsent {
    struct _ftsent *fts_cycle;  /* the directory this one repeats (FTS_DC) */
    struct _ftsent *fts_parent; /* its directory */
    struct _ftsent *fts_link;   /* the next entry, in a list from fts_children */
    long fts_number;            /* the program's own */
    void *fts_pointer;          /* the program's own */
    char *fts_accpath;          /* a path to reach it by */
    char *fts_path;             /* its path from the starting point */
    int fts_errno;
    int fts_symfd;
    unsigned short fts_pathlen;
    unsigned short fts_namelen;
    ino_t fts_ino;
    dev_t fts_dev;
    nlink_t fts_nlink;
    short fts_level; /* 0 for a starting point */
    unsigned short fts_info;
    unsigned short fts_flags;
    unsigned short fts_instr;
    struct stat *fts_statp;
    char fts_name[1];
} FTSENT;

typedef struct __ferry_fts FTS;

/* fts_open's options */
#define FTS_COMFOLLOW 0x001
#define FTS_LOGICAL 0x002
#define FTS_NOCHDIR 0x004
#define FTS_NOSTAT 0x008
#define FTS_PHYSICAL 0x010
#define FTS_SEEDOT 0x020
#define FTS_XDEV 0x040
#define FTS_WHITEOUT 0x080
#define FTS_COMFOLLOWDIR 0x400
#define FTS_OPTIONMASK 0x4ff
#define FTS_NAMEONLY 0x100
#define FTS_STOP 0x200

/* fts_level of a starting point and of the entry above it */
#define FTS_ROOTPARENTLEVEL -1
#define FTS_ROOTLEVEL 0

/* fts_info */
#define FTS_D 1
#define FTS_DC 2
#define FTS_DEFAULT 3
#define FTS_DNR 4
#define FTS_DOT 5
#define FTS_DP 6
#define FTS_ERR 7
#define FTS_F 8
#define FTS_INIT 9
#define FTS_NS 10
#define FTS_NSOK 11
#define FTS_SL 12
#define FTS_SLNONE 13
#define FTS_W 14

/* fts_set's instructions */
#define FTS_AGAIN 1
#define FTS_FOLLOW 2
#define FTS_NOINSTR 3
#define FTS_SKIP 4

FTS *fts_open(char *const *paths, int options, int (*compar)(const FTSENT **, const FTSENT **))
    __FERRY_INODE64(fts_open);
FTSENT *fts_read(FTS *) __FERRY_INODE64(fts_read);
FTSENT *fts_children(FTS *, int options) __FERRY_INODE64(fts_children);
int fts_set(FTS *, FTSENT *, int instr) __FERRY_INODE64(fts_set);
int fts_close(FTS *) __FERRY_INODE64(fts_close);

__FERRY_END
#endif
