/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSMutableCharacterSet and the parts of NSCharacterSet that
 * Foundation.h doesn't declare (foundation/NSCharacterSet.m), with NSString's
 * percent encoding, which takes a character set. Foundation.h declares
 * NSCharacterSet itself and imports this header at its end. Written for
 * freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSCHARACTERSET_H_
#define _FERRY_FOUNDATION_NSCHARACTERSET_H_
#include <Foundation/Foundation.h>

#ifndef _FERRY_UTF32CHAR_DEFINED
#define _FERRY_UTF32CHAR_DEFINED
typedef uint32_t UTF32Char;
#endif
enum { NSOpenStepUnicodeReservedBase = 0xF400 };

@interface NSCharacterSet (NSCharacterSetMore) <NSMutableCopying>
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL controlCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL uppercaseLetterCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL lowercaseLetterCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL capitalizedLetterCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL nonBaseCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL decomposableCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL illegalCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL symbolCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLUserAllowedCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLPasswordAllowedCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLHostAllowedCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLPathAllowedCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLQueryAllowedCharacterSet;
@property (class, readonly, copy) NSCharacterSet * FERRY_SWIFT_NONNULL URLFragmentAllowedCharacterSet;
+ (NSCharacterSet *)characterSetWithRange:(NSRange)range;
+ (NSCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data;
+ (NSCharacterSet *)characterSetWithContentsOfFile:(NSString *)path;
- (BOOL)longCharacterIsMember:(UTF32Char)c;
- (BOOL)isSupersetOfSet:(NSCharacterSet *)other;
- (BOOL)hasMemberInPlane:(uint8_t)plane;
@property (readonly, copy) NSData *bitmapRepresentation;
- (id)mutableCopyWithZone:(NSZone *)zone;
@end

@interface NSMutableCharacterSet : NSCharacterSet <NSCopying, NSMutableCopying>
- (void)addCharactersInRange:(NSRange)range;
- (void)removeCharactersInRange:(NSRange)range;
- (void)addCharactersInString:(NSString *)s;
- (void)removeCharactersInString:(NSString *)s;
- (void)formUnionWithCharacterSet:(NSCharacterSet *)other;
- (void)formIntersectionWithCharacterSet:(NSCharacterSet *)other;
- (void)invert;
/* The makers of NSCharacterSet, answering mutable sets here. */
+ (NSMutableCharacterSet *)whitespaceCharacterSet;
+ (NSMutableCharacterSet *)whitespaceAndNewlineCharacterSet;
+ (NSMutableCharacterSet *)newlineCharacterSet;
+ (NSMutableCharacterSet *)decimalDigitCharacterSet;
+ (NSMutableCharacterSet *)letterCharacterSet;
+ (NSMutableCharacterSet *)alphanumericCharacterSet;
+ (NSMutableCharacterSet *)punctuationCharacterSet;
+ (NSMutableCharacterSet *)controlCharacterSet;
+ (NSMutableCharacterSet *)uppercaseLetterCharacterSet;
+ (NSMutableCharacterSet *)lowercaseLetterCharacterSet;
+ (NSMutableCharacterSet *)capitalizedLetterCharacterSet;
+ (NSMutableCharacterSet *)nonBaseCharacterSet;
+ (NSMutableCharacterSet *)decomposableCharacterSet;
+ (NSMutableCharacterSet *)illegalCharacterSet;
+ (NSMutableCharacterSet *)symbolCharacterSet;
+ (NSMutableCharacterSet *)URLUserAllowedCharacterSet;
+ (NSMutableCharacterSet *)URLPasswordAllowedCharacterSet;
+ (NSMutableCharacterSet *)URLHostAllowedCharacterSet;
+ (NSMutableCharacterSet *)URLPathAllowedCharacterSet;
+ (NSMutableCharacterSet *)URLQueryAllowedCharacterSet;
+ (NSMutableCharacterSet *)URLFragmentAllowedCharacterSet;
+ (NSMutableCharacterSet *)characterSetWithCharactersInString:(NSString *)s;
+ (NSMutableCharacterSet *)characterSetWithRange:(NSRange)range;
+ (NSMutableCharacterSet *)characterSetWithBitmapRepresentation:(NSData *)data;
+ (NSMutableCharacterSet *)characterSetWithContentsOfFile:(NSString *)path;
@end

@interface NSString (NSCharacterSetPercentEncoding)
- (NSString *)stringByAddingPercentEncodingWithAllowedCharacters:(NSCharacterSet *)allowed;
@property (readonly, copy) NSString *stringByRemovingPercentEncoding;
@end

#endif
