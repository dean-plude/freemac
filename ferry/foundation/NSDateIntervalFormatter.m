/* SPDX-License-Identifier: GPL-3.0-or-later
 * The date interval formatter, formatting contexts, the data detector for
 * links, resource specifiers (and the tags key) and locale identifiers
 * from components
 * (sdk/include/Foundation/NSDateIntervalFormatter.h; freemac 1.232,
 * Ferry 0.56.0). Written from Apple's public documentation. */
#import "FInternal.h"
#import <objc/runtime.h>

NSNotificationName const NSSystemClockDidChangeNotification = @"NSSystemClockDidChangeNotification";
NSString *const NSURLTagNamesKey = @"NSURLTagNamesKey";

static char context_key;

@implementation NSDateFormatter (NSFormattingContext)
- (NSFormattingContext)formattingContext
{
    return [objc_getAssociatedObject(self, &context_key) integerValue];
}
- (void)setFormattingContext:(NSFormattingContext)c
{
    objc_setAssociatedObject(self, &context_key, [NSNumber numberWithInteger:c], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* ---- date intervals ---------------------------------------------------------------------- */

@implementation NSDateIntervalFormatter {
    NSLocale *_locale;
    NSCalendar *_calendar;
    NSTimeZone *_timeZone;
    NSString *_dateTemplate;
    NSDateIntervalFormatterStyle _dateStyle, _timeStyle;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _dateStyle = NSDateIntervalFormatterMediumStyle;
        _timeStyle = NSDateIntervalFormatterMediumStyle;
    }
    return self;
}
- (void)dealloc
{
    [_locale release];
    [_calendar release];
    [_timeZone release];
    [_dateTemplate release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSDateIntervalFormatter *f = [[NSDateIntervalFormatter alloc] init];
    f.locale = _locale;
    f.calendar = _calendar;
    f.timeZone = _timeZone;
    f.dateTemplate = _dateTemplate;
    f.dateStyle = _dateStyle;
    f.timeStyle = _timeStyle;
    return f;
}
#define FERRY_COPY_PROPERTY(type, name, setter, ivar) \
    - (type *)name { return [[ivar retain] autorelease]; } \
    - (void)setter:(type *)v { if (v != ivar) { [ivar release]; ivar = [v copy]; } }
FERRY_COPY_PROPERTY(NSLocale, locale, setLocale, _locale)
FERRY_COPY_PROPERTY(NSCalendar, calendar, setCalendar, _calendar)
FERRY_COPY_PROPERTY(NSTimeZone, timeZone, setTimeZone, _timeZone)
FERRY_COPY_PROPERTY(NSString, dateTemplate, setDateTemplate, _dateTemplate)
#undef FERRY_COPY_PROPERTY
- (NSDateIntervalFormatterStyle)dateStyle { return _dateStyle; }
- (void)setDateStyle:(NSDateIntervalFormatterStyle)s { _dateStyle = s; }
- (NSDateIntervalFormatterStyle)timeStyle { return _timeStyle; }
- (void)setTimeStyle:(NSDateIntervalFormatterStyle)s { _timeStyle = s; }

- (NSDateFormatter *)_formatterWithDate:(BOOL)date time:(BOOL)time
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    if (_locale)
        f.locale = _locale;
    if (_timeZone)
        f.timeZone = _timeZone;
    if (_dateTemplate.length && date)
        [f setLocalizedDateFormatFromTemplate:_dateTemplate];
    else {
        f.dateStyle = date ? (NSDateFormatterStyle)_dateStyle : NSDateFormatterNoStyle;
        f.timeStyle = time ? (NSDateFormatterStyle)_timeStyle : NSDateFormatterNoStyle;
    }
    return f;
}

- (NSString *)stringFromDate:(NSDate *)from toDate:(NSDate *)to
{
    if (!from || !to)
        return @"";
    NSCalendar *cal = [[(_calendar ?: [NSCalendar currentCalendar]) copy] autorelease];
    if (_timeZone)
        cal.timeZone = _timeZone;
    BOOL sameDay = [cal isDate:from inSameDayAsDate:to];
    BOOL hasDate = _dateStyle != NSDateIntervalFormatterNoStyle || _dateTemplate.length;
    BOOL hasTime = _timeStyle != NSDateIntervalFormatterNoStyle && !_dateTemplate.length;
    NSString *dash = @" – ";
    if (!hasDate && !hasTime)
        return @"";
    if (sameDay && hasDate && hasTime) {
        /* "Nov 23, 2026, 9:30 – 10:45 AM": the day once */
        NSDateFormatter *day = [self _formatterWithDate:YES time:NO];
        NSDateFormatter *t = [self _formatterWithDate:NO time:YES];
        if ([from isEqualToDate:to])
            return [NSString stringWithFormat:@"%@, %@", [day stringFromDate:from], [t stringFromDate:from]];
        return [NSString stringWithFormat:@"%@, %@%@%@", [day stringFromDate:from], [t stringFromDate:from], dash,
                                          [t stringFromDate:to]];
    }
    NSDateFormatter *f = [self _formatterWithDate:hasDate time:hasTime];
    NSString *a = [f stringFromDate:from], *b = [f stringFromDate:to];
    if ([a isEqualToString:b])
        return a;
    return [NSString stringWithFormat:@"%@%@%@", a, dash, b];
}

- (NSString *)stringForObjectValue:(id)obj { return nil; }
@end

/* ---- links --------------------------------------------------------------------------------- */

@interface FLinkResult : NSTextCheckingResult {
@public
    NSRange _range;
    NSURL *_url;
}
@end
@implementation FLinkResult
- (void)dealloc
{
    [_url release];
    [super dealloc];
}
- (NSTextCheckingType)resultType { return NSTextCheckingTypeLink; }
- (NSRange)range { return _range; }
- (NSUInteger)numberOfRanges { return 1; }
- (NSURL *)URL { return _url; }
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset
{
    return [NSTextCheckingResult linkCheckingResultWithRange:NSMakeRange(_range.location + offset, _range.length) URL:_url];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSLinkCheckingResult %p>{%lu, %lu}{%@}", (void *)self, (unsigned long)_range.location,
                                      (unsigned long)_range.length, _url];
}
@end

