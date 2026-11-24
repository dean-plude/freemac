/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CommonCrypto, the part of libSystem that Mac programs use for digests,
 * message authentication codes, encryption, key derivation and random
 * bytes. Written for freemac from Apple's public documentation of the
 * calls (the CommonCrypto manual pages) and from the published standards:
 * MD5 (RFC 1321), SHA-1 and SHA-2 (FIPS 180-4), HMAC (RFC 2104), PBKDF2
 * (RFC 8018), AES (FIPS 197) and its modes (NIST SP 800-38A), and PKCS #7
 * padding (RFC 5652).
 *
 * The digests, HMAC, PBKDF2 and random bytes are Ferry's own code here: a
 * Mac program keeps their state in structures of a documented size on its
 * own stack, so the state has to fit there. AES itself is done by this
 * system's OpenSSL libcrypto, opened the first time a program encrypts
 * (src/host.c); Ferry keeps the buffering and the padding itself, so the
 * answers are CommonCrypto's. Without libcrypto, encryption answers
 * kCCUnimplemented and everything else still works.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <time.h>

#include "ferry.h"

/* ---- status codes and numbers (the CommonCrypto manual pages) -------------------- */

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError = -4304,
    kCCUnimplemented = -4305,
    kCCRNGFailure = -4307,
    kCCUnspecifiedError = -4308,
    kCCKeySizeError = -4310,
};
enum { kCCEncrypt = 0, kCCDecrypt = 1 };
enum { kCCAlgorithmAES = 0 };
enum { kCCOptionPKCS7Padding = 1, kCCOptionECBMode = 2 };
enum { kCCModeECB = 1, kCCModeCBC = 2, kCCModeCTR = 4 };
enum { ccNoPadding = 0, ccPKCS7Padding = 1 };
enum { kCCModeOptionCTR_LE = 1, kCCModeOptionCTR_BE = 2 };
enum { kCCHmacAlgSHA1, kCCHmacAlgMD5, kCCHmacAlgSHA256, kCCHmacAlgSHA384, kCCHmacAlgSHA512, kCCHmacAlgSHA224 };
enum { kCCPBKDF2 = 2 };
enum { kCCPRFHmacAlgSHA1 = 1, kCCPRFHmacAlgSHA224, kCCPRFHmacAlgSHA256, kCCPRFHmacAlgSHA384, kCCPRFHmacAlgSHA512 };

static inline uint32_t rol32(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }
static inline uint32_t ror32(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
static inline uint64_t ror64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }
static inline uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static inline uint32_t le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }
static inline uint64_t be64(const uint8_t *p) { return (uint64_t)be32(p) << 32 | be32(p + 4); }
static inline void put_be32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static inline void put_le32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static inline void put_be64(uint8_t *p, uint64_t v) { put_be32(p, v >> 32); put_be32(p + 4, (uint32_t)v); }

/* ---- the digests ------------------------------------------------------------------
 * Each state is laid out to fit the program's structure exactly:
 * CC_MD5_CTX is 92 bytes, CC_SHA1_CTX 96, CC_SHA256_CTX (also SHA-224's)
 * 104 and CC_SHA512_CTX (also SHA-384's) 208, as the documented
 * structures are. Lengths are kept in bytes. */

struct md5_state {
    uint32_t h[4];
    uint32_t lo, hi;
    uint8_t buf[64];
    int32_t num;
};
struct sha1_state {
    uint32_t h[5];
    uint32_t lo, hi;
    uint8_t buf[64];
    int32_t num;
};
struct sha256_state {
    uint32_t lo, hi;
    uint32_t h[8];
    uint8_t buf[64];
};
struct sha512_state {
    uint64_t lo, hi;
    uint64_t h[8];
    uint8_t buf[128];
};
_Static_assert(sizeof(struct md5_state) == 92, "CC_MD5_CTX is 92 bytes");
_Static_assert(sizeof(struct sha1_state) == 96, "CC_SHA1_CTX is 96 bytes");
_Static_assert(sizeof(struct sha256_state) == 104, "CC_SHA256_CTX is 104 bytes");
_Static_assert(sizeof(struct sha512_state) == 208, "CC_SHA512_CTX is 208 bytes");

static void md5_block(uint32_t h[4], const uint8_t *p)
{
    static const uint32_t K[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    };
    static const int S[64] = {7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                              5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,  14, 20,
                              4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                              6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21};
    uint32_t m[16];
    for (int i = 0; i < 16; i++)
        m[i] = le32(p + 4 * i);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f;
        int g;
        if (i < 16)
            f = (b & c) | (~b & d), g = i;
        else if (i < 32)
            f = (d & b) | (~d & c), g = (5 * i + 1) & 15;
        else if (i < 48)
            f = b ^ c ^ d, g = (3 * i + 5) & 15;
        else
            f = c ^ (b | ~d), g = (7 * i) & 15;
        uint32_t t = d;
        d = c;
        c = b;
        b = b + rol32(a + f + K[i] + m[g], S[i]);
        a = t;
    }
    h[0] += a, h[1] += b, h[2] += c, h[3] += d;
}

static void sha1_block(uint32_t h[5], const uint8_t *p)
{
    uint32_t w[80];
    for (int i = 0; i < 16; i++)
        w[i] = be32(p + 4 * i);
    for (int i = 16; i < 80; i++)
        w[i] = rol32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20)
            f = (b & c) | (~b & d), k = 0x5a827999;
        else if (i < 40)
            f = b ^ c ^ d, k = 0x6ed9eba1;
        else if (i < 60)
            f = (b & c) | (b & d) | (c & d), k = 0x8f1bbcdc;
        else
            f = b ^ c ^ d, k = 0xca62c1d6;
        uint32_t t = rol32(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = rol32(b, 30);
        b = a;
        a = t;
    }
    h[0] += a, h[1] += b, h[2] += c, h[3] += d, h[4] += e;
}

