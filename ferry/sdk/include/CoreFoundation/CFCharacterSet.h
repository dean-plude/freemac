/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CFCharacterSet (foundation/CFCharacterSet.m, freemac 1.264).
 * Written for freemac from Apple's public CoreFoundation documentation;
 * not Apple's header. A CFCharacterSet is an NSCharacterSet. */
#ifndef _FERRY_CFCHARACTERSET_H_
#define _FERRY_CFCHARACTERSET_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef const struct CF_BRIDGED_TYPE(NSCharacterSet) __CFCharacterSet *CFCharacterSetRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSMutableCharacterSet) __CFCharacterSet *CFMutableCharacterSetRef;
typedef CF_ENUM(CFIndex, CFCharacterSetPredefinedSet) {
    kCFCharacterSetControl = 1, kCFCharacterSetWhitespace, kCFCharacterSetWhitespaceAndNewline,
    kCFCharacterSetDecimalDigit, kCFCharacterSetLetter, kCFCharacterSetLowercaseLetter,
    kCFCharacterSetUppercaseLetter, kCFCharacterSetNonBase, kCFCharacterSetDecomposable,
    kCFCharacterSetAlphaNumeric, kCFCharacterSetPunctuation, kCFCharacterSetCapitalizedLetter = 13,
    kCFCharacterSetSymbol, kCFCharacterSetNewline, kCFCharacterSetIllegal,
};
CFTypeID CFCharacterSetGetTypeID(void);
CFCharacterSetRef CFCharacterSetGetPredefined(CFCharacterSetPredefinedSet theSetIdentifier);
CFCharacterSetRef CFCharacterSetCreateWithCharactersInRange(CFAllocatorRef alloc, CFRange theRange);
CFCharacterSetRef CFCharacterSetCreateWithCharactersInString(CFAllocatorRef alloc, CFStringRef theString);
CFCharacterSetRef CFCharacterSetCreateInvertedSet(CFAllocatorRef alloc, CFCharacterSetRef theSet);
CFCharacterSetRef CFCharacterSetCreateCopy(CFAllocatorRef alloc, CFCharacterSetRef theSet);
CFMutableCharacterSetRef CFCharacterSetCreateMutable(CFAllocatorRef alloc);
CFMutableCharacterSetRef CFCharacterSetCreateMutableCopy(CFAllocatorRef alloc, CFCharacterSetRef theSet);
Boolean CFCharacterSetIsCharacterMember(CFCharacterSetRef theSet, UniChar theChar);
Boolean CFCharacterSetIsLongCharacterMember(CFCharacterSetRef theSet, UTF32Char theChar);
Boolean CFCharacterSetIsSupersetOfSet(CFCharacterSetRef theSet, CFCharacterSetRef theOtherset);
void CFCharacterSetAddCharactersInRange(CFMutableCharacterSetRef theSet, CFRange theRange);
void CFCharacterSetRemoveCharactersInRange(CFMutableCharacterSetRef theSet, CFRange theRange);
void CFCharacterSetAddCharactersInString(CFMutableCharacterSetRef theSet, CFStringRef theString);
void CFCharacterSetRemoveCharactersInString(CFMutableCharacterSetRef theSet, CFStringRef theString);
void CFCharacterSetUnion(CFMutableCharacterSetRef theSet, CFCharacterSetRef theOtherSet);
void CFCharacterSetIntersect(CFMutableCharacterSetRef theSet, CFCharacterSetRef theOtherSet);
void CFCharacterSetInvert(CFMutableCharacterSetRef theSet);
__FERRY_END
#endif
