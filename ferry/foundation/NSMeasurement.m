/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: units and their converters, measurements, the
 * measurement formatter, and the background activity scheduler (freemac
 * 1.271, for Stats, which shows its sensors' temperatures through
 * MeasurementFormatter and refreshes through the scheduler).
 *
 * A dimension's converter turns its values into the base unit's (kelvin,
 * bytes, hertz and so on) and back; two measurements of one dimension
 * convert through the base. The formatter writes temperatures in the
 * locale's scale unless asked for the unit given.
 *
 * Written from Apple's public documentation; no Apple code was used. */
#import "FInternal.h"
#include <dispatch/dispatch.h>

/* ---- converters ------------------------------------------------------------------ */

@implementation NSUnitConverter
- (double)baseUnitValueFromValue:(double)value { return value; }
- (double)valueFromBaseUnitValue:(double)baseUnitValue { return baseUnitValue; }
@end

@implementation NSUnitConverterLinear {
    double _coefficient, _constant;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoefficient:(double)coefficient { return [self initWithCoefficient:coefficient constant:0]; }
- (instancetype)initWithCoefficient:(double)coefficient constant:(double)constant
{
    if ((self = [super init])) {
        _coefficient = coefficient;
        _constant = constant;
    }
    return self;
}
- (double)coefficient { return _coefficient; }
- (double)constant { return _constant; }
- (double)baseUnitValueFromValue:(double)value { return value * _coefficient + _constant; }
- (double)valueFromBaseUnitValue:(double)base { return (base - _constant) / _coefficient; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeDouble:_coefficient forKey:@"NS.coefficient"];
    [c encodeDouble:_constant forKey:@"NS.constant"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithCoefficient:[c decodeDoubleForKey:@"NS.coefficient"] constant:[c decodeDoubleForKey:@"NS.constant"]];
}
@end

/* ---- units ----------------------------------------------------------------------- */

