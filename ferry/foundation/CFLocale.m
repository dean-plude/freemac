/* SPDX-License-Identifier: GPL-3.0-or-later
 * CFLocale, CFDate and CFDateFormatter (sdk/include/CoreFoundation/
 * CFLocale.h, CFDate.h), written for freemac from Apple's public
 * documentation. A CFLocaleRef is an NSLocale (NSTimeZone.m), a CFDateRef
 * an NSDate and a CFDateFormatterRef an NSDateFormatter, so the calls ask
 * them; a locale's keys are NSLocale's own strings, as on a Mac. */
#import "FInternal.h"

#define FERRY_TYPE_LOCALE 0x46520017
#define FERRY_TYPE_DATE_FORMATTER 0x46520018
#define FERRY_TYPE_DATE 0x46520019

const CFLocaleKey kCFLocaleIdentifier = (CFStringRef)@"locale:id";
const CFLocaleKey kCFLocaleLanguageCode = (CFStringRef)@"locale:language code";
const CFLocaleKey kCFLocaleCountryCode = (CFStringRef)@"locale:country code";
const CFLocaleKey kCFLocaleScriptCode = (CFStringRef)@"locale:script code";
const CFLocaleKey kCFLocaleVariantCode = (CFStringRef)@"locale:variant code";
const CFLocaleKey kCFLocaleDecimalSeparator = (CFStringRef)@"locale:decimal separator";
const CFLocaleKey kCFLocaleGroupingSeparator = (CFStringRef)@"locale:grouping separator";
const CFLocaleKey kCFLocaleUsesMetricSystem = (CFStringRef)@"locale:uses metric";
const CFLocaleKey kCFLocaleCalendar = (CFStringRef)@"locale:calendar";
const CFLocaleKey kCFLocaleCurrencyCode = (CFStringRef)@"locale:currency code";
const CFLocaleKey kCFLocaleCurrencySymbol = (CFStringRef)@"locale:currency symbol";
const CFStringRef kCFLocaleCurrentLocaleDidChangeNotification =
    (CFStringRef)@"kCFLocaleCurrentLocaleDidChangeNotification";

@implementation NSLocale (FerryCFLocale)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_LOCALE; }
@end

CFTypeID CFLocaleGetTypeID(void) { return FERRY_TYPE_LOCALE; }
CFLocaleRef CFLocaleCopyCurrent(void) { return (CFLocaleRef)[[NSLocale currentLocale] retain]; }
CFLocaleRef CFLocaleGetSystem(void) { return (CFLocaleRef)[NSLocale systemLocale]; }
CFLocaleRef CFLocaleCreate(CFAllocatorRef allocator, CFLocaleIdentifier identifier)
{
    if (!identifier)
        return NULL;
    return (CFLocaleRef)[[NSLocale alloc] initWithLocaleIdentifier:(NSString *)identifier];
}
CFLocaleRef CFLocaleCreateCopy(CFAllocatorRef allocator, CFLocaleRef locale)
{
    return locale ? (CFLocaleRef)[(NSLocale *)locale copy] : NULL;
}
CFLocaleIdentifier CFLocaleGetIdentifier(CFLocaleRef locale)
{
    return locale ? (CFStringRef)[(NSLocale *)locale localeIdentifier] : NULL;
}
CFTypeRef CFLocaleGetValue(CFLocaleRef locale, CFLocaleKey key)
{
    if (!locale || !key)
        return NULL;
    return (CFTypeRef)[(NSLocale *)locale objectForKey:(NSString *)key];
}
CFStringRef CFLocaleCopyDisplayNameForPropertyValue(CFLocaleRef displayLocale, CFLocaleKey key, CFStringRef value)
{
    if (!displayLocale || !key || !value)
        return NULL;
    return (CFStringRef)[[(NSLocale *)displayLocale displayNameForKey:(NSString *)key value:(id)value] copy];
}
CFArrayRef CFLocaleCopyAvailableLocaleIdentifiers(void)
{
    return (CFArrayRef)[[NSLocale availableLocaleIdentifiers] copy];
}
CFArrayRef CFLocaleCopyISOLanguageCodes(void) { return (CFArrayRef)[[NSLocale ISOLanguageCodes] copy]; }
CFArrayRef CFLocaleCopyPreferredLanguages(void) { return (CFArrayRef)[[NSLocale preferredLanguages] copy]; }
CFLocaleIdentifier CFLocaleCreateCanonicalLocaleIdentifierFromString(CFAllocatorRef allocator, CFStringRef string)
{
    if (!string)
        return NULL;
    return (CFStringRef)[[NSLocale canonicalLocaleIdentifierFromString:(NSString *)string] copy];
}
CFDictionaryRef CFLocaleCreateComponentsFromLocaleIdentifier(CFAllocatorRef allocator, CFLocaleIdentifier localeID)
{
    if (!localeID)
        return NULL;
    return (CFDictionaryRef)[[NSLocale componentsFromLocaleIdentifier:(NSString *)localeID] copy];
}

