/* SPDX-License-Identifier: GPL-3.0-or-later
 * CFCharacterSet (freemac 1.264, for HandBrake), written for freemac from
 * Apple's public CoreFoundation documentation. As on a Mac, a CF set is
 * an NSCharacterSet and a mutable one an NSMutableCharacterSet, so either
 * call works on it. */
#import "FInternal.h"

#define OBJ(x) ((id)(x))

CFTypeID CFCharacterSetGetTypeID(void) { return (CFTypeID)[NSCharacterSet class]; }

CFCharacterSetRef CFCharacterSetGetPredefined(CFCharacterSetPredefinedSet which)
{
    switch (which) {
    case kCFCharacterSetControl: return (CFCharacterSetRef)[NSCharacterSet controlCharacterSet];
    case kCFCharacterSetWhitespace: return (CFCharacterSetRef)[NSCharacterSet whitespaceCharacterSet];
    case kCFCharacterSetWhitespaceAndNewline:
        return (CFCharacterSetRef)[NSCharacterSet whitespaceAndNewlineCharacterSet];
    case kCFCharacterSetDecimalDigit: return (CFCharacterSetRef)[NSCharacterSet decimalDigitCharacterSet];
    case kCFCharacterSetLetter: return (CFCharacterSetRef)[NSCharacterSet letterCharacterSet];
    case kCFCharacterSetLowercaseLetter: return (CFCharacterSetRef)[NSCharacterSet lowercaseLetterCharacterSet];
    case kCFCharacterSetUppercaseLetter: return (CFCharacterSetRef)[NSCharacterSet uppercaseLetterCharacterSet];
    case kCFCharacterSetNonBase: return (CFCharacterSetRef)[NSCharacterSet nonBaseCharacterSet];
    case kCFCharacterSetDecomposable: return (CFCharacterSetRef)[NSCharacterSet decomposableCharacterSet];
    case kCFCharacterSetAlphaNumeric: return (CFCharacterSetRef)[NSCharacterSet alphanumericCharacterSet];
    case kCFCharacterSetPunctuation: return (CFCharacterSetRef)[NSCharacterSet punctuationCharacterSet];
    case kCFCharacterSetCapitalizedLetter:
        return (CFCharacterSetRef)[NSCharacterSet capitalizedLetterCharacterSet];
    case kCFCharacterSetSymbol: return (CFCharacterSetRef)[NSCharacterSet symbolCharacterSet];
    case kCFCharacterSetNewline: return (CFCharacterSetRef)[NSCharacterSet newlineCharacterSet];
    case kCFCharacterSetIllegal: return (CFCharacterSetRef)[NSCharacterSet illegalCharacterSet];
    }
    return NULL;
}

CFCharacterSetRef CFCharacterSetCreateWithCharactersInRange(CFAllocatorRef alloc, CFRange r)
{
    (void)alloc;
    if (r.location < 0 || r.length < 0)
        return NULL;
    return (CFCharacterSetRef)[[NSCharacterSet characterSetWithRange:NSMakeRange((NSUInteger)r.location,
                                                                                  (NSUInteger)r.length)] copy];
}

CFCharacterSetRef CFCharacterSetCreateWithCharactersInString(CFAllocatorRef alloc, CFStringRef s)
{
    (void)alloc;
    return (CFCharacterSetRef)[[NSCharacterSet characterSetWithCharactersInString:OBJ(s) ?: @""] copy];
}

CFCharacterSetRef CFCharacterSetCreateInvertedSet(CFAllocatorRef alloc, CFCharacterSetRef set)
{
    (void)alloc;
    return set ? (CFCharacterSetRef)[[OBJ(set) invertedSet] copy] : NULL;
}

CFCharacterSetRef CFCharacterSetCreateCopy(CFAllocatorRef alloc, CFCharacterSetRef set)
{
    (void)alloc;
    return set ? (CFCharacterSetRef)[OBJ(set) copy] : NULL;
}

CFMutableCharacterSetRef CFCharacterSetCreateMutable(CFAllocatorRef alloc)
{
    (void)alloc;
    return (CFMutableCharacterSetRef)[[NSMutableCharacterSet alloc] init];
}

CFMutableCharacterSetRef CFCharacterSetCreateMutableCopy(CFAllocatorRef alloc, CFCharacterSetRef set)
{
    (void)alloc;
    if (!set)
        return CFCharacterSetCreateMutable(alloc);
    return (CFMutableCharacterSetRef)[OBJ(set) mutableCopy];
}

Boolean CFCharacterSetIsCharacterMember(CFCharacterSetRef set, UniChar c)
{
    return set && [OBJ(set) characterIsMember:c];
}

Boolean CFCharacterSetIsLongCharacterMember(CFCharacterSetRef set, UTF32Char c)
{
    return set && [OBJ(set) longCharacterIsMember:c];
}

Boolean CFCharacterSetIsSupersetOfSet(CFCharacterSetRef set, CFCharacterSetRef other)
{
    return set && other && [OBJ(set) isSupersetOfSet:OBJ(other)];
}

static BOOL is_mutable(CFMutableCharacterSetRef set) { return set && [OBJ(set) isKindOfClass:[NSMutableCharacterSet class]]; }

void CFCharacterSetAddCharactersInRange(CFMutableCharacterSetRef set, CFRange r)
{
    if (is_mutable(set) && r.location >= 0 && r.length > 0)
        [OBJ(set) addCharactersInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)];
}

void CFCharacterSetRemoveCharactersInRange(CFMutableCharacterSetRef set, CFRange r)
{
    if (is_mutable(set) && r.location >= 0 && r.length > 0)
        [OBJ(set) removeCharactersInRange:NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length)];
}

void CFCharacterSetAddCharactersInString(CFMutableCharacterSetRef set, CFStringRef s)
{
    if (is_mutable(set) && s)
        [OBJ(set) addCharactersInString:OBJ(s)];
}

void CFCharacterSetRemoveCharactersInString(CFMutableCharacterSetRef set, CFStringRef s)
{
    if (is_mutable(set) && s)
        [OBJ(set) removeCharactersInString:OBJ(s)];
}

void CFCharacterSetUnion(CFMutableCharacterSetRef set, CFCharacterSetRef other)
{
    if (is_mutable(set) && other)
        [OBJ(set) formUnionWithCharacterSet:OBJ(other)];
}

void CFCharacterSetIntersect(CFMutableCharacterSetRef set, CFCharacterSetRef other)
{
    if (is_mutable(set) && other)
        [OBJ(set) formIntersectionWithCharacterSet:OBJ(other)];
}

void CFCharacterSetInvert(CFMutableCharacterSetRef set)
{
    if (is_mutable(set))
        [OBJ(set) invert];
}
