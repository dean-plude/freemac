/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: property lists as data, calendars, time zones' names, number
 * formatters, more of the date formatter, bundles, numbers, preferences
 * and URL resource keys (freemac 1.232, Ferry 0.56.0), the calls Qt's core
 * makes on a Mac. Written for freemac from Apple's public Core Foundation
 * documentation; not Apple's header. Each is served from Foundation's file
 * (foundation/CFQtCore.m), on the Foundation class it is bridged to, as on
 * a Mac. Included by <CoreFoundation/CoreFoundation.h>. */
#ifndef _FERRY_CFPROPERTYLIST_H_
#define _FERRY_CFPROPERTYLIST_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
/* ---- property lists --------------------------------------------------------------- */
typedef CF_ENUM(CFIndex, CFPropertyListFormat) {
    kCFPropertyListOpenStepFormat = 1,
    kCFPropertyListXMLFormat_v1_0 = 100,
    kCFPropertyListBinaryFormat_v1_0 = 200,
};
typedef CF_OPTIONS(CFOptionFlags, CFPropertyListMutabilityOptions) {
    kCFPropertyListImmutable = 0,
    kCFPropertyListMutableContainers = 1 << 0,
    kCFPropertyListMutableContainersAndLeaves = 1 << 1,
};
CFDataRef CFPropertyListCreateData(CFAllocatorRef allocator, CFPropertyListRef propertyList,
                                   CFPropertyListFormat format, CFOptionFlags options, CFErrorRef *error);
CFPropertyListRef CFPropertyListCreateWithData(CFAllocatorRef allocator, CFDataRef data, CFOptionFlags options,
                                               CFPropertyListFormat *format, CFErrorRef *error);
Boolean CFPropertyListIsValid(CFPropertyListRef plist, CFPropertyListFormat format);

/* ---- calendars and time zones ------------------------------------------------------- */
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSCalendar) __CFCalendar *CFCalendarRef;
typedef const struct CF_BRIDGED_TYPE(NSTimeZone) __CFTimeZone *CFTimeZoneRef;
CFCalendarRef CFCalendarCopyCurrent(void);
CFIndex CFCalendarGetFirstWeekday(CFCalendarRef calendar);
CFIndex CFCalendarGetMinimumDaysInFirstWeek(CFCalendarRef calendar);
CFTimeZoneRef CFTimeZoneCopySystem(void);
CFTimeZoneRef CFTimeZoneCopyDefault(void);
CFStringRef CFTimeZoneGetName(CFTimeZoneRef tz);

/* ---- what a date formatter knows -------------------------------------------------- */
typedef CFStringRef CFDateFormatterKey;
extern const CFDateFormatterKey kCFDateFormatterAMSymbol;
extern const CFDateFormatterKey kCFDateFormatterPMSymbol;
extern const CFDateFormatterKey kCFDateFormatterMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterShortMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterVeryShortMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterStandaloneMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterShortStandaloneMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterVeryShortStandaloneMonthSymbols;
extern const CFDateFormatterKey kCFDateFormatterWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterShortWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterVeryShortWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterStandaloneWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterShortStandaloneWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterVeryShortStandaloneWeekdaySymbols;
extern const CFDateFormatterKey kCFDateFormatterEraSymbols;
CFTypeRef CFDateFormatterCopyProperty(CFDateFormatterRef formatter, CFDateFormatterKey key);

/* ---- number formatters (NSNumberFormatters) ----------------------------------------- */
typedef struct __CFNumberFormatter *CFNumberFormatterRef;
typedef CF_ENUM(CFIndex, CFNumberFormatterStyle) {
    kCFNumberFormatterNoStyle = 0,
    kCFNumberFormatterDecimalStyle = 1,
    kCFNumberFormatterCurrencyStyle = 2,
    kCFNumberFormatterPercentStyle = 3,
    kCFNumberFormatterScientificStyle = 4,
    kCFNumberFormatterSpellOutStyle = 5,
};
typedef CFStringRef CFNumberFormatterKey;
extern const CFNumberFormatterKey kCFNumberFormatterCurrencyCode;
extern const CFNumberFormatterKey kCFNumberFormatterCurrencySymbol;
extern const CFNumberFormatterKey kCFNumberFormatterDecimalSeparator;
extern const CFNumberFormatterKey kCFNumberFormatterGroupingSeparator;
extern const CFNumberFormatterKey kCFNumberFormatterGroupingSize;
extern const CFNumberFormatterKey kCFNumberFormatterMinusSign;
extern const CFNumberFormatterKey kCFNumberFormatterPlusSign;
extern const CFNumberFormatterKey kCFNumberFormatterPercentSymbol;
CFTypeID CFNumberFormatterGetTypeID(void);
CFNumberFormatterRef CFNumberFormatterCreate(CFAllocatorRef allocator, CFLocaleRef locale,
                                             CFNumberFormatterStyle style);
