/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFDate and CFDateFormatter, written for freemac from Apple's
 * public CFDate and CFDateFormatter documentation; not Apple's headers. A
 * CFDateRef is an NSDate and a CFDateFormatterRef an NSDateFormatter, as
 * on a Mac. Included by <CoreFoundation/CoreFoundation.h>;
 * foundation/CFLocale.m. */
#ifndef _FERRY_CFDATE_H_
#define _FERRY_CFDATE_H_

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
extern const CFTimeInterval kCFAbsoluteTimeIntervalSince1904;
CFTypeID CFDateGetTypeID(void);
CFDateRef CFDateCreate(CFAllocatorRef allocator, CFAbsoluteTime at);
CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef theDate);
CFTimeInterval CFDateGetTimeIntervalSinceDate(CFDateRef theDate, CFDateRef otherDate);
CFComparisonResult CFDateCompare(CFDateRef theDate, CFDateRef otherDate, void *context);

typedef struct __CFDateFormatter *CFDateFormatterRef;
typedef CF_ENUM(CFIndex, CFDateFormatterStyle) {
    kCFDateFormatterNoStyle = 0,
    kCFDateFormatterShortStyle = 1,
    kCFDateFormatterMediumStyle = 2,
    kCFDateFormatterLongStyle = 3,
    kCFDateFormatterFullStyle = 4,
};
CFTypeID CFDateFormatterGetTypeID(void);
CFDateFormatterRef CFDateFormatterCreate(CFAllocatorRef allocator, CFLocaleRef locale, CFDateFormatterStyle dateStyle,
                                         CFDateFormatterStyle timeStyle);
CFLocaleRef CFDateFormatterGetLocale(CFDateFormatterRef formatter);
CFDateFormatterStyle CFDateFormatterGetDateStyle(CFDateFormatterRef formatter);
CFDateFormatterStyle CFDateFormatterGetTimeStyle(CFDateFormatterRef formatter);
CFStringRef CFDateFormatterGetFormat(CFDateFormatterRef formatter);
void CFDateFormatterSetFormat(CFDateFormatterRef formatter, CFStringRef formatString);
CFStringRef CFDateFormatterCreateStringWithDate(CFAllocatorRef allocator, CFDateFormatterRef formatter, CFDateRef date);
CFStringRef CFDateFormatterCreateStringWithAbsoluteTime(CFAllocatorRef allocator, CFDateFormatterRef formatter,
                                                        CFAbsoluteTime at);
CFDateRef CFDateFormatterCreateDateFromString(CFAllocatorRef allocator, CFDateFormatterRef formatter,
                                              CFStringRef string, CFRange *rangep);
CFStringRef CFDateFormatterCreateDateFormatFromTemplate(CFAllocatorRef allocator, CFStringRef tmplate,
                                                        CFOptionFlags options, CFLocaleRef locale);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