@implementation NSTextCheckingResult (NSTextCheckingResultLink)
- (NSURL *)URL { return nil; }
+ (NSTextCheckingResult *)linkCheckingResultWithRange:(NSRange)range URL:(NSURL *)url
{
    FLinkResult *r = [[FLinkResult alloc] init];
    r->_range = range;
    r->_url = [url copy];
    return [r autorelease];
}
@end

/* A web address with its scheme, one starting www., or a mail address. */
static NSString *const link_pattern =
    @"(?:[a-zA-Z][a-zA-Z0-9+.-]*://|www\\.)[^\\s<>\"]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}";

@implementation NSDataDetector {
    NSTextCheckingTypes _types;
}
+ (instancetype)dataDetectorWithTypes:(NSTextCheckingTypes)types error:(NSError **)error
{
    return [[[self alloc] initWithTypes:types error:error] autorelease];
}
- (instancetype)initWithTypes:(NSTextCheckingTypes)types error:(NSError **)error
{
    if ((self = [super initWithPattern:link_pattern options:0 error:error]))
        _types = types;
    return self;
}
- (NSTextCheckingTypes)checkingTypes { return _types; }

- (void)enumerateMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop))block
{
    if (!(_types & NSTextCheckingTypeLink)) {
        if (options & NSMatchingReportCompletion) {
            BOOL stop = NO;
            block(nil, NSMatchingCompleted, &stop);
        }
        return;
    }
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@".,;:!?)]}'"];
    [super enumerateMatchesInString:string options:options range:range
                         usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags flags, BOOL *stop) {
                           if (!r) {
                               block(nil, flags, stop);
                               return;
                           }
                           NSRange m = r.range;
                           /* a sentence's full stop or a closing bracket isn't part of the link */
                           while (m.length > 1 && [trailing characterIsMember:[string characterAtIndex:NSMaxRange(m) - 1]]) {
                               unichar c = [string characterAtIndex:NSMaxRange(m) - 1];
                               if (c == ')' && [[string substringWithRange:m] rangeOfString:@"("].location != NSNotFound)
                                   break;
                               m.length--;
                           }
                           NSString *text = [string substringWithRange:m];
                           NSString *address = text;
                           if ([text rangeOfString:@"://"].location == NSNotFound)
                               address = [text rangeOfString:@"@"].location != NSNotFound && ![text hasPrefix:@"www."]
                                             ? [@"mailto:" stringByAppendingString:text]
                                             : [@"http://" stringByAppendingString:text];
                           NSURL *url = [NSURL URLWithString:address]
                                            ?: [NSURL URLWithString:[address stringByAddingPercentEncodingWithAllowedCharacters:
                                                                                 [NSCharacterSet URLFragmentAllowedCharacterSet]]];
                           if (url)
                               block([NSTextCheckingResult linkCheckingResultWithRange:m URL:url], flags, stop);
                         }];
}
@end

@implementation NSURL (NSURLResourceSpecifier)
- (NSString *)resourceSpecifier
{
    NSString *s = [self absoluteString];
    NSRange colon = [s rangeOfString:@":"];
    return colon.location == NSNotFound ? s : [s substringFromIndex:colon.location + 1];
}
@end

@implementation NSString (NSLocalizedStandardCompare)
- (NSComparisonResult)localizedStandardCompare:(NSString *)string
{
    return [self compare:string
                 options:NSCaseInsensitiveSearch | NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch];
}
@end

@implementation NSLocale (NSLocaleIdentifierFromComponents)
+ (NSString *)localeIdentifierFromComponents:(NSDictionary *)d
{
    NSMutableString *s = [NSMutableString stringWithString:[d objectForKey:NSLocaleLanguageCode] ?: @""];
    for (NSString *k in @[ NSLocaleScriptCode, NSLocaleCountryCode, NSLocaleVariantCode ]) {
        NSString *v = [d objectForKey:k];
        if (v.length) {
            [s appendString:@"_"];
            [s appendString:v];
        }
    }
    /* the rest are keywords: @calendar=…;currency=… */
    NSMutableArray *keywords = [NSMutableArray array];
    for (NSString *k in [[d allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([k isEqual:NSLocaleLanguageCode] || [k isEqual:NSLocaleScriptCode] || [k isEqual:NSLocaleCountryCode] ||
            [k isEqual:NSLocaleVariantCode] || ![[d objectForKey:k] isKindOfClass:[NSString class]])
            continue;
        [keywords addObject:[NSString stringWithFormat:@"%@=%@", k, [d objectForKey:k]]];
    }
    if (keywords.count)
        [s appendFormat:@"@%@", [keywords componentsJoinedByString:@";"]];
    return s;
}
@end