@implementation NSUnit {
@protected
    NSString *_symbol;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithSymbol:(NSString *)symbol
{
    if ((self = [super init]))
        _symbol = [symbol copy];
    return self;
}
- (void)dealloc
{
    [_symbol release];
    [super dealloc];
}
- (NSString *)symbol { return _symbol; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
- (BOOL)isEqual:(id)o
{
    return o == self || ([o isKindOfClass:[NSUnit class]] && [o class] == [self class] && [[o symbol] isEqual:_symbol]);
}
- (NSUInteger)hash { return [_symbol hash]; }
- (NSString *)description { return _symbol; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_symbol forKey:@"NS.symbol"]; }
- (instancetype)initWithCoder:(NSCoder *)c { return [self initWithSymbol:[c decodeObjectForKey:@"NS.symbol"]]; }
@end

@implementation NSDimension {
    NSUnitConverter *_converter;
}
- (instancetype)initWithSymbol:(NSString *)symbol
{
    return [self initWithSymbol:symbol converter:[[[NSUnitConverterLinear alloc] initWithCoefficient:1] autorelease]];
}
- (instancetype)initWithSymbol:(NSString *)symbol converter:(NSUnitConverter *)converter
{
    if ((self = [super initWithSymbol:symbol]))
        _converter = [converter retain];
    return self;
}
- (void)dealloc
{
    [_converter release];
    [super dealloc];
}
- (NSUnitConverter *)converter { return _converter; }
+ (instancetype)baseUnit { return nil; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [super encodeWithCoder:c];
    [c encodeObject:_converter forKey:@"NS.converter"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithSymbol:[c decodeObjectForKey:@"NS.symbol"] converter:[c decodeObjectForKey:@"NS.converter"]];
}
@end

/* A unit kept for the life of the program: one per class and symbol. */
static id unit_of(Class cls, NSString *symbol, double coefficient, double constant)
{
    static NSMutableDictionary *units;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    if (!units)
        units = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%s %@", class_getName(cls), symbol];
    id u = [units objectForKey:key];
    if (!u) {
        NSUnitConverter *conv = [[[NSUnitConverterLinear alloc] initWithCoefficient:coefficient constant:constant] autorelease];
        u = [[[cls alloc] initWithSymbol:symbol converter:conv] autorelease];
        [units setObject:u forKey:key];
    }
    pthread_mutex_unlock(&lock);
    return u;
}

#define UNIT(name, sym, coef) \
    + (instancetype)name { return unit_of(self, @sym, coef, 0); }

@implementation NSUnitTemperature
+ (instancetype)kelvin { return unit_of([NSUnitTemperature class], @"K", 1, 0); }
+ (instancetype)celsius { return unit_of([NSUnitTemperature class], @"°C", 1, 273.15); }
+ (instancetype)fahrenheit { return unit_of([NSUnitTemperature class], @"°F", 5.0 / 9.0, 273.15 - 32.0 * 5.0 / 9.0); }
+ (instancetype)baseUnit { return [self kelvin]; }
@end

@implementation NSUnitInformationStorage
UNIT(bits, "bit", 0.125)
UNIT(bytes, "B", 1)
UNIT(kilobytes, "kB", 1e3)
UNIT(megabytes, "MB", 1e6)
UNIT(gigabytes, "GB", 1e9)
UNIT(terabytes, "TB", 1e12)
UNIT(kibibytes, "KiB", 1024.0)
UNIT(mebibytes, "MiB", 1048576.0)
UNIT(gibibytes, "GiB", 1073741824.0)
+ (instancetype)baseUnit { return [self bytes]; }
@end

@implementation NSUnitFrequency
UNIT(hertz, "Hz", 1)
UNIT(kilohertz, "kHz", 1e3)
UNIT(megahertz, "MHz", 1e6)
UNIT(gigahertz, "GHz", 1e9)
+ (instancetype)baseUnit { return [self hertz]; }
@end

@implementation NSUnitPower
UNIT(watts, "W", 1)
UNIT(milliwatts, "mW", 1e-3)
UNIT(kilowatts, "kW", 1e3)
+ (instancetype)baseUnit { return [self watts]; }
@end

@implementation NSUnitElectricPotentialDifference
UNIT(volts, "V", 1)
UNIT(millivolts, "mV", 1e-3)
+ (instancetype)baseUnit { return [self volts]; }
@end

@implementation NSUnitElectricCurrent
UNIT(amperes, "A", 1)
UNIT(milliamperes, "mA", 1e-3)
+ (instancetype)baseUnit { return [self amperes]; }
@end

@implementation NSUnitDuration
UNIT(seconds, "s", 1)
UNIT(minutes, "min", 60)
UNIT(hours, "hr", 3600)
UNIT(milliseconds, "ms", 1e-3)
+ (instancetype)baseUnit { return [self seconds]; }
@end

@implementation NSUnitLength
UNIT(meters, "m", 1)
UNIT(kilometers, "km", 1e3)
UNIT(centimeters, "cm", 1e-2)
UNIT(millimeters, "mm", 1e-3)
UNIT(inches, "in", 0.0254)
UNIT(feet, "ft", 0.3048)
UNIT(miles, "mi", 1609.344)
+ (instancetype)baseUnit { return [self meters]; }
@end

/* ---- measurements ---------------------------------------------------------------- */

@implementation NSMeasurement {
    NSUnit *_unit;
    double _value;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithDoubleValue:(double)doubleValue unit:(NSUnit *)unit
{
    if ((self = [super init])) {
        _value = doubleValue;
        _unit = [unit retain];
    }
    return self;
}
- (void)dealloc
{
    [_unit release];
    [super dealloc];
}
- (id)unit { return _unit; }
- (double)doubleValue { return _value; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
static Class dimension_root(NSUnit *u)
{
    Class c = [u class], dim = [NSDimension class];
    if (![u isKindOfClass:dim])
        return Nil;
    while (class_getSuperclass(c) && class_getSuperclass(c) != dim)
        c = class_getSuperclass(c);
    return c;
}
- (BOOL)canBeConvertedToUnit:(NSUnit *)unit
{
    if ([unit isEqual:_unit])
        return YES;
    Class a = dimension_root(_unit), b = dimension_root(unit);
    return a && a == b;
}
- (NSMeasurement *)measurementByConvertingToUnit:(NSUnit *)unit
{
    if ([unit isEqual:_unit])
        return [[[NSMeasurement alloc] initWithDoubleValue:_value unit:unit] autorelease];
    if (![self canBeConvertedToUnit:unit])
        [NSException raise:NSInvalidArgumentException format:@"can't convert %@ to %@", _unit, unit];
    double base = [[(NSDimension *)_unit converter] baseUnitValueFromValue:_value];
    double v = [[(NSDimension *)unit converter] valueFromBaseUnitValue:base];
    return [[[NSMeasurement alloc] initWithDoubleValue:v unit:unit] autorelease];
}
- (NSMeasurement *)measurementByAddingMeasurement:(NSMeasurement *)m
{
    double v = [[m measurementByConvertingToUnit:_unit] doubleValue];
    return [[[NSMeasurement alloc] initWithDoubleValue:_value + v unit:_unit] autorelease];
}
- (NSMeasurement *)measurementBySubtractingMeasurement:(NSMeasurement *)m
{
    double v = [[m measurementByConvertingToUnit:_unit] doubleValue];
    return [[[NSMeasurement alloc] initWithDoubleValue:_value - v unit:_unit] autorelease];
}
- (BOOL)isEqual:(id)o
{
    if (o == self)
        return YES;
    if (![o isKindOfClass:[NSMeasurement class]] || ![o canBeConvertedToUnit:_unit])
        return NO;
    return [[o measurementByConvertingToUnit:_unit] doubleValue] == _value;
}
- (NSUInteger)hash { return (NSUInteger)_value ^ [_unit hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"%g %@", _value, [_unit symbol]]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeDouble:_value forKey:@"NS.value"];
    [c encodeObject:_unit forKey:@"NS.unit"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    return [self initWithDoubleValue:[c decodeDoubleForKey:@"NS.value"] unit:[c decodeObjectForKey:@"NS.unit"]];
}
@end

/* ---- the formatter --------------------------------------------------------------- */

@implementation NSMeasurementFormatter {
    NSMeasurementFormatterUnitOptions _options;
    NSFormattingUnitStyle _style;
    NSLocale *_locale;
    NSNumberFormatter *_numbers;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init
{
    if ((self = [super init]))
        _style = NSFormattingUnitStyleMedium;
    return self;
}
- (void)dealloc
{
    [_locale release];
    [_numbers release];
    [super dealloc];
}
- (NSMeasurementFormatterUnitOptions)unitOptions { return _options; }
- (void)setUnitOptions:(NSMeasurementFormatterUnitOptions)o { _options = o; }
- (NSFormattingUnitStyle)unitStyle { return _style; }
- (void)setUnitStyle:(NSFormattingUnitStyle)s { _style = s; }
- (NSLocale *)locale { return _locale ? _locale : [NSLocale currentLocale]; }
- (void)setLocale:(NSLocale *)l
{
    [_locale release];
    _locale = [l copy];
}
- (NSNumberFormatter *)numberFormatter
{
    if (!_numbers) {
        _numbers = [[NSNumberFormatter alloc] init];
        [_numbers setNumberStyle:NSNumberFormatterDecimalStyle];
        [_numbers setMaximumFractionDigits:3];
    }
    return _numbers;
}
- (void)setNumberFormatter:(NSNumberFormatter *)f
{
    [_numbers release];
    _numbers = [f copy];
}

/* The countries that measure temperatures in Fahrenheit. */
static BOOL locale_uses_fahrenheit(NSLocale *l)
{
    NSString *cc = [l objectForKey:NSLocaleCountryCode];
    for (NSString *f in @[@"US", @"BS", @"BZ", @"KY", @"PW", @"LR"])
        if ([f isEqualToString:cc])
            return YES;
    return NO;
}

static NSString *long_name(NSUnit *u)
{
    NSDictionary *names = @{@"K": @"kelvins", @"°C": @"degrees Celsius", @"°F": @"degrees Fahrenheit",
                            @"B": @"bytes", @"kB": @"kilobytes", @"MB": @"megabytes", @"GB": @"gigabytes",
                            @"TB": @"terabytes", @"Hz": @"hertz", @"MHz": @"megahertz", @"GHz": @"gigahertz",
                            @"W": @"watts", @"V": @"volts", @"A": @"amperes", @"s": @"seconds",
                            @"min": @"minutes", @"hr": @"hours", @"m": @"meters", @"km": @"kilometers"};
    NSString *n = [names objectForKey:[u symbol]];
    return n ? n : [u symbol];
}

- (NSString *)stringFromUnit:(NSUnit *)unit
{
    return _style == NSFormattingUnitStyleLong ? long_name(unit) : [unit symbol];
}

- (NSString *)stringFromMeasurement:(NSMeasurement *)m
{
    if (!m)
        return nil;
    NSUnit *unit = [m unit];
    BOOL temperature = [unit isKindOfClass:[NSUnitTemperature class]];
    if (temperature && !(_options & NSMeasurementFormatterUnitOptionsProvidedUnit)) {
        NSUnit *want = locale_uses_fahrenheit([self locale]) ? [NSUnitTemperature fahrenheit] : [NSUnitTemperature celsius];
        m = [m measurementByConvertingToUnit:want];
        unit = want;
    }
    NSString *num = [[self numberFormatter] stringFromNumber:[NSNumber numberWithDouble:[m doubleValue]]];
    if (!num)
        num = [NSString stringWithFormat:@"%g", [m doubleValue]];
    if (temperature) {
        if ((_options & NSMeasurementFormatterUnitOptionsTemperatureWithoutUnit) || _style == NSFormattingUnitStyleShort)
            return [num stringByAppendingString:@"°"];
        if (_style == NSFormattingUnitStyleLong)
            return [NSString stringWithFormat:@"%@ %@", num, long_name(unit)];
        return [num stringByAppendingString:[unit symbol]];
    }
    return [NSString stringWithFormat:@"%@ %@", num, [self stringFromUnit:unit]];
}

- (NSString *)stringForObjectValue:(id)obj
{
    if ([obj isKindOfClass:[NSMeasurement class]])
        return [self stringFromMeasurement:obj];
    if ([obj isKindOfClass:[NSUnit class]])
        return [self stringFromUnit:obj];
    return nil;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeInteger:(NSInteger)_options forKey:@"NS.unitOptions"];
    [c encodeInteger:_style forKey:@"NS.unitStyle"];
}
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [self init])) {
        _options = (NSMeasurementFormatterUnitOptions)[c decodeIntegerForKey:@"NS.unitOptions"];
        if ([c containsValueForKey:@"NS.unitStyle"])
            _style = [c decodeIntegerForKey:@"NS.unitStyle"];
    }
    return self;
}
@end

