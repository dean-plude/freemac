/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: collection views (NSCollectionView.m), written from
 * Apple's public documentation. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_NSCOLLECTIONVIEW_H_
#define _FERRY_APPKIT_NSCOLLECTIONVIEW_H_

@class NSCollectionView, NSCollectionViewLayout, NSCollectionViewLayoutAttributes, NSDraggingSession;

typedef NSString *NSCollectionViewSupplementaryElementKind;
typedef NSString *NSCollectionViewDecorationElementKind;
APPKIT_EXTERN NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionHeader;
APPKIT_EXTERN NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionFooter;
APPKIT_EXTERN NSCollectionViewSupplementaryElementKind const NSCollectionElementKindInterItemGapIndicator;
APPKIT_EXTERN NSCollectionViewSupplementaryElementKind const NSCollectionElementKindSectionCollapseButton;

typedef NS_OPTIONS(NSUInteger, NSCollectionViewScrollPosition) {
    NSCollectionViewScrollPositionNone = 0,
    NSCollectionViewScrollPositionTop = 1 << 0,
    NSCollectionViewScrollPositionCenteredVertically = 1 << 1,
    NSCollectionViewScrollPositionBottom = 1 << 2,
    NSCollectionViewScrollPositionNearestHorizontalEdge = 1 << 9,
    NSCollectionViewScrollPositionLeft = 1 << 3,
    NSCollectionViewScrollPositionCenteredHorizontally = 1 << 4,
    NSCollectionViewScrollPositionRight = 1 << 5,
    NSCollectionViewScrollPositionLeadingEdge = 1 << 6,
    NSCollectionViewScrollPositionTrailingEdge = 1 << 7,
    NSCollectionViewScrollPositionNearestVerticalEdge = 1 << 8,
};
typedef NS_ENUM(NSInteger, NSCollectionViewItemHighlightState) {
    NSCollectionViewItemHighlightNone = 0,
    NSCollectionViewItemHighlightForSelection = 1,
    NSCollectionViewItemHighlightForDeselection = 2,
    NSCollectionViewItemHighlightAsDropTarget = 3,
};
typedef NS_ENUM(NSInteger, NSCollectionViewDropOperation) {
    NSCollectionViewDropOn = 0, NSCollectionViewDropBefore = 1,
};
typedef NS_ENUM(NSInteger, NSCollectionElementCategory) {
    NSCollectionElementCategoryItem = 0, NSCollectionElementCategorySupplementaryView = 1,
    NSCollectionElementCategoryDecorationView = 2, NSCollectionElementCategoryInterItemGap = 3,
};
typedef NS_ENUM(NSInteger, NSCollectionViewScrollDirection) {
    NSCollectionViewScrollDirectionVertical = 0, NSCollectionViewScrollDirectionHorizontal = 1,
};

/* An object with an identifier, which views and items are made by. */
@protocol NSUserInterfaceItemIdentification <NSObject>
@property (copy) NSUserInterfaceItemIdentifier identifier;
@end

/* What items and supplementary views share: they are prepared for reuse
 * and told their layout attributes. */
@protocol NSCollectionViewElement <NSObject, NSUserInterfaceItemIdentification>
@optional
- (void)prepareForReuse;
- (void)applyLayoutAttributes:(NSCollectionViewLayoutAttributes *)layoutAttributes;
- (void)willTransitionFromLayout:(NSCollectionViewLayout *)oldLayout toLayout:(NSCollectionViewLayout *)newLayout;
- (void)didTransitionFromLayout:(NSCollectionViewLayout *)oldLayout toLayout:(NSCollectionViewLayout *)newLayout;
- (NSCollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(NSCollectionViewLayoutAttributes *)layoutAttributes;
@end
@protocol NSCollectionViewSectionHeaderView <NSCollectionViewElement>
@optional
@property (assign) IBOutlet NSButton *sectionCollapseButton;
@end

/* One item: a view controller whose view the collection view shows. */
@interface NSCollectionViewItem : NSViewController <NSCopying, NSCollectionViewElement>
@property (readonly, assign) NSCollectionView *collectionView;
@property (getter=isSelected) BOOL selected;
@property NSCollectionViewItemHighlightState highlightState;
@property (assign) IBOutlet NSImageView *imageView;
@property (assign) IBOutlet NSTextField *textField;
@property (readonly) NSArray *draggingImageComponents;
@property (copy) NSUserInterfaceItemIdentifier identifier;
- (void)prepareForReuse;
- (void)applyLayoutAttributes:(NSCollectionViewLayoutAttributes *)layoutAttributes;
@end

/* Where a layout puts one element. */
@interface NSCollectionViewLayoutAttributes : NSObject <NSCopying>
+ (instancetype)layoutAttributesForItemWithIndexPath:(NSIndexPath *)indexPath;
+ (instancetype)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)indexPath;
+ (instancetype)layoutAttributesForSupplementaryViewOfKind:(NSCollectionViewSupplementaryElementKind)kind
                                             withIndexPath:(NSIndexPath *)indexPath;
