/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Core Foundation calls Qt's core makes on a Mac and Ferry didn't have
 * (freemac 1.232, Ferry 0.56.0): property lists as data, calendars, time
 * zones' names, number formatters, a date formatter's symbols, every
 * bundle, a number's type, preferences set many at once, URL resource
 * keys and bookmarks, the mounted volumes, and CFNetwork's proxy settings.
 * Written for freemac from Apple's public Core Foundation documentation
 * (sdk/include/CoreFoundation/CFPropertyList.h, CFURLEnumerator.h and
 * CFNetwork/CFNetwork.h). Each CF type is the Foundation class it is
 * bridged to on a Mac, so the calls ask that class. OBS Studio is built on
 * Qt, and these let QtCore start.
 */
#import "FInternal.h"
#include <CoreFoundation/CFURLEnumerator.h>
#include <CFNetwork/CFNetwork.h>
#include <sys/mount.h>
#include <string.h>

#define OBJ(x) ((id)(x))
#define FERRY_TYPE_NUMBER_FORMATTER 0x4652001b
#define FERRY_TYPE_URL_ENUMERATOR 0x4652001c

/* ---- property lists ---------------------------------------------------------------- */

CFDataRef CFPropertyListCreateData(CFAllocatorRef allocator, CFPropertyListRef propertyList,
                                   CFPropertyListFormat format, CFOptionFlags options, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    NSError *e = nil;
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:OBJ(propertyList)
                                                           format:(NSPropertyListFormat)format
                                                          options:0
                                                            error:&e];
    if (!d && error && e)
        *error = (CFErrorRef)[e retain];
    return (CFDataRef)[d retain];
}

CFPropertyListRef CFPropertyListCreateWithData(CFAllocatorRef allocator, CFDataRef data, CFOptionFlags options,
                                               CFPropertyListFormat *format, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    if (!data)
        return NULL;
    NSError *e = nil;
    NSPropertyListFormat f = 0;
    id plist = [NSPropertyListSerialization propertyListWithData:OBJ(data)
                                                         options:(NSPropertyListReadOptions)options
                                                          format:&f
                                                           error:&e];
    if (format)
        *format = (CFPropertyListFormat)f;
    if (!plist && error && e)
        *error = (CFErrorRef)[e retain];
    return (CFPropertyListRef)[plist retain];
}

Boolean CFPropertyListIsValid(CFPropertyListRef plist, CFPropertyListFormat format)
{
    return plist && [NSPropertyListSerialization propertyList:OBJ(plist)
                                            isValidForFormat:(NSPropertyListFormat)format];
}

/* ---- calendars and time zones ------------------------------------------------------ */

CFCalendarRef CFCalendarCopyCurrent(void) { return (CFCalendarRef)[[NSCalendar currentCalendar] retain]; }
CFIndex CFCalendarGetFirstWeekday(CFCalendarRef c) { return c ? (CFIndex)[OBJ(c) firstWeekday] : 1; }
CFIndex CFCalendarGetMinimumDaysInFirstWeek(CFCalendarRef c)
{
    return c ? (CFIndex)[OBJ(c) minimumDaysInFirstWeek] : 1;
}
CFTimeZoneRef CFTimeZoneCopySystem(void) { return (CFTimeZoneRef)[[NSTimeZone systemTimeZone] retain]; }
CFTimeZoneRef CFTimeZoneCopyDefault(void) { return (CFTimeZoneRef)[[NSTimeZone defaultTimeZone] retain]; }
CFStringRef CFTimeZoneGetName(CFTimeZoneRef tz) { return tz ? (CFStringRef)[OBJ(tz) name] : NULL; }

/* ---- a date formatter's symbols --------------------------------------------------- */

