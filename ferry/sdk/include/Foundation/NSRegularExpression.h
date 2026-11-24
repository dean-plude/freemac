/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSRegularExpression and NSTextCheckingResult
 * (foundation/NSRegularExpression.m), on this system's ICU. Written for
 * freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSREGULAREXPRESSION_H_
#define _FERRY_FOUNDATION_NSREGULAREXPRESSION_H_
#include <Foundation/Foundation.h>

@class NSRegularExpression;

typedef NS_OPTIONS(uint64_t, NSTextCheckingType) {
    NSTextCheckingTypeOrthography = 1ULL << 0,
    NSTextCheckingTypeSpelling = 1ULL << 1,
    NSTextCheckingTypeGrammar = 1ULL << 2,
    NSTextCheckingTypeDate = 1ULL << 3,
    NSTextCheckingTypeAddress = 1ULL << 4,
    NSTextCheckingTypeLink = 1ULL << 5,
    NSTextCheckingTypeQuote = 1ULL << 6,
    NSTextCheckingTypeDash = 1ULL << 7,
    NSTextCheckingTypeReplacement = 1ULL << 8,
    NSTextCheckingTypeCorrection = 1ULL << 9,
    NSTextCheckingTypeRegularExpression = 1ULL << 10,
    NSTextCheckingTypePhoneNumber = 1ULL << 11,
    NSTextCheckingTypeTransitInformation = 1ULL << 12,
};

@interface NSTextCheckingResult : NSObject <NSCopying>
@property (readonly) NSTextCheckingType resultType;
@property (readonly) NSRange range;
@property (readonly) NSUInteger numberOfRanges;
- (NSRange)rangeAtIndex:(NSUInteger)idx;
- (NSRange)rangeWithName:(NSString *)name;
@property (readonly, copy) NSRegularExpression *regularExpression;
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset;
+ (NSTextCheckingResult *)regularExpressionCheckingResultWithRanges:(NSRangePointer)ranges
                                                              count:(NSUInteger)count
                                                  regularExpression:(NSRegularExpression *)regularExpression;
@end

typedef NS_OPTIONS(NSUInteger, NSRegularExpressionOptions) {
    NSRegularExpressionCaseInsensitive = 1 << 0,
    NSRegularExpressionAllowCommentsAndWhitespace = 1 << 1,
    NSRegularExpressionIgnoreMetacharacters = 1 << 2,
    NSRegularExpressionDotMatchesLineSeparators = 1 << 3,
    NSRegularExpressionAnchorsMatchLines = 1 << 4,
    NSRegularExpressionUseUnixLineSeparators = 1 << 5,
    NSRegularExpressionUseUnicodeWordBoundaries = 1 << 6,
};

typedef NS_OPTIONS(NSUInteger, NSMatchingOptions) {
    NSMatchingReportProgress = 1 << 0,
    NSMatchingReportCompletion = 1 << 1,
    NSMatchingAnchored = 1 << 2,
    NSMatchingWithTransparentBounds = 1 << 3,
    NSMatchingWithoutAnchoringBounds = 1 << 4,
};

typedef NS_OPTIONS(NSUInteger, NSMatchingFlags) {
    NSMatchingProgress = 1 << 0,
    NSMatchingCompleted = 1 << 1,
    NSMatchingHitEnd = 1 << 2,
    NSMatchingRequiredEnd = 1 << 3,
    NSMatchingInternalError = 1 << 4,
};

@interface NSRegularExpression : NSObject <NSCopying>
+ (instancetype)regularExpressionWithPattern:(NSString *)pattern
                                     options:(NSRegularExpressionOptions)options
                                       error:(NSError **)error;
- (instancetype)initWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error;
@property (readonly, copy) NSString *pattern;
@property (readonly) NSRegularExpressionOptions options;
@property (readonly) NSUInteger numberOfCaptureGroups;
+ (NSString *)escapedPatternForString:(NSString *)string;

- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop))block;
- (NSArray<NSTextCheckingResult *> *)matchesInString:(NSString *)string
                                             options:(NSMatchingOptions)options
                                               range:(NSRange)range;
- (NSUInteger)numberOfMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range;
- (NSTextCheckingResult *)firstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range;
- (NSRange)rangeOfFirstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range;

- (NSString *)stringByReplacingMatchesInString:(NSString *)string
                                       options:(NSMatchingOptions)options
                                         range:(NSRange)range
                                  withTemplate:(NSString *)templ;
- (NSUInteger)replaceMatchesInString:(NSMutableString *)string
                             options:(NSMatchingOptions)options
                               range:(NSRange)range
                        withTemplate:(NSString *)templ;
- (NSString *)replacementStringForResult:(NSTextCheckingResult *)result
                                inString:(NSString *)string
                                  offset:(NSInteger)offset
                                template:(NSString *)templ;
+ (NSString *)escapedTemplateForString:(NSString *)string;
@end

@interface NSString (NSRegularExpressionSearch)
/* With NSRegularExpressionSearch in the options, the replacement is a template. */
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target
                                        withString:(NSString *)replacement
                                           options:(NSStringCompareOptions)options
                                             range:(NSRange)searchRange;
@end

#endif