+ (instancetype)layoutAttributesForDecorationViewOfKind:(NSCollectionViewDecorationElementKind)kind
                                          withIndexPath:(NSIndexPath *)indexPath;
@property NSRect frame;
@property NSSize size;
@property CGFloat alpha;
@property NSInteger zIndex;
@property (getter=isHidden) BOOL hidden;
@property (retain) NSIndexPath *indexPath;
@property (readonly) NSCollectionElementCategory representedElementCategory;
@property (readonly) NSString *representedElementKind;
@end

/* One change in a batch of updates. */
typedef NS_ENUM(NSInteger, NSCollectionUpdateAction) {
    NSCollectionUpdateActionInsert = 0, NSCollectionUpdateActionDelete = 1, NSCollectionUpdateActionReload = 2,
    NSCollectionUpdateActionMove = 3, NSCollectionUpdateActionNone = 4,
};
@interface NSCollectionViewUpdateItem : NSObject
@property (readonly) NSIndexPath *indexPathBeforeUpdate, *indexPathAfterUpdate;
@property (readonly) NSCollectionUpdateAction updateAction;
@end

@interface NSCollectionViewLayoutInvalidationContext : NSObject
@property (readonly) BOOL invalidateEverything, invalidateDataSourceCounts;
@property NSPoint contentOffsetAdjustment;
@property NSSize contentSizeAdjustment;
- (void)invalidateItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
@property (readonly) NSSet<NSIndexPath *> *invalidatedItemIndexPaths;
@end

/* Works out where every element goes. Subclasses override prepareLayout,
 * collectionViewContentSize and the layoutAttributesFor... methods. */
@interface NSCollectionViewLayout : NSObject <NSCoding>
@property (readonly, assign) NSCollectionView *collectionView;
+ (Class)layoutAttributesClass;
+ (Class)invalidationContextClass;
- (void)invalidateLayout;
- (void)invalidateLayoutWithContext:(NSCollectionViewLayoutInvalidationContext *)context;
- (void)registerClass:(Class)viewClass forDecorationViewOfKind:(NSCollectionViewDecorationElementKind)elementKind;
- (void)registerNib:(NSNib *)nib forDecorationViewOfKind:(NSCollectionViewDecorationElementKind)elementKind;
- (void)prepareLayout;
@property (readonly) NSSize collectionViewContentSize;
- (NSArray<__kindof NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSCollectionViewSupplementaryElementKind)kind
                                                                     atIndexPath:(NSIndexPath *)indexPath;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSCollectionViewDecorationElementKind)kind
                                                                  atIndexPath:(NSIndexPath *)indexPath;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDropTargetAtPoint:(NSPoint)pointInCollectionView;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)indexPath;
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds;
- (NSPoint)targetContentOffsetForProposedContentOffset:(NSPoint)proposedContentOffset;
- (void)prepareForCollectionViewUpdates:(NSArray<NSCollectionViewUpdateItem *> *)updateItems;
- (void)finalizeCollectionViewUpdates;
@end

/* Lines of items, line after line, with headers and footers for the
 * sections; lines run across when scrolling vertically, down when
 * scrolling horizontally. */
@interface NSCollectionViewFlowLayout : NSCollectionViewLayout
@property CGFloat minimumLineSpacing, minimumInteritemSpacing;
@property NSSize itemSize, estimatedItemSize;
@property NSCollectionViewScrollDirection scrollDirection;
@property NSSize headerReferenceSize, footerReferenceSize;
@property NSEdgeInsets sectionInset;
@property BOOL sectionHeadersPinToVisibleBounds, sectionFootersPinToVisibleBounds;
- (BOOL)sectionAtIndexIsCollapsed:(NSUInteger)sectionIndex;
- (void)collapseSectionAtIndex:(NSUInteger)sectionIndex;
- (void)expandSectionAtIndex:(NSUInteger)sectionIndex;
@end

/* Items of one size in rows and columns, stretched to fill the width
 * between the minimum and maximum item sizes. */
