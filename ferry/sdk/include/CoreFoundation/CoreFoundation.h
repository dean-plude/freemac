/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the CoreFoundation basics Ferry provides. Written for freemac
 * from Apple's public API documentation; not Apple's header. In Ferry every
 * CF object is also an Objective-C object (CFStringRef is an NSString and so
 * on), which is what "toll-free bridging" promises. */
#ifndef _FERRY_COREFOUNDATION_H_
#define _FERRY_COREFOUNDATION_H_
#include <_ferry.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
/* What CoreFoundation brings in on a Mac, which programs rely on without
 * including it themselves (freemac 1.221, Ferry 0.45.0). */
#include <TargetConditionals.h>
#include <Availability.h>
#include <AvailabilityMacros.h>
#include <sys/types.h>
#include <mach/boolean.h>
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* and Block_copy, when blocks are on (freemac 1.226, Ferry 0.50.0) */
#if __BLOCKS__
#include <Block.h>
#endif
#include <time.h>

typedef const void *CFTypeRef;
typedef CFTypeRef CFPropertyListRef;
typedef long CFIndex;
typedef unsigned long CFHashCode;
typedef unsigned long CFOptionFlags;
typedef unsigned long CFTypeID;
typedef unsigned char Boolean;
typedef double CFTimeInterval;
typedef CFTimeInterval CFAbsoluteTime;
typedef int32_t SInt32;
typedef uint32_t UInt32;
typedef uint8_t UInt8;
typedef uint16_t UniChar;
/* The rest of the classic Mac types (MacTypes.h), freemac 1.221, Ferry 0.45.0. */
typedef int8_t SInt8;
typedef uint16_t UInt16;
typedef int16_t SInt16;
typedef uint64_t UInt64;
typedef int64_t SInt64;
typedef float Float32;
typedef double Float64;
typedef uint8_t Byte;
typedef int8_t SignedByte;
typedef char *Ptr;
typedef Ptr *Handle;
typedef long Size;
typedef uint16_t UTF16Char;
typedef uint32_t UTF32Char;
typedef uint8_t UTF8Char;
typedef unsigned char Str255[256];
typedef unsigned char Str63[64];
typedef unsigned char Str31[32];
typedef unsigned char *StringPtr;
typedef const unsigned char *ConstStringPtr;
typedef const unsigned char *ConstStr255Param;
typedef uint32_t FourCharCode;
typedef uint32_t ResType;
typedef int16_t ScriptCode;
typedef int16_t LangCode;
enum { kNilOptions = 0 }; /* no options (MacTypes.h; freemac 1.232) */
/* no error, as a Mac's CoreFoundation brings it in from MacTypes.h: OBS's
 * RTMP output checks Security's answers against it (freemac OBS work) */
#ifndef _FERRY_NOERR_
#define _FERRY_NOERR_
enum { noErr = 0 };
#endif
typedef int16_t RegionCode;
typedef struct { uint32_t lo, hi; } UnsignedWide; /* little-endian order */
typedef UInt32 CFStringEncoding;
typedef struct { CFIndex location, length; } CFRange;
static inline CFRange CFRangeMake(CFIndex loc, CFIndex len) { CFRange r = {loc, len}; return r; }
typedef enum { kCFCompareLessThan = -1, kCFCompareEqualTo = 0, kCFCompareGreaterThan = 1 } CFComparisonResult;

/* The CF types that are Foundation's objects say so, as on a Mac, so that
 * ARC lets a message's or property's result be cast to them without
 * __bridge (freemac 1.223, Ferry 0.47.0). */
