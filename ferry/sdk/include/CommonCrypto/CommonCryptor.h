/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's symmetric encryption. Written for freemac from
 * Apple's public documentation (CCCryptor(3cc), CCCrypt(3cc)); not Apple's
 * header. Implemented in ferry/src/commoncrypto.c: AES-128, AES-192 and
 * AES-256 in ECB and CBC mode, with or without PKCS #7 padding, and in CTR
 * mode (a big-endian counter). The other algorithms and modes are declared
 * so programs compile; asking for them answers kCCUnimplemented. */
#ifndef _FERRY_COMMONCRYPTOR_H_
#define _FERRY_COMMONCRYPTOR_H_
#include <_ferry.h>
#include <stdbool.h>
#include <CommonCrypto/CommonCryptoError.h>

__FERRY_BEGIN

typedef struct _CCCryptor *CCCryptorRef;

enum { kCCEncrypt = 0, kCCDecrypt };
typedef uint32_t CCOperation;

enum {
    kCCAlgorithmAES128 = 0,
    kCCAlgorithmAES = 0,
    kCCAlgorithmDES,
    kCCAlgorithm3DES,
    kCCAlgorithmCAST,
    kCCAlgorithmRC4,
    kCCAlgorithmRC2,
    kCCAlgorithmBlowfish,
};
typedef uint32_t CCAlgorithm;

enum {
    kCCOptionPKCS7Padding = 0x0001,
    kCCOptionECBMode = 0x0002,
};
typedef uint32_t CCOptions;

enum {
    kCCKeySizeAES128 = 16,
    kCCKeySizeAES192 = 24,
    kCCKeySizeAES256 = 32,
    kCCKeySizeDES = 8,
    kCCKeySize3DES = 24,
    kCCKeySizeMinCAST = 5,
    kCCKeySizeMaxCAST = 16,
    kCCKeySizeMinRC4 = 1,
    kCCKeySizeMaxRC4 = 512,
    kCCKeySizeMinRC2 = 1,
    kCCKeySizeMaxRC2 = 128,
    kCCKeySizeMinBlowfish = 8,
    kCCKeySizeMaxBlowfish = 56,
};

enum {
    kCCBlockSizeAES128 = 16,
    kCCBlockSizeDES = 8,
    kCCBlockSize3DES = 8,
    kCCBlockSizeCAST = 8,
    kCCBlockSizeRC2 = 8,
    kCCBlockSizeBlowfish = 8,
};

enum {
    kCCModeECB = 1,
    kCCModeCBC = 2,
    kCCModeCFB = 3,
    kCCModeCTR = 4,
    kCCModeOFB = 7,
    kCCModeXTS = 8,
    kCCModeRC4 = 9,
    kCCModeCFB8 = 10,
};
typedef uint32_t CCMode;

enum {
    ccNoPadding = 0,
    ccPKCS7Padding = 1,
};
typedef uint32_t CCPadding;

enum {
    kCCModeOptionCTR_LE = 0x0001,
    kCCModeOptionCTR_BE = 0x0002,
};
typedef uint32_t CCModeOptions;

CCCryptorStatus CCCryptorCreate(CCOperation op, CCAlgorithm alg, CCOptions options, const void *key, size_t keyLength,
                                const void *iv, CCCryptorRef *cryptorRef);
CCCryptorStatus CCCryptorCreateWithMode(CCOperation op, CCMode mode, CCAlgorithm alg, CCPadding padding,
                                        const void *iv, const void *key, size_t keyLength, const void *tweak,
                                        size_t tweakLength, int numRounds, CCModeOptions options,
                                        CCCryptorRef *cryptorRef);
CCCryptorStatus CCCryptorRelease(CCCryptorRef cryptorRef);
CCCryptorStatus CCCryptorUpdate(CCCryptorRef cryptorRef, const void *dataIn, size_t dataInLength, void *dataOut,
                                size_t dataOutAvailable, size_t *dataOutMoved);
CCCryptorStatus CCCryptorFinal(CCCryptorRef cryptorRef, void *dataOut, size_t dataOutAvailable,
                               size_t *dataOutMoved);
size_t CCCryptorGetOutputLength(CCCryptorRef cryptorRef, size_t inputLength, bool final);
CCCryptorStatus CCCryptorReset(CCCryptorRef cryptorRef, const void *iv);
CCCryptorStatus CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions options, const void *key, size_t keyLength,
                        const void *iv, const void *dataIn, size_t dataInLength, void *dataOut,
                        size_t dataOutAvailable, size_t *dataOutMoved);

__FERRY_END
#endif