@interface NSCollectionViewGridLayout : NSCollectionViewLayout
@property NSEdgeInsets margins;
@property CGFloat minimumInteritemSpacing, minimumLineSpacing;
@property NSUInteger maximumNumberOfRows, maximumNumberOfColumns;
@property NSSize minimumItemSize, maximumItemSize;
@property (copy) NSArray<NSColor *> *backgroundColors;
@end

@protocol NSCollectionViewDataSource <NSObject>
@required
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath;
@optional
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView;
- (NSView *)collectionView:(NSCollectionView *)collectionView
    viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
                          atIndexPath:(NSIndexPath *)indexPath;
@end

@protocol NSCollectionViewDelegate <NSObject>
@optional
- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView
           shouldChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
                        toHighlightState:(NSCollectionViewItemHighlightState)highlightState;
- (void)collectionView:(NSCollectionView *)collectionView didChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
      toHighlightState:(NSCollectionViewItemHighlightState)highlightState;
- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView
          shouldSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView
        shouldDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)collectionView:(NSCollectionView *)collectionView
    didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)collectionView:(NSCollectionView *)collectionView willDisplayItem:(NSCollectionViewItem *)item
    forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(NSCollectionView *)collectionView willDisplaySupplementaryView:(NSView *)view
        forElementKind:(NSCollectionViewSupplementaryElementKind)elementKind atIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(NSCollectionView *)collectionView didEndDisplayingItem:(NSCollectionViewItem *)item
    forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(NSCollectionView *)collectionView didEndDisplayingSupplementaryView:(NSView *)view
      forElementOfKind:(NSCollectionViewSupplementaryElementKind)elementKind atIndexPath:(NSIndexPath *)indexPath;
/* dragging (declared; Ferry doesn't drag items yet) */
- (BOOL)collectionView:(NSCollectionView *)collectionView canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
             withEvent:(NSEvent *)event;
- (BOOL)collectionView:(NSCollectionView *)collectionView canDragItemsAtIndexes:(NSIndexSet *)indexes
             withEvent:(NSEvent *)event;
- (BOOL)collectionView:(NSCollectionView *)collectionView writeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
          toPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)collectionView:(NSCollectionView *)collectionView writeItemsAtIndexes:(NSIndexSet *)indexes
          toPasteboard:(NSPasteboard *)pasteboard;
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView validateDrop:(id<NSDraggingInfo>)draggingInfo
                proposedIndexPath:(NSIndexPath **)proposedDropIndexPath
                    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation;
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView validateDrop:(id<NSDraggingInfo>)draggingInfo
                    proposedIndex:(NSInteger *)proposedDropIndex
                    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation;
- (BOOL)collectionView:(NSCollectionView *)collectionView acceptDrop:(id<NSDraggingInfo>)draggingInfo
             indexPath:(NSIndexPath *)indexPath dropOperation:(NSCollectionViewDropOperation)dropOperation;
- (BOOL)collectionView:(NSCollectionView *)collectionView acceptDrop:(id<NSDraggingInfo>)draggingInfo
                 index:(NSInteger)index dropOperation:(NSCollectionViewDropOperation)dropOperation;
- (void)collectionView:(NSCollectionView *)collectionView draggingSession:(NSDraggingSession *)session
          endedAtPoint:(NSPoint)screenPoint dragOperation:(NSDragOperation)operation;
@end

@protocol NSCollectionViewDelegateFlowLayout <NSCollectionViewDelegate>
@optional
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath;
- (NSEdgeInsets)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section;
- (CGFloat)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
    minimumLineSpacingForSectionAtIndex:(NSInteger)section;
- (CGFloat)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
    minimumInteritemSpacingForSectionAtIndex:(NSInteger)section;
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section;
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)collectionViewLayout
    referenceSizeForFooterInSection:(NSInteger)section;
@end

/* A scrollable grid of items. It works the modern way, with a data source
 * that has sections and items and a layout, or the older way, with an
 * array of content objects and an item prototype that is copied for each
 * one. */