#if defined(__has_attribute) && __has_attribute(objc_bridge)
#define CF_BRIDGED_TYPE(T) __attribute__((objc_bridge(T)))
#define CF_BRIDGED_MUTABLE_TYPE(T) __attribute__((objc_bridge_mutable(T)))
#else
#define CF_BRIDGED_TYPE(T)
#define CF_BRIDGED_MUTABLE_TYPE(T)
#endif
typedef const struct __CFAllocator *CFAllocatorRef;
typedef const struct CF_BRIDGED_TYPE(NSString) __CFString *CFStringRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableString) __CFString *CFMutableStringRef;
typedef const struct CF_BRIDGED_TYPE(NSArray) __CFArray *CFArrayRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableArray) __CFArray *CFMutableArrayRef;
typedef const struct CF_BRIDGED_TYPE(NSDictionary) __CFDictionary *CFDictionaryRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableDictionary) __CFDictionary *CFMutableDictionaryRef;
typedef const struct CF_BRIDGED_TYPE(NSData) __CFData *CFDataRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableData) __CFData *CFMutableDataRef;
typedef const struct CF_BRIDGED_TYPE(NSNumber) __CFNumber *CFNumberRef;
typedef const struct CF_BRIDGED_TYPE(NSNumber) __CFBoolean *CFBooleanRef;
typedef const struct CF_BRIDGED_TYPE(NSNull) __CFNull *CFNullRef;
typedef const struct CF_BRIDGED_TYPE(NSDate) __CFDate *CFDateRef;
typedef const struct CF_BRIDGED_TYPE(NSURL) __CFURL *CFURLRef;
typedef struct CF_BRIDGED_TYPE(NSError) __CFError *CFErrorRef;
typedef struct __CFRunLoop *CFRunLoopRef;
typedef struct __CFBundle *CFBundleRef;
/* a string wrapped in a struct of its own in Swift, CFRunLoopMode(rawValue:) (freemac 1.230) */
#ifdef __swift__
typedef CFStringRef CFRunLoopMode __attribute__((swift_wrapper(struct)));
#else
typedef CFStringRef CFRunLoopMode;
#endif
typedef struct __CFRunLoopObserver *CFRunLoopObserverRef;

#define kCFNotFound ((CFIndex)-1)
#define kCFStringEncodingASCII 0x0600
#define kCFStringEncodingUTF8 0x08000100
#define kCFStringEncodingISOLatin1 0x0201
#define kCFStringEncodingUnicode 0x0100

typedef enum {
    kCFNumberSInt8Type = 1, kCFNumberSInt16Type = 2, kCFNumberSInt32Type = 3, kCFNumberSInt64Type = 4,
    kCFNumberFloat32Type = 5, kCFNumberFloat64Type = 6, kCFNumberCharType = 7, kCFNumberShortType = 8,
    kCFNumberIntType = 9, kCFNumberLongType = 10, kCFNumberLongLongType = 11, kCFNumberFloatType = 12,
    kCFNumberDoubleType = 13, kCFNumberCFIndexType = 14, kCFNumberNSIntegerType = 15,
    kCFNumberCGFloatType = 16,
} CFNumberType;

#define CFSTR(s) ((CFStringRef)__builtin___CFStringMakeConstantString("" s ""))

#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#define CF_RETURNS_NOT_RETAINED __attribute__((cf_returns_not_retained))
/* with a Mac's attributes, for Swift (freemac 1.227) */
#define CF_ENUM(type, name) enum __attribute__((enum_extensibility(open))) name : type name; \
    enum __attribute__((enum_extensibility(open))) name : type
/* In C++ a Mac's option sets are the plain number type, so that flags
 * combine with | into it without a cast (as Qt's code does). */
#ifdef __cplusplus
#define CF_OPTIONS(type, name) type name; enum __attribute__((flag_enum, enum_extensibility(open))) : name
#else
#define CF_OPTIONS(type, name) enum __attribute__((flag_enum, enum_extensibility(open))) name : type name; \
    enum __attribute__((flag_enum, enum_extensibility(open))) name : type
#endif
#define CF_EXPORT extern
#define CF_INLINE static inline

/* nil, as a Mac's MacTypes.h gives it to C and C++ too: the same null as
 * <objc/objc.h>'s (freemac 1.232) */
#ifndef nil
#if defined(__cplusplus) && __cplusplus >= 201103L
#define nil nullptr
#elif defined(__cplusplus)
#define nil __null
#else
#define nil ((void *)0)
#endif
#endif
__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFAllocatorRef kCFAllocatorSystemDefault;
extern const CFAllocatorRef kCFAllocatorNull;
extern const CFBooleanRef kCFBooleanTrue;
extern const CFBooleanRef kCFBooleanFalse;
extern const CFNullRef kCFNull; /* NSNull's object */
extern const CFRunLoopMode kCFRunLoopDefaultMode;
extern const CFRunLoopMode kCFRunLoopCommonModes;