#define DF_KEY(name, string) const CFDateFormatterKey name = (CFStringRef)@string;
DF_KEY(kCFDateFormatterAMSymbol, "kCFDateFormatterAMSymbolKey")
DF_KEY(kCFDateFormatterPMSymbol, "kCFDateFormatterPMSymbolKey")
DF_KEY(kCFDateFormatterMonthSymbols, "kCFDateFormatterMonthSymbolsKey")
DF_KEY(kCFDateFormatterShortMonthSymbols, "kCFDateFormatterShortMonthSymbolsKey")
DF_KEY(kCFDateFormatterVeryShortMonthSymbols, "kCFDateFormatterVeryShortMonthSymbolsKey")
DF_KEY(kCFDateFormatterStandaloneMonthSymbols, "kCFDateFormatterStandaloneMonthSymbolsKey")
DF_KEY(kCFDateFormatterShortStandaloneMonthSymbols, "kCFDateFormatterShortStandaloneMonthSymbolsKey")
DF_KEY(kCFDateFormatterVeryShortStandaloneMonthSymbols, "kCFDateFormatterVeryShortStandaloneMonthSymbolsKey")
DF_KEY(kCFDateFormatterWeekdaySymbols, "kCFDateFormatterWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterShortWeekdaySymbols, "kCFDateFormatterShortWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterVeryShortWeekdaySymbols, "kCFDateFormatterVeryShortWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterStandaloneWeekdaySymbols, "kCFDateFormatterStandaloneWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterShortStandaloneWeekdaySymbols, "kCFDateFormatterShortStandaloneWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterVeryShortStandaloneWeekdaySymbols,
       "kCFDateFormatterVeryShortStandaloneWeekdaySymbolsKey")
DF_KEY(kCFDateFormatterEraSymbols, "kCFDateFormatterEraSymbolsKey")
#undef DF_KEY

CFTypeRef CFDateFormatterCopyProperty(CFDateFormatterRef formatter, CFDateFormatterKey key)
{
    if (!formatter || !key)
        return NULL;
    NSDateFormatter *f = OBJ(formatter);
    static const struct {
        const CFDateFormatterKey *key;
        const char *selector;
    } map[] = {
        {&kCFDateFormatterAMSymbol, "AMSymbol"},
        {&kCFDateFormatterPMSymbol, "PMSymbol"},
        {&kCFDateFormatterMonthSymbols, "monthSymbols"},
        {&kCFDateFormatterShortMonthSymbols, "shortMonthSymbols"},
        {&kCFDateFormatterVeryShortMonthSymbols, "veryShortMonthSymbols"},
        {&kCFDateFormatterStandaloneMonthSymbols, "standaloneMonthSymbols"},
        {&kCFDateFormatterShortStandaloneMonthSymbols, "shortStandaloneMonthSymbols"},
        {&kCFDateFormatterVeryShortStandaloneMonthSymbols, "veryShortStandaloneMonthSymbols"},
        {&kCFDateFormatterWeekdaySymbols, "weekdaySymbols"},
        {&kCFDateFormatterShortWeekdaySymbols, "shortWeekdaySymbols"},
        {&kCFDateFormatterVeryShortWeekdaySymbols, "veryShortWeekdaySymbols"},
        {&kCFDateFormatterStandaloneWeekdaySymbols, "standaloneWeekdaySymbols"},
        {&kCFDateFormatterShortStandaloneWeekdaySymbols, "shortStandaloneWeekdaySymbols"},
        {&kCFDateFormatterVeryShortStandaloneWeekdaySymbols, "veryShortStandaloneWeekdaySymbols"},
        {&kCFDateFormatterEraSymbols, "eraSymbols"},
    };
    for (size_t i = 0; i < sizeof map / sizeof map[0]; i++)
        if ([OBJ(*map[i].key) isEqualToString:OBJ(key)]) {
            SEL s = sel_registerName(map[i].selector);
            if (![f respondsToSelector:s])
                return NULL;
            return (CFTypeRef)[[f performSelector:s] retain];
        }
    return NULL;
}

/* ---- number formatters ----------------------------------------------------------- */

#define NF_KEY(name, string) const CFNumberFormatterKey name = (CFStringRef)@string;
NF_KEY(kCFNumberFormatterCurrencyCode, "kCFNumberFormatterCurrencyCodeKey")
NF_KEY(kCFNumberFormatterCurrencySymbol, "kCFNumberFormatterCurrencySymbolKey")
NF_KEY(kCFNumberFormatterDecimalSeparator, "kCFNumberFormatterDecimalSeparatorKey")
NF_KEY(kCFNumberFormatterGroupingSeparator, "kCFNumberFormatterGroupingSeparatorKey")
NF_KEY(kCFNumberFormatterGroupingSize, "kCFNumberFormatterGroupingSizeKey")
NF_KEY(kCFNumberFormatterMinusSign, "kCFNumberFormatterMinusSignKey")
NF_KEY(kCFNumberFormatterPlusSign, "kCFNumberFormatterPlusSignKey")
NF_KEY(kCFNumberFormatterPercentSymbol, "kCFNumberFormatterPercentSymbolKey")
#undef NF_KEY

