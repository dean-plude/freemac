/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: zlib's interface, written for freemac from zlib's public
 * manual (freemac 1.221, Ferry 0.45.0); not zlib's own header. A Mac's
 * /usr/lib/libz.1.dylib is served by this system's zlib (src/host.c), so
 * the structures and numbers here are zlib's own, which are the same on
 * both systems. Link with -lz. */
#ifndef _FERRY_ZLIB_H_
#define _FERRY_ZLIB_H_
#include <_ferry.h>
#include <sys/types.h>

__FERRY_BEGIN

/* Any zlib 1.x answers to a program built for 1.2.12: the version check
 * in the ...Init_ calls compares the first digit only. */
#define ZLIB_VERSION "1.2.12"
#define ZLIB_VERNUM 0x12c0
#define ZLIB_VER_MAJOR 1
#define ZLIB_VER_MINOR 2
#define ZLIB_VER_REVISION 12
#define ZLIB_VER_SUBREVISION 0

/* the types and macros the calls are written with (freemac 1.226, Ferry 0.50.0) */
#include <zconf.h>

typedef voidpf (*alloc_func)(voidpf opaque, uInt items, uInt size);
typedef void (*free_func)(voidpf opaque, voidpf address);

struct internal_state;

typedef struct z_stream_s {
    const Bytef *next_in;
    uInt avail_in;
    uLong total_in;
    Bytef *next_out;
    uInt avail_out;
    uLong total_out;
    const char *msg;
    struct internal_state *state;
    alloc_func zalloc;
    free_func zfree;
    voidpf opaque;
    int data_type;
    uLong adler;
    uLong reserved;
} z_stream;
typedef z_stream *z_streamp;

typedef struct gz_header_s {
    int text;
    uLong time;
    int xflags;
    int os;
    Bytef *extra;
    uInt extra_len;
    uInt extra_max;
    Bytef *name;
    uInt name_max;
    Bytef *comment;
    uInt comm_max;
    int hcrc;
    int done;
} gz_header;
typedef gz_header *gz_headerp;

/* flush values */
#define Z_NO_FLUSH 0
#define Z_PARTIAL_FLUSH 1
#define Z_SYNC_FLUSH 2
#define Z_FULL_FLUSH 3
#define Z_FINISH 4
#define Z_BLOCK 5
#define Z_TREES 6
/* return codes */
#define Z_OK 0
#define Z_STREAM_END 1
#define Z_NEED_DICT 2
#define Z_ERRNO (-1)
#define Z_STREAM_ERROR (-2)
#define Z_DATA_ERROR (-3)
#define Z_MEM_ERROR (-4)
#define Z_BUF_ERROR (-5)
#define Z_VERSION_ERROR (-6)
/* compression levels and strategies */
#define Z_NO_COMPRESSION 0
#define Z_BEST_SPEED 1
#define Z_BEST_COMPRESSION 9
#define Z_DEFAULT_COMPRESSION (-1)
#define Z_FILTERED 1
#define Z_HUFFMAN_ONLY 2
#define Z_RLE 3
#define Z_FIXED 4
#define Z_DEFAULT_STRATEGY 0
/* data types */
#define Z_BINARY 0
#define Z_TEXT 1
#define Z_ASCII Z_TEXT
#define Z_UNKNOWN 2
#define Z_DEFLATED 8
#define Z_NULL 0

const char *zlibVersion(void);
uLong zlibCompileFlags(void);
const char *zError(int err);

int deflate(z_streamp strm, int flush);
int deflateEnd(z_streamp strm);
int deflateInit_(z_streamp strm, int level, const char *version, int stream_size);
int deflateInit2_(z_streamp strm, int level, int method, int windowBits, int memLevel, int strategy,
                  const char *version, int stream_size);
int deflateSetDictionary(z_streamp strm, const Bytef *dictionary, uInt dictLength);
int deflateGetDictionary(z_streamp strm, Bytef *dictionary, uInt *dictLength);
int deflateCopy(z_streamp dest, z_streamp source);
int deflateReset(z_streamp strm);
int deflateParams(z_streamp strm, int level, int strategy);
int deflateTune(z_streamp strm, int good_length, int max_lazy, int nice_length, int max_chain);
uLong deflateBound(z_streamp strm, uLong sourceLen);
int deflatePending(z_streamp strm, unsigned *pending, int *bits);
int deflatePrime(z_streamp strm, int bits, int value);
int deflateSetHeader(z_streamp strm, gz_headerp head);