CFTypeRef CFRetain(CFTypeRef cf);
void CFRelease(CFTypeRef cf);
CFTypeRef CFAutorelease(CFTypeRef cf);
CFIndex CFGetRetainCount(CFTypeRef cf);
Boolean CFEqual(CFTypeRef a, CFTypeRef b);
CFHashCode CFHash(CFTypeRef cf);
CFStringRef CFCopyDescription(CFTypeRef cf);
void CFShow(CFTypeRef obj);

CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char *s, CFStringEncoding enc);
CFStringRef CFStringCreateWithCharacters(CFAllocatorRef alloc, const UniChar *chars, CFIndex len);
CFStringRef CFStringCreateWithFormat(CFAllocatorRef alloc, CFDictionaryRef options, CFStringRef format, ...);
CFStringRef CFStringCreateCopy(CFAllocatorRef alloc, CFStringRef s);
CFMutableStringRef CFStringCreateMutable(CFAllocatorRef alloc, CFIndex max);
void CFStringAppend(CFMutableStringRef s, CFStringRef appended);
void CFStringAppendCString(CFMutableStringRef s, const char *cstr, CFStringEncoding enc);
CFIndex CFStringGetLength(CFStringRef s);
UniChar CFStringGetCharacterAtIndex(CFStringRef s, CFIndex i);
Boolean CFStringGetCString(CFStringRef s, char *buffer, CFIndex size, CFStringEncoding enc);
const char *CFStringGetCStringPtr(CFStringRef s, CFStringEncoding enc);
const UniChar *CFStringGetCharactersPtr(CFStringRef s);
void CFStringGetCharacters(CFStringRef s, CFRange range, UniChar *buffer);
CFComparisonResult CFStringCompare(CFStringRef a, CFStringRef b, CFOptionFlags options);
Boolean CFStringHasPrefix(CFStringRef s, CFStringRef prefix);
Boolean CFStringHasSuffix(CFStringRef s, CFStringRef suffix);
SInt32 CFStringGetIntValue(CFStringRef s);
double CFStringGetDoubleValue(CFStringRef s);

CFIndex CFArrayGetCount(CFArrayRef a);
const void *CFArrayGetValueAtIndex(CFArrayRef a, CFIndex i);
void CFArrayAppendValue(CFMutableArrayRef a, const void *value);

CFIndex CFDictionaryGetCount(CFDictionaryRef d);
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *key);
Boolean CFDictionaryContainsKey(CFDictionaryRef d, const void *key);
void CFDictionarySetValue(CFMutableDictionaryRef d, const void *key, const void *value);
void CFDictionaryRemoveValue(CFMutableDictionaryRef d, const void *key);

CFNumberRef CFNumberCreate(CFAllocatorRef alloc, CFNumberType type, const void *value);
Boolean CFNumberGetValue(CFNumberRef n, CFNumberType type, void *value);
Boolean CFBooleanGetValue(CFBooleanRef b);
CFTypeID CFBooleanGetTypeID(void);
CFTypeID CFNumberGetTypeID(void);
CFTypeID CFDataGetTypeID(void);

CFDataRef CFDataCreate(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length);
CFIndex CFDataGetLength(CFDataRef d);
const UInt8 *CFDataGetBytePtr(CFDataRef d);
/* mutable data (freemac 1.225) */
CFMutableDataRef CFDataCreateMutable(CFAllocatorRef alloc, CFIndex capacity);
CFMutableDataRef CFDataCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFDataRef d);
CFDataRef CFDataCreateCopy(CFAllocatorRef alloc, CFDataRef d);
UInt8 *CFDataGetMutableBytePtr(CFMutableDataRef d);
void CFDataGetBytes(CFDataRef d, CFRange range, UInt8 *buffer);
void CFDataSetLength(CFMutableDataRef d, CFIndex length);
void CFDataIncreaseLength(CFMutableDataRef d, CFIndex extraLength);
void CFDataAppendBytes(CFMutableDataRef d, const UInt8 *bytes, CFIndex length);
void CFDataReplaceBytes(CFMutableDataRef d, CFRange range, const UInt8 *newBytes, CFIndex newLength);
void CFDataDeleteBytes(CFMutableDataRef d, CFRange range);

CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
extern const CFTimeInterval kCFAbsoluteTimeIntervalSince1970;

CFRunLoopRef CFRunLoopGetCurrent(void);
CFRunLoopRef CFRunLoopGetMain(void);
void CFRunLoopRun(void);
SInt32 CFRunLoopRunInMode(CFRunLoopMode mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled);
void CFRunLoopStop(CFRunLoopRef rl);
void CFRunLoopWakeUp(CFRunLoopRef rl);
void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void));
enum { kCFRunLoopRunFinished = 1, kCFRunLoopRunStopped = 2, kCFRunLoopRunTimedOut = 3, kCFRunLoopRunHandledSource = 4 };

/* Run loop timers (freemac 1.232, Ferry 0.56.0): NSTimers, as on a Mac. An
 * interval of 0 fires once. */
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSTimer) __CFRunLoopTimer *CFRunLoopTimerRef;
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFRunLoopTimerContext;
typedef void (*CFRunLoopTimerCallBack)(CFRunLoopTimerRef timer, void *info);
CFTypeID CFRunLoopTimerGetTypeID(void);
CFRunLoopTimerRef CFRunLoopTimerCreate(CFAllocatorRef allocator, CFAbsoluteTime fireDate, CFTimeInterval interval,
                                       CFOptionFlags flags, CFIndex order, CFRunLoopTimerCallBack callout,
                                       CFRunLoopTimerContext *context);
CFRunLoopTimerRef CFRunLoopTimerCreateWithHandler(CFAllocatorRef allocator, CFAbsoluteTime fireDate,
                                                  CFTimeInterval interval, CFOptionFlags flags, CFIndex order,
                                                  void (^block)(CFRunLoopTimerRef timer));
void CFRunLoopAddTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode);
void CFRunLoopRemoveTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode);
Boolean CFRunLoopContainsTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFRunLoopMode mode);
void CFRunLoopTimerInvalidate(CFRunLoopTimerRef timer);
Boolean CFRunLoopTimerIsValid(CFRunLoopTimerRef timer);
CFAbsoluteTime CFRunLoopTimerGetNextFireDate(CFRunLoopTimerRef timer);
void CFRunLoopTimerSetNextFireDate(CFRunLoopTimerRef timer, CFAbsoluteTime fireDate);
CFTimeInterval CFRunLoopTimerGetInterval(CFRunLoopTimerRef timer);
Boolean CFRunLoopTimerDoesRepeat(CFRunLoopTimerRef timer);
CFIndex CFRunLoopTimerGetOrder(CFRunLoopTimerRef timer);
void CFRunLoopTimerGetContext(CFRunLoopTimerRef timer, CFRunLoopTimerContext *context);
CFTimeInterval CFRunLoopTimerGetTolerance(CFRunLoopTimerRef timer);
void CFRunLoopTimerSetTolerance(CFRunLoopTimerRef timer, CFTimeInterval tolerance);
void CFRunLoopAddCommonMode(CFRunLoopRef rl, CFRunLoopMode mode);

/* Run loop observers (freemac 1.230): called as a run loop enters and
 * leaves a run, before it fires timers and handles sources, and before and
 * after it waits, in their order. Ferry's run loops don't tell modes apart,
 * so an observer added for any mode sees every pass. */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),
    kCFRunLoopBeforeTimers = (1UL << 1),
    kCFRunLoopBeforeSources = (1UL << 2),
    kCFRunLoopBeforeWaiting = (1UL << 5),
    kCFRunLoopAfterWaiting = (1UL << 6),
    kCFRunLoopExit = (1UL << 7),
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFRunLoopObserverContext;
typedef void (*CFRunLoopObserverCallBack)(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);
CFTypeID CFRunLoopObserverGetTypeID(void);
CFRunLoopObserverRef CFRunLoopObserverCreate(CFAllocatorRef allocator, CFOptionFlags activities, Boolean repeats,
                                             CFIndex order, CFRunLoopObserverCallBack callout,
                                             CFRunLoopObserverContext *context);
