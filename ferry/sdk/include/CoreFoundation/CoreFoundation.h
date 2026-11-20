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

typedef const void *CFTypeRef;
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
typedef UInt32 CFStringEncoding;
typedef struct { CFIndex location, length; } CFRange;
static inline CFRange CFRangeMake(CFIndex loc, CFIndex len) { CFRange r = {loc, len}; return r; }
typedef enum { kCFCompareLessThan = -1, kCFCompareEqualTo = 0, kCFCompareGreaterThan = 1 } CFComparisonResult;

typedef const struct __CFAllocator *CFAllocatorRef;
typedef const struct __CFString *CFStringRef;
typedef struct __CFString *CFMutableStringRef;
typedef const struct __CFArray *CFArrayRef;
typedef struct __CFArray *CFMutableArrayRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef struct __CFDictionary *CFMutableDictionaryRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFNumber *CFNumberRef;
typedef const struct __CFBoolean *CFBooleanRef;
typedef const struct __CFDate *CFDateRef;
typedef const struct __CFURL *CFURLRef;
typedef const struct __CFError *CFErrorRef;
typedef struct __CFRunLoop *CFRunLoopRef;
typedef struct __CFBundle *CFBundleRef;
typedef CFStringRef CFRunLoopMode;

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

#ifdef __OBJC__
#define CF_BRIDGED_TYPE(T)
#endif
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#define CF_RETURNS_NOT_RETAINED __attribute__((cf_returns_not_retained))
#define CF_ENUM(type, name) enum name : type name; enum name : type
#define CF_OPTIONS(type, name) enum name : type name; enum name : type
#define CF_EXPORT extern
#define CF_INLINE static inline

__FERRY_BEGIN
extern const CFAllocatorRef kCFAllocatorDefault;
extern const CFAllocatorRef kCFAllocatorSystemDefault;
extern const CFAllocatorRef kCFAllocatorNull;
extern const CFBooleanRef kCFBooleanTrue;
extern const CFBooleanRef kCFBooleanFalse;
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
CFComparisonResult CFStringCompare(CFStringRef a, CFStringRef b, CFOptionFlags options);
Boolean CFStringHasPrefix(CFStringRef s, CFStringRef prefix);
Boolean CFStringHasSuffix(CFStringRef s, CFStringRef suffix);
SInt32 CFStringGetIntValue(CFStringRef s);
double CFStringGetDoubleValue(CFStringRef s);

CFIndex CFArrayGetCount(CFArrayRef a);
const void *CFArrayGetValueAtIndex(CFArrayRef a, CFIndex i);
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const void *callbacks);
void CFArrayAppendValue(CFMutableArrayRef a, const void *value);
extern const char kCFTypeArrayCallBacks[];

CFIndex CFDictionaryGetCount(CFDictionaryRef d);
const void *CFDictionaryGetValue(CFDictionaryRef d, const void *key);
Boolean CFDictionaryContainsKey(CFDictionaryRef d, const void *key);
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const void *keyCallBacks,
                                                 const void *valueCallBacks);
void CFDictionarySetValue(CFMutableDictionaryRef d, const void *key, const void *value);
void CFDictionaryRemoveValue(CFMutableDictionaryRef d, const void *key);
extern const char kCFTypeDictionaryKeyCallBacks[];
extern const char kCFTypeDictionaryValueCallBacks[];

CFNumberRef CFNumberCreate(CFAllocatorRef alloc, CFNumberType type, const void *value);
Boolean CFNumberGetValue(CFNumberRef n, CFNumberType type, void *value);
Boolean CFBooleanGetValue(CFBooleanRef b);

CFDataRef CFDataCreate(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex length);
CFIndex CFDataGetLength(CFDataRef d);
const UInt8 *CFDataGetBytePtr(CFDataRef d);

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

CFBundleRef CFBundleGetMainBundle(void);
CFTypeRef CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key);
CFStringRef CFBundleGetIdentifier(CFBundleRef bundle);
__FERRY_END
#endif