@interface NSCollectionView : NSView
@property (assign) IBOutlet id<NSCollectionViewDataSource> dataSource;
@property (assign) IBOutlet id<NSCollectionViewDelegate> delegate;
@property (retain) NSCollectionViewLayout *collectionViewLayout;
@property (retain) NSView *backgroundView;
@property BOOL backgroundViewScrollsWithContent;
@property (copy) NSArray<NSColor *> *backgroundColors;
@property (getter=isSelectable) BOOL selectable;
@property BOOL allowsEmptySelection, allowsMultipleSelection;
@property (copy) NSSet<NSIndexPath *> *selectionIndexPaths;
@property (copy) NSIndexSet *selectionIndexes;
@property (readonly, getter=isFirstResponder) BOOL firstResponder;
/* sections and items */
@property (readonly) NSInteger numberOfSections;
- (NSInteger)numberOfItemsInSection:(NSInteger)section;
- (void)reloadData;
- (void)reloadSections:(NSIndexSet *)sections;
- (void)reloadItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)insertSections:(NSIndexSet *)sections;
- (void)deleteSections:(NSIndexSet *)sections;
- (void)moveSection:(NSInteger)section toSection:(NSInteger)newSection;
- (void)insertItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)deleteItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath;
- (void)performBatchUpdates:(void (^)(void))updates completionHandler:(void (^)(BOOL finished))completionHandler;
/* making items and supplementary views */
- (void)registerClass:(Class)itemClass forItemWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;
- (void)registerNib:(NSNib *)nib forItemWithIdentifier:(NSUserInterfaceItemIdentifier)identifier;
- (void)registerClass:(Class)viewClass forSupplementaryViewOfKind:(NSCollectionViewSupplementaryElementKind)kind
       withIdentifier:(NSUserInterfaceItemIdentifier)identifier;
- (void)registerNib:(NSNib *)nib forSupplementaryViewOfKind:(NSCollectionViewSupplementaryElementKind)kind
     withIdentifier:(NSUserInterfaceItemIdentifier)identifier;
- (__kindof NSCollectionViewItem *)makeItemWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
                                             forIndexPath:(NSIndexPath *)indexPath;
- (__kindof NSView *)makeSupplementaryViewOfKind:(NSCollectionViewSupplementaryElementKind)elementKind
                                  withIdentifier:(NSUserInterfaceItemIdentifier)identifier
                                    forIndexPath:(NSIndexPath *)indexPath;
/* finding items */
- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)indexPath;
- (NSArray<NSCollectionViewItem *> *)visibleItems;
- (NSSet<NSIndexPath *> *)indexPathsForVisibleItems;
- (NSIndexPath *)indexPathForItem:(NSCollectionViewItem *)item;
- (NSIndexPath *)indexPathForItemAtPoint:(NSPoint)point;
- (NSView<NSCollectionViewElement> *)supplementaryViewForElementKind:(NSCollectionViewSupplementaryElementKind)elementKind
                                                         atIndexPath:(NSIndexPath *)indexPath;
- (NSArray<NSView<NSCollectionViewElement> *> *)visibleSupplementaryViewsOfKind:(NSCollectionViewSupplementaryElementKind)kind;
- (NSSet<NSIndexPath *> *)indexPathsForVisibleSupplementaryElementsOfKind:(NSCollectionViewSupplementaryElementKind)kind;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath;
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
                                                                        atIndexPath:(NSIndexPath *)indexPath;
/* selection and scrolling */
- (void)selectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths scrollPosition:(NSCollectionViewScrollPosition)position;
- (void)deselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths;
- (IBAction)selectAll:(id)sender;
- (IBAction)deselectAll:(id)sender;
- (void)scrollToItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths scrollPosition:(NSCollectionViewScrollPosition)position;
- (IBAction)toggleSectionCollapse:(id)sender;
/* the older way: content objects and an item prototype */
@property (copy) NSArray *content;
@property (retain) NSCollectionViewItem *itemPrototype;
- (NSCollectionViewItem *)newItemForRepresentedObject:(id)object;
- (NSCollectionViewItem *)itemAtIndex:(NSUInteger)index;
- (NSRect)frameForItemAtIndex:(NSUInteger)index;
- (NSRect)frameForItemAtIndex:(NSUInteger)index withNumberOfItems:(NSUInteger)numberOfItems;
@property NSUInteger maxNumberOfRows, maxNumberOfColumns;
@property NSSize minItemSize, maxItemSize;
@end

@interface NSSet (NSCollectionViewAdditions)
+ (instancetype)setWithCollectionViewIndexPath:(NSIndexPath *)indexPath;
+ (instancetype)setWithCollectionViewIndexPaths:(NSArray<NSIndexPath *> *)indexPaths;
- (void)enumerateIndexPathsWithOptions:(NSEnumerationOptions)opts
                            usingBlock:(void (^)(NSIndexPath *indexPath, BOOL *stop))block;
@end

#endif
