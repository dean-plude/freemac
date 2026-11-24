/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSExpression (foundation/NSExpression.m, freemac 1.211,
 * Ferry 0.37.0). Written for freemac from Apple's public API documentation
 * and the "Predicate Format String Syntax" of the Predicate Programming
 * Guide; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSEXPRESSION_H_
#define _FERRY_FOUNDATION_NSEXPRESSION_H_
#include <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, NSExpressionType) {
    NSConstantValueExpressionType = 0,
    NSEvaluatedObjectExpressionType = 1,
    NSVariableExpressionType = 2,
    NSKeyPathExpressionType = 3,
    NSFunctionExpressionType = 4,
    NSUnionSetExpressionType = 5,
    NSIntersectSetExpressionType = 6,
    NSMinusSetExpressionType = 7,
    NSSubqueryExpressionType = 13,
    NSAggregateExpressionType = 14,
    NSAnyKeyExpressionType = 15,
    NSBlockExpressionType = 19,
    NSConditionalExpressionType = 20,
};

@interface NSExpression : NSObject <NSCopying, NSSecureCoding>
+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat, ...;
+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat argumentArray:(NSArray *)arguments;
+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat arguments:(va_list)argList;
+ (NSExpression *)expressionForConstantValue:(id)obj;
+ (NSExpression *)expressionForEvaluatedObject;
+ (NSExpression *)expressionForVariable:(NSString *)string;
+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath;
+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters;
+ (NSExpression *)expressionForFunction:(NSExpression *)target
                           selectorName:(NSString *)name
                              arguments:(NSArray *)parameters;
+ (NSExpression *)expressionForAggregate:(NSArray<NSExpression *> *)subexpressions;
+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForSubquery:(NSExpression *)expression
                  usingIteratorVariable:(NSString *)variable
                              predicate:(NSPredicate *)predicate;
+ (NSExpression *)expressionForAnyKey;
+ (NSExpression *)expressionForBlock:(id (^)(id evaluatedObject, NSArray<NSExpression *> *expressions,
                                             NSMutableDictionary *context))block
                           arguments:(NSArray<NSExpression *> *)arguments;
+ (NSExpression *)expressionForConditional:(NSPredicate *)predicate
                            trueExpression:(NSExpression *)trueExpression
                           falseExpression:(NSExpression *)falseExpression;
- (instancetype)initWithExpressionType:(NSExpressionType)type;

@property (readonly) NSExpressionType expressionType;
@property (readonly, retain) id constantValue;
@property (readonly, copy) NSString *keyPath;
@property (readonly, copy) NSString *function;
@property (readonly, copy) NSString *variable;
@property (readonly, copy) NSExpression *operand;
@property (readonly, copy) NSArray<NSExpression *> *arguments;
@property (readonly, retain) id collection;
@property (readonly, copy) NSPredicate *predicate;
@property (readonly, copy) NSExpression *leftExpression;
@property (readonly, copy) NSExpression *rightExpression;
@property (readonly, copy) NSExpression *trueExpression;
@property (readonly, copy) NSExpression *falseExpression;
@property (readonly, copy) id (^expressionBlock)(id, NSArray<NSExpression *> *, NSMutableDictionary *);

- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context;
- (void)allowEvaluation;
@end

#endif
