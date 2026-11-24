/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSScanner (foundation/NSScanner.m). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSSCANNER_H_
#define _FERRY_FOUNDATION_NSSCANNER_H_
#include <Foundation/Foundation.h>

@interface NSScanner : NSObject <NSCopying>
+ (instancetype)scannerWithString:(NSString *)string;
+ (id)localizedScannerWithString:(NSString *)string;
- (instancetype)initWithString:(NSString *)string;
@property (readonly, copy) NSString *string;
@property NSUInteger scanLocation;
@property (copy) NSCharacterSet *charactersToBeSkipped;
@property BOOL caseSensitive;
@property (retain) id locale;
@property (readonly, getter=isAtEnd) BOOL atEnd;

- (BOOL)scanInt:(int *)result;
- (BOOL)scanInteger:(NSInteger *)result;
- (BOOL)scanLongLong:(long long *)result;
- (BOOL)scanUnsignedLongLong:(unsigned long long *)result;
- (BOOL)scanFloat:(float *)result;
- (BOOL)scanDouble:(double *)result;
- (BOOL)scanHexInt:(unsigned int *)result;
- (BOOL)scanHexLongLong:(unsigned long long *)result;
- (BOOL)scanHexFloat:(float *)result;
- (BOOL)scanHexDouble:(double *)result;
- (BOOL)scanString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result;
- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result;
@end

#endif
