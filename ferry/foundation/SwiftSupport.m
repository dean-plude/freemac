/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What Swift's standard library asks of Foundation's strings and
 * collections (freemac 1.227). A Swift String handed to Objective-C is a
 * subclass of NSString kept by Swift, and an NSString handed to Swift is
 * read through a few of NSString's methods; the same goes for arrays,
 * dictionaries and sets. These are the methods of that exchange Ferry's
 * Foundation didn't have, each as Apple's documentation of NSString,
 * NSDictionary and NSSet describes it (the two underscored NSString
 * methods are hints, which may answer nothing, and +newTaggedNSString...
 * may decline to make a tagged string, which Ferry never makes).
 */
#import <Foundation/Foundation.h>
#import "FInternal.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Swift's own strings, handed to Objective-C, answer -hash by asking for
 * these two functions by name (with dlsym, as CoreFoundation's on a Mac):
 * a hash of ASCII bytes, and of a string's characters. They hash as
 * Ferry's NSString does, so a Swift string and an NSString with the same
 * characters find each other in a dictionary. The second reads the
 * characters rather than asking -hash, which is what Swift's strings call
 * it from. */
CFHashCode CFStringHashCString(const uint8_t *bytes, CFIndex len);
CFHashCode CFStringHashNSString(id str);

CFHashCode CFStringHashCString(const uint8_t *bytes, CFIndex len)
{
    NSUInteger h = 5381;
    for (CFIndex i = 0; i < len; i++)
        h = h * 33 + bytes[i];
    return h;
}

CFHashCode CFStringHashNSString(id str)
{
    NSUInteger n = [str length];
    unichar small[64], *c = n <= 64 ? small : malloc(n * sizeof(unichar));
    if (!c)
        return 0;
    [str getCharacters:c range:NSMakeRange(0, n)];
    NSUInteger h = FHashChars(c, n);
    if (c != small)
        free(c);
    return h;
}

@implementation NSString (FerrySwift)

/* Swift asks NSString (through its own subclass) for a small string kept
 * inside the pointer; Ferry has none, so Swift makes an ordinary one. */
+ (id)newTaggedNSStringWithASCIIBytes_:(const char *)bytes length_:(NSUInteger)length
{
    return nil;
}

/* Pointers straight to the characters, when a string keeps them so:
 * Swift falls back to copying when there are none. */
- (const char *)_fastCStringContents:(BOOL)nulTerminated { return NULL; }
- (const unichar *)_fastCharacterContents { return NULL; }

/* -getBytes:maxLength:usedLength:encoding:options:range:remainingRange:,
 * for UTF-8 and ASCII (the two Swift asks for) character by character, so
 * a short buffer is filled with whole characters only; with no buffer it
 * counts the bytes the whole range needs. Other encodings convert the
 * range at once. */
- (BOOL)getBytes:(void *)buffer maxLength:(NSUInteger)max usedLength:(NSUInteger *)used
        encoding:(NSStringEncoding)encoding options:(NSStringEncodingConversionOptions)options
           range:(NSRange)range remainingRange:(NSRangePointer)left
{
    NSUInteger n = 0, i = range.location, end = range.location + range.length;
    if (encoding != NSUTF8StringEncoding && encoding != NSASCIIStringEncoding) {
        NSData *d = [[self substringWithRange:range] dataUsingEncoding:encoding];
        if (!d)
            return NO;
        n = [d length];
        if (buffer && n > max) {
            if (used) *used = 0;
            if (left) *left = range;
            return NO;
        }
        if (buffer)
            memcpy(buffer, [d bytes], n);
        if (used) *used = n;
        if (left) *left = NSMakeRange(end, 0);
        return YES;
    }
    unsigned char *out = buffer;
    while (i < end) {
        uint32_t c = [self characterAtIndex:i];
        NSUInteger units = 1;
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < end) {
            unichar lo = [self characterAtIndex:i + 1];
            if (lo >= 0xDC00 && lo < 0xE000) {
                c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
                units = 2;
            }
        }
        unsigned char b[4];
        NSUInteger k;
        if (encoding == NSASCIIStringEncoding) {
            if (c > 0x7F)
                break;
            b[0] = (unsigned char)c;
            k = 1;
        } else if (c < 0x80) {
            b[0] = (unsigned char)c;
            k = 1;
        } else if (c < 0x800) {
            b[0] = 0xC0 | (c >> 6);
            b[1] = 0x80 | (c & 0x3F);
            k = 2;
        } else if (c < 0x10000) {
            if (c >= 0xD800 && c < 0xE000)
                c = 0xFFFD; /* a lone surrogate */
            b[0] = 0xE0 | (c >> 12);
            b[1] = 0x80 | ((c >> 6) & 0x3F);
            b[2] = 0x80 | (c & 0x3F);
            k = 3;
        } else {
            b[0] = 0xF0 | (c >> 18);
            b[1] = 0x80 | ((c >> 12) & 0x3F);
            b[2] = 0x80 | ((c >> 6) & 0x3F);
            b[3] = 0x80 | (c & 0x3F);
            k = 4;
        }
        if (out) {
            if (n + k > max)
                break;
            memcpy(out + n, b, k);
        }
        n += k;
        i += units;
    }
    if (used) *used = n;
    if (left) *left = NSMakeRange(i, end - i);
    return i > range.location || range.length == 0;
}

- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask
                        range:(NSRange)range locale:(id)locale
{
    NSString *mine = range.location == 0 && range.length == [self length] ? self : [self substringWithRange:range];
    return [mine compare:other options:mask];
}

@end

@implementation NSDictionary (FerrySwift)

- (void)getObjects:(id *)objects andKeys:(id *)keys count:(NSUInteger)count
{
    NSUInteger i = 0;
    for (id k in self) {
        if (i >= count)
            break;
        if (keys) keys[i] = k;
        if (objects) objects[i] = [self objectForKey:k];
        i++;
    }
}

- (void)getObjects:(id *)objects andKeys:(id *)keys
{
    [self getObjects:objects andKeys:keys count:[self count]];
}

- (void)enumerateKeysAndObjectsWithOptions:(NSEnumerationOptions)opts
                                usingBlock:(void (^)(id key, id obj, BOOL *stop))block
{
    BOOL stop = NO;
    for (id k in [self allKeys]) {
        block(k, [self objectForKey:k], &stop);
        if (stop)
            break;
    }
}

@end

@implementation NSSet (FerrySwift)

- (void)getObjects:(id *)objects count:(NSUInteger)count
{
    NSUInteger i = 0;
    for (id o in self) {
        if (i >= count)
            break;
        objects[i++] = o;
    }
}

- (void)getObjects:(id *)objects
{
    [self getObjects:objects count:[self count]];
}

@end