@implementation NSNumberFormatter (FerryCFNumberFormatter)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_NUMBER_FORMATTER; }
@end

CFTypeID CFNumberFormatterGetTypeID(void) { return FERRY_TYPE_NUMBER_FORMATTER; }

CFNumberFormatterRef CFNumberFormatterCreate(CFAllocatorRef allocator, CFLocaleRef locale,
                                             CFNumberFormatterStyle style)
{
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    if (locale)
        [f setLocale:OBJ(locale)];
    [f setNumberStyle:(NSNumberFormatterStyle)style];
    return (CFNumberFormatterRef)f;
}

static BOOL nf_is(CFNumberFormatterKey key, CFNumberFormatterKey known) { return [OBJ(key) isEqualToString:OBJ(known)]; }

CFTypeRef CFNumberFormatterCopyProperty(CFNumberFormatterRef formatter, CFNumberFormatterKey key)
{
    if (!formatter || !key)
        return NULL;
    NSNumberFormatter *f = OBJ(formatter);
    id v = nil;
    if (nf_is(key, kCFNumberFormatterCurrencyCode))
        v = [f currencyCode];
    else if (nf_is(key, kCFNumberFormatterCurrencySymbol))
        v = [f currencySymbol];
    else if (nf_is(key, kCFNumberFormatterDecimalSeparator))
        v = [f decimalSeparator];
    else if (nf_is(key, kCFNumberFormatterGroupingSeparator))
        v = [f groupingSeparator];
    else if (nf_is(key, kCFNumberFormatterGroupingSize))
        v = [NSNumber numberWithUnsignedInteger:[f groupingSize]];
    else if (nf_is(key, kCFNumberFormatterMinusSign))
        v = [f minusSign];
    else if (nf_is(key, kCFNumberFormatterPlusSign))
        v = [f plusSign];
    else if (nf_is(key, kCFNumberFormatterPercentSymbol))
        v = [f percentSymbol];
    return (CFTypeRef)[v retain];
}

void CFNumberFormatterSetProperty(CFNumberFormatterRef formatter, CFNumberFormatterKey key, CFTypeRef value)
{
    if (!formatter || !key)
        return;
    NSNumberFormatter *f = OBJ(formatter);
    id v = OBJ(value);
    if (nf_is(key, kCFNumberFormatterCurrencyCode))
        [f setCurrencyCode:v];
    else if (nf_is(key, kCFNumberFormatterCurrencySymbol))
        [f setCurrencySymbol:v];
    else if (nf_is(key, kCFNumberFormatterDecimalSeparator))
        [f setDecimalSeparator:v];
    else if (nf_is(key, kCFNumberFormatterGroupingSeparator))
        [f setGroupingSeparator:v];
    else if (nf_is(key, kCFNumberFormatterGroupingSize))
        [f setGroupingSize:[v unsignedIntegerValue]];
    else if (nf_is(key, kCFNumberFormatterMinusSign))
        [f setMinusSign:v];
    else if (nf_is(key, kCFNumberFormatterPlusSign))
        [f setPlusSign:v];
    else if (nf_is(key, kCFNumberFormatterPercentSymbol))
        [f setPercentSymbol:v];
}

CFStringRef CFNumberFormatterGetFormat(CFNumberFormatterRef formatter)
{
    return formatter ? (CFStringRef)[OBJ(formatter) positiveFormat] : NULL;
}

CFStringRef CFNumberFormatterCreateStringWithNumber(CFAllocatorRef allocator, CFNumberFormatterRef formatter,
                                                    CFNumberRef number)
{
    if (!formatter || !number)
        return NULL;
    return (CFStringRef)[[OBJ(formatter) stringFromNumber:OBJ(number)] copy];
}

CFStringRef CFNumberFormatterCreateStringWithValue(CFAllocatorRef allocator, CFNumberFormatterRef formatter,
                                                   CFNumberType numberType, const void *valuePtr)
{
    if (!formatter || !valuePtr)
        return NULL;
    CFNumberRef n = CFNumberCreate(allocator, numberType, valuePtr);
    CFStringRef s = CFNumberFormatterCreateStringWithNumber(allocator, formatter, n);
    CFRelease(n);
    return s;
}

/* ---- numbers, data and strings --------------------------------------------------- */