CFTypeRef CFNumberFormatterCopyProperty(CFNumberFormatterRef formatter, CFNumberFormatterKey key);
void CFNumberFormatterSetProperty(CFNumberFormatterRef formatter, CFNumberFormatterKey key, CFTypeRef value);
CFStringRef CFNumberFormatterGetFormat(CFNumberFormatterRef formatter);
CFStringRef CFNumberFormatterCreateStringWithNumber(CFAllocatorRef allocator, CFNumberFormatterRef formatter,
                                                    CFNumberRef number);
CFStringRef CFNumberFormatterCreateStringWithValue(CFAllocatorRef allocator, CFNumberFormatterRef formatter,
                                                   CFNumberType numberType, const void *valuePtr);

/* ---- numbers, data and strings ------------------------------------------------------ */
CFNumberType CFNumberGetType(CFNumberRef number);
Boolean CFNumberIsFloatType(CFNumberRef number);
CFIndex CFNumberGetByteSize(CFNumberRef number);
/* Ferry copies the bytes, and frees nothing: it can't tell kCFAllocatorNull
 * from the default allocator */
CFDataRef CFDataCreateWithBytesNoCopy(CFAllocatorRef allocator, const UInt8 *bytes, CFIndex length,
                                      CFAllocatorRef bytesDeallocator);
CFStringRef CFStringCreateWithFileSystemRepresentation(CFAllocatorRef alloc, const char *buffer);
CFStringRef CFCopyTypeIDDescription(CFTypeID type_id);

/* ---- bundles and preferences ---------------------------------------------------- */
CFArrayRef CFBundleGetAllBundles(void);
CFURLRef CFBundleCopyPrivateFrameworksURL(CFBundleRef bundle);
CFURLRef CFBundleCopySharedFrameworksURL(CFBundleRef bundle);
void CFBundleGetPackageInfo(CFBundleRef bundle, UInt32 *packageType, UInt32 *packageCreator);
Boolean CFBundleGetPackageInfoInDirectory(CFURLRef url, UInt32 *packageType, UInt32 *packageCreator);
void CFPreferencesSetMultiple(CFDictionaryRef keysToSet, CFArrayRef keysToRemove, CFStringRef applicationID,
                              CFStringRef userName, CFStringRef hostName);

/* ---- URL resource keys and bookmarks ---------------------------------------------- */
extern const CFStringRef kCFURLNameKey;
extern const CFStringRef kCFURLLocalizedNameKey;
extern const CFStringRef kCFURLIsRegularFileKey;
extern const CFStringRef kCFURLIsDirectoryKey;
extern const CFStringRef kCFURLIsSymbolicLinkKey;
extern const CFStringRef kCFURLIsPackageKey;
extern const CFStringRef kCFURLIsHiddenKey;
extern const CFStringRef kCFURLIsAliasFileKey;
extern const CFStringRef kCFURLFileSizeKey;
extern const CFStringRef kCFURLContentModificationDateKey;
extern const CFStringRef kCFURLCreationDateKey;
/* a volume's, answered from statvfs and the mount table */
extern const CFStringRef kCFURLVolumeURLKey;
extern const CFStringRef kCFURLVolumeNameKey;
extern const CFStringRef kCFURLVolumeLocalizedNameKey;
extern const CFStringRef kCFURLVolumeTotalCapacityKey;
extern const CFStringRef kCFURLVolumeAvailableCapacityKey;
extern const CFStringRef kCFURLVolumeIsReadOnlyKey;
extern const CFStringRef kCFURLVolumeSupportsCaseSensitiveNamesKey;
extern const CFStringRef kCFURLVolumeIsLocalKey;
extern const CFStringRef kCFURLVolumeIsRemovableKey;
CFDictionaryRef CFURLCopyResourcePropertiesForKeys(CFURLRef url, CFArrayRef keys, CFErrorRef *error);
typedef CF_OPTIONS(CFOptionFlags, CFURLBookmarkResolutionOptions) {
    kCFBookmarkResolutionWithoutUIMask = (1UL << 8),
    kCFBookmarkResolutionWithoutMountingMask = (1UL << 9),
};
typedef CFOptionFlags CFURLBookmarkCreationOptions;
CFDataRef CFURLCreateBookmarkData(CFAllocatorRef allocator, CFURLRef url, CFURLBookmarkCreationOptions options,
                                  CFArrayRef resourcePropertiesToInclude, CFURLRef relativeToURL, CFErrorRef *error);
CFDataRef CFURLCreateBookmarkDataFromFile(CFAllocatorRef allocator, CFURLRef fileURL, CFErrorRef *errorRef);
CFURLRef CFURLCreateByResolvingBookmarkData(CFAllocatorRef allocator, CFDataRef bookmark,
                                           CFURLBookmarkResolutionOptions options, CFURLRef relativeToURL,
                                           CFArrayRef resourcePropertiesToInclude, Boolean *isStale,
                                           CFErrorRef *error);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
