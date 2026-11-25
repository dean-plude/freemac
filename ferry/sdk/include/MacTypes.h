/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The Mac's basic types (freemac 1.227), as the Carbon Core reference
 * describes them, for Swift's Darwin overlay; the framework headers that
 * need some of them declare the same ones themselves. */
#ifndef _FERRY_MACTYPES_H_
#define _FERRY_MACTYPES_H_
#include <stdint.h>
/* nil, as a Mac's MacTypes.h gives it to C and C++ too: the same null as
 * <objc/objc.h>'s (freemac 1.232) */
#ifndef nil
#ifdef __cplusplus
#define nil __null
#else
#define nil ((void *)0)
#endif
#endif
typedef uint8_t UInt8;
typedef int8_t SInt8;
typedef uint16_t UInt16;
typedef int16_t SInt16;
typedef uint32_t UInt32;
typedef int32_t SInt32;
typedef uint64_t UInt64;
typedef int64_t SInt64;
typedef float Float32;
typedef double Float64;
typedef uint8_t Byte;
typedef int8_t SignedByte;
typedef unsigned char Boolean;
typedef int16_t OSErr;
typedef int32_t OSStatus;
typedef uint32_t FourCharCode;
typedef uint32_t OSType;
typedef uint32_t ResType;
/* no error, as every Carbon-era call and Core Audio answers (freemac 1.234) */
enum { noErr = 0 };
typedef uint16_t UniChar;
typedef uint8_t UTF8Char;
typedef uint16_t UTF16Char;
typedef uint32_t UTF32Char;
/* counts and sizes, which Swift sees as Int (freemac 1.230) */
typedef unsigned long ItemCount;
typedef unsigned long ByteCount;
#endif