/* The type an NSNumber keeps, named as CFNumberCreate takes it. */
CFNumberType CFNumberGetType(CFNumberRef number)
{
    const char *t = number ? [OBJ(number) objCType] : "q";
    switch (t ? t[0] : 'q') {
    case 'c':
    case 'C':
    case 'B': return kCFNumberSInt8Type;
    case 's':
    case 'S': return kCFNumberSInt16Type;
    case 'i':
    case 'I': return kCFNumberSInt32Type;
    case 'f': return kCFNumberFloat32Type;
    case 'd': return kCFNumberFloat64Type;
    default: return kCFNumberSInt64Type;
    }
}

Boolean CFNumberIsFloatType(CFNumberRef number)
{
    CFNumberType t = CFNumberGetType(number);
    return t == kCFNumberFloat32Type || t == kCFNumberFloat64Type;
}

CFIndex CFNumberGetByteSize(CFNumberRef number)
{
    switch (CFNumberGetType(number)) {
    case kCFNumberSInt8Type: return 1;
    case kCFNumberSInt16Type: return 2;
    case kCFNumberSInt32Type:
    case kCFNumberFloat32Type: return 4;
    default: return 8;
    }
}

/* kCFAllocatorNull is NULL here, like the default allocator, so Ferry can't
 * tell whether the bytes may be freed: it copies them and frees nothing. */
CFDataRef CFDataCreateWithBytesNoCopy(CFAllocatorRef allocator, const UInt8 *bytes, CFIndex length,
                                      CFAllocatorRef bytesDeallocator)
{
    return CFDataCreate(allocator, bytes, length);
}

CFStringRef CFStringCreateWithFileSystemRepresentation(CFAllocatorRef alloc, const char *buffer)
{
    if (!buffer)
        return NULL;
    return (CFStringRef)[[[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer
                                                                                     length:strlen(buffer)] copy];
}

CFStringRef CFCopyTypeIDDescription(CFTypeID type_id)
{
    static const struct {
        CFTypeID id;
        const char *name;
    } names[] = {
        {0x46520004, "CFRunLoopTimer"},     {0x46520010, "CFArray"},  {0x46520011, "CFDictionary"},
        {0x46520012, "CFString"},           {0x46520013, "CFURL"},    {0x46520014, "CFUUID"},
        {0x46520018, "CFDateFormatter"},    {0x46520019, "CFDate"},   {0x4652001a, "CFError"},
        {FERRY_TYPE_NUMBER_FORMATTER, "CFNumberFormatter"},
        {FERRY_TYPE_URL_ENUMERATOR, "CFURLEnumerator"},
    };
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++)
        if (names[i].id == type_id)
            return (CFStringRef)[[NSString alloc] initWithUTF8String:names[i].name];
    /* a type that isn't one of Ferry's numbers is a class (CFGetTypeID) */
    if (type_id > 0xffffffffu)
        return (CFStringRef)[NSStringFromClass((Class)type_id) copy];
    return (CFStringRef)[[NSString alloc] initWithFormat:@"<CFType %lu>", (unsigned long)type_id];
}

/* ---- bundles and preferences ---------------------------------------------------- */

CFArrayRef CFBundleGetAllBundles(void)
{
    /* the array is kept, as on a Mac, which owns what it returns here */
    static NSArray *last;
    NSArray *now = [[NSBundle allBundles] retain];
    [last release];
    last = now;
    return (CFArrayRef)last;
}

CFURLRef FerryBundleRelativeURL(CFBundleRef bundle, NSURL *folder);
CFURLRef CFBundleCopyPrivateFrameworksURL(CFBundleRef bundle)
{
    return bundle ? FerryBundleRelativeURL(bundle, [OBJ(bundle) privateFrameworksURL]) : NULL;
}
CFURLRef CFBundleCopySharedFrameworksURL(CFBundleRef bundle)
{
    return bundle ? FerryBundleRelativeURL(bundle, [OBJ(bundle) sharedFrameworksURL]) : NULL;
}

static UInt32 four_cc(id s)
{
    if (![s isKindOfClass:[NSString class]] || [s length] != 4)
        return 0;
    const char *c = [s UTF8String];
    if (!c || strlen(c) != 4)
        return 0;
    return ((UInt32)(unsigned char)c[0] << 24) | ((UInt32)(unsigned char)c[1] << 16) |
           ((UInt32)(unsigned char)c[2] << 8) | (UInt32)(unsigned char)c[3];
}

