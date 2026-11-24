/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's random bytes, from this system's kernel
 * (getrandom). Written for freemac from Apple's public documentation; not
 * Apple's header. Implemented in ferry/src/commoncrypto.c. */
#ifndef _FERRY_COMMONRANDOM_H_
#define _FERRY_COMMONRANDOM_H_
#include <_ferry.h>
#include <CommonCrypto/CommonCryptoError.h>

__FERRY_BEGIN

typedef CCCryptorStatus CCRNGStatus;
CCRNGStatus CCRandomGenerateBytes(void *bytes, size_t count);

/* The older form: kCCRandomDefault is the only generator; 0 means success. */
typedef struct __CCRandom *CCRandomRef;
extern const CCRandomRef kCCRandomDefault;
int CCRandomCopyBytes(CCRandomRef rnd, void *bytes, size_t count);

__FERRY_END
#endif
