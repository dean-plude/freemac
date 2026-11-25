/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Foundation's byte order functions, as Apple's documentation of
 * NSByteOrder.h describes them (freemac 1.221, Ferry 0.45.0). Ferry runs
 * Intel programs, so the host is little-endian. */
#ifndef _FERRY_FOUNDATION_NSBYTEORDER_H_
#define _FERRY_FOUNDATION_NSBYTEORDER_H_
#include <stdint.h>

enum { NS_UnknownByteOrder = 0, NS_LittleEndian = 1, NS_BigEndian = 2 };
typedef struct { unsigned int v; } NSSwappedFloat;
typedef struct { unsigned long long v; } NSSwappedDouble;

static inline long NSHostByteOrder(void) { return NS_LittleEndian; }

static inline unsigned short NSSwapShort(unsigned short x) { return __builtin_bswap16(x); }
static inline unsigned int NSSwapInt(unsigned int x) { return __builtin_bswap32(x); }
static inline unsigned long NSSwapLong(unsigned long x) { return __builtin_bswap64(x); }
static inline unsigned long long NSSwapLongLong(unsigned long long x) { return __builtin_bswap64(x); }

static inline unsigned short NSSwapBigShortToHost(unsigned short x) { return NSSwapShort(x); }
static inline unsigned int NSSwapBigIntToHost(unsigned int x) { return NSSwapInt(x); }
static inline unsigned long NSSwapBigLongToHost(unsigned long x) { return NSSwapLong(x); }
static inline unsigned long long NSSwapBigLongLongToHost(unsigned long long x) { return NSSwapLongLong(x); }
static inline unsigned short NSSwapHostShortToBig(unsigned short x) { return NSSwapShort(x); }
static inline unsigned int NSSwapHostIntToBig(unsigned int x) { return NSSwapInt(x); }
static inline unsigned long NSSwapHostLongToBig(unsigned long x) { return NSSwapLong(x); }
static inline unsigned long long NSSwapHostLongLongToBig(unsigned long long x) { return NSSwapLongLong(x); }

static inline unsigned short NSSwapLittleShortToHost(unsigned short x) { return x; }
static inline unsigned int NSSwapLittleIntToHost(unsigned int x) { return x; }
static inline unsigned long NSSwapLittleLongToHost(unsigned long x) { return x; }
static inline unsigned long long NSSwapLittleLongLongToHost(unsigned long long x) { return x; }
static inline unsigned short NSSwapHostShortToLittle(unsigned short x) { return x; }
static inline unsigned int NSSwapHostIntToLittle(unsigned int x) { return x; }
static inline unsigned long NSSwapHostLongToLittle(unsigned long x) { return x; }
static inline unsigned long long NSSwapHostLongLongToLittle(unsigned long long x) { return x; }

static inline NSSwappedFloat NSConvertHostFloatToSwapped(float x)
{
    NSSwappedFloat s;
    __builtin_memcpy(&s.v, &x, sizeof x);
    return s;
}
static inline float NSConvertSwappedFloatToHost(NSSwappedFloat x)
{
    float f;
    __builtin_memcpy(&f, &x.v, sizeof f);
    return f;
}
static inline NSSwappedDouble NSConvertHostDoubleToSwapped(double x)
{
    NSSwappedDouble s;
    __builtin_memcpy(&s.v, &x, sizeof x);
    return s;
}
static inline double NSConvertSwappedDoubleToHost(NSSwappedDouble x)
{
    double d;
    __builtin_memcpy(&d, &x.v, sizeof d);
    return d;
}
static inline NSSwappedFloat NSSwapFloat(NSSwappedFloat x) { x.v = NSSwapInt(x.v); return x; }
static inline NSSwappedDouble NSSwapDouble(NSSwappedDouble x) { x.v = NSSwapLongLong(x.v); return x; }
static inline float NSSwapBigFloatToHost(NSSwappedFloat x) { return NSConvertSwappedFloatToHost(NSSwapFloat(x)); }
static inline double NSSwapBigDoubleToHost(NSSwappedDouble x) { return NSConvertSwappedDoubleToHost(NSSwapDouble(x)); }
static inline NSSwappedFloat NSSwapHostFloatToBig(float x) { return NSSwapFloat(NSConvertHostFloatToSwapped(x)); }
static inline NSSwappedDouble NSSwapHostDoubleToBig(double x) { return NSSwapDouble(NSConvertHostDoubleToSwapped(x)); }
static inline float NSSwapLittleFloatToHost(NSSwappedFloat x) { return NSConvertSwappedFloatToHost(x); }
static inline double NSSwapLittleDoubleToHost(NSSwappedDouble x) { return NSConvertSwappedDoubleToHost(x); }
static inline NSSwappedFloat NSSwapHostFloatToLittle(float x) { return NSConvertHostFloatToSwapped(x); }
static inline NSSwappedDouble NSSwapHostDoubleToLittle(double x) { return NSConvertHostDoubleToSwapped(x); }
#endif