/* ---- NSBackgroundActivityScheduler ----------------------------------------------- */

@implementation NSBackgroundActivityScheduler {
    NSString *_identifier;
    NSQualityOfService _qos;
    BOOL _repeats;
    NSTimeInterval _interval, _tolerance;
    dispatch_source_t _timer;
}
- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _qos = NSQualityOfServiceBackground;
    }
    return self;
}
- (void)dealloc
{
    [self invalidate];
    [_identifier release];
    [super dealloc];
}
- (NSString *)identifier { return _identifier; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (BOOL)repeats { return _repeats; }
- (void)setRepeats:(BOOL)r { _repeats = r; }
- (NSTimeInterval)interval { return _interval; }
- (void)setInterval:(NSTimeInterval)i { _interval = i; }
- (NSTimeInterval)tolerance { return _tolerance; }
- (void)setTolerance:(NSTimeInterval)t { _tolerance = t; }
- (BOOL)shouldDefer { return NO; }

- (void)scheduleWithBlock:(void (^)(NSBackgroundActivityCompletionHandler))block
{
    [self invalidate];
    /* The first run comes a little after scheduling, as on a Mac, where the
     * system picks a moment within the interval; then once each interval. */
    NSTimeInterval first = _repeats ? (_interval > 0 ? _interval : 60) : (_tolerance > 0 ? _tolerance : 1);
    if (first > 10)
        first = 10;
    NSTimeInterval every = _interval > 0 ? _interval : 60;
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(first * NSEC_PER_SEC)),
                              _repeats ? (uint64_t)(every * NSEC_PER_SEC) : DISPATCH_TIME_FOREVER,
                              (uint64_t)(_tolerance * NSEC_PER_SEC));
    void (^work)(NSBackgroundActivityCompletionHandler) = [block copy];
    BOOL repeats = _repeats;
    dispatch_source_t timer = _timer;
    dispatch_source_set_event_handler(_timer, ^{
        work(^(NSBackgroundActivityResult result) { (void)result; });
        if (!repeats)
            dispatch_source_cancel(timer);
    });
    dispatch_resume(_timer);
}

- (void)invalidate
{
    if (_timer) {
        dispatch_source_cancel(_timer);
        dispatch_release(_timer);
        _timer = NULL;
    }
}
@end