int inflate(z_streamp strm, int flush);
int inflateEnd(z_streamp strm);
int inflateInit_(z_streamp strm, const char *version, int stream_size);
int inflateInit2_(z_streamp strm, int windowBits, const char *version, int stream_size);
int inflateSetDictionary(z_streamp strm, const Bytef *dictionary, uInt dictLength);
int inflateGetDictionary(z_streamp strm, Bytef *dictionary, uInt *dictLength);
int inflateSync(z_streamp strm);
int inflateCopy(z_streamp dest, z_streamp source);
int inflateReset(z_streamp strm);
int inflateReset2(z_streamp strm, int windowBits);
int inflatePrime(z_streamp strm, int bits, int value);
long inflateMark(z_streamp strm);
int inflateGetHeader(z_streamp strm, gz_headerp head);
typedef unsigned (*in_func)(void *, const unsigned char **);
typedef int (*out_func)(void *, unsigned char *, unsigned);
int inflateBackInit_(z_streamp strm, int windowBits, unsigned char *window, const char *version, int stream_size);
int inflateBack(z_streamp strm, in_func in, void *in_desc, out_func out, void *out_desc);
int inflateBackEnd(z_streamp strm);

#define deflateInit(strm, level) deflateInit_((strm), (level), ZLIB_VERSION, (int)sizeof(z_stream))
#define inflateInit(strm) inflateInit_((strm), ZLIB_VERSION, (int)sizeof(z_stream))
#define deflateInit2(strm, level, method, windowBits, memLevel, strategy) \
    deflateInit2_((strm), (level), (method), (windowBits), (memLevel), (strategy), ZLIB_VERSION, (int)sizeof(z_stream))
#define inflateInit2(strm, windowBits) inflateInit2_((strm), (windowBits), ZLIB_VERSION, (int)sizeof(z_stream))
#define inflateBackInit(strm, windowBits, window) \
    inflateBackInit_((strm), (windowBits), (window), ZLIB_VERSION, (int)sizeof(z_stream))

int compress(Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen);
int compress2(Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen, int level);
uLong compressBound(uLong sourceLen);
int uncompress(Bytef *dest, uLongf *destLen, const Bytef *source, uLong sourceLen);
int uncompress2(Bytef *dest, uLongf *destLen, const Bytef *source, uLong *sourceLen);

uLong adler32(uLong adler, const Bytef *buf, uInt len);
uLong adler32_z(uLong adler, const Bytef *buf, z_size_t len);
uLong adler32_combine(uLong adler1, uLong adler2, z_off_t len2);
uLong crc32(uLong crc, const Bytef *buf, uInt len);
uLong crc32_z(uLong crc, const Bytef *buf, z_size_t len);
uLong crc32_combine(uLong crc1, uLong crc2, z_off_t len2);
const z_crc_t *get_crc_table(void);

typedef struct gzFile_s *gzFile;
gzFile gzopen(const char *path, const char *mode);
gzFile gzdopen(int fd, const char *mode);
int gzbuffer(gzFile file, unsigned size);
int gzsetparams(gzFile file, int level, int strategy);
int gzread(gzFile file, voidp buf, unsigned len);
z_size_t gzfread(voidp buf, z_size_t size, z_size_t nitems, gzFile file);
int gzwrite(gzFile file, voidpc buf, unsigned len);
z_size_t gzfwrite(voidpc buf, z_size_t size, z_size_t nitems, gzFile file);
int gzprintf(gzFile file, const char *format, ...);
int gzputs(gzFile file, const char *s);
char *gzgets(gzFile file, char *buf, int len);
int gzputc(gzFile file, int c);
int gzgetc(gzFile file);
int gzungetc(int c, gzFile file);
int gzflush(gzFile file, int flush);
z_off_t gzseek(gzFile file, z_off_t offset, int whence);
int gzrewind(gzFile file);
z_off_t gztell(gzFile file);
z_off_t gzoffset(gzFile file);
int gzeof(gzFile file);
int gzdirect(gzFile file);
int gzclose(gzFile file);
int gzclose_r(gzFile file);
int gzclose_w(gzFile file);
const char *gzerror(gzFile file, int *errnum);
void gzclearerr(gzFile file);

__FERRY_END
#endif
