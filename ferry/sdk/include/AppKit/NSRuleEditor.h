/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSRuleEditor (freemac 1.222, Ferry 0.46.0), written from
 * Apple's public documentation; not Apple's header. A list of rows, each a
 * chain of criteria its delegate gives, shown as pop-up menus, labels and
 * the delegate's own views, with buttons to add and remove rows; compound
 * rows hold rows of their own. The rows can be bound ("rows") to an array
 * of the model's. Included from AppKit.h. NSPredicateEditor, which gives
 * its own criteria, is in NSPredicateEditor.h. */
#import <Foundation/Foundation.h>

@class NSRuleEditor;

typedef NSString *NSRuleEditorPredicatePartKey;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateLeftExpression;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateRightExpression;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateComparisonModifier;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateOptions;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateOperatorType;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateCustomSelector;
APPKIT_EXTERN NSRuleEditorPredicatePartKey const NSRuleEditorPredicateCompoundType;
APPKIT_EXTERN NSNotificationName const NSRuleEditorRowsDidChangeNotification;

typedef NS_ENUM(NSUInteger, NSRuleEditorNestingMode) {
    NSRuleEditorNestingModeSingle = 0,   /* one row, no more */
    NSRuleEditorNestingModeList = 1,     /* simple rows, one after another */
    NSRuleEditorNestingModeCompound = 2, /* compound rows holding others */
    NSRuleEditorNestingModeSimple = 3,   /* one compound row holding simple ones */
};
typedef NS_ENUM(NSUInteger, NSRuleEditorRowType) { NSRuleEditorRowTypeSimple = 0, NSRuleEditorRowTypeCompound = 1 };

@protocol NSRuleEditorDelegate <NSObject>
@required
- (NSInteger)ruleEditor:(NSRuleEditor *)editor numberOfChildrenForCriterion:(id)criterion
            withRowType:(NSRuleEditorRowType)rowType;
- (id)ruleEditor:(NSRuleEditor *)editor child:(NSInteger)index forCriterion:(id)criterion
     withRowType:(NSRuleEditorRowType)rowType;
- (id)ruleEditor:(NSRuleEditor *)editor displayValueForCriterion:(id)criterion inRow:(NSInteger)row;
@optional
- (NSDictionary<NSRuleEditorPredicatePartKey, id> *)ruleEditor:(NSRuleEditor *)editor
                                    predicatePartsForCriterion:(id)criterion
                                              withDisplayValue:(id)value
                                                         inRow:(NSInteger)row;
- (void)ruleEditorRowsDidChange:(NSNotification *)notification;
@end

@interface NSRuleEditor : NSControl
@property (assign) id<NSRuleEditorDelegate> delegate;
@property (copy) NSString *formattingStringsFilename;
@property (copy) NSDictionary<NSString *, NSString *> *formattingDictionary;
- (void)reloadCriteria;
@property NSRuleEditorNestingMode nestingMode;
@property CGFloat rowHeight;
@property (getter=isEditable) BOOL editable;
@property BOOL canRemoveAllRows;
@property (readonly, retain) NSPredicate *predicate;
- (void)reloadPredicate;
- (NSPredicate *)predicateForRow:(NSInteger)row;
@property (readonly) NSInteger numberOfRows;
- (NSIndexSet *)subrowIndexesForRow:(NSInteger)rowIndex;
- (NSArray *)criteriaForRow:(NSInteger)row;
- (NSArray *)displayValuesForRow:(NSInteger)row;
- (NSInteger)rowForDisplayValue:(id)displayValue;
- (NSRuleEditorRowType)rowTypeForRow:(NSInteger)rowIndex;
- (NSInteger)parentRowForRow:(NSInteger)rowIndex;
- (void)addRow:(id)sender;
- (void)insertRowAtIndex:(NSInteger)rowIndex withType:(NSRuleEditorRowType)rowType asSubrowOfRow:(NSInteger)parentRow
                 animate:(BOOL)shouldAnimate;
- (void)setCriteria:(NSArray *)criteria andDisplayValues:(NSArray *)values forRowAtIndex:(NSInteger)rowIndex;
- (void)removeRowAtIndex:(NSInteger)rowIndex;
- (void)removeRowsAtIndexes:(NSIndexSet *)rowIndexes includeSubrows:(BOOL)includeSubrows;
@property (readonly, copy) NSIndexSet *selectedRowIndexes;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
/* how the rows are kept: objects of rowClass, read and written with these key paths */
@property (assign) Class rowClass;
@property (copy) NSString *rowTypeKeyPath;
@property (copy) NSString *subrowsKeyPath;
@property (copy) NSString *criteriaKeyPath;
@property (copy) NSString *displayValuesKeyPath;
@end