/* The type and creator from the bundle's Info.plist, or 'BNDL' and '????'. */
static void package_info(NSDictionary *info, UInt32 *type, UInt32 *creator)
{
    UInt32 t = four_cc([info objectForKey:@"CFBundlePackageType"]);
    UInt32 c = four_cc([info objectForKey:@"CFBundleSignature"]);
    if (type)
        *type = t ? t : 0x424E444C; /* 'BNDL' */
    if (creator)
        *creator = c ? c : 0x3F3F3F3F; /* '????' */
}

void CFBundleGetPackageInfo(CFBundleRef bundle, UInt32 *packageType, UInt32 *packageCreator)
{
    package_info(bundle ? [OBJ(bundle) infoDictionary] : nil, packageType, packageCreator);
}

Boolean CFBundleGetPackageInfoInDirectory(CFURLRef url, UInt32 *packageType, UInt32 *packageCreator)
{
    if (!url)
        return false;
    NSString *path = [OBJ(url) path];
    NSDictionary *info = [NSDictionary
        dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if (!info)
        info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    if (!info)
        return false;
    package_info(info, packageType, packageCreator);
    return true;
}

void CFPreferencesSetMultiple(CFDictionaryRef keysToSet, CFArrayRef keysToRemove, CFStringRef applicationID,
                              CFStringRef userName, CFStringRef hostName)
{
    for (id k in OBJ(keysToSet))
        CFPreferencesSetValue((CFStringRef)k, (CFPropertyListRef)[OBJ(keysToSet) objectForKey:k], applicationID,
                              userName, hostName);
    for (id k in OBJ(keysToRemove))
        CFPreferencesSetValue((CFStringRef)k, NULL, applicationID, userName, hostName);
}

/* ---- URL resource keys, volumes and bookmarks --------------------------------------- */

/* The same strings as NSURL's keys (NSFileAccess.m), as on a Mac. */
#define URL_KEY(name, string) const CFStringRef name = (CFStringRef)@string;
URL_KEY(kCFURLNameKey, "NSURLNameKey")
URL_KEY(kCFURLLocalizedNameKey, "NSURLLocalizedNameKey")
URL_KEY(kCFURLIsRegularFileKey, "NSURLIsRegularFileKey")
URL_KEY(kCFURLIsDirectoryKey, "NSURLIsDirectoryKey")
URL_KEY(kCFURLIsSymbolicLinkKey, "NSURLIsSymbolicLinkKey")
URL_KEY(kCFURLIsPackageKey, "NSURLIsPackageKey")
URL_KEY(kCFURLIsHiddenKey, "NSURLIsHiddenKey")
URL_KEY(kCFURLIsAliasFileKey, "NSURLIsAliasFileKey")
URL_KEY(kCFURLFileSizeKey, "NSURLFileSizeKey")
URL_KEY(kCFURLContentModificationDateKey, "NSURLContentModificationDateKey")
URL_KEY(kCFURLCreationDateKey, "NSURLCreationDateKey")
URL_KEY(kCFURLVolumeURLKey, "NSURLVolumeURLKey")
URL_KEY(kCFURLVolumeNameKey, "NSURLVolumeNameKey")
URL_KEY(kCFURLVolumeLocalizedNameKey, "NSURLVolumeLocalizedNameKey")
URL_KEY(kCFURLVolumeTotalCapacityKey, "NSURLVolumeTotalCapacityKey")
URL_KEY(kCFURLVolumeAvailableCapacityKey, "NSURLVolumeAvailableCapacityKey")
URL_KEY(kCFURLVolumeIsReadOnlyKey, "NSURLVolumeIsReadOnlyKey")
URL_KEY(kCFURLVolumeSupportsCaseSensitiveNamesKey, "NSURLVolumeSupportsCaseSensitiveNamesKey")
URL_KEY(kCFURLVolumeIsLocalKey, "NSURLVolumeIsLocalKey")
URL_KEY(kCFURLVolumeIsRemovableKey, "NSURLVolumeIsRemovableKey")
#undef URL_KEY

/* The name a volume shows: the system disk's is the machine's, as in the
 * Finder's sidebar; any other's is its mount point's last part. */
static NSString *volume_name(NSString *mountPoint)
{
    if ([mountPoint isEqualToString:@"/"])
        return @"Macintosh HD";
    return [mountPoint lastPathComponent];
}

/* A volume key's value from statfs, or nil when the key isn't a volume's. */
id FVolumeResourceValue(NSString *path, NSString *key, BOOL *known)
{
    *known = [key hasPrefix:@"NSURLVolume"] && ![key isEqualToString:@"NSURLVolumeIdentifierKey"];
    if (!*known)
        return nil;
    struct statfs s;
    if (statfs([path fileSystemRepresentation], &s) != 0)
        return nil;
    NSString *mount = [NSString stringWithUTF8String:s.f_mntonname];
    if (![mount length])
        mount = @"/";
    unsigned long long block = s.f_bsize ? s.f_bsize : 512;
    if ([key isEqualToString:OBJ(kCFURLVolumeURLKey)])
        return [NSURL fileURLWithPath:mount isDirectory:YES];
    if ([key isEqualToString:OBJ(kCFURLVolumeNameKey)] || [key isEqualToString:OBJ(kCFURLVolumeLocalizedNameKey)])
        return volume_name(mount);
    if ([key isEqualToString:OBJ(kCFURLVolumeTotalCapacityKey)])
        return [NSNumber numberWithUnsignedLongLong:s.f_blocks * block];
    if ([key isEqualToString:OBJ(kCFURLVolumeAvailableCapacityKey)])
        return [NSNumber numberWithUnsignedLongLong:s.f_bavail * block];
    if ([key isEqualToString:OBJ(kCFURLVolumeIsReadOnlyKey)])
        return [NSNumber numberWithBool:(s.f_flags & MNT_RDONLY) != 0];
    if ([key isEqualToString:OBJ(kCFURLVolumeSupportsCaseSensitiveNamesKey)]) {
        /* the disks a PC formats for Windows ignore case; this system's own don't */
        const char *t = s.f_fstypename;
        BOOL folds = !strcmp(t, "msdos") || !strcmp(t, "vfat") || !strcmp(t, "exfat") || !strcmp(t, "ntfs") ||
                     !strcmp(t, "ntfs3") || !strcmp(t, "fuseblk");
        return [NSNumber numberWithBool:!folds];
    }
    if ([key isEqualToString:OBJ(kCFURLVolumeIsLocalKey)])
        return [NSNumber numberWithBool:(s.f_flags & MNT_LOCAL) != 0];
    if ([key isEqualToString:OBJ(kCFURLVolumeIsRemovableKey)])
        return [NSNumber numberWithBool:[mount hasPrefix:@"/media/"] || [mount hasPrefix:@"/run/media/"]];
    return nil;
}

CFDictionaryRef CFURLCopyResourcePropertiesForKeys(CFURLRef url, CFArrayRef keys, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    if (!url)
        return NULL;
    NSURL *u = OBJ(url);
    NSMutableDictionary *out = [[NSMutableDictionary alloc] init];
    for (NSString *k in OBJ(keys)) {
        BOOL known;
        id v = [u isFileURL] ? FVolumeResourceValue([u path], k, &known) : nil;
        if (![u isFileURL])
            known = NO;
        if (!known) {
            NSError *e = nil;
            if (![u getResourceValue:&v forKey:k error:&e]) {
                if (error && e)
                    *error = (CFErrorRef)[e retain];
                [out release];
                return NULL;
            }
        }
        if (v)
            [out setObject:v forKey:k];
    }
    return (CFDictionaryRef)out;
}

CFDataRef CFURLCreateBookmarkData(CFAllocatorRef allocator, CFURLRef url, CFURLBookmarkCreationOptions options,
                                  CFArrayRef resourcePropertiesToInclude, CFURLRef relativeToURL, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    if (!url)
        return NULL;
    NSError *e = nil;
    NSData *d = [OBJ(url) bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options
                   includingResourceValuesForKeys:OBJ(resourcePropertiesToInclude)
                                    relativeToURL:OBJ(relativeToURL)
                                            error:&e];
    if (!d && error && e)
        *error = (CFErrorRef)[e retain];
    return (CFDataRef)[d retain];
}

/* An alias file is a bookmark written to disk (NSURL's
 * writeBookmarkData:toURL:), so this reads it back. */
CFDataRef CFURLCreateBookmarkDataFromFile(CFAllocatorRef allocator, CFURLRef fileURL, CFErrorRef *errorRef)
{
    if (errorRef)
        *errorRef = NULL;
    if (!fileURL)
        return NULL;
    NSError *e = nil;
    NSData *d = [NSData dataWithContentsOfURL:OBJ(fileURL) options:0 error:&e];
    if (!d && errorRef && e)
        *errorRef = (CFErrorRef)[e retain];
    return (CFDataRef)[d retain];
}

CFURLRef CFURLCreateByResolvingBookmarkData(CFAllocatorRef allocator, CFDataRef bookmark,
                                           CFURLBookmarkResolutionOptions options, CFURLRef relativeToURL,
                                           CFArrayRef resourcePropertiesToInclude, Boolean *isStale,
                                           CFErrorRef *error)
{
    if (error)
        *error = NULL;
    if (!bookmark)
        return NULL;
    BOOL stale = NO;
    NSError *e = nil;
    NSURL *u = [NSURL URLByResolvingBookmarkData:OBJ(bookmark)
                                         options:(NSURLBookmarkResolutionOptions)options
                                   relativeToURL:OBJ(relativeToURL)
                             bookmarkDataIsStale:&stale
                                           error:&e];
    if (isStale)
        *isStale = stale;
    if (!u && error && e)
        *error = (CFErrorRef)[e retain];
    return (CFURLRef)[u retain];
}

/* ---- the mounted volumes ---------------------------------------------------------- */

@interface FCFURLEnumerator : NSObject {
@public
    NSArray *_urls;
    NSUInteger _next;
}
@end
@implementation FCFURLEnumerator
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_URL_ENUMERATOR; }
- (void)dealloc
{
    [_urls release];
    [super dealloc];
}
@end

