/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSDecimal and its C functions (foundation/NSDecimalNumber.m,
 * freemac 1.NEXT, Ferry 0.NEXT). Written for freemac from Apple's public
 * API documentation; not Apple's header.
 *
 * A decimal is a mantissa of up to 128 bits (eight 16-bit words, the
 * lowest word first, _length of them in use), a power of ten from -128
 * to 127 and a sign. The arithmetic is exact in base 10 and keeps up to
 * 38 digits (39 when they fit in 128 bits), rounding the rest away as the
 * rounding mode says. A decimal with no words in use and the sign set is
 * "not a number". */
#ifndef _FERRY_FOUNDATION_NSDECIMAL_H_
#define _FERRY_FOUNDATION_NSDECIMAL_H_
#include <Foundation/Foundation.h>
#include <limits.h>

#define NSDecimalMaxSize 8
#define NSDecimalNoScale SHRT_MAX

typedef struct {
    signed int _exponent : 8;
    unsigned int _length : 4;
    unsigned int _isNegative : 1;
    unsigned int _isCompact : 1;
    unsigned int _reserved : 18;
    unsigned short _mantissa[NSDecimalMaxSize];
} NSDecimal;

typedef NS_ENUM(NSUInteger, NSRoundingMode) {
    NSRoundPlain,
    NSRoundDown,
    NSRoundUp,
    NSRoundBankers,
};

typedef NS_ENUM(NSUInteger, NSCalculationError) {
    NSCalculationNoError = 0,
    NSCalculationLossOfPrecision,
    NSCalculationUnderflow,
    NSCalculationOverflow,
    NSCalculationDivideByZero,
};

FOUNDATION_EXPORT BOOL NSDecimalIsNotANumber(const NSDecimal *dcm);
FOUNDATION_EXPORT void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source);
FOUNDATION_EXPORT void NSDecimalCompact(NSDecimal *number);
FOUNDATION_EXPORT NSComparisonResult NSDecimalCompare(const NSDecimal *leftOperand, const NSDecimal *rightOperand);
FOUNDATION_EXPORT void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale,
                                      NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2,
                                                        NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *leftOperand,
                                                  const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *leftOperand,
                                                       const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *leftOperand,
                                                       const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *leftOperand,
                                                     const NSDecimal *rightOperand, NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, NSUInteger power,
                                                    NSRoundingMode roundingMode);
FOUNDATION_EXPORT NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number,
                                                                  short power, NSRoundingMode roundingMode);
/* The number in plain notation (no exponent), with the locale's decimal
 * separator (an NSLocale, or a dictionary with NSLocaleDecimalSeparator). */
FOUNDATION_EXPORT NSString *NSDecimalString(const NSDecimal *dcm, id locale);

#endif
