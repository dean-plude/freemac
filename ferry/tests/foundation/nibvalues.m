/* Ferry test: the Foundation values Flycut's nib and code need: number and
 * date formatters and decimal numbers decoded as a Mac's archives hold them
 * (written here by stand-in classes that encode a Mac's keys), formatters
 * archived and read back, old-style property list strings, NSArray's
 * searches within a range and the iCloud calls of a Mac with no account. */
#import <Foundation/Foundation.h>
#include <stdio.h>

/* A decimal number as a Mac archives it: 1234.5 is 12345 with exponent -1. */
@interface MacDecimal : NSObject <NSCoding>
@property BOOL bigEndian;
@end
@implementation MacDecimal
- (Class)classForKeyedArchiver { return [NSDecimalNumber class]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    uint8_t m[16] = {0};
    unsigned short v = 12345;
    m[0] = self.bigEndian ? (uint8_t)(v >> 8) : (uint8_t)(v & 0xff);
    m[1] = self.bigEndian ? (uint8_t)(v & 0xff) : (uint8_t)(v >> 8);
    [c encodeBytes:m length:sizeof m forKey:@"NS.mantissa"];
    [c encodeInt:self.bigEndian ? 0 : 1 forKey:@"NS.mantissa.bo"];
    [c encodeInt:1 forKey:@"NS.length"];
    [c encodeInt:-1 forKey:@"NS.exponent"];
    [c encodeBool:YES forKey:@"NS.negative"];
    [c encodeBool:YES forKey:@"NS.compact"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
@end

/* A number formatter in an old nib: its own keys, no NS.attributes. */
@interface OldNumberFormatter : NSObject <NSCoding>
@end
@implementation OldNumberFormatter
- (Class)classForKeyedArchiver { return [NSNumberFormatter class]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:@"#,##0.00" forKey:@"NS.positiveformat"];
    [c encodeObject:@"-#,##0.00" forKey:@"NS.negativeformat"];
    [c encodeObject:@"," forKey:@"NS.decimal"];
    [c encodeObject:@"." forKey:@"NS.thousand"];
    [c encodeBool:YES forKey:@"NS.hasthousands"];
    [c encodeBool:YES forKey:@"NS.allowsfloats"];
    [c encodeObject:[NSDecimalNumber notANumber] forKey:@"NS.min"];
    [c encodeObject:@100000 forKey:@"NS.max"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
@end

/* A formatter in a newer nib: its properties in NS.attributes. */
@interface NewNumberFormatter : NSObject <NSCoding>
@end
@implementation NewNumberFormatter
- (Class)classForKeyedArchiver { return [NSNumberFormatter class]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:@{
        @"formatterBehavior" : @1040, @"numberStyle" : @1, @"maximumFractionDigits" : @1,
        @"minimumFractionDigits" : @1, @"usesGroupingSeparator" : @NO, @"notAProperty" : @"ignored"
    }
             forKey:@"NS.attributes"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
@end

@interface NibDateFormatter : NSObject <NSCoding>
@end
@implementation NibDateFormatter
- (Class)classForKeyedArchiver { return [NSDateFormatter class]; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:@{@"formatterBehavior" : @1040, @"dateFormat" : @"yyyy/MM/dd"} forKey:@"NS.attributes"];
}
- (instancetype)initWithCoder:(NSCoder *)c { return [self init]; }
@end

static id roundTrip(id object)
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

static void decimals(void)
{
    MacDecimal *little = [MacDecimal new], *big = [MacDecimal new];
    big.bigEndian = YES;
    id a = roundTrip(little), b = roundTrip(big);
    printf("decimal from a Mac archive: %s %s\n", object_getClassName(a), [[a description] UTF8String]);
    printf("  with big-endian words: %s\n", [[b description] UTF8String]);
    NSDecimalNumber *mine = [NSDecimalNumber decimalNumberWithString:@"98.76"];
    printf("Ferry's own, read back: %s\n", [[roundTrip(mine) description] UTF8String]);
}

static void formatters(void)
{
    NSNumberFormatter *old = roundTrip([OldNumberFormatter new]);
    printf("old nib formatter: %s, format %s, decimal '%s', grouping '%s' %d, maximum %s, minimum %s\n",
           object_getClassName(old), [[old positiveFormat] UTF8String], [[old decimalSeparator] UTF8String],
           [[old groupingSeparator] UTF8String], [old usesGroupingSeparator], [[[old maximum] description] UTF8String],
           [old minimum] ? "set" : "none");
    printf("  formats 1234.5 as %s\n", [[old stringFromNumber:@1234.5] UTF8String]);
    NSNumberFormatter *newer = roundTrip([NewNumberFormatter new]);
    printf("newer nib formatter: style %ld, fraction digits %ld-%ld, grouping %d\n", (long)[newer numberStyle],
           (long)[newer minimumFractionDigits], (long)[newer maximumFractionDigits], [newer usesGroupingSeparator]);
    newer.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    printf("  formats 1234.56 as %s\n", [[newer stringFromNumber:@1234.56] UTF8String]);

    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterPercentStyle;
    f.maximum = @2;
    NSNumberFormatter *back = roundTrip(f);
    printf("archived and read back: style %ld, maximum %s\n", (long)[back numberStyle],
           [[[back maximum] description] UTF8String]);

    NSDateFormatter *d = roundTrip([NibDateFormatter new]);
    d.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    printf("nib date formatter: %s, %s\n", [[d dateFormat] UTF8String],
           [[d stringFromDate:[NSDate dateWithTimeIntervalSince1970:0]] UTF8String]);
    NSDateFormatter *styled = [NSDateFormatter new];
    styled.dateStyle = NSDateFormatterLongStyle;
    styled.timeStyle = NSDateFormatterNoStyle;
    NSDateFormatter *back2 = roundTrip(styled);
    printf("date formatter read back: styles %ld %ld\n", (long)[back2 dateStyle], (long)[back2 timeStyle]);
}

static void strings(void)
{
    id plist = [@"{ name = Flycut; sizes = (1, 2, \"three\"); }" propertyList];
    printf("propertyList: a dictionary %d, %lu keys, sizes %lu\n", [plist isKindOfClass:[NSDictionary class]],
           (unsigned long)[plist count],
           (unsigned long)[[plist objectForKey:@"sizes"] count]);
    NSDictionary *strings = [@"\"Clear All\" = \"Tout effacer\";\n/* a comment */\n\"Quit\" = \"Quitter\";\n"
        propertyListFromStringsFileFormat];
    printf("strings file: %lu entries, Quit is %s\n", (unsigned long)[strings count],
           [[strings objectForKey:@"Quit"] UTF8String]);
    @try {
        [@"{ unterminated" propertyList];
        printf("bad property list: no exception\n");
    } @catch (NSException *e) {
        printf("bad property list: %s\n", [[e name] UTF8String]);
    }
}

static void arrays(void)
{
    NSString *x = [NSString stringWithFormat:@"%s", "x"];
    NSArray *a = @[ @"a", x, @"b", @"x", @"c" ];
    printf("indexOfObject:inRange: %lu %lu %s\n", (unsigned long)[a indexOfObject:@"x" inRange:NSMakeRange(2, 3)],
           (unsigned long)[a indexOfObject:@"x" inRange:NSMakeRange(0, 2)],
           [a indexOfObject:@"a" inRange:NSMakeRange(1, 4)] == NSNotFound ? "NSNotFound" : "found");
    printf("indexOfObjectIdenticalTo:inRange: %lu %s\n",
           (unsigned long)[a indexOfObjectIdenticalTo:x inRange:NSMakeRange(0, 5)],
           [a indexOfObjectIdenticalTo:x inRange:NSMakeRange(2, 3)] == NSNotFound ? "NSNotFound" : "found");
    @try {
        [a indexOfObject:@"x" inRange:NSMakeRange(3, 5)];
        printf("out of range: no exception\n");
    } @catch (NSException *e) {
        printf("out of range: %s\n", [[e name] UTF8String]);
    }
}

static void ubiquity(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    printf("iCloud: token %s, container %s, ubiquitous %d, notification %s\n",
           fm.ubiquityIdentityToken ? "some" : "none",
           [fm URLForUbiquityContainerIdentifier:nil] ? "some" : "none",
           [fm isUbiquitousItemAtURL:[NSURL fileURLWithPath:@"/tmp"]],
           [NSUbiquityIdentityDidChangeNotification UTF8String]);
}

int main(void)
{
    @autoreleasepool {
        decimals();
        formatters();
        strings();
        arrays();
        ubiquity();
    }
    return 0;
}
