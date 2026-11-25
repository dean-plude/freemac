/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSDecimalNumber and NSDecimalNumberHandler
 * (foundation/NSDecimalNumber.m, freemac 1.211, Ferry 0.37.0). Written for
 * freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSDECIMALNUMBER_H_
#define _FERRY_FOUNDATION_NSDECIMALNUMBER_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSDecimal.h>
#include <Foundation/NSScanner.h>

FOUNDATION_EXPORT NSString *const NSDecimalNumberExactnessException;
FOUNDATION_EXPORT NSString *const NSDecimalNumberOverflowException;
FOUNDATION_EXPORT NSString *const NSDecimalNumberUnderflowException;
FOUNDATION_EXPORT NSString *const NSDecimalNumberDivideByZeroException;

@class NSDecimalNumber;

@protocol NSDecimalNumberBehaviors
- (NSRoundingMode)roundingMode;
- (short)scale;
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation
                                        error:(NSCalculationError)error
                                  leftOperand:(NSDecimalNumber *)leftOperand
                                 rightOperand:(NSDecimalNumber *)rightOperand;
@end

@interface NSDecimalNumber : NSNumber <NSSecureCoding>
- (instancetype FERRY_SWIFT_NONNULL)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag;
- (instancetype FERRY_SWIFT_NONNULL)initWithDecimal:(NSDecimal)dcm;
- (instancetype)initWithString:(NSString *)numberValue;
- (instancetype)initWithString:(NSString *)numberValue locale:(id)locale;
+ (NSDecimalNumber *)decimalNumberWithMantissa:(unsigned long long)mantissa
                                      exponent:(short)exponent
                                    isNegative:(BOOL)flag;
+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)dcm;
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue;
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue locale:(id)locale;
@property (class, readonly, copy) NSDecimalNumber * FERRY_SWIFT_NONNULL zero;
@property (class, readonly, copy) NSDecimalNumber * FERRY_SWIFT_NONNULL one;
@property (class, readonly, copy) NSDecimalNumber * FERRY_SWIFT_NONNULL minimumDecimalNumber;
@property (class, readonly, copy) NSDecimalNumber * FERRY_SWIFT_NONNULL maximumDecimalNumber;
@property (class, readonly, copy) NSDecimalNumber * FERRY_SWIFT_NONNULL notANumber;
@property (class, strong) id<NSDecimalNumberBehaviors> defaultBehavior;
- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)decimalNumber
                              withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)decimalNumber
                                   withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)decimalNumber
                                     withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)decimalNumber
                                  withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power;
- (NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power
                                      withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power;
- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power
                                              withBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSDecimalNumber *)decimalNumberByRoundingAccordingToBehavior:(id<NSDecimalNumberBehaviors>)behavior;
- (NSComparisonResult)compare:(NSNumber *)decimalNumber;
@property (readonly) NSDecimal decimalValue;
@property (readonly) double doubleValue;
@property (readonly) const char *objCType NS_RETURNS_INNER_POINTER;
- (NSString *)descriptionWithLocale:(id)locale;
@end

@interface NSDecimalNumberHandler : NSObject <NSDecimalNumberBehaviors, NSSecureCoding>
@property (class, readonly, strong) NSDecimalNumberHandler * FERRY_SWIFT_NONNULL defaultDecimalNumberHandler;
+ (instancetype FERRY_SWIFT_NONNULL)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode
                                               scale:(short)scale
                                    raiseOnExactness:(BOOL)exact
                                     raiseOnOverflow:(BOOL)overflow
                                    raiseOnUnderflow:(BOOL)underflow
                                 raiseOnDivideByZero:(BOOL)divideByZero;
- (instancetype FERRY_SWIFT_NONNULL)initWithRoundingMode:(NSRoundingMode)roundingMode
                               scale:(short)scale
                    raiseOnExactness:(BOOL)exact
                     raiseOnOverflow:(BOOL)overflow
                    raiseOnUnderflow:(BOOL)underflow
                 raiseOnDivideByZero:(BOOL)divideByZero;
@end

@interface NSNumber (NSDecimalNumberExtensions)
@property (readonly) NSDecimal decimalValue;
@end

@interface NSScanner (NSDecimalNumberScanning)
- (BOOL)scanDecimal:(NSDecimal *)dcm;
@end

#endif