static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void sha256_block(uint32_t h[8], const uint8_t *p)
{
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = be32(p + 4 * i);
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ror32(w[i - 15], 7) ^ ror32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ror32(w[i - 2], 17) ^ ror32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = hh + (ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25)) + ((e & f) ^ (~e & g)) + K256[i] + w[i];
        uint32_t t2 = (ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
    }
    h[0] += a, h[1] += b, h[2] += c, h[3] += d, h[4] += e, h[5] += f, h[6] += g, h[7] += hh;
}

static const uint64_t K512[80] = {
    0x428a2f98d728ae22ull, 0x7137449123ef65cdull, 0xb5c0fbcfec4d3b2full, 0xe9b5dba58189dbbcull,
    0x3956c25bf348b538ull, 0x59f111f1b605d019ull, 0x923f82a4af194f9bull, 0xab1c5ed5da6d8118ull,
    0xd807aa98a3030242ull, 0x12835b0145706fbeull, 0x243185be4ee4b28cull, 0x550c7dc3d5ffb4e2ull,
    0x72be5d74f27b896full, 0x80deb1fe3b1696b1ull, 0x9bdc06a725c71235ull, 0xc19bf174cf692694ull,
    0xe49b69c19ef14ad2ull, 0xefbe4786384f25e3ull, 0x0fc19dc68b8cd5b5ull, 0x240ca1cc77ac9c65ull,
    0x2de92c6f592b0275ull, 0x4a7484aa6ea6e483ull, 0x5cb0a9dcbd41fbd4ull, 0x76f988da831153b5ull,
    0x983e5152ee66dfabull, 0xa831c66d2db43210ull, 0xb00327c898fb213full, 0xbf597fc7beef0ee4ull,
    0xc6e00bf33da88fc2ull, 0xd5a79147930aa725ull, 0x06ca6351e003826full, 0x142929670a0e6e70ull,
    0x27b70a8546d22ffcull, 0x2e1b21385c26c926ull, 0x4d2c6dfc5ac42aedull, 0x53380d139d95b3dfull,
    0x650a73548baf63deull, 0x766a0abb3c77b2a8ull, 0x81c2c92e47edaee6ull, 0x92722c851482353bull,
    0xa2bfe8a14cf10364ull, 0xa81a664bbc423001ull, 0xc24b8b70d0f89791ull, 0xc76c51a30654be30ull,
    0xd192e819d6ef5218ull, 0xd69906245565a910ull, 0xf40e35855771202aull, 0x106aa07032bbd1b8ull,
    0x19a4c116b8d2d0c8ull, 0x1e376c085141ab53ull, 0x2748774cdf8eeb99ull, 0x34b0bcb5e19b48a8ull,
    0x391c0cb3c5c95a63ull, 0x4ed8aa4ae3418acbull, 0x5b9cca4f7763e373ull, 0x682e6ff3d6b2b8a3ull,
    0x748f82ee5defb2fcull, 0x78a5636f43172f60ull, 0x84c87814a1f0ab72ull, 0x8cc702081a6439ecull,
    0x90befffa23631e28ull, 0xa4506cebde82bde9ull, 0xbef9a3f7b2c67915ull, 0xc67178f2e372532bull,
    0xca273eceea26619cull, 0xd186b8c721c0c207ull, 0xeada7dd6cde0eb1eull, 0xf57d4f7fee6ed178ull,
    0x06f067aa72176fbaull, 0x0a637dc5a2c898a6ull, 0x113f9804bef90daeull, 0x1b710b35131c471bull,
    0x28db77f523047d84ull, 0x32caab7b40c72493ull, 0x3c9ebe0a15c9bebcull, 0x431d67c49c100d4cull,
    0x4cc5d4becb3e42b6ull, 0x597f299cfc657e2aull, 0x5fcb6fab3ad6faecull, 0x6c44198c4a475817ull,
};