CFTypeID CFURLEnumeratorGetTypeID(void) { return FERRY_TYPE_URL_ENUMERATOR; }

/* /proc/self/mounts writes a space in a mount point as \040, and so on. */
static NSString *unescape_mount(NSString *s)
{
    if ([s rangeOfString:@"\\"].location == NSNotFound)
        return s;
    const char *c = [s UTF8String];
    size_t n = strlen(c);
    char *out = malloc(n + 1), *o = out;
    for (size_t i = 0; i < n; i++)
        if (c[i] == '\\' && i + 3 < n + 0 && c[i + 1] >= '0' && c[i + 1] <= '7') {
            *o++ = (char)(((c[i + 1] - '0') << 6) | ((c[i + 2] - '0') << 3) | (c[i + 3] - '0'));
            i += 3;
        } else
            *o++ = c[i];
    *o = 0;
    NSString *r = [NSString stringWithUTF8String:out];
    free(out);
    return r ? r : s;
}

/* The volumes that hold files: the system disk, and each disk, stick or
 * card this system has mounted, as a Mac lists them (not /proc and the
 * like). */
static NSArray *mounted_volumes(BOOL skipInvisibles)
{
    static const char *const disk_types[] = {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "vfat", "msdos",
                                             "exfat", "ntfs", "ntfs3", "fuseblk", "iso9660", "udf", "hfsplus",
                                             "apfs", NULL};
    NSMutableArray *out = [NSMutableArray arrayWithObject:[NSURL fileURLWithPath:@"/" isDirectory:YES]];
    NSString *table = [NSString stringWithContentsOfFile:@"/proc/self/mounts" encoding:NSUTF8StringEncoding error:NULL];
    for (NSString *line in [table componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if ([f count] < 3)
            continue;
        NSString *mount = unescape_mount([f objectAtIndex:1]);
        const char *type = [[f objectAtIndex:2] UTF8String];
        BOOL disk = NO;
        for (int i = 0; disk_types[i]; i++)
            disk = disk || !strcmp(type, disk_types[i]);
        if (!disk || [mount isEqualToString:@"/"] || [mount hasPrefix:@"/boot"])
            continue;
        if (skipInvisibles && [[mount lastPathComponent] hasPrefix:@"."])
            continue;
        NSURL *u = [NSURL fileURLWithPath:mount isDirectory:YES];
        if (![out containsObject:u])
            [out addObject:u];
    }
    return out;
}

CFURLEnumeratorRef CFURLEnumeratorCreateForMountedVolumes(CFAllocatorRef alloc, CFURLEnumeratorOptions option,
                                                          CFArrayRef propertyKeys)
{
    FCFURLEnumerator *e = [[FCFURLEnumerator alloc] init];
    e->_urls = [mounted_volumes((option & kCFURLEnumeratorSkipInvisibles) != 0) retain];
    return (CFURLEnumeratorRef)e;
}

CFURLEnumeratorResult CFURLEnumeratorGetNextURL(CFURLEnumeratorRef enumerator, CFURLRef *url, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    FCFURLEnumerator *e = OBJ(enumerator);
    if (!e || e->_next >= [e->_urls count]) {
        if (url)
            *url = NULL;
        return kCFURLEnumeratorEnd;
    }
    /* the URL belongs to the enumerator, as on a Mac */
    if (url)
        *url = (CFURLRef)[e->_urls objectAtIndex:e->_next];
    e->_next++;
    return kCFURLEnumeratorSuccess;
}

/* ---- CFNetwork's proxies --------------------------------------------------------- */

#define PROXY_KEY(name, string) const CFStringRef name = (CFStringRef)@string;
PROXY_KEY(kCFNetworkProxiesFTPEnable, "FTPEnable")
PROXY_KEY(kCFNetworkProxiesFTPPort, "FTPPort")
PROXY_KEY(kCFNetworkProxiesFTPProxy, "FTPProxy")
PROXY_KEY(kCFNetworkProxiesSOCKSEnable, "SOCKSEnable")
PROXY_KEY(kCFNetworkProxiesSOCKSPort, "SOCKSPort")
PROXY_KEY(kCFNetworkProxiesSOCKSProxy, "SOCKSProxy")
PROXY_KEY(kCFNetworkProxiesExcludeSimpleHostnames, "ExcludeSimpleHostnames")
PROXY_KEY(kCFProxyTypeKey, "kCFProxyTypeKey")
PROXY_KEY(kCFProxyHostNameKey, "kCFProxyHostNameKey")
PROXY_KEY(kCFProxyPortNumberKey, "kCFProxyPortNumberKey")
PROXY_KEY(kCFProxyUsernameKey, "kCFProxyUsernameKey")
PROXY_KEY(kCFProxyPasswordKey, "kCFProxyPasswordKey")
PROXY_KEY(kCFProxyAutoConfigurationURLKey, "kCFProxyAutoConfigurationURLKey")
PROXY_KEY(kCFProxyTypeNone, "kCFProxyTypeNone")
PROXY_KEY(kCFProxyTypeHTTP, "kCFProxyTypeHTTP")
PROXY_KEY(kCFProxyTypeHTTPS, "kCFProxyTypeHTTPS")
PROXY_KEY(kCFProxyTypeFTP, "kCFProxyTypeFTP")
PROXY_KEY(kCFProxyTypeSOCKS, "kCFProxyTypeSOCKS")
PROXY_KEY(kCFProxyTypeAutoConfigurationURL, "kCFProxyTypeAutoConfigurationURL")
#undef PROXY_KEY

/* The system settings (CFNetworkCopySystemProxySettings and its keys) are
 * CFProxySupport.m's, read from the environment. */
static NSArray *no_proxy(void)
{
    return [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:OBJ(kCFProxyTypeNone)
                                                                forKey:OBJ(kCFProxyTypeKey)]];
}

CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings)
{
    return (CFArrayRef)[no_proxy() retain];
}

/* A proxy auto-configuration script isn't run: the source, once added to a
 * run loop and signalled, answers that the URL goes direct. */
struct pac_request {
    CFProxyAutoConfigurationResultCallback cb;
    void *client;
    CFStreamClientContext context;
};

static void pac_perform(void *info)
{
    struct pac_request *r = info;
    if (r->cb)
        r->cb(r->client, (CFArrayRef)no_proxy(), NULL);
}

static void pac_release(const void *info)
{
    struct pac_request *r = (struct pac_request *)info;
    if (r->context.release && r->context.info)
        r->context.release(r->context.info);
    free(r);
}

CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationURL(CFURLRef proxyAutoConfigURL, CFURLRef targetURL,
                                                            CFProxyAutoConfigurationResultCallback cb,
                                                            CFStreamClientContext *clientContext)
{
    struct pac_request *r = calloc(1, sizeof *r);
    if (!r)
        return NULL;
    r->cb = cb;
    if (clientContext) {
        r->context = *clientContext;
        if (r->context.retain && r->context.info)
            r->context.info = (void *)r->context.retain(r->context.info);
        r->client = r->context.info;
    }
    CFRunLoopSourceContext sc = {0};
    sc.info = r;
    sc.release = pac_release;
    sc.perform = pac_perform;
    CFRunLoopSourceRef s = CFRunLoopSourceCreate(NULL, 0, &sc);
    if (s)
        CFRunLoopSourceSignal(s);
    return s;
}