CFRunLoopObserverRef CFRunLoopObserverCreateWithHandler(CFAllocatorRef allocator, CFOptionFlags activities,
                                                        Boolean repeats, CFIndex order,
                                                        void (^block)(CFRunLoopObserverRef observer,
                                                                      CFRunLoopActivity activity));
CFOptionFlags CFRunLoopObserverGetActivities(CFRunLoopObserverRef observer);
Boolean CFRunLoopObserverDoesRepeat(CFRunLoopObserverRef observer);
CFIndex CFRunLoopObserverGetOrder(CFRunLoopObserverRef observer);
void CFRunLoopObserverInvalidate(CFRunLoopObserverRef observer);
Boolean CFRunLoopObserverIsValid(CFRunLoopObserverRef observer);
void CFRunLoopObserverGetContext(CFRunLoopObserverRef observer, CFRunLoopObserverContext *context);
void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode);
void CFRunLoopRemoveObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode);
Boolean CFRunLoopContainsObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFRunLoopMode mode);

typedef const struct CF_BRIDGED_TYPE(NSAttributedString) __CFAttributedString *CFAttributedStringRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableAttributedString) __CFAttributedString *CFMutableAttributedStringRef;

CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef alloc, CFStringRef str, CFDictionaryRef attributes);
CFAttributedStringRef CFAttributedStringCreateCopy(CFAllocatorRef alloc, CFAttributedStringRef str);
CFMutableAttributedStringRef CFAttributedStringCreateMutable(CFAllocatorRef alloc, CFIndex maxLength);
CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(CFAllocatorRef alloc, CFIndex maxLength,
                                                                 CFAttributedStringRef str);
CFStringRef CFAttributedStringGetString(CFAttributedStringRef str);
CFIndex CFAttributedStringGetLength(CFAttributedStringRef str);
CFDictionaryRef CFAttributedStringGetAttributes(CFAttributedStringRef str, CFIndex loc, CFRange *effectiveRange);
CFTypeRef CFAttributedStringGetAttribute(CFAttributedStringRef str, CFIndex loc, CFStringRef name,
                                         CFRange *effectiveRange);
void CFAttributedStringReplaceString(CFMutableAttributedStringRef str, CFRange range, CFStringRef replacement);
void CFAttributedStringSetAttributes(CFMutableAttributedStringRef str, CFRange range, CFDictionaryRef attributes,
                                     Boolean clearOtherAttributes);
void CFAttributedStringSetAttribute(CFMutableAttributedStringRef str, CFRange range, CFStringRef name,
                                    CFTypeRef value);
void CFAttributedStringRemoveAttribute(CFMutableAttributedStringRef str, CFRange range, CFStringRef name);
void CFAttributedStringBeginEditing(CFMutableAttributedStringRef str);
void CFAttributedStringEndEditing(CFMutableAttributedStringRef str);

CFBundleRef CFBundleGetMainBundle(void);
CFTypeRef CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key);
CFStringRef CFBundleGetIdentifier(CFBundleRef bundle);
CFBundleRef CFBundleCreate(CFAllocatorRef allocator, CFURLRef bundleURL);
CFBundleRef CFBundleGetBundleWithIdentifier(CFStringRef bundleID);
CFURLRef CFBundleCopyBundleURL(CFBundleRef bundle);
CFURLRef CFBundleCopyExecutableURL(CFBundleRef bundle);
CFURLRef CFBundleCopyResourcesDirectoryURL(CFBundleRef bundle);
CFURLRef CFBundleCopyBuiltInPlugInsURL(CFBundleRef bundle);
CFDictionaryRef CFBundleGetInfoDictionary(CFBundleRef bundle);
/* A bundle folder's Info.plist, read afresh from the disk (Contents/Info.plist,
 * Resources/Info.plist or Info.plist), and a folder's or file's
 * (freemac 1.223, Ferry 0.47.0). */
