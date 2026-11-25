/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSPredicateEditor and its row templates (freemac 1.232, Ferry
 * 0.56.0), written from Apple's public documentation; not Apple's header.
 * A rule editor that is its own delegate: each row is shown and read by a
 * copy of one of its row templates, the one that matches the row's
 * predicate best. A template compares a left expression, chosen from a
 * pop-up, with a right one, typed in a field or chosen from a pop-up, by
 * one of its operators; a compound template joins its rows with All, Any
 * or None. Implemented in appkit/NSPredicateEditor.m. Included from
 * AppKit.h. */
#import <AppKit/NSRuleEditor.h>

@class NSPredicateEditorRowTemplate;

@interface NSPredicateEditor : NSRuleEditor
@property (copy) NSArray<NSPredicateEditorRowTemplate *> *rowTemplates;
/* objectValue is the predicate: setting it makes the rows that show it */
@end

@interface NSPredicateEditorRowTemplate : NSObject <NSCoding, NSCopying>
/* How well this template shows a predicate: 0 not at all, up to 1. */
- (double)matchForPredicate:(NSPredicate *)predicate;
/* What the row shows, in order: pop-ups, fields and labels. */
@property (readonly, copy) NSArray<NSView *> *templateViews;
/* Shows predicate in the template's views. */
- (void)setPredicate:(NSPredicate *)predicate;
/* The predicate the views show now; a compound one joins subpredicates. */
- (NSPredicate *)predicateWithSubpredicates:(NSArray<NSPredicate *> *)subpredicates;
/* The rows under a compound one: its subpredicates; nil for a simple one. */
- (NSArray<NSPredicate *> *)displayableSubpredicatesOfPredicate:(NSPredicate *)predicate;

- (instancetype)initWithLeftExpressions:(NSArray<NSExpression *> *)leftExpressions
                       rightExpressions:(NSArray<NSExpression *> *)rightExpressions
                               modifier:(NSComparisonPredicateModifier)modifier
                              operators:(NSArray<NSNumber *> *)operators
                                options:(NSUInteger)options;
/* attributeType is one of Core Data's NSAttributeType values: a string, a
 * number, a date or a Boolean is typed (or ticked) in the row. */
- (instancetype)initWithLeftExpressions:(NSArray<NSExpression *> *)leftExpressions
           rightExpressionAttributeType:(NSUInteger)attributeType
                               modifier:(NSComparisonPredicateModifier)modifier
                              operators:(NSArray<NSNumber *> *)operators
                                options:(NSUInteger)options;
- (instancetype)initWithCompoundTypes:(NSArray<NSNumber *> *)compoundTypes;

@property (readonly) NSArray<NSExpression *> *leftExpressions;
@property (readonly) NSArray<NSExpression *> *rightExpressions;
@property (readonly) NSUInteger rightExpressionAttributeType;
@property (readonly) NSComparisonPredicateModifier modifier;
@property (readonly) NSArray<NSNumber *> *operators;
@property (readonly) NSUInteger options;
@property (readonly) NSArray<NSNumber *> *compoundTypes;
@end
