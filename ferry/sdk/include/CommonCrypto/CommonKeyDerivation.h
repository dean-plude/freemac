/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's password-based key derivation (PBKDF2,
 * RFC 8018). Written for freemac from Apple's public documentation; not
 * Apple's header. Implemented in ferry/src/commoncrypto.c. */
#ifndef _FERRY_COMMONKEYDERIVATION_H_
#define _FERRY_COMMONKEYDERIVATION_H_
#include <_ferry.h>
#include <CommonCrypto/CommonCryptoError.h>

__FERRY_BEGIN

enum { kCCPBKDF2 = 2 };
typedef uint32_t CCPBKDFAlgorithm;

enum {
    kCCPRFHmacAlgSHA1 = 1,
    kCCPRFHmacAlgSHA224 = 2,
    kCCPRFHmacAlgSHA256 = 3,
    kCCPRFHmacAlgSHA384 = 4,
    kCCPRFHmacAlgSHA512 = 5,
};
typedef uint32_t CCPseudoRandomAlgorithm;

/* kCCSuccess, or kCCParamError for an unknown algorithm or no rounds. */
int CCKeyDerivationPBKDF(CCPBKDFAlgorithm algorithm, const char *password, size_t passwordLen, const uint8_t *salt,
                         size_t saltLen, CCPseudoRandomAlgorithm prf, unsigned rounds, uint8_t *derivedKey,
                         size_t derivedKeyLen);
/* The number of rounds that take about msec milliseconds on this computer. */
unsigned CCCalibratePBKDF(CCPBKDFAlgorithm algorithm, size_t passwordLen, size_t saltLen,
                          CCPseudoRandomAlgorithm prf, size_t derivedKeyLen, uint32_t msec);

__FERRY_END
#endif
