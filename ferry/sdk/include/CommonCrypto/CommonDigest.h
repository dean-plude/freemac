/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's digests (MD2, MD4, MD5, SHA-1 and SHA-2), part
 * of libSystem. Written for freemac from Apple's public documentation of the
 * calls and from RFCs 1319, 1320 and 1321 and FIPS 180-4; not Apple's header. The context
 * structures have the documented sizes; what is inside them is private.
 * Implemented in ferry/src/commoncrypto.c. */
#ifndef _FERRY_COMMONDIGEST_H_
#define _FERRY_COMMONDIGEST_H_
#include <_ferry.h>

__FERRY_BEGIN

typedef uint32_t CC_LONG;
typedef uint64_t CC_LONG64;

#define CC_MD2_DIGEST_LENGTH 16
#define CC_MD2_BLOCK_BYTES 64
#define CC_MD2_BLOCK_LONG (CC_MD2_BLOCK_BYTES / sizeof(CC_LONG))
typedef struct CC_MD2state_st {
    int num;
    unsigned char data[CC_MD2_DIGEST_LENGTH];
    CC_LONG cksm[CC_MD2_BLOCK_LONG];
    CC_LONG state[CC_MD2_BLOCK_LONG];
} CC_MD2_CTX;

#define CC_MD4_DIGEST_LENGTH 16
#define CC_MD4_BLOCK_BYTES 64
#define CC_MD4_BLOCK_LONG (CC_MD4_BLOCK_BYTES / sizeof(CC_LONG))
typedef struct CC_MD4state_st {
    CC_LONG A, B, C, D;
    CC_LONG Nl, Nh;
    CC_LONG data[CC_MD4_BLOCK_LONG];
    unsigned int num;
} CC_MD4_CTX;

#define CC_MD5_DIGEST_LENGTH 16
#define CC_MD5_BLOCK_BYTES 64
#define CC_MD5_BLOCK_LONG (CC_MD5_BLOCK_BYTES / sizeof(CC_LONG))
typedef struct CC_MD5state_st {
    CC_LONG A, B, C, D;
    CC_LONG Nl, Nh;
    CC_LONG data[CC_MD5_BLOCK_LONG];
    int num;
} CC_MD5_CTX;

#define CC_SHA1_DIGEST_LENGTH 20
#define CC_SHA1_BLOCK_BYTES 64
#define CC_SHA1_BLOCK_LONG (CC_SHA1_BLOCK_BYTES / sizeof(CC_LONG))
typedef struct CC_SHA1state_st {
    CC_LONG h0, h1, h2, h3, h4;
    CC_LONG Nl, Nh;
    CC_LONG data[CC_SHA1_BLOCK_LONG];
    int num;
} CC_SHA1_CTX;

#define CC_SHA224_DIGEST_LENGTH 28
#define CC_SHA224_BLOCK_BYTES 64
#define CC_SHA256_DIGEST_LENGTH 32
#define CC_SHA256_BLOCK_BYTES 64
#define CC_SHA256_BLOCK_LONG (CC_SHA256_BLOCK_BYTES / sizeof(CC_LONG))
typedef struct CC_SHA256state_st {
    CC_LONG count[2];
    CC_LONG hash[8];
    CC_LONG wbuf[16];
} CC_SHA256_CTX;
typedef CC_SHA256_CTX CC_SHA224_CTX;

#define CC_SHA384_DIGEST_LENGTH 48
#define CC_SHA384_BLOCK_BYTES 128
#define CC_SHA512_DIGEST_LENGTH 64
#define CC_SHA512_BLOCK_BYTES 128
#define CC_SHA512_BLOCK_LONG (CC_SHA512_BLOCK_BYTES / sizeof(CC_LONG64))
typedef struct CC_SHA512state_st {
    CC_LONG64 count[2];
    CC_LONG64 hash[8];
    CC_LONG64 wbuf[16];
} CC_SHA512_CTX;
typedef CC_SHA512_CTX CC_SHA384_CTX;

/* Each _Init, _Update and _Final returns 1. The one-shot calls return md. */
int CC_MD2_Init(CC_MD2_CTX *c);
int CC_MD2_Update(CC_MD2_CTX *c, const void *data, CC_LONG len);
int CC_MD2_Final(unsigned char *md, CC_MD2_CTX *c);
unsigned char *CC_MD2(const void *data, CC_LONG len, unsigned char *md);

int CC_MD4_Init(CC_MD4_CTX *c);
int CC_MD4_Update(CC_MD4_CTX *c, const void *data, CC_LONG len);
int CC_MD4_Final(unsigned char *md, CC_MD4_CTX *c);
unsigned char *CC_MD4(const void *data, CC_LONG len, unsigned char *md);

int CC_MD5_Init(CC_MD5_CTX *c);
int CC_MD5_Update(CC_MD5_CTX *c, const void *data, CC_LONG len);
int CC_MD5_Final(unsigned char *md, CC_MD5_CTX *c);
unsigned char *CC_MD5(const void *data, CC_LONG len, unsigned char *md);

int CC_SHA1_Init(CC_SHA1_CTX *c);
int CC_SHA1_Update(CC_SHA1_CTX *c, const void *data, CC_LONG len);
int CC_SHA1_Final(unsigned char *md, CC_SHA1_CTX *c);
unsigned char *CC_SHA1(const void *data, CC_LONG len, unsigned char *md);

int CC_SHA224_Init(CC_SHA256_CTX *c);
int CC_SHA224_Update(CC_SHA256_CTX *c, const void *data, CC_LONG len);
int CC_SHA224_Final(unsigned char *md, CC_SHA256_CTX *c);
unsigned char *CC_SHA224(const void *data, CC_LONG len, unsigned char *md);

int CC_SHA256_Init(CC_SHA256_CTX *c);
int CC_SHA256_Update(CC_SHA256_CTX *c, const void *data, CC_LONG len);
int CC_SHA256_Final(unsigned char *md, CC_SHA256_CTX *c);
unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md);

int CC_SHA384_Init(CC_SHA512_CTX *c);
int CC_SHA384_Update(CC_SHA512_CTX *c, const void *data, CC_LONG len);
int CC_SHA384_Final(unsigned char *md, CC_SHA512_CTX *c);
unsigned char *CC_SHA384(const void *data, CC_LONG len, unsigned char *md);

int CC_SHA512_Init(CC_SHA512_CTX *c);
int CC_SHA512_Update(CC_SHA512_CTX *c, const void *data, CC_LONG len);
int CC_SHA512_Final(unsigned char *md, CC_SHA512_CTX *c);
unsigned char *CC_SHA512(const void *data, CC_LONG len, unsigned char *md);

__FERRY_END
#endif
