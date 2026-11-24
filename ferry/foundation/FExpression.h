/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: what NSPredicate.m, NSComparisonPredicate.m,
 * NSExpression.m and NSPredicateParser.m share (freemac 1.NEXT, Ferry
 * 0.NEXT). Our own code. */
#ifndef FERRY_FOUNDATION_EXPRESSION_H
#define FERRY_FOUNDATION_EXPRESSION_H
#import "FInternal.h"

@interface NSPredicate (FPrivate)
/* Evaluation with variables (nil when none were given). */
- (BOOL)_evaluate:(id)object vars:(NSDictionary *)vars;
/* The predicate with its variables replaced; a variable that vars maps to
 * FKeepVariable() stays a variable (a subquery's iterator). */
- (NSPredicate *)_substitute:(NSDictionary *)vars;
/* The key paths the predicate reads from the object (for AppKit's array controller). */
- (void)_ferryAddKeyPathsTo:(NSMutableSet *)set;
/* The predicate's tree, for Core Data's SQLite store to read: nil for a
 * predicate it can't describe. */
- (id)_ferryStructure;
@end

@interface NSExpression (FPrivate)
/* A key path read from another expression's value ($x.name, SUBQUERY(...).@count). */
+ (NSExpression *)_expressionForKeyPath:(NSString *)keyPath operand:(NSExpression *)operand;
- (NSExpression *)_substitute:(NSDictionary *)vars;
- (void)_addKeyPathsTo:(NSMutableSet *)set;
/* {kind: constant, keypath, self, variable, aggregate or other, value} */
- (id)_ferryStructure;
/* How the expression is written in a format string. */
- (NSString *)_format;
@end

/* The marker for a variable that substitution leaves alone. */
id FKeepVariable(void);
/* A constant written as a format string writes it. */
NSString *FFormatConstant(id value);

/* NSPredicateParser.m: a predicate or an expression from a format string,
 * its arguments from a va_list or an array. */
NSPredicate *FParsePredicate(NSString *format, va_list *ap, NSArray *args);
NSExpression *FParseExpression(NSString *format, va_list *ap, NSArray *args);

/* NSComparisonPredicate.m: NONE, which is NOT(ANY ...) written as NONE. */
NSPredicate *FNonePredicate(NSPredicate *anyComparison);

#endif