/* ---- dates ---------------------------------------------------------------------------- */
const CFTimeInterval kCFAbsoluteTimeIntervalSince1904 = 3061152000.0;

/* Every kind of NSDate answers the one type (CFGetTypeID asks _ferryCFTypeID). */
@implementation NSDate (FerryCFDate)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_DATE; }
@end
CFTypeID CFDateGetTypeID(void) { return FERRY_TYPE_DATE; }
CFDateRef CFDateCreate(CFAllocatorRef allocator, CFAbsoluteTime at)
{
    return (CFDateRef)[[NSDate alloc] initWithTimeIntervalSinceReferenceDate:at];
}
CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef date) { return [(NSDate *)date timeIntervalSinceReferenceDate]; }
CFTimeInterval CFDateGetTimeIntervalSinceDate(CFDateRef date, CFDateRef other)
{
    return [(NSDate *)date timeIntervalSinceDate:(NSDate *)other];
}
CFComparisonResult CFDateCompare(CFDateRef date, CFDateRef other, void *context)
{
    return (CFComparisonResult)[(NSDate *)date compare:(NSDate *)other];
}

/* ---- date formatters ------------------------------------------------------------------ */
@interface NSDateFormatter (FerryCFDateFormatter)
@end
@implementation NSDateFormatter (FerryCFDateFormatter)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_DATE_FORMATTER; }
@end

CFTypeID CFDateFormatterGetTypeID(void) { return FERRY_TYPE_DATE_FORMATTER; }
CFDateFormatterRef CFDateFormatterCreate(CFAllocatorRef allocator, CFLocaleRef locale, CFDateFormatterStyle dateStyle,
                                         CFDateFormatterStyle timeStyle)
{
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    if (locale)
        [f setLocale:(NSLocale *)locale];
    [f setDateStyle:(NSDateFormatterStyle)dateStyle];
    [f setTimeStyle:(NSDateFormatterStyle)timeStyle];
    return (CFDateFormatterRef)f;
}
CFLocaleRef CFDateFormatterGetLocale(CFDateFormatterRef f) { return (CFLocaleRef)[(NSDateFormatter *)f locale]; }
CFDateFormatterStyle CFDateFormatterGetDateStyle(CFDateFormatterRef f)
{
    return (CFDateFormatterStyle)[(NSDateFormatter *)f dateStyle];
}
CFDateFormatterStyle CFDateFormatterGetTimeStyle(CFDateFormatterRef f)
{
    return (CFDateFormatterStyle)[(NSDateFormatter *)f timeStyle];
}
CFStringRef CFDateFormatterGetFormat(CFDateFormatterRef f) { return (CFStringRef)[(NSDateFormatter *)f dateFormat]; }
void CFDateFormatterSetFormat(CFDateFormatterRef f, CFStringRef format)
{
    [(NSDateFormatter *)f setDateFormat:(NSString *)format];
}
CFStringRef CFDateFormatterCreateStringWithDate(CFAllocatorRef allocator, CFDateFormatterRef f, CFDateRef date)
{
    if (!f || !date)
        return NULL;
    return (CFStringRef)[[(NSDateFormatter *)f stringFromDate:(NSDate *)date] copy];
}
CFStringRef CFDateFormatterCreateStringWithAbsoluteTime(CFAllocatorRef allocator, CFDateFormatterRef f,
                                                        CFAbsoluteTime at)
{
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:at];
    return CFDateFormatterCreateStringWithDate(allocator, f, (CFDateRef)date);
}
CFDateRef CFDateFormatterCreateDateFromString(CFAllocatorRef allocator, CFDateFormatterRef f, CFStringRef string,
                                              CFRange *rangep)
{
    if (!f || !string)
        return NULL;
    NSString *s = (NSString *)string;
    if (rangep)
        s = [s substringWithRange:NSMakeRange((NSUInteger)rangep->location, (NSUInteger)rangep->length)];
    NSDate *date = [(NSDateFormatter *)f dateFromString:s];
    return (CFDateRef)[date retain];
}
CFStringRef CFDateFormatterCreateDateFormatFromTemplate(CFAllocatorRef allocator, CFStringRef tmpl,
                                                        CFOptionFlags options, CFLocaleRef locale)
{
    if (!tmpl)
        return NULL;
    return (CFStringRef)[[NSDateFormatter dateFormatFromTemplate:(NSString *)tmpl options:options
                                                          locale:(NSLocale *)locale] copy];
}
