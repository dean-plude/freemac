/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSGridView (freemac 1.225, Ferry 0.49.0), written for Ferry
 * from Apple's public API documentation (appkit/NSGridView.m). A grid lays
 * its cells' views out in rows and columns by frames, not constraints: a
 * column is as wide as its widest view (or its width), a row as tall as
 * its tallest (or its height), the last column and row take the room the
 * grid has left over, and each view is placed in its cell by its x and y
 * placement (the cell's, else its column's or row's, else the grid's).
 * Hidden rows and columns take no room. Baseline row alignment is taken
 * as none, and custom placement constraints aren't applied. */
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSGridCellPlacement) {
    NSGridCellPlacementInherited = 0,
    NSGridCellPlacementNone,
    NSGridCellPlacementLeading,
    NSGridCellPlacementTop = NSGridCellPlacementLeading,
    NSGridCellPlacementTrailing,
    NSGridCellPlacementBottom = NSGridCellPlacementTrailing,
    NSGridCellPlacementCenter,
    NSGridCellPlacementFill,
};
typedef NS_ENUM(NSInteger, NSGridRowAlignment) {
    NSGridRowAlignmentInherited = 0,
    NSGridRowAlignmentNone,
    NSGridRowAlignmentFirstBaseline,
    NSGridRowAlignmentLastBaseline,
};
/* a row's height or a column's width that is its content's */
APPKIT_EXTERN const CGFloat NSGridViewSizeForContent;

@class NSGridRow, NSGridColumn, NSGridCell;

@interface NSGridView : NSView
+ (instancetype FERRY_SWIFT_NONNULL)gridViewWithNumberOfColumns:(NSInteger)columnCount rows:(NSInteger)rowCount;
/* rows of views; a row shorter than the longest gets empty cells, and an
 * [NSGridCell emptyContentView] leaves a cell empty */
+ (instancetype FERRY_SWIFT_NONNULL)gridViewWithViews:(NSArray<NSArray<NSView *> *> *)rows;
@property (readonly) NSInteger numberOfRows, numberOfColumns;
- (NSGridRow *)rowAtIndex:(NSInteger)index;
- (NSInteger)indexOfRow:(NSGridRow *)row;
- (NSGridColumn *)columnAtIndex:(NSInteger)index;
- (NSInteger)indexOfColumn:(NSGridColumn *)column;
- (NSGridCell *)cellAtColumnIndex:(NSInteger)columnIndex rowIndex:(NSInteger)rowIndex;
/* the cell whose content view is the view or holds it, or nil */
- (nullable NSGridCell *)cellForView:(NSView *)view;
- (NSGridRow *)addRowWithViews:(NSArray<NSView *> *)views;
- (NSGridRow *)insertRowAtIndex:(NSInteger)index withViews:(NSArray<NSView *> *)views;
- (void)moveRowAtIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)removeRowAtIndex:(NSInteger)index;
- (NSGridColumn *)addColumnWithViews:(NSArray<NSView *> *)views;
- (NSGridColumn *)insertColumnAtIndex:(NSInteger)index withViews:(NSArray<NSView *> *)views;
- (void)moveColumnAtIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;
- (void)removeColumnAtIndex:(NSInteger)index;
@property NSGridCellPlacement xPlacement, yPlacement;
@property NSGridRowAlignment rowAlignment;
@property CGFloat rowSpacing, columnSpacing;
/* one cell, the range's first, then holds the content of them all */
- (void)mergeCellsInHorizontalRange:(NSRange)hRange verticalRange:(NSRange)vRange;
@end

@interface NSGridRow : NSObject <NSCoding>
@property (readonly, weak, nullable) NSGridView *gridView;
@property (readonly) NSInteger numberOfCells;
- (NSGridCell *)cellAtIndex:(NSInteger)index;
@property NSGridCellPlacement yPlacement;
@property NSGridRowAlignment rowAlignment;
@property CGFloat height, topPadding, bottomPadding;
@property (getter=isHidden) BOOL hidden;
- (void)mergeCellsInRange:(NSRange)range;
@end

@interface NSGridColumn : NSObject <NSCoding>
@property (readonly, weak, nullable) NSGridView *gridView;
@property (readonly) NSInteger numberOfCells;
- (NSGridCell *)cellAtIndex:(NSInteger)index;
@property NSGridCellPlacement xPlacement;
@property CGFloat width, leadingPadding, trailingPadding;
@property (getter=isHidden) BOOL hidden;
- (void)mergeCellsInRange:(NSRange)range;
@end

@interface NSGridCell : NSObject <NSCoding>
@property (strong, nullable) NSView *contentView;
/* the view that marks a cell to be left empty */
@property (class, readonly, strong) NSView * FERRY_SWIFT_NONNULL emptyContentView;
@property (readonly, weak, nullable) NSGridRow *row;
@property (readonly, weak, nullable) NSGridColumn *column;
@property NSGridCellPlacement xPlacement, yPlacement;
@property NSGridRowAlignment rowAlignment;
@property (copy) NSArray<NSLayoutConstraint *> *customPlacementConstraints;
@end

NS_ASSUME_NONNULL_END
