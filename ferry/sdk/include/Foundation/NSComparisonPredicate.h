/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSComparisonPredicate (foundation/NSComparisonPredicate.m,
 * freemac 1.211, Ferry 0.37.0). Written for freemac from Apple's public
 * API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSCOMPARISONPREDICATE_H_
#define _FERRY_FOUNDATION_NSCOMPARISONPREDICATE_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSExpression.h>

typedef NS_OPTIONS(NSUInteger, NSComparisonPredicateOptions) {
    NSCaseInsensitivePredicateOption = 0x01,
    NSDiacriticInsensitivePredicateOption = 0x02,
    NSNormalizedPredicateOption = 0x04,
};

typedef NS_ENUM(NSUInteger, NSComparisonPredicateModifier) {
    NSDirectPredicateModifier = 0,
    NSAllPredicateModifier,
    NSAnyPredicateModifier,
};

typedef NS_ENUM(NSUInteger, NSPredicateOperatorType) {
    NSLessThanPredicateOperatorType = 0,
    NSLessThanOrEqualToPredicateOperatorType,
    NSGreaterThanPredicateOperatorType,
    NSGreaterThanOrEqualToPredicateOperatorType,
    NSEqualToPredicateOperatorType,
    NSNotEqualToPredicateOperatorType,
    NSMatchesPredicateOperatorType,
    NSLikePredicateOperatorType,
    NSBeginsWithPredicateOperatorType,
    NSEndsWithPredicateOperatorType,
    NSInPredicateOperatorType,
    NSCustomSelectorPredicateOperatorType,
    NSContainsPredicateOperatorType = 99,
    NSBetweenPredicateOperatorType,
};

@interface NSComparisonPredicate : NSPredicate
+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                                       rightExpression:(NSExpression *)rhs
                                              modifier:(NSComparisonPredicateModifier)modifier
                                                  type:(NSPredicateOperatorType)type
                                               options:(NSComparisonPredicateOptions)options;
+ (NSComparisonPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                                       rightExpression:(NSExpression *)rhs
                                        customSelector:(SEL)selector;
- (instancetype)initWithLeftExpression:(NSExpression *)lhs
                       rightExpression:(NSExpression *)rhs
                              modifier:(NSComparisonPredicateModifier)modifier
                                  type:(NSPredicateOperatorType)type
                               options:(NSComparisonPredicateOptions)options;
- (instancetype)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs customSelector:(SEL)selector;
@property (readonly) NSPredicateOperatorType predicateOperatorType;
@property (readonly) NSComparisonPredicateModifier comparisonPredicateModifier;
@property (readonly, retain) NSExpression *leftExpression;
@property (readonly, retain) NSExpression *rightExpression;
@property (readonly) SEL customSelector;
@property (readonly) NSComparisonPredicateOptions options;
@end

#endif