static void sha512_block(uint64_t h[8], const uint8_t *p)
{
    uint64_t w[80];
    for (int i = 0; i < 16; i++)
        w[i] = be64(p + 8 * i);
    for (int i = 16; i < 80; i++) {
        uint64_t s0 = ror64(w[i - 15], 1) ^ ror64(w[i - 15], 8) ^ (w[i - 15] >> 7);
        uint64_t s1 = ror64(w[i - 2], 19) ^ ror64(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint64_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 80; i++) {
        uint64_t t1 = hh + (ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41)) + ((e & f) ^ (~e & g)) + K512[i] + w[i];
        uint64_t t2 = (ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g, g = f, f = e, e = d + t1, d = c, c = b, b = a, a = t1 + t2;
    }
    h[0] += a, h[1] += b, h[2] += c, h[3] += d, h[4] += e, h[5] += f, h[6] += g, h[7] += hh;
}

/* The common part of every digest's update: whole blocks go to the
 * compression function, the rest waits in the buffer. */
#define FEED(block, state, bs, filled, data, len)                       \
    do {                                                                \
        const uint8_t *p_ = (const uint8_t *)(data);                    \
        size_t n_ = (len), f_ = (filled);                               \
        if (f_) {                                                       \
            size_t take_ = bs - f_ < n_ ? bs - f_ : n_;                 \
            memcpy((state)->buf + f_, p_, take_);                       \
            p_ += take_, n_ -= take_, f_ += take_;                      \
            if (f_ == bs)                                               \
                block((state)->h, (state)->buf), f_ = 0;                \
        }                                                               \
        for (; n_ >= bs; p_ += bs, n_ -= bs)                            \
            block((state)->h, p_);                                      \
        memcpy((state)->buf, p_, n_);                                   \
        (void)f_;                                                       \
    } while (0)

static void add_count32(uint32_t *lo, uint32_t *hi, size_t n)
{
    uint64_t c = ((uint64_t)*hi << 32 | *lo) + n;
    *lo = (uint32_t)c;
    *hi = (uint32_t)(c >> 32);
}

/* MD5 */
static int cc_md5_init(struct md5_state *c)
{
    memset(c, 0, sizeof *c);
    c->h[0] = 0x67452301, c->h[1] = 0xefcdab89, c->h[2] = 0x98badcfe, c->h[3] = 0x10325476;
    return 1;
}
static int cc_md5_update(struct md5_state *c, const void *data, uint32_t len)
{
    size_t filled = c->lo & 63;
    add_count32(&c->lo, &c->hi, len);
    FEED(md5_block, c, 64, filled, data, len);
    c->num = c->lo & 63;
    return 1;
}
static int cc_md5_final(unsigned char *md, struct md5_state *c)
{
    uint64_t bits = ((uint64_t)c->hi << 32 | c->lo) * 8;
    uint8_t pad[72] = {0x80};
    size_t filled = c->lo & 63, padlen = filled < 56 ? 56 - filled : 120 - filled;
    uint8_t len[8];
    put_le32(len, (uint32_t)bits);
    put_le32(len + 4, (uint32_t)(bits >> 32));
    cc_md5_update(c, pad, (uint32_t)padlen);
    cc_md5_update(c, len, 8);
    for (int i = 0; i < 4; i++)
        put_le32(md + 4 * i, c->h[i]);
    memset(c, 0, sizeof *c);
    return 1;
}
static unsigned char *cc_md5(const void *data, uint32_t len, unsigned char *md)
{
    struct md5_state c;
    cc_md5_init(&c);
    cc_md5_update(&c, data, len);
    cc_md5_final(md, &c);
    return md;
}

/* SHA-1 */
static int cc_sha1_init(struct sha1_state *c)
{
    memset(c, 0, sizeof *c);
    c->h[0] = 0x67452301, c->h[1] = 0xefcdab89, c->h[2] = 0x98badcfe, c->h[3] = 0x10325476, c->h[4] = 0xc3d2e1f0;
    return 1;
}
static int cc_sha1_update(struct sha1_state *c, const void *data, uint32_t len)
{
    size_t filled = c->lo & 63;
    add_count32(&c->lo, &c->hi, len);
    FEED(sha1_block, c, 64, filled, data, len);
    c->num = c->lo & 63;
    return 1;
}
static int cc_sha1_final(unsigned char *md, struct sha1_state *c)
{
    uint64_t bits = ((uint64_t)c->hi << 32 | c->lo) * 8;
    uint8_t pad[72] = {0x80}, len[8];
    size_t filled = c->lo & 63, padlen = filled < 56 ? 56 - filled : 120 - filled;
    put_be64(len, bits);
    cc_sha1_update(c, pad, (uint32_t)padlen);
    cc_sha1_update(c, len, 8);
    for (int i = 0; i < 5; i++)
        put_be32(md + 4 * i, c->h[i]);
    memset(c, 0, sizeof *c);
    return 1;
}
static unsigned char *cc_sha1(const void *data, uint32_t len, unsigned char *md)
{
    struct sha1_state c;
    cc_sha1_init(&c);
    cc_sha1_update(&c, data, len);
    cc_sha1_final(md, &c);
    return md;
}

/* SHA-256 and SHA-224 */
static int sha256_start(struct sha256_state *c, const uint32_t iv[8])
{
    memset(c, 0, sizeof *c);
    memcpy(c->h, iv, sizeof c->h);
    return 1;
}
static const uint32_t IV256[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
static const uint32_t IV224[8] = {0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
                                  0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4};
static int cc_sha256_init(struct sha256_state *c) { return sha256_start(c, IV256); }
static int cc_sha224_init(struct sha256_state *c) { return sha256_start(c, IV224); }
static int cc_sha256_update(struct sha256_state *c, const void *data, uint32_t len)
{
    size_t filled = c->lo & 63;
    add_count32(&c->lo, &c->hi, len);
    FEED(sha256_block, c, 64, filled, data, len);
    return 1;
}
static void sha256_finish(unsigned char *md, struct sha256_state *c, int words)
{
    uint64_t bits = ((uint64_t)c->hi << 32 | c->lo) * 8;
    uint8_t pad[72] = {0x80}, len[8];
    size_t filled = c->lo & 63, padlen = filled < 56 ? 56 - filled : 120 - filled;
    put_be64(len, bits);
    cc_sha256_update(c, pad, (uint32_t)padlen);
    cc_sha256_update(c, len, 8);
    for (int i = 0; i < words; i++)
        put_be32(md + 4 * i, c->h[i]);
    memset(c, 0, sizeof *c);
}
static int cc_sha256_final(unsigned char *md, struct sha256_state *c) { sha256_finish(md, c, 8); return 1; }
static int cc_sha224_final(unsigned char *md, struct sha256_state *c) { sha256_finish(md, c, 7); return 1; }
static unsigned char *cc_sha256(const void *data, uint32_t len, unsigned char *md)
{
    struct sha256_state c;
    cc_sha256_init(&c);
    cc_sha256_update(&c, data, len);
    cc_sha256_final(md, &c);
    return md;
}
static unsigned char *cc_sha224(const void *data, uint32_t len, unsigned char *md)
{
    struct sha256_state c;
    cc_sha224_init(&c);
    cc_sha256_update(&c, data, len);
    cc_sha224_final(md, &c);
    return md;
}

/* SHA-512 and SHA-384 */
static const uint64_t IV512[8] = {0x6a09e667f3bcc908ull, 0xbb67ae8584caa73bull, 0x3c6ef372fe94f82bull,
                                  0xa54ff53a5f1d36f1ull, 0x510e527fade682d1ull, 0x9b05688c2b3e6c1full,
                                  0x1f83d9abfb41bd6bull, 0x5be0cd19137e2179ull};
static const uint64_t IV384[8] = {0xcbbb9d5dc1059ed8ull, 0x629a292a367cd507ull, 0x9159015a3070dd17ull,
                                  0x152fecd8f70e5939ull, 0x67332667ffc00b31ull, 0x8eb44a8768581511ull,
                                  0xdb0c2e0d64f98fa7ull, 0x47b5481dbefa4fa4ull};
static int sha512_start(struct sha512_state *c, const uint64_t iv[8])
{
    memset(c, 0, sizeof *c);
    memcpy(c->h, iv, sizeof c->h);
    return 1;
}
static int cc_sha512_init(struct sha512_state *c) { return sha512_start(c, IV512); }
static int cc_sha384_init(struct sha512_state *c) { return sha512_start(c, IV384); }
static int cc_sha512_update(struct sha512_state *c, const void *data, uint32_t len)
{
    size_t filled = c->lo & 127;
    uint64_t before = c->lo;
    c->lo += len;
    if (c->lo < before)
        c->hi++;
    FEED(sha512_block, c, 128, filled, data, len);
    return 1;
}
static void sha512_finish(unsigned char *md, struct sha512_state *c, int words)
{
    uint8_t pad[144] = {0x80}, len[16];
    size_t filled = c->lo & 127, padlen = filled < 112 ? 112 - filled : 240 - filled;
    put_be64(len, c->hi << 3 | c->lo >> 61);
    put_be64(len + 8, c->lo << 3);
    cc_sha512_update(c, pad, (uint32_t)padlen);
    cc_sha512_update(c, len, 16);
    for (int i = 0; i < words; i++)
        put_be64(md + 8 * i, c->h[i]);
    memset(c, 0, sizeof *c);
}
static int cc_sha512_final(unsigned char *md, struct sha512_state *c) { sha512_finish(md, c, 8); return 1; }
static int cc_sha384_final(unsigned char *md, struct sha512_state *c) { sha512_finish(md, c, 6); return 1; }
static unsigned char *cc_sha512(const void *data, uint32_t len, unsigned char *md)
{
    struct sha512_state c;
    cc_sha512_init(&c);
    cc_sha512_update(&c, data, len);
    cc_sha512_final(md, &c);
    return md;
}
static unsigned char *cc_sha384(const void *data, uint32_t len, unsigned char *md)
{
    struct sha512_state c;
    cc_sha384_init(&c);
    cc_sha512_update(&c, data, len);
    cc_sha384_final(md, &c);
    return md;
}

/* ---- one digest, chosen at run time (for HMAC and PBKDF2) ------------------------- */

union any_state {
    struct md5_state md5;
    struct sha1_state sha1;
    struct sha256_state sha256;
    struct sha512_state sha512;
};
struct digest {
    size_t size, block;
    int (*init)(void *);
    void (*update)(void *, const void *, size_t);
    int (*final)(unsigned char *, void *);
};

/* Each digest's three steps on an untyped state, the updates with a
 * size_t length (in pieces a CC_LONG can hold). */
#define ANY_DIGEST(name, type, init_fn, update_fn, final_fn)                  \
    static int name##_init(void *c) { return init_fn((type *)c); }             \
    static int name##_final(unsigned char *md, void *c) { return final_fn(md, (type *)c); } \
    static void name##_update(void *c, const void *data, size_t len)           \
    {                                                                         \
        const uint8_t *p = data;                                              \
        while (len) {                                                         \
            uint32_t n = len > 0x40000000u ? 0x40000000u : (uint32_t)len;     \
            update_fn((type *)c, p, n);                                       \
            p += n, len -= n;                                                 \
        }                                                                     \
    }
ANY_DIGEST(any_md5, struct md5_state, cc_md5_init, cc_md5_update, cc_md5_final)
ANY_DIGEST(any_sha1, struct sha1_state, cc_sha1_init, cc_sha1_update, cc_sha1_final)
ANY_DIGEST(any_sha224, struct sha256_state, cc_sha224_init, cc_sha256_update, cc_sha224_final)
ANY_DIGEST(any_sha256, struct sha256_state, cc_sha256_init, cc_sha256_update, cc_sha256_final)
ANY_DIGEST(any_sha384, struct sha512_state, cc_sha384_init, cc_sha512_update, cc_sha384_final)
ANY_DIGEST(any_sha512, struct sha512_state, cc_sha512_init, cc_sha512_update, cc_sha512_final)

static const struct digest d_md5 = {16, 64, any_md5_init, any_md5_update, any_md5_final};
static const struct digest d_sha1 = {20, 64, any_sha1_init, any_sha1_update, any_sha1_final};
static const struct digest d_sha224 = {28, 64, any_sha224_init, any_sha224_update, any_sha224_final};
static const struct digest d_sha256 = {32, 64, any_sha256_init, any_sha256_update, any_sha256_final};
static const struct digest d_sha384 = {48, 128, any_sha384_init, any_sha384_update, any_sha384_final};
static const struct digest d_sha512 = {64, 128, any_sha512_init, any_sha512_update, any_sha512_final};

static const struct digest *hmac_digest(uint32_t alg)
{
    switch (alg) {
    case kCCHmacAlgSHA1: return &d_sha1;
    case kCCHmacAlgMD5: return &d_md5;
    case kCCHmacAlgSHA256: return &d_sha256;
    case kCCHmacAlgSHA384: return &d_sha384;
    case kCCHmacAlgSHA512: return &d_sha512;
    case kCCHmacAlgSHA224: return &d_sha224;
    }
    return NULL;
}

/* ---- HMAC (RFC 2104) ---------------------------------------------------------------
 * CCHmacContext is 384 bytes, aligned for 32-bit words. It holds the inner
 * digest's state and the key XORed with the outer pad, which the last
 * step needs; the state is worked on in a copy, so that it can be aligned. */

struct hmac_state {
    uint32_t alg, valid;
    union any_state inner;
    uint8_t okey[128];
};
_Static_assert(sizeof(struct hmac_state) <= 384, "CCHmacContext is 384 bytes");
#define HMAC_VALID 0x484d4143u

static void hmac_start(struct hmac_state *h, const struct digest *d, uint32_t alg, const void *key, size_t keylen)
{
    uint8_t k[128] = {0}, ipad[128];
    if (keylen > d->block) {
        union any_state s;
        d->init(&s);
        d->update(&s, key, keylen);
        d->final(k, &s);
    } else if (keylen)
        memcpy(k, key, keylen);
    for (size_t i = 0; i < d->block; i++) {
        ipad[i] = k[i] ^ 0x36;
        h->okey[i] = k[i] ^ 0x5c;
    }
    h->alg = alg;
    h->valid = HMAC_VALID;
    d->init(&h->inner);
    d->update(&h->inner, ipad, d->block);
    memset(k, 0, sizeof k);
    memset(ipad, 0, sizeof ipad);
}

static void hmac_finish(struct hmac_state *h, const struct digest *d, void *mac)
{
    uint8_t inner[64];
    union any_state outer;
    d->final(inner, &h->inner);
    d->init(&outer);
    d->update(&outer, h->okey, d->block);
    d->update(&outer, inner, d->size);
    d->final(mac, &outer);
    memset(h, 0, sizeof *h);
}

static void cc_hmac_init(void *ctx, uint32_t alg, const void *key, size_t keylen)
{
    struct hmac_state h;
    const struct digest *d = hmac_digest(alg);
    memset(&h, 0, sizeof h);
    if (d)
        hmac_start(&h, d, alg, key, keylen);
    memcpy(ctx, &h, sizeof h);
    memset(&h, 0, sizeof h);
}
static void cc_hmac_update(void *ctx, const void *data, size_t len)
{
    struct hmac_state h;
    memcpy(&h, ctx, sizeof h);
    const struct digest *d = h.valid == HMAC_VALID ? hmac_digest(h.alg) : NULL;
    if (d) {
        d->update(&h.inner, data, len);
        memcpy(ctx, &h, sizeof h);
    }
    memset(&h, 0, sizeof h);
}
static void cc_hmac_final(void *ctx, void *mac)
{
    struct hmac_state h;
    memcpy(&h, ctx, sizeof h);
    const struct digest *d = h.valid == HMAC_VALID ? hmac_digest(h.alg) : NULL;
    if (d)
        hmac_finish(&h, d, mac);
    memset(ctx, 0, sizeof h);
    memset(&h, 0, sizeof h);
}
static void cc_hmac(uint32_t alg, const void *key, size_t keylen, const void *data, size_t len, void *mac)
{
    struct hmac_state h;
    const struct digest *d = hmac_digest(alg);
    if (!d)
        return;
    hmac_start(&h, d, alg, key, keylen);
    d->update(&h.inner, data, len);
    hmac_finish(&h, d, mac);
}

/* ---- PBKDF2 (RFC 8018, section 5.2) ------------------------------------------------ */

static const struct digest *prf_digest(uint32_t prf, uint32_t *alg)
{
    static const uint32_t algs[] = {0, kCCHmacAlgSHA1, kCCHmacAlgSHA224, kCCHmacAlgSHA256, kCCHmacAlgSHA384,
                                    kCCHmacAlgSHA512};
    if (prf < kCCPRFHmacAlgSHA1 || prf > kCCPRFHmacAlgSHA512)
        return NULL;
    *alg = algs[prf];
    return hmac_digest(*alg);
}

/* The keyed digest set up once (ipad and opad states), then reused for
 * every round: the same answer as HMAC each time, at half the cost. */
static void pbkdf2(const struct digest *d, uint32_t alg, const void *password, size_t plen, const uint8_t *salt,
                   size_t slen, unsigned rounds, uint8_t *out, size_t outlen)
{
    struct hmac_state base;
    hmac_start(&base, d, alg, password, plen);
    union any_state outer_base;
    d->init(&outer_base);
    d->update(&outer_base, base.okey, d->block);
    for (uint32_t block = 1; outlen; block++) {
        uint8_t u[64], t[64], be[4];
        put_be32(be, block);
        union any_state s = base.inner, o = outer_base;
        d->update(&s, salt, slen);
        d->update(&s, be, 4);
        d->final(u, &s);
        d->update(&o, u, d->size);
        d->final(u, &o);
        memcpy(t, u, d->size);
        for (unsigned r = 1; r < rounds; r++) {
            s = base.inner;
            o = outer_base;
            d->update(&s, u, d->size);
            d->final(u, &s);
            d->update(&o, u, d->size);
            d->final(u, &o);
            for (size_t i = 0; i < d->size; i++)
                t[i] ^= u[i];
        }
        size_t n = outlen < d->size ? outlen : d->size;
        memcpy(out, t, n);
        out += n, outlen -= n;
        memset(u, 0, sizeof u);
        memset(t, 0, sizeof t);
    }
    memset(&base, 0, sizeof base);
    memset(&outer_base, 0, sizeof outer_base);
}

static int cc_key_derivation_pbkdf(uint32_t algorithm, const char *password, size_t plen, const uint8_t *salt,
                                   size_t slen, uint32_t prf, unsigned rounds, uint8_t *derived, size_t dlen)
{
    uint32_t alg;
    const struct digest *d = prf_digest(prf, &alg);
    if (algorithm != kCCPBKDF2 || !d || !rounds || !derived || !dlen || (!password && plen) || (!salt && slen))
        return kCCParamError;
    pbkdf2(d, alg, password ? password : "", plen, salt ? salt : (const uint8_t *)"", slen, rounds, derived, dlen);
    return kCCSuccess;
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* How many rounds take about msec milliseconds here, timed on a short run. */
static unsigned cc_calibrate_pbkdf(uint32_t algorithm, size_t plen, size_t slen, uint32_t prf, size_t dlen,
                                   uint32_t msec)
{
    uint32_t alg;
    const struct digest *d = prf_digest(prf, &alg);
    if (algorithm != kCCPBKDF2 || !d || !dlen || dlen > 1024 || plen > 4096 || slen > 4096)
        return (unsigned)-1;
    char *password = calloc(1, plen + 1);
    uint8_t *salt = calloc(1, slen + 1), *out = malloc(dlen);
    if (!password || !salt || !out) {
        free(password), free(salt), free(out);
        return (unsigned)-1;
    }
    unsigned trial = 1000;
    double took;
    for (;;) {
        double start = now_ms();
        pbkdf2(d, alg, password, plen, salt, slen, trial, out, dlen);
        took = now_ms() - start;
        if (took >= 5 || trial >= (1u << 24))
            break;
        trial *= 4;
    }
    free(password), free(salt), free(out);
    double rounds = took > 0 ? trial * (double)msec / took : (double)trial * msec;
    return rounds < 1 ? 1 : rounds > 4e9 ? 4000000000u : (unsigned)rounds;
}

/* ---- random bytes ------------------------------------------------------------------ */

static int fill_random(void *bytes, size_t count)
{
    uint8_t *p = bytes;
    while (count) {
        ssize_t n = getrandom(p, count, 0);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return kCCRNGFailure;
        }
        p += n, count -= (size_t)n;
    }
    return kCCSuccess;
}
static int cc_random_generate_bytes(void *bytes, size_t count)
{
    if (!bytes && count)
        return kCCParamError;
    return fill_random(bytes, count);
}
/* The older call takes a generator; kCCRandomDefault is the only one. */
static const int random_default_generator = 1;
static const void *const random_default = &random_default_generator;
static int cc_random_copy_bytes(const void *rnd, void *bytes, size_t count)
{
    return cc_random_generate_bytes(bytes, count) == kCCSuccess ? 0 : -1;
}

/* ---- AES through libcrypto ------------------------------------------------------------
 * The calls come from OpenSSL's public API (EVP_CIPHER(3)). Every block
 * mode used here is OpenSSL's with its own padding off; Ferry hands it
 * whole blocks only, and keeps the bytes in between and the padding itself. */

typedef void EVP_CIPHER_CTX;
typedef void EVP_CIPHER;
static struct {
    int loaded, ok;
    EVP_CIPHER_CTX *(*ctx_new)(void);
    void (*ctx_free)(EVP_CIPHER_CTX *);
    int (*init)(EVP_CIPHER_CTX *, const EVP_CIPHER *, void *engine, const unsigned char *key,
                const unsigned char *iv, int enc);
    int (*update)(EVP_CIPHER_CTX *, unsigned char *out, int *outl, const unsigned char *in, int inl);
    int (*set_padding)(EVP_CIPHER_CTX *, int pad);
    const EVP_CIPHER *(*ciphers[3][3])(void); /* [ECB, CBC, CTR][128, 192, 256] */
} E;

static int load_evp_locked(void)
{
    if (E.loaded)
        return E.ok;
    E.loaded = 1;
    static const char *const names[3][3] = {
        {"EVP_aes_128_ecb", "EVP_aes_192_ecb", "EVP_aes_256_ecb"},
        {"EVP_aes_128_cbc", "EVP_aes_192_cbc", "EVP_aes_256_cbc"},
        {"EVP_aes_128_ctr", "EVP_aes_192_ctr", "EVP_aes_256_ctr"},
    };
#define GET(field, name) if (!(*(void **)&E.field = ferry_crypto_symbol(name))) return 0
    GET(ctx_new, "EVP_CIPHER_CTX_new");
    GET(ctx_free, "EVP_CIPHER_CTX_free");
    GET(init, "EVP_CipherInit_ex");
    GET(update, "EVP_CipherUpdate");
    GET(set_padding, "EVP_CIPHER_CTX_set_padding");
    for (int m = 0; m < 3; m++)
        for (int k = 0; k < 3; k++)
            GET(ciphers[m][k], names[m][k]);
#undef GET
    E.ok = 1;
    return 1;
}

/* Loaded once; a thread that asks while another loads waits for it. */
static int load_evp(void)
{
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    int ok = load_evp_locked();
    pthread_mutex_unlock(&lock);
    return ok;
}

struct cryptor {
    uint32_t magic;
    int op, mode, padding;
    EVP_CIPHER_CTX *evp;
    uint8_t buf[16];
    size_t buffered;
};
#define CRYPTOR_MAGIC 0x43437279u

static int key_index(size_t keylen) { return keylen == 16 ? 0 : keylen == 24 ? 1 : keylen == 32 ? 2 : -1; }

static int cryptor_make(uint32_t op, uint32_t mode, uint32_t alg, uint32_t padding, const void *iv, const void *key,
                        size_t keylen, uint32_t mode_options, struct cryptor **out)
{
    if (!out)
        return kCCParamError;
    *out = NULL;
    if (op != kCCEncrypt && op != kCCDecrypt)
        return kCCParamError;
    if (alg != kCCAlgorithmAES)
        return kCCUnimplemented;
    if (mode != kCCModeECB && mode != kCCModeCBC && mode != kCCModeCTR)
        return kCCUnimplemented;
    if (mode == kCCModeCTR && (mode_options & kCCModeOptionCTR_LE))
        return kCCUnimplemented;
    if (padding != ccNoPadding && padding != ccPKCS7Padding)
        return kCCParamError;
    int k = key_index(keylen);
    if (k < 0)
        return kCCKeySizeError;
    if (!key)
        return kCCParamError;
    if (!load_evp())
        return kCCUnimplemented;
    struct cryptor *c = calloc(1, sizeof *c);
    if (!c || !(c->evp = E.ctx_new())) {
        free(c);
        return kCCMemoryFailure;
    }
    static const uint8_t zero_iv[16];
    int m = mode == kCCModeECB ? 0 : mode == kCCModeCBC ? 1 : 2;
    /* a counter runs forwards whichever way the data goes */
    int enc = mode == kCCModeCTR ? 1 : op == kCCEncrypt;
    if (!E.init(c->evp, E.ciphers[m][k](), NULL, key, mode == kCCModeECB ? NULL : iv ? iv : zero_iv, enc)) {
        E.ctx_free(c->evp);
        free(c);
        return kCCParamError;
    }
    E.set_padding(c->evp, 0);
    c->magic = CRYPTOR_MAGIC;
    c->op = (int)op;
    c->mode = (int)mode;
    c->padding = mode == kCCModeCTR ? ccNoPadding : (int)padding;
    *out = c;
    return kCCSuccess;
}

static struct cryptor *cryptor_of(void *ref)
{
    struct cryptor *c = ref;
    return c && c->magic == CRYPTOR_MAGIC ? c : NULL;
}

/* Whole blocks through OpenSSL. */
static int run_blocks(struct cryptor *c, const uint8_t *in, size_t len, uint8_t *out)
{
    while (len) {
        int n = len > (1u << 30) ? 1 << 30 : (int)len, got = 0;
        if (!E.update(c->evp, out, &got, in, n) || got != n)
            return kCCUnspecifiedError;
        in += n, out += n, len -= (size_t)n;
    }
    return kCCSuccess;
}

/* An upper bound of what an update (or, with final, an update and the
 * final step) of len more bytes writes, as CCCryptorGetOutputLength
 * documents. Decrypting with padding holds the last whole block back
 * until the final step, which takes the padding off. */
static size_t output_length(const struct cryptor *c, size_t len, int final)
{
    if (c->mode == kCCModeCTR)
        return len;
    size_t total = c->buffered + len;
    if (c->op == kCCEncrypt)
        return final ? (c->padding ? (total / 16 + 1) * 16 : total) : total - total % 16;
    if (final)
        return total;
    if (c->padding && total && total % 16 == 0)
        return total - 16;
    return total - total % 16;
}

static int cryptor_update(struct cryptor *c, const void *in, size_t len, void *out, size_t avail, size_t *moved)
{
    size_t need = output_length(c, len, 0);
    if (moved)
        *moved = 0;
    if (len && (!in || (need && !out)))
        return kCCParamError;
    if (avail < need) {
        if (moved)
            *moved = need;
        return kCCBufferTooSmall;
    }
    if (c->mode == kCCModeCTR) {
        int rc = len ? run_blocks(c, in, len, out) : kCCSuccess;
        if (moved && rc == kCCSuccess)
            *moved = len;
        return rc;
    }
    const uint8_t *p = in;
    uint8_t *o = out, *copy = NULL;
    size_t left = len, done = 0;
    /* in place, or overlapping: the waiting bytes come out first, so work from a copy */
    if (c->buffered && need && o < p + len && p < o + need) {
        if (!(copy = malloc(len)))
            return kCCMemoryFailure;
        memcpy(copy, p, len);
        p = copy;
    }
    int rc = kCCSuccess;
    if (c->buffered && need) {
        size_t take = 16 - c->buffered;
        memcpy(c->buf + c->buffered, p, take);
        p += take, left -= take;
        rc = run_blocks(c, c->buf, 16, o);
        done = 16;
        c->buffered = 0;
    }
    if (rc == kCCSuccess && need > done) {
        rc = run_blocks(c, p, need - done, o + done);
        p += need - done, left -= need - done;
        done = need;
    }
    if (rc == kCCSuccess) {
        memcpy(c->buf + c->buffered, p, left);
        c->buffered += left;
        if (moved)
            *moved = done;
    }
    free(copy);
    return rc;
}

static int cryptor_final(struct cryptor *c, void *out, size_t avail, size_t *moved)
{
    if (moved)
        *moved = 0;
    if (c->mode == kCCModeCTR)
        return kCCSuccess;
    if (!c->padding)
        return c->buffered ? kCCAlignmentError : kCCSuccess;
    size_t need = output_length(c, 0, 1);
    if (avail < need) {
        if (moved)
            *moved = need;
        return kCCBufferTooSmall;
    }
    if (!out)
        return kCCParamError;
    uint8_t block[16];
    if (c->op == kCCEncrypt) {
        uint8_t pad = (uint8_t)(16 - c->buffered);
        memset(c->buf + c->buffered, pad, pad);
        c->buffered = 0;
        int rc = run_blocks(c, c->buf, 16, block);
        if (rc == kCCSuccess) {
            memcpy(out, block, 16);
            if (moved)
                *moved = 16;
        }
        return rc;
    }
    if (c->buffered != 16)
        return c->buffered ? kCCAlignmentError : kCCDecodeError;
    c->buffered = 0;
    int rc = run_blocks(c, c->buf, 16, block);
    if (rc != kCCSuccess)
        return rc;
    uint8_t pad = block[15];
    int bad = pad == 0 || pad > 16;
    for (int i = bad ? 16 : 16 - pad; i < 16; i++)
        bad |= block[i] != pad;
    if (bad) {
        memset(block, 0, sizeof block);
        return kCCDecodeError;
    }
    memcpy(out, block, 16 - pad);
    if (moved)
        *moved = 16u - pad;
    memset(block, 0, sizeof block);
    return kCCSuccess;
}

static void cryptor_free(struct cryptor *c)
{
    if (!c)
        return;
    E.ctx_free(c->evp);
    memset(c, 0, sizeof *c);
    free(c);
}

static int cc_cryptor_create_with_mode(uint32_t op, uint32_t mode, uint32_t alg, uint32_t padding, const void *iv,
                                       const void *key, size_t keylen, const void *tweak, size_t tweaklen,
                                       int rounds, uint32_t options, void **ref)
{
    return cryptor_make(op, mode, alg, padding, iv, key, keylen, options, (struct cryptor **)ref);
}

static int cc_cryptor_create(uint32_t op, uint32_t alg, uint32_t options, const void *key, size_t keylen,
                             const void *iv, void **ref)
{
    if (options & ~(uint32_t)(kCCOptionPKCS7Padding | kCCOptionECBMode))
        return kCCParamError;
    return cryptor_make(op, (options & kCCOptionECBMode) ? kCCModeECB : kCCModeCBC, alg,
                        (options & kCCOptionPKCS7Padding) ? ccPKCS7Padding : ccNoPadding, iv, key, keylen, 0,
                        (struct cryptor **)ref);
}

static int cc_cryptor_release(void *ref)
{
    struct cryptor *c = cryptor_of(ref);
    if (!c)
        return kCCParamError;
    cryptor_free(c);
    return kCCSuccess;
}

static int cc_cryptor_update(void *ref, const void *in, size_t len, void *out, size_t avail, size_t *moved)
{
    struct cryptor *c = cryptor_of(ref);
    return c ? cryptor_update(c, in, len, out, avail, moved) : kCCParamError;
}

static int cc_cryptor_final(void *ref, void *out, size_t avail, size_t *moved)
{
    struct cryptor *c = cryptor_of(ref);
    return c ? cryptor_final(c, out, avail, moved) : kCCParamError;
}

static size_t cc_cryptor_get_output_length(void *ref, size_t len, _Bool final)
{
    struct cryptor *c = cryptor_of(ref);
    return c ? output_length(c, len, final) : 0;
}

static int cc_cryptor_reset(void *ref, const void *iv)
{
    static const uint8_t zero_iv[16];
    struct cryptor *c = cryptor_of(ref);
    if (!c)
        return kCCParamError;
    c->buffered = 0;
    memset(c->buf, 0, sizeof c->buf);
    if (c->mode != kCCModeECB && !E.init(c->evp, NULL, NULL, NULL, iv ? iv : zero_iv, -1))
        return kCCUnspecifiedError;
    return kCCSuccess;
}

static int cc_crypt(uint32_t op, uint32_t alg, uint32_t options, const void *key, size_t keylen, const void *iv,
                    const void *in, size_t len, void *out, size_t avail, size_t *moved)
{
    struct cryptor *c;
    if (moved)
        *moved = 0;
    int rc = cc_cryptor_create(op, alg, options, key, keylen, iv, (void **)&c);
    if (rc != kCCSuccess)
        return rc;
    if (!c->padding && len % 16) {
        cryptor_free(c);
        return kCCAlignmentError;
    }
    size_t need = output_length(c, len, 1);
    if (avail < need) {
        cryptor_free(c);
        if (moved)
            *moved = need;
        return kCCBufferTooSmall;
    }
    size_t first = 0, last = 0;
    rc = cryptor_update(c, in, len, out, avail, &first);
    if (rc == kCCSuccess)
        rc = cryptor_final(c, (uint8_t *)out + first, avail - first, &last);
    cryptor_free(c);
    if (moved)
        *moved = rc == kCCSuccess ? first + last : 0;
    return rc;
}

/* ---- the table ------------------------------------------------------------------- */

const struct ferry_symbol ferry_commoncrypto_symbols[] = {
    {"CC_MD5", cc_md5},
    {"CC_MD5_Init", cc_md5_init},
    {"CC_MD5_Update", cc_md5_update},
    {"CC_MD5_Final", cc_md5_final},
    {"CC_SHA1", cc_sha1},
    {"CC_SHA1_Init", cc_sha1_init},
    {"CC_SHA1_Update", cc_sha1_update},
    {"CC_SHA1_Final", cc_sha1_final},
    {"CC_SHA224", cc_sha224},
    {"CC_SHA224_Init", cc_sha224_init},
    {"CC_SHA224_Update", cc_sha256_update},
    {"CC_SHA224_Final", cc_sha224_final},
    {"CC_SHA256", cc_sha256},
    {"CC_SHA256_Init", cc_sha256_init},
    {"CC_SHA256_Update", cc_sha256_update},
    {"CC_SHA256_Final", cc_sha256_final},
    {"CC_SHA384", cc_sha384},
    {"CC_SHA384_Init", cc_sha384_init},
    {"CC_SHA384_Update", cc_sha512_update},
    {"CC_SHA384_Final", cc_sha384_final},
    {"CC_SHA512", cc_sha512},
    {"CC_SHA512_Init", cc_sha512_init},
    {"CC_SHA512_Update", cc_sha512_update},
    {"CC_SHA512_Final", cc_sha512_final},
    {"CCHmac", cc_hmac},
    {"CCHmacInit", cc_hmac_init},
    {"CCHmacUpdate", cc_hmac_update},
    {"CCHmacFinal", cc_hmac_final},
    {"CCKeyDerivationPBKDF", cc_key_derivation_pbkdf},
    {"CCCalibratePBKDF", cc_calibrate_pbkdf},
    {"CCRandomGenerateBytes", cc_random_generate_bytes},
    {"CCRandomCopyBytes", cc_random_copy_bytes},
    {"kCCRandomDefault", (void *)&random_default},
    {"CCCrypt", cc_crypt},
    {"CCCryptorCreate", cc_cryptor_create},
    {"CCCryptorCreateWithMode", cc_cryptor_create_with_mode},
    {"CCCryptorUpdate", cc_cryptor_update},
    {"CCCryptorFinal", cc_cryptor_final},
    {"CCCryptorGetOutputLength", cc_cryptor_get_output_length},
    {"CCCryptorReset", cc_cryptor_reset},
    {"CCCryptorRelease", cc_cryptor_release},
    {NULL, NULL},
};
