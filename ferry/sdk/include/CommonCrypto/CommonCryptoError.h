/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CommonCrypto's status codes. Written for freemac from Apple's
 * public documentation; not Apple's header. */
#ifndef _FERRY_COMMONCRYPTOERROR_H_
#define _FERRY_COMMONCRYPTOERROR_H_
#include <_ferry.h>

typedef int32_t CCStatus;
typedef int32_t CCCryptorStatus;

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError = -4304,
    kCCUnimplemented = -4305,
    kCCOverflow = -4306,
    kCCRNGFailure = -4307,
    kCCUnspecifiedError = -4308,
    kCCCallSequenceError = -4309,
    kCCKeySizeError = -4310,
    kCCInvalidKey = -4311,
};

#endif
