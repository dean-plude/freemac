/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: units, measurements, the measurement formatter and the
 * background activity scheduler (foundation/NSMeasurement.m, freemac
 * 1.271). Written for freemac from Apple's public API documentation; not
 * Apple's header. */
#ifndef _FERRY_FOUNDATION_NSMEASUREMENT_H_
#define _FERRY_FOUNDATION_NSMEASUREMENT_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSOperation.h>

typedef NS_ENUM(NSInteger, NSFormattingUnitStyle) {
    NSFormattingUnitStyleShort = 1,
    NSFormattingUnitStyleMedium = 2,
    NSFormattingUnitStyleLong = 3,
};

/* Turns a value in a unit into the value in its dimension's base unit and back. */
@interface NSUnitConverter : NSObject
- (double)baseUnitValueFromValue:(double)value;
- (double)valueFromBaseUnitValue:(double)baseUnitValue;
@end

/* base = value * coefficient + constant */
@interface NSUnitConverterLinear : NSUnitConverter <NSSecureCoding>
- (instancetype)initWithCoefficient:(double)coefficient;
- (instancetype)initWithCoefficient:(double)coefficient constant:(double)constant;
@property (readonly) double coefficient;
@property (readonly) double constant;
@end

@interface NSUnit : NSObject <NSCopying, NSSecureCoding>
- (instancetype)initWithSymbol:(NSString *)symbol;
@property (readonly, copy) NSString *symbol;
@end

@interface NSDimension : NSUnit
- (instancetype)initWithSymbol:(NSString *)symbol converter:(NSUnitConverter *)converter;
@property (readonly, copy) NSUnitConverter *converter;
+ (instancetype)baseUnit;
@end

@interface NSUnitTemperature : NSDimension
@property (class, readonly, copy) NSUnitTemperature *kelvin;
@property (class, readonly, copy) NSUnitTemperature *celsius;
@property (class, readonly, copy) NSUnitTemperature *fahrenheit;
@end

@interface NSUnitInformationStorage : NSDimension
@property (class, readonly, copy) NSUnitInformationStorage *bits;
@property (class, readonly, copy) NSUnitInformationStorage *bytes;
@property (class, readonly, copy) NSUnitInformationStorage *kilobytes;
@property (class, readonly, copy) NSUnitInformationStorage *megabytes;
@property (class, readonly, copy) NSUnitInformationStorage *gigabytes;
@property (class, readonly, copy) NSUnitInformationStorage *terabytes;
@property (class, readonly, copy) NSUnitInformationStorage *kibibytes;
@property (class, readonly, copy) NSUnitInformationStorage *mebibytes;
@property (class, readonly, copy) NSUnitInformationStorage *gibibytes;
@end

@interface NSUnitFrequency : NSDimension
@property (class, readonly, copy) NSUnitFrequency *hertz;
@property (class, readonly, copy) NSUnitFrequency *kilohertz;
@property (class, readonly, copy) NSUnitFrequency *megahertz;
@property (class, readonly, copy) NSUnitFrequency *gigahertz;
@end

@interface NSUnitPower : NSDimension
@property (class, readonly, copy) NSUnitPower *watts;
@property (class, readonly, copy) NSUnitPower *milliwatts;
@property (class, readonly, copy) NSUnitPower *kilowatts;
@end

@interface NSUnitElectricPotentialDifference : NSDimension
@property (class, readonly, copy) NSUnitElectricPotentialDifference *volts;
@property (class, readonly, copy) NSUnitElectricPotentialDifference *millivolts;
@end

@interface NSUnitElectricCurrent : NSDimension
@property (class, readonly, copy) NSUnitElectricCurrent *amperes;
@property (class, readonly, copy) NSUnitElectricCurrent *milliamperes;
@end

@interface NSUnitDuration : NSDimension
@property (class, readonly, copy) NSUnitDuration *seconds;
@property (class, readonly, copy) NSUnitDuration *minutes;
@property (class, readonly, copy) NSUnitDuration *hours;
@property (class, readonly, copy) NSUnitDuration *milliseconds;
@end

@interface NSUnitLength : NSDimension
@property (class, readonly, copy) NSUnitLength *meters;
@property (class, readonly, copy) NSUnitLength *kilometers;
@property (class, readonly, copy) NSUnitLength *centimeters;
@property (class, readonly, copy) NSUnitLength *millimeters;
@property (class, readonly, copy) NSUnitLength *inches;
@property (class, readonly, copy) NSUnitLength *feet;
@property (class, readonly, copy) NSUnitLength *miles;
@end

@interface NSMeasurement<UnitType : NSUnit *> : NSObject <NSCopying, NSSecureCoding>
- (instancetype)initWithDoubleValue:(double)doubleValue unit:(UnitType)unit;
@property (readonly, copy) UnitType unit;
@property (readonly) double doubleValue;
- (BOOL)canBeConvertedToUnit:(NSUnit *)unit;
- (NSMeasurement *)measurementByConvertingToUnit:(NSUnit *)unit;
- (NSMeasurement<UnitType> *)measurementByAddingMeasurement:(NSMeasurement<UnitType> *)measurement;
- (NSMeasurement<UnitType> *)measurementBySubtractingMeasurement:(NSMeasurement<UnitType> *)measurement;
@end

typedef NS_OPTIONS(NSUInteger, NSMeasurementFormatterUnitOptions) {
    NSMeasurementFormatterUnitOptionsProvidedUnit = 1UL << 0,
    NSMeasurementFormatterUnitOptionsNaturalScale = 1UL << 1,
    NSMeasurementFormatterUnitOptionsTemperatureWithoutUnit = 1UL << 2,
};

/* Temperatures in the locale's own scale (Fahrenheit in the United States)
 * unless the provided unit is asked for; numbers to at most three places. */
@interface NSMeasurementFormatter : NSFormatter <NSSecureCoding>
@property NSMeasurementFormatterUnitOptions unitOptions;
@property NSFormattingUnitStyle unitStyle;
@property (copy) NSLocale *locale;
@property (copy) NSNumberFormatter *numberFormatter;
- (NSString *)stringFromMeasurement:(NSMeasurement *)measurement;
- (NSString *)stringFromUnit:(NSUnit *)unit;
@end

/* ---- NSBackgroundActivityScheduler ---- */

typedef NS_ENUM(NSInteger, NSBackgroundActivityResult) {
    NSBackgroundActivityResultFinished = 1,
    NSBackgroundActivityResultDeferred = 2,
};
typedef void (^NSBackgroundActivityCompletionHandler)(NSBackgroundActivityResult result);

/* Runs its block on a background queue once the interval (or, not
 * repeating, the tolerance) has passed, again each interval if it repeats.
 * Ferry never asks it to defer. */
@interface NSBackgroundActivityScheduler : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier;
@property (readonly, copy) NSString *identifier;
@property NSQualityOfService qualityOfService;
@property BOOL repeats;
@property NSTimeInterval interval;
@property NSTimeInterval tolerance;
- (void)scheduleWithBlock:(void (^)(NSBackgroundActivityCompletionHandler completionHandler))block;
- (void)invalidate;
@property (readonly) BOOL shouldDefer;
@end

#endif