CFDictionaryRef CFBundleCopyInfoDictionaryInDirectory(CFURLRef bundleURL);
CFDictionaryRef CFBundleCopyInfoDictionaryForURL(CFURLRef url);
Boolean CFBundleLoadExecutable(CFBundleRef bundle);
Boolean CFBundleLoadExecutableAndReturnError(CFBundleRef bundle, CFErrorRef *error);
Boolean CFBundleIsExecutableLoaded(CFBundleRef bundle);
void CFBundleUnloadExecutable(CFBundleRef bundle);
void *CFBundleGetFunctionPointerForName(CFBundleRef bundle, CFStringRef functionName);
void *CFBundleGetDataPointerForName(CFBundleRef bundle, CFStringRef symbolName);
void CFBundleGetFunctionPointersForNames(CFBundleRef bundle, CFArrayRef functionNames, void *ftbl[]);

/* Preferences: the same store as NSUserDefaults; the user and host arguments are ignored */
extern const CFStringRef kCFPreferencesAnyApplication, kCFPreferencesCurrentApplication, kCFPreferencesAnyHost,
    kCFPreferencesCurrentHost, kCFPreferencesAnyUser, kCFPreferencesCurrentUser;
CFPropertyListRef CFPreferencesCopyAppValue(CFStringRef key, CFStringRef applicationID);
Boolean CFPreferencesGetAppBooleanValue(CFStringRef key, CFStringRef applicationID, Boolean *keyExistsAndHasValidFormat);
CFIndex CFPreferencesGetAppIntegerValue(CFStringRef key, CFStringRef applicationID, Boolean *keyExistsAndHasValidFormat);
void CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef applicationID);
Boolean CFPreferencesAppSynchronize(CFStringRef applicationID);
Boolean CFPreferencesAppValueIsForced(CFStringRef key, CFStringRef applicationID);
CFPropertyListRef CFPreferencesCopyValue(CFStringRef key, CFStringRef applicationID, CFStringRef userName,
                                         CFStringRef hostName);
void CFPreferencesSetValue(CFStringRef key, CFPropertyListRef value, CFStringRef applicationID, CFStringRef userName,
                           CFStringRef hostName);
CFDictionaryRef CFPreferencesCopyMultiple(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName,
                                          CFStringRef hostName);
Boolean CFPreferencesSynchronize(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);
CFArrayRef CFPreferencesCopyKeyList(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
/* Arrays and dictionaries with callbacks, more strings, string encodings,
 * UUIDs, URLs, bundle keys and byte order (Ferry 0.43.0) */
#include <CoreFoundation/CFMore.h>
#include <CoreFoundation/CFSet.h>
#include <CoreFoundation/CFCharacterSet.h>
/* locales, which are NSLocales (foundation/CFLocale.m) */
#include <CoreFoundation/CFLocale.h>
#include <CoreFoundation/CFDate.h>
/* property lists as data, number formatters, calendars, URL keys (freemac 1.232) */
#include <CoreFoundation/CFPropertyList.h>
/* errors, which are NSErrors (foundation/CFError.m) */
#include <CoreFoundation/CFError.h>
/* run loop sources, sockets and streams (foundation/CFSocket.m, NSStream.m) */
#include <CoreFoundation/CFSocket.h>
#include <CoreFoundation/CFStream.h>
/* notification centers and Mach ports (foundation/CFNotificationCenter.m,
 * freemac 1.224, Ferry 0.48.0) */
#include <CoreFoundation/CFNotificationCenter.h>
/* allocators from a context, binary heaps, string tokenizers (freemac 1.265,
 * Ferry 0.88.0, foundation/CFElectron.m) */
#include <CoreFoundation/CFBinaryHeap.h>
/* an object's type (freemac 1.215, Ferry 0.41.0) */
#ifdef __cplusplus
extern "C" CFTypeID CFGetTypeID(CFTypeRef cf);
#else
CFTypeID CFGetTypeID(CFTypeRef cf);
#endif
#endif
