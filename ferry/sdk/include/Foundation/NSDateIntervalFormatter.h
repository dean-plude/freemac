/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Newer Foundation names that menu-bar apps such as Itsycal use (freemac
 * 1.232, Ferry 0.56.0): the date interval formatter, a formatter's
 * capitalization context, the data detector for links, a URL's resource
 * specifier and its tags key, the Finder's sort of strings, locale
 * identifiers from their components and the clock's change notification.
 * Written from Apple's public documentation; not Apple's header. Implemented in foundation/NSDateIntervalFormatter.m.
 * Imported by Foundation.h. */
#ifndef _FERRY_NSDATEINTERVALFORMATTER_H_
#define _FERRY_NSDATEINTERVALFORMATTER_H_

/* How a formatted string will be placed, for its capitalization. */
typedef NS_ENUM(NSInteger, NSFormattingContext) {
    NSFormattingContextUnknown = 0,
    NSFormattingContextDynamic = 1,
    NSFormattingContextStandalone = 2,
    NSFormattingContextListItem = 3,
    NSFormattingContextBeginningOfSentence = 4,
    NSFormattingContextMiddleOfSentence = 5,
};

/* Kept; a string beginning a sentence or standing alone starts with a capital. */
@interface NSDateFormatter (NSFormattingContext)
@property NSFormattingContext formattingContext;
@end

typedef NS_ENUM(NSUInteger, NSDateIntervalFormatterStyle) {
    NSDateIntervalFormatterNoStyle = 0,
    NSDateIntervalFormatterShortStyle = 1,
    NSDateIntervalFormatterMediumStyle = 2,
    NSDateIntervalFormatterLongStyle = 3,
    NSDateIntervalFormatterFullStyle = 4,
};

/* Two dates as one range ("9:30 – 10:45 AM", "Nov 23 – 25, 2026"): the
 * date said once when both are on the same day. */
@interface NSDateIntervalFormatter : NSFormatter
@property (copy) NSLocale *locale;
@property (copy) NSCalendar *calendar;
@property (copy) NSTimeZone *timeZone;
@property (copy) NSString *dateTemplate;
@property NSDateIntervalFormatterStyle dateStyle;
@property NSDateIntervalFormatterStyle timeStyle;
- (NSString *)stringFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate;
@end

/* Finds links (web addresses with or without their scheme, and mail
 * addresses), the one kind of data detected for now; asked for other
 * kinds, it finds nothing of them. */
@interface NSDataDetector : NSRegularExpression
+ (instancetype)dataDetectorWithTypes:(NSTextCheckingTypes)checkingTypes error:(NSError **)error;
- (instancetype)initWithTypes:(NSTextCheckingTypes)checkingTypes error:(NSError **)error;
@property (readonly) NSTextCheckingTypes checkingTypes;
@end

@interface NSTextCheckingResult (NSTextCheckingResultLink)
@property (readonly, copy) NSURL *URL;    /* a link's address; nil for other results */
+ (NSTextCheckingResult *)linkCheckingResultWithRange:(NSRange)range URL:(NSURL *)url;
@end

@interface NSURL (NSURLResourceSpecifier)
@property (readonly, copy) NSString *resourceSpecifier;    /* all after the scheme and its colon */
@end
/* A file's Finder tags: this system keeps none, so the value is nil and a
 * value set is kept by nothing, as for the other keys it has no place for. */
FOUNDATION_EXPORT NSString *const NSURLTagNamesKey;

/* As the Finder sorts names: case and accents aside, numbers by value. */
@interface NSString (NSLocalizedStandardCompare)
- (NSComparisonResult)localizedStandardCompare:(NSString *)string;
@end

@interface NSLocale (NSLocaleIdentifierFromComponents)
+ (NSString *)localeIdentifierFromComponents:(NSDictionary<NSString *, NSString *> *)dict;
@end

/* Posted on a Mac when the system's clock is set. Ferry doesn't watch the
 * clock yet, so it is declared for observers and never posted. */
FOUNDATION_EXPORT NSNotificationName const NSSystemClockDidChangeNotification;

#endif
