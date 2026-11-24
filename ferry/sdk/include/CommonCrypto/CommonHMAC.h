/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's keyed-hash message authentication codes
 * (HMAC, RFC 2104). Written for freemac from Apple's public documentation;
 * not Apple's header. Implemented in ferry/src/commoncrypto.c. */
#ifndef _FERRY_COMMONHMAC_H_
#define _FERRY_COMMONHMAC_H_
#include <CommonCrypto/CommonDigest.h>

__FERRY_BEGIN

enum {
    kCCHmacAlgSHA1,
    kCCHmacAlgMD5,
    kCCHmacAlgSHA256,
    kCCHmacAlgSHA384,
    kCCHmacAlgSHA512,
    kCCHmacAlgSHA224,
};
typedef uint32_t CCHmacAlgorithm;

#define CC_HMAC_CONTEXT_SIZE 96
typedef struct {
    uint32_t ctx[CC_HMAC_CONTEXT_SIZE];
} CCHmacContext;

void CCHmacInit(CCHmacContext *ctx, CCHmacAlgorithm algorithm, const void *key, size_t keyLength);
void CCHmacUpdate(CCHmacContext *ctx, const void *data, size_t dataLength);
void CCHmacFinal(CCHmacContext *ctx, void *macOut);
void CCHmac(CCHmacAlgorithm algorithm, const void *key, size_t keyLength, const void *data, size_t dataLength,
            void *macOut);

__FERRY_END
#endif
