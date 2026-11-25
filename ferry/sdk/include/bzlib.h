/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: bzip2's interface, written for freemac from bzip2's public
 * manual (freemac 1.226, Ferry 0.50.0); not bzip2's own header. A Mac's
 * /usr/lib/libbz2.dylib is served by this system's libbz2 (src/host.c), so
 * the structure and numbers here are bzip2's own, the same on both
 * systems; the calls that take a FILE are given this system's FILE for the
 * Mac's. Sequel Pro reads and writes .bz2 dumps through it. Link with
 * -lbz2. */
#ifndef _FERRY_BZLIB_H_
#define _FERRY_BZLIB_H_
#include <_ferry.h>
#include <stdio.h>

__FERRY_BEGIN

#define BZ_RUN 0
#define BZ_FLUSH 1
#define BZ_FINISH 2

#define BZ_OK 0
#define BZ_RUN_OK 1
#define BZ_FLUSH_OK 2
#define BZ_FINISH_OK 3
#define BZ_STREAM_END 4
#define BZ_SEQUENCE_ERROR (-1)
#define BZ_PARAM_ERROR (-2)
#define BZ_MEM_ERROR (-3)
#define BZ_DATA_ERROR (-4)
#define BZ_DATA_ERROR_MAGIC (-5)
#define BZ_IO_ERROR (-6)
#define BZ_UNEXPECTED_EOF (-7)
#define BZ_OUTBUFF_FULL (-8)
#define BZ_CONFIG_ERROR (-9)

#define BZ_MAX_UNUSED 5000

typedef struct {
    char *next_in;
    unsigned int avail_in;
    unsigned int total_in_lo32;
    unsigned int total_in_hi32;
    char *next_out;
    unsigned int avail_out;
    unsigned int total_out_lo32;
    unsigned int total_out_hi32;
    void *state;
    void *(*bzalloc)(void *, int, int);
    void (*bzfree)(void *, void *);
    void *opaque;
} bz_stream;

typedef void BZFILE;

#define BZ_API(func) func
#define BZ_EXTERN extern

/* streams in memory */
int BZ2_bzCompressInit(bz_stream *strm, int blockSize100k, int verbosity, int workFactor);
int BZ2_bzCompress(bz_stream *strm, int action);
int BZ2_bzCompressEnd(bz_stream *strm);
int BZ2_bzDecompressInit(bz_stream *strm, int verbosity, int small);
int BZ2_bzDecompress(bz_stream *strm);
int BZ2_bzDecompressEnd(bz_stream *strm);

/* files, with an error number */
BZFILE *BZ2_bzReadOpen(int *bzerror, FILE *f, int verbosity, int small, void *unused, int nUnused);
void BZ2_bzReadClose(int *bzerror, BZFILE *b);
void BZ2_bzReadGetUnused(int *bzerror, BZFILE *b, void **unused, int *nUnused);
int BZ2_bzRead(int *bzerror, BZFILE *b, void *buf, int len);
BZFILE *BZ2_bzWriteOpen(int *bzerror, FILE *f, int blockSize100k, int verbosity, int workFactor);
void BZ2_bzWrite(int *bzerror, BZFILE *b, void *buf, int len);
void BZ2_bzWriteClose(int *bzerror, BZFILE *b, int abandon, unsigned int *nbytes_in,
                      unsigned int *nbytes_out);
void BZ2_bzWriteClose64(int *bzerror, BZFILE *b, int abandon, unsigned int *nbytes_in_lo32,
                        unsigned int *nbytes_in_hi32, unsigned int *nbytes_out_lo32,
                        unsigned int *nbytes_out_hi32);

/* one buffer to another */
int BZ2_bzBuffToBuffCompress(char *dest, unsigned int *destLen, char *source, unsigned int sourceLen,
                             int blockSize100k, int verbosity, int workFactor);
int BZ2_bzBuffToBuffDecompress(char *dest, unsigned int *destLen, char *source, unsigned int sourceLen,
                               int small, int verbosity);

/* zlib-like file calls */
const char *BZ2_bzlibVersion(void);
BZFILE *BZ2_bzopen(const char *path, const char *mode);
BZFILE *BZ2_bzdopen(int fd, const char *mode);
int BZ2_bzread(BZFILE *b, void *buf, int len);
int BZ2_bzwrite(BZFILE *b, void *buf, int len);
int BZ2_bzflush(BZFILE *b);
void BZ2_bzclose(BZFILE *b);
const char *BZ2_bzerror(BZFILE *b, int *errnum);

__FERRY_END

#endif
